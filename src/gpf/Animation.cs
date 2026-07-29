using Godot;
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Gpf
{
    // Порт клипа GameplayFootball (src/utils/animation.cpp, Apache 2.0).
    // 14 треков: строка 0 "player" — позиция корня, строки 1..13 — джойнты-кватернионы
    // (абсолютная локальная ориентация в пространстве родителя). Кадр = 10 мс, ключи разрежены.
    // Всё — в «их» осях: Z-вверх, вперёд −Y; порядок компонент кватерниона в файле == Godot (x,y,z,w).
    public partial class Animation : RefCounted
    {
        public struct KeyFrame
        {
            public Quaternion Orientation;
            public Vector3 Position;
        }

        private sealed class NodeAnimation
        {
            public string NodeName = "";
            public SortedDictionary<int, KeyFrame> Keys = new();
        }

        public static readonly string[] TrackOrder =
        {
            "player", "body", "middle", "neck",
            "left_shoulder", "left_elbow", "right_shoulder", "right_elbow",
            "left_thigh", "left_knee", "left_ankle",
            "right_thigh", "right_knee", "right_ankle",
        };

        private readonly List<NodeAnimation> _tracks = new();
        private readonly SortedDictionary<int, Vector3> _touches = new();
        private readonly Dictionary<string, string> _variables = new();
        private int _frameCount;
        private string _name = "";

        // e_Foot (animation.hpp:41-44): 0 left / 1 right. Дефолт right (animation.cpp:29):
        // «все клипы начинают движение с правой ноги, если не отзеркалены».
        public const int FootLeft = 0;
        public const int FootRight = 1;
        private int _currentFoot = FootRight;

        public string GetName() => _name;
        public int GetFrameCount() => _frameCount;
        public int GetEffectiveFrameCount() => GetFrameCount() - 1; // animation.hpp:83
        public int GetTrackCount() => _tracks.Count;
        public string GetTrackName(int i) => _tracks[i].NodeName;

        // Касания мяча из строки extension,football — кадр контакта + позиция мяча в осях клипа.
        public int GetTouchCount() => _touches.Count;

        public int GetTouchFrame(int index)
        {
            int i = 0;
            foreach (var kv in _touches) { if (i == index) return kv.Key; i++; }
            return -1;
        }

        public Vector3 GetTouchPosition(int index)
        {
            int i = 0;
            foreach (var kv in _touches) { if (i == index) return kv.Value; i++; }
            return Vector3.Zero;
        }

        public string GetAnimType() => GetVariable("type");

        public string GetVariable(string tag)
            => _variables.TryGetValue(tag, out var v) ? v : "";

        public Godot.Collections.Array GetKeyFrames(string nodeName)
        {
            var result = new Godot.Collections.Array();
            var track = FindTrack(nodeName);
            if (track != null)
                foreach (int frame in track.Keys.Keys) result.Add(frame);
            return result;
        }

        public Quaternion GetKeyRotation(string nodeName, int frame)
        {
            var track = FindTrack(nodeName);
            if (track == null)
            {
                GD.PushError($"Gpf.Animation: нет трека {nodeName}");
                return Quaternion.Identity;
            }
            return track.Keys[frame].Orientation;
        }

        public Vector3 GetKeyPosition(string nodeName, int frame)
        {
            var track = FindTrack(nodeName);
            if (track == null)
            {
                GD.PushError($"Gpf.Animation: нет трека {nodeName}");
                return Vector3.Zero;
            }
            return track.Keys[frame].Position;
        }

        private NodeAnimation? FindTrack(string nodeName)
            => _tracks.Find(t => t.NodeName == nodeName);

        // Порт GetInterpolatedValues (animation.cpp:179-295).
        private void GetInterpolatedValues(SortedDictionary<int, KeyFrame> keys, int frame,
                                           out Quaternion orientation, out Vector3 position)
        {
            orientation = Quaternion.Identity;
            position = Vector3.Zero;
            if (keys.Count == 0) return;

            if (frame > 0 && frame < _frameCount)
            {
                // последний ключ < frame и первый ключ >= frame (animation.cpp:186-206)
                bool hasBefore = false, hasAfter = false;
                int beforeFrame = 0, afterFrame = 0;
                KeyFrame before = default, after = default;
                foreach (var kv in keys)
                {
                    if (kv.Key >= frame) { after = kv.Value; afterFrame = kv.Key; hasAfter = true; break; }
                    before = kv.Value; beforeFrame = kv.Key; hasBefore = true;
                }

                if (hasBefore && hasAfter)
                {
                    float bias = (frame - beforeFrame) / (float)(afterFrame - beforeFrame);
                    orientation = QuatUtil.Slerp(before.Orientation, bias, after.Orientation);
                    position = before.Position * (1f - bias) + after.Position * bias;
                }
                else if (hasAfter) // все ключи позже текущего кадра
                {
                    orientation = after.Orientation;
                    position = after.Position;
                }
                else // ключи трека кончились раньше frameCount → держим последний
                {
                    orientation = before.Orientation;
                    position = before.Position;
                }
            }
            else if (frame >= _frameCount)
            {
                // экстраполяция за концом (animation.cpp:247-282): slerp с bias > 1
                KeyFrame last = default, secondLast = default;
                int lastFrame = 0, secondLastFrame = 0, seen = 0;
                foreach (var kv in keys)
                {
                    secondLast = last; secondLastFrame = lastFrame;
                    last = kv.Value; lastFrame = kv.Key; seen++;
                }
                if (seen == 1) { orientation = last.Orientation; position = last.Position; return; }
                float dist1 = lastFrame - secondLastFrame;
                float dist2 = frame - lastFrame;
                float bias = 1f + (1f / dist1) * dist2;
                orientation = QuatUtil.Slerp(secondLast.Orientation, bias, last.Orientation);
                position = secondLast.Position * (1f - bias) + last.Position * bias;
            }
            else // frame <= 0 → первый ключ (animation.cpp:284-292)
            {
                foreach (var kv in keys)
                {
                    orientation = kv.Value.Orientation;
                    position = kv.Value.Position;
                    break;
                }
            }
        }

        // Сентинел timeOffset_ms == -1 (animation.cpp:391-392): «смещение неизвестно» →
        // серединный bias 0.5, а не клампованный ноль. Так рендер-путь зовёт Apply
        // (humanoidbase.cpp:779), поэтому поведение обязано отличаться от timeOffset 0.
        // Намеренно расширено до "< 0" (оригинал сравнивает строго != -1, animation.cpp:392): параметр у нас float, любое отрицательное значение трактуем как сентинел.
        private static float SampleBias(float timeOffsetMs)
            => timeOffsetMs < 0f ? 0.5f : Mathf.Clamp(timeOffsetMs / 10f, 0f, 1f);

        // Субкадровый семпл по схеме Animation::Apply (animation.cpp:389-405).
        public Quaternion SampleRotation(string nodeName, int frame, float timeOffsetMs)
        {
            var track = FindTrack(nodeName);
            if (track == null)
            {
                GD.PushError($"Gpf.Animation: нет трека {nodeName}");
                return Quaternion.Identity;
            }
            float bias = SampleBias(timeOffsetMs);
            GetInterpolatedValues(track.Keys, frame, out var qPre, out _);
            GetInterpolatedValues(track.Keys, frame + 1, out var qPost, out _);
            qPre = QuatUtil.SameNeighborhood(qPre, qPost);
            return QuatUtil.Lerp(qPre, bias, qPost).Normalized();
        }

        // Ориентационная половина Animation::GetKeyFrame (animation.hpp:85 → animation.cpp:111-120):
        // интерполированное значение НА кадре, без субкадрового смещения. Bool-результат оригинала
        // («есть ли ровно такой ключ») не нужен ни одному вызову фазы 3 — не переносим.
        public Quaternion GetInterpolatedRotation(string nodeName, int frame)
        {
            var track = FindTrack(nodeName);
            if (track == null)
            {
                GD.PushError($"Gpf.Animation: нет трека {nodeName}");
                return Quaternion.Identity;
            }
            GetInterpolatedValues(track.Keys, frame, out var q, out _);
            return q;
        }

        // Флаги getOrientation/getPosition оригинала (animation.hpp:88) опущены: у player-трека
        // в .anim нет ориентации (она identity), поэтому отдаём только позицию.
        public Vector3 SampleRootPosition(int frame, float timeOffsetMs)
        {
            var track = FindTrack("player");
            if (track == null)
            {
                GD.PushError("Gpf.Animation: нет трека player");
                return Vector3.Zero;
            }
            float bias = SampleBias(timeOffsetMs);
            GetInterpolatedValues(track.Keys, frame, out _, out var pPre);
            GetInterpolatedValues(track.Keys, frame + 1, out _, out var pPost);
            return pPre * (1f - bias) + pPost * bias;
        }

        public bool LoadFromFile(string resPath)
        {
            _tracks.Clear();
            _touches.Clear();
            _variables.Clear();
            _frameCount = 0;
            // Оригинальный Animation::Load (animation.cpp:1109) сброса кэша не делает — он полагается
            // на LoadData→SetKeyFrame и на то, что Load зовут только по свежему объекту (кэш грязный
            // с конструктора, animation.cpp:31). У нас LoadFromFile можно позвать повторно, а у
            // пустого/битого файла SetKeyFrame не вызовется вовсе — сбрасываем явно.
            DirtyCache();

            using var f = FileAccess.Open(resPath, FileAccess.ModeFlags.Read);
            if (f == null)
            {
                GD.PushError($"Gpf.Animation: не открыть {resPath}");
                return false;
            }
            _name = resPath;

            // Трёхфазный разбор как в Animation::Load (animation.cpp:1109):
            // CSV-строки → extension-строки → XML-хвост.
            var csv = new List<string[]>();
            var lines = new List<string>();
            while (!f.EofReached())
            {
                string line = f.GetLine();
                if (line.StripEdges().Length > 0) lines.Add(line);
            }

            int cursor = 0;
            for (; cursor < lines.Count; cursor++)
            {
                string stripped = lines[cursor].StripEdges();
                if (stripped.StartsWith("extension") || stripped.StartsWith("<")) break;
                csv.Add(lines[cursor].Split(','));
            }

            try
            {
                LoadData(csv);

                for (; cursor < lines.Count; cursor++)
                {
                    string stripped = lines[cursor].StripEdges();
                    if (!stripped.StartsWith("extension")) break;
                    var tokens = stripped.Split(',');
                    if (tokens.Length > 1 && tokens[1] == "football") LoadFootballExtension(tokens);
                }

                var xml = new System.Text.StringBuilder();
                for (; cursor < lines.Count; cursor++) xml.AppendLine(lines[cursor]);
                LoadXmlTail(xml.ToString());
            }
            catch (Exception e) when (e is FormatException or IndexOutOfRangeException
                                        or OverflowException or System.Xml.XmlException)
            {
                GD.PushError($"Gpf.Animation: битый файл {resPath}: {e.Message}");
                return false;
            }

            NormalizeDirectionTags();     // animation.cpp:1157-1179 (шов 3)
            if (_tracks.Count >= 2) ConvertToStartFacingForwardIfIdle(); // animation.cpp:1196 (шов 2)

            return _tracks.Count > 0;
        }

        // Порт Animation::LoadData (animation.cpp:1076-1107).
        private void LoadData(List<string[]> file)
        {
            for (int line = 0; line < file.Count; line++)
            {
                var tokens = file[line];
                int key = 1;
                while (key < tokens.Length)
                {
                    int frame = int.Parse(tokens[key], CultureInfo.InvariantCulture);
                    var orientation = Quaternion.Identity;
                    var position = Vector3.Zero;
                    if (line != 0)
                    {
                        // джойнты: только ориентация (frame,qx,qy,qz,qw)
                        orientation = new Quaternion(
                            ParseF(tokens[key + 1]), ParseF(tokens[key + 2]),
                            ParseF(tokens[key + 3]), ParseF(tokens[key + 4]));
                        key += 5;
                    }
                    else
                    {
                        // player: только позиция (frame,x,y,z)
                        position = new Vector3(
                            ParseF(tokens[key + 1]), ParseF(tokens[key + 2]), ParseF(tokens[key + 3]));
                        key += 4;
                    }
                    SetKeyFrame(tokens[0], frame, orientation, position);
                }
            }
        }

        // Порт FootballAnimationExtension::Load (footballanimationextension.cpp:109-125).
        private void LoadFootballExtension(string[] tokens)
        {
            // Оригинал чистит карту касаний на каждый вызов Load (footballanimationextension.cpp:110):
            // при нескольких extension-строках в файле остаётся только последняя. Общий сброс в
            // LoadFromFile этого не покрывает (он выполняется один раз до цикла по extension-строкам).
            _touches.Clear();
            int key = 2;
            while (key + 3 < tokens.Length)
            {
                int frame = int.Parse(tokens[key], CultureInfo.InvariantCulture);
                _touches[frame] = new Vector3(
                    ParseF(tokens[key + 1]), ParseF(tokens[key + 2]), ParseF(tokens[key + 3]));
                key += 4;
            }
        }

        // XML-хвост: плоские теги верхнего уровня → словарь тег → тримленный текст.
        // Нормализация тегов bumpdirection/balldirection/incomingballdirection (animation.cpp:1157-1179)
        // выполняется отдельно в NormalizeDirectionTags() уже после разбора всего файла — как в
        // Animation::Load, где нормализация идёт перед созданием variableCache.
        private void LoadXmlTail(string xml)
        {
            if (xml.Trim().Length == 0) return;
            var doc = new System.Xml.XmlDocument();
            doc.LoadXml("<root>" + xml + "</root>");
            foreach (System.Xml.XmlNode child in doc.DocumentElement!.ChildNodes)
                if (child.NodeType == System.Xml.XmlNodeType.Element)
                    _variables[child.Name] = child.InnerText.Trim();
        }

        // Порт Animation::SetKeyFrame (animation.cpp:122-158). Ключ на существующем кадре —
        // замена, не дубликат (SortedDictionary по индексатору делает ровно это).
        public void SetKeyFrame(string nodeName, int frame, Quaternion orientation, Vector3 position)
        {
            var track = FindTrack(nodeName);
            if (track == null)
            {
                track = new NodeAnimation { NodeName = nodeName };
                _tracks.Add(track);
            }
            track.Keys[frame] = new KeyFrame { Orientation = orientation, Position = position };
            if (frame >= _frameCount) _frameCount = frame + 1; // animation.cpp:123
            DirtyCache();
        }

        public int GetCurrentFootId() => _currentFoot;
        public void SetCurrentFootId(int id) => _currentFoot = id;

        public void SetName(string name) => _name = name;

        // Порт SetVariable (animation.cpp:1340-1356): у нас один словарь вместо XMLTree+variableCache.
        public void SetVariable(string name, string value) => _variables[name] = value;

        // ───────────────────────── кэш дескрипторов клипа ─────────────────────────
        // animation.hpp:146-169 — 12 mutable-полей + 12 dirty-флагов, ленивый пересчёт.
        private bool _cTranslationDirty = true;             private Vector3 _cTranslation;
        private bool _cIncomingMovementDirty = true;        private Vector3 _cIncomingMovement;
        private bool _cIncomingVelocityDirty = true;        private float _cIncomingVelocity;
        private bool _cOutgoingDirectionDirty = true;       private Vector3 _cOutgoingDirection;
        private bool _cOutgoingMovementDirty = true;        private Vector3 _cOutgoingMovement;
        private bool _cRangedOutgoingMovementDirty = true;  private Vector3 _cRangedOutgoingMovement;
        private bool _cOutgoingVelocityDirty = true;        private float _cOutgoingVelocity;
        private bool _cAngleDirty = true;                   private float _cAngle;
        private bool _cIncomingBodyAngleDirty = true;       private float _cIncomingBodyAngle;
        private bool _cOutgoingBodyAngleDirty = true;       private float _cOutgoingBodyAngle;
        private bool _cIncomingBodyDirectionDirty = true;   private Vector3 _cIncomingBodyDirection;
        private bool _cOutgoingBodyDirectionDirty = true;   private Vector3 _cOutgoingBodyDirection;

        // Порт Animation::DirtyCache (animation.cpp:92-105) — взводит все 12 cache_*_dirty флагов.
        public void DirtyCache()
        {
            _cTranslationDirty = true;
            _cIncomingMovementDirty = true;
            _cIncomingVelocityDirty = true;
            _cOutgoingDirectionDirty = true;
            _cOutgoingMovementDirty = true;
            _cRangedOutgoingMovementDirty = true;
            _cOutgoingVelocityDirty = true;
            _cAngleDirty = true;
            _cIncomingBodyAngleDirty = true;
            _cOutgoingBodyAngleDirty = true;
            _cIncomingBodyDirectionDirty = true;
            _cOutgoingBodyDirectionDirty = true;
        }

        // Порядок треков фиксирован (TrackOrder): 0 — "player" (корень), 1 — "body".
        // Оригинал адресует их так же — nodeAnimations.at(0) / at(1).
        private const int RootTrack = 0;
        private const int BodyTrack = 1;

        private int RootKeyCount => _tracks.Count > RootTrack ? _tracks[RootTrack].Keys.Count : 0;
        private int BodyKeyCount => _tracks.Count > BodyTrack ? _tracks[BodyTrack].Keys.Count : 0;

        // Аналог итераторной арифметики оригинала над std::map root-трека:
        //   position 0/1 при fromEnd=false → begin() / ++begin()      (первый / второй ключ)
        //   position 0/1 при fromEnd=true  → --end() / --(--end())    (последний / предпоследний)
        // Возвращает (номер кадра, ключ). Вызывающая сторона обязана сама проверить RootKeyCount:
        // у оригинала выход за границы — UB, у нас безопасный default.
        private (int frame, KeyFrame key) RootKeyAt(int position, bool fromEnd)
        {
            var keys = _tracks[RootTrack].Keys;
            int i = 0, target = fromEnd ? keys.Count - 1 - position : position;
            foreach (var kv in keys)
            {
                if (i == target) return (kv.Key, kv.Value);
                i++;
            }
            return (0, default);
        }

        // (nodeAnimations.at(1)->animation.begin())->second — первый ключ body-трека.
        // Оба Body-хелпера предполагают, что трек есть, и при его отсутствии бросят исключение
        // индексатора (аналог out_of_range от `.at(1)`). Практически это достижимо ровно в одном
        // месте — ветка ±180° в GetOutgoingAngle (:925-933), которая, как и оригинал, читает body
        // БЕЗ проверки. Все остальные вызовы прикрыты guard'ом BodyKeyCount > 0, который на
        // отсутствующем треке отдаёт 0 и уводит в нулевую ветку вместо исключения.
        private KeyFrame FirstBodyKey()
        {
            foreach (var kv in _tracks[BodyTrack].Keys) return kv.Value;
            return default;
        }

        // (--(nodeAnimations.at(1)->animation.end()))->second — последний ключ body-трека.
        private KeyFrame LastBodyKey()
        {
            KeyFrame last = default;
            foreach (var kv in _tracks[BodyTrack].Keys) last = kv.Value;
            return last;
        }

        // Дельта пары ключей root-трека, нормированная на разность кадров, ×100, Z занулён.
        // Оригинал пишет знаменатель как `(f1 - f0 * 1.0)`: по приоритету операций `*` связывает
        // сильнее `-`, то есть это `f1 - (f0 * 1.0)` — численно ровно `f1 - f0`. Ни багом, ни
        // необходимостью `* 1.0` не является: у Vector3 есть только `operator / (const real)`
        // (vector3.hpp:61), перегрузки под int нет, так что целочисленного деления там не могло
        // случиться и без него — приём чисто оборонительный/стилистический. Запись сохранена
        // дословно (animation.cpp:803-806/:841-844).
        private Vector3 RootDelta(int posA, int posB, bool fromEnd)
        {
            var (fa, ka) = RootKeyAt(posA, fromEnd);
            var (fb, kb) = RootKeyAt(posB, fromEnd);
            Vector3 result = (ka.Position - kb.Position) / (fa - fb * 1.0f) * 100f;
            result.Z = 0;
            return result;
        }

        // Квантование скорости по корзинам (animation.cpp:825-828 и :902-905 — идентичные блоки).
        // Литералы оригинала: пороги совпадают с Velo.IdleDribbleSwitch/DribbleWalkSwitch/
        // WalkSprintSwitch, но верхняя корзина — 7.0, а НЕ Velo.Sprint (8.0). Так в оригинале.
        private static float BucketVelocity(float v)
        {
            if (v < 1.8f) return 0f;
            else if (v >= 1.8f && v < 4.2f) return 3.5f;
            else if (v >= 4.2f && v < 6.0f) return 5.0f;
            else if (v >= 6.0f) return 7.0f;
            return v;
        }

        // animation.cpp:789-797. Оригинал не проверяет размер: при пустом треке `--end()` — UB.
        public Vector3 GetTranslation()
        {
            if (_cTranslationDirty)
            {
                if (RootKeyCount > 0)
                {
                    var (_, last) = RootKeyAt(0, true);
                    var (_, first) = RootKeyAt(0, false);
                    _cTranslation = last.Position - first.Position;
                    _cTranslation.Z = 0;
                }
                else _cTranslation = Vector3.Zero;
                _cTranslationDirty = false;
            }
            return _cTranslation;
        }

        // animation.cpp:799-814 (дельта двух ПЕРВЫХ ключей root-трека)
        public Vector3 GetIncomingMovement()
        {
            if (_cIncomingMovementDirty)
            {
                _cIncomingMovement = RootKeyCount > 1 ? RootDelta(1, 0, false) : Vector3.Zero;
                _cIncomingMovementDirty = false;
            }
            return _cIncomingMovement;
        }

        // animation.cpp:816-835
        public float GetIncomingVelocity()
        {
            if (_cIncomingVelocityDirty)
            {
                if (RootKeyCount > 1) _cIncomingVelocity = BucketVelocity(RootDelta(1, 0, false).Length());
                else _cIncomingVelocity = 0;
                _cIncomingVelocityDirty = false;
            }
            return _cIncomingVelocity;
        }

        // animation.cpp:837-853 (дельта двух ПОСЛЕДНИХ ключей root-трека)
        public Vector3 GetOutgoingMovement()
        {
            if (_cOutgoingMovementDirty)
            {
                _cOutgoingMovement = RootKeyCount > 1 ? RootDelta(0, 1, true) : Vector3.Zero;
                _cOutgoingMovementDirty = false;
            }
            return _cOutgoingMovement;
        }

        // animation.cpp:855-867
        public Vector3 GetRangedOutgoingMovement()
        {
            if (_cRangedOutgoingMovementDirty || _cOutgoingVelocityDirty || _cAngleDirty)
            {
                if (RootKeyCount > 1)
                    _cRangedOutgoingMovement = BluntMath.GetRotated2D(
                        new Vector3(0, -GetOutgoingVelocity(), 0), GetOutgoingAngle());
                else
                    _cRangedOutgoingMovement = Vector3.Zero;
                _cRangedOutgoingMovementDirty = false;
            }
            return _cRangedOutgoingMovement;
        }

        // animation.cpp:869-875
        public Vector3 GetOutgoingDirection()
        {
            if (_cOutgoingDirectionDirty || _cAngleDirty)
            {
                _cOutgoingDirection = BluntMath.GetRotated2D(new Vector3(0, -1, 0), GetOutgoingAngle());
                _cOutgoingDirectionDirty = false;
            }
            return _cOutgoingDirection;
        }

        // animation.cpp:877-883
        public Vector3 GetIncomingBodyDirection()
        {
            if (_cIncomingBodyDirectionDirty || _cIncomingBodyAngleDirty)
            {
                _cIncomingBodyDirection = BluntMath.GetRotated2D(new Vector3(0, -1, 0), GetIncomingBodyAngle());
                _cIncomingBodyDirectionDirty = false;
            }
            return _cIncomingBodyDirection;
        }

        // animation.cpp:885-891
        public Vector3 GetOutgoingBodyDirection()
        {
            if (_cOutgoingBodyDirectionDirty || _cOutgoingBodyAngleDirty)
            {
                _cOutgoingBodyDirection = BluntMath.GetRotated2D(new Vector3(0, -1, 0), GetOutgoingBodyAngle());
                _cOutgoingBodyDirectionDirty = false;
            }
            return _cOutgoingBodyDirection;
        }

        // animation.cpp:893-912
        public float GetOutgoingVelocity()
        {
            if (_cOutgoingVelocityDirty)
            {
                if (RootKeyCount > 1) _cOutgoingVelocity = BucketVelocity(RootDelta(0, 1, true).Length());
                else _cOutgoingVelocity = 0;
                _cOutgoingVelocityDirty = false;
            }
            return _cOutgoingVelocity;
        }

        // animation.cpp:914-962
        public float GetOutgoingAngle()
        {
            if (_cAngleDirty || _cOutgoingVelocityDirty)
            {
                if (GetOutgoingVelocity() >= 1.8f)
                {
                    // полный поворот игрока = направление последнего перемещения.
                    // Внимание: здесь берётся СЫРАЯ разность позиций (Z не зануляется, в отличие
                    // от GetOutgoingMovement) и НЕ делится на кадры — GetAngle2D смотрит лишь X/Y.
                    var (_, last) = RootKeyAt(0, true);
                    var (_, prev) = RootKeyAt(1, true);
                    Vector3 lastMoveVector = last.Position - prev.Position;
                    _cAngle = BluntMath.FixAngle(BluntMath.GetAngle2D(lastMoveVector));

                    // Около ±180° неясно, 180 нам нужно или -180 — сторону подсказывает
                    // z-эйлер последнего ключа body (animation.cpp:925-933).
                    if (_cAngle < -0.95f * Mathf.Pi || _cAngle > 0.95f * Mathf.Pi)
                    {
                        QuatUtil.GetAngles(LastBodyKey().Orientation, out _, out _, out float z);
                        if (BluntMath.SignSide(_cAngle) != BluntMath.SignSide(z))
                            _cAngle = Mathf.Pi * 0.99f * BluntMath.SignSide(z);
                        else
                            // кламп и при уже верной стороне: нужен зазор до pi, иначе у векторов,
                            // построенных на этом угле, нет внятной стороны (animation.cpp:931)
                            _cAngle = Mathf.Clamp(_cAngle, -0.99f * Mathf.Pi, 0.99f * Mathf.Pi);
                    }
                }
                else
                {
                    // стоим — угол берём из поворота тела (animation.cpp:937-955)
                    if (BodyKeyCount > 0)
                    {
                        QuatUtil.GetAngles(LastBodyKey().Orientation, out _, out _, out float z);
                        _cAngle = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi, z);
                    }
                    else _cAngle = 0;
                }
                _cAngleDirty = false;
            }
            return _cAngle;
        }

        // animation.cpp:964-991 — z-эйлер ПЕРВОГО ключа body-трека
        public float GetIncomingBodyAngle()
        {
            if (_cIncomingBodyAngleDirty)
            {
                if (BodyKeyCount > 0)
                {
                    QuatUtil.GetAngles(FirstBodyKey().Orientation, out _, out _, out float z);
                    _cIncomingBodyAngle = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi, z);
                }
                else _cIncomingBodyAngle = 0;
                _cIncomingBodyAngleDirty = false;
            }
            return _cIncomingBodyAngle;
        }

        // animation.cpp:993-1027 — z-эйлер ПОСЛЕДНЕГО ключа body минус GetOutgoingAngle();
        // при outgoing velocity < 1.8 жёстко 0 (animation.cpp:1020-1022).
        public float GetOutgoingBodyAngle()
        {
            if (_cOutgoingBodyAngleDirty || _cAngleDirty || _cOutgoingVelocityDirty)
            {
                if (GetOutgoingVelocity() >= 1.8f)
                {
                    if (BodyKeyCount > 0)
                    {
                        QuatUtil.GetAngles(LastBodyKey().Orientation, out _, out _, out float z);
                        _cOutgoingBodyAngle = z - GetOutgoingAngle();
                        _cOutgoingBodyAngle = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi, _cOutgoingBodyAngle);
                    }
                    else _cOutgoingBodyAngle = 0;
                }
                else _cOutgoingBodyAngle = 0;
                _cOutgoingBodyAngleDirty = false;
            }
            return _cOutgoingBodyAngle;
        }

        // Порт Animation::GetOutgoingFoot (animation.cpp:1029-1052). Без кэша — как в оригинале.
        // Нечётное число шагов меняет ногу, чётное оставляет текущую; тег steps пуст → 1 шаг.
        public int GetOutgoingFootId()
        {
            string foot = GetVariable("steps");
            int curFoot = GetCurrentFootId();
            int steps = 1;
            if (foot != "") steps = BluntMath.AtoI(foot);
            if (BluntMath.IsOdd(steps)) return curFoot == FootLeft ? FootRight : FootLeft;
            else return curFoot == FootRight ? FootRight : FootLeft;
        }

        // Порт конструктора копии Animation (animation.cpp:34-85). Extensions у нас интегрированы
        // в сам класс, поэтому `_touches` копируются глубоко — строже shallow-копии оригинала
        // (animation.cpp:43-44), что безопаснее для Mirror/Shift над клоном.
        //
        // ХВОСТ ДЛЯ ЗАДАЧ 5-6: в оригинале shallow-копия extensions немедленно затирается —
        // GenerateAutoAnims сразу после copy-ctor вешает клону СВЕЖИЙ пустой
        // FootballAnimationExtension (animcollection.cpp:409-417), так что наблюдаемое поведение
        // там — «у клона касаний нет». Наш Clone переносит _touches. Для movement-шаблонов,
        // из которых идёт автогенерация, карта касаний пуста → разницы нет; но если клонировать
        // клип С касаниями по этому пути, поведение разойдётся — держать в голове.
        public Animation Clone()
        {
            var dst = new Animation { _name = _name, _frameCount = _frameCount, _currentFoot = _currentFoot };
            foreach (var track in _tracks)
            {
                var t = new NodeAnimation { NodeName = track.NodeName };
                foreach (var kv in track.Keys) t.Keys[kv.Key] = kv.Value; // KeyFrame — struct, копия по значению
                dst._tracks.Add(t);
            }
            foreach (var kv in _touches) dst._touches[kv.Key] = kv.Value;
            foreach (var kv in _variables) dst._variables[kv.Key] = kv.Value; // шов 4: enumerator не нужен
            return dst;
        }

        // Порт Animation::Shift (animation.cpp:723-787). Поддержан только offset ±1 — как в оригинале
        // («todo: offset does not yet work» для остальных). Касания сдвигаются синхронно (шов 2;
        // extension->Shift, animation.cpp:782-786 + footballanimationextension.cpp:19-46).
        public void Shift(int fromFrame, int offset)
        {
            if (offset == 1)
            {
                bool somethingShifted = false;
                foreach (var track in _tracks)
                {
                    var newKeys = new SortedDictionary<int, KeyFrame>();
                    foreach (var kv in track.Keys)
                    {
                        int frameNum = kv.Key;
                        if (kv.Key >= fromFrame) { frameNum++; somethingShifted = true; }
                        newKeys[frameNum] = kv.Value;
                    }
                    track.Keys.Clear();
                    foreach (var kv in newKeys) track.Keys[kv.Key] = kv.Value;
                }
                if (somethingShifted) { _frameCount++; DirtyCache(); }
            }
            if (offset == -1)
            {
                bool somethingShifted = false;
                foreach (var track in _tracks)
                {
                    var newKeys = new SortedDictionary<int, KeyFrame>();
                    foreach (var kv in track.Keys)
                    {
                        int frameNum = kv.Key;
                        if (kv.Key != fromFrame) // ключ на fromFrame выбрасывается (animation.cpp:764)
                        {
                            if (kv.Key > fromFrame) { frameNum--; somethingShifted = true; }
                            newKeys[frameNum] = kv.Value;
                        }
                    }
                    track.Keys.Clear();
                    foreach (var kv in newKeys) track.Keys[kv.Key] = kv.Value;
                }
                if (somethingShifted) { _frameCount--; DirtyCache(); }
            }

            // Касания — те же правила сдвига (footballanimationextension.cpp:19-46)
            var newTouches = new SortedDictionary<int, Vector3>();
            foreach (var kv in _touches)
            {
                int frameNum = kv.Key;
                if (offset == 1) { if (kv.Key >= fromFrame) frameNum++; newTouches[frameNum] = kv.Value; }
                else if (offset == -1)
                {
                    if (kv.Key == fromFrame) continue;
                    if (kv.Key > fromFrame) frameNum--;
                    newTouches[frameNum] = kv.Value;
                }
                // Расхождение с оригиналом (осознанное): при offset вне ±1 C++-extension присваивает
                // пустой newAnimation и ТЕРЯЕТ все касания (footballanimationextension.cpp:21,46),
                // хотя ключи клипа при этом не трогаются. Ветка вдвойне недостижима: единственный
                // вызов Shift в оригинале идёт с offset=1 (animcollection.cpp:1060), да и сам он
                // сидит внутри Slowdown, а её единственный вызов закомментирован
                // (animcollection.cpp:1186). Мы касания сохраняем.
                else newTouches[frameNum] = kv.Value;
            }
            _touches.Clear();
            foreach (var kv in newTouches) _touches[kv.Key] = kv.Value;
        }

        // Порт Animation::Mirror (animation.cpp:1246-1313) + зеркало касаний
        // (footballanimationextension.cpp:59-67) — extensions у нас интегрированы (шов 2).
        public void Mirror()
        {
            _name += "_mirror";
            _currentFoot = _currentFoot == 1 ? 0 : 1;

            // swap треков left* ↔ right* (animation.cpp:1250-1269)
            for (int i = 0; i < _tracks.Count; i++)
            {
                if (!_tracks[i].NodeName.StartsWith("left")) continue;
                string needle = "right" + _tracks[i].NodeName.Substring(4);
                for (int j = 0; j < _tracks.Count; j++)
                {
                    if (_tracks[j].NodeName != needle) continue;
                    (_tracks[i].Keys, _tracks[j].Keys) = (_tracks[j].Keys, _tracks[i].Keys);
                    break;
                }
            }

            // негация: root X, у джойнтов — Y/Z кватерниона (animation.cpp:1271-1284)
            for (int i = 0; i < _tracks.Count; i++)
            {
                var newKeys = new SortedDictionary<int, KeyFrame>();
                foreach (var kv in _tracks[i].Keys)
                {
                    var k = kv.Value;
                    if (i == 0) k.Position = new Vector3(-k.Position.X, k.Position.Y, k.Position.Z);
                    else k.Orientation = new Quaternion(k.Orientation.X, -k.Orientation.Y,
                                                        -k.Orientation.Z, k.Orientation.W);
                    newKeys[kv.Key] = k;
                }
                _tracks[i].Keys.Clear();
                foreach (var kv in newKeys) _tracks[i].Keys[kv.Key] = kv.Value;
            }

            // касания: X-негация (footballanimationextension.cpp:59-67)
            var mirroredTouches = new SortedDictionary<int, Vector3>();
            foreach (var kv in _touches)
                mirroredTouches[kv.Key] = new Vector3(-kv.Value.X, kv.Value.Y, kv.Value.Z);
            _touches.Clear();
            foreach (var kv in mirroredTouches) _touches[kv.Key] = kv.Value;

            // значения переменных left↔right (animation.cpp:1293-1303)
            foreach (string key in new List<string>(_variables.Keys))
            {
                string v = _variables[key];
                if (v.StartsWith("left")) _variables[key] = "right" + v.Substring(4);
                else if (v.StartsWith("right")) _variables[key] = "left" + v.Substring(5);
            }

            // direction-теги: X-негация (animation.cpp:1305-1310). В оригинале SetVariable зовётся
            // безусловно (пустой тег станет "0.000000, 0.000000, 0.000000") — bug-for-bug.
            foreach (string tag in new[] { "balldirection", "incomingballdirection", "bumpdirection" })
            {
                Vector3 v = GetVariable(tag) != ""
                    ? BluntMath.GetVectorFromString(GetVariable(tag)) * new Vector3(-1, 1, 1)
                    : Vector3.Zero;
                SetVariable(tag, BluntMath.GetStringFromVector(v));
            }

            DirtyCache();
        }

        // animation.cpp:1157-1179 (шов 3): три direction-тега нормализуются при загрузке,
        // GetVariable дальше отдаёт уже нормализованный вектор.
        // КОРРЕКЦИЯ ОТНОСИТЕЛЬНО БРИФА: сериализация тут — НЕ GetStringFromVector. Load оригинала
        // (animation.cpp:1162/1170/1178) собирает строку инлайн: real_to_str(x)+","+real_to_str(y)+
        // ","+real_to_str(z), где real_to_str = snprintf("%f") (utils.cpp:205-211) — БЕЗ пробелов
        // после запятых. GetStringFromVector же даёт "%f, %f, %f" с пробелами (utils.cpp:213-219) и
        // используется только в Convert/Mirror (:337-339,:1308-1310). Чтобы Load-формат был 1:1 с
        // оригиналом ("0.000000,1.000000,0.000000"), формируем строку без пробелов.
        private void NormalizeDirectionTags()
        {
            foreach (string tag in new[] { "bumpdirection", "balldirection", "incomingballdirection" })
            {
                if (!_variables.ContainsKey(tag)) continue;
                Vector3 v = BluntMath.GetVectorFromString(_variables[tag]);
                if (v.Length() > 0) v = v.Normalized();
                _variables[tag] = string.Format(CultureInfo.InvariantCulture,
                    "{0:F6},{1:F6},{2:F6}", v.X, v.Y, v.Z);
            }
        }

        // Порт ConvertToStartFacingForwardIfIdle (animation.cpp:297-342): idle-входные клипы
        // разворачиваются лицом вперёд; касания и direction-теги вращаются синхронно (шов 2).
        private void ConvertToStartFacingForwardIfIdle()
        {
            float incomingBodyAngle = GetIncomingBodyAngle();
            if (GetIncomingVelocity() >= 1.8f) return;

            // позиции root (animation.cpp:305-311)
            var rootKeys = new SortedDictionary<int, KeyFrame>();
            foreach (var kv in _tracks[0].Keys)
            {
                var k = kv.Value;
                k.Position = BluntMath.GetRotated2D(k.Position, -incomingBodyAngle);
                rootKeys[kv.Key] = k;
            }
            _tracks[0].Keys.Clear();
            foreach (var kv in rootKeys) _tracks[0].Keys[kv.Key] = kv.Value;

            // ориентации body (animation.cpp:313-325)
            Quaternion zRot = QuatUtil.AngleAxis(-incomingBodyAngle, new Vector3(0, 0, 1));
            var bodyKeys = new SortedDictionary<int, KeyFrame>();
            foreach (var kv in _tracks[1].Keys)
            {
                var k = kv.Value;
                k.Orientation = zRot * k.Orientation;
                bodyKeys[kv.Key] = k;
            }
            _tracks[1].Keys.Clear();
            foreach (var kv in bodyKeys) _tracks[1].Keys[kv.Key] = kv.Value;

            // касания (animation.cpp:327-331 → footballanimationextension.cpp:49-57)
            var rotTouches = new SortedDictionary<int, Vector3>();
            foreach (var kv in _touches)
                rotTouches[kv.Key] = BluntMath.GetRotated2D(kv.Value, -incomingBodyAngle);
            _touches.Clear();
            foreach (var kv in rotTouches) _touches[kv.Key] = kv.Value;

            // direction-теги (animation.cpp:333-339; безусловный SetVariable — bug-for-bug)
            foreach (string tag in new[] { "balldirection", "incomingballdirection", "bumpdirection" })
            {
                Vector3 v = GetVariable(tag) != ""
                    ? BluntMath.GetRotated2D(BluntMath.GetVectorFromString(GetVariable(tag)), -incomingBodyAngle)
                    : Vector3.Zero;
                SetVariable(tag, BluntMath.GetStringFromVector(v));
            }

            DirtyCache();
        }

        // Доступ для AnimCollection/генератора клипов (задачи 5-6) — внутри одной сборки.
        internal SortedDictionary<int, KeyFrame> TrackKeys(int i) => _tracks[i].Keys;
        internal void ClearTrackKeys(int i) => _tracks[i].Keys.Clear();
        internal SortedDictionary<int, Vector3> Touches => _touches;
        internal Dictionary<string, string> Variables => _variables;

        internal void GetInterpolatedValuesAt(int trackIndex, int frame,
                                              out Quaternion orientation, out Vector3 position)
            => GetInterpolatedValues(_tracks[trackIndex].Keys, frame, out orientation, out position);

        private static float ParseF(string s) => float.Parse(s, CultureInfo.InvariantCulture);
    }
}

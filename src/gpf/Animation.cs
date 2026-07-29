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

        public string GetName() => _name;
        public int GetFrameCount() => _frameCount;
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
        // Расхождение с оригиналом: при загрузке animation.cpp:1157-1192 нормализует (нормирует вектор)
        // значения тегов bumpdirection/balldirection/incomingballdirection и кладёт в variableCache уже
        // нормализованными. Здесь GetVariable отдаёт сырой текст тега — нормализация отложена до фазы 2
        // (AnimCollection), зафиксировано в docs/wiki/открытые-вопросы.md.
        private void LoadXmlTail(string xml)
        {
            if (xml.Trim().Length == 0) return;
            var doc = new System.Xml.XmlDocument();
            doc.LoadXml("<root>" + xml + "</root>");
            foreach (System.Xml.XmlNode child in doc.DocumentElement!.ChildNodes)
                if (child.NodeType == System.Xml.XmlNodeType.Element)
                    _variables[child.Name] = child.InnerText.Trim();
        }

        private void SetKeyFrame(string nodeName, int frame, Quaternion orientation, Vector3 position)
        {
            var track = FindTrack(nodeName);
            if (track == null)
            {
                track = new NodeAnimation { NodeName = nodeName };
                _tracks.Add(track);
            }
            track.Keys[frame] = new KeyFrame { Orientation = orientation, Position = position };
            if (frame >= _frameCount) _frameCount = frame + 1; // animation.cpp:123
        }

        private static float ParseF(string s) => float.Parse(s, CultureInfo.InvariantCulture);
    }
}

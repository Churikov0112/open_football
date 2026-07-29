using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // Порт AnimCollection (animcollection.{hpp,cpp}): квадранты, загрузка библиотеки,
    // _PrepareAnim-обогащение. CrudeSelection — отдельным куском (задача 7).
    public partial class AnimCollection : RefCounted
    {
        // e_FunctionType (gamedefines.hpp:93-108), int-иды для моста
        public const int FnNone = 0; public const int FnMovement = 1; public const int FnBallControl = 2;
        public const int FnTrap = 3; public const int FnShortPass = 4; public const int FnLongPass = 5;
        public const int FnHighPass = 6; public const int FnHeader = 7; public const int FnShot = 8;
        public const int FnDeflect = 9; public const int FnCatch = 10; public const int FnInterfere = 11;
        public const int FnTrip = 12; public const int FnSliding = 13; public const int FnSpecial = 14;

        public struct Quadrant
        {
            public int Id;
            public Vector3 Position;
            public int VelocityId;
            public float Angle;
        }

        private readonly List<Animation> _animations = new();
        private readonly List<Quadrant> _quadrants = new();
        private readonly AnimationApplier _applier = new();
        private int _idleMovementAnimId = -1;

        // animcollection.cpp:57-58
        private const float MaxIncomingBallDirectionDeviation = 0.25f * Mathf.Pi;
        private const float MaxOutgoingBallDirectionDeviation = 0.25f * Mathf.Pi;

        public AnimCollection()
        {
            // Квадранты (animcollection.cpp:61-106): idle + 3 скорости × 11 углов
            _quadrants.Add(new Quadrant { Id = 0, VelocityId = Velo.IdVelIdle, Angle = 0, Position = Vector3.Zero });
            float[] angles =
            {
                0f, 20f, 45f, 90f, 135f, 179f, -20f, -45f, -90f, -135f, -179f,
            };
            int id = 1;
            for (int velocityId = 1; velocityId < 4; velocityId++)
            {
                foreach (float deg in angles)
                {
                    float angle = Mathf.Pi / 180f * deg;
                    _quadrants.Add(new Quadrant
                    {
                        Id = id,
                        VelocityId = velocityId,
                        Angle = angle,
                        Position = BluntMath.GetRotated2D(new Vector3(0, -1, 0), angle)
                                   * Velo.EnumToFloatVelocity(velocityId),
                    });
                    id++;
                }
            }
        }

        public int GetAnimationCount() => _animations.Count;
        public Animation GetAnim(int index) => _animations[index];
        internal List<Animation> Animations => _animations;
        public int GetQuadrantCount() => _quadrants.Count;
        public float GetQuadrantAngle(int id) => _quadrants[id].Angle;
        public int GetQuadrantVelocityId(int id) => _quadrants[id].VelocityId;
        public Vector3 GetQuadrantPosition(int id) => _quadrants[id].Position;
        internal Quadrant GetQuadrant(int id) => _quadrants[id];
        public int GetIdleMovementAnimID() => _idleMovementAnimId;

        // Кэш позиций корня per-клип — порт Match::Match (match.cpp:86-105): позиция player-трека
        // на каждом кадре, Z занулён. Оригинал держит его в Match (map Animation* → vector<Vector3>);
        // у нас живёт при коллекции — единственном владельце клипов, и индексируется параллельно
        // _animations.
        private readonly List<List<Vector3>> _positionCaches = new();

        internal List<Vector3> GetPositionCacheInternal(int animIndex) => _positionCaches[animIndex];
        public int GetPositionCacheCount() => _positionCaches.Count;

        internal static List<Vector3> BuildPositionCacheInternal(Animation anim)
        {
            var positions = new List<Vector3>();
            for (int frame = 0; frame < anim.GetFrameCount(); frame++) // match.cpp:97
            {
                Vector3 position = anim.SampleRootPosition(frame, 0f);  // == GetKeyFrame position
                position.Z = 0.0f;                                      // match.cpp:99
                positions.Add(position);
            }
            return positions;
        }

        // Мост-обёртка для GDScript: List<Vector3> через мост не ходит, отдаём Godot Array.
        public static Godot.Collections.Array BuildPositionCache(Animation anim)
        {
            var result = new Godot.Collections.Array();
            foreach (Vector3 p in BuildPositionCacheInternal(anim)) result.Add(p);
            return result;
        }

        // Порт AnimCollection::Load (animcollection.cpp:354-487).
        public void Load(string animationsRoot, Skeleton3D utilitySkeleton)
        {
            _animations.Clear();
            _idleMovementAnimId = -1;

            var files = new List<string>();
            ScanAnimFiles(animationsRoot, files);
            files.Sort(System.StringComparer.Ordinal); // контракт детерминизма (в C++ порядок ФС)

            // Ветка templates + GenerateAutoAnims (animcollection.cpp:384-419) — задача 6.
            LoadTemplatesAndGenerate(animationsRoot, utilitySkeleton);

            // «Все остальные» (animcollection.cpp:422-476): без templates/ и luxury, каждый ×2
            foreach (string file in files)
            {
                if (file.Contains("luxury") || file.Contains("templates")) continue; // :437
                for (int mirror = 0; mirror < 2; mirror++) // :444-449
                {
                    var animation = new Animation();
                    if (!animation.LoadFromFile(file))
                    {
                        GD.PushError($"Gpf.AnimCollection: не загрузился {file}");
                        continue;
                    }
                    if (mirror == 1) animation.Mirror();
                    PrepareAnim(animation, utilitySkeleton);
                }
            }

            for (int i = 0; i < _animations.Count; i++)
            {
                var a = _animations[i];
                if (a.GetAnimType() == "movement" && a.GetIncomingVelocity() < 1.8f && a.GetOutgoingVelocity() < 1.8f)
                {
                    _idleMovementAnimId = i; // фолбэк humanoidbase.cpp:1416
                    break;
                }
            }

            // Кэш позиций корня строится ПОСЛЕДНИМ — коллекция уже окончательна (автогены, зеркала,
            // файловые клипы все в _animations), поэтому кэш параллелен ей по индексам. В оригинале
            // это отдельный проход в конструкторе Match уже после anims->Load (match.cpp:86-105).
            _positionCaches.Clear();
            foreach (Animation clip in _animations) _positionCaches.Add(BuildPositionCacheInternal(clip));
        }

        private int _autoAnimVelocityMismatchCount;
        public int GetAutoAnimVelocityMismatchCount() => _autoAnimVelocityMismatchCount;

        // animcollection.cpp:125-160 — таблица углов направлений.
        private static float GetAngle(int directionId) => directionId switch
        {
            0 => 0.0f,
            1 => 0.25f * Mathf.Pi,
            2 => -0.25f * Mathf.Pi,
            3 => 0.50f * Mathf.Pi,
            4 => -0.50f * Mathf.Pi,
            5 => 0.75f * Mathf.Pi,
            6 => -0.75f * Mathf.Pi,
            7 => 0.99f * Mathf.Pi,
            8 => -0.99f * Mathf.Pi,
            _ => 0.0f,
        };

        // Порт ветки Load для templates (animcollection.cpp:384-419).
        private void LoadTemplatesAndGenerate(string animationsRoot, Skeleton3D utilitySkeleton)
        {
            var templateFiles = new List<string>();
            ScanAnimFiles(animationsRoot + "/templates", templateFiles);
            templateFiles.Sort(System.StringComparer.Ordinal);
            if (templateFiles.Count == 0) return;

            var templates = new List<Animation>();
            foreach (string f in templateFiles)
            {
                var t = new Animation();
                if (t.LoadFromFile(f)) templates.Add(t);
            }

            var autoAnims = new List<Animation>();
            GenerateAutoAnims(templates, autoAnims);

            foreach (var auto in autoAnims) // :408-419 — зеркало первым, затем оригинал
            {
                var mirrored = auto.Clone();
                mirrored.Mirror();
                PrepareAnim(mirrored, utilitySkeleton);
                PrepareAnim(auto, utilitySkeleton);
            }
        }

        // Порт GenerateAutoAnims (animcollection.cpp:162-352). Дословно, включая кумулятивный
        // lean-эффект movementChangeMPS внутри кадрового цикла body (:315) — так в оригинале.
        internal void GenerateAutoAnims(List<Animation> templates, List<Animation> autoAnims)
        {
            const float leanAmount = 0.001f; // :164
            const int frameCount = 25;       // :165
            const float margin = 0.01f;      // :166

            for (int t1 = 0; t1 < templates.Count; t1++)
            for (int t2 = 0; t2 < templates.Count; t2++)
            {
                Animation anim1 = templates[t1];
                Animation anim2 = templates[t2];

                for (int direction = 0; direction < 9; direction++)
                {
                    float angle = GetAngle(direction);
                    float incomingVelocityT1 = anim1.GetIncomingVelocity();
                    float outgoingVelocityT2 = anim2.GetOutgoingVelocity();
                    float incomingBodyAngleT1 = anim1.GetIncomingBodyAngle();
                    float outgoingBodyAngleT2 = anim2.GetOutgoingBodyAngle();

                    bool legalAnim = true;

                    int incomingVeloId = Velo.GetVelocityID(Velo.FloatToEnumVelocity(incomingVelocityT1));
                    int outgoingVeloId = Velo.GetVelocityID(Velo.FloatToEnumVelocity(outgoingVelocityT2));
                    float averageVeloFactor = BluntMath.NormalizedClamp(incomingVeloId + outgoingVeloId, 0, 6);

                    // max acceleration (:189-190)
                    int veloIdDiff = outgoingVeloId - incomingVeloId;
                    if (veloIdDiff > 1) legalAnim = false;

                    // max deceleration через dot (:193-196)
                    float dot = new Vector3(0, -1, 0).Dot(BluntMath.GetRotated2D(new Vector3(0, -1, 0), angle));
                    int veloIdDiffDotted = Mathf.RoundToInt(outgoingVeloId * dot - incomingVeloId);
                    if (veloIdDiffDotted < -3) legalAnim = false;

                    // :198 sprint→dribble с развёрнутым корпусом
                    if (incomingVeloId == 3 && outgoingVeloId == 1 &&
                        (Mathf.Abs(outgoingBodyAngleT2) > 0.25f * Mathf.Pi + margin ||
                         Mathf.Abs(angle) > 0.25f * Mathf.Pi + margin)) legalAnim = false;

                    // :202 движение→движение с углом > 90°
                    if (incomingVeloId > 0 && outgoingVeloId > 0 &&
                        Mathf.Abs(angle) > 0.50f * Mathf.Pi + margin) legalAnim = false;

                    // :211-212 быстрые связки с углом > 45°
                    if (incomingVeloId + outgoingVeloId > 5 && Mathf.Abs(angle) > 0.25f * Mathf.Pi + margin) legalAnim = false;
                    if (incomingVeloId + outgoingVeloId > 4 && Mathf.Abs(angle) > 0.25f * Mathf.Pi + margin) legalAnim = false;

                    // :217-218 суммарный поворот > 180°
                    float bodyAngleDelta = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi,
                        outgoingBodyAngleT2 - incomingBodyAngleT1);
                    if (Mathf.Abs(angle + bodyAngleDelta) > 1.0f * Mathf.Pi + margin) legalAnim = false;

                    const float animSpeedFactor = 1.0f; // :233

                    if (!legalAnim) continue;

                    Animation gen = anim1.Clone(); // :237
                    gen.SetName("autogen [v" + Velo.GetVelocityID(Velo.FloatToEnumVelocity(incomingVelocityT1))
                        + " b" + (int)(incomingBodyAngleT1 / Mathf.Pi * 180f)
                        + "] => [v" + Velo.GetVelocityID(Velo.FloatToEnumVelocity(outgoingVelocityT2))
                        + " b" + (int)(outgoingBodyAngleT2 / Mathf.Pi * 180f)
                        + " a" + (int)(angle / Mathf.Pi * 180f) + "]"); // :238
                    gen.SetVariable("priority", "1"); // :239

                    for (int n = 0; n < gen.GetTrackCount(); n++)
                    {
                        gen.ClearTrackKeys(n); // :246

                        Vector3 cumulativePosition = Vector3.Zero;
                        int prevFrame = 0;
                        Vector3 outgoingMovement = BluntMath.GetRotated2D(anim2.GetOutgoingMovement(), angle); // :255
                        Vector3 movementChangeMps = (outgoingMovement - anim1.GetIncomingMovement()) * (100.0f / frameCount); // :257

                        // сбор ключей обоих шаблонов (:262-276)
                        var keyFrames = new SortedSet<int>();
                        foreach (var kv in anim1.TrackKeys(n)) keyFrames.Add(kv.Key);
                        foreach (var kv in anim2.TrackKeys(n)) keyFrames.Add(kv.Key);
                        if (n == 0)
                        {
                            keyFrames.Add(1);
                            keyFrames.Add(23);
                            for (int i = 2; i < frameCount - 2; i += 4) keyFrames.Add(i); // :273
                        }

                        foreach (int frame in keyFrames) // :281-332
                        {
                            float targetFrame = frame * (1.0f / animSpeedFactor);

                            anim1.GetInterpolatedValuesAt(n, frame, out Quaternion orientationT1, out Vector3 positionT1);
                            anim2.GetInterpolatedValuesAt(n, frame, out Quaternion orientationT2, out Vector3 positionT2);
                            if (n == 0) { orientationT1 = Quaternion.Identity; orientationT2 = Quaternion.Identity; } // getOrientation=false (:289)

                            float origBias = Mathf.Clamp(frame - 1.0f, 0.0f, frameCount - 3.0f) / (frameCount - 3.0f); // :295
                            float bias = Mathf.Pow(origBias,
                                1.0f * (0.3f + 0.4f * averageVeloFactor +
                                        0.3f * BluntMath.NormalizedClamp(movementChangeMps.Length(), 0.0f, 20.0f))); // :302
                            bias = BluntMath.Curve(bias, 0.7f); // :304
                            Quaternion orientation = QuatUtil.Slerp(orientationT1, bias, orientationT2); // :306

                            if (n == 1) // body (:308-318)
                            {
                                Quaternion angleQuat = QuatUtil.AngleAxis(
                                    angle * Mathf.Pow(bias * 0.7f + origBias * 0.3f, 1.0f), new Vector3(0, 0, 1)); // :310
                                orientation = angleQuat * orientation;

                                movementChangeMps *= 0.5f + 0.5f *
                                    ((anim1.GetIncomingMovement() * (1.0f - bias) + outgoingMovement * bias).Length()
                                     / Velo.Sprint); // :315 — кумулятивно по кадрам, как в оригинале
                                Quaternion leanQuat = QuatUtil.AngleAxis(
                                    movementChangeMps.Length() * leanAmount * (0.5f + 0.5f * Mathf.Sin(origBias * Mathf.Pi)),
                                    BluntMath.GetRotated2D(new Vector3(0, 1, 0),
                                        BluntMath.GetAngle2D(BluntMath.GetNormalized(movementChangeMps, Vector3.Zero)))); // :316
                                orientation = leanQuat * orientation;
                            }

                            float height = 0.0f;
                            if (n == 0) // player (:321-326)
                            {
                                cumulativePosition +=
                                    anim1.GetIncomingMovement() * ((frame - prevFrame) * 0.01f) * (1.0f - bias) +
                                    outgoingMovement * ((frame - prevFrame) * 0.01f) * bias;
                                height = positionT1.Z * (1.0f - bias) + positionT2.Z * bias;
                            }

                            gen.SetKeyFrame(gen.GetTrackName(n), (int)Mathf.Floor(targetFrame), orientation,
                                cumulativePosition * (1.0f / animSpeedFactor) + new Vector3(0, 0, height)); // :328

                            prevFrame = frame;
                        }
                    }

                    gen.DirtyCache(); // :335

                    // :337-338 — в C++ assert
                    if (gen.GetIncomingVelocity() != anim1.GetIncomingVelocity() ||
                        gen.GetOutgoingVelocity() != anim2.GetOutgoingVelocity())
                    {
                        _autoAnimVelocityMismatchCount++;
                        GD.PushError($"Gpf.AnimCollection: автоген с расхождением скоростей: {gen.GetName()}");
                    }

                    autoAnims.Add(gen);
                }
            }

            GD.Print($"[gpf] GenerateAutoAnims: {autoAnims.Count} автогенов");
        }

        private static void ScanAnimFiles(string dir, List<string> outFiles)
        {
            using var d = DirAccess.Open(dir);
            if (d == null) return;
            d.ListDirBegin();
            for (string f = d.GetNext(); f != ""; f = d.GetNext())
            {
                string path = dir + "/" + f;
                if (d.CurrentIsDir()) { if (!f.StartsWith(".")) ScanAnimFiles(path, outFiles); }
                else if (f.EndsWith(".anim")) outFiles.Add(path);
            }
            d.ListDirEnd();
        }

        // Порт _PrepareAnim (animcollection.cpp:1171-1209).
        private void PrepareAnim(Animation animation, Skeleton3D utilitySkeleton)
        {
            bool isTouch = animation.GetTouchCount() > 0;
            string type = animation.GetAnimType();
            bool touchless = type == "movement" || type == "trip" || type == "special";
            if (isTouch == touchless) // :1178-1179
                GD.PushWarning($"Gpf.AnimCollection: invalid ball touch for animtype: {animation.GetName()}");

            float expectedFrameCount = CalculateAnimDifficulty(animation, out float absDiff); // :1182
            _ = expectedFrameCount; // Slowdown не портируется — вызов закомментирован в оригинале (:1186)
            animation.SetVariable("animdifficultyfactor",
                absDiff.ToString(System.Globalization.CultureInfo.InvariantCulture));

            int touchFrame = AddExtraTouches(animation, utilitySkeleton); // :1189
            animation.SetVariable("touchframe", touchFrame.ToString());

            int quadrantId = GetQuadrantID(animation, animation.GetOutgoingMovement(), animation.GetOutgoingAngle()); // :1195-1197
            animation.SetVariable("quadrant_id", quadrantId.ToString());

            _animations.Add(animation);
        }

        // Живая часть AddExtraTouches (animcollection.cpp:883-911; хвост за
        // «return animTouchFrame; // XDEBUG disable this» мёртв и не портирован).
        // Приближение: «части тела» = глобальные позы 13 костей утилитарного скелета
        // (в C++ — Geometry-сегменты player.object, прикреплённые к тем же узлам).
        private int AddExtraTouches(Animation animation, Skeleton3D skel)
        {
            if (animation.GetTouchCount() == 0) return -1; // animTouchFrame default (:885)

            Vector3 animBallPos = animation.GetTouchPosition(0);
            int animTouchFrame = animation.GetTouchFrame(0);

            _applier.Apply(skel, animation, animTouchFrame, 0f); // :892

            string closest = "";
            float closestDistance = 100f; // :895
            for (int b = 0; b < skel.GetBoneCount(); b++)
            {
                string boneName = skel.GetBoneName(b);
                if (boneName == "player") continue;
                float distance = (animBallPos - skel.GetBoneGlobalPose(b).Origin).Length();
                if (distance < closestDistance)
                {
                    closestDistance = distance;
                    closest = boneName;
                }
            }
            animation.SetVariable("touch_bodypart", closest); // :909
            return animTouchFrame; // :911 — дальше в оригинале мёртвый код
        }

        // Порт CalculateAnimDifficulty (animcollection.cpp:977-1033).
        private static float CalculateAnimDifficulty(Animation animation, out float absoluteDifficulty)
        {
            bool isTouch = animation.GetTouchCount() > 0;

            float bodyDirDifficulty = Mathf.Clamp(Mathf.Abs(
                BluntMath.GetAngle2D(animation.GetIncomingBodyDirection(), animation.GetOutgoingBodyDirection()) / Mathf.Pi), 0f, 1f);
            float directionDifficulty = Mathf.Clamp(Mathf.Abs(
                BluntMath.GetAngle2D(new Vector3(0, -1, 0), animation.GetOutgoingDirection()) / Mathf.Pi), 0f, 1f);

            float veloChangeDifficulty = Mathf.Clamp(
                Mathf.Abs(animation.GetIncomingVelocity() - animation.GetOutgoingVelocity()) / Velo.Sprint, 0f, 1f);
            float accelDifficulty = Mathf.Clamp(
                (animation.GetOutgoingVelocity() - animation.GetIncomingVelocity()) / Velo.Sprint, 0f, 1f);
            float veloDifficulty = veloChangeDifficulty * 0.5f + accelDifficulty * 0.5f; // :988

            float averageVelocity = Mathf.Clamp(
                (animation.GetIncomingVelocity() + animation.GetOutgoingVelocity()) / (Velo.Sprint * 2f), 0f, 1f);
            float movementDifficulty = Mathf.Clamp(
                (animation.GetIncomingMovement() - animation.GetOutgoingMovement()).Length() / Velo.Sprint, 0f, 1f)
                * Mathf.Pow(averageVelocity, 2f);

            const float bodyDirW = 0.5f, directionW = 1.0f, veloW = 1.0f, movementW = 4.0f; // :994-997
            float result = (bodyDirDifficulty * bodyDirW + directionDifficulty * directionW +
                            veloDifficulty * veloW + movementDifficulty * movementW)
                           / (bodyDirW + directionW + veloW + movementW);

            float expectedFrameCount = 20f + result * 80f; // :1006
            absoluteDifficulty = Mathf.Clamp(result, 0f, 1f); // :1015

            if (isTouch) { expectedFrameCount *= 1.1f; expectedFrameCount += 4f; } // :1017-1020
            absoluteDifficulty *= 0.88f;             // :1022
            if (isTouch) absoluteDifficulty += 0.12f; // :1023

            expectedFrameCount = Mathf.Clamp(expectedFrameCount,
                1, animation.GetFrameCount() - 1 + 16); // :1031 (GetEffectiveFrameCount() + 16)
            return expectedFrameCount;
        }

        // Порт GetQuadrantID (animcollection.cpp:865-880); animation/angle не используются — как в оригинале.
        public int GetQuadrantID(Animation animation, Vector3 movement, float angle)
        {
            Vector3 adaptedMovement = BluntMath.GetNormalized(movement, Vector3.Zero)
                                      * Velo.RangeVelocity(movement.Length());
            int quadrantId = 0;
            float shortestDistance = 100000.0f;
            foreach (var q in _quadrants)
            {
                float distance = (adaptedMovement - q.Position).Length();
                if (distance < shortestDistance)
                {
                    shortestDistance = distance;
                    quadrantId = q.Id;
                }
            }
            return quadrantId;
        }

        // Порт _CheckFunctionType (animcollection.cpp:1211-1275); строки типов — defString
        // (animcollection.cpp:35-55). Header в switch оригинала отсутствует → false.
        internal static bool CheckFunctionType(string animType, int queryFunctionTypeId) => queryFunctionTypeId switch
        {
            FnMovement => animType == "movement",
            FnBallControl => animType == "ballcontrol",
            FnTrap => animType == "trap",
            FnShortPass => animType == "shortpass",
            FnLongPass => animType == "longpass",
            FnHighPass => animType == "highpass",
            FnShot => animType == "shot",
            FnDeflect => animType == "deflect",
            FnCatch => animType == "catch",
            FnInterfere => animType == "interfere",
            FnTrip => animType == "trip",
            FnSliding => animType == "sliding",
            FnSpecial => animType == "special",
            _ => false,
        };

        // Публичная мост-обёртка для GDScript: нетипизированный Godot Array (мост не строг к
        // типизированным массивам), наполняется int-индексами выбранных клипов.
        public void CrudeSelection(Godot.Collections.Array dataSet, CrudeSelectionQuery query)
        {
            var list = new List<int>();
            CrudeSelectionInternal(list, query);
            foreach (int i in list) dataSet.Add(i);
        }

        // Порт AnimCollection::CrudeSelection (animcollection.cpp:494-863): грубый булев фильтр
        // библиотеки по запросу, один линейный проход, каждая секция под if (selectAnim). Внутренняя
        // перегрузка с List<int> — для C#-вызовов задач 8/10.
        internal void CrudeSelectionInternal(List<int> dataSet, CrudeSelectionQuery query)
        {
            for (int i = 0; i < _animations.Count; i++)
            {
                Animation anim = _animations[i];
                string animType = anim.GetAnimType();
                bool selectAnim = true;

                // select by TYPE (:510-514)
                if (selectAnim && query.ByFunctionType &&
                    !CheckFunctionType(animType, query.FunctionTypeId)) selectAnim = false;

                // select by INCOMING VELOCITY (:529-575)
                if (selectAnim && query.ByIncomingVelocity)
                {
                    int animIn = Velo.FloatToEnumVelocity(anim.GetIncomingVelocity());
                    if (!query.IncomingVelocityStrict)
                    {
                        // нестрогая матрица запретов (:537-548)
                        if (query.IncomingVelocityNoDribbleToIdle &&
                            animIn == Velo.IdVelIdle && query.IncomingVelocityId == Velo.IdVelDribble) selectAnim = false;
                        if (animIn == Velo.IdVelIdle && query.IncomingVelocityId == Velo.IdVelWalk) selectAnim = false;
                        if (animIn == Velo.IdVelIdle && query.IncomingVelocityId == Velo.IdVelSprint) selectAnim = false;
                        if (animIn == Velo.IdVelDribble && query.IncomingVelocityId == Velo.IdVelIdle) selectAnim = false;
                        if (animIn == Velo.IdVelWalk && query.IncomingVelocityId == Velo.IdVelIdle) selectAnim = false;
                        if (animIn == Velo.IdVelSprint && query.IncomingVelocityId == Velo.IdVelIdle) selectAnim = false;
                        if (query.IncomingVelocityNoDribbleToSprint &&
                            animIn == Velo.IdVelSprint && query.IncomingVelocityId == Velo.IdVelDribble) selectAnim = false;

                        if (query.IncomingVelocityForceLinearity) // :550-563
                        {
                            float animInF = Velo.RangeVelocity(anim.GetIncomingVelocity());
                            float animOutF = Velo.RangeVelocity(anim.GetOutgoingVelocity());
                            float queryF = Velo.EnumToFloatVelocity(query.IncomingVelocityId);
                            // dribble считается walk (:557-559)
                            if (Velo.FloatToEnumVelocity(animInF) == Velo.IdVelDribble) animInF = Velo.Walk;
                            if (Velo.FloatToEnumVelocity(animOutF) == Velo.IdVelDribble) animOutF = Velo.Walk;
                            if (Velo.FloatToEnumVelocity(queryF) == Velo.IdVelDribble) queryF = Velo.Walk;
                            if (animInF > Mathf.Max(queryF, animOutF)) selectAnim = false;
                            if (animInF < Mathf.Min(queryF, animOutF)) selectAnim = false;
                        }
                    }
                    else if (animIn != query.IncomingVelocityId) selectAnim = false; // strict (:567)
                }

                // select by OUTGOING VELOCITY (:585-589)
                if (selectAnim && query.ByOutgoingVelocity &&
                    Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) != query.OutgoingVelocityId) selectAnim = false;

                // CULL WRONG ROTATIONAL SIDE (:594-623)
                if (selectAnim && query.BySide)
                {
                    Vector3 animIncomingDirection = anim.GetIncomingBodyDirection(); // :597
                    Vector3 animOutgoingDirection = BluntMath.GetRotated2D(
                        anim.GetOutgoingDirection(), anim.GetOutgoingBodyAngle()); // :600
                    float animTurnAngle = BluntMath.GetAngle2D(animOutgoingDirection, animIncomingDirection); // :601
                    Vector3 fencedDirection = BluntMath.GetRotated2D(query.LookAtVecRel, Mathf.Pi); // :604

                    if (Mathf.Abs(animTurnAngle) > 0.06f * Mathf.Pi) // :606 threshold
                    {
                        int animSide = animTurnAngle > 0 ? 0 : 1; // e_Side: left=0/right=1 (:607)
                        float animInToFence = BluntMath.GetAngle2D(fencedDirection, animIncomingDirection); // :609
                        float queryInToFence = BluntMath.GetAngle2D(fencedDirection, query.IncomingBodyDirection); // :610
                        float fenceToOut = BluntMath.GetAngle2D(animOutgoingDirection, fencedDirection); // :611
                        int animInToFenceSide = animInToFence > 0 ? 0 : 1; // :613
                        int queryInToFenceSide = queryInToFence > 0 ? 0 : 1; // :614
                        int fenceToOutSide = fenceToOut > 0 ? 0 : 1; // :615

                        if (animInToFenceSide == animSide && fenceToOutSide == animSide &&
                            Mathf.Abs(animInToFence + fenceToOut) < Mathf.Pi) selectAnim = false; // :618
                        // :619 bug-for-bug: оригинал складывает enum-сторону (int e_Side) с радианами
                        // (queryIncomingToFenceSide + fenceToOutgoingAngle) вместо, видимо, угла
                        // queryIncomingToFenceAngle. Портируем дословно, НЕ «чиним».
                        if (queryInToFenceSide == animSide && fenceToOutSide == animSide &&
                            Mathf.Abs(queryInToFenceSide + fenceToOut) < Mathf.Pi) selectAnim = false;
                    }
                }

                // select by RETAIN BALL (:640-647)
                if (selectAnim && query.ByPickupBall)
                {
                    string retain = anim.GetVariable("outgoing_retain_state");
                    if ((retain == "" && query.PickupBall) || (retain != "" && !query.PickupBall)) selectAnim = false;
                }

                // select LAST DITCH ANIMS (:652-658)
                if (selectAnim && !query.AllowLastDitchAnims && anim.GetVariable("lastditch") == "true") selectAnim = false;

                // select by INCOMING BODY ANGLE (:663-752)
                if (selectAnim && query.ByIncomingBodyDirection &&
                    !(query.ByIncomingVelocity && query.IncomingVelocityId == Velo.IdVelIdle)) // :665
                {
                    const float marginRadians = 0.06f * Mathf.Pi; // :667
                    if (Velo.FloatToEnumVelocity(anim.GetIncomingVelocity()) != Velo.IdVelIdle) // :669
                    {
                        Vector3 incomingBodyDir = anim.GetIncomingBodyDirection(); // :671
                        // :691 — вход клипа не «шире» текущего
                        if (Mathf.Abs(BluntMath.FixAngle(BluntMath.GetAngle2D(anim.GetIncomingBodyDirection()))) >
                            Mathf.Abs(BluntMath.FixAngle(BluntMath.GetAngle2D(query.IncomingBodyDirection))) + marginRadians)
                            selectAnim = false;

                        if (selectAnim)
                        {
                            // абсолютное outgoing body dir = body dir + outgoing dir (:697)
                            Vector3 outgoingBodyDir = BluntMath.GetRotated2D(new Vector3(0, -1, 0),
                                anim.GetOutgoingBodyAngle() + anim.GetOutgoingAngle());
                            if (query.IncomingBodyDirectionStrict) // :709-710
                            {
                                if (Mathf.Abs(BluntMath.GetAngle2D(incomingBodyDir, query.IncomingBodyDirection)) > marginRadians)
                                    selectAnim = false;
                            }
                            else if (Mathf.Abs(BluntMath.GetAngle2D(incomingBodyDir, query.IncomingBodyDirection)) >
                                     0.5f * Mathf.Pi + marginRadians) selectAnim = false; // :712

                            if (selectAnim && query.IncomingBodyDirectionForceLinearity) // :718-732
                            {
                                float shortestAngle1 = BluntMath.GetAngle2D(incomingBodyDir, outgoingBodyDir); // :724
                                float shortestAngle2 = BluntMath.GetAngle2D(incomingBodyDir, query.IncomingBodyDirection); // :725
                                if ((shortestAngle1 > marginRadians && shortestAngle2 > marginRadians) ||
                                    (shortestAngle1 < -marginRadians && shortestAngle2 < -marginRadians)) selectAnim = false; // :726-729
                                if (Mathf.Abs(shortestAngle1) + Mathf.Abs(shortestAngle2) > Mathf.Pi + marginRadians)
                                    selectAnim = false; // :730
                            }
                        }
                    }
                    else // клип с idle-входом (:737-747)
                    {
                        if (query.IncomingBodyDirectionStrict)
                        {
                            if (Mathf.Abs(BluntMath.GetAngle2D(new Vector3(0, -1, 0), query.IncomingBodyDirection)) >
                                marginRadians) selectAnim = false; // :742
                        }
                        else if (Mathf.Abs(BluntMath.GetAngle2D(new Vector3(0, -1, 0), query.IncomingBodyDirection)) >
                                 0.25f * Mathf.Pi + marginRadians) selectAnim = false; // :744
                    }
                }

                // select by INCOMING BALL DIRECTION (:757-786)
                if (selectAnim && query.ByIncomingBallDirection)
                {
                    Vector3 animBallDirection = BluntMath.GetVectorFromString(anim.GetVariable("incomingballdirection"));
                    if (animBallDirection.Length() < 0.1f) // :760
                    {
                        // :761 в C++ фатал e_FatalError; в порте — предупреждение + отсев, без падения.
                        GD.PushError($"Gpf.AnimCollection: {anim.GetName()} missing incoming ball direction");
                        selectAnim = false;
                    }
                    else if (query.IncomingBallDirection.Length() != 0.0f) // :763
                    {
                        animBallDirection.Z *= 0.4f; // :766 decimate height diff
                        animBallDirection = animBallDirection.Normalized();
                        Vector3 adapted = query.IncomingBallDirection;
                        adapted.Z *= 0.4f; // :769
                        adapted = adapted.Normalized();
                        float ballDirectionAngle = Mathf.Abs(BluntMath.GetAngle2D(adapted, animBallDirection)); // :773
                        float maxDeviation = Mathf.Abs(
                            BluntMath.AtoF(anim.GetVariable("incomingballdirection_maxdeviation")) * Mathf.Pi); // :778
                        if (maxDeviation == 0.0f)
                        {
                            maxDeviation = MaxIncomingBallDirectionDeviation; // :780
                            if (animType == "deflect") maxDeviation = 0.4f * Mathf.Pi; // :781
                        }
                        if (ballDirectionAngle > maxDeviation) selectAnim = false; // :783
                    }
                }

                // select by OUTGOING BALL DIRECTION (:791-807)
                if (selectAnim && query.ByOutgoingBallDirection)
                {
                    Vector3 animBallDirection = BluntMath.GetVectorFromString(anim.GetVariable("balldirection"));
                    animBallDirection = BluntMath.GetNormalized(animBallDirection, Vector3.Zero); // :794
                    float ballDirectionAngle = Mathf.Abs(BluntMath.GetAngle2D(
                        BluntMath.GetNormalized(BluntMath.Get2D(query.OutgoingBallDirection), animBallDirection),
                        animBallDirection)); // :797
                    float maxDeviation = Mathf.Abs(
                        BluntMath.AtoF(anim.GetVariable("outgoingballdirection_maxdeviation")) * Mathf.Pi); // :801
                    if (maxDeviation == 0.0f) maxDeviation = MaxOutgoingBallDirectionDeviation; // :803
                    if (ballDirectionAngle > maxDeviation) selectAnim = false; // :805
                }

                // select by PROPERTIES (:812-819)
                if (selectAnim)
                {
                    if (query.GetProperty("incoming_special_state") != anim.GetVariable("incoming_special_state"))
                        selectAnim = false; // :813
                    // hax: разрешить смену рук (кроме deflect) (:815-816)
                    bool queryRetain = query.GetProperty("incoming_retain_state") != "";
                    bool animRetain = anim.GetVariable("incoming_retain_state") != "";
                    if ((query.FunctionTypeId == FnDeflect || queryRetain != animRetain) &&
                        query.GetProperty("incoming_retain_state") != anim.GetVariable("incoming_retain_state"))
                        selectAnim = false;
                    if (BluntMath.AtoF(query.GetProperty("specialvar1")) != BluntMath.AtoF(anim.GetVariable("specialvar1")))
                        selectAnim = false; // :817
                    if (BluntMath.AtoF(query.GetProperty("specialvar2")) != BluntMath.AtoF(anim.GetVariable("specialvar2")))
                        selectAnim = false; // :818
                }

                // select by TRIP TYPE (:824-828)
                if (selectAnim && query.ByTripType &&
                    Mathf.RoundToInt(BluntMath.AtoF(anim.GetVariable("triptype"))) != query.TripType) selectAnim = false;

                // select by FORCED FOOT (:834-857)
                if (selectAnim && query.HeedForcedFoot)
                {
                    string forcedFoot = anim.GetVariable("forcedfoot");
                    int which = forcedFoot == "strong" ? 1 : forcedFoot == "weak" ? 2 : 0; // :838-840
                    if (which != 0)
                    {
                        int animFoot = anim.GetVariable("touchfoot") == "left" ? 0 : 1; // e_Foot: left=0/right=1 (:843-845)
                        if (anim.GetCurrentFootId() == 0) animFoot = animFoot == 0 ? 1 : 0; // зеркальные (:848-850)
                        if (which == 1 && query.StrongFootId != animFoot) selectAnim = false; // :852
                        if (which == 2 && query.StrongFootId == animFoot) selectAnim = false; // :853
                    }
                }

                if (selectAnim) dataSet.Add(i); // :860
            }
        }
    }
}

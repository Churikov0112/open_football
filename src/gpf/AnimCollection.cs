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
        }

        // Задача 6 наполняет; сейчас — пусто, чтобы каркас собирался и тестировался.
        private void LoadTemplatesAndGenerate(string animationsRoot, Skeleton3D utilitySkeleton) { }

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
    }
}

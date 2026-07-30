using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // Порт варпинга траектории HumanoidBase::CalculatePhysicsVector (humanoidbase.cpp:2014-2544)
    // и его хелперов (humanoid_utils.cpp:68-100,129-144; playerbase.cpp:131-139).
    // Задача 2 — только статики; ядро Calculate приходит задачей 3.
    public partial class PhysicsVector : RefCounted
    {
        // humanoid_utils.cpp:68-100. Движение (м/с) в кадре frameNum по кэшу позиций корня.
        // Множитель 100.0f (:80,:84,:90) — дельта за кадр при 100 Гц анимации → м/с.
        // smoothFrames по умолчанию 0 — как в humanoid_utils.hpp:25.
        internal static Vector3 CalculateMovementAtFrame(List<Vector3> positions, int frameNum, int smoothFrames = 0)
        {
            // :79-81 — выходное движение без сглаживания (иначе неверная квантованная скорость).
            // Отклонение от оригинала: там `frameNum == positions.size() - 1` под защитой
            // `assert(frameNum < positions.size())` (:76); у нас `>=` вместо assert —
            // на легальном диапазоне поведение идентично.
            if (frameNum >= positions.Count - 1)
                return BluntMath.Get2D(positions[positions.Count - 1] - positions[positions.Count - 2]) * 100.0f;
            // :83-85 — для кадра 0 нельзя взять дельту -1→0, берём 0→1
            if (frameNum == 0)
                return BluntMath.Get2D(positions[1] - positions[0]) * 100.0f;

            Vector3 totalMovement = Vector3.Zero;                    // :87-97
            int count = 0;
            for (int frame = frameNum - smoothFrames; frame <= frameNum + smoothFrames; frame++)
            {
                // :89 — в оригинале было `frame > 1`, автор пометил как баг и исправил на `frame > 0`
                if (frame > 0 && frame < positions.Count)
                {
                    totalMovement += BluntMath.Get2D(positions[frame] - positions[frame - 1]) * 100.0f;
                    count++;
                }
            }
            if (count > 0) totalMovement /= count;
            return totalMovement;
        }

        // Мост для тестов: GDScript не умеет ни List<Vector3>, ни дефолт-аргументы C#.
        public static Vector3 CalculateMovementAtFrameArr(Godot.Collections.Array positions, int frameNum, int smoothFrames)
        {
            var list = new List<Vector3>();
            foreach (var p in positions) list.Add((Vector3)p);
            return CalculateMovementAtFrame(list, frameNum, smoothFrames);
        }

        // humanoid_utils.cpp:129-144 — растянуть спринтовую часть скорости под max игрока.
        // Ходьба (< walkSprintSwitch) не масштабируется, спринтовый «излишек» — линейно.
        // Оригинал держит `assert(targetMaxVelocity > walkSprintSwitch)` (:130) — не переносим.
        public static float StretchSprintTo(float inputVelocity, float inputSpaceMaxVelocity, float targetMaxVelocity)
        {
            if (inputVelocity < Velo.WalkSprintSwitch) return inputVelocity;    // :132
            float howMuchSprintage = inputVelocity - Velo.WalkSprintSwitch;     // :134
            float oldLength = inputSpaceMaxVelocity - Velo.WalkSprintSwitch;    // :136
            float newLength = targetMaxVelocity - Velo.WalkSprintSwitch;        // :137
            float toNewFactor = newLength / oldLength;                          // :139
            return Velo.WalkSprintSwitch + howMuchSprintage * toNewFactor;      // :141-143
        }

        // playerbase.cpp:131-139: GetMaxVelocity = sprintVelocity * GetVelocityMultiplier(),
        // где множитель = 0.9f + stat("physical_velocity") * 0.1f (:138); статы лежат в [0,1],
        // т.е. диапазон max-скорости — [7.2, 8.0] м/с.
        public static float GetMaxVelocity(float statVelocity)
            => Velo.Sprint * (0.9f + statVelocity * 0.1f);
    }
}

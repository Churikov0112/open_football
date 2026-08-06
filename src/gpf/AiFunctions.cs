using Godot;

namespace Gpf
{
    // Порт AI-слоя оригинала (src/onthepitch/AIsupport/AIfunctions.cpp) — по одной функции, по мере
    // надобности. Пока перенесён только магнит ведения: без него игрок с мячом бежит по сырой
    // стрелке, уходит от мяча боком и теряет его (вскрыто глазной приёмкой фазы 7).
    //
    // ШОВ MentalImage: оригинал спрашивает `mentalImage->GetBallPrediction(t)` — «мяч, каким игрок
    // его помнит». Порт всюду берёт объективный `Ball.Predict(t)`; это главное системное
    // приближение, оно уже задокументировано в [[расхождения-с-оригиналом]] и снимается фазой 8.
    //
    // `Match*`/`Player*` развёрнуты в плоские аргументы — тот же приём, что в `TouchVectors`.
    public partial class AiFunctions : RefCounted
    {
        // gamedefines.hpp:54 — «нужно проехать 4 метра → нужна скорость 4 × множитель»
        public const float DistanceToVelocityMultiplier = 2.6f;

        // Порт AI_GetBallControlMovement (AIfunctions.cpp:893-940).
        //
        // Ключевое, ради чего это переносится: направление бега берётся ОТ МЯЧА, а не от ввода.
        // Ввод игрока (`desiredDirection`) в теле функции не участвует вовсе — в оригинале на его
        // месте стоит текущее направление тела, а сам аргумент закомментирован (:912). Стрелка
        // человека при ведении рулит не бегом, а тем, куда ballcontrol-касание толкнёт мяч.
        //
        // Возврат оригинала — `player->GetTimeNeededToGetToBall_ms()` (сеттер-суррогат лабы, 0);
        // отдаём его же аргументом, чтобы не выдумывать значение.
        public static uint GetBallControlMovement(
            Ball ball, Vector3 playerPosition, Vector3 playerDirectionVec,
            Vector3 desiredDirection, float desiredVelocityFloat,
            out Vector3 bestDirection, out float bestVelocityFloat, out Vector3 bestLookAt,
            uint timeNeededToGetToBallMs = 0)
        {
            _ = desiredDirection; // :912 — оригинал его не читает, сигнатура сохранена

            uint desiredTimeToBallMs = 250 + (uint)GpfPitch.DefaultTouchOffsetMs; // :895

            Vector3 toBallMovement =
                BluntMath.Get2D(ball.Predict((int)desiredTimeToBallMs)) - playerPosition; // :897
            float toBallDistance = BluntMath.GetLength(toBallMovement);                   // :898

            // «это должно убрать артефакты на коротких дистанциях» (:900)
            float manualDirectionStartDistanceThreshold = 0.2f; // :901
            float manualDirectionEndDistanceThreshold = 0.4f;   // :902
            float autoDirectionBias = 1.0f;                     // :903
            if (toBallDistance < manualDirectionEndDistanceThreshold) // :904
            {
                autoDirectionBias = Mathf.Pow(
                    BluntMath.NormalizedClamp(toBallDistance,
                        manualDirectionStartDistanceThreshold,
                        manualDirectionEndDistanceThreshold), 0.5f); // :905-909
            }

            Vector3 autoDirection = BluntMath.GetNormalized(toBallMovement, playerDirectionVec); // :911
            Vector3 manualDirection = playerDirectionVec; // :912 — «desiredDirection» закомментирован
            // :913 — закомментированный тест оригинала:
            // if (player->GetDirectionVec().GetDotProduct(desiredDirection) < 0) manualDirection = desiredDirection;

            bestDirection = autoDirection * autoDirectionBias
                + manualDirection * (1.0f - autoDirectionBias);                    // :915
            bestDirection = BluntMath.GetNormalized(bestDirection, playerDirectionVec); // :916

            Vector3 bestLookDirection = bestDirection; // :920-921

            // скорость — от дистанции до мяча, ввод только ограничивает сверху (:923-935)
            float toBallVelocity = toBallDistance * DistanceToVelocityMultiplier; // :923
            bestVelocityFloat = toBallVelocity;                                   // :924

            // :926 — «квантование есть корень всякого счастья», строка закомментирована
            if (bestVelocityFloat < Velo.Dribble) // :927 — низкие скорости не квантуем
            {
                // :928 — тело закомментировано в оригинале (bestVelocityFloat = idleVelocity)
            }
            else
            {
                float clampedDesiredVelocityFloat = Mathf.Clamp(
                    desiredVelocityFloat, bestVelocityFloat, bestVelocityFloat + 8.0f); // :931
                bestVelocityFloat = clampedDesiredVelocityFloat;                        // :932
                if (Velo.RangeVelocity(bestVelocityFloat) < bestVelocityFloat)
                    bestVelocityFloat = bestVelocityFloat * 0.9f
                        + Velo.RangeVelocity(bestVelocityFloat) * 0.1f;                 // :933
                if (Velo.RangeVelocity(bestVelocityFloat) > bestVelocityFloat)
                    bestVelocityFloat = bestVelocityFloat * 0.1f
                        + Velo.RangeVelocity(bestVelocityFloat) * 0.9f;                 // :934
            }

            bestLookAt = playerPosition + bestLookDirection * 10.0f; // :937
            return timeNeededToGetToBallMs;                          // :939
        }

        // Порт хвоста PlayerController::_MovementCommand (playercontroller.cpp:590-601): смешивание
        // «авто» и «ручной» команд по autoBias. При владении мячом оригинал ставит autoBias = 1.0
        // (:483), то есть ручная команда не участвует вовсе — но смешивание переносится целиком,
        // потому что фазы 8-9 приведут сюда остальные ветки магнита с дробным bias.
        public static void BlendAutoMovement(
            Vector3 autoDirection, float autoVelocityFloat, Vector3 autoLookDirection,
            Vector3 manualDirection, float manualVelocityFloat, float autoBias,
            Vector3 playerPosition, Vector3 quantizedInputDirection,
            out Vector3 desiredDirection, out float desiredVelocityFloat, out Vector3 desiredLookAt)
        {
            Vector3 autoMovement = autoDirection * autoVelocityFloat;       // :591
            Vector3 manualMovement = manualDirection * manualVelocityFloat; // :592
            Vector3 resultingMovement =
                manualMovement * (1.0f - autoBias) + autoMovement * autoBias; // :593

            desiredDirection = BluntMath.GetNormalized(resultingMovement, quantizedInputDirection); // :594
            desiredVelocityFloat = Mathf.Clamp(
                BluntMath.GetLength(resultingMovement), Velo.Idle, Velo.Sprint);                   // :595

            // :597 — на скорости ниже порога дриблинга направление берётся из взгляда: иначе
            // почти стоящий игрок разворачивался бы по остаточному вектору движения
            if (desiredVelocityFloat < Velo.IdleDribbleSwitch) desiredDirection = autoLookDirection;

            desiredLookAt = playerPosition + autoLookDirection * 10.0f; // :599-600
        }

        // --- мост для GDScript-проверок: `out`-параметры через CSharpScript не ходят ---

        // [время до мяча, направление, скорость, точка взгляда]
        public static Godot.Collections.Array DescribeBallControlMovement(
            Ball ball, Vector3 playerPosition, Vector3 playerDirectionVec,
            Vector3 desiredDirection, float desiredVelocityFloat)
        {
            uint time = GetBallControlMovement(ball, playerPosition, playerDirectionVec,
                desiredDirection, desiredVelocityFloat,
                out Vector3 bestDirection, out float bestVelocityFloat, out Vector3 bestLookAt);
            return new Godot.Collections.Array { time, bestDirection, bestVelocityFloat, bestLookAt };
        }

        // [направление, скорость, точка взгляда]
        public static Godot.Collections.Array DescribeBlendAutoMovement(
            Vector3 autoDirection, float autoVelocityFloat, Vector3 autoLookDirection,
            Vector3 manualDirection, float manualVelocityFloat, float autoBias,
            Vector3 playerPosition, Vector3 quantizedInputDirection)
        {
            BlendAutoMovement(autoDirection, autoVelocityFloat, autoLookDirection,
                manualDirection, manualVelocityFloat, autoBias, playerPosition,
                quantizedInputDirection,
                out Vector3 desiredDirection, out float desiredVelocityFloat,
                out Vector3 desiredLookAt);
            return new Godot.Collections.Array
                { desiredDirection, desiredVelocityFloat, desiredLookAt };
        }
    }
}

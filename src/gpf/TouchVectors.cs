using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // Порт touch-векторов humanoid_utils.cpp (:32-38, :146-520) + Match::CheckBallCollisions
    // (match.cpp:1926-2045, класс BallBodyCollider ниже). Всё — статики, контекст приходит
    // параметрами (без глобалов); Match*/Player* оригинала развёрнуты в плоские аргументы.
    // Ссылки `:NNN` — humanoid_utils.cpp, если явно не указан другой файл.
    // Параметры оригинала, не читаемые в теле функции, СОХРАНЕНЫ в сигнатурах (1:1 маппинг на
    // C++-список аргументов для ревью) и явно погашены `_ = ...`.
    // Все random(a,b) оригинала — через инжектируемый GpfRng (global-constraints №3).
    public partial class TouchVectors : RefCounted
    {
        // ---- GetTouchTypeForBodyPart (:32-38) ----
        // Тип касания по имени части тела из anim-переменной "touch_bodypart".
        public static int GetTouchTypeForBodyPart(string bodypartName)
            => (bodypartName.Contains("foot") || bodypartName.Contains("lowerleg"))  // :33-34
                ? HumanoidBase.TouchTypeIntentionalKicked                            // :35
                : HumanoidBase.TouchTypeIntentionalNonkicked;                        // :37

        // ---- GetDifficultyFactors (:146-206) ----
        // Модель ошибки касания: насколько далеко/высоко мяч отскочит от ног и сколько текущего
        // движения мяча сохранится. В C++ контекст — Match*/Player*; здесь он развёрнут:
        //   playerMovement/playerPosition/playerDirectionVec — player->GetMovement()/GetPosition()/
        //     GetDirectionVec() (== spatialState гуманоида);
        //   positionOffsetLength — positionOffset.GetLength() (тело читает только длину, :154);
        //   lastOppTouchBias — ШОВ перехват-штрафа (:182-195): гейт «последней мяч трогала чужая
        //     команда» и lastTouchPlayer->GetLastTouchBias(1000 − reaction·500) живут в матч-слое —
        //     сюда приходит уже вычисленный биас (в лабе 0: соперников нет). При 0 штраф
        //     pow(0, 0.6)·5 == 0 — совпадает с непопаданием в ветку оригинала;
        //   statPhysicalReaction — окно распада вычисляет ВЫЗЫВАЮЩИЙ (матч-слой, задача 9+);
        //     здесь параметр не читается, оставлен для симметрии с C++ (:187).
        public static void GetDifficultyFactors(Ball ball, Vector3 playerMovement,
            Vector3 playerPosition, Vector3 playerDirectionVec, float positionOffsetLength,
            float statTechnicalBallControl, float lastOppTouchBias, float statPhysicalReaction,
            GpfRng rng, out float distanceFactor, out float heightFactor,
            out float ballMovementFactor)
        {
            _ = statPhysicalReaction; // см. шапку: окно распада — у вызывающего (:187)

            distanceFactor = 0.0f;     // :150 — насколько далеко мяч отскакивает от ног
            heightFactor = 0.0f;       // :151 — насколько высоко
            ballMovementFactor = 0.0f; // :152 — сколько текущего движения мяча сохраняется

            // толкучка — это тяжело (:153-154)
            float positionOffsetPenalty =
                BluntMath.NormalizedClamp(positionOffsetLength, 0.0f, 0.1f) * 2.0f; // :154 (was: 7.0f)
            // быстрые мячи труднее (:155-161)
            float ballBodyVeloPenalty = Mathf.Pow(BluntMath.NormalizedClamp(
                (playerMovement - ball.GetMovement()).Length(), 10.0f, 50.0f), 1.5f) * 5.0f;
            // мяч дальше от тела — труднее (:162-170)
            float fartherAwayPenalty = Mathf.Pow(BluntMath.NormalizedClamp(
                ((playerPosition + playerDirectionVec * 0.2f)
                 - BluntMath.Get2D(ball.Predict(0))).Length(), 0.7f, 1.3f), 2.0f) * 2.0f;

            distanceFactor += positionOffsetPenalty * 2.0f; // :173
            distanceFactor += ballBodyVeloPenalty;          // :174
            distanceFactor += fartherAwayPenalty * 4.0f;    // :175

            heightFactor += positionOffsetPenalty * 0.5f;   // :177
            heightFactor += ballBodyVeloPenalty * 2.0f;     // :178
            heightFactor += fartherAwayPenalty;             // :179

            // перехват пасов труднее (:181-195); ШОВ lastOppTouchBias — см. шапку
            float lastTouchBiasPenalty = Mathf.Pow(lastOppTouchBias, 0.6f) * 5.0f; // :185-189
            distanceFactor += lastTouchBiasPenalty;           // :191
            heightFactor += lastTouchBiasPenalty;             // :192
            ballMovementFactor += lastTouchBiasPenalty * 0.1f; // :193

            ballMovementFactor = Mathf.Clamp(ballMovementFactor, 0.0f, 0.9f); // :196

            float skillPenaltyMultiplier =
                (1.0f - statTechnicalBallControl * 0.5f) * rng.Uniform(0.5f, 1.0f); // :198
            distanceFactor *= skillPenaltyMultiplier;                       // :199
            heightFactor *= skillPenaltyMultiplier;                         // :200
            ballMovementFactor *= skillPenaltyMultiplier;                   // :201
            distanceFactor = Mathf.Clamp(distanceFactor, 0.0f, 1.0f);      // :202
            heightFactor = Mathf.Clamp(heightFactor, 0.0f, 1.0f);          // :203
            ballMovementFactor = Mathf.Clamp(ballMovementFactor, 0.0f, 1.0f); // :204
        }

        // ---- GetBallControlVector (:208-332) ----
        // Развёртка контекста C++ (Ball*, Player*, const Anim*, SpatialState):
        //   animOutgoingVelocity — currentAnim->anim->GetOutgoingVelocity() (:219, :230, :253);
        //   animEffectiveFrameCount/frameNum — тайминг клипа (:290);
        //   cmdDesiredDirection/cmdDesiredVelocityFloat — currentAnim->originatingCommand (:223-226, :235);
        //   spatialAngle/spatialDirectionVec/bodyDirectionVec — spatialState (:225, :252) и
        //     player->GetBodyDirectionVec() (:258);
        //   controllerVelocity — ШОВ player->GetController()->GetFloatVelocity() (:235): в лабе —
        //     желаемая скорость породившей команды (решение брифа);
        //   maxVelocity — player->GetMaxVelocity() (:241) == PhysicsVector.GetMaxVelocity(stat);
        //   closestOpponentDistance — player->GetClosestOpponentDistance() (:254), в лабе 1000;
        //   positionOffset — параметр оригинала, В ТЕЛЕ НЕ ЧИТАЕТСЯ (толкучка приходит через
        //     ffoOffset у trap-обёртки) — сохранён и погашен.
        public static Vector3 GetBallControlVector(Ball ball, Vector3 nextStartPos,
            float nextStartAngle, float nextBodyAngle, Vector3 outgoingMovement,
            float animOutgoingVelocity, int animEffectiveFrameCount, int frameNum,
            Vector3 cmdDesiredDirection, float cmdDesiredVelocityFloat,
            float spatialAngle, Vector3 spatialDirectionVec, Vector3 bodyDirectionVec,
            bool hasPossession, float controllerVelocity, float maxVelocity,
            float closestOpponentDistance, float statMentalCalmness, float statPhysicalBalance,
            float statTechnicalDribble, float statTechnicalBallControl, Vector3 positionOffset,
            out float xRot, out float yRot, float ffoOffset = 0.0f)
        {
            _ = positionOffset; // не читается в теле оригинала (см. шапку)

            // часть результата — физика, часть — клип/контроллер; originatingBias применяется
            // только к (1 − physicsBias)-части (:210-211)
            float physicsBias = 0.7f;                                          // :211
            if (!hasPossession) physicsBias = 0.9f;                            // :213-216
            if (Velo.FloatToEnumVelocity(animOutgoingVelocity) == Velo.IdVelIdle)
                physicsBias = 1.0f;                                            // :219

            float explosivenessFactor = 0.6f;                                  // :221
            float maximumOverdriveMps = 1.0f * explosivenessFactor;            // :222
            if (cmdDesiredVelocityFloat < Velo.DribbleWalkSwitch)
                maximumOverdriveMps = 0.0f;                                    // :223
            if (cmdDesiredVelocityFloat > Velo.WalkSprintSwitch)
                maximumOverdriveMps = 2.0f * explosivenessFactor;              // :224
            // inv-отклонение от текущего направления (:225) и от желаемого при выборе клипа (:226)
            float dotFactor1 = spatialDirectionVec.Dot(cmdDesiredDirection) * 0.5f + 0.5f;
            float dotFactor2 = BluntMath.GetRotated2D(new Vector3(0, -1, 0), nextStartAngle)
                .Dot(cmdDesiredDirection) * 0.5f + 0.5f;
            float dotFactor = Mathf.Min(dotFactor1, dotFactor2);               // :227
            maximumOverdriveMps *= dotFactor;                                  // :228

            if (Velo.FloatToEnumVelocity(animOutgoingVelocity) == Velo.IdVelIdle)
                maximumOverdriveMps = 0.0f;                                    // :230

            float originatingBias = 0.7f;                                      // :232

            // скорость — микс команды и контроллера (:234-235)
            Vector3 desiredMovement = cmdDesiredDirection
                * (cmdDesiredVelocityFloat * originatingBias
                   + controllerVelocity * (1.0f - originatingBias));           // :235

            // держим не выше max-скорости игрока — иначе медленные игроки бьют мяч слишком
            // далеко (:240-241)
            if (desiredMovement.Length() > Velo.WalkSprintSwitch)
                desiredMovement = BluntMath.GetNormalized(desiredMovement, Vector3.Zero)
                    * PhysicsVector.StretchSprintTo(desiredMovement.Length(), Velo.Sprint,
                        maxVelocity);                                          // :241

            // не ниже физической скорости (переедем мяч), не сильно выше (мяч убежит) (:243-247)
            float velocity = Mathf.Clamp(desiredMovement.Length(), outgoingMovement.Length(),
                outgoingMovement.Length() + maximumOverdriveMps);              // :245
            desiredMovement = BluntMath.GetNormalized(desiredMovement,
                BluntMath.GetRotated2D(new Vector3(0, -1, 0), nextStartAngle)) * velocity; // :246
            Vector3 physicsMovement =
                BluntMath.GetRotated2D(new Vector3(0, -1, 0), nextStartAngle) * velocity;  // :247

            float desiredVelocity = desiredMovement.Length();                  // :249
            float physicsVelocity = physicsMovement.Length();                  // :250

            Vector3 ffoSrc = HumanoidBase.GetFrontOfFootOffsetRel(physicsVelocity,
                nextBodyAngle - spatialAngle, ball.Predict(0).Z);              // :252
            // к низким скоростям эффект не применяем — слишком хаотично (:253)
            float annoyanceVeloFactor = BluntMath.Curve(
                BluntMath.NormalizedClamp(animOutgoingVelocity, Velo.Idle, Velo.Sprint), 0.7f);
            float opponentAnnoyanceFactor =
                (1.0f - BluntMath.NormalizedClamp(closestOpponentDistance, 0.5f, 1.5f))
                * (1.0f - (statMentalCalmness * 0.5f + statPhysicalBalance * 0.3f))
                * annoyanceVeloFactor;                                         // :254
            // positionOffset уже в ffoOffset (пока только у trap) — комментарий оригинала (:255)
            Vector3 ffo = BluntMath.GetRotated2D(new Vector3(0, -1, 0), nextBodyAngle)
                * (ffoSrc.Length() + ffoOffset + opponentAnnoyanceFactor * 3.0f); // :255
            // высокие мячи отскакивают от корпуса — иначе застревают в теле (:256)
            float heightFFOOffset =
                BluntMath.NormalizedClamp(ball.Predict(0).Z, 0.5f, 1.0f) * 0.5f;  // :256
            ffo += ffoSrc * heightFFOOffset * 0.5f
                + bodyDirectionVec * heightFFOOffset * 0.5f;                   // :257-258

            Vector3 desiredPlannedBallPos = nextStartPos;                      // :260
            Vector3 physicsPlannedBallPos = nextStartPos;                      // :261

            // мяч должен оказаться дальше нашей следующей позиции — коснёмся его снова через
            // несколько шагов (:263-273)
            float desiredDelayTime = Mathf.Pow(
                BluntMath.NormalizedClamp(desiredVelocity, 0.0f, Velo.Sprint), 2.0f)
                * 0.60f + 0.25f;                                               // :264-268
            float physicsDelayTime = Mathf.Pow(
                BluntMath.NormalizedClamp(physicsVelocity, 0.0f, Velo.Sprint), 2.0f)
                * 0.60f + 0.25f;                                               // :269-273
            desiredPlannedBallPos += desiredMovement * desiredDelayTime + ffo; // :276
            physicsPlannedBallPos += physicsMovement * physicsDelayTime + ffo; // :277

            Vector3 plannedBallPos = physicsPlannedBallPos * physicsBias
                + desiredPlannedBallPos * (1.0f - physicsBias);                // :287
            Vector3 toPlannedBall = plannedBallPos - BluntMath.Get2D(ball.Predict(0)); // :288

            float timeToGo = ((animEffectiveFrameCount - frameNum) * 10) * 0.001f; // :290
            timeToGo += physicsDelayTime * physicsBias
                + desiredDelayTime * (1.0f - physicsBias);                     // :291
            // время в следующем клипе, когда хотим коснуться мяча (:292)
            timeToGo += GpfPitch.DefaultTouchOffsetMs * 0.001f;

            float divisor = timeToGo * (0.38f + 0.02f * statTechnicalDribble); // :294 — выше == ближе
            divisor *= 1.1f;                                                   // :295

            // pow-магия: на высоких скоростях мяч и тормозит быстрее (:297-298)
            float power = Mathf.Pow(toPlannedBall.Length() / divisor, 0.7f);   // :298
            Vector3 direction = BluntMath.GetNormalized(toPlannedBall,
                BluntMath.GetRotated2D(new Vector3(0, -1, 0), nextBodyAngle)); // :299

            float height = Mathf.Clamp(0.1f + 1.5f * Mathf.Pow(power / 10.0f, 1.6f),
                0.0f, 1.5f);                                                   // :305-306 (power ~= 0..10)

            float powerMultiplier = 1.2f - (statTechnicalBallControl * 0.03f); // :309
            // множитель применяется только к высоким скоростям (:310-311)
            float veloBias = BluntMath.NormalizedClamp(velocity, Velo.Walk, Velo.Sprint - 0.8f);
            powerMultiplier = 1.0f * (1.0f - veloBias) + powerMultiplier * veloBias; // :311

            Vector3 touchVec = direction * power * powerMultiplier
                + new Vector3(0, 0, height);                                   // :313

            float backspinFactor = 30.0f;                                      // :321
            float velo = touchVec.Length();                                    // :322
            float veloFactor = Mathf.Pow(
                BluntMath.NormalizedClamp(touchVec.Length(), 0.0f, 10.0f), 0.7f); // :323-325
            Vector3 spinMix = BluntMath.GetNormalized(
                BluntMath.GetNormalized(ffo, Vector3.Zero) * 0.6f
                + BluntMath.GetNormalized(touchVec, Vector3.Zero) * 0.4f, Vector3.Zero); // :326-327
            xRot = spinMix.Y * ((2f * Mathf.Pi * velo) - (backspinFactor * veloFactor)); // :326
            yRot = spinMix.X * ((2f * Mathf.Pi * velo) - (backspinFactor * veloFactor)); // :327

            return touchVec;                                                   // :331
        }

        // ---- GetTrapVector (:334-352) ----
        // GetDifficultyFactors → GetBallControlVector(ffoOffset = distanceFactor) → надбавка
        // высоты → микс с текущим движением мяча. Дополнительные к ballcontrol параметры —
        // контекст GetDifficultyFactors (см. её шапку); positionOffset здесь ЧИТАЕТСЯ (:341).
        public static Vector3 GetTrapVector(Ball ball, Vector3 nextStartPos,
            float nextStartAngle, float nextBodyAngle, Vector3 outgoingMovement,
            float animOutgoingVelocity, int animEffectiveFrameCount, int frameNum,
            Vector3 cmdDesiredDirection, float cmdDesiredVelocityFloat,
            float spatialAngle, Vector3 spatialDirectionVec, Vector3 bodyDirectionVec,
            bool hasPossession, float controllerVelocity, float maxVelocity,
            float closestOpponentDistance, float statMentalCalmness, float statPhysicalBalance,
            float statTechnicalDribble, float statTechnicalBallControl,
            Vector3 playerMovement, Vector3 playerPosition, Vector3 positionOffset,
            float lastOppTouchBias, float statPhysicalReaction, GpfRng rng,
            out float xRot, out float yRot)
        {
            // :338-341 — порядок СВЯЩЕННЫЙ: сначала GetDifficultyFactors (единственный вызов rng
            // здесь), затем GetBallControlVector с ffoOffset = distanceFactor
            GetDifficultyFactors(ball, playerMovement, playerPosition, spatialDirectionVec,
                positionOffset.Length(), statTechnicalBallControl, lastOppTouchBias,
                statPhysicalReaction, rng, out float distanceFactor, out float heightFactor,
                out float ballMovementFactor);                                 // :341

            // базовый вектор (:343-344)
            Vector3 ballControl = GetBallControlVector(ball, nextStartPos, nextStartAngle,
                nextBodyAngle, outgoingMovement, animOutgoingVelocity, animEffectiveFrameCount,
                frameNum, cmdDesiredDirection, cmdDesiredVelocityFloat, spatialAngle,
                spatialDirectionVec, bodyDirectionVec, hasPossession, controllerVelocity,
                maxVelocity, closestOpponentDistance, statMentalCalmness, statPhysicalBalance,
                statTechnicalDribble, statTechnicalBallControl, positionOffset,
                out xRot, out yRot, distanceFactor);                           // :344

            ballControl.Z += ball.GetMovement().Z * heightFactor * 1.0f
                + heightFactor * 4.0f;                                         // :346-347

            return ballControl * (1.0f - ballMovementFactor)
                + ball.GetMovement() * ballMovementFactor;                     // :349-350
        }

        // ---- GetShotVector (:354-520) ----
        // Развёртка контекста:
        //   nextStartPos/nextStartAngle/nextBodyAngle/outgoingMovement — параметры оригинала,
        //     В ТЕЛЕ НЕ ЧИТАЮТСЯ — сохранены и погашены;
        //   origPositionCache/frameNum — match->GetAnimPositionCache(anim) + currentAnim->frameNum (:358-359);
        //   tiDesiredDirection/tiDesiredPower — originatingCommand.touchInfo (:371, :404, :458 и далее);
        //   positionOffsetLength — positionOffset.GetLength() (:391, :433);
        //   animTouchMaxPowerFactorRaw — atof(anim var "touch_maxpowerfactor") (:408), 0 → 1 внутри;
        //   autoDirectionBias — параметр оригинала, в теле не читается (рефайн направления жил
        //     в вызывающем коде через AI_GetShotDirection и не портируется — решение плана).
        // RNG: 7 вызовов — 3 на random-направление worst case (:474; порядок вычисления
        //   аргументов Vector3(...) в C++ не специфицирован — фиксируем X, Y, Z), 1 на
        //   worstCaseFactor (:491), по 1 на xRot/yRot (:505-506), 1 на zRot (:515).
        public static Vector3 GetShotVector(Ball ball, Vector3 nextStartPos,
            float nextStartAngle, float nextBodyAngle, Vector3 outgoingMovement,
            List<Vector3> origPositionCache, int frameNum,
            float spatialAngle, Vector3 spatialDirectionVec, Vector3 spatialBodyDirectionVec,
            float cmdDesiredVelocityFloat, Vector3 tiDesiredDirection, float tiDesiredPower,
            float positionOffsetLength, float animTouchMaxPowerFactorRaw,
            float statPhysicalShotPower, float statTechnicalVolley, float statTechnicalShot,
            GpfRng rng, out float xRot, out float yRot, out float zRot,
            float autoDirectionBias = 0.0f)
        {
            _ = nextStartPos; _ = nextStartAngle; _ = nextBodyAngle; _ = outgoingMovement;
            _ = autoDirectionBias; // не читаются в теле оригинала (см. шапку)

            // spatialState.movement ненадёжен из-за смагглов — движение из кэша клипа (:358-359)
            Vector3 touchMovement = BluntMath.GetRotated2D(
                PhysicsVector.CalculateMovementAtFrame(origPositionCache, frameNum),
                spatialAngle);                                                 // :359
            Vector3 touchDirection =
                BluntMath.GetNormalized(touchMovement, spatialDirectionVec);   // :361
            float touchVelocity = touchMovement.Length();                      // :362
            if (Velo.FloatToEnumVelocity(touchVelocity) == Velo.IdVelIdle)
                touchDirection = spatialDirectionVec;                          // :363

            // :366 — вычислен и дальше не используется, как в оригинале
            float expressionModifierFactor = BluntMath.NormalizedClamp(
                cmdDesiredVelocityFloat, Velo.Idle, Velo.Sprint);
            _ = expressionModifierFactor;

            // идеальный угол ~36° == 0.2π (:369-375)
            float idealAngle = 0.2f * Mathf.Pi;                                // :370
            float angle1 = Mathf.Abs(BluntMath.GetAngle2D(touchDirection,
                BluntMath.GetRotated2D(tiDesiredDirection, -idealAngle)));     // :371
            float angle2 = Mathf.Abs(BluntMath.GetAngle2D(touchDirection,
                BluntMath.GetRotated2D(tiDesiredDirection, idealAngle)));      // :372
            float angle = Mathf.Min(angle1, angle2);                           // :373
            float directionFactor = Mathf.Clamp(angle / Mathf.Pi, 0.0f, 1.0f); // :374
            directionFactor = BluntMath.Curve(1.0f - directionFactor, 0.8f);   // :375

            // сила: желаемая как максимум, вычеты за движение игрока/мяча и т.п. (:379-421)

            // вбок бить всё ещё довольно легко (:381-383)
            float playerDirDesiredDirPowerFactor = Mathf.Pow(directionFactor, 0.8f);
            // >= скорость ходьбы — оптимум (:386-388)
            float playerVelocityPowerFactor = Mathf.Pow(
                BluntMath.NormalizedClamp(touchVelocity, 0.0f, Velo.Sprint), 0.3f);
            float positionOffsetPowerFactor =
                1.0f - BluntMath.NormalizedClamp(positionOffsetLength, 0.0f, 0.1f); // :391

            float powerFactor = 1.0f *
                (0.7f + playerDirDesiredDirPowerFactor * 0.3f) *
                (0.7f + playerVelocityPowerFactor * 0.3f) *
                (0.4f + positionOffsetPowerFactor * 0.6f);                     // :394-397
            powerFactor = Mathf.Clamp(powerFactor, 0.0f, 1.0f);               // :398

            float adaptedDesiredPower = 45.0f *
                (0.7f + Mathf.Pow(tiDesiredPower, 0.5f) * 0.3f);               // :401-405

            float animMaxPowerFactor = animTouchMaxPowerFactorRaw;             // :408
            if (animMaxPowerFactor == 0.0f) animMaxPowerFactor = 1.0f;         // :409

            float power = Mathf.Clamp(powerFactor * adaptedDesiredPower, 0.0f,
                (32.0f + statPhysicalShotPower * 13.0f)
                * (0.2f + animMaxPowerFactor * 0.8f));                         // :412

            // после стат-клампа: использование текущего движения мяча — бонус для всех (:414-419)
            float playerMovBallMovPowerFactor =
                (touchMovement - ball.GetMovement()).Length();                 // :415
            playerMovBallMovPowerFactor =
                BluntMath.NormalizedClamp(playerMovBallMovPowerFactor, 0.0f, 10.0f); // :416
            power *= 1.0f + playerMovBallMovPowerFactor * 0.2f;                // :419

            // сложность: желаемая сила, движение, скилл, толкучка и т.п. (:424-452)

            // вбок целиться всё ещё довольно легко (:426-427)
            float playerDirDesiredDirEasinessFactor = Mathf.Pow(directionFactor, 0.8f);
            // скорость дриблинга — оптимум (:430)
            float playerVelocityEasinessFactor = 1.0f - BluntMath.NormalizedClamp(
                Mathf.Abs(touchVelocity - Velo.Dribble), 0.0f, 4.0f);
            float positionOffsetEasinessFactor =
                1.0f - BluntMath.NormalizedClamp(positionOffsetLength, 0.0f, 0.1f); // :433

            // :436-437 — КВИРК оригинала: первое присваивание (длина разности движений) тут же
            // ПЕРЕЗАПИСЫВАЕТСЯ формулой от powerFactor'а — мёртвый код, переносится как есть
            float playerMovBallMovEasinessFactor =
                (touchMovement - ball.GetMovement()).Length();                 // :436
            playerMovBallMovEasinessFactor = 1.0f - playerMovBallMovPowerFactor
                * (0.5f - statTechnicalVolley * 0.3f);                         // :437

            float powerEasinessFactor = 1.0f - BluntMath.NormalizedClamp(power, 30.0f, 100.0f); // :440
            powerEasinessFactor = BluntMath.Curve(powerEasinessFactor, 1.0f);  // :441

            float easinessFactor = 1.0f *
                (0.4f + playerDirDesiredDirEasinessFactor * 0.6f) *
                (0.7f + playerVelocityEasinessFactor * 0.3f) *
                (0.3f + positionOffsetEasinessFactor * 0.7f) *
                (0.6f + playerMovBallMovEasinessFactor * 0.4f) *
                (0.6f + powerEasinessFactor * 0.4f);                           // :444-449
            float difficultyFactor = Mathf.Clamp(1.0f - easinessFactor, 0.0f, 1.0f); // :450

            // best case (:455-458)
            float desiredHeight = 0.05f;                                       // :457
            Vector3 desiredShot = BluntMath.GetNormalized(
                BluntMath.Get2D(tiDesiredDirection) + new Vector3(0, 0, desiredHeight),
                Vector3.Zero) * power;                                         // :458

            // worst case (:465-482)
            Vector3 worstCaseDirection = BluntMath.Get2D(tiDesiredDirection);  // :467

            // запаздывание направления (:469-471)
            float laggyDirectionBias = difficultyFactor * 0.8f;                // :470
            worstCaseDirection = BluntMath.GetNormalized(
                touchDirection * laggyDirectionBias
                + worstCaseDirection * (1.0f - laggyDirectionBias), Vector3.Zero); // :471

            // случайное направление (:473-475); порядок rng-вызовов фиксирован X, Y, Z (см. шапку)
            float rndX = rng.Uniform(-1f, 1f);
            float rndY = rng.Uniform(-1f, 1f);
            float rndZ = rng.Uniform(-1f, 1f);
            worstCaseDirection = worstCaseDirection
                + (new Vector3(rndX, rndY, rndZ) * 0.5f * difficultyFactor);   // :474
            worstCaseDirection = BluntMath.GetNormalized(worstCaseDirection, Vector3.Zero); // :475

            float worstCaseHeight =
                BluntMath.Curve(Mathf.Pow(difficultyFactor, 0.7f), 0.7f) * 0.7f; // :477

            float worstCasePower =
                power * (1.0f - Mathf.Pow(difficultyFactor, 0.7f) * 0.5f);     // :479-480

            Vector3 worstCaseShot = BluntMath.GetNormalized(
                worstCaseDirection + new Vector3(0, 0, worstCaseHeight), Vector3.Zero)
                * worstCasePower;                                              // :482

            // actual result (:489-496)
            float worstCaseFactor = rng.Uniform(0.0f, 1.0f);                   // :491
            worstCaseFactor = Mathf.Pow(worstCaseFactor, statTechnicalShot * 0.7f); // :492-493

            Vector3 shot = desiredShot * (1.0f - worstCaseFactor)
                + worstCaseShot * worstCaseFactor;                             // :495-496

            // немного кривизны (:499-515)
            float randomCurveFactor = 0.3f + worstCaseFactor * 0.7f;           // :501
            float plannedCurveFactor = 0.7f; // :502 — todo оригинала: кривизна как план, не рандом

            // «кривизна» вперёд/назад (:504-506)
            xRot = -tiDesiredDirection.Y * 20.0f
                + (rng.Uniform(-20f, 20f) * randomCurveFactor);                // :505
            yRot = -tiDesiredDirection.X * 20.0f
                + (rng.Uniform(-20f, 20f) * randomCurveFactor);                // :506

            // боковая кривизна (:508-515)
            float bodyTouchAngle = BluntMath.GetAngle2D(spatialBodyDirectionVec, shot) / Mathf.Pi; // :509
            if (Mathf.Abs(bodyTouchAngle) > 0.5f)
                bodyTouchAngle = (1.0f - Mathf.Abs(bodyTouchAngle))
                    * BluntMath.SignSide(bodyTouchAngle);                      // :510
            bodyTouchAngle *= 2.0f;                                            // :511
            float amount = bodyTouchAngle * 0.25f;                             // :513
            shot = BluntMath.GetRotated2D(shot, amount
                * (0.4f + 0.6f * BluntMath.NormalizedClamp(shot.Length(), 0.0f, 70.0f))); // :514
            zRot = amount * -420f + (rng.Uniform(-20f, 20f) * plannedCurveFactor); // :515

            return shot;                                                       // :519
        }

        // ---- Мосты для GDScript-тестов ----
        // Сигнатуры мостов фиксирует реализация (бриф); методы с out-параметрами через мост не
        // ходят — выходы в Dictionary; лаб-дефолты контекста прописаны здесь.

        public static Godot.Collections.Dictionary GetDifficultyFactorsBridge(Ball ball,
            Vector3 playerMovement, Vector3 playerPosition, Vector3 playerDirectionVec,
            float positionOffsetLength, float statTechnicalBallControl, float lastOppTouchBias,
            float statPhysicalReaction, GpfRng rng)
        {
            GetDifficultyFactors(ball, playerMovement, playerPosition, playerDirectionVec,
                positionOffsetLength, statTechnicalBallControl, lastOppTouchBias,
                statPhysicalReaction, rng, out float distance, out float height,
                out float ballMovement);
            return new Godot.Collections.Dictionary
            {
                { "distance", distance },
                { "height", height },
                { "ball_movement", ballMovement },
            };
        }

        // Лаб-мост GetBallControlVector: одинокий игрок в начале координат, направление/скорость —
        // аргументами, остальной контекст — дефолты лабы (статы 0.6, без соперников, движение
        // игрока и клипа совпадают с желаемым). rng принят для единообразия мостов —
        // GetBallControlVector случайности не содержит.
        public static Vector3 GetBallControlVectorBridge(Ball ball, Vector3 desiredDirection,
            float desiredVelocityFloat, GpfRng rng)
        {
            _ = rng; // случайности в GetBallControlVector нет
            float startAngle = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi,
                BluntMath.FixAngle(BluntMath.GetAngle2D(desiredDirection)));
            return GetBallControlVector(ball,
                nextStartPos: Vector3.Zero, nextStartAngle: startAngle, nextBodyAngle: startAngle,
                outgoingMovement: desiredDirection * desiredVelocityFloat,
                animOutgoingVelocity: desiredVelocityFloat,
                animEffectiveFrameCount: 20, frameNum: 0,
                cmdDesiredDirection: desiredDirection,
                cmdDesiredVelocityFloat: desiredVelocityFloat,
                spatialAngle: startAngle, spatialDirectionVec: desiredDirection,
                bodyDirectionVec: desiredDirection,
                hasPossession: true, controllerVelocity: desiredVelocityFloat,
                maxVelocity: PhysicsVector.GetMaxVelocity(0.6f),
                closestOpponentDistance: 1000.0f, statMentalCalmness: 0.6f,
                statPhysicalBalance: 0.6f, statTechnicalDribble: 0.6f,
                statTechnicalBallControl: 0.6f, positionOffset: Vector3.Zero,
                out _, out _, ffoOffset: 0.0f);
        }

        // Лаб-мост GetShotVector: args — Dictionary с ключами "desired_direction" (Vector3),
        // "desired_power" (float), "touch_velocity" (Vector3, движение игрока в кадр касания).
        // Синтетический кэш из двух позиций даёт CalculateMovementAtFrame(cache, 0) ==
        // touch_velocity (спецветка кадра 0: (p1 − p0)·100, humanoid_utils.cpp:83-85).
        public static Vector3 GetShotVectorBridge(Ball ball,
            Godot.Collections.Dictionary args, GpfRng rng)
        {
            Vector3 desiredDirection = args.TryGetValue("desired_direction", out var dd)
                ? (Vector3)dd : new Vector3(0, -1, 0);
            float desiredPower = args.TryGetValue("desired_power", out var dp)
                ? (float)dp : 1.0f;
            Vector3 touchVelocity = args.TryGetValue("touch_velocity", out var tv)
                ? (Vector3)tv : Vector3.Zero;

            var cache = new List<Vector3> { Vector3.Zero, touchVelocity * 0.01f };
            return GetShotVector(ball,
                nextStartPos: Vector3.Zero, nextStartAngle: 0f, nextBodyAngle: 0f,
                outgoingMovement: touchVelocity,
                origPositionCache: cache, frameNum: 0,
                spatialAngle: 0f, spatialDirectionVec: new Vector3(0, -1, 0),
                spatialBodyDirectionVec: new Vector3(0, -1, 0),
                cmdDesiredVelocityFloat: touchVelocity.Length(),
                tiDesiredDirection: desiredDirection, tiDesiredPower: desiredPower,
                positionOffsetLength: 0f, animTouchMaxPowerFactorRaw: 0f,
                statPhysicalShotPower: 0.6f, statTechnicalVolley: 0.6f, statTechnicalShot: 0.6f,
                rng, out _, out _, out _, autoDirectionBias: 0.0f);
        }

        // Лаб-мост BallBodyCollider.Check: сегменты костей — плоский массив Vector3 (пары
        // [начало, конец]); выходы — в Dictionary. Регистрацию случайного касания
        // (SetLastTouchPlayer, match.cpp:2006) выполняет вызывающий по флагу "accidental_touch".
        public static Godot.Collections.Dictionary CheckBallCollisionsBridge(Ball ball,
            Godot.Collections.Array boneSegmentEndpoints, Vector3 playerPosition,
            Vector3 playerMovement, int currentFunctionType, bool hasPossession,
            bool hasUniquePossession, bool isDesignatedTeamPossessionPlayer,
            float lastTouchBias, float oppLastTouchBias, float oppLastTouchBiasLong,
            float matchLastTouchBias, float unexpectedDistance,
            long actualTimeMs, long lastBodyBallCollisionTimeMs, GpfRng rng)
        {
            var endpoints = new List<Vector3>();
            foreach (var p in boneSegmentEndpoints) endpoints.Add((Vector3)p);
            long cooldown = lastBodyBallCollisionTimeMs;
            bool touched = BallBodyCollider.Check(ball, endpoints, playerPosition, playerMovement,
                currentFunctionType, hasPossession, hasUniquePossession,
                isDesignatedTeamPossessionPlayer, lastTouchBias, oppLastTouchBias,
                oppLastTouchBiasLong, matchLastTouchBias, unexpectedDistance, actualTimeMs,
                ref cooldown, rng, out bool controlled, out bool accidental);
            return new Godot.Collections.Dictionary
            {
                { "touched", touched },
                { "controlled_collision", controlled },
                { "accidental_touch", accidental },
                { "last_collision_time_ms", cooldown },
            };
        }
    }

    // ---- BallBodyCollider — порт Match::CheckBallCollisions (match.cpp:1926-2045) ----
    // Специализация под ОДНОГО игрока лаборатории: цикл по игрокам (:1943) выполняет вызывающий,
    // аккумулятор bounceVec/bias при одном игроке эквивалентен оригиналу. Геометрия тела —
    // AABB по сегментам костей утилитарного скелета: AABB сегмента = min/max его концов
    // ± паддинг 0.12 (решение п.7 скоупа плана; в оригинале — AABB геометрии узлов тела).
    // Не Godot-класс: GDScript ходит через TouchVectors.CheckBallCollisionsBridge.
    public static class BallBodyCollider
    {
        public const float BonePadding = 0.12f; // решение п.7 скоупа плана

        // aabb.cpp:130-143 AABB::Intersects(center, radius) — сфера против AABB по сумме
        // квадратов выходов за грани; d <= r² (отрицательный radius даёт r² > 0 — как в C++).
        private static bool AabbIntersectsSphere(Vector3 mn, Vector3 mx, Vector3 center,
            float radius)
        {
            float d = 0f;
            for (int i = 0; i < 3; i++)
            {
                float c = center[i];
                if (c < mn[i]) { float s = c - mn[i]; d += s * s; }
                else if (c > mx[i]) { float s = c - mx[i]; d += s * s; }
            }
            return d <= radius * radius;
        }

        // Контекст (в C++ — Match/Team/Player, окна биасов вычислял матч):
        //   boneSegmentEndpoints — плоские пары [начало, конец] сегментов костей (мировые);
        //   lastTouchBias — players[i]->GetLastTouchBias(200) (:1948-1950);
        //   oppLastTouchBias — GetTeam(opp)->GetLastTouchBias(200) (:1949), в лабе 0;
        //   oppLastTouchBiasLong — GetTeam(opp)->GetLastTouchBias(1600) (:1951) — вычислен и НЕ
        //     используется в оригинале, параметр сохранён и погашен;
        //   matchLastTouchBias — match GetLastTouchBias(200) (:1996);
        //   unexpectedDistance — ШОВ MentalImage (:1962): |предсказание в памяти − реальное|;
        //     с нулевой задержкой восприятия лабы всегда 0 → directionChangedUnexpectedly=false;
        //   controlledCollisionTriggered — players[i]->TriggerControlledBallCollision() (:1998),
        //     флаг гуманоиду выставляет вызывающий;
        //   accidentalTouch — SetLastTouchPlayer(Accidental) (:2006), регистрирует вызывающий.
        // Возвращает true, если мяч был затронут (:2024-2042).
        public static bool Check(Ball ball, List<Vector3> boneSegmentEndpoints,
            Vector3 playerPosition, Vector3 playerMovement, int currentFunctionType,
            bool hasPossession, bool hasUniquePossession, bool isDesignatedTeamPossessionPlayer,
            float lastTouchBias, float oppLastTouchBias, float oppLastTouchBiasLong,
            float matchLastTouchBias, float unexpectedDistance, long actualTimeMs,
            ref long lastBodyBallCollisionTimeMs, GpfRng rng,
            out bool controlledCollisionTriggered, out bool accidentalTouch)
        {
            controlledCollisionTriggered = false;
            accidentalTouch = false;
            _ = oppLastTouchBiasLong; // :1951 — вычислен и не используется, как в оригинале

            if (actualTimeMs <= lastBodyBallCollisionTimeMs + 150) return false; // :1931 — кулдаун

            Vector3 bounceVec = Vector3.Zero; // :1938
            float bias = 0.0f;                // :1939
            int bounceCount = 0;              // :1940

            // нельзя столкнуться, если соперник не касался мяча недавно (мы бы его предсказали)
            // или если игрок сам недавно касался (perpetuum collision + место для controlled
            // collisions гуманоида) (:1953)
            if (lastTouchBias <= 0.01f && oppLastTouchBias > 0.01f)
            {
                bool collisionAnim =
                    currentFunctionType == AnimCollection.FnMovement ||
                    currentFunctionType == AnimCollection.FnTrip ||
                    currentFunctionType == AnimCollection.FnSliding ||
                    currentFunctionType == AnimCollection.FnInterfere ||
                    currentFunctionType == AnimCollection.FnDeflect;           // :1955-1956
                bool onlyWhenDirectionChangedUnexpectedly =
                    currentFunctionType == AnimCollection.FnInterfere ||
                    currentFunctionType == AnimCollection.FnDeflect;           // :1957-1958

                bool directionChangedUnexpectedly = false;                     // :1960
                if (onlyWhenDirectionChangedUnexpectedly)                      // :1961
                {
                    if (unexpectedDistance > 0.5f) directionChangedUnexpectedly = true; // :1962-1963
                }

                if (collisionAnim && !hasUniquePossession &&
                    (onlyWhenDirectionChangedUnexpectedly == directionChangedUnexpectedly)) // :1972
                {
                    // фейковый размер AABB: больше — блоки веселее, меньше — меньше отскоков (:1974)
                    float boundingBoxSizeOffset = -0.1f;
                    if (!hasPossession) boundingBoxSizeOffset += 0.03f;
                    else boundingBoxSizeOffset -= 0.03f;                       // :1975-1976

                    if (currentFunctionType == AnimCollection.FnSliding ||
                        currentFunctionType == AnimCollection.FnInterfere)
                        boundingBoxSizeOffset += 0.1f;                         // :1978-1980
                    if (currentFunctionType == AnimCollection.FnDeflect)
                        boundingBoxSizeOffset += 0.2f;                         // :1981-1983

                    // premature optimization is the root of all evil :D (:1985)
                    if (((playerPosition + new Vector3(0, 0, 0.8f)) - ball.Predict(0)).Length()
                        < 2.5f)
                    {
                        for (int s = 0; s + 1 < boneSegmentEndpoints.Count; s += 2) // :1988-1989
                        {
                            Vector3 a = boneSegmentEndpoints[s];
                            Vector3 b = boneSegmentEndpoints[s + 1];
                            // AABB сегмента: min/max концов ± паддинг (решение п.7 скоупа)
                            Vector3 mn = new Vector3(
                                Mathf.Min(a.X, b.X) - BonePadding,
                                Mathf.Min(a.Y, b.Y) - BonePadding,
                                Mathf.Min(a.Z, b.Z) - BonePadding);
                            Vector3 mx = new Vector3(
                                Mathf.Max(a.X, b.X) + BonePadding,
                                Mathf.Max(a.Y, b.Y) + BonePadding,
                                Mathf.Max(a.Z, b.Z) + BonePadding);

                            float ballRadius = 0.11f + boundingBoxSizeOffset;  // :1992
                            if (AabbIntersectsSphere(mn, mx, ball.Predict(0), ballRadius)) // :1993
                            {
                                // todo оригинала: использовать стат реакции (:1996)
                                if (isDesignatedTeamPossessionPlayer && matchLastTouchBias < 0.01f)
                                {
                                    controlledCollisionTriggered = true;       // :1998
                                }
                                else
                                {
                                    // todonow оригинала: усреднять bouncevec/bias на хит (:2002)
                                    float movementBias = oppLastTouchBias * 0.8f + 0.2f; // :2003
                                    // ШОВ GetDerivedPosition() геометрии → середина сегмента кости
                                    Vector3 derivedPosition = (a + b) * 0.5f;
                                    bounceVec += BluntMath.GetNormalized(
                                        ball.Predict(0) - derivedPosition, Vector3.Zero)
                                        * movementBias
                                        + playerMovement * (1.0f - movementBias); // :2004
                                    bounceCount++;                             // :2005
                                    accidentalTouch = true;                    // :2006 — регистрирует вызывающий
                                    Vector3 aabbCenter = (mn + mx) * 0.5f;     // :2007-2008 (aabb.cpp:119-128)
                                    // aabb.cpp:106-117 GetRadius — полудиагональ AABB
                                    float aabbRadius = ((mx - mn) * 0.5f).Length();
                                    bias += (1.0f - Mathf.Clamp(
                                        ((ball.Predict(0) - aabbCenter).Length() - ballRadius)
                                        / aabbRadius, 0.0f, 1.0f)) * 0.9f + 0.1f; // :2009
                                }
                            }
                        }
                    }
                }
            }

            if (bias > 0.0f)                                                   // :2024
            {
                bounceVec /= bounceCount * 1.0f;                               // :2025
                bounceVec.Z *= 0.6f;                                           // :2026
                bounceVec = BluntMath.GetNormalized(bounceVec, Vector3.Zero);  // :2027 Normalize()
                Vector3 currentMovement = ball.GetMovement();                  // :2028
                Vector3 fullCollisionVec = (bounceVec * 6.0f)
                    + (bounceVec * currentMovement.Length() * 0.6f)
                    + (currentMovement * -0.2f);                               // :2029
                bias = Mathf.Clamp(bias, 0.0f, 1.0f);                          // :2030
                bias = bias * 0.5f + 0.5f;                                     // :2031
                Vector3 resultVector = fullCollisionVec * bias
                    + currentMovement * (1.0f - bias);                         // :2032
                if (resultVector.Length() > currentMovement.Length())
                    resultVector = BluntMath.GetNormalized(resultVector, Vector3.Zero)
                        * currentMovement.Length();                            // :2033
                resultVector *= 0.7f;                                          // :2035

                ball.Touch(resultVector);                                      // :2037
                ball.SetRotation(rng.Uniform(-30f, 30f), rng.Uniform(-30f, 30f),
                    rng.Uniform(-30f, 30f), 0.5f * bias);                      // :2038
                ball.TriggerBallTouchSound(
                    Mathf.Pow(BluntMath.NormalizedClamp(resultVector.Length(), 4.0f, 40.0f), 0.7f)); // :2039

                lastBodyBallCollisionTimeMs = actualTimeMs;                    // :2041
                return true;
            }

            return false;
        }
    }
}

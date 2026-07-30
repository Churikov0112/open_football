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
        // Множитель 100.0f (:80,:84,:91) — дельта за кадр при 100 Гц анимации → м/с.
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
                // :90 — в оригинале было `frame > 1`, автор пометил как баг и исправил на `frame > 0`
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

        // ---- Флаги модов оригинала (humanoidbase.cpp:2138-2146). static readonly, не const:
        // мёртвые ветки должны компилироваться без CS0162 (bug-for-bug, включаемо при отладке).
        private static readonly bool ModAllowRotation = true;       // :2138
        private static readonly bool ModCorneringBraking = false;   // :2139
        private static readonly bool ModPointinessCurve = true;     // :2140
        private static readonly bool ModMaximumAccelDecel = false;  // :2141
        private static readonly bool ModBrakeOnTouch = false;       // :2142 — «может быть слишком остро у клипов ~90°» (ориг.)
        private static readonly bool ModMaxCornering = true;        // :2143
        private static readonly bool ModMaxChange = true;           // :2144
        private static readonly bool ModAirResistance = true;       // :2145
        private static readonly bool ModCheatBodyDirection = false; // :2146

        // ---- входное состояние (сеттеры; дефолты — лаба без мяча и толкучки) ----
        private Vector3 _spatialPosition;
        private float _spatialAngle;
        private Vector3 _spatialDirectionVec = new Vector3(0, -1, 0);
        private float _spatialFloatVelocity;
        private Vector3 _spatialMovement;
        private float _statAgility = 0.6f, _statAcceleration = 0.6f, _statVelocity = 0.6f; // humanoidbase.cpp:2021-2023
        private float _statDribble = 0.6f, _statBallControl = 0.6f, _statBalance = 0.6f;   // :2024, :2108, :2084
        private float _agilityFactor = 0.5f;       // gameplay_agilityfactor (gamedefines.hpp:43)
        private float _accelerationFactor = 0.5f;  // gameplay_accelerationfactor (gamedefines.hpp:44)
        private float _lastTouchBias = 0f;                // player->GetLastTouchBias(1000) (:2082)
        private float _decayingPositionOffsetLength = 0f; // decayingPositionOffset.GetLength() (:2084)

        private readonly List<Vector3> _lastPositions = new();
        private float _lastRotationOffset;

        public void SetSpatialState(Vector3 position, float angle, Vector3 directionVec,
                                    float floatVelocity, Vector3 movement)
        {
            _spatialPosition = position; _spatialAngle = angle; _spatialDirectionVec = directionVec;
            _spatialFloatVelocity = floatVelocity; _spatialMovement = movement;
        }

        public void SetStats(float agility, float acceleration, float velocity,
                             float dribble, float ballControl, float balance)
        {
            _statAgility = agility; _statAcceleration = acceleration; _statVelocity = velocity;
            _statDribble = dribble; _statBallControl = ballControl; _statBalance = balance;
        }

        public void SetConfigFactors(float agilityFactor, float accelerationFactor)
        { _agilityFactor = agilityFactor; _accelerationFactor = accelerationFactor; }

        public void SetTouchContext(float lastTouchBias, float decayingPositionOffsetLength)
        { _lastTouchBias = lastTouchBias; _decayingPositionOffsetLength = decayingPositionOffsetLength; }

        // Мост для тестов/лабы: out-параметры через мост не ходят — складываем выходы в поля.
        public Vector3 CalculateForAnim(AnimCollection anims, int animIndex,
            bool useDesiredMovement, Vector3 desiredMovement,
            bool useDesiredBodyDirection, Vector3 desiredBodyDirectionRel)
        {
            var result = Calculate(anims.GetAnim(animIndex), anims.GetPositionCacheInternal(animIndex),
                useDesiredMovement, desiredMovement, useDesiredBodyDirection, desiredBodyDirectionRel,
                _lastPositions, out _lastRotationOffset);
            return result;
        }

        public Godot.Collections.Array GetLastPositions()
        {
            var arr = new Godot.Collections.Array();
            foreach (Vector3 p in _lastPositions) arr.Add(p);
            return arr;
        }

        public float GetLastRotationOffset() => _lastRotationOffset;

        // Порт HumanoidBase::CalculatePhysicsVector (humanoidbase.cpp:2014-2544).
        // positionsRet — варпнутая траектория корня (точка на кадр, относительная от старта клипа);
        // rotationOffsetRet — rotationSmuggle.end; возвращает итоговое движение (м/с).
        // Ассерты оригинала (:2058-2063, :2090-2091, :2300, :2475, :2480-2481, :2495, :2541 — все
        // про Z==0 и размер positions) в код не переносим; их семантику проверяет check-скрипт.
        internal Vector3 Calculate(Animation anim, List<Vector3> origPositionCache,
            bool useDesiredMovement, Vector3 desiredMovement,
            bool useDesiredBodyDirection, Vector3 desiredBodyDirectionRel,
            List<Vector3> positionsRet, out float rotationOffsetRet)
        {
            positionsRet.Clear();                                          // :2016

            int animTouchFrame = BluntMath.AtoI(anim.GetVariable("touchframe")); // :2018
            bool touch = animTouchFrame > 0;                               // :2019

            float statAgility = _statAgility;                              // :2021-2024
            float statAcceleration = _statAcceleration;
            float statDribble = _statDribble;

            float incomingSwitchBias = 0.0f; // :2026 — не-0 даёт непуристичное поведение (ориг.)
            float outgoingSwitchBias = 0.0f; // :2027

            string animType = anim.GetAnimType();                          // :2029

            if (animType == "ballcontrol") outgoingSwitchBias = 0.0f;      // :2031-2047
            else if (animType == "trap") outgoingSwitchBias = 0.0f;
            else if (animType == "interfere") outgoingSwitchBias = 0.0f;
            else if (animType == "deflect") outgoingSwitchBias = 1.0f;
            else if (animType == "sliding") outgoingSwitchBias = 0.0f;
            else if (animType == "special") outgoingSwitchBias = 1.0f;
            else if (animType == "trip") outgoingSwitchBias = 0.5f; // направление отчасти предрешено коллизией
            else if (touch) outgoingSwitchBias = 1.0f;

            if (anim.GetVariable("incoming_special_state") != "" ||
                anim.GetVariable("outgoing_special_state") != "") outgoingSwitchBias = 1.0f; // :2049-2050

            Vector3 animIncomingMovement = BluntMath.GetRotated2D(new Vector3(0, -1, 0), _spatialAngle)
                * Velo.RangeVelocity(anim.GetIncomingVelocity());          // :2052
            Vector3 adaptedCurrentMovement = animIncomingMovement * incomingSwitchBias
                + _spatialMovement * (1.0f - incomingSwitchBias);          // :2053

            Vector3 predictedOutgoingMovement =
                BluntMath.GetRotated2D(anim.GetOutgoingMovement(), _spatialAngle); // :2055
            Vector3 velocifiedDesiredMovement =
                useDesiredMovement ? desiredMovement : predictedOutgoingMovement;  // :2056

            Vector3 adaptedDesiredMovement = predictedOutgoingMovement * outgoingSwitchBias
                + velocifiedDesiredMovement * (1.0f - outgoingSwitchBias); // :2060

            float maxVelocity = GetMaxVelocity(_statVelocity);             // :2065
            if (touch) maxVelocity *= 0.92f;                               // :2066

            const int timeStepMs = 10;                                     // :2070

            bool isBaseAnim = anim.GetVariable("baseanim") == "true";      // :2072 (дальше не используется — как в ориг.)
            _ = isBaseAnim;

            float difficultyFactor = BluntMath.AtoF(anim.GetVariable("animdifficultyfactor")); // :2074
            float difficultyPenaltyFactor = Mathf.Pow(                     // :2075-2080
                Mathf.Clamp((difficultyFactor - 0.0f)
                    * (1.0f - (statAgility * 0.2f + statAcceleration * 0.2f)) * 2.0f, 0.0f, 1.0f),
                0.7f);

            // :2082-2084 (todo ориг.: lasttouchbias в цикл, чтобы менялся во времени)
            float powerFactor = 1.0f - Mathf.Clamp(
                Mathf.Pow(_lastTouchBias, 0.8f) * (0.8f - statDribble * 0.3f), 0.0f, 0.4f);
            powerFactor *= 1.0f - Mathf.Clamp(
                _decayingPositionOffsetLength * (10.0f - _statBalance * 5.0f) - 0.1f, 0.0f, 0.3f);

            Vector3 temporalMovement = adaptedCurrentMovement;             // :2088

            Vector3 currentPosition = Vector3.Zero;                        // :2098

            // доля «чистой физики», просвечивающей сквозь чистый клип (:2100-2101)
            float physicsBias = 1.0f;
            // допустимое отклонение угла от клипа (:2102-2105)
            float maxAngleModUnderAnimAngle = 0.125f * Mathf.Pi;
            float maxAngleModOverAnimAngle = 0.125f * Mathf.Pi;
            float maxAngleModStraightAnimAngle = 0.125f * Mathf.Pi;
            if (touch)                                                     // :2106-2112
            {
                float bonus = 1.0f - Mathf.Pow(BluntMath.NormalizedClamp(
                    (adaptedCurrentMovement + predictedOutgoingMovement).Length() * 0.5f,
                    0, Velo.Sprint), 0.8f) * 0.8f;                         // :2107
                bonus *= 0.6f + 0.4f * _statBallControl; // :2108 — todo ориг.: «shouldn't this be agility?»
                maxAngleModUnderAnimAngle = 0.2f * Mathf.Pi * bonus;       // :2109
                maxAngleModOverAnimAngle = 0;                              // :2110
                maxAngleModStraightAnimAngle = 0.1f * Mathf.Pi * bonus;    // :2111
            }
            if (animType == "sliding")                                     // :2113-2117
            {
                maxAngleModUnderAnimAngle = 0.5f * Mathf.Pi;
                maxAngleModOverAnimAngle = 0.5f * Mathf.Pi;
                maxAngleModStraightAnimAngle = 0.5f * Mathf.Pi;
            }

            if (animType == "movement") physicsBias *= 1.0f;               // :2119-2136
            if (animType == "ballcontrol") physicsBias *= 1.0f;
            if (animType == "trap") physicsBias *= 1.0f;
            if (animType == "shortpass") physicsBias *= 0.0f;
            if (animType == "highpass") physicsBias *= 0.0f;
            if (animType == "shot") physicsBias *= 0.0f;
            if (animType == "interfere") physicsBias *= 0.5f;
            if (animType == "deflect") physicsBias *= 0.0f;
            if (animType == "sliding") physicsBias *= 1.0f;
            if (animType == "trip")
            { if (anim.GetVariable("triptype") == "1") physicsBias *= 0.5f; else physicsBias *= 0.0f; }
            if (animType == "special") physicsBias *= 0.0f;
            if (anim.GetVariable("incoming_special_state") != "") physicsBias *= 0.0f;

            // mod-флаги (:2138-2146) — static readonly поля класса выше

            float accelerationMultiplier = 0.5f + _accelerationFactor;     // :2148

            // --- поворот клипа к желаемому углу (:2151-2176) ---
            float toDesiredAngleCapped = 0;                                // :2153
            if (ModAllowRotation && physicsBias > 0.0f)                    // :2154
            {
                Vector3 animOutgoingVector = BluntMath.GetNormalized(predictedOutgoingMovement, Vector3.Zero); // :2155
                if (Velo.FloatToEnumVelocity(predictedOutgoingMovement.Length()) == Velo.IdVelIdle)
                    animOutgoingVector = BluntMath.GetRotated2D(anim.GetOutgoingDirection(), _spatialAngle);   // :2156
                Vector3 desiredVector = BluntMath.GetNormalized(adaptedDesiredMovement, Vector3.Zero);         // :2157
                if (Velo.FloatToEnumVelocity(adaptedDesiredMovement.Length()) == Velo.IdVelIdle)
                    desiredVector = BluntMath.GetRotated2D(desiredBodyDirectionRel, _spatialAngle);            // :2158
                float toDesiredAngle = BluntMath.GetAngle2D(desiredVector, animOutgoingVector);                // :2159
                if (Mathf.Abs(toDesiredAngle) <= 0.5f * Mathf.Pi || animType == "sliding") // :2160 — хотим больше? пропускаем клип
                {
                    float animChange = BluntMath.GetAngle2D(animOutgoingVector, _spatialDirectionVec); // :2162
                    if (Mathf.Abs(animChange) > 0.06f * Mathf.Pi)          // :2163
                    {
                        int sign = BluntMath.SignSide(animChange);         // :2164
                        if (BluntMath.SignSide(toDesiredAngle) == sign)    // :2165-2166
                            toDesiredAngleCapped = Mathf.Clamp(toDesiredAngle,
                                -maxAngleModOverAnimAngle, maxAngleModOverAnimAngle);
                        else                                               // :2167-2168
                            toDesiredAngleCapped = Mathf.Clamp(toDesiredAngle,
                                -maxAngleModUnderAnimAngle, maxAngleModUnderAnimAngle);
                    }
                    else
                    {
                        // клип «прямо» — у него нет стороны (:2170-2173)
                        toDesiredAngleCapped = Mathf.Clamp(toDesiredAngle,
                            -maxAngleModStraightAnimAngle, maxAngleModStraightAnimAngle);
                    }
                }
            }

            float maximumOutgoingVelocity = Velo.Sprint;                   // :2179
            if (ModCorneringBraking)                                       // :2181-2202 — мёртвая ветка
            {
                float brakeBias = 0.8f;                                    // :2183
                brakeBias *= touch ? 1.0f : 0.8f;                          // :2184
                brakeBias *= 1.0f - statAgility * 0.2f;                    // :2185
                Vector3 animOutgoingMovementCb = anim.GetOutgoingMovement();               // :2187
                animOutgoingMovementCb = BluntMath.GetRotated2D(animOutgoingMovementCb, toDesiredAngleCapped); // :2188
                brakeBias *= Mathf.Pow(BluntMath.NormalizedClamp(
                    _spatialFloatVelocity, Velo.Idle, Velo.Sprint - 0.5f), 0.8f);          // :2189-2191
                float maxVelo = Velo.Sprint * ((1.0f - brakeBias)
                    + (1.0f - Mathf.Pow(Mathf.Abs(BluntMath.GetAngle2D(
                        BluntMath.GetNormalized(animOutgoingMovementCb, Vector3.Zero),
                        new Vector3(0, -1, 0)) / Mathf.Pi), 0.5f)) * brakeBias);           // :2192-2200
                maximumOutgoingVelocity = maxVelo;                         // :2201
            }

            // --- loop da loop (:2206-2493) ---
            for (int timeMs = 0; timeMs < anim.GetFrameCount() * 10; timeMs += timeStepMs)
            {
                // +1: первый кадр тоже под влиянием; финал с bias 1.0 на предпоследнем кадре,
                // чтобы следующий клип прочитал уже готовые стартовые значения (:2208-2211)
                float frameBias = (timeMs + 10) / (float)((anim.GetEffectiveFrameCount() + 1) * 10);

                float lagExp = 1.0f;                                       // :2213
                if (ModPointinessCurve && physicsBias > 0.0f
                    && (animType == "ballcontrol" || animType == "movement")) // :2214
                {
                    lagExp = 1.4f - _agilityFactor * 0.8f;                 // :2215
                    lagExp *= 1.2f - statAgility * 0.4f;                   // :2216
                    if (touch) lagExp += -0.1f + Mathf.Clamp(difficultyFactor * 0.4f, 0.0f, 0.5f); // :2217-2218
                    else lagExp += -0.2f + Mathf.Clamp(difficultyFactor * 0.2f, 0.0f, 0.2f);       // :2219-2220
                    lagExp = Mathf.Clamp(lagExp, 0.25f, 4.0f);             // :2223
                    if (touch && timeMs < animTouchFrame * 10) lagExp = Mathf.Max(lagExp, 0.7f); // :2224 — иначе можно «пропустить» мяч
                    lagExp = lagExp * physicsBias + 1.0f * (1.0f - physicsBias); // :2226
                }
                float adaptedFrameBias = Mathf.Pow(frameBias, lagExp);     // :2228
                // (unsigned int)-приведение аргумента оригинала (humanoid_utils.hpp:25) → усечение вниз (:2229)
                Vector3 animMovement = BluntMath.GetRotated2D(
                    CalculateMovementAtFrame(origPositionCache,
                        (int)(anim.GetEffectiveFrameCount() * adaptedFrameBias), 1),
                    _spatialAngle);

                float animVelo = animMovement.Length();                    // :2231-2233
                Vector3 adaptedAnimMovement = animMovement;
                float adaptedAnimVelo = animVelo;

                // спринт клипа → max скорость игрока (:2236-2245)
                if (animVelo > Velo.WalkSprintSwitch
                    && (animType == "movement" || animType == "ballcontrol" || animType == "trap")) // :2238
                {
                    if (maxVelocity > animVelo) // :2240 — только ускоряем: в клипе бывают быстрые куски (прыжки)
                    {
                        adaptedAnimVelo = StretchSprintTo(animVelo, Velo.AnimSprint, maxVelocity);  // :2241
                        adaptedAnimMovement = BluntMath.GetNormalized(adaptedAnimMovement, Vector3.Zero) * adaptedAnimVelo; // :2242
                    }
                }

                float maxSlower = 1.6f;   // :2248 — не свалиться ниже dribble − idleDribbleSwitch
                if (touch) maxSlower = 1.2f;                               // :2249
                float maxFaster = 0.0f;                                    // :2250
                if (touch) maxFaster = 0.0f;                               // :2251
                if (temporalMovement.Length() > adaptedAnimVelo)           // :2252 — уже быстрее, ладно
                    maxFaster = Mathf.Min(0.0f + 1.0f * (1.0f - frameBias),
                        Mathf.Max(maxFaster, temporalMovement.Length() - adaptedAnimVelo));
                if (maxFaster > 0)                                         // :2253 — только в нужную сторону
                    maxFaster *= Mathf.Max(0.0f, BluntMath.GetNormalizedMax(adaptedAnimMovement, 1.0f)
                        .Dot(BluntMath.GetNormalized(adaptedDesiredMovement, Vector3.Zero)));
                if (animType == "sliding") maxFaster = 100;                // :2254
                float desiredVelocity = adaptedDesiredMovement.Length();   // :2255
                adaptedAnimVelo = Mathf.Clamp(desiredVelocity,
                    adaptedAnimVelo - maxSlower, adaptedAnimVelo + maxFaster); // :2256
                adaptedAnimMovement = BluntMath.GetNormalized(adaptedAnimMovement, Vector3.Zero) * adaptedAnimVelo; // :2257

                if (ModCorneringBraking)                                   // :2259-2265 — мёртвая ветка
                {
                    float frameBiasedMaximumOutgoingVelocity =
                        Velo.Sprint * (1.0f - frameBias) + maximumOutgoingVelocity * frameBias; // :2260
                    if (adaptedAnimVelo > frameBiasedMaximumOutgoingVelocity)                   // :2261
                    {
                        adaptedAnimVelo = frameBiasedMaximumOutgoingVelocity;                   // :2262
                        adaptedAnimMovement = BluntMath.GetNormalized(adaptedAnimMovement, Vector3.Zero) * adaptedAnimVelo; // :2263
                    }
                }

                if (ModMaximumAccelDecel)                                  // :2267-2279 — мёртвая ветка
                {
                    // сглаживание переходов; с низкими max-ами могло бы служить и «физической медлительностью»,
                    // но решено использовать только для капа скорости перехода (:2268-2270)
                    float maxAccelMPS = 20.0f;                             // :2271
                    float maxDecelMPS = 20.0f;                             // :2272
                    float currentVelo = temporalMovement.Length();         // :2273
                    float veloChangeMPS = (adaptedAnimVelo - currentVelo) / (timeStepMs * 0.001f); // :2274
                    if (veloChangeMPS < -maxDecelMPS || veloChangeMPS > maxAccelMPS)              // :2275
                    {
                        adaptedAnimVelo = currentVelo
                            + Mathf.Clamp(veloChangeMPS, -maxDecelMPS, maxAccelMPS) * (timeStepMs * 0.001f); // :2276
                        adaptedAnimMovement = BluntMath.GetNormalized(adaptedAnimMovement, Vector3.Zero) * adaptedAnimVelo; // :2277
                    }
                }

                Vector3 resultingPhysicsMovement = adaptedAnimMovement;    // :2281
                // угол (:2283-2284)
                resultingPhysicsMovement = BluntMath.GetRotated2D(
                    resultingPhysicsMovement, toDesiredAngleCapped * frameBias);

                // --- насколько остаёмся верны клипу (:2287-2289) ---
                resultingPhysicsMovement = resultingPhysicsMovement * physicsBias
                    + animMovement * (1.0f - physicsBias);

                // вот и всё, теперь мы знаем, куда хотим в жизни (:2292-2294)
                Vector3 toDesired = resultingPhysicsMovement - temporalMovement;

                float penaltyBreakFactor = 0.0f;                           // :2303
                if (ModBrakeOnTouch)                                       // :2304-2326 — мёртвая ветка
                {
                    // замедление после касания мяча (precalc на touchframe: temporalMovement
                    // изменится из-за этого же эффекта) (:2305-2306)
                    int numBrakeFrames = 15;                               // :2307
                    if (touch && timeMs >= animTouchFrame * 10
                        && timeMs < (animTouchFrame + numBrakeFrames) * 10) // :2308
                    {
                        int brakeFramesInto = (timeMs - animTouchFrame * 10) / 10; // :2309
                        float brakeFrameFactor = Mathf.Pow(1.0f - brakeFramesInto / (float)numBrakeFrames, 0.5f); // :2310-2311
                        float touchBrakeFactor = 0.3f;                     // :2313
                        float touchDifficultyFactor = Mathf.Clamp(
                            (difficultyFactor + 0.7f) * (1.0f - statDribble * 0.4f), 0.0f, 1.0f); // :2315
                        touchDifficultyFactor *= 1.0f - Mathf.Pow(
                            Mathf.Abs(anim.GetOutgoingAngle()) / Mathf.Pi, 0.75f); // :2316-2320 — не помогать тормозить к 180°
                        float veloFactorBt = BluntMath.NormalizedClamp(
                            temporalMovement.Length(), Velo.Walk, Velo.Sprint);    // :2322
                        penaltyBreakFactor = touchDifficultyFactor * veloFactorBt * brakeFrameFactor * touchBrakeFactor; // :2324
                    }
                }

                if (ModMaxCornering)                                       // :2341-2370
                {
                    Vector3 predictedMovement = temporalMovement + toDesired; // :2342
                    float startVelo = Velo.IdleDribbleSwitch;              // :2343
                    if (temporalMovement.Length() > startVelo && predictedMovement.Length() > startVelo) // :2344
                    {
                        // :2345 — GetNormalized() оригинала без фолбэка; длины > startVelo гарантированы
                        float angle = BluntMath.GetAngle2D(
                            BluntMath.GetNormalized(predictedMovement, Vector3.Zero),
                            BluntMath.GetNormalized(temporalMovement, Vector3.Zero));
                        float maxAngleFactor = 1.0f * (timeStepMs / 1000.0f);      // :2346
                        maxAngleFactor *= 0.7f + 0.3f * statAgility;               // :2347
                        if (!touch) maxAngleFactor *= 1.5f;                        // :2348
                        float maxAngle = maxAngleFactor * Mathf.Pi;                // :2349
                        float veloFactorMc = Mathf.Pow(BluntMath.NormalizedClamp(
                            temporalMovement.Length(), 0, Velo.Sprint), 1.0f);     // :2350-2352
                        maxAngle /= veloFactorMc + 0.01f;                          // :2353

                        if (Mathf.Abs(angle) > maxAngle)                           // :2355
                        {
                            int mode = 1; // 0: ограничить угол, 1: ограничить скорость (:2357)
                            if (mode == 0)                                         // :2359-2362
                            {
                                Vector3 restrictedPredictedMovement = BluntMath.GetRotated2D(
                                    predictedMovement, (Mathf.Abs(angle) - maxAngle) * -BluntMath.SignSide(angle));
                                toDesired = restrictedPredictedMovement - temporalMovement;
                            }
                            else if (mode == 1)                                    // :2363-2365
                            {
                                float overAngle = Mathf.Abs(angle) - maxAngle; // > 0
                                toDesired += -temporalMovement * Mathf.Clamp(overAngle / Mathf.Pi * 3.0f, 0.0f, 1.0f);
                            }
                        }
                    }
                }

                if (ModMaxChange)                                          // :2372-2405
                {
                    float maxChange = 0.03f;                               // :2373
                    if (animType == "trip") maxChange *= 0.7f;             // :2374
                    if (animType == "sliding") maxChange = 0.1f;           // :2375
                    float veloFactorM = Mathf.Pow(BluntMath.NormalizedClamp(
                        temporalMovement.Length(), 0, Velo.Sprint), 1.5f); // :2378-2380
                    float firstStepFactor = veloFactorM;                   // :2381
                    if (animType == "movement") firstStepFactor *= 0.4f;   // :2382
                    // без силы первые кадры — переходы плавнее (:2376, :2383)
                    maxChange *= (1.0f - firstStepFactor)
                        + firstStepFactor * BluntMath.Curve(BluntMath.NormalizedClamp(timeMs, 0.0f, 160.0f), 1.0f);
                    maxChange *= 1.2f - veloFactorM * 0.4f;                // :2385
                    maxChange *= 0.75f + _agilityFactor * 0.5f;            // :2387
                    maxChange *= powerFactor;                              // :2399

                    float desiredLength = toDesired.Length();              // :2401
                    float maxAddition = maxChange * timeStepMs;            // :2402
                    toDesired = BluntMath.NormalizeMax(toDesired, Mathf.Min(desiredLength, maxAddition)); // :2404
                }

                // --- сопротивление воздуха (:2408-2451) ---
                if (ModAirResistance && animType != "sliding" && animType != "deflect") // :2410
                {
                    float veloExp = 1.8f;                                  // :2411
                    float accelPower = 11.0f * accelerationMultiplier;     // :2412
                    float falloffStartVelo = Velo.IdleDribbleSwitch;       // :2413

                    if ((temporalMovement + toDesired).Length() > falloffStartVelo) // :2415
                    {
                        accelPower *= 1.0f - difficultyPenaltyFactor * 0.4f; // :2417-2418 — тяжёлые клипы слабее

                        // :2422-2427 — СВЕЖИЙ GetMaxVelocity() (без touch-множителя 0.92 из :2066!)
                        float veloAirResistanceFactor = Mathf.Clamp(
                            Mathf.Pow(Mathf.Clamp((temporalMovement.Length() - falloffStartVelo)
                                / (GetMaxVelocity(_statVelocity) - falloffStartVelo), 0.0f, 1.0f),
                                veloExp), 0.0f, 1.0f);

                        // круговая версия (:2432-2439)
                        Vector3 forwardVector = Vector3.Zero;
                        if ((temporalMovement + toDesired).Length() > temporalMovement.Length()) // :2434 — вне «круга скорости»
                        {
                            Vector3 destination = temporalMovement + toDesired;    // :2435
                            float velo = temporalMovement.Length();                // :2436
                            float accel = destination.Length() - velo;             // :2437
                            forwardVector = BluntMath.GetNormalized(destination, Vector3.Zero) * accel; // :2438
                        }

                        float accelerationAddition = forwardVector.Length();       // :2441
                        float maxAccelerationMPS = accelPower * (1.0f - veloAirResistanceFactor)
                            * (statAcceleration * 0.3f + 0.7f);                    // :2442
                        float maxAccelerationAddition = maxAccelerationMPS * (timeStepMs / 1000.0f); // :2443
                        if (accelerationAddition > maxAccelerationAddition)        // :2444
                        {
                            float remainingFactor = maxAccelerationAddition / accelerationAddition; // :2445
                            toDesired -= forwardVector * (1.0f - remainingFactor); // :2446
                        }
                    }
                }

                // MAKE IT SEW! (:2454)
                Vector3 tmpTemporalMovement = temporalMovement + toDesired; // :2456

                // выходная скорость той же idle-ности, что клип (:2458-2473)
                if (timeMs >= (anim.GetFrameCount() - 2) * 10)             // :2459
                {
                    bool hardQuantize = true;                              // :2461
                    if (!hardQuantize && anim.GetVariable("outgoing_special_state") != "") hardQuantize = true; // :2462

                    if (!hardQuantize)
                    {
                        // мягкая версия (:2464-2467) — мёртвая ветка
                        if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) == Velo.IdVelIdle
                            && Velo.FloatToEnumVelocity(tmpTemporalMovement.Length()) != Velo.IdVelIdle)
                            tmpTemporalMovement = BluntMath.GetNormalizedTo(
                                tmpTemporalMovement, Velo.IdleDribbleSwitch - 0.01f);          // :2466
                        else if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) != Velo.IdVelIdle
                            && Velo.FloatToEnumVelocity(tmpTemporalMovement.Length()) == Velo.IdVelIdle)
                            tmpTemporalMovement = BluntMath.GetNormalizedTo(
                                BluntMath.GetRotated2D(anim.GetOutgoingMovement(), _spatialAngle),
                                Velo.IdleDribbleSwitch + 0.01f);                               // :2467
                    }
                    else
                    {
                        // жёсткая версия (:2468-2471)
                        if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) == Velo.IdVelIdle
                            && Velo.FloatToEnumVelocity(tmpTemporalMovement.Length()) != Velo.IdVelIdle)
                            tmpTemporalMovement = Vector3.Zero;                                // :2470
                        else if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) != Velo.IdVelIdle
                            && Velo.FloatToEnumVelocity(tmpTemporalMovement.Length()) == Velo.IdVelIdle)
                            tmpTemporalMovement = BluntMath.GetNormalizedTo(
                                BluntMath.GetRotated2D(anim.GetOutgoingMovement(), _spatialAngle),
                                Velo.Dribble);                                                 // :2471
                    }
                }

                temporalMovement = tmpTemporalMovement;                    // :2476

                if (timeMs >= (anim.GetFrameCount() - 2) * 10) penaltyBreakFactor = 0.0f; // :2478
                currentPosition += temporalMovement * (1.0f - penaltyBreakFactor)
                    * (timeStepMs / 1000.0f);                              // :2479

                if (timeMs % 10 == 0) positionsRet.Add(currentPosition);   // :2482-2484 (шаг 10 → каждый виток)
            }

            Vector3 resultingMovement = temporalMovement;                  // :2496

            if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) != Velo.IdVelIdle
                && Velo.FloatToEnumVelocity(resultingMovement.Length()) != Velo.IdVelIdle)
                rotationOffsetRet = BluntMath.GetAngle2D(
                    BluntMath.GetRotated2D(resultingMovement, -_spatialAngle),
                    anim.GetOutgoingMovement());                           // :2499-2500
            else
                rotationOffsetRet = toDesiredAngleCapped * physicsBias;    // :2502

            // body direction assist (:2506-2539) — мёртвая ветка (ModCheatBodyDirection=false)
            if (ModCheatBodyDirection && useDesiredBodyDirection && animType == "movement") // :2507
            {
                float angleFactor = 0.5f;                                  // :2509
                float maxAngleCbd = 0.25f * Mathf.Pi;                      // :2510
                float predictedAngleRel = anim.GetOutgoingAngle() + anim.GetOutgoingBodyAngle() + rotationOffsetRet; // :2512
                float desiredRotationOffset = BluntMath.GetAngle2D(
                    BluntMath.GetRotated2D(desiredBodyDirectionRel, -predictedAngleRel),
                    new Vector3(0, -1, 0));                                // :2513
                if (Mathf.Abs(desiredRotationOffset) < 0.5f * Mathf.Pi)    // :2515 — иначе слишком
                {
                    float outgoingVelocityFactorInv = 1.0f - BluntMath.NormalizedClamp(
                        resultingMovement.Length(), Velo.IdleDribbleSwitch, Velo.Sprint - 1.0f) * 1.0f; // :2517
                    float animLengthFactor = BluntMath.NormalizedClamp(anim.GetFrameCount(), 0, 25);    // :2518
                    float maximizedRotationOffset = Mathf.Clamp(desiredRotationOffset,
                        outgoingVelocityFactorInv * animLengthFactor * angleFactor * -maxAngleCbd,
                        outgoingVelocityFactorInv * animLengthFactor * angleFactor * maxAngleCbd);      // :2519-2520
                    rotationOffsetRet += maximizedRotationOffset;          // :2528
                }
            }

            return resultingMovement;                                      // :2543
        }
    }
}

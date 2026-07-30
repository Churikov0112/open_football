using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // Порт Ball (ball.cpp/ball.hpp) минус: сетка ворот (ball.cpp:331-408, решение роадмапа — сеткой
    // занимается наш NetSim, ballTouchesNet не переносится), звук (:46-68, :324-327, :553-560),
    // сцена/geometry (:33-44, :74-84), Put/temporal smoothing (:587-600), debug-клавиша BACKSPACE
    // (:564-569), привязки к Match (:99-102). Радиус мяча 0.11 — хардкод оригинала по всему коду
    // (НЕ константа), переносится литералом.
    public partial class Ball : RefCounted
    {
        // ball.cpp:23-29 — калиброванные константы, НЕ менять
        private const float Bounce = 0.62f;         // ball.cpp:23 — 1 = полный отскок, 0 = никакого
        private const float LinearBounce = 0.06f;   // ball.cpp:24 — больше = сильнее торможение
        private const float Drag = 0.015f;          // ball.cpp:25 — previously 0.025f (комментарий оригинала)
        private const float Friction = 0.04f;       // ball.cpp:26 — больше = сильнее
        private const float LinearFriction = 1.6f;  // ball.cpp:27 — больше = сильнее, произвольная шкала
        private const float Gravity = -9.81f;       // ball.cpp:28
        private const float GrassHeight = 0.025f;   // ball.cpp:29

        // ball.cpp:160 — мёртвая ветка оригинала (false), портирована дословно (:518-522)
        private static readonly bool AutoDegradeTimeStep = false;

        // ball.cpp:154 woodwork_enabled — у оригинала локальный bool true; вынесен в публичное
        // поле, чтобы лаба без ворот могла выключить штанги
        public bool WoodworkEnabled = true;

        // ball.hpp:34-41 BallSpatialInfo — возврат CalculatePrediction
        private readonly struct BallSpatialInfo
        {
            public readonly Vector3 Momentum;
            public readonly Quaternion RotationMs;
            public BallSpatialInfo(Vector3 momentum, Quaternion rotationMs)
            {
                Momentum = momentum;
                RotationMs = rotationMs;
            }
        }

        // ball.hpp:89-100 — состояние
        private Vector3 _momentum;
        private Quaternion _rotationMs = Quaternion.Identity;
        private readonly Vector3[] _predictions = new Vector3[GpfPitch.BallPredictionSizeMs / 10];
        private Quaternion _orientPrediction = Quaternion.Identity;
        private readonly List<Vector3> _ballPosHistory = new();
        private Vector3 _previousMomentum;
        private Vector3 _previousPosition;
        private Vector3 _positionBuffer;
        private Quaternion _orientationBuffer = Quaternion.Identity;

        // ball.cpp:21-72 — конструктор минус сцена/звук: сразу наполняет кэш предсказаний (:71)
        public Ball()
        {
            CalculatePrediction();
        }

        // vector3.hpp:261-268 GetLength — КВИРК оригинала: длина < 1e-6 обнуляется.
        // Участвует в drag (:180), трении (:216), дистанциях штанг (:247, :298) и магнусе (:492).
        private static float GetLength(Vector3 v)
        {
            float length = Mathf.Sqrt(Mathf.Pow(v.X, 2f) + Mathf.Pow(v.Y, 2f) + Mathf.Pow(v.Z, 2f));
            if (length < 0.000001f) length = 0f;
            return length;
        }

        // vector3.cpp:183-188 Normalize() БЕЗ проверок (деление на ноль возможно, как в оригинале).
        // Используется в отражении от штанг (:291, :321), где аргумент гарантированно ненулевой.
        private static Vector3 GetNormalizedUnchecked(Vector3 v)
        {
            float f = 1.0f / Mathf.Sqrt(v.Dot(v));
            return v * f;
        }

        // vector3.cpp:252-254 GetAbsolute — покомпонентный fabsf
        private static Vector3 GetAbsolute(Vector3 v)
            => new Vector3(Mathf.Abs(v.X), Mathf.Abs(v.Y), Mathf.Abs(v.Z));

        // ball.hpp:51-57. Bug-for-bug: отрицательный predictTimeMs проходит unsigned-каст
        // оригинала (`unsigned int index = predictTime_ms`) и даёт ПОСЛЕДНЮЮ точку кэша, не первую;
        // проверка `if (index < 0)` оригинала (:55) мертва для unsigned — не переносится.
        public Vector3 Predict(int predictTimeMs)
        {
            uint index = (uint)predictTimeMs;
            if (index >= GpfPitch.BallPredictionSizeMs) index = (uint)(GpfPitch.BallPredictionSizeMs - 10);
            index /= 10;
            return _predictions[index];
        }

        // ball.cpp:86-89 — метры в секунду
        public Vector3 GetMovement() => _momentum;

        // ball.hpp:99 — прямое поле; TemporalSmoother-обёртка GetPositionBuffer() оригинала
        // (ball.hpp:67) вырезана вместе с Put-буферами
        public Vector3 GetPositionBuffer() => _positionBuffer;

        // ball.cpp:91-103
        public void Touch(Vector3 target)
        {
            if (_positionBuffer.Z < 0.11f) _positionBuffer.Z = 0.11f; // :93

            SetMomentum(target); // :95 (внутри — CalculatePrediction, :98)

            // шов (:99-102): match->UpdateLatestMentalImageBallPredictions() и
            // UpdatePossessionStats обеих команд — слой матча/ИИ, не физика мяча
        }

        // ball.cpp:105-112
        public void SetPosition(Vector3 target)
        {
            _positionBuffer = target;            // :106
            _momentum = Vector3.Zero;            // :107
            SetRotation(0f, 0f, 0f, 1.0f);       // :108 (внутри — CalculatePrediction)
            _ballPosHistory.Clear();             // :109
            _previousMomentum = _momentum;       // :110
            _previousPosition = _positionBuffer; // :111
        }

        // ball.cpp:114-117
        public void SetMomentum(Vector3 target)
        {
            _momentum = target;     // :115
            CalculatePrediction();  // :116
        }

        // ball.cpp:119-131 — радианы в секунду по каждой оси
        public void SetRotation(float x, float y, float z, float bias)
        {
            Quaternion rotX = QuatUtil.AngleAxis(
                Mathf.Clamp(x * 0.001f, -Mathf.Pi * 0.49f, Mathf.Pi * 0.49f), new Vector3(-1, 0, 0)); // :120-121
            Quaternion rotY = QuatUtil.AngleAxis(
                Mathf.Clamp(y * 0.001f, -Mathf.Pi * 0.49f, Mathf.Pi * 0.49f), new Vector3(0, 1, 0));  // :122-123
            Quaternion rotZ = QuatUtil.AngleAxis(
                Mathf.Clamp(z * 0.001f, -Mathf.Pi * 0.49f, Mathf.Pi * 0.49f), new Vector3(0, 0, 1));  // :124-125

            Quaternion tmpRotationMs = rotX * rotY * rotZ;                 // :127
            _rotationMs = QuatUtil.Slerp(_rotationMs, bias, tmpRotationMs); // :128 — GetSlerped(bias, other)

            CalculatePrediction(); // :130
        }

        // ball.cpp:133-135; отдельное имя — GDScript-мост не различает перегрузки
        public void SetRotationVec(Vector3 rot, float bias)
        {
            SetRotation(rot.X, rot.Y, rot.Z, bias);
        }

        // ball.cpp:137-537 — ядро: один проход наполняет кэш предсказаний на 3 секунды вперёд
        // шагами по 10 мс и возвращает состояние (momentum/rotation) на 10 мс.
        // Порядок секций внутри шага — СВЯЩЕННЫЙ:
        // гравитация (:175) → drag (:180-183) → grassBias (:186-191) → отскок (:197-205)
        // → трение газона (:210-227) → штанги+перекладина (только firstTime, :240-328)
        // → [сетка ВЫРЕЗАНА, :331-408] → вращение от качения + обратное влияние (:413-481)
        // → магнус (:486-501) → интеграция позиции/ориентации (:506-514)
        // → кэш каждые 10 мс (:516-525) → снапшот нового состояния на 10 мс (:527-531).
        private BallSpatialInfo CalculatePrediction()
        {
            Vector3 newMomentum = default;               // :139
            Quaternion newRotationMs = Quaternion.Identity; // :140

            // наполнение кэша (:143-150)
            Vector3 nextPos = _positionBuffer;           // :145
            Quaternion nextOrientation = _orientationBuffer; // :146
            Vector3 momentumPredict = _momentum;         // :147
            Quaternion rotationPredictMs = _rotationMs;  // :148

            _predictions[0] = nextPos; // :150

            bool dragEnabled = true;                 // :152
            bool groundFrictionEnabled = true;       // :153
            // :154 woodwork_enabled — поле WoodworkEnabled класса
            // :155 netting_enabled — вырезано вместе с сеткой
            bool groundRotationEffectsEnabled = true; // :156
            bool swerveEnabled = true;                // :157

            float timeStep = 0.01f; // :159 — секунды (0.001f в комментарии оригинала)

            bool firstTime = true; // :163

            // :165 ballTouchesNet — вырезан вместе с сеткой

            for (uint predictTimeMs = (uint)(int)(timeStep * 1000.0f);
                 predictTimeMs < GpfPitch.BallPredictionSizeMs;
                 predictTimeMs += (uint)(int)(timeStep * 1000.0f)) // :167
            {
                float frictionFactor = 0.0f; // :169


                // гравитация (:172-175): vz = vz0 + g * t

                momentumPredict.Z = momentumPredict.Z + Gravity * timeStep; // :175


                // сопротивление воздуха (:178-183) — к ПОЛНОМУ 3D-вектору, не только XY

                float momentumVelo = GetLength(momentumPredict); // :180
                float momentumVeloDragged =
                    momentumVelo - Drag * Mathf.Pow(momentumVelo, 2.0f) * timeStep; // :181-182
                if (dragEnabled)
                    momentumPredict = BluntMath.GetNormalized(momentumPredict, Vector3.Zero)
                        * momentumVeloDragged; // :183 — GetNormalized(0): 0-вектор остаётся нулём


                // влияние травы (:186-191)

                float ballBottom = nextPos.Z - 0.11f; // :186
                float grassInfluenceBias = Mathf.Clamp(1.0f - (ballBottom / GrassHeight), 0.0f, 1.0f); // :187 — 0 = нет трения, 1 = всё трение
                grassInfluenceBias = Mathf.Pow(grassInfluenceBias, 0.7f); // :189-191 — на половине травы трения уже больше 50%


                // отскок (:195-205)

                if (nextPos.Z < 0.11f) // :197
                {
                    if (momentumPredict.Z < 0.0f) // :198
                    {
                        // :199 — считается ДО перезаписи vz и только в кадре удара о землю (раз на отскок)
                        frictionFactor = BluntMath.NormalizedClamp(-momentumPredict.Z - 0.5f, 0.0f, 12.0f);
                        momentumPredict.Z = -momentumPredict.Z * Bounce; // :200
                        momentumPredict.Z = Mathf.Max(momentumPredict.Z - LinearBounce, 0.0f); // :201 — линейный отскок, вычитание ПОСЛЕ множителя
                    }

                    nextPos.Z = 0.11f; // :204
                }


                // трение газона (:208-227) — порог 0.11 + grassHeight, НЕ 0.11 как у отскока

                if (nextPos.Z < 0.11f + GrassHeight && groundFrictionEnabled) // :210
                {
                    float adaptedFriction = Friction * grassInfluenceBias; // :211

                    // v(t) = v(0) * (k ^ t)  (:213)

                    Vector3 xy = BluntMath.Get2D(momentumPredict); // :215
                    float velo = GetLength(xy);                    // :216

                    float newVelo = velo - adaptedFriction * Mathf.Pow(velo, 2.0f) * timeStep; // :218

                    // линейное трение (:220-221) — кламп снизу нулём: мяч не едет назад
                    newVelo = Mathf.Clamp(newVelo - (LinearFriction * grassInfluenceBias * timeStep), 0.0f, 100000.0f);

                    xy = BluntMath.GetNormalized(xy, Vector3.Zero); // :223
                    xy *= newVelo;                                  // :224
                    momentumPredict.X = xy.X;                       // :225
                    momentumPredict.Y = xy.Y;                       // :226
                }

                // :229-236: netAbsorbInv (0.95 → pow(0.95, timeStep*100)), powFactor 2.6 и
                // powerFac 1.8 питали только вырезанную сетку — НЕ переносятся (мёртвый код)
                float postAbsorbInv = 0.8f; // :232
                float ballRadius = 0.11f;   // :233
                float postRadius = 0.07f;   // :234

                // штанги/перекладина (:238-328) — ТОЛЬКО на первом шаге (firstTime): на
                // предсказание дальних отскоков от штанги оригинал забил, работает через
                // пересчёт в Process() каждый тик; переносится как есть

                if (firstTime && WoodworkEnabled) // :240
                {
                    bool woodwork = false; // :242 — в оригинале питал только звук штанги (:324-327, вырезан)


                    // штанги (:245-292)

                    if (nextPos.Z < GpfPitch.GoalHeight + ballRadius + postRadius &&
                        GetLength(GetAbsolute(BluntMath.Get2D(nextPos))
                            - new Vector3(GpfPitch.PitchHalfW, GpfPitch.GoalHalfWidth, 0f))
                            < ballRadius + postRadius) // :247
                    {
                        Vector3 normal;

                        if (nextPos.X < 0f) // :250 — левая половина поля
                        {
                            if (nextPos.Y < 0f) // :252 — «нижняя» сторона
                            {
                                normal = BluntMath.GetNormalized(
                                    BluntMath.Get2D(nextPos) - new Vector3(-GpfPitch.PitchHalfW, -GpfPitch.GoalHalfWidth, 0f),
                                    new Vector3(1, 0, 0)); // :254
                                float nextPosZ = nextPos.Z; // :255
                                nextPos = new Vector3(-GpfPitch.PitchHalfW, -GpfPitch.GoalHalfWidth, 0f)
                                    + normal * (postRadius + ballRadius); // :256
                                nextPos.Z = nextPosZ; // :257
                                woodwork = true;      // :258
                            }
                            else // :260 — «верхняя» сторона
                            {
                                normal = BluntMath.GetNormalized(
                                    BluntMath.Get2D(nextPos) - new Vector3(-GpfPitch.PitchHalfW, GpfPitch.GoalHalfWidth, 0f),
                                    new Vector3(1, 0, 0)); // :262
                                float nextPosZ = nextPos.Z; // :263
                                nextPos = new Vector3(-GpfPitch.PitchHalfW, GpfPitch.GoalHalfWidth, 0f)
                                    + normal * (postRadius + ballRadius); // :264
                                nextPos.Z = nextPosZ; // :265
                                woodwork = true;      // :266
                            }
                        }
                        else // :269 — правая половина поля
                        {
                            if (nextPos.Y < 0f) // :271 — «нижняя» сторона
                            {
                                normal = BluntMath.GetNormalized(
                                    BluntMath.Get2D(nextPos) - new Vector3(GpfPitch.PitchHalfW, -GpfPitch.GoalHalfWidth, 0f),
                                    new Vector3(-1, 0, 0)); // :273
                                float nextPosZ = nextPos.Z; // :274
                                nextPos = new Vector3(GpfPitch.PitchHalfW, -GpfPitch.GoalHalfWidth, 0f)
                                    + normal * (postRadius + ballRadius); // :275
                                nextPos.Z = nextPosZ; // :276
                                woodwork = true;      // :277
                            }
                            else // :279 — «верхняя» сторона
                            {
                                normal = BluntMath.GetNormalized(
                                    BluntMath.Get2D(nextPos) - new Vector3(GpfPitch.PitchHalfW, GpfPitch.GoalHalfWidth, 0f),
                                    new Vector3(-1, 0, 0)); // :281
                                float nextPosZ = nextPos.Z; // :283
                                nextPos = new Vector3(GpfPitch.PitchHalfW, GpfPitch.GoalHalfWidth, 0f)
                                    + normal * (postRadius + ballRadius); // :284
                                nextPos.Z = nextPosZ; // :285
                                woodwork = true;      // :286
                            }
                        }

                        // :291 — отражение: постабсорб 0.8, вертикальная компонента сохраняется
                        momentumPredict =
                            GetNormalizedUnchecked(
                                BluntMath.GetNormalized(BluntMath.Get2D(momentumPredict), normal)
                                + (normal * 1.1f))
                            * GetLength(BluntMath.Get2D(momentumPredict)) * postAbsorbInv
                            + (new Vector3(0, 0, 1) * momentumPredict.Z);
                    }


                    // перекладина (:295-322) — в плоскости XZ, юниты Y сохраняются

                    Vector3 nextPosXZ = nextPos * new Vector3(1, 0, 1); // :297
                    if (GetLength(GetAbsolute(nextPosXZ) - new Vector3(GpfPitch.PitchHalfW, 0f, GpfPitch.GoalHeight))
                            < ballRadius + postRadius &&
                        Mathf.Abs(nextPos.Y) < GpfPitch.GoalHalfWidth + ballRadius + postRadius) // :298-299
                    {
                        Vector3 normal;

                        if (nextPos.X < 0f) // :302 — левая половина поля
                        {
                            normal = BluntMath.GetNormalized(
                                nextPosXZ - new Vector3(-GpfPitch.PitchHalfW, 0f, GpfPitch.GoalHeight),
                                new Vector3(0, 0, 1)); // :304
                            float nextPosY = nextPos.Y; // :305
                            nextPos = new Vector3(-GpfPitch.PitchHalfW, 0f, GpfPitch.GoalHeight)
                                + normal * (postRadius + ballRadius); // :306
                            nextPos.Y = nextPosY; // :307
                            woodwork = true;      // :308
                        }
                        else // :310 — правая половина поля
                        {
                            normal = BluntMath.GetNormalized(
                                nextPosXZ - new Vector3(GpfPitch.PitchHalfW, 0f, GpfPitch.GoalHeight),
                                new Vector3(0, 0, -1)); // :312
                            float nextPosY = nextPos.Y; // :313
                            nextPos = new Vector3(GpfPitch.PitchHalfW, 0f, GpfPitch.GoalHeight)
                                + normal * (postRadius + ballRadius); // :314
                            nextPos.Y = nextPosY; // :315
                            woodwork = true;      // :316
                        }

                        Vector3 momentumPredictXZ = momentumPredict * new Vector3(1, 0, 1); // :320
                        momentumPredict =
                            GetNormalizedUnchecked(
                                BluntMath.GetNormalized(momentumPredictXZ, normal) + (normal * 1.1f))
                            * GetLength(momentumPredictXZ) * postAbsorbInv
                            + (new Vector3(0, 1, 0) * momentumPredict.Y); // :321
                    }

                    // шов (:324-327): звук удара о штангу вырезан — единственный потребитель woodwork
                    _ = woodwork;
                }


                // СЕТКА ВЫРЕЗАНА (:331-408): решение роадмапа — сеткой занимается наш NetSim;
                // ballTouchesNet не переносится


                // вращение (:411-481)

                if (nextPos.Z < 0.11f + GrassHeight && groundRotationEffectsEnabled) // :413
                {
                    // вращение от трения о газон (:418-419)
                    float xR, yR;

                    // x-движение крутит вокруг оси y (:421)
                    float radius = 0.11f;                  // :422
                    xR = momentumPredict.Y / radius;       // :423
                    yR = momentumPredict.X / radius;       // :424

                    // кламп (:426): быстрее вертеть нельзя — математика перестанет понимать направление
                    Quaternion rotX = QuatUtil.AngleAxis(
                        Mathf.Clamp(xR * 0.001f, -Mathf.Pi * 0.49f, Mathf.Pi * 0.49f), new Vector3(-1, 0, 0)); // :427-428
                    Quaternion rotY = QuatUtil.AngleAxis(
                        Mathf.Clamp(yR * 0.001f, -Mathf.Pi * 0.49f, Mathf.Pi * 0.49f), new Vector3(0, 1, 0));  // :429-430

                    Quaternion groundRot = rotX * rotY; // :432

                    Quaternion oldToNewRotation =
                        QuatUtil.GetNormalized(QuatUtil.GetRotationTo(rotationPredictMs, groundRot)); // :434
                    float rotationChangePerSecond =
                        Mathf.Abs(QuatUtil.GetRotationAngle(oldToNewRotation, Quaternion.Identity)) * 1000.0f; // :435

                    float maxRotationChangePerSecond = 1.0f * Mathf.Pi * grassInfluenceBias; // :437
                    // мяч влип в землю (:438-439): случается один раз на отскок (frictionFactor)
                    if (frictionFactor > 0.0f) // :440
                    {
                        maxRotationChangePerSecond += 4.0f * Mathf.Pi; // :441
                    }
                    float factor = 1.0f; // :443 — volatile оригинала: только анти-оптимизация компилятора
                    if (rotationChangePerSecond > maxRotationChangePerSecond) // :444
                    {
                        factor = maxRotationChangePerSecond / rotationChangePerSecond; // :445
                    }
                    if (factor < 1.0f) // :447
                    {
                        oldToNewRotation = QuatUtil.GetRotationMultipliedBy(oldToNewRotation, factor); // :448
                    }

                    Quaternion newRotationPredictMs = oldToNewRotation * rotationPredictMs; // :451


                    // обратное влияние вращения на движение (:454-463) — от СТАРОГО rotationPredictMs

                    QuatUtil.GetAngles(rotationPredictMs, out float x, out float y, out float z); // :456-457
                    x = -x; // :458

                    // как быстро ехал бы мяч, забери мы 100% его вращения (:460-463);
                    // оси нарочно перепутаны местами (качение: x-скорость ↔ y-вращение)
                    Vector3 ballRotationMomentum = Vector3.Zero;
                    ballRotationMomentum.X = y * radius * 1000.0f; // :462
                    ballRotationMomentum.Y = x * radius * 1000.0f; // :463

                    // микс (:465-466): меньше = мяч легче, больше = контакт «резиновее»
                    float rotBias = 0.01f;          // :466
                    rotBias *= grassInfluenceBias;  // :467

                    // мяч влип в землю (:469-470) — раз на отскок
                    if (frictionFactor > 0.0f) // :471
                    {
                        rotBias += 0.5f * frictionFactor; // :472
                    }
                    rotBias = Mathf.Clamp(rotBias, 0.0f, 1.0f); // :474
                    momentumPredict.X = momentumPredict.X * (1.0f - rotBias) + ballRotationMomentum.X * rotBias; // :475
                    momentumPredict.Y = momentumPredict.Y * (1.0f - rotBias) + ballRotationMomentum.Y * rotBias; // :476


                    // и лишь теперь применяем накопленное вращение от качения (:479-480)
                    rotationPredictMs = newRotationPredictMs; // :480
                }


                // магнус (:484-501)

                if (swerveEnabled) // :486
                {
                    QuatUtil.GetAngles(rotationPredictMs, out float rvx, out float rvy, out float rvz); // :487-488
                    Vector3 rotVec = new Vector3(rvx, rvy, rvz);
                    rotVec *= 10.0f; // :489

                    // сила магнуса спадает после определённой скорости (:491-495)
                    float swerveAmount = BluntMath.NormalizedClamp(GetLength(momentumPredict), 0.0f, 70.0f); // :492
                    swerveAmount = Mathf.Pow(Mathf.Sin(swerveAmount * Mathf.Pi * 0.94f), 2.6f); // :495
                    Vector3 adaptedMomentumPredict =
                        BluntMath.GetNormalized(momentumPredict, Vector3.Zero) * swerveAmount * 30.0f; // :496

                    Vector3 swerve = adaptedMomentumPredict.Cross(-rotVec) * 1.0f; // :498

                    momentumPredict += swerve * timeStep; // :500
                }


                // интеграция следующего шага (:504-514)

                nextPos += momentumPredict * timeStep; // :506

                // пара GetAngles → *= timeStep/0.001 → SetAngles НЕ взаимно-обратна (перестановки
                // осей C++ не гасятся) — асимметрия входит в интегрирование вращения, bug-for-bug
                // (см. комментарий над QuatUtil.SetAngles)
                QuatUtil.GetAngles(rotationPredictMs, out float rx, out float ry, out float rz); // :508-509
                Vector3 rotationVector = new Vector3(rx, ry, rz);
                rotationVector *= timeStep / 0.001f; // :510
                Quaternion rotationPredictTimeStepped =
                    QuatUtil.SetAngles(rotationVector.X, rotationVector.Y, rotationVector.Z); // :511-512

                nextOrientation = rotationPredictTimeStepped * nextOrientation; // :514 — умножение СЛЕВА

                if (predictTimeMs % 10 == 0) // :516 — при шаге 10 мс это каждый виток
                {
                    if (AutoDegradeTimeStep) // :518 — мёртвая ветка (false), перенесена дословно
                    {
                        if (predictTimeMs == 100) timeStep = 0.005f; // :519
                        if (predictTimeMs == 200) timeStep = 0.01f;  // :520
                        // :521 — выше 0.01f нельзя: в кэше остались бы дыры (комментарий оригинала)
                    }

                    _predictions[predictTimeMs / 10] = nextPos; // :524
                }

                if (predictTimeMs == 10) // :527 — снапшот нового состояния на 10 мс
                {
                    newMomentum = momentumPredict;      // :528
                    newRotationMs = rotationPredictMs;  // :529
                    _orientPrediction = nextOrientation; // :530
                }

                firstTime = false; // :533
            }

            return new BallSpatialInfo(newMomentum, newRotationMs); // :536
        }

        // ball.cpp:539-551 — среднее по хвосту истории позиций (записи каждые 10 мс)
        public Vector3 GetAveragePosition(int durationMs)
        {
            uint total = 0;      // :541
            Vector3 averageVec = Vector3.Zero; // :542
            for (int i = _ballPosHistory.Count - 1; i >= 0; i--) // :540, :543 — с конца
            {
                averageVec += _ballPosHistory[i]; // :544
                total++;                          // :545
                if (total * 10 > (uint)durationMs) break; // :546 — unsigned-сравнение оригинала
            }
            if (total > 0) averageVec /= total; else averageVec = Predict(0); // :549
            return averageVec; // :550
        }

        // ball.cpp:562-585 минус debug-клавиша BACKSPACE (:564-569, телепорт мяча к игроку)
        public void Process()
        {
            BallSpatialInfo spatialInfo = CalculatePrediction(); // :571
            _momentum = spatialInfo.Momentum;                    // :572
            _rotationMs = spatialInfo.RotationMs;                // :573

            _positionBuffer = Predict(10);        // :575
            _orientationBuffer = _orientPrediction; // :576

            _ballPosHistory.Add(_positionBuffer); // :578
            // :579 — КВИРК оригинала: кап сравнивает ЧИСЛО ЗАПИСЕЙ с ballHistorySize_ms (4000),
            // а записи идут раз в 10 мс — фактическая глубина истории 40 секунд, не 4
            if (_ballPosHistory.Count > GpfPitch.BallHistorySizeMs) _ballPosHistory.RemoveAt(0);

            // :581 changedMomentum = momentum - previousMomentum — вычислялся и не использовался

            _previousMomentum = _momentum;        // :583
            _previousPosition = _positionBuffer;  // :584
        }

        // ball.cpp:602-615
        public void ResetSituation(Vector3 focusPos)
        {
            _momentum = Vector3.Zero;           // :603
            _rotationMs = Quaternion.Identity;  // :604
            for (int i = 0; i < GpfPitch.BallPredictionSizeMs / 10; i++) // :605
            {
                _predictions[i] = focusPos + new Vector3(0, 0, 0.11f); // :606
            }
            _orientPrediction = Quaternion.Identity; // :608
            _ballPosHistory.Clear();                 // :609
            _previousMomentum = Vector3.Zero;        // :610
            _previousPosition = focusPos + new Vector3(0, 0, 0.11f); // :611
            _positionBuffer = focusPos + new Vector3(0, 0, 0.11f);   // :612
            _orientationBuffer = Quaternion.Identity; // :613
            // :614 ballTouchesNet — вырезан вместе с сеткой
        }
    }
}

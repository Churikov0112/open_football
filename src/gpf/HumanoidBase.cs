using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // Порт контура состояния movement-пути HumanoidBase (humanoidbase.cpp): порядок тика Process
    // (:569-714, без ReQueue/Trip — в лабе только Switch на границе клипа), movement-ветка SelectAnim
    // (:1374-1601), CalculateOutgoingMovement (:1617-1620), CalculateSpatialState (:1622-1726),
    // CalculateFactualSpatialState (:1728-1737). Один тик = 10 мс = один кадр анимации.
    // ВАЖНО: игроки инстанцируются как Humanoid (player.cpp:88; голый HumanoidBase — судьи),
    // поэтому по НАСЛЕДНИКУ портированы: лерп rotationSmuggleOffset с 16-кадровым капом
    // (humanoid.cpp:722-742), «hax»-формула desiredBodyDirectionRel (humanoid.cpp:1664-1665) и,
    // с фазы 4 задачи 3, сам ОТБОР клипов движения — через цепочку Humanoid::SelectAnim
    // (голова BuildCrudeDataSet humanoid.cpp:1244-1365, движенческая strict-ветка :1441-1455,
    // общая сорт-цепочка :1556-1637; порт — src/gpf/Humanoid.cs, метод SelectNextMovementAnim
    // здесь лишь собирает PlayerCommand и делегирует). Это закрывает бывший открытый вопрос
    // фазы 3: движение раньше по ошибке шло по базовому AnimSelector (humanoidbase.cpp,
    // фаза 2) — расхождение с путём игроков было задокументировано в
    // docs/wiki/открытые-вопросы.md. AnimSelector.SelectMovementInternal остался портом базовой
    // ветки для судей (голый HumanoidBase), которые SelectAnim наследника не вызывают. Порядок
    // тика и startPos/startAngle наследника совпадают с базой (humanoid.cpp:120-138, :270-271).
    // Smuggle-поля (Action*/Movement*-офсеты и *Movement в SpatialState) до фазы 4 — нули,
    // но участвуют в формулах дословно.
    public partial class HumanoidBase : RefCounted
    {
        // humanoid.cpp:42; static readonly (не const) — иначе CS0429 в инициализаторе ниже
        // (правило global-constraints для выключенных флагов оригинала)
        private static readonly bool AnimSmoothing = true;
        private const float BodyRotationSmoothingFactor = 1.0f;        // humanoid.cpp:54
        private static readonly float BodyRotationSmoothingMaxAngle =
            AnimSmoothing ? 0.25f * Mathf.Pi : 0.0f;                   // humanoid.cpp:55

        // humanoidbase.cpp:1691 — мёртвая else-ветка портируется под readonly-флагом (не const:
        // CS0162 unreachable code на живой сборке)
        private static readonly bool PreferCorrectVeloOverCorrectAngle = true;

        // humanoid.cpp:64 (false) — pre-touch ветка rotation-смаггла (:731, :2113)
        private static readonly bool AllowPreTouchRotationSmuggle = false;

        // enum e_InterruptAnim (humanoidbase.hpp:47-55) → int-константы порта.
        internal const int InterruptNone = 0;
        internal const int InterruptSwitch = 1;
        internal const int InterruptSliding = 2;
        internal const int InterruptBump = 3;
        internal const int InterruptTrip = 4;
        internal const int InterruptCheat = 5;
        internal const int InterruptCancel = 6;
        internal const int InterruptReQueue = 7;

        // struct Anim (humanoidbase.hpp:85-112) — с задачи 5 фазы 4 несёт весь smuggle-контур.
        private class CurrentAnimState
        {
            public int Id = -1;
            public Animation Anim = null!;
            public int FrameNum;
            public int FunctionType = AnimCollection.FnMovement; // hpp:89
            public int OriginatingInterrupt = InterruptNone;     // hpp:90
            public int TouchFrame = -1;                          // hpp:97 (-1 == клип без касания)
            public float RadiusOffset;                           // hpp:96
            public Vector3 TouchPos;                             // hpp:98
            public List<Vector3> Positions = new();
            public float RotationSmuggleBegin, RotationSmuggleEnd, RotationSmuggleOffset;
            public Vector3 IncomingMovement, OutgoingMovement;
            public Vector3 FullActionSmuggle, ActionSmuggle, ActionSmuggleOffset;      // hpp:99-101
            public Vector3 ActionSmuggleSustain, ActionSmuggleSustainOffset;           // hpp:102-103
            public Vector3 MovementSmuggle, MovementSmuggleOffset;                     // hpp:104-105
            public Vector3 PositionOffset;                                             // hpp:106
            public PlayerCommand OriginatingCommand = new();                           // hpp:111
        }

        // previousAnim (humanoidbase.hpp:236) — УСЕЧЁННАЯ копия: в C++ `*previousAnim =
        // *currentAnim` (:1759) копирует весь struct, но живые потребители порта — только
        // functionType (правило smoothFactor humanoid.cpp:277, requeue-делэй :319 — задача 6)
        // и frameNum (инкремент :124). Расширять по мере появления потребителей.
        private class PreviousAnimState
        {
            public int FunctionType = AnimCollection.FnMovement;
            public int FrameNum;
        }

        private AnimCollection _anims = null!;
        private AnimSelector _selector = null!;
        private readonly PhysicsVector _physics = new();
        private SpatialState _spatial = new();
        private Vector3 _startPos;           // humanoidbase.hpp:238 startPos
        private float _startAngle;           // humanoidbase.hpp:239 startAngle
        private Vector3 _nextStartPos;       // humanoidbase.hpp:240 nextStartPos
        private float _nextStartAngle;       // humanoidbase.hpp:241 nextStartAngle
        private Vector3 _previousPosition2D; // humanoidbase.hpp:263
        private readonly CurrentAnimState _current = new();
        private readonly PreviousAnimState _previous = new(); // см. комментарий у класса
        // animApplyBuffer (humanoidbase.hpp:133-162) — подмножество пути игроков; с задачи 5
        // добавлены smooth/smoothFactor (закрывает открытый вопрос фазы 3)
        private int _applyFrameNum;
        private Vector3 _applyPosition;
        private float _applyOrientation;
        private bool _applyNoPos;
        private bool _applySmooth = true;         // humanoidbase.hpp:137 (дефолт конструктора)
        private float _applySmoothFactor = 0.5f;  // humanoidbase.hpp:138 (дефолт конструктора)

        public void Setup(AnimCollection anims, AnimSelector selector)
        {
            _anims = anims;
            _selector = selector;
        }

        // Все 6 статов = preset (лаба; дефолты PhysicsVector — 0.6 по humanoidbase.cpp:2021-2024)
        public void SetStatsPreset(float preset) =>
            _physics.SetStats(preset, preset, preset, preset, preset, preset);

        // Аналог ResetPosition (humanoidbase.cpp:929-971) для лаборатории: угол задаётся напрямую
        // (в оригинале — из focusPos, :932). ОТКЛОНЕНИЕ от :954: там frameNum = random(0,
        // effectiveFrameCount-1) — лаба детерминирована, стартуем с кадра 0.
        public void ResetSituation(Vector3 position, float angle)
        {
            _startPos = position;                       // :931
            _startAngle = angle;                        // :932
            _nextStartPos = _startPos;                  // :933
            _nextStartAngle = _startAngle;              // :934
            _previousPosition2D = position;             // :935
            // :937-947 — остальные поля покрывают дефолты SpatialState (в т.ч. foot = Right, :947)
            _spatial = new SpatialState
            {
                Position = position,                    // :937
                Angle = angle,                          // :938
                DirectionVec = BluntMath.GetRotated2D(new Vector3(0, -1, 0), angle), // :939
            };

            _current.Id = _anims.GetIdleMovementAnimID();   // :949-950
            _current.Anim = _anims.GetAnim(_current.Id);    // :951
            _current.Positions.Clear();                     // :952
            // :953 — КОПИЯ кэша (в C++ vector копируется по значению; ссылку отдавать нельзя —
            // Clear при следующем выборе клипа стёр бы кэш коллекции)
            _current.Positions.AddRange(_anims.GetPositionCacheInternal(_current.Id));
            _current.FrameNum = 0;                          // вместо random :954 (см. выше)
            _current.RadiusOffset = 0.0f;                   // :955
            _current.TouchFrame = -1;                       // :956
            _current.OriginatingInterrupt = InterruptNone;  // :957
            _current.FullActionSmuggle = Vector3.Zero;          // :958
            _current.ActionSmuggle = Vector3.Zero;              // :959
            _current.ActionSmuggleOffset = Vector3.Zero;        // :960
            _current.ActionSmuggleSustain = Vector3.Zero;       // :961
            _current.ActionSmuggleSustainOffset = Vector3.Zero; // :962
            _current.MovementSmuggle = Vector3.Zero;            // :963
            _current.MovementSmuggleOffset = Vector3.Zero;      // :964
            _current.RotationSmuggleBegin = 0;              // :965
            _current.RotationSmuggleEnd = 0;                // :966
            _current.RotationSmuggleOffset = 0;             // :967
            _current.FunctionType = AnimCollection.FnMovement; // :968
            _current.IncomingMovement = Vector3.Zero;       // :969
            _current.OutgoingMovement = Vector3.Zero;       // :970
            _current.PositionOffset = Vector3.Zero;         // :971
            _current.OriginatingCommand = new PlayerCommand();
            // previousAnim (:973-994) — усечённая копия, см. PreviousAnimState
            _previous.FunctionType = AnimCollection.FnMovement; // :991
            _previous.FrameNum = 0;                             // :977

            // apply-буфер стартового состояния (до первого Tick) — аналог :996-1004;
            // noPos = false — дефолт конструктора AnimApplyBuffer (humanoidbase.hpp:139),
            // ResetPosition его не трогает
            _applyFrameNum = 0;
            _applyPosition = position;                      // :1001
            _applyOrientation = angle;                      // :1002
            _applyNoPos = false;
            _applySmooth = false;                           // :999
            _applySmoothFactor = 0.0f;                      // :1000
        }

        // Один тик — порядок Humanoid::Process наследника (humanoid.cpp:97-781; ссылки ниже —
        // humanoid.cpp, если не сказано иное). Возвращает true при смене клипа.
        // wantBall — ВРЕМЕННЫЙ ЛАБ-ВВОД (нет Player::RequestCommand, :225): true кладёт в очередь
        // команд BallControl-команду перед движ-командой. Задача 6 заменит на очередь команд,
        // задача 8 — на клавиши.
        public bool Tick(Vector3 desiredDirectionWorld, float desiredVelocityFloat, bool wantBall,
                         bool useDesiredLookAt, Vector3 desiredLookAt)
        {
            // ШОВ match->GetActualTime_ms(): матчевое время тикает +10 мс на тик 100 Гц
            // (поле — Humanoid.cs; потребитель — GetLastTouchBias, humanoid.cpp:2204)
            _actualTimeMs += 10;
            CalculateSpatialState();                        // :120
            _spatial.PositionOffsetMovement = Vector3.Zero; // :121
            _current.FrameNum++;                            // :123
            _previous.FrameNum++;                           // :124

            /*
            // bump-прерывание (:129-134) — ЗАКОММЕНТИРОВАН в оригинале («todo: work in progress»),
            // переносится комментарием:
            // if (currentAnim->positionOffset.GetLength() > 0.1f && interruptAnim == e_InterruptAnim_None) {
            //   interruptAnim = e_InterruptAnim_Bump;
            // }
            */

            bool switched = false;
            int interruptAnim = InterruptNone;
            // на границе клипа — Switch-прерывание (:136-138)
            if (_current.FrameNum == _current.Anim.GetFrameCount() - 1 && interruptAnim == InterruptNone)
                interruptAnim = InterruptSwitch;

            // ReQueue-машинерия (:140-212) — задача 6; в лабе interrupt только Switch.

            if (interruptAnim != InterruptNone)             // :214
            {
                // ШОВ Player::RequestCommand (:225): очереди контроллера нет — собираем её из
                // лаб-входов тика. wantBall → BallControl-команда первой (контроллер оригинала
                // кладёт тач-команды перед движ-фолбэком), затем движ-команда (тот же набор
                // полей, что движ-команда фазы 3).
                var commandQueue = new List<PlayerCommand>(); // :218
                if (wantBall)
                    commandQueue.Add(new PlayerCommand
                    {
                        DesiredFunctionType = AnimCollection.FnBallControl,
                        UseDesiredMovement = true,
                        DesiredDirection = desiredDirectionWorld,
                        DesiredVelocityFloat = desiredVelocityFloat,
                        UseDesiredLookAt = useDesiredLookAt,
                        DesiredLookAt = desiredLookAt,
                    });
                commandQueue.Add(new PlayerCommand
                {
                    DesiredFunctionType = AnimCollection.FnMovement,
                    UseDesiredMovement = true,
                    DesiredDirection = desiredDirectionWorld,
                    DesiredVelocityFloat = desiredVelocityFloat,
                    UseDesiredLookAt = useDesiredLookAt,
                    DesiredLookAt = desiredLookAt,
                });

                // первый применимый из очереди (:229-247)
                bool found = false;                          // :231
                bool preferPassAndShot = false;              // :232 (пас/удар в очереди — задача 8)
                foreach (var command in commandQueue)        // :233-247
                {
                    // :237-242 preferPassAndShot по типам пас/удар — команд таких типов
                    // лаб-очередь не порождает
                    found = SelectAnim(command, interruptAnim, preferPassAndShot); // :245
                    if (found) break;                        // :246
                }

                if (interruptAnim == InterruptSwitch && !found)
                {
                    // «RED ALERT» (:249-267) в лабе недостижим: движ-команда в очереди всегда
                    // есть, а её отбор несёт idle-фолбэк (:1657-1660). Страховка от вылета на
                    // пустой коллекции: перезапустить текущий клип с нуля (отклонение от
                    // оригинала, где exit(1)/ResetPosition).
                    GD.PushError("Gpf.HumanoidBase: не найден следующий клип — перезапуск текущего");
                    _current.FrameNum = 0;
                }

                if (found)                                   // :269
                {
                    switched = true;
                    _startPos = _spatial.Position;           // :270
                    _startAngle = _spatial.Angle;            // :271
                    CalculatePredictedSituation(out _nextStartPos, out _nextStartAngle); // :273

                    // :275 animApplyBuffer.anim — клип буфера у нас читается по GetCurrentAnimId()
                    _applySmooth = AnimSmoothing;            // :276
                    // :277 — больше сглаживания mid-anim реквеям; movement→movement на Switch = 0
                    _applySmoothFactor = (interruptAnim == InterruptSwitch
                        && _previous.FunctionType == AnimCollection.FnMovement
                        && _current.FunctionType == AnimCollection.FnMovement) ? 0.0f : 1.0f;
                    if (_current.FunctionType == AnimCollection.FnShot)
                        _applySmoothFactor = 0.8f;           // :278
                    if (_current.FunctionType == AnimCollection.FnShortPass ||
                        _current.FunctionType == AnimCollection.FnHighPass)
                        _applySmoothFactor = 0.8f;           // :279-280
                    if (_current.FunctionType == AnimCollection.FnDeflect ||
                        _current.FunctionType == AnimCollection.FnSliding)
                        _applySmoothFactor = 0.8f;           // :281-282
                    if (_current.FunctionType == AnimCollection.FnBallControl ||
                        _current.FunctionType == AnimCollection.FnTrap)
                        _applySmoothFactor = 0.8f;           // :283-284

                    // :288-310 debug-выводы — не переносим; :312-314 decayingDifficultyFactor и
                    // :317-321 reQueueDelayFrames — система сложности/ReQueue, задача 6.
                }
            }
            // :326 reQueueDelayFrames-- — задача 6; :336 interruptAnim = None — локальная переменная.

            // сторож «FLYING PLAYERS» (:338-340) — живой код
            if (_startPos.Z != 0f)
                GD.PushError("Gpf.HumanoidBase: BWAAAAAH FLYING PLAYERS!! height: " + _startPos.Z);

            // :342-646 — исполнение касания/коллизии мяча (задача 7); :648-665 — superglue
            // ретейнера (задача 7).

            // action smuggle (:668-695)
            // :670-672 — комментарий оригинала: стартуем с +1, чтобы влиять и на первый кадр;
            // финишируем frameBias = 1.0 на предпоследнем кадре — первый кадр следующего клипа
            // «одной температуры» с последним текущего.
            // :673 frameBias — вычислен и НЕ используется дальше в Process, как в оригинале.
            float frameBias = (_current.FrameNum + 1)
                / (float)(_current.Anim.GetEffectiveFrameCount() + 1);         // :673
            _ = frameBias;

            if (_current.TouchFrame != -1 && _current.FrameNum <= _current.TouchFrame) // :675
            {
                // :676-678 линейная версия — *outdated* в оригинале; :681 assert(touchFrame > 0)
                float value = Mathf.Cos((_current.FrameNum / (float)(_current.TouchFrame + 1)
                    - 0.5f) * Mathf.Pi * 2.0f) + 1.0f;                         // :682-686
                value = value * 0.1f + 0.9f;                                   // :689 add some linearity
                _spatial.ActionSmuggleMovement = (_current.ActionSmuggle
                    / (float)(_current.TouchFrame + 1)) * value * 100.0f;      // :690 (м/с)
                _current.ActionSmuggleOffset += _spatial.ActionSmuggleMovement / 100.0f; // :691
            }
            else
            {
                _spatial.ActionSmuggleMovement = Vector3.Zero;                 // :693-694
            }

            // movement smuggle (:698-719)
            // :700 — omit one frame, or balltouch will be influenced because of velo
            if (_current.TouchFrame == -1 && _current.FrameNum <= _current.Anim.GetEffectiveFrameCount())
            {
                float value = Mathf.Cos((_current.FrameNum
                    / (float)(_current.Anim.GetEffectiveFrameCount() + 1)
                    - 0.5f) * Mathf.Pi * 2.0f) + 1.0f;                         // :706-711
                value = value * 0.1f + 0.9f;                                   // :714 add some linearity
                _spatial.MovementSmuggleMovement = (_current.MovementSmuggle
                    / (float)(_current.Anim.GetEffectiveFrameCount() + 1)) * value * 100.0f; // :715
                _current.MovementSmuggleOffset += _spatial.MovementSmuggleMovement / 100.0f; // :716
            }
            else
            {
                _spatial.MovementSmuggleMovement = Vector3.Zero;               // :717-718
            }

            // rotation smuggle — блок НАСЛЕДНИКА Humanoid::Process (humanoid.cpp:722-742), НЕ базы
            // (humanoidbase.cpp:684-695): игроки исполняют версию наследника с 16-кадровым капом
            // ease-in; базовый незакапленный лерп гоняют только судьи.
            int beginRotationFrameCount = 16; // humanoid.cpp:724 — после стольких кадров ease-in готов
            float cappedFrameBias = Mathf.Min(1.0f, (_current.FrameNum + 1)
                / (float)Mathf.Min(beginRotationFrameCount,
                    _current.Anim.GetEffectiveFrameCount() + 1));              // :725
            float beginFrameBias = cappedFrameBias;                            // :726
            float endFrameBias = cappedFrameBias;                              // :727
            if (_current.TouchFrame != -1) // :728 — с задачи 5 ветка ЖИВАЯ (тач-клипы)
            {
                // beginFrameBias идёт 0→1 за кадры 0..min(touchFrame, beginRotationFrameCount) (:729-730)
                beginFrameBias = Mathf.Min(1.0f, (_current.FrameNum + 1)
                    / (float)Mathf.Min(beginRotationFrameCount, _current.TouchFrame + 1));
                if (!AllowPreTouchRotationSmuggle)                             // :731 (humanoid.cpp:64)
                {
                    if (_current.FrameNum > _current.TouchFrame)
                    {
                        // end-смаггл начинается после касания (:732-734)
                        endFrameBias = (_current.FrameNum - _current.TouchFrame)
                            / (float)(_current.Anim.GetEffectiveFrameCount() - _current.TouchFrame);
                    }
                    else
                    {
                        endFrameBias = 0.0f;                                   // :735-737 — до касания смаггла нет
                    }
                }
            }
            _current.RotationSmuggleOffset = _current.RotationSmuggleBegin * (1.0f - beginFrameBias)
                + _current.RotationSmuggleEnd * endFrameBias;                  // :741-742

            // apply-данные — порядок слагаемых НАСЛЕДНИКА (:763-780): startPos + positions[fn]
            // + actionSmuggleOffset + actionSmuggleSustainOffset + movementSmuggleOffset (:769).
            // Закрывает открытый вопрос фазы 3 (база :703 складывала смагглы до positions —
            // при нулевых смагглах численно то же самое, walker не должен дрогнуть).
            _applyFrameNum = _current.FrameNum;                                // :765
            if (_current.Positions.Count > _current.FrameNum)                  // :767
            {
                _applyPosition = _startPos + _current.Positions[_current.FrameNum]
                    + _current.ActionSmuggleOffset + _current.ActionSmuggleSustainOffset
                    + _current.MovementSmuggleOffset;                          // :769
                _applyOrientation = _startAngle + _current.RotationSmuggleOffset; // :770
                _applyNoPos = true;                                            // :772
            }
            else                                                               // :773-778
            {
                // :774 debug printf — не переносим
                _applyPosition = _startPos + _current.ActionSmuggleOffset
                    + _current.ActionSmuggleSustainOffset + _current.MovementSmuggleOffset; // :775
                _applyOrientation = _startAngle;                               // :776
                _applyNoPos = false;                                           // :777
            }
            // :780 animApplyBuffer.offsets — offsets не портированы (пустые)
            return switched;
        }

        // CalculatePredictedSituation (humanoidbase.cpp:1603-1615): позиция/угол на конец
        // текущего клипа с учётом ПОЛНЫХ смагглов (не офсетов). Потребители: CalculateMovementSmuggle
        // (humanoid.cpp:2351), пост-выбор тика (:273), ReQueue задачи 6, touch-исполнение задачи 7.
        internal void CalculatePredictedSituation(out Vector3 predictedPos, out float predictedAngle)
        {
            if (_current.Positions.Count > _current.FrameNum)                  // :1605
            {
                // assert(positions.size() > effectiveFrameCount) (:1606) — не переносим
                predictedPos = _spatial.Position
                    + _current.Positions[_current.Anim.GetEffectiveFrameCount()]
                    + _current.ActionSmuggle + _current.ActionSmuggleSustain
                    + _current.MovementSmuggle;                                // :1607
            }
            else                                                               // :1608-1610
            {
                predictedPos = _spatial.Position
                    + BluntMath.GetRotated2D(BluntMath.Get2D(_current.Anim.GetTranslation()),
                        _spatial.Angle)
                    + _current.ActionSmuggle + _current.ActionSmuggleSustain
                    + _current.MovementSmuggle;                                // :1609
            }

            predictedAngle = _spatial.Angle + _current.Anim.GetOutgoingAngle()
                + _current.RotationSmuggleEnd;                                 // :1612
            predictedAngle = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi, predictedAngle); // :1613
            // assert(predictedPos.coords[2] == 0.0f) (:1614) — не переносим
        }

        // ФАЗА 4, задача 5: выбор клипа целиком переехал в Humanoid::SelectAnim наследника
        // (Humanoid.cs, humanoid.cpp:1159-1820) — единый путь для movement- И action-команд.
        // Бывший SelectNextMovementAnim (movement-обёртка задачи 3) поглощён им же:
        // движ-ветка (:1667-1680) и заполнение Anim (:1747-1786) — там.

        // humanoidbase.cpp:1617-1620
        private static Vector3 CalculateOutgoingMovement(List<Vector3> positions)
        {
            if (positions.Count < 2) return Vector3.Zero;                      // :1618
            return (positions[positions.Count - 1] - positions[positions.Count - 2]) * 100.0f; // :1619
        }

        // humanoidbase.cpp:1622-1726
        private void CalculateSpatialState()
        {
            Vector3 position;
            if (_current.Positions.Count > _current.FrameNum)                  // :1624
            {
                position = _startPos + _current.Positions[_current.FrameNum]
                    + _current.ActionSmuggleOffset + _current.ActionSmuggleSustainOffset
                    + _current.MovementSmuggleOffset;                          // :1625
            }
            else                                                               // :1626-1631
            {
                position = _current.Anim.SampleRootPosition(_current.FrameNum, 0f); // :1628 GetKeyFrame("player")
                position.Z = 0.0f;                                             // :1629
                position = _startPos + BluntMath.GetRotated2D(position, _startAngle)
                    + _current.ActionSmuggleOffset + _current.ActionSmuggleSustainOffset
                    + _current.MovementSmuggleOffset;                          // :1630
            }

            if (_current.FrameNum > 12)                                        // :1633-1635
                _spatial.Foot = _current.Anim.GetOutgoingFootId();             // :1634

            _spatial.ActualMovement = (position - _previousPosition2D) * 100.0f; // :1642
            float positionOffsetMovementIgnoreFactor = 0.5f;                   // :1643
            _spatial.PhysicsMovement = _spatial.ActualMovement
                - _spatial.ActionSmuggleMovement - _spatial.MovementSmuggleMovement
                - _spatial.PositionOffsetMovement * positionOffsetMovementIgnoreFactor; // :1644
            _spatial.AnimMovement = _spatial.PhysicsMovement;                  // :1645
            if (_current.Positions.Count > 0)                                  // :1646-1651
            {
                // экшн-чит исключается из текущего движения — лучшие реквеи; но офсеты от
                // столкновений с игроками так тоже игнорируются (коммент. оригинала :1647-1648)
                List<Vector3> origPositionCache = _anims.GetPositionCacheInternal(_current.Id); // :1649
                _spatial.AnimMovement = BluntMath.GetRotated2D(
                    PhysicsVector.CalculateMovementAtFrame(origPositionCache, _current.FrameNum, 1),
                    _startAngle);                                              // :1650
            }
            _spatial.Movement = _spatial.PhysicsMovement;                      // :1655 PICK DEFAULT

            Quaternion bodyOrientation =
                _current.Anim.GetInterpolatedRotation("body", _current.FrameNum); // :1662 GetKeyFrame("body")
            QuatUtil.GetAngles(bodyOrientation, out _, out _, out float z);    // :1663-1664

            Vector3 bodyDirectionVec = BluntMath.GetRotated2D(new Vector3(0, -1, 0),
                z + _startAngle + _current.RotationSmuggleOffset);             // :1668

            _spatial.FloatVelocity = _spatial.Movement.Length();               // :1670
            _spatial.EnumVelocity = Velo.FloatToEnumVelocity(_spatial.FloatVelocity); // :1671

            if (_spatial.EnumVelocity != Velo.IdVelIdle)                       // :1673-1674
                _spatial.DirectionVec = BluntMath.GetNormalized(_spatial.Movement, Vector3.Zero);
            else                                                               // :1675-1678
                _spatial.DirectionVec = bodyDirectionVec; // слишком медленно — направление тела

            _spatial.Position = position;                                      // :1680
            _spatial.Angle = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi,
                BluntMath.FixAngle(BluntMath.GetAngle2D(_spatial.DirectionVec))); // :1681

            if (_spatial.EnumVelocity != Velo.IdVelIdle)                       // :1683
            {
                Vector3 adaptedBodyDirectionVec =
                    BluntMath.GetRotated2D(bodyDirectionVec, -_spatial.Angle); // :1684

                float bodyAngleRel = BluntMath.GetAngle2D(adaptedBodyDirectionVec,
                    new Vector3(0, -1, 0));                                    // :1692
                if (_spatial.EnumVelocity == Velo.IdVelSprint
                    && Mathf.Abs(bodyAngleRel) >= 0.125f * Mathf.Pi)           // :1693
                {
                    if (PreferCorrectVeloOverCorrectAngle)
                    {
                        // невозможная пара скорость×угол → уменьшаем угол (:1695-1696)
                        adaptedBodyDirectionVec = BluntMath.GetRotated2D(new Vector3(0, -1, 0),
                            0.12f * Mathf.Pi * BluntMath.SignSide(bodyAngleRel));
                    }
                    else
                    {
                        // мёртвая ветка (:1698-1700): уменьшаем скорость
                        _spatial.FloatVelocity = Velo.WalkSprintSwitch - 0.1f;
                        _spatial.EnumVelocity = Velo.FloatToEnumVelocity(_spatial.FloatVelocity);
                    }
                }
                else if (_spatial.EnumVelocity == Velo.IdVelWalk
                    && Mathf.Abs(bodyAngleRel) >= 0.5f * Mathf.Pi)             // :1703
                {
                    if (PreferCorrectVeloOverCorrectAngle)
                    {
                        // невозможная пара скорость×угол → уменьшаем угол (:1705-1706)
                        adaptedBodyDirectionVec = BluntMath.GetRotated2D(new Vector3(0, -1, 0),
                            0.495f * Mathf.Pi * BluntMath.SignSide(bodyAngleRel));
                    }
                    else
                    {
                        // мёртвая ветка (:1708-1710): уменьшаем скорость
                        _spatial.FloatVelocity = Velo.DribbleWalkSwitch - 0.1f;
                        _spatial.EnumVelocity = Velo.FloatToEnumVelocity(_spatial.FloatVelocity);
                    }
                }

                _spatial.RelBodyDirectionVecNonquantized = adaptedBodyDirectionVec; // :1714
                _spatial.RelBodyDirectionVec =
                    _selector.ForceIntoAllowedBodyDirectionVec(adaptedBodyDirectionVec); // :1715
            }
            else                                                               // :1716-1719
            {
                _spatial.RelBodyDirectionVecNonquantized = new Vector3(0, -1, 0);
                _spatial.RelBodyDirectionVec = new Vector3(0, -1, 0);
            }
            _spatial.RelBodyAngle = BluntMath.GetAngle2D(_spatial.RelBodyDirectionVec,
                new Vector3(0, -1, 0));                                        // :1720
            _spatial.RelBodyAngleNonquantized = BluntMath.GetAngle2D(
                _spatial.RelBodyDirectionVecNonquantized, new Vector3(0, -1, 0)); // :1721
            _spatial.BodyDirectionVec = BluntMath.GetRotated2D(_spatial.RelBodyDirectionVec,
                _spatial.Angle); // :1722 — поворот обратно, уже в разрешённом угле
            _spatial.BodyAngle = BluntMath.GetAngle2D(_spatial.BodyDirectionVec,
                new Vector3(0, -1, 0));                                        // :1723

            _previousPosition2D = position;                                    // :1725
        }

        // humanoidbase.cpp:1728-1737
        private void CalculateFactualSpatialState()
        {
            _spatial.Foot = _current.Anim.GetOutgoingFootId();                 // :1730
            if (_current.Anim.GetVariable("outgoing_special_state") != "")     // :1732
            {
                _spatial.FloatVelocity = 0;                                    // :1733
                _spatial.EnumVelocity = Velo.IdVelIdle;                        // :1734
                _spatial.Movement = Vector3.Zero;                              // :1735
            }
        }

        // ---- Мост-геттеры (apply-буфер + spatial) для лабы/тестов ----
        public int GetApplyFrameNum() => _applyFrameNum;
        public Vector3 GetApplyPosition() => _applyPosition;
        public float GetApplyOrientation() => _applyOrientation;
        public bool GetApplyNoPos() => _applyNoPos;
        public bool GetApplySmooth() => _applySmooth;
        public float GetSmoothFactor() => _applySmoothFactor;
        // ---- Мост-геттеры smuggle-контура (задача 5) ----
        public Vector3 GetActionSmuggle() => _current.ActionSmuggle;
        public Vector3 GetActionSmuggleOffset() => _current.ActionSmuggleOffset;
        public Vector3 GetMovementSmuggle() => _current.MovementSmuggle;
        public Vector3 GetMovementSmuggleOffset() => _current.MovementSmuggleOffset;
        public int GetCurrentTouchFrame() => _current.TouchFrame;
        public int GetCurrentFrameNum() => _current.FrameNum;
        // Тестовый геттер: apply-позиция БЕЗ смаггл-слагаемых (:769 без офсетов) — чтобы тест
        // видел, что смагглы реально вошли в буфер.
        public Vector3 GetApplyPositionNoSmuggle() =>
            _current.Positions.Count > _current.FrameNum
                ? _startPos + _current.Positions[_current.FrameNum]
                : _startPos;
        public int GetCurrentAnimId() => _current.Id;
        public Vector3 GetSpatialPosition() => _spatial.Position;
        public float GetSpatialAngle() => _spatial.Angle;
        public int GetSpatialEnumVelocity() => _spatial.EnumVelocity;
        public float GetSpatialFloatVelocity() => _spatial.FloatVelocity;
        public Vector3 GetSpatialMovement() => _spatial.Movement;
        public Vector3 GetRelBodyDirectionVec() => _spatial.RelBodyDirectionVec;
        public int GetFoot() => _spatial.Foot;
        // Мост для тестируемости лерпа rotation smuggle (humanoid.cpp:722-742): begin/end живут
        // приватно в CurrentAnimState; тест пересчитывает формулу наследника по ним.
        public float GetRotationSmuggleBegin() => _current.RotationSmuggleBegin;
        public float GetRotationSmuggleEnd() => _current.RotationSmuggleEnd;
    }
}

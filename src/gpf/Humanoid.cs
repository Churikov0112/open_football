using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // ФАЙЛ-НАСЛЕДНИК. В оригинале это методы класса `Humanoid` (humanoid.cpp) — наследника
    // `HumanoidBase`. В порте отдельного класса нет: путь игроков ЕДИН и живёт в `HumanoidBase`,
    // а этот файл — ПАРТИАЛЬНАЯ часть того же класса, куда сложены переопределения наследника.
    // Причина: игроки в оригинале инстанцируются как Humanoid (player.cpp:88), голый HumanoidBase
    // гоняют только судьи — значит ветки наследника и есть «настоящий» путь (главный урок фазы 3).
    // Ссылки вида `:NNNN` в этом файле — humanoid.cpp, если явно не указан другой файл.
    //
    // Здесь: GetHasteFactor (:1143-1157), SelectAnim целиком (:1159-1820) — голова-сборка
    // CrudeSelectionQuery (:1244-1365), KeepBest*-ветки по типам и сорт-цепочка (:1369-1637),
    // ветки Movement/BallControl и «make it so»-заполнение Anim (:1648-1786, задача 5),
    // NeedTouch (:1822-1857), плюс _HighOrBouncyBall (humanoidbase.cpp:1089-1100) — он нужен
    // trap-ветке и до фазы 4 в порт не попадал. С задачи 4 — сердце smuggle-механики:
    // GetFrontOfFootOffsetRel (humanoid_utils.cpp:103-115), GetLastTouchBias
    // (playerbase.cpp:141-146), GetBodyBallDistanceAdvantage (:1859-1997) и
    // GetBestCheatableAnimID (:1999-2323); с задачи 5 — CalculateMovementSmuggle (:2326-2408).
    //
    // С задачи 6 — отказные фильтры ReQueue (:1192-1234) и quadrant-reject (:1727-1742).
    //
    // С задачи 7 — исполнение касания: оптимизации-ранние-выходы SelectAnim (:1163-1189),
    // action-ветки выбора Trap/Interfere/Deflect/пасов/удара/Sliding (:1687-1722),
    // touch-ветки тика (:342-646, ExecuteTouchTick), GetBestPossibleTouch (:2410-2486);
    // формулы touch-векторов — src/gpf/TouchVectors.cs (humanoid_utils.cpp:146-520).
    public partial class HumanoidBase
    {
        // ---- Константы наследника (humanoid.cpp:40-65) ----
        // Флаги — static readonly (не const): мёртвые ветки обязаны компилироваться без CS0162
        // (правило фазы 3). :40-41 (spatial/movementSmuggle debug-пилоны) — чисто отладочная
        // графика, не переносятся. :42 animSmoothing, :54 bodyRotationSmoothingFactor,
        // :55 bodyRotationSmoothingMaxAngle и :64 allowPreTouchRotationSmuggle уже живут в
        // HumanoidBase.cs (фаза 3) — тот же партиальный класс, второй раз не заводим.
        private const float CheatFactor = 0.5f;                 // :43 — общий масштаб смаггл-зоны
        private static readonly bool UseContinuousBallCheck = true; // :44 — окно −6..+3 мс вместо точки
        internal static readonly bool EnableMovementSmuggle = true; // :45 — потребитель CalculateMovementSmuggle (задача 5)
        // :46 — этот кусок чита не «показываем» (мал — красиво, велик — игрок «мажет» мимо мяча);
        // сильно влияет на геймплей, т.к. затрагивает и коллизии игроков
        private const float CheatDiscardDistance = 0.02f;
        // :47 — добавка к разрешённой чит-дистанции (в метрах), тоже не «показываем»
        private const float CheatDistanceBonus = 0.02f;
        private const float CheatDiscardDistanceMultiplier = 0.4f; // :48 — ниже == резче (snappy)
        private const float MaxSmuggleDiscardDistance = 0.2f;   // :49 — кап сброса смаггла (min-квирк :2267)
        private static readonly bool EnableActionSmuggleDiscard = true;    // :50 — включает «чит на чит»
        private static readonly bool ForceFullActionSmuggleDiscard = false; // :51 — сбросить смаггл целиком
        private static readonly bool DiscardForwardSmuggle = true;  // :52 — гасить переднюю компоненту
        private static readonly bool DiscardSidewaysSmuggle = false; // :53 — гасить боковую компоненту
        // ReQueue-константы (:56-63); потребители — гейт тика (:140-212, HumanoidBase.cs) и
        // отказные фильтры SelectAnim (:1192-1234, ниже)
        private const int InitialReQueueDelayFrames = 22;       // :56
        // :57 — осталось меньше кадров? пусть клип доиграет, мы почти у цели
        private const int MinRemainingMovementReQueueFrames = 6;
        // :58 — то же для кадров до touchframe trap-клипа
        private const int MinRemainingTrapReQueueFrames = 6;
        private const int MaxBallControlReQueueFrame = 8;       // :59
        internal static readonly bool AllowReQueue = true;              // :60
        internal static readonly bool AllowMovementReQueue = true;      // :61
        internal static readonly bool AllowBallControlReQueue = true;   // :62
        internal static readonly bool AllowTrapReQueue = true;          // :63
        // :65 — потребитель CheckBallCollisions придёт задачей 7
        internal static readonly bool EnableControlledBallCollisions = true;

        // ---- Зависимости ядра и ШВЫ лаборатории ----
        // В оригинале это Match/Team/Player/MentalImage. В лабе их нет — поля с дефолтами,
        // ветки при этом портируются дословно.

        // match->GetBall(); дефолтный мяч (покоится в центре) — чтобы лаба и старые тесты фазы 3
        // работали без явного SetBall.
        private Ball _ball = new Ball();
        // Единый seeded-генератор ядра (global-constraints №3). Потребители — задачи 5/7.
        private GpfRng _rng = new GpfRng();

        // match->IsInPlay() / IsInSetPiece() (:1564-1565) — в лабе мяч всегда в игре.
        private bool _isInPlay = true;
        private bool _isInSetPiece = false;
        // match->GetBallRetainer() == player (:1307, :1350) — вратарь с мячом в руках; в лабе нет.
        private bool _isBallRetainer = false;
        // Player::AllowLastDitch (player.cpp:141-144) — зависит от GetTimeNeededToGetToBall_ms
        // игрока и владения команды; ни того, ни другого в ядре порта ещё нет.
        private bool _allowLastDitch = false;
        // team->GetTeamPossessionAmount() (:1154-1155) — команд в порте нет; 1.0 = равное владение.
        private float _teamPossessionAmountStub = 1.0f;
        // Лаб-контекст (потребители — задачи 4-5: GetBodyBallDistanceAdvantage и смагглы).
        private float _closestOpponentDistance = 1000.0f;
        private float _playerHeight = 1.92f; // defaultPlayerHeight, gamedefines.hpp:66

        // ШОВ match->GetActualTime_ms(): счётчик времени матча, +10 мс на тик 100 Гц
        // (инкремент — в начале Tick, HumanoidBase.cs). Потребитель — GetLastTouchBias (:2204).
        private long _actualTimeMs = 0;
        // ШОВ PlayerBase::lastTouchTime_ms: время последнего касания мяча; касания появятся
        // задачей 7. ОТКЛОНЕНИЕ от дефолта оригинала (0, playerbase.cpp:150): у них время
        // беззнаковое и «матчевое» (большое), а лаба стартует с 0 — дефолт 0 давал бы ложный
        // биас ~1 в первые 600 мс. По брифу плана до задачи 7 тут «−бесконечность» → биас 0
        // (long.MinValue/2 — без переполнения вычитания).
        private long _lastTouchTimeMs = long.MinValue / 2;
        // ШОВ player->GetStat("technical_ballcontrol") (:2206); дефолт 0.6 — как статы
        // PhysicsVector (humanoidbase.cpp:2021-2024) в лабе.
        private float _statTechnicalBallControl = 0.6f;

        // ШОВ match->GetDesignatedPossessionPlayer() == player (:165, :168, :2330): матча в лабе
        // нет — одинокий игрок с мячом и есть «designated», дефолт true.
        private bool _designatedPossession = true;
        // ШОВ team->GetDesignatedTeamPossessionPlayer() == player (:171, :2330). До задачи 6 оба
        // «designated»-предиката жили одним полем (в :2330 они И-нятся); маска частоты ReQueue
        // (:165-179) различает их ветками, поэтому поле разведено. Дефолт тот же — true.
        private bool _teamDesignatedPossession = true;
        // ШОВ team->GetID() (:166, :169, :172, :175, :178) — сдвиг фазы маски частоты по команде;
        // в лабе команда одна, ID = 0.
        private int _teamId = 0;
        // ШОВ match->GetDesignatedPossessionPlayer()->GetPosition() (:1194): позиция игрока,
        // «назначенного» на мяч. null == этот игрок и есть designated (лаба) → focusDistance 0.
        // Задача 9 (матч) подставит сюда реальную позицию.
        private Vector3? _designatedPossessionPlayerPos = null;
        // ШОВ PlayerBase::GetLastTouchType() (:1229) — тип последнего касания; касания приходят
        // задачей 7, до неё дефолт «касания не было».
        private int _lastTouchType = TouchTypeNone;

        // enum e_TouchType (gamedefines.hpp:111-116) → int-константы порта.
        internal const int TouchTypeIntentionalKicked = 0;    // :112
        internal const int TouchTypeIntentionalNonkicked = 1; // :113
        internal const int TouchTypeAccidental = 2;           // :114
        internal const int TouchTypeNone = 3;                 // :115
        // ---- Швы и состояние задачи 7 (исполнение касания) ----
        // _PassFiddlingEnabled() (humanoid.cpp:88-90) — всегда true; readonly, не const (правило
        // фазы 3: выключаемая ветка обязана компилироваться).
        private static readonly bool PassFiddlingEnabled = true;
        // decayingPositionOffset (humanoidbase.hpp; распад — humanoid.cpp:98-99, сброс —
        // humanoidbase.cpp:1009). Копится столкновениями игроков (humanoidbase.cpp:1040-1041,
        // не портированы) — в лабе остаётся нулём, но контур распада/потребители живут.
        private Vector3 _decayingPositionOffset = Vector3.Zero;
        // Player::TriggerControlledBallCollision / IsControlledBallCollisionTriggered /
        // ResetControlledBallCollisionTrigger (player.hpp) — одиночный флаг.
        private bool _controlledBallCollisionTriggered = false;
        // ЛАБ-ПАРАМЕТР (решение плана): canRetain deflect-ветки (:599-616) в лабе выключен —
        // вратарский контур (ретейнер/superglue) не входит в фазу 4; ветка портирована дословно.
        private bool _labAllowDeflectRetain = false;
        // ШОВ team->GetSide() (team.cpp:102-108): -1 == левая половина (команда 0 в первом
        // тайме); потребитель — deflect-вынос (:620).
        private int _teamSide = -1;
        // ШВЫ player->GetStat(...) — статы задачи 7, дефолт 0.6 (как статы PhysicsVector).
        private float _statMentalCalmness = 0.6f;     // humanoid_utils.cpp:254
        private float _statPhysicalBalance = 0.6f;    // humanoid_utils.cpp:254
        private float _statTechnicalDribble = 0.6f;   // humanoid_utils.cpp:294
        private float _statPhysicalReaction = 0.6f;   // humanoid_utils.cpp:187, humanoid.cpp:609
        private float _statPhysicalShotPower = 0.6f;  // humanoid_utils.cpp:412
        private float _statTechnicalVolley = 0.6f;    // humanoid_utils.cpp:437
        private float _statTechnicalShot = 0.6f;      // humanoid_utils.cpp:493
        private float _statTechnicalShortPass = 0.6f; // humanoid.cpp:2446
        private float _statTechnicalHighPass = 0.6f;  // humanoid.cpp:2447
        private float _statPhysicalVelocity = 0.6f;   // playerbase.cpp:138

        public void SetTeamSide(int side) => _teamSide = side;
        public void SetAllowDeflectRetain(bool allow) => _labAllowDeflectRetain = allow;

        // ШОВ GetLastTouchBias команды соперника / её lastTouchPlayer (humanoid.cpp:345, :605-611;
        // humanoid_utils.cpp:182-195): соперников в лабе нет — биас 0 при любом окне. Матч-слой
        // (задача 9+) заменит на реальную команду.
        private float OppLastTouchBias(int decayMs)
        {
            _ = decayMs;
            return 0.0f;
        }

        // ШОВ player->GetController()->GetFloatVelocity() (humanoid_utils.cpp:235): контроллера
        // в лабе нет — желаемая скорость команды, породившей текущий клип (решение брифа).
        private float ControllerFloatVelocity() => _current.OriginatingCommand.DesiredVelocityFloat;

        // player->GetMaxVelocity() (playerbase.cpp:131-139) поверх шва-стата.
        private float MaxVelocity() => PhysicsVector.GetMaxVelocity(_statPhysicalVelocity);

        // Порт player-части Team::SetLastTouchPlayer (team.cpp:241-248): SetLastTouchTime_ms
        // (:245) + SetLastTouchType (:246). Командная и матчевая части (lastTouchPlayers,
        // SetLastTouchTeamID) — матч-слой (задача 9+).
        private void RegisterTouch(int touchType)
        {
            _lastTouchTimeMs = _actualTimeMs; // team.cpp:245
            _lastTouchType = touchType;       // team.cpp:246
        }

        // FootballAnimationExtension::GetTouchPos(frame) (footballanimationextension.cpp:178-186):
        // точный поиск позиции касания по кадру. Не найдено → Vector3.Zero (в C++ выходной
        // параметр остался бы неинициализированным; touchFrame всегда берётся из списка касаний
        // клипа, так что ветка мертва).
        private static Vector3 GetAnimTouchPosAtFrame(Animation anim, int frame)
        {
            int n = anim.GetTouchCount();
            for (int i = 0; i < n; i++)
                if (anim.GetTouchFrame(i) == frame) return anim.GetTouchPosition(i);
            return Vector3.Zero;
        }

        // ШОВ CastPlayer()->GetTimeNeededToGetToBall_ms() (:2340): считает AI (AIfunctions);
        // в лабе — сеттер, дефолт 0 («уже у мяча»).
        private int _timeNeededToGetToBallMs = 0;
        // ШОВ CastPlayer()->GetDesiredTimeToBall_ms() (:2341): задаёт тактика команды; дефолт 0.
        private int _desiredTimeToBallMs = 0;

        // Оба designated-предиката разом: до задачи 6 они были одним полем, внешний API это
        // сохраняет (лаб-вызовы «этот игрок назначен/не назначен на мяч»).
        public void SetDesignatedPossession(bool designated)
        {
            _designatedPossession = designated;
            _teamDesignatedPossession = designated;
        }
        public void SetTeamId(int teamId) => _teamId = teamId;
        public void SetTimeNeededToGetToBall(int ms) => _timeNeededToGetToBallMs = ms;
        public void SetDesiredTimeToBall(int ms) => _desiredTimeToBallMs = ms;

        // TouchPending (humanoid.hpp:29) — ДОСЛОВНО: `frameNum < touchFrame`. Для клипа без
        // касания (touchFrame == -1) всегда false, т.к. frameNum >= 0. Потребитель — гейт
        // «правильный ли клип для реквея» (:194-195).
        internal bool TouchPending() => _current.FrameNum < _current.TouchFrame;

        // TouchAnim (humanoid.hpp:30) — держим рядом с TouchPending, потребители придут задачей 7.
        internal bool TouchAnim() => _current.TouchFrame != -1;

        // ШОВ :1194: позиция designated possession player; в лабе это сам игрок.
        private Vector3 DesignatedPossessionPlayerPosition() =>
            _designatedPossessionPlayerPos ?? _spatial.Position;

        // ШОВ CastPlayer()->HasPossession() (:2358): настоящий предикат живёт в
        // Match::CalculatePossession (придёт с матчем, задача 9+). Лаб-суррогат: мяч ближе
        // 1.6 м по земле и ниже 1 м — «мяч у ног».
        private bool HasPossession()
        {
            Vector3 ballNow = _ball.Predict(0);
            return (BluntMath.Get2D(ballNow) - _spatial.Position).Length() < 1.6f
                && ballNow.Z < 1.0f;
        }

        public void SetBall(Ball ball) => _ball = ball;
        public void SetRng(GpfRng rng) => _rng = rng;

        // Лаб-суррогат match->GetBallRetainer(): в фазе 4 ретейнер — либо «этот игрок», либо
        // никто; состояние «чужой ретейнер» придёт с матчем (задача 9+). Пишет тот же флаг,
        // что и SetMatchContext (то же сравнение GetBallRetainer() == player).
        public void SetBallRetainerSelf(bool retains) => _isBallRetainer = retains;

        public void SetLabContext(float closestOpponentDistance, float playerHeight)
        {
            _closestOpponentDistance = closestOpponentDistance;
            _playerHeight = playerHeight;
        }

        // Состояние матча для сорт-цепочки (:1564-1566) — мостом наружу, дефолты как выше.
        public void SetMatchContext(bool isInPlay, bool isInSetPiece, bool isBallRetainer,
                                    bool allowLastDitch)
        {
            _isInPlay = isInPlay;
            _isInSetPiece = isInSetPiece;
            _isBallRetainer = isBallRetainer;
            _allowLastDitch = allowLastDitch;
        }

        // player.cpp:141-144. Аргумент includingPossessionAmount оригинала влияет только на
        // team-ветку (:142), которой у нас нет → обе формы дают один и тот же шов.
        private bool AllowLastDitch(bool includingPossessionAmount = true) => _allowLastDitch;

        // ---- GetHasteFactor (:1143-1157) ----
        // ШОВ MentalImage: currentMentalImage->GetBallPrediction(t) — «мяч, каким его помнит
        // игрок» (задержка восприятия). MentalImage не портирован → берём объективный
        // _ball.Predict(t); расхождение с оригиналом — только в задержке восприятия.
        internal float GetHasteFactor(bool considerOpponentProximity)
        {
            float haste = 0.0f;                                                    // :1144

            float playerMovementInfluence = 0.5f;                                  // :1146
            float playerBallDistanceNow = (BluntMath.Get2D(_ball.Predict(50))
                - (_spatial.Position + _spatial.Movement * 0.05f * playerMovementInfluence)).Length(); // :1147
            float playerBallDistanceFuture = (BluntMath.Get2D(_ball.Predict(500))
                - (_spatial.Position + _spatial.Movement * 0.5f * playerMovementInfluence)).Length();  // :1148

            haste = BluntMath.NormalizedClamp(playerBallDistanceFuture - playerBallDistanceNow,
                0.0f, 1.0f);                                                       // :1150

            if (haste <= 1.0f && considerOpponentProximity)                        // :1152
            {
                // :1153-1155 — ВЕТКА-ЗАГЛУШКА: GetTeamPossessionAmount команды не портирован
                // (задача 9+). Все вызовы фазы 4 идут с considerOpponentProximity=false, т.е.
                // ветка мертва; формула перенесена дословно поверх шва _teamPossessionAmountStub.
                if (_teamPossessionAmountStub < 2.0f) haste += 1.0f - _teamPossessionAmountStub * 0.5f;
            }

            return Mathf.Clamp(haste, 0.0f, 1.0f);                                 // :1156
        }

        // ---- _HighOrBouncyBall (humanoidbase.cpp:1089-1100) ----
        private bool HighOrBouncyBall()
        {
            const int defaultTouchOffsetMs = 80;                                   // gamedefines.hpp:64
            float ballHeight1 = _ball.Predict(10).Z;                               // :1090
            float ballHeight2 = _ball.Predict(defaultTouchOffsetMs).Z;             // :1091
            float ballBounce = Mathf.Abs(_ball.GetMovement().Z);                   // :1092
            bool highBall = false;                                                 // :1093
            if (ballHeight1 > 0.3f || ballHeight2 > 0.3f) highBall = true;         // :1094-1095
            // низкий, но сильно скачущий мяч тоже считается «высоким» (:1096-1097)
            else if (ballBounce > 1.0f) highBall = true;
            return highBall;                                                       // :1099
        }

        // ---- Голова Humanoid::SelectAnim: сборка запроса и грубый отбор (:1244-1365) ----
        // Возвращает пустой список там, где оригинал делает `return false` (:1364).
        internal List<int> BuildCrudeDataSet(PlayerCommand command)
        {
            var query = new CrudeSelectionQuery();                                 // :1244

            query.ByFunctionType = true;                                           // :1246
            query.FunctionTypeId = command.DesiredFunctionType;                    // :1247

            query.ByFoot = false;                                                  // :1249
            query.FootId = _spatial.Foot == Animation.FootLeft
                ? Animation.FootRight : Animation.FootLeft;                        // :1250

            // hax: длинный пас использует клипы короткого (:1255-1256)
            if (query.FunctionTypeId == AnimCollection.FnLongPass)
                query.FunctionTypeId = AnimCollection.FnShortPass;

            if (command.TouchInfo.DesiredPower != 0.0f)                            // :1258
            {
                query.ByOutgoingBallDirection = true;                              // :1259
                query.OutgoingBallDirection = BluntMath.GetRotated2D(
                    command.TouchInfo.DesiredDirection, -_spatial.Angle);          // :1260
            }

            query.ByIncomingVelocity = true;                                       // :1263
            query.IncomingVelocityId = _spatial.EnumVelocity;                      // :1264

            if (query.FunctionTypeId != AnimCollection.FnMovement &&
                query.IncomingVelocityId == Velo.IdVelDribble)
                query.IncomingVelocityId = Velo.IdVelWalk;                         // :1266

            query.IncomingVelocityStrict = false;                                  // :1268
            if (query.FunctionTypeId != AnimCollection.FnMovement &&
                query.FunctionTypeId != AnimCollection.FnBallControl)              // :1269
            {
                query.IncomingVelocityForceLinearity = false;                      // :1270
                if (query.FunctionTypeId != AnimCollection.FnDeflect)              // :1271
                {
                    query.IncomingVelocityNoDribbleToSprint = true;                // :1272
                    // :1273 — пасы/удар живут по своим правилам
                    if (query.FunctionTypeId != AnimCollection.FnShortPass &&
                        query.FunctionTypeId != AnimCollection.FnLongPass &&
                        query.FunctionTypeId != AnimCollection.FnHighPass &&
                        query.FunctionTypeId != AnimCollection.FnShot)
                    {
                        query.IncomingVelocityForceLinearity = true;               // :1274
                        query.IncomingVelocityNoDribbleToIdle = true;              // :1275
                    }
                    else                                                           // :1276-1278 passes and such
                    {
                        query.IncomingVelocityForceLinearity = false;
                        query.IncomingVelocityNoDribbleToIdle = false;
                    }
                }
                else                                                               // :1280-1282 deflect
                {
                    query.IncomingVelocityNoDribbleToSprint = false;
                    query.IncomingVelocityNoDribbleToIdle = false;
                }
            }
            else                                                                   // :1284-1286
            {
                query.IncomingVelocityStrict = true;
            }

            query.ByIncomingBodyDirection = true;                                  // :1288
            query.IncomingBodyDirection = _spatial.RelBodyDirectionVec;            // :1290
            if (query.FunctionTypeId != AnimCollection.FnMovement)                 // :1291
            {
                query.IncomingBodyDirectionStrict = false;                         // :1292
                if (query.FunctionTypeId != AnimCollection.FnDeflect)              // :1293
                {
                    // :1294-1298 — ballcontrol намеренно нелинейный: так его клипы чаще годятся
                    // как trap и не дают мячу прокатиться мимо
                    query.IncomingBodyDirectionForceLinearity =
                        query.FunctionTypeId != AnimCollection.FnBallControl;
                }
                else                                                               // :1299-1301 deflect
                {
                    query.IncomingBodyDirectionForceLinearity = false;
                }
            }
            else                                                                   // :1302-1304
            {
                query.IncomingBodyDirectionStrict = true;
            }

            query.BySide = false;                                                  // :1306
            if (command.UseDesiredLookAt
                && _current.Anim.GetVariable("outgoing_special_state") == ""
                && !_isBallRetainer)                                               // :1307
            {
                Vector3 playerLookAtVec = BluntMath.GetNormalized(
                    command.DesiredLookAt - _spatial.Position, _spatial.DirectionVec); // :1308
                query.LookAtVecRel = BluntMath.GetRotated2D(playerLookAtVec, -_spatial.Angle); // :1309
                query.BySide = true;                                               // :1310
            }

            if (command.OnlyDeflectAnimsThatPickupBall)                            // :1313
            {
                query.ByPickupBall = true;                                         // :1314
                query.PickupBall = true;                                           // :1315
            }

            if (command.DesiredFunctionType == AnimCollection.FnTrap ||
                command.DesiredFunctionType == AnimCollection.FnInterfere ||
                command.DesiredFunctionType == AnimCollection.FnDeflect)           // :1318-1320
            {
                query.ByIncomingBallDirection = true;                              // :1321
                // :1322 — ШОВ MentalImage (см. GetHasteFactor): GetBallPrediction → _ball.Predict.
                // todo оригинала «proper prediction time» переносим как есть.
                query.IncomingBallDirection = BluntMath.GetNormalized(
                    BluntMath.GetRotated2D(_ball.Predict(180) - _ball.Predict(120), -_spatial.Angle),
                    Vector3.Zero);
            }

            query.AllowLastDitchAnims = AllowLastDitch();                          // :1338-1342

            if (command.DesiredFunctionType == AnimCollection.FnTrip)              // :1344
            {
                query.ByTripType = true;                                           // :1345
                query.TripType = command.TripType;                                 // :1346
            }

            query.SetProperty("incoming_special_state",
                _current.Anim.GetVariable("outgoing_special_state"));              // :1349
            if (_isBallRetainer)
                query.SetProperty("incoming_retain_state",
                    _current.Anim.GetVariable("outgoing_retain_state"));           // :1350
            // :1351-1352 — int уходит в перегрузку Properties::Set(name, real) → real_to_str
            // (properties.cpp:57-60); формат неважен: фильтр сравнивает обе стороны через AtoF
            // (animcollection.cpp:817-818). InvariantCulture — требование global-constraints.
            if (command.UseSpecialVar1)
                query.SetProperty("specialvar1", command.SpecialVar1.ToString(
                    System.Globalization.CultureInfo.InvariantCulture));           // :1351
            if (command.UseSpecialVar2)
                query.SetProperty("specialvar2", command.SpecialVar2.ToString(
                    System.Globalization.CultureInfo.InvariantCulture));           // :1352

            // клипы вставания всегда стартуют из idle (:1354)
            if (_current.Anim.GetVariable("outgoing_special_state") != "")
                query.IncomingVelocityId = Velo.IdVelIdle;

            var dataSet = new List<int>();                                         // :1356
            _anims.CrudeSelectionInternal(dataSet, query);                         // :1357
            if (dataSet.Count == 0)                                                // :1359
            {
                // :1363 — движение доигрывается idle-клипом. Страховка порта (как в фазе 3):
                // на пустой коллекции GetIdleMovementAnimID() == -1, и класть -1 в отбор нельзя;
                // в оригинале такого состояния не бывает (клипы всегда загружены).
                if (command.DesiredFunctionType == AnimCollection.FnMovement       // :1360
                    && _anims.GetIdleMovementAnimID() >= 0)
                    dataSet.Add(_anims.GetIdleMovementAnimID());
                // :1364 — иначе SelectAnim возвращает false; у нас это пустой список
            }
            return dataSet;
        }

        // ---- Хвост Humanoid::SelectAnim: KeepBest*-ветки и сорт-цепочка (:1369-1637) ----
        // Возвращает false там, где оригинал делает `return false` (:1535 — «nope, too wrong!»).
        // ВНИМАНИЕ: query.allowLastDitchAnims из головы нужен trap-ветке (:1511) — берём то же
        // AllowLastDitch(), что и BuildCrudeDataSet (:1338).
        internal bool SortDataSet(List<int> dataSet, PlayerCommand command)
        {
            _selector.SetSpatialForPredicates(_spatial.Position, _spatial.Angle);

            if (command.UseDesiredMovement)                                        // :1369
            {
                Vector3 relDesiredDirection = BluntMath.GetRotated2D(
                    command.DesiredDirection, -_spatial.Angle);                    // :1371
                float desiredAnimationVelocityFloat = command.DesiredVelocityFloat; // :1372

                _selector.SetMovementSimilarityPredicate(relDesiredDirection,
                    Velo.FloatToEnumVelocity(desiredAnimationVelocityFloat),
                    _spatial.FloatVelocity);                                       // :1379
                _selector.SetBodyDirectionSimilarityPredicate(command.DesiredLookAt); // :1380

                if (command.DesiredFunctionType == AnimCollection.FnMovement)      // :1441
                {
                    // строгий отбор из остатка (:1445-1447)
                    _selector.KeepBestDirectionAnims(dataSet, command, true);      // :1446
                    if (command.UseDesiredLookAt)
                        _selector.KeepBestBodyDirectionAnims(dataSet, command, true); // :1447
                }
                else if (command.DesiredFunctionType == AnimCollection.FnBallControl) // :1457
                {
                    bool strict = true;                                            // :1458
                    if (AllowLastDitch()) strict = false;                          // :1459-1461
                    float allowedBaseAngle = 0.0f * Mathf.Pi;                      // :1462
                    // :1463 — last-ditch клипам смена скорости разрешена всегда, пока strict=false
                    int allowedVelocitySteps = 0;
                    if (command.UseDesiredLookAt)
                        _selector.KeepBestBodyDirectionAnims(dataSet, command, strict, allowedBaseAngle); // :1464
                    _selector.KeepBestDirectionAnims(dataSet, command, strict, allowedBaseAngle,
                        allowedVelocitySteps);                                     // :1465
                }
                else if (command.DesiredFunctionType == AnimCollection.FnTrap)     // :1475
                {
                    bool strict = true;                                            // :1489
                    if (AllowLastDitch(false) || HighOrBouncyBall()) strict = false; // :1490
                    float allowedBaseAngle = 0.3f * Mathf.Pi;                      // :1491
                    int allowedVelocitySteps = 2;                                  // :1492
                    int bestBallControlQuadrantId = -1;                            // :1493
                    _selector.KeepBestDirectionAnims(dataSet, command, strict, allowedBaseAngle,
                        allowedVelocitySteps, bestBallControlQuadrantId);          // :1494
                    if (command.UseDesiredLookAt)
                        _selector.KeepBestBodyDirectionAnims(dataSet, command, strict, allowedBaseAngle); // :1495

                    // слишком непохоже на желаемое движение — не лезем вовсе, ждём следующего
                    // ballcontrol/trap-клипа (:1510-1511)
                    if (!HighOrBouncyBall() && !AllowLastDitch())
                    {
                        if (dataSet.Count == 0) return false;                      // :1512 assert
                        Vector3 desiredMovement = command.DesiredDirection
                            * command.DesiredVelocityFloat;                        // :1513
                        Animation bestWeGot = _anims.GetAnim(dataSet[0]);          // :1514
                        Vector3 bestWeGotMovement = BluntMath.GetRotated2D(
                            bestWeGot.GetOutgoingMovement(), _spatial.Angle);      // :1515
                        float currentDesiredDot = command.DesiredDirection.Dot(_spatial.DirectionVec); // :1516

                        bool allowAnim = true;                                     // :1518

                        float angleDiff = Mathf.Abs(BluntMath.GetAngle2D(
                            BluntMath.GetRotated2D(bestWeGot.GetOutgoingDirection(), _spatial.Angle),
                            command.DesiredDirection));                            // :1520
                        // :1521 — 0.375π: принимаем хотя бы 000- или 135-градусные клипы
                        if (angleDiff > 0.375f * Mathf.Pi) allowAnim = false;      // :1521-1522

                        Vector3 desiredBestDiff = bestWeGotMovement - desiredMovement; // :1526
                        if ((desiredBestDiff.Length() > Velo.Walk + 0.5f && currentDesiredDot > 0.0f) ||
                            (desiredBestDiff.Length() > Velo.Sprint + 0.5f && currentDesiredDot <= 0.0f))
                            allowAnim = false;                                     // :1527-1529 (+ запас)

                        if (!allowAnim) return false;                              // :1533-1536
                    }
                }
                else if (command.DesiredFunctionType == AnimCollection.FnInterfere) // :1542
                {
                    bool strict = false;                                           // :1544
                    float allowedAngle = 0.3f * Mathf.Pi;                          // :1545
                    int allowedVelocitySteps = 1;                                  // :1546
                    if (command.StrictMovement == PlayerCommand.StrictTrue) strict = true; // :1547

                    _selector.KeepBestDirectionAnims(dataSet, command, strict, allowedAngle,
                        allowedVelocitySteps);                                     // :1549
                    if (command.UseDesiredLookAt)
                        _selector.KeepBestBodyDirectionAnims(dataSet, command, strict, allowedAngle); // :1550
                }
            }

            // ---- общая сорт-цепочка (:1556-1637); все сорты — StableSort ----

            _selector.SetNumericVariableSimilarityPredicate("priority", 0);        // :1556
            _selector.SortByNumericVariable(dataSet);                              // :1560

            int desiredIdleLevel = 0;                                              // :1563
            if (!_isInPlay) desiredIdleLevel = 2;                                  // :1564
            // :1565-1566 — цепочка оригинала именно такая: `if (setpiece) 1; else if (далеко) 1;`,
            // из-за чего «мяч далеко» ПЕРЕЗАПИСЫВАЕТ уровень 2 из :1564. Переносим как есть.
            if (_isInSetPiece) desiredIdleLevel = 1;
            else if ((_ball.Predict(200) - _spatial.Position).Length() > 16.0f) desiredIdleLevel = 1;
            _selector.SetNumericVariableSimilarityPredicate("idlelevel", desiredIdleLevel); // :1567
            _selector.SortByNumericVariable(dataSet);                              // :1571

            _selector.SetFootSimilarityPredicate(_spatial.Foot);                   // :1574
            _selector.SortByFootSimilarity(dataSet);                               // :1578

            if (command.DesiredFunctionType != AnimCollection.FnBallControl)       // :1581
            {
                _selector.SetIncomingBodyDirectionSimilarityPredicate(_spatial.RelBodyDirectionVec); // :1582
                _selector.SortByIncomingBodyDirectionSimilarity(dataSet);          // :1586
            }

            // moved down (:1590)
            _selector.SetIncomingVelocitySimilarityPredicate(_spatial.EnumVelocity); // :1591
            _selector.SortByIncomingVelocitySimilarity(dataSet);                   // :1595

            // :1598-1608 — сорт по BodyDirectionSimilarity закомментирован в оригинале
            // («are deleted earlier on anyways»); не переносим.

            if (command.UseDesiredTripDirection)                                   // :1611 OLD METHOD
            {
                Vector3 relDesiredTripDirection = BluntMath.GetRotated2D(
                    command.DesiredTripDirection, -_spatial.Angle);                // :1612
                _selector.SetTripDirectionSimilarityPredicate(relDesiredTripDirection); // :1613
                _selector.SortByTripDirectionSimilarity(dataSet);                  // :1617
            }

            if (command.DesiredFunctionType != AnimCollection.FnMovement)          // :1623 OLD METHOD
                _selector.SortByBaseanimSimilarity(dataSet);                       // :1627

            if (command.DesiredFunctionType == AnimCollection.FnDeflect)           // :1631
                _selector.SortByCatchOrDeflect(dataSet);                           // :1635

            return true;
        }

        // ---- Humanoid::SelectAnim (:1159-1820) — единый выбор клипа наследника ----
        // Голова (crude query) — BuildCrudeDataSet, сорт-цепочка — SortDataSet; здесь — каркас,
        // ветки по типам команд и заполнение Anim («make it so», :1747-1786).
        // С задачи 7 портировано всё: оптимизации-ранние-выходы (:1163-1189), ветки
        // Trap/Interfere/Deflect (:1687-1692), пасов/удара (:1693-1709) и Sliding (:1710-1722).
        // Не портированы только FnHeader и FnCatch — придут с вратарским контуром.
        internal bool SelectAnim(PlayerCommand command, int localInterruptAnim, bool preferPassAndShot)
        {
            // :1160 assert(desiredDirection.z == 0) — не переносим

            // ---- оптимизации-ранние-выходы (:1163-1189) ----
            if (command.DesiredFunctionType != AnimCollection.FnMovement &&
                command.DesiredFunctionType != AnimCollection.FnTrip &&
                command.DesiredFunctionType != AnimCollection.FnSpecial &&
                command.DesiredFunctionType != AnimCollection.FnSliding)       // :1165-1168
            {
                // :1169 ШОВ MentalImage (см. GetHasteFactor): GetBallPrediction → _ball.Predict
                if ((BluntMath.Get2D(_ball.Predict(200)) - _spatial.Position).Length()
                    > GpfPitch.BallDistanceOptimizeThreshold)
                    return false;                                              // :1170
                // мяч дальше 2 м и удаляется от игрока (:1172-1177)
                if ((BluntMath.Get2D(_ball.Predict(GpfPitch.DefaultTouchOffsetMs))
                     - _spatial.Position).Length() > 2.0f &&                   // :1172
                    (BluntMath.Get2D(_ball.Predict(GpfPitch.DefaultTouchOffsetMs))
                     - (_spatial.Position
                        + _spatial.Movement * GpfPitch.DefaultTouchOffsetMs * 0.001f)).Length() >
                    (BluntMath.Get2D(_ball.Predict(0)) - _spatial.Position).Length()) // :1174-1175
                {
                    return false;                                              // :1176
                }
            }

            // :1180-1187 — гейт «в памяти игрока мяч не там, где он есть» (после чужого касания
            // клипы не должны стартовать по устаревшей картинке). ШОВ MentalImage: задержка
            // восприятия в лабе нулевая → mental-предсказание == реальному, разность 0 <= 2 м —
            // ветка НИКОГДА не срабатывает. Портируем дословно поверх шва: обе стороны сравнения —
            // один и тот же _ball.Predict(1000).
            if (command.DesiredFunctionType != AnimCollection.FnMovement &&
                command.DesiredFunctionType != AnimCollection.FnTrip &&
                command.DesiredFunctionType != AnimCollection.FnSpecial &&
                command.DesiredFunctionType != AnimCollection.FnSliding &&
                command.DesiredFunctionType != AnimCollection.FnDeflect &&
                !_isBallRetainer)                                              // :1181-1185
            {
                if ((_ball.Predict(1000) - _ball.Predict(1000)).Length() > 2.0f)
                    return false;                                              // :1186
            }

            // /optimizations (:1189)

            // ---- отказные фильтры ReQueue (:1192-1234) ----
            // Работают ТОЛЬКО когда прерывание пришло по ReQueue: Switch (граница клипа) обязан
            // выбрать хоть что-то, реквей — лишь «улучшение» и вправе отказаться.
            if (localInterruptAnim == HumanoidBase.InterruptReQueue)            // :1192
            {
                // :1194 ШОВ — расстояние до игрока, назначенного на мяч (в лабе это мы сами → 0)
                float focusDistance =
                    (DesignatedPossessionPlayerPosition() - _spatial.Position).Length();

                // из НЕ-движения в движение реквея не бывает (:1196)
                if (_current.FunctionType != AnimCollection.FnMovement
                    && command.DesiredFunctionType == AnimCollection.FnMovement) return false;
                // движение→движение: с мячом у ног или вдали от очага борьбы клип доигрывается
                // (:1197; закомментированный в оригинале GetTeamPossessionAmount не переносим)
                if (_current.FunctionType == AnimCollection.FnMovement
                    && command.DesiredFunctionType == AnimCollection.FnMovement
                    && (HasPossession() || focusDistance > 12.0f)) return false;
                // осталось меньше 6 кадров — доигрываем (:1198)
                if (_current.FunctionType == AnimCollection.FnMovement
                    && command.DesiredFunctionType == AnimCollection.FnMovement
                    && _current.FrameNum + MinRemainingMovementReQueueFrames
                       > _current.Anim.GetEffectiveFrameCount()) return false;
                // флаг выключен или не истёк делэй после прошлого реквея того же типа (:1199)
                if (_current.FunctionType == AnimCollection.FnMovement
                    && command.DesiredFunctionType == AnimCollection.FnMovement
                    && (!AllowMovementReQueue || _reQueueDelayFrames > 0)) return false;
                // ballcontrol→ballcontrol: только в первые 8 кадров (:1200)
                if (_current.FunctionType == AnimCollection.FnBallControl
                    && command.DesiredFunctionType == AnimCollection.FnBallControl
                    && (!AllowBallControlReQueue || _current.FrameNum > MaxBallControlReQueueFrame
                        || _reQueueDelayFrames > 0)) return false;
                // ballcontrol→trap не реквеится вовсе (:1201)
                if (_current.FunctionType == AnimCollection.FnBallControl
                    && command.DesiredFunctionType == AnimCollection.FnTrap) return false;
                // trap→trap: пока до касания больше 6 кадров (:1202)
                if (_current.FunctionType == AnimCollection.FnTrap
                    && command.DesiredFunctionType == AnimCollection.FnTrap
                    && (!AllowTrapReQueue
                        || _current.FrameNum + MinRemainingTrapReQueueFrames > _current.TouchFrame
                        || _reQueueDelayFrames > 0)) return false;
                // trap→ballcontrol: то же условие, что и trap→trap (:1203)
                if (_current.FunctionType == AnimCollection.FnTrap
                    && command.DesiredFunctionType == AnimCollection.FnBallControl
                    && (!AllowTrapReQueue
                        || _current.FrameNum + MinRemainingTrapReQueueFrames > _current.TouchFrame
                        || _reQueueDelayFrames > 0)) return false;

                // слишком похоже на то, что уже пытаемся сделать (:1205-1209). Сравнение идёт со
                // СНИМКОМ команды, породившей текущий клип (:1784 копирует по значению — см.
                // PlayerCommand.Clone).
                if (_current.OriginatingCommand.DesiredFunctionType == command.DesiredFunctionType
                    && ((_current.OriginatingCommand.DesiredDirection
                         * _current.OriginatingCommand.DesiredVelocityFloat)
                        - (command.DesiredDirection * command.DesiredVelocityFloat)).Length() < 1.5f)
                {
                    return false;                                              // :1208
                }

                // реквей не нужен? (:1211-1226)
                if ((_current.FunctionType == AnimCollection.FnMovement
                     && command.DesiredFunctionType == AnimCollection.FnMovement) ||    // :1212
                    (_current.FunctionType == AnimCollection.FnBallControl
                     && command.DesiredFunctionType == AnimCollection.FnBallControl) || // :1213
                    (_current.FunctionType == AnimCollection.FnTrap
                     && command.DesiredFunctionType == AnimCollection.FnBallControl) || // :1214
                    (_current.FunctionType == AnimCollection.FnTrap
                     && command.DesiredFunctionType == AnimCollection.FnTrap))          // :1215
                {
                    // запланированная смена импульса против желаемой (:1217-1219)
                    Vector3 plannedMomentumChange =
                        _current.OutgoingMovement - _current.IncomingMovement;          // :1218
                    Vector3 desiredMomentumChange =
                        (command.DesiredDirection * command.DesiredVelocityFloat)
                        - _spatial.Movement;                                            // :1219

                    // GetDistance(a, b) оригинала == длина разности (:1221-1222)
                    if ((desiredMomentumChange.Dot(plannedMomentumChange) > 0.0f
                         && (desiredMomentumChange - plannedMomentumChange).Length() < 4.0f) ||
                        desiredMomentumChange.Dot(plannedMomentumChange) > 0.8f ||
                        (desiredMomentumChange - plannedMomentumChange).Length() < 2.0f)
                    {
                        return false;                                          // :1223
                    }
                }

                // не реквеим движение в ballcontrol на полпути движ-клипа, если только не
                // запрошена серьёзная смена движения (:1228-1232)
                if (_current.FunctionType == AnimCollection.FnMovement
                    && command.DesiredFunctionType == AnimCollection.FnBallControl
                    && (_actualTimeMs - _lastTouchTimeMs < 600
                        && _lastTouchType == TouchTypeIntentionalKicked)
                    && HasPossession())
                {
                    float desiredMovementChange = (_spatial.Movement
                        - (command.DesiredDirection * command.DesiredVelocityFloat)).Length(); // :1230
                    if (desiredMovementChange < 1.0f) return false;            // :1231
                }
            }

            if (localInterruptAnim != HumanoidBase.InterruptReQueue || _current.FrameNum > 12)
                CalculateFactualSpatialState();                                // :1236

            // :1239 assert(desiredLookAt.z == 0) — не переносим

            var dataSet = BuildCrudeDataSet(command);                          // :1244-1357
            if (dataSet.Count == 0) return false;                              // :1364
            if (!SortDataSet(dataSet, command)) return false;                  // :1369-1637, false == :1535

            int selectedAnimID = -1;                                           // :1648
            var positionsTmp = new List<Vector3>();                            // :1649
            int touchFrameTmp = -1;                                            // :1650
            float radiusOffsetTmp = 0.0f;                                      // :1651
            Vector3 touchPosTmp = Vector3.Zero;                                // :1652
            Vector3 fullActionSmuggleTmp = Vector3.Zero;                       // :1653
            Vector3 actionSmuggleTmp = Vector3.Zero;                           // :1654
            float rotationSmuggleTmp = 0f;                                     // :1655

            if (dataSet.Count == 0 && command.DesiredFunctionType == AnimCollection.FnMovement)
            {
                // :1657-1660 — движение доигрывается idle-клипом; >= 0 — страховка порта на
                // пустой коллекции (как в BuildCrudeDataSet)
                if (_anims.GetIdleMovementAnimID() >= 0)
                    dataSet.Add(_anims.GetIdleMovementAnimID());               // :1659
            }
            // страховка порта: KeepBest*-фильтры могли опустошить action-отбор; в C++ дальше
            // NeedTouch(*dataSet.begin()) / dataSet[0] в GetBestCheatableAnimID — UB на пустом
            if (dataSet.Count == 0) return false;

            // desiredBodyDirectionRel — todo-«hax» оригинала (:1664-1665), bug-for-bug:
            // упреждение движения на 0.1 с, нормализация ДО GetRotated2D
            Vector3 desiredBodyDirectionRel = new Vector3(0, -1, 0);           // :1664
            if (command.UseDesiredLookAt)
                desiredBodyDirectionRel = BluntMath.GetRotated2D(
                    BluntMath.GetNormalized(
                        command.DesiredLookAt - (_spatial.Position + _spatial.Movement * 0.1f),
                        new Vector3(0, -1, 0)),
                    -_spatial.Angle);                                          // :1665

            if (command.DesiredFunctionType == AnimCollection.FnMovement ||
                command.DesiredFunctionType == AnimCollection.FnTrip ||
                command.DesiredFunctionType == AnimCollection.FnSpecial)       // :1667-1669
            {
                selectedAnimID = dataSet[0];                                   // :1671
                Animation nextAnim = _anims.GetAnim(selectedAnimID);           // :1672
                Vector3 desiredMovement = command.DesiredDirection * command.DesiredVelocityFloat; // :1673
                // :1674-1678 debug print + assert(desiredMovement.z == 0) — не переносим
                // ШОВ: CalculatePhysicsVector — член humanoid'а в C++; наш PhysicsVector —
                // отдельный объект, передаём то же состояние
                _physics.SetSpatialState(_spatial.Position, _spatial.Angle, _spatial.DirectionVec,
                    _spatial.FloatVelocity, _spatial.Movement);
                // player->GetLastTouchBias(1000) + decayingPositionOffset — контекст
                // CalculatePhysicsVector (humanoidbase.cpp:2082-2084), читается на месте вызова
                _physics.SetTouchContext(GetLastTouchBias(1000), _decayingPositionOffset.Length());
                _physics.Calculate(nextAnim, _anims.GetPositionCacheInternal(selectedAnimID),
                    command.UseDesiredMovement, desiredMovement, command.UseDesiredLookAt,
                    desiredBodyDirectionRel, positionsTmp, out rotationSmuggleTmp); // :1679
            }
            else if (command.DesiredFunctionType == AnimCollection.FnBallControl) // :1681
            {
                if (NeedTouch(dataSet[0], command))                            // :1682 — гейт тач-попытки
                {
                    float hasteFactor = GetHasteFactor(false);                 // :1683
                    selectedAnimID = GetBestCheatableAnimID(dataSet, command.UseDesiredMovement,
                        command.DesiredDirection, command.DesiredVelocityFloat,
                        command.UseDesiredLookAt, desiredBodyDirectionRel, positionsTmp,
                        ref touchFrameTmp, ref radiusOffsetTmp, ref touchPosTmp,
                        ref fullActionSmuggleTmp, ref actionSmuggleTmp, ref rotationSmuggleTmp,
                        hasteFactor, localInterruptAnim, preferPassAndShot);   // :1684
                }
            }
            else if (command.DesiredFunctionType == AnimCollection.FnTrap ||
                     command.DesiredFunctionType == AnimCollection.FnInterfere ||
                     command.DesiredFunctionType == AnimCollection.FnDeflect)  // :1687-1689
            {
                float hasteFactor = GetHasteFactor(false);                     // :1690
                selectedAnimID = GetBestCheatableAnimID(dataSet, command.UseDesiredMovement,
                    command.DesiredDirection, command.DesiredVelocityFloat,
                    command.UseDesiredLookAt, desiredBodyDirectionRel, positionsTmp,
                    ref touchFrameTmp, ref radiusOffsetTmp, ref touchPosTmp,
                    ref fullActionSmuggleTmp, ref actionSmuggleTmp, ref rotationSmuggleTmp,
                    hasteFactor, localInterruptAnim, preferPassAndShot);       // :1691
            }
            else if (command.DesiredFunctionType == AnimCollection.FnShortPass ||
                     command.DesiredFunctionType == AnimCollection.FnLongPass ||
                     command.DesiredFunctionType == AnimCollection.FnHighPass ||
                     command.DesiredFunctionType == AnimCollection.FnShot)     // :1693-1696
            {
                float hasteFactor = GetHasteFactor(false);                     // :1697
                // :1698 — preferPassAndShot в этом вызове НЕ передаётся (дефолт false C++)
                selectedAnimID = GetBestCheatableAnimID(dataSet, command.UseDesiredMovement,
                    command.DesiredDirection, command.DesiredVelocityFloat,
                    command.UseDesiredLookAt, desiredBodyDirectionRel, positionsTmp,
                    ref touchFrameTmp, ref radiusOffsetTmp, ref touchPosTmp,
                    ref fullActionSmuggleTmp, ref actionSmuggleTmp, ref rotationSmuggleTmp,
                    hasteFactor, localInterruptAnim, false);
                // :1699-1708 debug-блок закомментирован в оригинале — не переносим
            }
            else if (command.DesiredFunctionType == AnimCollection.FnSliding)  // :1710
            {
                float hasteFactor = GetHasteFactor(false);                     // :1711
                // :1712 — preferPassAndShot не передаётся (дефолт false C++)
                selectedAnimID = GetBestCheatableAnimID(dataSet, command.UseDesiredMovement,
                    command.DesiredDirection, command.DesiredVelocityFloat,
                    command.UseDesiredLookAt, desiredBodyDirectionRel, positionsTmp,
                    ref touchFrameTmp, ref radiusOffsetTmp, ref touchPosTmp,
                    ref fullActionSmuggleTmp, ref actionSmuggleTmp, ref rotationSmuggleTmp,
                    hasteFactor, localInterruptAnim, false);
                if (selectedAnimID == -1)                                      // :1713
                {
                    // подкат без дотягиваемого касания — берём лучший клип как есть (:1714-1720)
                    if (dataSet.Count > 0)                                     // :1714
                    {
                        selectedAnimID = dataSet[0];                           // :1715
                        Animation nextAnim = _anims.GetAnim(selectedAnimID);   // :1716
                        Vector3 slideDesiredMovement =
                            command.DesiredDirection * command.DesiredVelocityFloat; // :1717
                        // :1718 assert — не переносим; ШОВ PhysicsVector — как движ-ветка выше
                        _physics.SetSpatialState(_spatial.Position, _spatial.Angle,
                            _spatial.DirectionVec, _spatial.FloatVelocity, _spatial.Movement);
                        _physics.SetTouchContext(GetLastTouchBias(1000),
                            _decayingPositionOffset.Length());
                        _physics.Calculate(nextAnim, _anims.GetPositionCacheInternal(selectedAnimID),
                            command.UseDesiredMovement, slideDesiredMovement,
                            command.UseDesiredLookAt, desiredBodyDirectionRel, positionsTmp,
                            out rotationSmuggleTmp);                           // :1719
                    }
                }
            }

            // ---- «а точно ли реквей лучше текущего?» (:1725-1742) ----
            // Гейт :1727 требует, чтобы ОБА набора позиций были длиннее 1 кадра (иначе сравнивать
            // нечего).
            if (localInterruptAnim == HumanoidBase.InterruptReQueue && selectedAnimID != -1
                && _current.Positions.Count > 1 && positionsTmp.Count > 1)     // :1727
            {
                Animation selectedAnim = _anims.GetAnim(selectedAnimID);
                // не реквеим в тот же квадрант (:1729-1737): для НЕ-idle клипов сравнивается
                // строковый quadrant_id, для пары idle→idle — исходящие углы, сведённые в
                // предпочтительные направления, с порогом 0.06π
                if (_current.FunctionType == command.DesiredFunctionType &&    // :1730
                    ((Velo.FloatToEnumVelocity(_current.Anim.GetOutgoingVelocity()) != Velo.IdVelIdle
                      && _current.Anim.GetVariable("quadrant_id")
                         == selectedAnim.GetVariable("quadrant_id"))           // :1732-1733
                     ||
                     ((Velo.FloatToEnumVelocity(_current.Anim.GetOutgoingVelocity()) == Velo.IdVelIdle
                       && Velo.FloatToEnumVelocity(selectedAnim.GetOutgoingVelocity()) == Velo.IdVelIdle)
                      && Mathf.Abs(
                          _selector.ForceIntoPreferredDirectionAngle(_current.Anim.GetOutgoingAngle())
                          - _selector.ForceIntoPreferredDirectionAngle(selectedAnim.GetOutgoingAngle()))
                         < 0.06f * Mathf.Pi)))                                 // :1735-1736
                {
                    selectedAnimID = -1;                                       // :1739
                    // :1740 debug printf — не переносим
                }
            }

            // make it so (:1745-1786)
            if (selectedAnimID != -1)                                          // :1747
            {
                // :1759 *previousAnim = *currentAnim — усечённая копия (см. PreviousAnimState)
                _previous.FunctionType = _current.FunctionType;
                _previous.FrameNum = _current.FrameNum;

                _current.Anim = _anims.GetAnim(selectedAnimID);                // :1761
                _current.Id = selectedAnimID;                                  // :1762
                _current.FunctionType = command.DesiredFunctionType;           // :1763
                _current.FrameNum = 0;                                         // :1764
                _current.TouchFrame = touchFrameTmp;                           // :1765
                _current.OriginatingInterrupt = localInterruptAnim;            // :1766
                _current.RadiusOffset = radiusOffsetTmp;                       // :1767
                _current.TouchPos = touchPosTmp;                               // :1768
                // :1769 — кап смягчения тела: для НЕ-movement клипов вдвое меньше (× 0.5)
                float rotationSmuggleCap = BodyRotationSmoothingMaxAngle
                    * (_current.FunctionType == AnimCollection.FnMovement ? 1.0f : 0.5f);
                _current.RotationSmuggleBegin = Mathf.Clamp(
                    BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi,
                        _spatial.RelBodyAngleNonquantized - _current.Anim.GetIncomingBodyAngle())
                    * BodyRotationSmoothingFactor,
                    -rotationSmuggleCap, rotationSmuggleCap);                  // :1769
                _current.RotationSmuggleEnd = rotationSmuggleTmp;              // :1770
                _current.RotationSmuggleOffset = 0;                            // :1771
                _current.FullActionSmuggle = fullActionSmuggleTmp;             // :1772
                _current.ActionSmuggle = actionSmuggleTmp;                     // :1773
                _current.ActionSmuggleOffset = Vector3.Zero;                   // :1774
                _current.ActionSmuggleSustain = Vector3.Zero;                  // :1775 calculated below (сустейн :1799-1814 — закомментирован в оригинале)
                _current.ActionSmuggleSustainOffset = Vector3.Zero;            // :1776
                // :1777 — «needs to be reset here, else the previous calc is used in upcoming
                // 'calculatemovementsmuggle'» — ДВОЙНОЕ присваивание movementSmuggle
                // (:1777 и :1785) переносится как есть
                _current.MovementSmuggle = Vector3.Zero;                       // :1777
                _current.MovementSmuggleOffset = Vector3.Zero;                 // :1778
                _current.IncomingMovement = _spatial.Movement;                 // :1779
                _current.OutgoingMovement = CalculateOutgoingMovement(positionsTmp); // :1780
                _current.Positions.Clear();                                    // :1781
                _current.Positions.AddRange(positionsTmp);                     // :1782
                _current.PositionOffset = Vector3.Zero;                        // :1783
                // :1784 — в C++ PlayerCommand копируется ПО ЗНАЧЕНИЮ; снимок читают ReQueue-фильтры
                // (:1206-1207), поэтому берём копию, а не ссылку (см. PlayerCommand.Clone)
                _current.OriginatingCommand = command.Clone();                 // :1784
                _current.MovementSmuggle = CalculateMovementSmuggle(
                    command.DesiredDirection, command.DesiredVelocityFloat);   // :1785
                _current.MovementSmuggleOffset = Vector3.Zero;                 // :1786

                // :1788-1797 debug-пилоны и :1799-1814 actionSmuggleSustain — закомментированы
                // в оригинале, не переносим

                return true;                                                   // :1816
            }

            return false;                                                      // :1819
        }

        // ---- CalculateMovementSmuggle (:2326-2408) ----
        // «Дотянуть» движ-клип к мячу, пока игрок — designated possession. Параметры
        // desiredDirection/desiredVelocityFloat в теле оригинала НЕ используются — переносятся
        // и не читаются, как есть.
        internal Vector3 CalculateMovementSmuggle(Vector3 desiredDirection, float desiredVelocityFloat)
        {
            _ = desiredDirection; _ = desiredVelocityFloat; // не используются (см. выше)

            if (!EnableMovementSmuggle) return Vector3.Zero;                   // :2328

            // гейты :2330-2332 дословно; швы: team+match designated (:2330 И-нит оба предиката),
            // match->GetBallRetainer() != 0 → _isBallRetainer (в лабе ретейнер — только сам)
            if (!(_teamDesignatedPossession && _designatedPossession) ||        // :2330
                _current.TouchFrame != -1 ||
                (_current.FunctionType == AnimCollection.FnTrip
                    && _current.Anim.GetVariable("triptype") != "1") ||
                _current.Anim.GetVariable("incoming_special_state") != "" ||
                _current.Anim.GetVariable("outgoing_special_state") != "" ||   // :2331
                !_isInPlay || _isInSetPiece || _isBallRetainer)                // :2332
                return Vector3.Zero;

            Vector3 toDesired;                                                 // :2335

            // various stuff needed by all (:2338-2345)
            int timeToBallMs = _timeNeededToGetToBallMs;                       // :2340 (ШОВ)
            if (_desiredTimeToBallMs > timeToBallMs) timeToBallMs = _desiredTimeToBallMs; // :2341-2343
            int animTimeMs = _current.Anim.GetFrameCount() * 10;               // :2344
            int futureTimeMs = Mathf.Max(animTimeMs + GpfPitch.DefaultTouchOffsetMs, timeToBallMs); // :2345

            Vector3 predictedOutgoingMovement = CalculateOutgoingMovement(_current.Positions); // :2348
            CalculatePredictedSituation(out Vector3 predictedPos, out float predictedAngle); // :2349-2351
            // :2352 — ШОВ MentalImage (см. GetHasteFactor): GetBallPrediction → _ball.Predict
            Vector3 ballPos = _ball.Predict(futureTimeMs);                     // :2352
            float ballHeight = ballPos.Z;                                      // :2353
            Vector3 ffo = BluntMath.GetRotated2D(
                GetFrontOfFootOffsetRel(predictedOutgoingMovement.Length(),
                    _current.Anim.GetOutgoingBodyAngle(), ballHeight),
                predictedAngle);                                               // :2354
            Vector3 desiredBallPos = predictedPos + ffo;                       // :2355

            if (!HasPossession())                                              // :2358 (ШОВ-суррогат)
            {
                // macro effect: линия движения мяча; тянемся от желаемой точки к ней (:2360-2361)
                Vector3 v0 = BluntMath.Get2D(_ball.Predict(0));                // :2364
                Vector3 v1 = BluntMath.Get2D(_ball.Predict(futureTimeMs));     // :2365
                if ((v1 - v0).Length() < 0.5f) return Vector3.Zero;            // :2366 — мяч медленный/близкий

                float u = BluntMath.LineClosestToPoint(v0, v1, desiredBallPos); // :2369 (без клампа, как GetClosestToPoint)
                Vector3 closestBallPos = v0 + (v1 - v0) * u;                   // :2370

                toDesired = closestBallPos - desiredBallPos;                   // :2372
            }
            else // if HasPossession (:2374)
            {
                toDesired = BluntMath.Get2D(ballPos) - desiredBallPos;         // :2376
            }

            // мяч «дальше», чем успеем? — отложить эффект до следующего клипа (:2381)
            int maxEffectTimeTresholdMs = 250 + GpfPitch.DefaultTouchOffsetMs; // :2381
            if (Velo.FloatToEnumVelocity(_current.Anim.GetOutgoingVelocity()) == Velo.IdVelIdle)
                maxEffectTimeTresholdMs = 2000; // :2382 — no danger of overrunning
            float maxEffectVelocity = Velo.DribbleWalkSwitch;                  // :2383
            float maxSmuggleMps = 1.6f;                                        // :2384

            if (futureTimeMs - (animTimeMs + GpfPitch.DefaultTouchOffsetMs) > maxEffectTimeTresholdMs)
                return Vector3.Zero;                                           // :2386

            Vector3 toDesiredMovement = toDesired / (animTimeMs * 0.001f);     // :2388
            Vector3 resultingMovement = predictedOutgoingMovement + toDesiredMovement; // :2389
            float predictedVelocity = predictedOutgoingMovement.Length();      // :2390
            float resultingVelocity = resultingMovement.Length();              // :2391
            if (resultingVelocity > predictedVelocity && resultingVelocity > maxEffectVelocity)
                return Vector3.Zero;                                           // :2392

            toDesired = BluntMath.NormalizeMax(toDesired,
                maxSmuggleMps * (_current.Anim.GetEffectiveFrameCount() * 0.01f)); // :2394

            // remove part of the smuggle (:2398-2399)
            float removeDistance = 0.06f;                                      // :2398
            toDesired = BluntMath.GetNormalized(toDesired, Vector3.Zero)
                * Mathf.Max(0.0f, toDesired.Length() - removeDistance);        // :2399

            // :2401-2406 debug-пилоны — не переносим
            return toDesired;                                                  // :2407
        }

        // ---- NeedTouch (:1822-1857) ----
        // «когда стоим (и хотим стоять), не надо трогать мяч каждый кадр» (:1824)
        internal bool NeedTouch(int animId, PlayerCommand command)
        {
            Animation anim = _anims.GetAnim(animId);                               // :1826

            // :1828 — СКОБОЧНЫЙ БАГ ОРИГИНАЛА, переносится КАК ЕСТЬ:
            //   if (FloatToEnumVelocity(anim->GetOutgoingVelocity() != e_Velocity_Idle))
            // сравнение выполнено ВНУТРИ вызова: bool (0.0f/1.0f) уходит в FloatToEnumVelocity,
            // а та на 0.0 и на 1.0 одинаково отдаёт e_Velocity_Idle (1.0 < idleDribbleSwitch=1.8)
            // → условие ВСЕГДА false. Скорее всего задумывалось
            //   FloatToEnumVelocity(anim->GetOutgoingVelocity()) != e_Velocity_Idle. НЕ чиним.
            if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity() != Velo.Idle ? 1.0f : 0.0f)
                != Velo.IdVelIdle) return true;
            if (command.DesiredVelocityFloat > Velo.IdleDribbleSwitch) return true; // :1829
            if (Mathf.Abs(_ball.GetMovement().Length()) > 2.0f) return true;        // :1830

            Vector3 animMovement = BluntMath.GetRotated2D(anim.GetOutgoingMovement(), _spatial.Angle)
                * 0.3f + _spatial.Movement * 0.7f;                                 // :1832
            float animVelo = animMovement.Length();                                // :1837
            animMovement = BluntMath.GetNormalized(animMovement, _spatial.DirectionVec); // :1838
            animMovement *= _spatial.Movement.Length() * 0.8f + animVelo * 0.2f;   // :1839

            // :1841 — ШОВ MentalImage (см. GetHasteFactor): GetBallPrediction → _ball.Predict
            Vector3 ballMovement = (BluntMath.Get2D(_ball.Predict(250))
                - BluntMath.Get2D(_ball.Predict(240))) * 100.0f;

            if (Mathf.Abs(anim.GetOutgoingAngle()) > 0.125f * Mathf.Pi) return true; // :1843

            float distanceDeviation = (animMovement - ballMovement).Length();      // :1845
            if (distanceDeviation >= 2.0f) return true;                            // :1846

            // отрицательное == мяч быстрее (:1848)
            float velocityDeviation = animMovement.Length() - ballMovement.Length();
            if (velocityDeviation < -1.4f || velocityDeviation >= 0.7f) return true; // :1849

            if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) != Velo.IdVelIdle) // :1851
            {
                float angleDeviation = BluntMath.GetNormalized(animMovement, _spatial.DirectionVec)
                    .Dot(BluntMath.GetNormalized(ballMovement, _spatial.DirectionVec)); // :1852
                if (angleDeviation < 0.975f) return true;                          // :1853
            }

            return false;                                                          // :1856
        }

        // ---- GetFrontOfFootOffsetRel (humanoid_utils.cpp:103-115) ----
        // Смещение, где нога «хочет» видеть мяч (отн. корня, anim space).
        internal static Vector3 GetFrontOfFootOffsetRel(float velocity, float bodyAngleRel, float height)
        {
            float fullDistanceFactor = 1.0f;                                   // :105
            // :106 — должно быть > 0 (ради будущего dot-product); defaultTouchOffset_ms = 80
            float distance = 0.34f + velocity * GpfPitch.DefaultTouchOffsetMs * 0.001f * fullDistanceFactor;

            Vector3 ffo = new Vector3(0, -distance * 0.8f, 0);                 // :108

            float bodyAngle = bodyAngleRel;                                    // :110
            if (velocity < Velo.IdleDribbleSwitch) bodyAngle = 0;              // :111
            Vector3 angled = BluntMath.GetRotated2D(new Vector3(0, -distance * 0.2f, 0), bodyAngle); // :112

            return (ffo + angled) * (1.0f - Mathf.Clamp((height - 0.11f) / 4.0f, 0.0f, 0.5f)); // :114
        }

        // ---- GetLastTouchBias (playerbase.cpp:141-146) ----
        // 1 сразу после касания → 0 спустя decayMs. Поверх швов _lastTouchTimeMs/_actualTimeMs
        // (см. поля выше); в оригинале время беззнаковое (unsigned long) — у нас long, семантика
        // на живых значениях совпадает.
        internal float GetLastTouchBias(int decayMs, long timeMs = 0)
        {
            long adaptedTimeMs = timeMs;                                       // :142
            if (timeMs == 0) adaptedTimeMs = _actualTimeMs;                    // :143 match->GetActualTime_ms()
            if (decayMs > 0)
                return 1.0f - Mathf.Clamp(
                    (adaptedTimeMs - _lastTouchTimeMs) / (float)decayMs, 0.0f, 1.0f); // :144
            return 0.0f;                                                       // :145
        }

        // ---- Аксессоры для лаб-оркестратора коллизий (задача 8) ----
        // Match::CheckBallCollisions (match.cpp:1943-1972) читает у players[i] ровно эти
        // предикаты; в порте цикл по игрокам выполняет вызывающий (комментарий у ExecuteTouchTick),
        // поэтому те же значения он обязан уметь достать. Логики здесь нет — только доступ.
        public int GetCurrentFunctionType() => _current.FunctionType;   // player: GetCurrentFunctionType()
        public bool GetHasPossession() => HasPossession();              // :1972 players[i]->HasPossession()
        // HasUniquePossession (match.cpp:1972) — «мяч только у меня»; соперников в лабе нет,
        // поэтому предикат совпадает с HasPossession. Матч-слой (задача 9+) разведёт их.
        public bool GetHasUniquePossession() => HasPossession();
        public long GetActualTimeMs() => _actualTimeMs;                 // match->GetActualTime_ms()
        public float GetLastTouchBiasMs(int decayMs) => GetLastTouchBias(decayMs); // playerbase.cpp:141
        // Player::TriggerControlledBallCollision (player.hpp) — вызывается из match.cpp:1998.
        public void TriggerControlledBallCollision() => _controlledBallCollisionTriggered = true;
        // Team::SetLastTouchPlayer(..., e_TouchType_Accidental) (match.cpp:2006 → team.cpp:241-248):
        // player-часть уже есть (RegisterTouch), наружу её зовёт оркестратор по флагу коллайдера.
        public void RegisterAccidentalTouch() => RegisterTouch(TouchTypeAccidental);
        // touchPos текущего клипа (humanoidbase.hpp:98) — маркер приёмки «нога у мяча» в лабе.
        public Vector3 GetCurrentTouchPos() => _current.TouchPos;

        // ---- GetBodyBallDistanceAdvantage (:1859-1997) ----
        // 1.0 == «дотягиваемся» (мяч внутри деформированной смаггл-зоны), 0.0 == deny.
        // Ассерты Z==0 оригинала (:1861-1862) не переносим; их семантику держит вызывающий код.
        internal float GetBodyBallDistanceAdvantage(Animation anim, int functionType,
            Vector3 animTouchMovement, Vector3 touchMovement, Vector3 incomingMovement,
            Vector3 outgoingMovement, float outgoingAngle, Vector3 bodyPos, Vector3 ffo,
            Vector3 animBallPos2D, Vector3 actualBallPos2D, Vector3 ballMovement2D,
            float radiusFactor, float radiusCheatDistance, float decayPow, bool debug)
        {
            // :1867-1876 — скорости
            float touchVelocity = touchMovement.Length();                      // :1867
            float animTouchVelocity = animTouchMovement.Length();              // :1868
            float highestTouchVelocity = Mathf.Max(animTouchVelocity, touchVelocity); // :1869

            float incomingVelocity = incomingMovement.Length();                // :1871
            float outgoingVelocity = outgoingMovement.Length();                // :1872
            float averageInOutVelocity = (incomingMovement + outgoingMovement).Length() * 0.5f; // :1873
            float highestInOutVelocity = Mathf.Max(incomingVelocity, outgoingVelocity); // :1874

            // :1876 — дальше не используется, как в оригинале
            float highestVelocity = Mathf.Max(highestTouchVelocity, highestInOutVelocity);
            _ = highestVelocity;

            float velocityChange = outgoingVelocity - incomingVelocity;        // :1878
            float velocityChangeMps = velocityChange / (anim.GetFrameCount() * 0.01f); // :1879

            // :1882-1885 — бонусы близости/скорости («less FFO feels better», :1882)
            float bodyAnimBallBonus = 1.0f - BluntMath.Curve(BluntMath.NormalizedClamp(
                ((bodyPos + BluntMath.GetNormalized(ffo, Vector3.Zero) * 0.1f) - animBallPos2D).Length(),
                0.0f, 0.7f), 0.7f);                                            // :1882
            float bodyActualBallBonus = 1.0f - BluntMath.Curve(BluntMath.NormalizedClamp(
                ((bodyPos + BluntMath.GetNormalized(ffo, Vector3.Zero) * 0.1f) - actualBallPos2D).Length(),
                0.0f, 0.7f), 0.4f);                                            // :1883
            float velocityBonus = 1.0f - BluntMath.NormalizedClamp(
                averageInOutVelocity, Velo.Idle, Velo.Sprint);                 // :1884
            float velocityChangeBonus = 1.0f - BluntMath.NormalizedClamp(
                velocityChangeMps / 20.0f, -1.0f, 1.0f);                       // :1885

            // :1888-1894 — радиус
            float radius = radiusFactor;                                       // :1888
            radius *= 1.0f +
                      1.0f * bodyAnimBallBonus +
                      0.6f * bodyActualBallBonus +
                      0.8f * bodyAnimBallBonus * bodyActualBallBonus +
                      0.0f * velocityChangeBonus +
                      1.0f * velocityBonus;                                    // :1889-1894

            // :1896-1899 — «больше чита быстрым мячам» закомментирован в оригинале, не переносим

            float effectiveRadiusCheatDistance = radiusCheatDistance;          // :1901

            // :1903-1908 — исходящее направление
            Vector3 outgoingDirection;
            if (Velo.FloatToEnumVelocity(outgoingMovement.Length()) == Velo.IdVelIdle)
                outgoingDirection = BluntMath.GetRotated2D(new Vector3(0, -1, 0), outgoingAngle); // :1905
            else
                outgoingDirection = BluntMath.GetNormalized(outgoingMovement, Vector3.Zero);      // :1907

            // :1911-1916 — behindVector: зона смещается назад по ходу
            Vector3 behindVectorUnscaled = -(incomingMovement * 0.1f + touchMovement * 0.2f + outgoingMovement * 0.7f);
            Vector3 behindVector =
                BluntMath.GetNormalized(behindVectorUnscaled, Vector3.Zero) *
                Mathf.Pow(BluntMath.NormalizedClamp(behindVectorUnscaled.Length(), 0, Velo.Sprint), 0.5f);

            // на поворотах — более центрированный behindvec, «богаче» охват (:1918-1921)
            float dot = new Vector3(0, -1, 0).Dot(outgoingDirection);          // :1919
            dot = 0.5f + Mathf.Clamp(dot * 0.5f + 0.5f, 0.0f, 1.0f) * 0.5f;    // :1920
            behindVector *= dot;                                               // :1921

            Vector3 animToActualBall = actualBallPos2D - animBallPos2D;        // :1923

            bool deformArea = true;                                            // :1925
            if (deformArea)
            {
                Vector3 straightAngleVectorUnscaled = incomingMovement;        // :1927
                Vector3 straightAngleVector = BluntMath.GetNormalized(straightAngleVectorUnscaled, outgoingDirection); // :1928
                float toStraightAngle = BluntMath.GetAngle2D(new Vector3(0, -1, 0), straightAngleVector); // :1929

                // поворачиваем animball→actualball в исходящее направление и колдуем (:1931-1932)
                animToActualBall = BluntMath.GetRotated2D(animToActualBall, toStraightAngle);

                // латеральный (от исходящего вектора) чит труднее на скорости —
                // круг превращается в эллипс (:1934-1939)
                float lateralRadiusFactor =
                    0.6f -
                    0.3f * Mathf.Pow(BluntMath.NormalizedClamp(straightAngleVectorUnscaled.Length(),
                                                               Velo.Idle, Velo.Sprint), 0.7f);
                animToActualBall.X /= lateralRadiusFactor; // :1940 — X теперь латеральная компонента
                // :1941-1945 — сохранить площадь (π·r²): sqrt от множителя площади
                radius *= Mathf.Pow(1.0f / lateralRadiusFactor, 0.5f);
                // :1946-1955 — «brick wall» закомментирован в оригинале, не переносим
                // поворачиваем обратно, как будто ничего не было (:1956-1957)
                animToActualBall = BluntMath.GetRotated2D(animToActualBall, -toStraightAngle);
            }

            // do some magic (:1961-1966)
            Vector3 adaptedActualBallPos2D = animBallPos2D + animToActualBall; // :1963

            float radiusCheatBehindBias = 0.6f; // :1965 — насколько radiuscheat слушает behindvec
            Vector3 behindCenter = animBallPos2D + behindVector *
                (radius + (effectiveRadiusCheatDistance * radiusCheatBehindBias)) * CheatFactor; // :1966

            float result = 1.0f;                                               // :1968
            float allowedRadius = (radius + effectiveRadiusCheatDistance) * CheatFactor + CheatDistanceBonus; // :1969
            if (adaptedActualBallPos2D.DistanceTo(behindCenter) > allowedRadius) result = 0.0f; // :1970 (stat-счётчик не переносим)

            // :1972-1992 — debug-пилоны не переносятся; :1994 закомментирован в оригинале

            return result;                                                     // :1996
        }

        // ---- GetBestCheatableAnimID (:1999-2323) ----
        // Перебирает sorted dataSet и касания каждого клипа, ищет первый «дотягиваемый» тач;
        // наружу — id клипа, кадр/позиция касания и смагглы. hasteFactor и localInterruptAnim
        // в теле оригинала НЕ используются — параметры переносятся и не читаются.
        internal int GetBestCheatableAnimID(List<int> sortedDataSet, bool useDesiredMovement,
            Vector3 desiredDirection, float desiredVelocityFloat, bool useDesiredBodyDirection,
            Vector3 desiredBodyDirectionRel, List<Vector3> positionsRet, ref int animTouchFrameRet,
            ref float radiusOffsetRet, ref Vector3 touchPosRet, ref Vector3 fullActionSmuggleRet,
            ref Vector3 actionSmuggleRet, ref float rotationSmuggleRet, float hasteFactor,
            int localInterruptAnim, bool preferPassAndShot)
        {
            // :2001-2002 — чужой ретейнер (мяч в руках другого) запрещает тач-клипы. В лабе
            // фазы 4 ретейнер — либо «сам», либо никто (SetBallRetainerSelf), состояния «чужой»
            // не существует → ветка-шов вернётся с матчем (задача 9+).

            // ШОВ: в C++ CalculatePhysicsVector — член humanoid'а, читающий spatialState
            // напрямую; наш PhysicsVector — отдельный объект, передаём ему то же состояние
            // (как SelectNextMovementAnim, HumanoidBase.cs).
            _physics.SetSpatialState(_spatial.Position, _spatial.Angle, _spatial.DirectionVec,
                _spatial.FloatVelocity, _spatial.Movement);
            // player->GetLastTouchBias(1000) + decayingPositionOffset — контекст
            // CalculatePhysicsVector (humanoidbase.cpp:2082-2084); единообразно с движ-веткой
            // SelectAnim (ревью задачи 4)
            _physics.SetTouchContext(GetLastTouchBias(1000), _decayingPositionOffset.Length());

            Vector3 incomingMovement = BluntMath.GetRotated2D(_spatial.Movement, -_spatial.Angle); // :2004

            int bestAnimID = -1;                                               // :2006
            Vector3 bestActionSmuggleVec2D = Vector3.Zero;                     // :2007
            // bestTouchMovementAbs (:2008, :2225) — присваивается и нигде не читается, не переносим

            int iterIdx = 0;                                                   // :2010 iter = begin

            Vector3 desiredMovement = desiredDirection * desiredVelocityFloat; // :2012

            float playerHeight = _playerHeight;                                // :2014 player->GetPlayerData()->GetHeight()

            // :2016 — functionType от ПЕРВОГО клипа списка (не от команды!) — bug-for-bug
            int functionType = AnimCollection.StringToFunctionType(
                _anims.GetAnim(sortedDataSet[0]).GetAnimType());

            float rotationSmuggleTmp = 0f;                                     // :2018 rotationSmuggle_ret_tmp
            float predictedAngle = 0f;                                         // :2019
            Vector3 adaptedOutgoingMovement = Vector3.Zero;                    // :2020

            bool found = false;                                                // :2024
            while (iterIdx < sortedDataSet.Count && !found)                    // :2025
            {
                Animation anim = _anims.GetAnim(sortedDataSet[iterIdx]);       // :2027
                bool isBase = anim.GetVariable("baseanim") == "true";          // :2028

                // :2030 match->GetAnimPositionCache(anim) — кэш живёт при коллекции (фаза 2)
                List<Vector3> origPositionCache = _anims.GetPositionCacheInternal(sortedDataSet[iterIdx]);

                // :2034 — траектория клипа под текущую физику (варп фазы 3)
                _physics.Calculate(anim, origPositionCache, useDesiredMovement, desiredMovement,
                    useDesiredBodyDirection, desiredBodyDirectionRel, positionsRet, out rotationSmuggleTmp);

                // anim space! (:2036-2038)
                predictedAngle = anim.GetOutgoingAngle() + rotationSmuggleTmp; // :2037
                predictedAngle = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi, predictedAngle); // :2038

                int touchNum = 0;                                              // :2041

                Vector3 outgoingMovement = BluntMath.GetRotated2D(
                    CalculateOutgoingMovement(positionsRet), -_spatial.Angle); // :2050
                // :2051 — «может стать touchMovement, когда клип найден» — в коде так и не меняется
                adaptedOutgoingMovement = outgoingMovement;

                int frameCount = anim.GetEffectiveFrameCount();                // :2053

                int totalTouches = anim.GetTouchCount();                       // :2057 footballExtension->GetTouchCount()
                // :2058 — vector<int> touchIDs(totalTouches). Запас +1: при totalTouches == 0
                // цикл :2065 всё равно пишет touchIDs[0] (в C++ это UB-запись за границу
                // вектора); тач-перебор ниже при этом не выполняется, поведение не меняется.
                var touchIDs = new int[totalTouches + 1];
                int count = 0;                                                 // :2059

                int defaultTouchFrame = BluntMath.AtoI(anim.GetVariable("touchframe")); // :2061

                // сначала средний тач и вниз до первого (:2064-2068)
                for (int i = totalTouches / 2; i > -1; i--) { touchIDs[count] = i; count++; }
                // затем следующий-за-средним и вверх (:2069-2073)
                for (int i = totalTouches / 2 + 1; i < totalTouches; i++) { touchIDs[count] = i; count++; }

                while (touchNum < totalTouches && !found)                      // :2075
                {
                    // :2077 GetTouch(touchIDs[touchNum], animBallPos, animTouchFrame)
                    Vector3 animBallPos = anim.GetTouchPosition(touchIDs[touchNum]);
                    int animTouchFrame = anim.GetTouchFrame(touchIDs[touchNum]);

                    // мяч за пределами поля в кадр касания? (:2082-2090); 0.11 — радиус мяча
                    if (!_isBallRetainer)                                      // :2083 GetBallRetainer() != player
                    {
                        Vector3 absBallPos = _ball.Predict(animTouchFrame * 10); // :2084 (мяч, не MentalImage)
                        if (Mathf.Abs(absBallPos.X) > GpfPitch.PitchHalfW + GpfPitch.LineHalfW + 0.11f ||
                            Mathf.Abs(absBallPos.Y) > GpfPitch.PitchHalfH + GpfPitch.LineHalfW + 0.11f) // :2085-2086
                        {
                            touchNum++;                                        // :2087
                            continue;                                          // :2088
                        }
                    }

                    // :2095-2096 — движение в кадр касания: варпнутое и исходное (smoothFrames —
                    // дефолтный 0, humanoid_utils.hpp:25; третьего аргумента в вызовах C++ нет)
                    Vector3 touchMovement = BluntMath.GetRotated2D(
                        PhysicsVector.CalculateMovementAtFrame(positionsRet, animTouchFrame),
                        -_spatial.Angle);                                      // :2095
                    Vector3 animTouchMovement =
                        PhysicsVector.CalculateMovementAtFrame(origPositionCache, animTouchFrame); // :2096 уже anim space

                    // :2098-2102 — предсказание мяча (ШОВ MentalImage, см. GetHasteFactor:
                    // GetBallPrediction → объективный _ball.Predict)
                    Vector3 ballPos = _ball.Predict(animTouchFrame * 10);      // :2099
                    Vector3 ballMovement = (_ball.Predict(animTouchFrame * 10 + 10)
                        - _ball.Predict(animTouchFrame * 10)) * 100.0f;        // :2100
                    ballPos = BluntMath.GetRotated2D(ballPos - _spatial.Position, -_spatial.Angle); // :2101
                    ballMovement = BluntMath.GetRotated2D(ballMovement, -_spatial.Angle);           // :2102

                    Vector3 bodyPos = BluntMath.GetRotated2D(positionsRet[animTouchFrame], -_spatial.Angle); // :2104
                    bodyPos.Z = 0;                                             // :2105

                    // :2107 GetKeyFrame("player") → интерполированные rotation + position
                    Quaternion animBodyRot = anim.GetInterpolatedRotation("player", animTouchFrame);
                    Vector3 animBodyPos = anim.SampleRootPosition(animTouchFrame, 0f);

                    QuatUtil.GetAngles(animBodyRot, out float rotX, out float rotY, out float rotZ); // :2109-2110
                    _ = rotX; _ = rotY; // в :2192 используется только z

                    float animBallHeight = animBallPos.Z;                      // :2112
                    if (AllowPreTouchRotationSmuggle)                          // :2113 (humanoid.cpp:64, false)
                        animBallPos = BluntMath.GetRotated2D(animBallPos - animBodyPos,
                                rotationSmuggleTmp * (animTouchFrame / (float)frameCount))
                            + BluntMath.GetRotated2D(positionsRet[animTouchFrame], -_spatial.Angle); // :2114
                    else
                        animBallPos = (animBallPos - animBodyPos)
                            + BluntMath.GetRotated2D(positionsRet[animTouchFrame], -_spatial.Angle); // :2116
                    animBallPos.Z = animBallHeight * (playerHeight / GpfPitch.DefaultPlayerHeight);  // :2118

                    // берём ближайшую к animBallPos точку мяча из окна −6..+3 мс — эмуляция
                    // непрерывной проверки вместо «одного момента» (:2121-2126)
                    if (UseContinuousBallCheck)                                // :2122
                    {
                        Vector3 v0 = ballPos - ballMovement * 0.006f;          // :2123 Line(...)
                        Vector3 v1 = ballPos + ballMovement * 0.003f;
                        float u = Mathf.Clamp(BluntMath.LineClosestToPoint(v0, v1, animBallPos), 0.0f, 1.0f); // :2124
                        ballPos = v0 + (v1 - v0) * u;                          // :2125
                    }

                    Vector3 actionSmuggleVec3D = ballPos - animBallPos;        // :2129
                    Vector3 actionSmuggleVec2D = BluntMath.Get2D(actionSmuggleVec3D); // :2130

                    // высота мяча (:2133-2147)
                    float ballDistanceZ = Mathf.Abs(actionSmuggleVec3D.Z);     // :2135
                    // высоким мячам — больше Z-чита, иначе нужен клип на каждую высоту (:2139)
                    ballDistanceZ *= 1.0f - Mathf.Clamp((animBallPos.Z - 0.11f) * 0.3f, 0.0f, 0.2f); // :2139
                    ballDistanceZ *= 1.0f - Mathf.Clamp((ballPos.Z - 0.11f) * 0.4f, 0.0f, 0.3f);     // :2140
                    // но максимум высоты принудить (:2141-2143)
                    if (ballPos.Z > 1.8f && ballPos.Z > animBallPos.Z + 0.12f) ballDistanceZ *= 2.0f;  // :2142
                    if (ballPos.Z > 2.6f && ballPos.Z > animBallPos.Z + 0.08f) ballDistanceZ *= 20.0f; // :2143
                    if (functionType == AnimCollection.FnDeflect) ballDistanceZ *= 0.8f;               // :2144
                    if (_isBallRetainer) ballDistanceZ = 0.0f;                 // :2145 GetBallRetainer() == player
                    // низкие мячи можно брать ground-клипами, выглядит неплохо (:2147)
                    if (ballPos.Z < 0.5f && isBase) ballDistanceZ = Mathf.Max(ballDistanceZ - 0.15f, 0.0f);

                    if (ballDistanceZ < 0.22f)                                 // :2149
                    {
                        // дефолтный тач можно «читить» сильнее всех — наибольший радиус (:2151-2153)
                        float touchFrameAwkwardness = BluntMath.NormalizedClamp(
                            Mathf.Abs(defaultTouchFrame - animTouchFrame), 0.0f, 4.0f); // :2152
                        touchFrameAwkwardness = Mathf.Pow(touchFrameAwkwardness, 2.0f) * 0.5f; // :2153

                        // :2155-2160 — flowVector-эксперимент закомментирован в оригинале

                        // ~0.5 у «среднего» кадра касания (:2162); бонус ранним касаниям —
                        // чита больше, но короче (:2163-2166); круче спад после 1.0 (:2167-2168)
                        float touchFrameFactor = animTouchFrame / 24.0f;       // :2162
                        touchFrameFactor = Mathf.Pow(touchFrameFactor, 0.7f);  // :2163
                        if (touchFrameFactor > 1.0f) touchFrameFactor = 1.0f + ((touchFrameFactor - 1.0f) * 0.5f); // :2168

                        // float decayPow = 1.0f (:2170) — в вызов :2215 уходит литералом, не переносим
                        float radiusCheatOffset = 0.0f;                        // :2171
                        float radiusFactor = 0.3f * (1.0f - touchFrameAwkwardness); // :2172

                        if (functionType == AnimCollection.FnDeflect) { radiusFactor *= 1.8f; radiusCheatOffset += 0.4f; } // :2174
                        // слайд предпочтительнее без касания мяча (:2176)
                        if (functionType == AnimCollection.FnSliding) { radiusFactor *= 0.2f; radiusCheatOffset = 0.0f; }
                        if (functionType == AnimCollection.FnInterfere) { radiusFactor *= 1.4f; radiusCheatOffset += 0.2f; } // :2177
                        if (functionType == AnimCollection.FnShortPass) { radiusFactor *= 1.3f; radiusCheatOffset += 0.15f; } // :2179
                        if (functionType == AnimCollection.FnLongPass) { radiusFactor *= 1.3f; radiusCheatOffset += 0.15f; }  // :2180
                        if (functionType == AnimCollection.FnHighPass) { radiusFactor *= 1.3f; radiusCheatOffset += 0.15f; }  // :2181
                        if (functionType == AnimCollection.FnShot) { radiusFactor *= 1.3f; radiusCheatOffset += 0.15f; }      // :2182
                        if ((functionType == AnimCollection.FnTrap ||
                             functionType == AnimCollection.FnBallControl) && preferPassAndShot)
                            radiusFactor *= 0.3f;                              // :2184-2186

                        radiusCheatOffset *= (1.0f - touchFrameAwkwardness);   // :2188

                        float touchVelo = touchMovement.Length();              // :2190

                        Vector3 ffo = GetFrontOfFootOffsetRel(touchVelo, rotZ, ballPos.Z); // :2192
                        // idle-ветка :2193-2194 — no-op (Rotate2D(z) закомментирован в оригинале)
                        if (Velo.FloatToEnumVelocity(touchVelo) != Velo.IdVelIdle)
                            ffo = BluntMath.GetRotated2D(ffo, BluntMath.FixAngle(BluntMath.GetAngle2D(
                                BluntMath.GetNormalized(touchMovement, new Vector3(0, -1, 0))))); // :2196

                        // только что коснулись мяча — радиус жмётся (:2203-2209)
                        float lastTouchBias = BluntMath.Curve(GetLastTouchBias(600,
                            _actualTimeMs + animTouchFrame * 10), 1.0f);       // :2204
                        if (lastTouchBias > 0.0f)                              // :2205
                        {
                            float factor = 1.0f - lastTouchBias * 0.97f
                                * (1.0f - _statTechnicalBallControl * 0.1f);   // :2206
                            radiusFactor *= factor;                            // :2207
                            radiusCheatOffset *= factor;                       // :2208
                        }

                        float touchFramedRadiusFactor = radiusFactor * touchFrameFactor; // :2214
                        float bodyBallDistanceAdvantage = GetBodyBallDistanceAdvantage(anim, functionType,
                            animTouchMovement, touchMovement, incomingMovement, adaptedOutgoingMovement,
                            predictedAngle, bodyPos, ffo, BluntMath.Get2D(animBallPos),
                            BluntMath.Get2D(ballPos), BluntMath.Get2D(ballMovement),
                            touchFramedRadiusFactor, radiusCheatOffset, 1.0f, false); // :2215 (debug=false, :2212)

                        if (bodyBallDistanceAdvantage >= 1.0f || _isBallRetainer) // :2217
                        {
                            found = true;                                      // :2221
                            bestAnimID = sortedDataSet[iterIdx];               // :2223
                            bestActionSmuggleVec2D = actionSmuggleVec2D;       // :2224
                            // :2225 bestTouchMovementAbs — мёртвое присваивание, см. выше
                            animTouchFrameRet = animTouchFrame;                // :2226
                            radiusOffsetRet = 1000.0f; // :2227 — todo оригинала «is this still in use?», как есть
                        }
                    }
                    touchNum++;                                                // :2231
                }
                iterIdx++;                                                     // :2233
            }

            if (found)                                                         // :2236
            {
                touchPosRet = _ball.Predict(animTouchFrameRet * 10);           // :2238 (ШОВ MentalImage)

                fullActionSmuggleRet = BluntMath.GetRotated2D(bestActionSmuggleVec2D, _spatial.Angle); // :2240
                actionSmuggleRet = fullActionSmuggleRet;                       // :2241

                if (ForceFullActionSmuggleDiscard)                             // :2243
                {
                    actionSmuggleRet = Vector3.Zero;                           // :2245
                }
                else if (EnableActionSmuggleDiscard)                           // :2247
                {
                    // cheat discard distance — не показывать часть чита («чит на чит», :2249)
                    float smuggleDistance = actionSmuggleRet.Length();         // :2250
                    float adaptedCheatDiscardDistanceMultiplier = CheatDiscardDistanceMultiplier; // :2251
                    if (functionType != AnimCollection.FnBallControl)
                        adaptedCheatDiscardDistanceMultiplier *= 0.8f;         // :2252
                    if (touchPosRet.Z > 0.5f) adaptedCheatDiscardDistanceMultiplier *= 0.7f; // :2253
                    if (touchPosRet.Z > 1.0f) adaptedCheatDiscardDistanceMultiplier *= 0.7f; // :2254
                    float cheatDiscardDistanceBonus = 0.0f;                    // :2255
                    if (functionType == AnimCollection.FnInterfere)
                        cheatDiscardDistanceBonus += 0.1f;                     // :2256 — не рвать поток

                    // метод 1: всегда сбрасываем часть смаггл-дистанции (:2263-2265)
                    smuggleDistance = Mathf.Clamp(
                        smuggleDistance - (CheatDiscardDistance + cheatDiscardDistanceBonus),
                        0.0f, 100.0f);                                         // :2264
                    smuggleDistance *= 1.0f - adaptedCheatDiscardDistanceMultiplier; // :2265

                    // :2267 — std::min с maxSmuggleDiscardDistance ПОРТИРУЕТСЯ КАК ЕСТЬ: при
                    // |full| < 0.2 даёт ОТРИЦАТЕЛЬНУЮ дистанцию, и присваивание ниже (:2281)
                    // разворачивает смаггл ОТ мяча.
                    // СВЕРЕНО С ОРИГИНАЛОМ 2026-08-03 (vi3itor/GameplayFootball,
                    // src/onthepitch/player/humanoid/humanoid.cpp:2267 — дословно
                    // `smuggleDistance = std::min(smuggleDistance,
                    //  actionSmuggle_ret.GetLength() - maxSmuggleDiscardDistance);`, тот же блок
                    // побайтово совпадает и в upstream BazkieBumpercar:2221). Это баг САМОГО
                    // оригинала, а не порта: строка воспроизведена верно. Замер в ball_lab —
                    // применённый смаггл смотрит ОТ мяча на каждом касании стабильного ведения
                    // (|full| = 0.06..0.18 < 0.2). НЕ чинить (global-constraints, bug-for-bug).
                    smuggleDistance = Mathf.Min(smuggleDistance,
                        actionSmuggleRet.Length() - MaxSmuggleDiscardDistance);

                    // :2269-2278 — «метод 2» помечен deprecated в оригинале, не переносим

                    if (_isBallRetainer) smuggleDistance = 0.0f;               // :2280
                    actionSmuggleRet = BluntMath.GetNormalized(actionSmuggleRet, Vector3.Zero) * smuggleDistance; // :2281

                    // гашение передней компоненты смаггла (:2284-2311)
                    if (DiscardForwardSmuggle || DiscardSidewaysSmuggle)       // :2286
                    {
                        float toStraightAngle = _spatial.Angle + predictedAngle; // :2288
                        actionSmuggleRet = BluntMath.GetRotated2D(actionSmuggleRet, -toStraightAngle); // :2289

                        if (DiscardForwardSmuggle)                             // :2291
                        {
                            float shortenForwardDistance = 0.02f;              // :2293
                            float allowForwardDistance =
                                0.25f *
                                (1.0f -
                                 Mathf.Pow(BluntMath.NormalizedClamp(adaptedOutgoingMovement.Length(),
                                                                     Velo.Idle, Velo.Sprint - 2.0f),
                                           0.6f)) *
                                (animTouchFrameRet * 0.1f);                    // :2294-2300
                            // пасам/ударам/интерферам можно смагглить вперёд больше — их
                            // движение-после не так важно (:2301)
                            if (functionType != AnimCollection.FnBallControl &&
                                functionType != AnimCollection.FnTrap)
                                allowForwardDistance += 0.1f;
                            if (actionSmuggleRet.Y < 0.0f)
                                actionSmuggleRet.Y = Mathf.Clamp(actionSmuggleRet.Y + shortenForwardDistance,
                                    -allowForwardDistance, 0.0f);              // :2302
                        }
                        if (DiscardSidewaysSmuggle)                            // :2304-2306
                            actionSmuggleRet.X *= 0.7f;

                        actionSmuggleRet = BluntMath.GetRotated2D(actionSmuggleRet, toStraightAngle); // :2308
                    }

                    // меньше хаоса в микро-битвах (:2313-2314); ШОВ GetClosestOpponentDistance:
                    // в лабе соперников нет → дефолт 1000 даёт множитель 1.0
                    actionSmuggleRet *= 0.7f + 0.3f * BluntMath.NormalizedClamp(
                        _closestOpponentDistance, 0.6f, 1.2f);                 // :2314
                }

                // assert(actionSmuggle_ret.coords[2] == 0.0f) (:2317) — держит check-скрипт
            }

            rotationSmuggleRet = rotationSmuggleTmp;                           // :2320

            return bestAnimID;                                                 // :2322
        }

        // ---- Контекст-обёртки touch-векторов (сбор аргументов C++-вызовов) ----
        // GetTrapVector(match, player, nextStartPos, nextStartAngle, nextBodyAngle,
        // CalculateOutgoingMovement(currentAnim->positions), currentAnim, currentAnim->frameNum,
        // spatialState, decayingPositionOffset, xRot, yRot) — humanoid.cpp:372/:430/:587.
        private Vector3 TrapVectorFromContext(float nextBodyAngle, out float xRot, out float yRot)
            => TouchVectors.GetTrapVector(_ball, _nextStartPos, _nextStartAngle, nextBodyAngle,
                CalculateOutgoingMovement(_current.Positions),
                _current.Anim.GetOutgoingVelocity(), _current.Anim.GetEffectiveFrameCount(),
                _current.FrameNum,
                _current.OriginatingCommand.DesiredDirection,
                _current.OriginatingCommand.DesiredVelocityFloat,
                _spatial.Angle, _spatial.DirectionVec, _spatial.BodyDirectionVec,
                HasPossession(), ControllerFloatVelocity(), MaxVelocity(),
                _closestOpponentDistance, _statMentalCalmness, _statPhysicalBalance,
                _statTechnicalDribble, _statTechnicalBallControl,
                _spatial.Movement, _spatial.Position, _decayingPositionOffset,
                OppLastTouchBias(1000 - (int)(_statPhysicalReaction * 500)), // humanoid_utils.cpp:187
                _statPhysicalReaction, _rng, out xRot, out yRot);

        // GetBallControlVector(ball, player, ..., xRot, yRot) без ffoOffset — humanoid.cpp:448.
        private Vector3 BallControlVectorFromContext(float nextBodyAngle,
            out float xRot, out float yRot)
            => TouchVectors.GetBallControlVector(_ball, _nextStartPos, _nextStartAngle,
                nextBodyAngle, CalculateOutgoingMovement(_current.Positions),
                _current.Anim.GetOutgoingVelocity(), _current.Anim.GetEffectiveFrameCount(),
                _current.FrameNum,
                _current.OriginatingCommand.DesiredDirection,
                _current.OriginatingCommand.DesiredVelocityFloat,
                _spatial.Angle, _spatial.DirectionVec, _spatial.BodyDirectionVec,
                HasPossession(), ControllerFloatVelocity(), MaxVelocity(),
                _closestOpponentDistance, _statMentalCalmness, _statPhysicalBalance,
                _statTechnicalDribble, _statTechnicalBallControl, _decayingPositionOffset,
                out xRot, out yRot, 0.0f); // ffoOffset — дефолт C++ (humanoid_utils.hpp:30)

        // ---- GetBestPossibleTouch (:2410-2486) ----
        // Модель ошибки паса: кламп к максимально возможной силе клипа, стат-скидки сложности,
        // случайный поворот/сползание к «родному» направлению клипа, надбавки высоты.
        internal Vector3 GetBestPossibleTouch(Vector3 desiredTouch, int functionType)
        {
            float maxPowerShortPass = 30.0f;                                   // :2412
            float maxPowerHighPass = 42.0f;                                    // :2413
            float maxPowerBase = maxPowerShortPass;                            // :2414
            if (functionType == AnimCollection.FnHighPass) maxPowerBase = maxPowerHighPass; // :2415

            Vector3 resultTouch = desiredTouch;                                // :2417

            // fetch vars (:2422-2426)
            float maxPowerFactor = BluntMath.AtoF(
                _current.Anim.GetVariable("touch_maxpowerfactor"));            // :2424
            if (maxPowerFactor == 0.0f) maxPowerFactor = 1.0f;                 // :2425
            maxPowerFactor = maxPowerFactor * 0.7f + 0.3f;                     // :2426

            // кламп к максимально возможной силе (:2429-2437)
            float maxPower = maxPowerBase * maxPowerFactor
                * (1.0f - Mathf.Clamp(_decayingPositionOffset.Length() * 2.5f, 0.0f, 0.25f)); // :2431
            maxPower += _ball.GetMovement().Length() * 0.5f; // :2432 — часть текущего момента мяча
            if (resultTouch.Length() > maxPower)                               // :2433
            {
                float missingPower = resultTouch.Length() - maxPower;          // :2434
                resultTouch = BluntMath.GetNormalized(resultTouch, Vector3.Zero) * maxPower; // :2435
                resultTouch.Z += Mathf.Clamp(missingPower, 0.0f, 10.0f) * 0.25f; // :2436
            }

            // сложность (:2440-2453)
            float difficultyFactor = BluntMath.AtoF(
                _current.Anim.GetVariable("touch_difficultyfactor"));          // :2442
            if (functionType == AnimCollection.FnShortPass ||
                functionType == AnimCollection.FnLongPass)
                difficultyFactor *= (1.0f - _statTechnicalShortPass * 0.5f);   // :2445-2446
            if (functionType == AnimCollection.FnHighPass)
                difficultyFactor *= (1.0f - _statTechnicalHighPass * 0.5f);    // :2447

            TouchVectors.GetDifficultyFactors(_ball, _spatial.Movement, _spatial.Position,
                _spatial.DirectionVec, _decayingPositionOffset.Length(), _statTechnicalBallControl,
                OppLastTouchBias(1000 - (int)(_statPhysicalReaction * 500)), _statPhysicalReaction,
                _rng, out float distanceFactor, out float heightFactor,
                out float ballMovementFactor);                                 // :2450-2453

            // трудные мячи уходят случайнее — либо сползают к дефолтному направлению клипа,
            // если оно есть (для клипа это самое лёгкое направление) (:2455-2468)
            float randomRotation = distanceFactor * 0.15f + heightFactor * 0.15f
                + ballMovementFactor * 0.3f + difficultyFactor * 0.5f;         // :2456-2457
            Vector3 animBallDirection = BluntMath.GetRotated2D(
                BluntMath.GetVectorFromString(_current.Anim.GetVariable("balldirection")),
                _startAngle + _current.RotationSmuggleOffset);                 // :2459
            if (animBallDirection.Length() > 0.01f)                            // :2460
            {
                float bias = Mathf.Clamp(randomRotation * 1.5f, 0.0f, 1.0f);   // :2461
                // :2462 — resultTouch * Vector3(0,0,1) оригинала == (0, 0, resultTouch.z)
                Vector3 nativeTouch = BluntMath.Get2D(
                    BluntMath.GetNormalized(animBallDirection, resultTouch)) * resultTouch.Length()
                    + new Vector3(0, 0, resultTouch.Z);
                resultTouch = resultTouch * (1.0f - bias) + nativeTouch * bias; // :2463
            }
            else
            {
                float rotation = _rng.Uniform(-0.5f * Mathf.Pi, 0.5f * Mathf.Pi)
                    * Mathf.Min(randomRotation, 0.5f);                         // :2465
                resultTouch = BluntMath.GetRotated2D(resultTouch, rotation);   // :2467
            }

            // мяч далеко == меньше силы (:2470-2472); компенсация высотой (меньше трения о газон)
            resultTouch *= 1.0f - distanceFactor * 0.3f;                       // :2471
            resultTouch.Z += distanceFactor * 1.5f;                            // :2472

            resultTouch.Z += _ball.GetMovement().Z * heightFactor * 0.5f
                + heightFactor * 1.0f;                                         // :2474-2475

            resultTouch = resultTouch * (1.0f - ballMovementFactor)
                + _ball.GetMovement() * ballMovementFactor;                    // :2477-2478

            resultTouch.Z += difficultyFactor * 5.0f * _rng.Uniform(0.2f, 1.0f); // :2480

            return resultTouch;                                                // :2485
        }

        // ---- Исполнение касания в тике (:342-646) ----
        // Вызывается из Tick (HumanoidBase.cs) после сброса interruptAnim (:336) и сторожа
        // «FLYING PLAYERS» (:338-340), перед action-смагглом (:668).
        private void ExecuteTouchTick()
        {
            // триггер контролируемой коллизии (:342-360)
            float ballDistanceNow =
                (BluntMath.Get2D(_ball.Predict(0)) - _spatial.Position).Length();      // :342
            float ballDistanceFuture = (BluntMath.Get2D(_ball.Predict(200))
                - (_spatial.Position + _spatial.Movement * 0.2f)).Length();            // :343
            float lastTouchBias = GetLastTouchBias(1500);                              // :344
            float oppLastTouchBias = OppLastTouchBias(240);                            // :345 (ШОВ)

            if (_designatedPossession &&                                               // :347 (ШОВ)
                (
                  (lastTouchBias <= 0.01f && oppLastTouchBias <= 0.01f &&
                   _current.FunctionType == AnimCollection.FnMovement &&
                   ballDistanceNow < 0.6f && ballDistanceFuture > 0.65f &&
                   ballDistanceFuture > ballDistanceNow)                               // :349-350
                  ||
                  // todo оригинала: only when triptype is 1 ? (:354)
                  (lastTouchBias <= 0.7f && HasPossession() &&
                   _current.FunctionType == AnimCollection.FnTrip && ballDistanceNow < 0.4f)
                ) && _ball.Predict(0).Z < 1.6f)                                        // :356
            {
                _controlledBallCollisionTriggered = true; // :358 TriggerControlledBallCollision
            }

            // контролируемая коллизия (:362-388, «EXPERIMENTAL» оригинала)
            bool controlledBallCollision = _controlledBallCollisionTriggered;          // :363
            if (controlledBallCollision) _controlledBallCollisionTriggered = false;    // :364
            if (EnableControlledBallCollisions && controlledBallCollision &&
                _current.TouchFrame == -1)                                             // :365
            {
                Vector3 currentBallVec = _ball.GetMovement();                          // :367
                float nextBodyAngle = _startAngle + _current.Anim.GetOutgoingAngle()
                    + _current.Anim.GetOutgoingBodyAngle() + _current.RotationSmuggleEnd; // :368

                Vector3 touchVec = TrapVectorFromContext(nextBodyAngle,
                    out float xRot, out float yRot);                                   // :370-372
                if ((_current.OriginatingCommand.Modifier & PlayerCommand.ModifierKnockOn) != 0)
                    touchVec *= 1.35f;                                                 // :373-375 (1.2 в комм.)

                float bumpyRideBias = 0.0f;                                            // :377
                touchVec = touchVec * (1.0f - bumpyRideBias) + currentBallVec * bumpyRideBias; // :378

                _ball.Touch(touchVec);                                                 // :381
                _ball.SetRotation(xRot, yRot, 0, 0.2f * (1.0f - bumpyRideBias));       // :382 (0.9 в комм.)
                // :383 TriggerBallTouchSound — звук не переносим

                RegisterTouch(TouchVectors.GetTouchTypeForBodyPart(
                    _current.Anim.GetVariable("touch_bodypart")));                     // :385
                // :386 UpdatePossessionStats — матч-слой
            }

            // touch-ветки по типам клипа (:390-646)
            if (_current.TouchFrame == _current.FrameNum)                              // :390
            {
                // позиция мяча клипа в кадр касания (:392-394)
                Vector3 desiredBallPosition =
                    GetAnimTouchPosAtFrame(_current.Anim, _current.TouchFrame);        // :393
                float desiredBallHeight = desiredBallPosition.Z;                       // :394

                float touchableDistance = 0.4f;                                        // :396

                float fullBallDistance = (_ball.Predict(0)
                    - (_current.TouchPos + _current.PositionOffset)).Length();         // :398

                // :400-409 verbose/debug — не переносим

                if (_current.Anim.GetVariable("incoming_retain_state") != "")          // :411
                {
                    fullBallDistance = 0.0f;                                           // :412
                    touchableDistance = 1.0f;                                          // :413
                }

                float bumpyRideBias = fullBallDistance / touchableDistance;            // :416
                bumpyRideBias = Mathf.Clamp(bumpyRideBias - 0.001f, 0.0f, 1.0f);       // :417
                bumpyRideBias = BluntMath.Curve(bumpyRideBias, 1.0f);                  // :418
                bumpyRideBias = BluntMath.Curve(bumpyRideBias, 0.5f);                  // :419
                Vector3 currentBallVec = _ball.GetMovement();                          // :420

                if (fullBallDistance < touchableDistance &&
                    Mathf.Abs(desiredBallHeight - _ball.Predict(0).Z) < 1.0f)          // :422
                {
                    float nextBodyAngle = _startAngle + _current.Anim.GetOutgoingAngle()
                        + _current.Anim.GetOutgoingBodyAngle() + _current.RotationSmuggleEnd; // :424

                    if (_current.FunctionType == AnimCollection.FnTrap ||
                        (_current.FunctionType == AnimCollection.FnBallControl &&
                         HasPossession() == false))                                    // :426
                    {
                        Vector3 touchVec = TrapVectorFromContext(nextBodyAngle,
                            out float xRot, out float yRot);                           // :430
                        if ((_current.OriginatingCommand.Modifier
                             & PlayerCommand.ModifierKnockOn) != 0)
                            touchVec *= 1.35f;                                         // :431-433

                        touchVec = touchVec * (1.0f - bumpyRideBias)
                            + currentBallVec * bumpyRideBias;                          // :435

                        _ball.Touch(touchVec);                                         // :438
                        _ball.SetRotation(xRot, yRot, 0, 0.5f * (1.0f - bumpyRideBias)); // :439

                        RegisterTouch(TouchVectors.GetTouchTypeForBodyPart(
                            _current.Anim.GetVariable("touch_bodypart")));             // :441
                        // :442 UpdatePossessionStats — матч-слой
                    }

                    else if (_current.FunctionType == AnimCollection.FnBallControl)    // :445
                    {
                        Vector3 touchVec = BallControlVectorFromContext(nextBodyAngle,
                            out float xRot, out float yRot);                           // :448
                        if ((_current.OriginatingCommand.Modifier
                             & PlayerCommand.ModifierKnockOn) != 0)
                            touchVec *= 1.35f;                                         // :449-451

                        touchVec = touchVec * (1.0f - bumpyRideBias)
                            + currentBallVec * bumpyRideBias;                          // :453

                        _ball.Touch(touchVec);                                         // :456
                        _ball.SetRotation(xRot, yRot, 0, 0.6f * (1.0f - bumpyRideBias)); // :457 (1.0 в комм.)

                        RegisterTouch(TouchVectors.GetTouchTypeForBodyPart(
                            _current.Anim.GetVariable("touch_bodypart")));             // :459
                        // :460 UpdatePossessionStats — матч-слой
                    }

                    else if (_current.FunctionType == AnimCollection.FnShortPass ||
                             _current.FunctionType == AnimCollection.FnLongPass ||
                             _current.FunctionType == AnimCollection.FnHighPass)       // :463-465
                    {
                        Vector3 ballDirection =
                            _current.OriginatingCommand.TouchInfo.DesiredDirection;    // :467
                        float ballPower = _current.OriginatingCommand.TouchInfo.DesiredPower; // :468
                        // :469-507 — ШОВ решения плана: AI_GetPass-рефайн цели/направления
                        // (:474-505) и targetPlayer/SelectPlayer (:469, :507) не портируются —
                        // AI-слой вне скоупа; ballDirection/ballPower берутся из
                        // originatingCommand.touchInfo как есть, targetPlayer == null.

                        float zcurve = 0.0f;                                           // :510
                        Vector3 touchVec = ballDirection * 36f * (ballPower + 0.3f);   // :511

                        if (PassFiddlingEnabled)                                       // :513 (:88-90)
                        {
                            touchVec = GetBestPossibleTouch(touchVec, _current.FunctionType); // :516

                            // немного кривизны для эстетики и реализма (:518-526)
                            float bodyTouchAngle = BluntMath.GetAngle2D(
                                _spatial.BodyDirectionVec, touchVec) / Mathf.Pi;       // :519
                            if (Mathf.Abs(bodyTouchAngle) > 0.5f)
                                bodyTouchAngle = (1.0f - Mathf.Abs(bodyTouchAngle))
                                    * BluntMath.SignSide(bodyTouchAngle);              // :520
                            bodyTouchAngle *= 2.0f;                                    // :521
                            float amount = bodyTouchAngle * 0.25f;                     // :523
                            if (_current.FunctionType == AnimCollection.FnHighPass)
                                amount *= 0.2f;                                        // :524
                            touchVec = BluntMath.GetRotated2D(touchVec, amount
                                * (0.4f + 0.6f * BluntMath.NormalizedClamp(
                                    touchVec.Length(), 0.0f, 70.0f)));                 // :525
                            zcurve = amount * -340f;                                   // :526 (-600 в комм.)
                        }

                        touchVec = touchVec * (1.0f - bumpyRideBias)
                            + currentBallVec * bumpyRideBias;                          // :531

                        _ball.Touch(touchVec);                                         // :534
                        // :535 TriggerBallTouchSound — звук не переносим

                        float forwardness = 3.5f;                                      // :537
                        if (_current.FunctionType == AnimCollection.FnHighPass)
                            forwardness = -1.3f;                                       // :538
                        float xRot = BluntMath.GetNormalized(touchVec, Vector3.Zero).Y
                            * (Mathf.Clamp(touchVec.Length(), 0f, 15f) * forwardness); // :539
                        float yRot = BluntMath.GetNormalized(touchVec, Vector3.Zero).X
                            * (Mathf.Clamp(touchVec.Length(), 0f, 15f) * forwardness); // :540
                        _ball.SetRotation(xRot, yRot, zcurve, 0.9f * (1.0f - bumpyRideBias)); // :541

                        RegisterTouch(TouchVectors.GetTouchTypeForBodyPart(
                            _current.Anim.GetVariable("touch_bodypart")));             // :543
                        // :544-545 UpdatePossessionStats своих/цели — матч-слой (цели нет — ШОВ выше)
                    }

                    else if (_current.FunctionType == AnimCollection.FnShot)           // :548
                    {
                        // :550-566 — ШОВ решения плана: AI_GetShotDirection-рефайн не портируется.
                        // КВИРК оригинала: локальный ballDirection после рефайна дальше НЕ
                        // используется — GetShotVector читает touchInfo.desiredDirection напрямую
                        // (:571), так что пропуск рефайна на вектор удара не влияет вовсе.
                        Vector3 touchVec = TouchVectors.GetShotVector(_ball,
                            _nextStartPos, _nextStartAngle, nextBodyAngle,
                            CalculateOutgoingMovement(_current.Positions),
                            _anims.GetPositionCacheInternal(_current.Id), _current.FrameNum,
                            _spatial.Angle, _spatial.DirectionVec, _spatial.BodyDirectionVec,
                            _current.OriginatingCommand.DesiredVelocityFloat,
                            _current.OriginatingCommand.TouchInfo.DesiredDirection,
                            _current.OriginatingCommand.TouchInfo.DesiredPower,
                            _decayingPositionOffset.Length(),
                            BluntMath.AtoF(_current.Anim.GetVariable("touch_maxpowerfactor")),
                            _statPhysicalShotPower, _statTechnicalVolley, _statTechnicalShot,
                            _rng, out float xRot, out float yRot, out float zRot,
                            _current.OriginatingCommand.TouchInfo.AutoDirectionBias);  // :568-571

                        touchVec = touchVec * (1.0f - bumpyRideBias)
                            + currentBallVec * bumpyRideBias;                          // :573

                        _ball.Touch(touchVec);                                         // :576
                        _ball.SetRotation(xRot, yRot, zRot, 0.7f * (1.0f - bumpyRideBias)); // :577
                        // :578 TriggerBallTouchSound — звук не переносим

                        RegisterTouch(TouchVectors.GetTouchTypeForBodyPart(
                            _current.Anim.GetVariable("touch_bodypart")));             // :580
                        // :581 MatchData::AddShot — матч-слой
                    }

                    else if (_current.FunctionType == AnimCollection.FnInterfere)      // :584
                    {
                        Vector3 touchVec = TrapVectorFromContext(nextBodyAngle,
                            out float xRot, out float yRot);                           // :587
                        touchVec = touchVec * 0.5f
                            + BluntMath.GetNormalized(
                                BluntMath.Get2D(_ball.Predict(0)) - _spatial.Position,
                                Vector3.Zero) * 4.0f
                            + new Vector3(0, 0, _rng.Uniform(0.5f, 1.5f));             // :588 (was 1..6)

                        touchVec = touchVec * (1.0f - bumpyRideBias)
                            + currentBallVec * bumpyRideBias;                          // :590

                        _ball.Touch(touchVec);                                         // :593
                        // :594 — КВИРК оригинала: SetRotation зовётся с ТРЕМЯ аргументами —
                        // 0.3·(1−bias) уходит в Z-ВРАЩЕНИЕ, а bias остаётся дефолтным 1.0
                        // (ball.hpp:64). Вероятно, задумывался bias — НЕ чиним.
                        _ball.SetRotation(xRot, yRot, 0.3f * (1.0f - bumpyRideBias), 1.0f);
                        // не совсем «случайное», но результирующее направление таково — вратари
                        // могут ловить такие мячи (комментарий оригинала :595)
                        RegisterTouch(TouchTypeAccidental);                            // :595
                    }

                    else if (_current.FunctionType == AnimCollection.FnDeflect)        // :598
                    {
                        bool canRetain = true; // :599 — сможем ли зафиксировать мяч?
                        if (_current.Anim.GetVariable("outgoing_retain_state") == "")
                            canRetain = false; // :600 — не тот клип, безнадёжно!
                        if (_isBallRetainer)
                            canRetain = false; // :601 ШОВ GetBallRetainer() != 0 (в лабе — только сам)
                        // ЛАБ-ПАРАМЕТР (решение плана): вратарский контур не в фазе 4
                        if (!_labAllowDeflectRetain) canRetain = false;

                        float veloDifficulty = BluntMath.NormalizedClamp(
                            (_ball.GetMovement() - _spatial.Movement).Length(), 0.0f, 40.0f); // :603
                        // :604-611 ШОВ lastTouchPlayer соперника (см. OppLastTouchBias):
                        // pow(0, 0.6) == 0 — совпадает с отсутствием lastTouchPlayer
                        float reactionDifficulty = Mathf.Pow(
                            OppLastTouchBias(1200 - (int)(_statPhysicalReaction * 400)), 0.6f);
                        if ((1.0f - veloDifficulty) * (1.0f - reactionDifficulty) < 0.3f)
                            canRetain = false;                                         // :612 — слишком трудно!

                        if (canRetain)                                                 // :615
                        {
                            _isBallRetainer = true; // :616 ШОВ match->SetBallRetainer(CastPlayer())
                        }
                        else
                        {
                            Vector3 currentBallMovement = BluntMath.Get2D(_ball.GetMovement()); // :618
                            Vector3 playerMovement = _spatial.Movement;                // :619
                            Vector3 touchVec = BluntMath.GetNormalized(
                                -currentBallMovement * 0.1f + playerMovement * 2.0f
                                + new Vector3(-_teamSide, 0, 0) * 4.0f
                                + new Vector3(0, _rng.Uniform(-1f, 1f), 0), Vector3.Zero)
                                * (currentBallMovement.Length() * 0.3f
                                   + playerMovement.Length() * 2.5f);                  // :620
                            touchVec.Z += 1.2f;                                        // :621

                            touchVec = touchVec * (1.0f - bumpyRideBias)
                                + currentBallVec * bumpyRideBias;                      // :623

                            _ball.Touch(touchVec);                                     // :626
                            _ball.SetRotation(0, 0, 0, 0.2f * (1.0f - bumpyRideBias)); // :627
                        }
                        RegisterTouch(TouchTypeAccidental);                            // :629
                    }

                    else if (_current.FunctionType == AnimCollection.FnSliding)        // :632
                    {
                        Vector3 touchVec = BluntMath.GetRotated2D(
                            BluntMath.GetVectorFromString(
                                _current.Anim.GetVariable("balldirection")),
                            _spatial.Angle);                                           // :633
                        touchVec = touchVec * 6.0f + _ball.GetMovement() * -0.28f;     // :634
                        touchVec += new Vector3(0, 0, 6);                              // :635

                        touchVec = touchVec * (1.0f - bumpyRideBias)
                            + currentBallVec * bumpyRideBias;                          // :637

                        _ball.Touch(touchVec);                                         // :640
                        // подкат мяч не подкручивает — SetRotation в ветке нет (:632-643)
                        RegisterTouch(TouchTypeAccidental);                            // :642
                    }
                }
            }

            // :648-665 superglue ретейнера (мяч «приклеен» к части тела retain-клипа) — ШОВ:
            // требует позиций узлов скелета (nodeMap), которых в ядре нет; вратарский контур —
            // вне фазы 4. Deflect-ветка может выставить ретейнера (в лабе выключено параметром),
            // но приклейка мяча к телу останется матч/сцен-слою.
        }

        // ---- Мосты для GDScript-тестов ----
        // Минимальная команда с дефолтами PlayerCommand (gamedefines.hpp:186-200) + тип функции.

        public Godot.Collections.Array BuildCrudeDataSetBridge(int functionTypeId)
        {
            var command = new PlayerCommand { DesiredFunctionType = functionTypeId };
            var result = new Godot.Collections.Array();
            foreach (int i in BuildCrudeDataSet(command)) result.Add(i);
            return result;
        }

        public Godot.Collections.Array BuildSortedDataSetBridge(int functionTypeId)
        {
            var command = new PlayerCommand { DesiredFunctionType = functionTypeId };
            var dataSet = BuildCrudeDataSet(command);
            var result = new Godot.Collections.Array();
            if (!SortDataSet(dataSet, command)) return result; // «too wrong» (:1535) — пустой ответ
            foreach (int i in dataSet) result.Add(i);
            return result;
        }

        public bool NeedTouchBridge(int animId, float desiredVelocityFloat)
        {
            var command = new PlayerCommand { DesiredVelocityFloat = desiredVelocityFloat };
            return NeedTouch(animId, command);
        }

        // Статический мост GetFrontOfFootOffsetRel (внутренний метод + обёртка).
        public static Vector3 GetFrontOfFootOffsetRelBridge(float velocity, float bodyAngleRel, float height)
            => GetFrontOfFootOffsetRel(velocity, bodyAngleRel, height);

        // Мост GetBestCheatableAnimID: собирает движенческую команду с типом действия (как
        // action-ветки SelectAnim, humanoid.cpp:1681-1698), строит sorted dataSet задачи 3 и
        // зовёт GetBestCheatableAnimID. desiredBodyDirectionRel — формула :1664-1665 без
        // desiredLookAt → (0, -1, 0). ref-параметры через мост не ходят — выходы в Dictionary.
        public Godot.Collections.Dictionary CheatableBridge(int functionTypeId,
            Vector3 desiredDirection, float desiredVelocityFloat)
        {
            var command = new PlayerCommand
            {
                DesiredFunctionType = functionTypeId,
                UseDesiredMovement = true,
                DesiredDirection = desiredDirection,
                DesiredVelocityFloat = desiredVelocityFloat,
            };
            var result = new Godot.Collections.Dictionary
            {
                { "id", -1 },
                { "touch_frame", -1 },
                { "touch_pos", Vector3.Zero },
                { "full_smuggle", Vector3.Zero },
                { "action_smuggle", Vector3.Zero },
                { "rotation_smuggle", 0f },
            };
            var dataSet = BuildCrudeDataSet(command);
            if (dataSet.Count == 0) return result;              // SelectAnim :1364
            if (!SortDataSet(dataSet, command)) return result;  // :1535 «too wrong»
            if (dataSet.Count == 0) return result;              // страховка: :2016 читает dataSet[0]

            Vector3 desiredBodyDirectionRel = new Vector3(0, -1, 0); // humanoid.cpp:1664 (без lookAt)

            var positionsTmp = new List<Vector3>();             // :1649
            int touchFrameTmp = -1;                             // :1650
            float radiusOffsetTmp = 0.0f;                       // :1651
            Vector3 touchPosTmp = Vector3.Zero;                 // :1652
            Vector3 fullActionSmuggleTmp = Vector3.Zero;        // :1653
            Vector3 actionSmuggleTmp = Vector3.Zero;            // :1654
            float rotationSmuggleTmp = 0f;                      // :1655

            // :1684 — hasteFactor = GetHasteFactor(false); localInterruptAnim в теле не
            // читается — передаём 0 (лаб-эквивалент), preferPassAndShot = false (дефолт).
            int selected = GetBestCheatableAnimID(dataSet, command.UseDesiredMovement,
                command.DesiredDirection, command.DesiredVelocityFloat, command.UseDesiredLookAt,
                desiredBodyDirectionRel, positionsTmp, ref touchFrameTmp, ref radiusOffsetTmp,
                ref touchPosTmp, ref fullActionSmuggleTmp, ref actionSmuggleTmp,
                ref rotationSmuggleTmp, GetHasteFactor(false), 0, false);

            result["id"] = selected;
            result["touch_frame"] = touchFrameTmp;
            result["touch_pos"] = touchPosTmp;
            result["full_smuggle"] = fullActionSmuggleTmp;
            result["action_smuggle"] = actionSmuggleTmp;
            result["rotation_smuggle"] = rotationSmuggleTmp;
            return result;
        }
    }
}

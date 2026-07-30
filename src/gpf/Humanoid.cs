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
    // НЕ портированы (по скоупу фазы): оптимизации-ранние-выходы SelectAnim (:1163-1189),
    // ветка e_InterruptAnim_ReQueue (:1191-1240 и quadrant-reject :1727-1742 — задача 6),
    // action-ветки Trap/Interfere/Deflect/пасов/удара/Sliding (:1687-1722 — задачи 7-8).
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
        // ReQueue-константы (:56-63) — потребитель придёт задачей 6, заведены по списку задачи 4
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

        // ШОВ team->GetDesignatedTeamPossessionPlayer() == player &&
        // match->GetDesignatedPossessionPlayer() == player (:2330): команд/матча в лабе нет —
        // одинокий игрок с мячом и есть «designated», дефолт true.
        private bool _designatedPossession = true;
        // ШОВ CastPlayer()->GetTimeNeededToGetToBall_ms() (:2340): считает AI (AIfunctions);
        // в лабе — сеттер, дефолт 0 («уже у мяча»).
        private int _timeNeededToGetToBallMs = 0;
        // ШОВ CastPlayer()->GetDesiredTimeToBall_ms() (:2341): задаёт тактика команды; дефолт 0.
        private int _desiredTimeToBallMs = 0;

        public void SetDesignatedPossession(bool designated) => _designatedPossession = designated;
        public void SetTimeNeededToGetToBall(int ms) => _timeNeededToGetToBallMs = ms;
        public void SetDesiredTimeToBall(int ms) => _desiredTimeToBallMs = ms;

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
        // ПО СКОУПУ ФАЗЫ не портированы: оптимизации-ранние-выходы (:1163-1189), ReQueue-гейты
        // (:1192-1234) и quadrant-reject (:1727-1742) — задача 6; ветки Trap/Interfere/Deflect
        // (:1687-1692), пасов/удара (:1693-1709) и Sliding (:1710-1722) — задачи 7-8 (лаб-очередь
        // команд таких типов не порождает).
        internal bool SelectAnim(PlayerCommand command, int localInterruptAnim, bool preferPassAndShot)
        {
            // :1160 assert(desiredDirection.z == 0) — не переносим

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
            // :1687-1722 Trap/Interfere/Deflect, пасы/удар, Sliding — задачи 7-8 (см. шапку метода)

            // :1727-1742 «не реквеить в тот же квадрант» — задача 6 (ReQueue)

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
                _current.OriginatingCommand = command;                         // :1784
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

            // гейты :2330-2332 дословно; швы: _designatedPossession (:2330),
            // match->GetBallRetainer() != 0 → _isBallRetainer (в лабе ретейнер — только сам)
            if (!_designatedPossession ||                                      // :2330
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
                    // |full| < 0.2 даёт ОТРИЦАТЕЛЬНУЮ дистанцию (смаггл разворачивается ОТ мяча) —
                    // подозрение на баг оригинала, НЕ чинить (global-constraints)
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

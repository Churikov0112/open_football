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
    // Здесь: GetHasteFactor (:1143-1157), голова SelectAnim — сборка CrudeSelectionQuery
    // (:1244-1365), хвост SelectAnim — KeepBest*-ветки по типам и сорт-цепочка (:1369-1637),
    // NeedTouch (:1822-1857), плюс _HighOrBouncyBall (humanoidbase.cpp:1089-1100) — он нужен
    // trap-ветке и до фазы 4 в порт не попадал.
    //
    // НЕ портированы в этой задаче (по скоупу фазы): оптимизации-ранние-выходы SelectAnim
    // (:1163-1187), вся ветка e_InterruptAnim_ReQueue (:1191-1240 — задача 6), цикл выбора
    // клипа с GetBestCheatableAnimID и «make it so» (:1657+ — задачи 4-5, 7).
    public partial class HumanoidBase
    {
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

        public void SetBall(Ball ball) => _ball = ball;
        public void SetRng(GpfRng rng) => _rng = rng;

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
    }
}

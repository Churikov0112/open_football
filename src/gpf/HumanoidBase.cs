using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // Порт контура состояния movement-пути HumanoidBase (humanoidbase.cpp): порядок тика Process
    // (:569-714, без ReQueue/Trip — в лабе только Switch на границе клипа), movement-ветка SelectAnim
    // (:1374-1601), CalculateOutgoingMovement (:1617-1620), CalculateSpatialState (:1622-1726),
    // CalculateFactualSpatialState (:1728-1737). Один тик = 10 мс = один кадр анимации.
    // ВАЖНО: игроки инстанцируются как Humanoid (player.cpp:88; голый HumanoidBase — судьи),
    // поэтому по НАСЛЕДНИКУ портированы ровно два места: лерп rotationSmuggleOffset с
    // 16-кадровым капом (humanoid.cpp:722-742) и «hax»-формула desiredBodyDirectionRel
    // (humanoid.cpp:1664-1665). ОТБОР клипов при этом — по базе humanoidbase.cpp:1374-1496
    // (AnimSelector, фаза 2), хотя Humanoid::SelectAnim переопределяет и его (ForceLinearity-флаги
    // :1396-1397 у наследника false; bySide при useDesiredLookAt humanoid.cpp:1306-1311;
    // двухнаборная lenient/strict цепочка :1386-1447) — расхождение с путём игроков
    // задокументировано в docs/wiki/открытые-вопросы.md (фаза 3, задача 6). Порядок тика и
    // startPos/startAngle наследника совпадают с базой (humanoid.cpp:120-138, :270-271).
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

        // humanoid.cpp:64 (false) — участвует только в мёртвой для movement ветке touchFrame != -1
        private static readonly bool AllowPreTouchRotationSmuggle = false;

        // Подмножество struct Anim (humanoidbase.hpp:85-112): только то, что нужно movement-пути.
        private class CurrentAnimState
        {
            public int Id = -1;
            public Animation Anim = null!;
            public int FrameNum;
            public int TouchFrame = -1; // humanoidbase.hpp:97; для movement всегда -1 (до фазы 4)
            public List<Vector3> Positions = new();
            public float RotationSmuggleBegin, RotationSmuggleEnd, RotationSmuggleOffset;
            public Vector3 IncomingMovement, OutgoingMovement;
            public Vector3 ActionSmuggleOffset, ActionSmuggleSustainOffset, MovementSmuggleOffset; // нули (фаза 4)
        }

        private AnimCollection _anims = null!;
        private AnimSelector _selector = null!;
        private readonly PhysicsVector _physics = new();
        private SpatialState _spatial = new();
        private Vector3 _startPos;           // humanoidbase.hpp:238 startPos
        private float _startAngle;           // humanoidbase.hpp:239 startAngle
        private Vector3 _previousPosition2D; // humanoidbase.hpp:263
        private readonly CurrentAnimState _current = new();
        // animApplyBuffer (humanoidbase.hpp:135-158) — подмножество movement-пути
        private int _applyFrameNum;
        private Vector3 _applyPosition;
        private float _applyOrientation;
        private bool _applyNoPos;

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
            _current.TouchFrame = -1;                       // :956
            _current.ActionSmuggleOffset = Vector3.Zero;        // :960
            _current.ActionSmuggleSustainOffset = Vector3.Zero; // :962
            _current.MovementSmuggleOffset = Vector3.Zero;      // :964
            _current.RotationSmuggleBegin = 0;              // :965
            _current.RotationSmuggleEnd = 0;                // :966
            _current.RotationSmuggleOffset = 0;             // :967
            _current.IncomingMovement = Vector3.Zero;       // :969
            _current.OutgoingMovement = Vector3.Zero;       // :970

            // apply-буфер стартового состояния (до первого Tick) — аналог :996-1004;
            // noPos = false — дефолт конструктора AnimApplyBuffer (humanoidbase.hpp:139),
            // ResetPosition его не трогает
            _applyFrameNum = 0;
            _applyPosition = position;
            _applyOrientation = angle;
            _applyNoPos = false;
        }

        // Один тик — порядок Process (humanoidbase.cpp:569-714; rotation smuggle — по наследнику
        // humanoid.cpp:722-742). Возвращает true при смене клипа.
        public bool Tick(Vector3 desiredDirectionWorld, float desiredVelocityFloat,
                         bool useDesiredLookAt, Vector3 desiredLookAt)
        {
            CalculateSpatialState();                        // :585
            _spatial.PositionOffsetMovement = Vector3.Zero; // :586
            _current.FrameNum++;                            // :588

            bool switched = false;
            // на границе клипа — Switch-прерывание и выбор следующего (:592-594, :615-637)
            if (_current.FrameNum == _current.Anim.GetFrameCount() - 1)
            {
                switched = SelectNextMovementAnim(desiredDirectionWorld, desiredVelocityFloat,
                                                  useDesiredLookAt, desiredLookAt);
                if (!switched)
                {
                    // «RED ALERT» (:639-645) в лабе недостижим: SelectMovementInternal сам
                    // подставляет idle-фолбэк (:1412-1417). Страховка от вылета на пустой
                    // коллекции: перезапустить текущий клип с нуля (отклонение от оригинала,
                    // где клип просто переигрывает границу).
                    GD.PushError("Gpf.HumanoidBase: не найден следующий клип — перезапуск текущего");
                    _current.FrameNum = 0;
                }
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
            if (_current.TouchFrame != -1) // :728 — мёртвая ветка для movement (touchFrame всегда -1)
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

            // apply-данные (:700-711; у наследника humanoid.cpp:763-780 та же логика, но ИНОЙ
            // порядок слагаемых позиции: startPos + positions + смагглы (:769) против базы
            // startPos + смагглы + positions (:703) — при нулевых смагглах численно одинаково,
            // при ненулевых разойдётся на ULP; выровнять по наследнику в фазе 4)
            _applyFrameNum = _current.FrameNum;                                // :700 / humanoid.cpp:765
            if (_current.Positions.Count > _current.FrameNum)                  // :702-705 / :767-772
            {
                _applyPosition = _startPos + _current.ActionSmuggleOffset
                    + _current.ActionSmuggleSustainOffset + _current.MovementSmuggleOffset
                    + _current.Positions[_current.FrameNum];                   // :703
                _applyOrientation = _startAngle + _current.RotationSmuggleOffset; // :704
                _applyNoPos = true;                                            // :705
            }
            else                                                               // :706-711 / :773-778
            {
                _applyPosition = _startPos + _current.ActionSmuggleOffset
                    + _current.ActionSmuggleSustainOffset + _current.MovementSmuggleOffset; // :708
                _applyOrientation = _startAngle;                               // :709
                _applyNoPos = false;                                           // :710
            }
            return switched;
        }

        // Movement-ветка SelectAnim (humanoidbase.cpp:1374-1601) + обновление startPos/startAngle
        // из Process (:648-649). Возвращает false, если клип не найден (:1510-1514).
        private bool SelectNextMovementAnim(Vector3 desiredDirectionWorld, float desiredVelocityFloat,
                                            bool useDesiredLookAt, Vector3 desiredLookAt)
        {
            // :1377 — при Switch условие «localInterruptAnim != ReQueue» всегда истинно
            CalculateFactualSpatialState();

            // запрос + сортировки (:1383-1496) — внутри селектора
            var dataSet = _selector.SelectMovementInternal(_spatial.Position, _spatial.Angle,
                _spatial.EnumVelocity, _spatial.FloatVelocity, _spatial.RelBodyDirectionVec,
                _spatial.Foot, desiredDirectionWorld, desiredVelocityFloat,
                useDesiredLookAt, desiredLookAt);
            if (dataSet.Count == 0) return false;                              // :1510-1514

            // desiredBodyDirectionRel — формула НАСЛЕДНИКА Humanoid::SelectAnim
            // (humanoid.cpp:1664-1665), НЕ базы (humanoidbase.cpp:1529-1530): игроки исполняют
            // Humanoid::SelectAnim. Отличия: упреждение движения на 0.1 с, нормализация ДО
            // GetRotated2D, БЕЗ вычета nextAnim.GetTranslation(); todo-«hax» оригинала переносим
            // bug-for-bug. Не зависит от выбранного клипа — считается до выбора, как в наследнике.
            Vector3 desiredBodyDirectionRel = new Vector3(0, -1, 0);           // humanoid.cpp:1664
            if (useDesiredLookAt)
                desiredBodyDirectionRel = BluntMath.GetRotated2D(
                    BluntMath.GetNormalized(
                        desiredLookAt - (_spatial.Position + _spatial.Movement * 0.1f),
                        new Vector3(0, -1, 0)),
                    -_spatial.Angle);                                          // humanoid.cpp:1665

            int selectedAnimID = dataSet[0];                                   // :1521 / humanoid.cpp:1671
            Animation nextAnim = _anims.GetAnim(selectedAnimID);               // :1522
            Vector3 desiredMovement = desiredDirectionWorld * desiredVelocityFloat; // :1523

            // CalculatePhysicsVector (:1531) — член в C++, у нас отдельный объект с тем же состоянием
            _physics.SetSpatialState(_spatial.Position, _spatial.Angle, _spatial.DirectionVec,
                _spatial.FloatVelocity, _spatial.Movement);
            var positionsTmp = new List<Vector3>();
            // Жёсткий `true` вместо `useDesiredMovement`: в оригинале это `command.useDesiredMovement`
            // (humanoid.cpp:1679) — true для movement-команд, false для action-команд (пас/удар/...),
            // которые задаёт `EliZaController` (elizacontroller.cpp:142,963). Movement-путь порта видит
            // только движение, поэтому здесь всегда true; в фазе 4 (когда появятся action-команды)
            // обязан стать параметром, а не константой.
            _physics.Calculate(nextAnim, _anims.GetPositionCacheInternal(selectedAnimID),
                true, desiredMovement, useDesiredLookAt, desiredBodyDirectionRel,
                positionsTmp, out float rotationSmuggleTmp);                   // :1531

            // make it so (:1558-1597; smuggle-поля кроме rotation — нули до фазы 4)
            _current.Anim = nextAnim;                                          // :1572
            _current.Id = selectedAnimID;                                      // :1573
            _current.FrameNum = 0;                                             // :1575
            _current.TouchFrame = -1;                                          // :1576 (touchFrame_tmp: movement не трогает, :1503)
            _current.RotationSmuggleBegin = Mathf.Clamp(
                BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi,
                    _spatial.RelBodyAngleNonquantized - nextAnim.GetIncomingBodyAngle())
                * BodyRotationSmoothingFactor,
                -BodyRotationSmoothingMaxAngle, BodyRotationSmoothingMaxAngle); // :1580
            _current.RotationSmuggleEnd = rotationSmuggleTmp;                  // :1581
            _current.RotationSmuggleOffset = 0;                                // :1582
            _current.ActionSmuggleOffset = Vector3.Zero;                       // :1585
            _current.ActionSmuggleSustainOffset = Vector3.Zero;                // :1587
            _current.MovementSmuggleOffset = Vector3.Zero;                     // :1589
            _current.IncomingMovement = _spatial.Movement;                     // :1590
            _current.OutgoingMovement = CalculateOutgoingMovement(positionsTmp); // :1591
            _current.Positions.Clear();                                        // :1592
            _current.Positions.AddRange(positionsTmp);                         // :1593

            _startPos = _spatial.Position;                                     // Process :648
            _startAngle = _spatial.Angle;                                      // Process :649
            return true;
        }

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

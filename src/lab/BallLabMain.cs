using Godot;
using System.Collections.Generic;

namespace Gpf.Lab
{
    // Лаб-сцена приёмки фазы 4: палочник + МЯЧ на настоящем ядре порта. Оркестратор одного тика
    // повторяет порядок Match::Process (match.cpp): контроллер собирает очередь команд
    // (HumanController::_GetCommands, humancontroller.cpp:23-330) → Humanoid::Process (тик
    // гуманоида, внутри — исполнение касания) → Match::CheckBallCollisions (:1926-2045) →
    // Ball::Process (ball.cpp:562-585) → отрисовка.
    // Смысл сцены — ГЛАЗНАЯ приёмка: непрерывность дриблинга, «нога у мяча» в кадр контакта,
    // пас/удар по направлению, правдоподобная физика мяча. Всё числовое — в HUD и в консоль.
    // walk_lab (фаза 3) не трогается: это отдельная сцена с тем же паттерном.
    public partial class BallLabMain : Node3D
    {
        // Сид ядра фиксирован: прогон сцены детерминирован и воспроизводим (печатается в HUD).
        private const ulong RngSeed = 20260731;

        // Радиус мяча 0.11 — хардкод оригинала по всему коду (не константа), тот же литерал,
        // что в Ball/BallBodyCollider.
        private const float BallRadius = 0.11f;

        private readonly Gpf.AnimationApplier _applier = new();
        private readonly Gpf.HumanoidBase _humanoid = new();
        private readonly Gpf.Ball _ball = new();
        private readonly Gpf.GpfRng _rng = new(RngSeed);
        private Gpf.AnimCollection _collection = null!;
        private Gpf.AnimSelector _selector = null!;
        private Skeleton3D _skeleton = null!;
        private Node3D _gpfSpace = null!;
        private Label _label = null!;
        private Camera3D _camera = null!;
        private MeshInstance3D _commandArrow = null!;
        private MeshInstance3D _ballMesh = null!;
        private MeshInstance3D _touchMarker = null!;

        // Кулдаун Match::lastBodyBallCollisionTime_ms (match.cpp:1931, :2041) — состояние матча,
        // не гуманоида: живёт у оркестратора.
        private long _lastBodyBallCollisionTimeMs = long.MinValue / 2;

        // команда («их» пространство: вперёд (0,-1,0))
        private Vector3 _desiredDirection = new Vector3(0, -1, 0);
        private int _desiredVelocityId = 1; // стартуем с дриблинга: мяч рядом

        // ---- буфер действия контроллера (humancontroller.cpp:97-197, :451-459) ----
        // actionMode: 0 — нет действия, 2 — заряжается/ждёт исполнения пас/удар.
        private int _actionMode;
        private int _actionButtonFunctionType = AnimCollection.FnNone; // ShortPass или Shot
        private int _gaugeMs;
        private int _actionBufferTimeMs;
        private bool _passHeldPrev;
        private bool _shotHeldPrev;

        // HUD/консоль приёмки
        private int _touches;
        private float _lastTouchBallDistance = -1f;
        private string _lastTouchWhat = "-";

        public override void _Ready()
        {
            Engine.PhysicsTicksPerSecond = 100; // дисциплина ядра (тик = 10 мс); с фазы 4 то же стоит
            // глобально в project.godot — здесь оставлено, чтобы лаба не зависела от настроек проекта

            var builder = new Gpf.SkeletonBuilder();
            _gpfSpace = builder.BuildAxisWrapper();
            AddChild(_gpfSpace);
            _skeleton = builder.BuildUtilitySkeleton();
            _gpfSpace.AddChild(_skeleton);
            var stickman = new StickmanRenderer();
            _gpfSpace.AddChild(stickman);
            stickman.Setup(_skeleton);

            SetupEnvironment();

            _collection = new Gpf.AnimCollection();
            ulong t0 = Time.GetTicksMsec();
            _collection.Load("res://assets/gpf/animations", _skeleton);
            GD.Print($"[BALL LAB] collection: {_collection.GetAnimationCount()} anims, "
                + $"{Time.GetTicksMsec() - t0} ms; rng seed {RngSeed}");
            _selector = new Gpf.AnimSelector();
            _selector.Setup(_collection);

            _humanoid.Setup(_collection, _selector);
            _humanoid.ResetSituation(Vector3.Zero, 0f); // idle-клип, кадр 0
            _ball.ResetSituation(new Vector3(0, -2f, 0)); // мяч перед игроком (их оси: −Y = вперёд)
            _ball.WoodworkEnabled = false;                // ворот в лабе нет
            _humanoid.SetBall(_ball);
            _humanoid.SetRng(_rng);
            // Единственный игрок лабы — он же designated possession player (в матче это
            // ближайший к мячу): даёт частый ReQueue (humanoid.cpp:165-169) и разрешает
            // контролируемые коллизии (:347).
            _humanoid.SetDesignatedPossession(true);
            // Мяч в игре, не стандарт, ретейнера нет (сорт-цепочка :1564-1566).
            _humanoid.SetMatchContext(true, false, false, false);
        }

        private void SetupEnvironment()
        {
            var floor = new MeshInstance3D
            {
                Mesh = new PlaneMesh { Size = new Vector2(200, 200) },
                MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.13f, 0.33f, 0.15f) },
            };
            AddChild(floor);
            var light = new DirectionalLight3D();
            light.RotationDegrees = new Vector3(-55, 30, 0);
            AddChild(light);
            _camera = new Camera3D();
            AddChild(_camera);

            _commandArrow = new MeshInstance3D
            {
                Mesh = new BoxMesh { Size = new Vector3(0.06f, 0.06f, 0.7f) },
                MaterialOverride = new StandardMaterial3D
                    { AlbedoColor = new Color(1f, 0.9f, 0.2f), ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded },
            };
            _gpfSpace.AddChild(_commandArrow);

            // Мяч: сфера радиуса 0.11 в «их» пространстве (позицию/ориентацию гонит ядро).
            _ballMesh = new MeshInstance3D
            {
                Mesh = new SphereMesh { Radius = BallRadius, Height = BallRadius * 2f, RadialSegments = 16, Rings = 8 },
                MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.95f, 0.95f, 0.95f) },
            };
            _gpfSpace.AddChild(_ballMesh);

            // Маркер touchPos выбранного тач-клипа: куда клип СОБИРАЕТСЯ поставить точку касания.
            // Гаснет, как только касание исполнено (touchFrame пройден).
            _touchMarker = new MeshInstance3D
            {
                Mesh = new SphereMesh { Radius = 0.05f, Height = 0.1f, RadialSegments = 10, Rings = 6 },
                MaterialOverride = new StandardMaterial3D
                    { AlbedoColor = new Color(1f, 0.95f, 0.1f), ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded },
                Visible = false,
            };
            _gpfSpace.AddChild(_touchMarker);

            var canvas = new CanvasLayer();
            AddChild(canvas);
            _label = new Label { Position = new Vector2(16, 12) };
            canvas.AddChild(_label);
        }

        // --- тестовый/входной API (как у ходунка: сцену можно шагать из GDScript) ---
        public void SetCommand(Vector3 desiredDirectionTheirSpace, int desiredVelocityId)
        {
            if (desiredDirectionTheirSpace.Length() > 0.01f)
                _desiredDirection = Gpf.BluntMath.GetNormalized(desiredDirectionTheirSpace, new Vector3(0, -1, 0));
            _desiredVelocityId = Mathf.Clamp(desiredVelocityId, 0, 3);
        }

        // Нажатие-и-отпускание кнопки действия без клавиатуры (headless-прогон, скрипты приёмки):
        // тот же буфер, что заполняют W/S, с уже набранным зарядом gaugeMs (10..1000 мс —
        // шкала humancontroller.cpp:453-454). functionType — FnShortPass или FnShot.
        public void RequestAction(int functionType, int gaugeMs)
        {
            if (_actionMode != 0) return;
            if (functionType != AnimCollection.FnShortPass && functionType != AnimCollection.FnShot) return;
            _actionMode = 2;
            _actionButtonFunctionType = functionType;
            _gaugeMs = Mathf.Clamp(gaugeMs, 10, 1000);
            _actionBufferTimeMs = 0;
        }

        public int GetCurrentAnimIndex() => _humanoid.GetCurrentAnimId();
        public Vector3 GetStatePosition() => _humanoid.GetSpatialPosition();
        public Vector3 GetBallPosition() => _ball.Predict(0);
        public int GetTouchCount() => _touches;

        // Один детерминированный шаг 10 мс: полный контур матча для одного игрока и мяча.
        public void StepOneFrame()
        {
            if (_humanoid.GetCurrentAnimId() < 0) return; // _Ready ещё не отработал

            List<Gpf.PlayerCommand> queue = BuildCommandQueue();

            _humanoid.Tick(queue);

            // Кадр касания (условие ExecuteTouchTick, humanoid.cpp:390 — на состоянии ПОСЛЕ
            // тика: и инкремент frameNum, и возможный перевыбор клипа уже случились).
            if (_humanoid.GetCurrentTouchFrame() >= 0
                && _humanoid.GetCurrentFrameNum() == _humanoid.GetCurrentTouchFrame())
            {
                // ball.Process() ещё не звали — Predict(0) держит позицию мяча кадра касания,
                // ровно ту, по которой ExecuteTouchTick считал fullBallDistance (:398).
                _lastTouchBallDistance =
                    (_ball.Predict(0) - _humanoid.GetCurrentTouchPos()).Length();
                _lastTouchWhat = FunctionTypeName(_humanoid.GetCurrentFunctionType());
                // touchableDistance = 0.4 (:396); высотный гейт (:422) здесь не повторяем —
                // печать диагностическая, решение принял сам тик.
                bool reached = _lastTouchBallDistance < 0.4f;
                if (reached) _touches++;
                GD.Print($"[BALL LAB] кадр касания ({_lastTouchWhat}): нога-мяч "
                    + $"{_lastTouchBallDistance:F3} м — {(reached ? $"дотянулись, касание #{_touches}" : "МИМО")} "
                    + "(порог 0.400 м, humanoid.cpp:396)");
            }

            // Межтельные коллизии мяча (Match::CheckBallCollisions, match.cpp:1926-2045) —
            // после тика игрока, до Ball::Process, как в Match::Process.
            CheckBallCollisions();

            _ball.Process();

            var anim = _collection.GetAnim(_humanoid.GetCurrentAnimId());
            // Применение ровно из apply-буфера тика (humanoid.cpp:763-780), как в walk_lab.
            _applier.Apply(_skeleton, anim, _humanoid.GetApplyFrameNum(), 0f,
                _humanoid.GetApplyNoPos(), _humanoid.GetApplyOrientation(), _humanoid.GetApplyPosition(),
                _humanoid.GetApplySmooth(), _humanoid.GetSmoothFactor(), 10);

            // Мяч в визуал: буферы ядра (в оригинале их разносит Ball::Put, ball.cpp:587-600).
            _ballMesh.Position = _ball.GetPositionBuffer();
            _ballMesh.Quaternion = _ball.GetOrientationBuffer();

            // Маркер точки касания жив, пока касание не исполнено (TouchPending, humanoid.hpp:29).
            bool pending = _humanoid.GetCurrentTouchFrame() >= 0
                && _humanoid.GetCurrentFrameNum() < _humanoid.GetCurrentTouchFrame();
            _touchMarker.Visible = pending;
            if (pending) _touchMarker.Position = _humanoid.GetCurrentTouchPos();
        }

        // Очередь команд лаб-контроллера. Порядок — HumanController::_GetCommands
        // (humancontroller.cpp:97-330): сначала пас/удар из буфера действия, потом ballcontrol,
        // движение — ПОСЛЕДНИМ (тик берёт первую применимую, humanoid.cpp:229-247).
        private List<Gpf.PlayerCommand> BuildCommandQueue()
        {
            var queue = new List<Gpf.PlayerCommand>();
            float desiredVelocityFloat = Gpf.Velo.EnumToFloatVelocity(_desiredVelocityId);
            Vector3 lookAt = _humanoid.GetSpatialPosition() + _desiredDirection * 10.0f;

            Gpf.PlayerCommand? action = BuildActionCommand();
            if (action != null) queue.Add(action);

            // BallControl (_BallControlCommand, playercontroller.cpp:277-320): в игре команда
            // ставится безусловно, «нужно ли вообще трогать мяч» решает NeedTouch внутри отбора.
            queue.Add(new Gpf.PlayerCommand
            {
                DesiredFunctionType = AnimCollection.FnBallControl,
                UseDesiredMovement = true,
                DesiredDirection = _desiredDirection,
                DesiredVelocityFloat = desiredVelocityFloat,
                UseDesiredLookAt = true,
                DesiredLookAt = lookAt,
            });
            queue.Add(new Gpf.PlayerCommand
            {
                DesiredFunctionType = AnimCollection.FnMovement,
                UseDesiredMovement = true,
                DesiredDirection = _desiredDirection,
                DesiredVelocityFloat = desiredVelocityFloat,
                UseDesiredLookAt = true,
                DesiredLookAt = lookAt,
            });
            return queue;
        }

        // Буфер действия: заряд по удержанию, исполнение по отпусканию (или на 500 мс заряда).
        // Порт humancontroller.cpp:41-49 (сброс буфера), :97-197 (исполнение), :428-459 (захват
        // кнопки и заряд). Кнопки лабы: W — короткий пас, S — удар (клавиатура: autoDirectionBias
        // = 1.0, :188). Возвращает команду или null.
        private Gpf.PlayerCommand? BuildActionCommand()
        {
            bool passHeld = Input.IsKeyPressed(Key.W);
            bool shotHeld = Input.IsKeyPressed(Key.S);

            // сброс буфера: действие уже исполняется клипом и касание позади (:41-49)
            int fn = _humanoid.GetCurrentFunctionType();
            if (_actionMode == 2
                && (fn == AnimCollection.FnShortPass || fn == AnimCollection.FnLongPass
                    || fn == AnimCollection.FnHighPass || fn == AnimCollection.FnShot)
                && !_humanoid.TouchPending())
            {
                ResetActionBuffer();
            }
            // отмена по переполнению буфера (:78-84, лаб-подмножество: только таймер)
            if (_actionMode == 2 && _actionBufferTimeMs > 2000) ResetActionBuffer();

            // захват кнопки по фронту (:428-443)
            if (_actionMode == 0)
            {
                if (passHeld && !_passHeldPrev)
                {
                    _actionMode = 2;
                    _actionButtonFunctionType = AnimCollection.FnShortPass;
                }
                else if (shotHeld && !_shotHeldPrev)
                {
                    _actionMode = 2;
                    _actionButtonFunctionType = AnimCollection.FnShot;
                }
            }
            _passHeldPrev = passHeld;
            _shotHeldPrev = shotHeld;

            if (_actionMode != 2) return null;

            bool buttonHeld = _actionButtonFunctionType == AnimCollection.FnShot ? shotHeld : passHeld;
            // заряд/ожидание (:451-459)
            if (buttonHeld)
            {
                _gaugeMs = Mathf.Clamp(_gaugeMs + 10, 10, 1000);
                _actionBufferTimeMs = 0;
            }
            else
            {
                _actionBufferTimeMs += 10;
            }

            // исполнять ли буфер сейчас (:99-101; ветка про сет-пис вырезана — стандартов нет)
            bool execute = !buttonHeld
                || _gaugeMs > 500
                || (!_humanoid.GetHasPossession() && _actionBufferTimeMs > 0);
            if (!execute) return null;

            int baseTimeMs = 60;                                              // :103
            float gaugeFactor = (_gaugeMs - baseTimeMs) * (1.0f / (1000 - baseTimeMs)); // :104
            gaugeFactor = Mathf.Clamp(gaugeFactor, 0.0f, 1.0f);               // :105

            var command = new Gpf.PlayerCommand
            {
                DesiredFunctionType = _actionButtonFunctionType,
                UseDesiredMovement = false,  // :133-134 / :184-185
                UseDesiredLookAt = false,
                UseTouchInfo = true,
            };
            command.TouchInfo.InputDirection = _desiredDirection;

            if (_actionButtonFunctionType == AnimCollection.FnShot)
            {
                // :186-190. desiredVelocityFloat — «спринт/дриблинг как модификатор удара» (:185).
                command.DesiredVelocityFloat = Gpf.Velo.EnumToFloatVelocity(_desiredVelocityId);
                command.TouchInfo.AutoDirectionBias = 1.0f;                   // :188 (клавиатура)
                // ШОВ AI_GetShotDirection (:189) — AI-слой вне скоупа фазы (тот же шов, что в
                // humanoid.cpp:550-566): направление берём как введено.
                command.TouchInfo.DesiredDirection = _desiredDirection;
                command.TouchInfo.DesiredPower =
                    Mathf.Clamp(Mathf.Pow(gaugeFactor, 0.6f), 0.01f, 1.0f);   // :190
            }
            else
            {
                float inputPower = Mathf.Clamp(Mathf.Pow(gaugeFactor, 0.7f), 0.01f, 1.0f); // :135
                command.TouchInfo.InputPower = inputPower;                    // :137
                // :138-139 autoDirection/autoPower из конфига — конфига нет; AI_GetPass (:140)
                // не портируется (ШОВ humanoid.cpp:469-507), поэтому desired* == input*.
                command.TouchInfo.DesiredDirection = _desiredDirection;
                command.TouchInfo.DesiredPower = inputPower;
            }
            return command;
        }

        private void ResetActionBuffer()
        {
            _actionMode = 0;
            _gaugeMs = 0;
            _actionBufferTimeMs = 0;
            _actionButtonFunctionType = AnimCollection.FnNone;
        }

        // Match::CheckBallCollisions для одного игрока: геометрия тела — сегменты костей
        // утилитарного скелета (их концы — глобальные позы, «их» пространство).
        private void CheckBallCollisions()
        {
            var segments = new List<Vector3>();
            for (int i = 0; i < _skeleton.GetBoneCount(); i++)
            {
                int parent = _skeleton.GetBoneParent(i);
                if (parent < 0) continue;
                segments.Add(_skeleton.GetBoneGlobalPose(parent).Origin);
                segments.Add(_skeleton.GetBoneGlobalPose(i).Origin);
            }

            // окна биасов — как их считает матч (:1948-1951, :1996); соперников в лабе нет,
            // поэтому командный биас соперника 0 (и тело коллизий, гейт :1953, не срабатывает —
            // это поведение оригинала, не дыра порта). unexpectedDistance = 0: задержки
            // восприятия (MentalImage) в лабе нет.
            bool touched = Gpf.BallBodyCollider.Check(_ball, segments,
                _humanoid.GetSpatialPosition(), _humanoid.GetSpatialMovement(),
                _humanoid.GetCurrentFunctionType(), _humanoid.GetHasPossession(),
                _humanoid.GetHasUniquePossession(), isDesignatedTeamPossessionPlayer: true,
                lastTouchBias: _humanoid.GetLastTouchBiasMs(200), oppLastTouchBias: 0f,
                oppLastTouchBiasLong: 0f, matchLastTouchBias: _humanoid.GetLastTouchBiasMs(200),
                unexpectedDistance: 0f, actualTimeMs: _humanoid.GetActualTimeMs(),
                ref _lastBodyBallCollisionTimeMs, _rng,
                out bool controlledCollision, out bool accidentalTouch);

            if (controlledCollision) _humanoid.TriggerControlledBallCollision(); // :1998
            if (accidentalTouch) _humanoid.RegisterAccidentalTouch();            // :2006
            if (touched)
            {
                _touches++;
                _lastTouchWhat = "body-collision";
                _lastTouchBallDistance = -1f;
                GD.Print($"[BALL LAB] коллизия тело-мяч (match.cpp:2037), touch #{_touches}");
            }
        }

        private static string FunctionTypeName(int functionType) => functionType switch
        {
            AnimCollection.FnMovement => "movement",
            AnimCollection.FnBallControl => "ballcontrol",
            AnimCollection.FnTrap => "trap",
            AnimCollection.FnShortPass => "shortpass",
            AnimCollection.FnLongPass => "longpass",
            AnimCollection.FnHighPass => "highpass",
            AnimCollection.FnShot => "shot",
            AnimCollection.FnInterfere => "interfere",
            AnimCollection.FnDeflect => "deflect",
            AnimCollection.FnSliding => "sliding",
            AnimCollection.FnTrip => "trip",
            _ => functionType.ToString(),
        };

        public override void _PhysicsProcess(double delta)
        {
            PollDirectionInput();
            StepOneFrame();
        }

        // Опрос зажатых стрелок — как в walk_lab (сумма векторов даёт диагонали).
        private void PollDirectionInput()
        {
            Vector3 dir = Vector3.Zero;
            if (Input.IsKeyPressed(Key.Up)) dir += new Vector3(0, -1, 0);
            if (Input.IsKeyPressed(Key.Down)) dir += new Vector3(0, 1, 0);
            if (Input.IsKeyPressed(Key.Left)) dir += new Vector3(1, 0, 0);
            if (Input.IsKeyPressed(Key.Right)) dir += new Vector3(-1, 0, 0);
            if (dir.Length() > 0.01f)
                _desiredDirection = Gpf.BluntMath.GetNormalized(dir, _desiredDirection);
        }

        public override void _Process(double delta)
        {
            int animId = _humanoid.GetCurrentAnimId();
            if (animId < 0) return;
            var anim = _collection.GetAnim(animId);
            Vector3 position = _humanoid.GetSpatialPosition();

            _commandArrow.Position = position + new Vector3(0, 0, 2.2f);
            _commandArrow.LookAt(_gpfSpace.ToGlobal(position + new Vector3(0, 0, 2.2f) + _desiredDirection), Vector3.Up);

            Vector3 camTargetTheirs = position + new Vector3(0, 0, 1f);
            Vector3 camTarget = _gpfSpace.ToGlobal(camTargetTheirs);
            _camera.Position = camTarget + new Vector3(0, 6f, 7f);
            _camera.LookAt(camTarget);

            string touchDist = _lastTouchBallDistance < 0f
                ? "-" : $"{_lastTouchBallDistance:F3} м";
            float footBallNow = (_ball.Predict(0) - _humanoid.GetSpatialPosition()).Length();

            _label.Text = $"{anim.GetName()}  [{FunctionTypeName(_humanoid.GetCurrentFunctionType())}]\n"
                + $"frame: {_humanoid.GetCurrentFrameNum()}/{anim.GetFrameCount()}   "
                + $"touchFrame: {_humanoid.GetCurrentTouchFrame()}\n"
                + $"|actionSmuggle|: {_humanoid.GetActionSmuggle().Length():F3}   "
                + $"|movementSmuggle|: {_humanoid.GetMovementSmuggle().Length():F3}\n"
                + $"игрок: v={_humanoid.GetSpatialFloatVelocity():F2} м/с "
                + $"angle={Mathf.RadToDeg(_humanoid.GetSpatialAngle()):F0}°   "
                + $"мяч: v={_ball.GetMovement().Length():F2} м/с z={_ball.Predict(0).Z:F2} м\n"
                + $"дистанция игрок-мяч: {footBallNow:F2} м   касаний: {_touches} "
                + $"(последнее: {_lastTouchWhat}, нога-мяч {touchDist})\n"
                + $"буфер действия: mode={_actionMode} gauge={_gaugeMs} мс   "
                + $"cmd: v={_desiredVelocityId} dir=({_desiredDirection.X:F1},{_desiredDirection.Y:F1})   "
                + $"rng seed: {RngSeed}\n"
                + "стрелки — направление;  0/1/2/3 — стойка/дриблинг/бег/спринт;  "
                + "W (держать) — пас,  S (держать) — удар;  R — сброс ситуации";
        }

        public override void _UnhandledKeyInput(InputEvent ev)
        {
            if (ev is not InputEventKey k || !k.Pressed || k.Echo) return;
            switch (k.Keycode)
            {
                case Key.Key0: SetCommand(_desiredDirection, 0); break;
                case Key.Key1: SetCommand(_desiredDirection, 1); break;
                case Key.Key2: SetCommand(_desiredDirection, 2); break;
                case Key.Key3: SetCommand(_desiredDirection, 3); break;
                case Key.R:
                    _humanoid.ResetSituation(Vector3.Zero, 0f);
                    _ball.ResetSituation(new Vector3(0, -2f, 0));
                    ResetActionBuffer();
                    _touches = 0;
                    _lastTouchBallDistance = -1f;
                    _lastTouchWhat = "-";
                    break;
            }
        }
    }
}

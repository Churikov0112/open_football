using Godot;
using System.Collections.Generic;

namespace Gpf.Lab
{
    // Лаб-сцена фазы 7: игрок и мяч ядра порта ВНУТРИ СТАДИОНА ОРИГИНАЛА. Первая сцена, после
    // которой возможна приёмка «глаза, бок о бок с эталон-exe»: до неё ядро жило на серой
    // плоскости, и сравнивать картинку было не с чем.
    //
    // Оркестратор — по образцу BallLabMain: порядок одного тика повторяет Match::Process
    // (match.cpp) — очередь команд контроллера → Humanoid::Process → Match::CheckBallCollisions
    // (:1926-2045) → previousBallPos (:881) → Ball::Process (ball.cpp:562-585) → CheckForGoal
    // (:970-975) → отрисовка. Здесь уже живут детект гола и жизненный цикл его флага (тикет 05),
    // щиты и солнце (09); по мере тикетов фазы приедут камера (07) и звук (08) — всё это
    // матч-собственность, которой нельзя течь в `Gpf.*` раньше фазы 8.
    //
    // ball_lab/walk_lab/anim_lab не трогаются: на ball_lab стоит оракул-режим, и любая правка
    // его оркестратора рискует нулевым диффом трасс. Отсюда сознательное дублирование очереди
    // команд вместо вынесения общего контроллера — вынести его можно будет фазой 8, когда
    // настоящий матч-слой заберёт эту логику целиком.
    public partial class StadiumLabMain : Node3D
    {
        // Геймплейный сид — тот же, что в ball_lab: прогон детерминирован и сравним.
        private const ulong RngSeed = 20260731;

        // ПРЕЗЕНТАЦИОННЫЙ ГСЧ — ВТОРОЙ, НЕЗАВИСИМЫЙ экземпляр (тикет
        // .scratch/oracle/issues/17-rng-potrebiteli-vne-geympleya.md). Из него кормится весь
        // презентационный код фазы: камера (2 числа на тик), звук (питч), солнце, бросок
        // ширины покоса, выбор адбордов. Геймплейный `_rng`, инжектированный в Humanoid и
        // TouchVectors, неприкосновенен — иначе нулевой дифф трасс умрёт без ошибки в логике.
        //
        // Сид — ОТ ВРЕМЕНИ, как у оригинала вне оракул-режима (main.cpp:295 → randomseed() от
        // std::time; там же fastrandomseed()). Иначе стадион и солнце были бы одинаковыми при
        // каждом запуске, а межматчевая вариация оригинала — часть приёмки фазы.
        // Печатается в консоль и в HUD: прогон при нужде воспроизводится подстановкой сида.

        // Радиус мяча 0.11 — хардкод оригинала по всему ball.cpp (не константа).
        private const float BallRadius = 0.11f;

        private const string StadiumGlb = "res://assets/models/gpf_stadium.glb";
        private const string PitchGlb = "res://assets/models/gpf_pitch.glb";
        private const string GoalsGlb = "res://assets/models/gpf_goals.glb";
        private const string BallGlb = "res://assets/models/gpf_ball.glb";

        private const string StadiumAse = "res://assets/gpf/media/objects/stadiums/test/test.ase";
        private const string PitchAse = "res://assets/gpf/media/objects/stadiums/test/pitch.ase";
        private const string GoalsAse = "res://assets/gpf/media/objects/stadiums/goals.ase";
        private const string BallAse = "res://assets/gpf/media/objects/balls/generic.ase";

        private readonly Gpf.AnimationApplier _applier = new();
        private readonly Gpf.HumanoidBase _humanoid = new();
        private readonly Gpf.Ball _ball = new();
        private readonly Gpf.GpfRng _rng = new(RngSeed);
        private readonly ulong _presentationSeed = (ulong)Time.GetUnixTimeFromSystem();
        private readonly Gpf.GpfRng _presentationRng = new(); // сидится в _Ready
        private readonly List<MeshInstance3D> _bodyParts = new();

        private Gpf.AnimCollection _collection = null!;
        private Gpf.AnimSelector _selector = null!;
        private Skeleton3D _skeleton = null!;
        private Node3D _gpfSpace = null!;
        private Node3D _ballNode = null!;
        private Camera3D _camera = null!;
        private Label _label = null!;
        private bool _flatShading;
        private int _missingModels;

        // Шов для тикетов 04/07/08/09: презентация берёт числа ОТСЮДА, не из геймплейного ГСЧ.
        public Gpf.GpfRng PresentationRng => _presentationRng;

        // Кулдаун Match::lastBodyBallCollisionTime_ms (match.cpp:1931, :2041) — состояние матча,
        // не гуманоида: живёт у оркестратора.
        private long _lastBodyBallCollisionTimeMs = long.MinValue / 2;

        // Флаг «мяч в воротах» и его жизненный цикл — тоже матч-собственность (выставление —
        // match.cpp:972-975, сброс — Match::ResetSituation / SetGoalScored(false)): живут здесь,
        // ядро только читает Ball.BallIsInGoal. Счёт, судья и IsInPlay в Gpf.* не заводятся —
        // это фаза 8.
        private bool _ballIsInGoal;
        private Vector3 _previousBallPos; // Match::previousBallPos (match.cpp:881)

        // Команда в «их» пространстве: вперёд (0,−1,0).
        private Vector3 _desiredDirection = new(0, -1, 0);
        private int _desiredVelocityId = 1;
        private float _desiredVelocityFloat = Gpf.Velo.Dribble;

        // Буфер действия контроллера (humancontroller.cpp:97-197, :451-459).
        private int _actionMode;
        private int _actionButtonFunctionType = AnimCollection.FnNone;
        private int _gaugeMs;
        private int _actionBufferTimeMs;
        private bool _passHeldPrev;
        private bool _shotHeldPrev;

        private int _touches;

        // Стартовая расстановка: центр поля, мяч перед игроком (их оси: −Y = вперёд).
        private static readonly Vector3 StartPosition = Vector3.Zero;
        private static readonly Vector3 StartBallPosition = new(0, -2f, 0);

        public override void _Ready()
        {
            Engine.PhysicsTicksPerSecond = 100; // дисциплина ядра: тик = 10 мс
            _presentationRng.Reseed(_presentationSeed);

            var builder = new Gpf.SkeletonBuilder();
            _gpfSpace = builder.BuildAxisWrapper();
            AddChild(_gpfSpace);

            LoadStadium();

            _skeleton = LabBody.Load(_gpfSpace, _bodyParts) ?? builder.BuildUtilitySkeleton();
            if (_skeleton.GetParent() == null) _gpfSpace.AddChild(_skeleton);

            SetupPresentation();

            _collection = new Gpf.AnimCollection();
            ulong t0 = Time.GetTicksMsec();
            _collection.Load("res://assets/gpf/animations", _skeleton);
            GD.Print($"[STADIUM LAB] collection: {_collection.GetAnimationCount()} anims, "
                + $"{Time.GetTicksMsec() - t0} ms; rng {RngSeed} / презентация {_presentationSeed}");
            _selector = new Gpf.AnimSelector();
            _selector.Setup(_collection);

            _humanoid.Setup(_collection, _selector);
            _humanoid.ResetSituation(StartPosition, 0f);
            _ball.ResetSituation(StartBallPosition);
            // В отличие от ball_lab ворота здесь есть: WoodworkEnabled остаётся включённым
            // (дефолт Gpf.Ball), сетка включается явно — её матч-вход Ball.BallIsInGoal кормит
            // CheckForGoals ниже.
            _ball.NettingEnabled = true;
            _previousBallPos = _ball.Predict(0);
            _humanoid.SetBall(_ball);
            _humanoid.SetRng(_rng);
            _humanoid.SetDesignatedPossession(true);
            _humanoid.SetMatchContext(true, false, false, false);
        }

        // Геометрия целиком под GpfSpace и в осях оригинала: `.glb` собраны с export_yup=False,
        // поэтому встают без доворотов (тикет 02, прецедент — LabBody).
        private void LoadStadium()
        {
            // Порядок обращений к презентационному ГСЧ повторяет конструкцию матча оригинала:
            // сначала щиты (RandomizeAdboards, match.cpp:182 — 23 броска), потом солнце
            // (SetRandomSunParams, :235 — 6 бросков).
            AddModel(StadiumGlb, StadiumAse, randomizeAdboards: true);
            AddModel(PitchGlb, PitchAse);
            AddModel(GoalsGlb, GoalsAse);
            _ballNode = AddModel(BallGlb, BallAse) ?? FallbackBallMesh();
        }

        private Node3D? AddModel(string glbPath, string asePath, bool randomizeAdboards = false)
        {
            if (!ResourceLoader.Exists(glbPath))
            {
                _missingModels++;
                GD.PushWarning($"StadiumLab: нет {glbPath} — собери tools/build_gpf_stadium.py "
                    + "и прогони импорт (--headless --import)");
                return null;
            }
            var node = GD.Load<PackedScene>(glbPath).Instantiate<Node3D>();
            _gpfSpace.AddChild(node);

            // Карты и скаляры читаются из того же `.ase`, что и в оригинале: `.glb` несёт
            // только геометрию и имена слотов. Подмена щитов вклинивается МЕЖДУ разбором и
            // назначением — у оригинала она тоже правит материалы, а не готовые меши.
            List<AseMaterials.Entry> entries = AseMaterials.Load(asePath);
            if (randomizeAdboards) MatchPresentation.RandomizeAdboards(entries, _presentationRng);
            AseMaterials.ApplyEntries(node, entries, asePath);
            return node;
        }

        // Мяч — единственная модель, без которой сцену смотреть нельзя вовсе.
        private Node3D FallbackBallMesh()
        {
            var mesh = new MeshInstance3D
            {
                Mesh = new SphereMesh
                {
                    Radius = BallRadius, Height = BallRadius * 2f, RadialSegments = 16, Rings = 8,
                },
                MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.95f, 0.95f, 0.95f) },
            };
            _gpfSpace.AddChild(mesh);
            return mesh;
        }

        // Солнце — по формулам оригинала; камера пока ВРЕМЕННАЯ (настоящую, UpdateIngameCamera
        // match.cpp:723, ставит тикет 07 — в тот же MatchPresentation).
        private void SetupPresentation()
        {
            // Под GpfSpace: SetRandomSunParams считает позицию в «их» осях.
            var sun = new DirectionalLight3D { Name = "Sun" };
            _gpfSpace.AddChild(sun);
            MatchPresentation.SetRandomSunParams(sun, _presentationRng);

            _camera = new Camera3D
            {
                // Окружение вешаем на камеру, а не узлом WorldEnvironment: узел не создаётся
                // в headless, и лаба тащила бы за собой лишнюю категорию ошибок.
                Environment = new Godot.Environment
                {
                    BackgroundMode = Godot.Environment.BGMode.Color,
                    BackgroundColor = new Color(0.45f, 0.55f, 0.7f),
                    AmbientLightSource = Godot.Environment.AmbientSource.Color,
                    AmbientLightColor = new Color(0.55f, 0.58f, 0.62f),
                    AmbientLightEnergy = 0.6f,
                },
            };
            AddChild(_camera);

            var canvas = new CanvasLayer();
            AddChild(canvas);
            _label = new Label { Position = new Vector2(16, 12) };
            canvas.AddChild(_label);
        }

        // --- вход для скриптов приёмки (тот же, что у ball_lab) ---
        public void SetCommand(Vector3 desiredDirectionTheirSpace, int desiredVelocityId)
        {
            if (desiredDirectionTheirSpace.Length() > 0.01f)
                _desiredDirection = Gpf.BluntMath.GetNormalized(desiredDirectionTheirSpace, new Vector3(0, -1, 0));
            _desiredVelocityId = Mathf.Clamp(desiredVelocityId, 0, 3);
            _desiredVelocityFloat = Gpf.Velo.EnumToFloatVelocity(_desiredVelocityId);
        }

        public Vector3 GetStatePosition() => _humanoid.GetSpatialPosition();
        public Vector3 GetBallPosition() => _ball.Predict(0);
        // Считаются ТОЛЬКО межтельные коллизии (match.cpp:2037), не касания тач-клипов:
        // ведение мяча идёт через них и этот счётчик не трогает.
        public int GetTouchCount() => _touches;

        // Один шаг 10 мс: контур матча для одного игрока и мяча.
        public void StepOneFrame()
        {
            if (_humanoid.GetCurrentAnimId() < 0) return;

            _humanoid.Tick(BuildCommandQueue());
            CheckBallCollisions();
            _previousBallPos = _ball.Predict(0); // match.cpp:881 — до Ball::Process
            _ball.Process();
            CheckForGoals(); // match.cpp:970-975 — после Ball::Process

            var anim = _collection.GetAnim(_humanoid.GetCurrentAnimId());
            _applier.Offsets = _humanoid.GetApplyOffsets();
            _applier.Apply(_skeleton, anim, _humanoid.GetApplyFrameNum(), 0f,
                _humanoid.GetApplyNoPos(), _humanoid.GetApplyOrientation(), _humanoid.GetApplyPosition(),
                _humanoid.GetApplySmooth(), _humanoid.GetSmoothFactor(), 10);

            _ballNode.Position = _ball.GetPositionBuffer();
            _ballNode.Quaternion = _ball.GetOrientationBuffer();
        }

        // Очередь команд лаб-контроллера — порядок HumanController::_GetCommands
        // (humancontroller.cpp:97-330): действие, ballcontrol, движение последним (тик берёт
        // первую применимую, humanoid.cpp:229-247).
        private List<Gpf.PlayerCommand> BuildCommandQueue()
        {
            var queue = new List<Gpf.PlayerCommand>();

            // lookAt из PlayerController::_MovementCommand (playercontroller.cpp:418-443, :600):
            // направление ввода доворачивается К МЯЧУ тем сильнее, чем медленнее игрок.
            const int defaultLookAtTimeMs = 40;
            Vector3 position = _humanoid.GetSpatialPosition();
            Vector3 manualDirection = _desiredDirection;
            float desiredVeloFactor = 1.0f - Mathf.Pow(Gpf.BluntMath.NormalizedClamp(
                Mathf.Min(_desiredVelocityFloat, _humanoid.GetSpatialFloatVelocity()),
                Gpf.Velo.IdleDribbleSwitch, Gpf.Velo.Sprint), 0.5f) * 0.3f;
            Vector3 focusPos = _ball.Predict(defaultLookAtTimeMs);
            focusPos.Z = 0.0f;                                       // Get2D
            focusPos += _humanoid.GetSpatialDirectionVec() * 0.5f;
            float toFocusAngle = Gpf.BluntMath.GetAngle2D(
                Gpf.BluntMath.GetNormalized(focusPos - position, manualDirection), manualDirection);
            Vector3 lookDirection = Gpf.BluntMath.GetRotated2D(manualDirection,
                toFocusAngle * Mathf.Pow(desiredVeloFactor, 0.7f));
            Vector3 lookAt = position + lookDirection * 10.0f;

            Gpf.PlayerCommand? action = BuildActionCommand();
            if (action != null) queue.Add(action);

            queue.Add(new Gpf.PlayerCommand
            {
                DesiredFunctionType = AnimCollection.FnBallControl,
                UseDesiredMovement = true,
                DesiredDirection = _desiredDirection,
                DesiredVelocityFloat = _desiredVelocityFloat,
                UseDesiredLookAt = true,
                DesiredLookAt = lookAt,
            });
            queue.Add(new Gpf.PlayerCommand
            {
                DesiredFunctionType = AnimCollection.FnMovement,
                UseDesiredMovement = true,
                DesiredDirection = _desiredDirection,
                DesiredVelocityFloat = _desiredVelocityFloat,
                UseDesiredLookAt = true,
                DesiredLookAt = lookAt,
            });
            return queue;
        }

        // Буфер действия: заряд по удержанию, исполнение по отпусканию. Порт
        // humancontroller.cpp:41-49 (сброс), :97-197 (исполнение), :428-459 (захват и заряд).
        // W — короткий пас, S — удар (клавиатура: autoDirectionBias = 1.0, :188).
        private Gpf.PlayerCommand? BuildActionCommand()
        {
            bool passHeld = Input.IsKeyPressed(Key.W);
            bool shotHeld = Input.IsKeyPressed(Key.S);

            int fn = _humanoid.GetCurrentFunctionType();
            if (_actionMode == 2
                && (fn == AnimCollection.FnShortPass || fn == AnimCollection.FnLongPass
                    || fn == AnimCollection.FnHighPass || fn == AnimCollection.FnShot)
                && !_humanoid.TouchPending())
            {
                ResetActionBuffer();
            }
            if (_actionMode == 2 && _actionBufferTimeMs > 2000) ResetActionBuffer();

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
            if (buttonHeld)
            {
                _gaugeMs = Mathf.Clamp(_gaugeMs + 10, 10, 1000);
                _actionBufferTimeMs = 0;
            }
            else
            {
                _actionBufferTimeMs += 10;
            }

            bool execute = !buttonHeld
                || _gaugeMs > 500
                || (!_humanoid.GetHasPossession() && _actionBufferTimeMs > 0);
            if (!execute) return null;

            int baseTimeMs = 60;                                                        // :103
            float gaugeFactor = (_gaugeMs - baseTimeMs) * (1.0f / (1000 - baseTimeMs)); // :104
            gaugeFactor = Mathf.Clamp(gaugeFactor, 0.0f, 1.0f);                         // :105

            var command = new Gpf.PlayerCommand
            {
                DesiredFunctionType = _actionButtonFunctionType,
                UseDesiredMovement = false,
                UseDesiredLookAt = false,
                UseTouchInfo = true,
            };
            command.TouchInfo.InputDirection = _desiredDirection;

            if (_actionButtonFunctionType == AnimCollection.FnShot)
            {
                command.DesiredVelocityFloat = _desiredVelocityFloat;                   // :185
                command.TouchInfo.AutoDirectionBias = 1.0f;                             // :188
                command.TouchInfo.DesiredDirection = _desiredDirection;
                command.TouchInfo.DesiredPower =
                    Mathf.Clamp(Mathf.Pow(gaugeFactor, 0.6f), 0.01f, 1.0f);             // :190
            }
            else
            {
                float inputPower = Mathf.Clamp(Mathf.Pow(gaugeFactor, 0.7f), 0.01f, 1.0f); // :135
                command.TouchInfo.InputPower = inputPower;                              // :137
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

        // Match::CheckBallCollisions для одного игрока (match.cpp:1926-2045).
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
            if (touched) _touches++;
        }

        // Проверка обеих сторон, как в Match::Process (:972-975, стороны команд −1 и 1);
        // флаг липкий до сброса — в матче его снимает kick-off (SetGoalScored(false)).
        private void CheckForGoals()
        {
            if (CheckForGoal(-1) || CheckForGoal(1)) _ballIsInGoal = true;
            _ball.BallIsInGoal = _ballIsInGoal;
        }

        // Match::CheckForGoal (match.cpp:1435-1466): Law 10 «весь мяч за линией» — плоскость
        // створа на pitchHalfW + lineHalfW + 0.11 (ширина линии + радиус мяча), пересечение
        // отрезка предыдущая→текущая позиция с двумя треугольниками створа. Габариты створа
        // 3.7/2.5 в оригинале захардкожены литералами — переносятся литералами.
        private bool CheckForGoal(int side)
        {
            if (Mathf.Abs(_ball.Predict(10).X) < Gpf.GpfPitch.PitchHalfW - 1.0f) return false; // :1436

            Vector3 l0 = _previousBallPos; // :1439
            Vector3 l1 = _ball.Predict(0); // :1440

            float x = (Gpf.GpfPitch.PitchHalfW + Gpf.GpfPitch.LineHalfW + 0.11f) * side;
            Vector3 normal = new Vector3(-side, 0, 0); // :1446, :1451

            bool intersect = TriangleIntersectsLine( // goal1 (:1442-1446), запрос :1457
                new Vector3(x, 3.7f, 0), new Vector3(x, -3.7f, 0), new Vector3(x, 3.7f, 2.5f),
                normal, l0, l1);
            if (!intersect)
                intersect = TriangleIntersectsLine( // goal2 (:1447-1451), запрос :1459
                    new Vector3(x, -3.7f, 0), new Vector3(x, -3.7f, 2.5f), new Vector3(x, 3.7f, 2.5f),
                    normal, l0, l1);

            // :1462-1463 — мяч мог «влететь» через боковую сетку: старт отрезка в поле, но за
            // штангой — не гол
            if (Mathf.Abs(_previousBallPos.Y) > 3.7f
                && Mathf.Abs(_previousBallPos.X) > Gpf.GpfPitch.PitchHalfW - Gpf.GpfPitch.LineHalfW - 0.11f)
                return false;

            return intersect; // :1465
        }

        // Triangle::IntersectsLine (triangle.cpp:320-369): пересечение отрезка l0→l1 с
        // треугольником. r строго внутри (0,1) — «hack to make edges look better» оригинала
        // (:341-343); обе ветки параллельности возвращают false (:333-337).
        private static bool TriangleIntersectsLine(Vector3 t0, Vector3 t1, Vector3 t2,
            Vector3 normal, Vector3 l0, Vector3 l1)
        {
            Vector3 u = t1 - t0;   // :326
            Vector3 v = t2 - t0;   // :327
            Vector3 dir = l1 - l0; // :329
            Vector3 w0 = l0 - t0;  // :330
            float a = -normal.Dot(w0); // :331
            float b = normal.Dot(dir); // :332
            if (Mathf.Abs(b) < 0.000001f) return false; // :333-337 — луч параллелен плоскости

            float r = a / b;                          // :340
            if (r <= 0.0f || r >= 1.0f) return false; // :343

            Vector3 intersect = l0 + dir * r; // :347

            float uu = u.Dot(u);              // :351
            float uv = u.Dot(v);              // :352
            float vv = v.Dot(v);              // :353
            Vector3 w = intersect - t0;       // :354
            float wu = w.Dot(u);              // :355
            float wv = w.Dot(v);              // :356
            float d = uv * uv - uu * vv;      // :357

            float s = (uv * wv - vv * wu) / d;         // :361
            if (s < 0.0f || s > 1.0f) return false;    // :362
            float t = (uv * wu - uu * wv) / d;         // :364
            if (t < 0.0f || (s + t) > 1.0f) return false; // :365
            return true; // :368
        }

        public override void _PhysicsProcess(double delta)
        {
            PollDirectionInput();
            StepOneFrame();
        }

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

            // ВРЕМЕННАЯ камера-догонялка (тикет 07 заменит её камерой матча оригинала).
            Vector3 camTarget = _gpfSpace.ToGlobal(position + new Vector3(0, 0, 1f));
            _camera.Position = camTarget + new Vector3(0, 6f, 12f);
            _camera.LookAt(camTarget);

            _label.Text = $"{anim.GetName()}\n"
                + $"игрок: ({position.X:F1}, {position.Y:F1}) v={_humanoid.GetSpatialFloatVelocity():F2} м/с\n"
                + $"мяч: ({_ball.Predict(0).X:F1}, {_ball.Predict(0).Y:F1}, {_ball.Predict(0).Z:F2}) "
                + $"v={_ball.GetMovement().Length():F2} м/с   коллизий тело-мяч: {_touches}\n"
                + $"rng: геймплей {RngSeed}, презентация {_presentationSeed}\n"
                + (_ballIsInGoal ? "ГОЛ — мяч в воротах (R — сброс)\n" : "")
                + (_missingModels > 0 ? $"!! нет {_missingModels} моделей стадиона\n" : "")
                + "стрелки — направление;  0/1/2/3 — стойка/дриблинг/бег/спринт;  "
                + "W — пас,  S — удар;  R — сброс"
                + LabBody.Hint(_bodyParts);
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
                    _humanoid.ResetSituation(StartPosition, 0f);
                    _ball.ResetSituation(StartBallPosition);
                    // Сброс флага «мяч в воротах» — зеркало Match::ResetSituation
                    // (match.cpp:660): в матче это делает kick-off после гола.
                    _ballIsInGoal = false;
                    _ball.BallIsInGoal = false;
                    _previousBallPos = _ball.Predict(0);
                    ResetActionBuffer();
                    _touches = 0;
                    break;
                case Key.M:
                    foreach (var part in _bodyParts) part.Visible = !part.Visible;
                    break;
                case Key.T:
                    _flatShading = !_flatShading;
                    LabBody.SetFlat(_bodyParts, _flatShading);
                    break;
            }
        }
    }
}

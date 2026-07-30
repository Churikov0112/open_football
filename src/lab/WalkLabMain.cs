using Godot;

namespace Gpf.Lab
{
    // Лаб-сцена: палочник бегает по командам (направление/скорость) на НАСТОЯЩЕЙ интеграции ядра —
    // Gpf.HumanoidBase (варпнутые траектории CalculatePhysicsVector + CalculateSpatialState,
    // humanoidbase.cpp:569-714, 1622-1737). Lite-интеграция фазы 2 (позиция/угол/скорость прямо из
    // дескрипторов клипа на его границе) удалена: состояние, выбор клипа и apply-буфер целиком
    // за HumanoidBase, лаба — только ввод, отрисовка и HUD.
    public partial class WalkLabMain : Node3D
    {
        private readonly Gpf.AnimationApplier _applier = new();
        private readonly Gpf.HumanoidBase _humanoid = new();
        private Gpf.AnimCollection _collection = null!;
        private Gpf.AnimSelector _selector = null!;
        private Skeleton3D _skeleton = null!;
        private Node3D _gpfSpace = null!;
        private Label _label = null!;
        private MeshInstance3D _commandArrow = null!;
        private Camera3D _camera = null!;

        // команда («их» пространство: вперёд (0,-1,0))
        private Vector3 _desiredDirection = new Vector3(0, -1, 0);
        private int _desiredVelocityId;

        // Пресеты статов для сравнения на глаз (клавиша A). Дефолт PhysicsVector — 0.6
        // (humanoidbase.cpp:2021-2024), с него и стартуем.
        private static readonly float[] StatsPresets = { 0.3f, 0.6f, 0.9f };
        private int _statsPresetIndex = 1;

        private int _transitions;

        public override void _Ready()
        {
            Engine.PhysicsTicksPerSecond = 100; // дисциплина ядра (тик = 10 мс), только в лабе

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
            GD.Print($"[WALK LAB] collection: {_collection.GetAnimationCount()} anims, {Time.GetTicksMsec() - t0} ms");
            _selector = new Gpf.AnimSelector();
            _selector.Setup(_collection);

            _humanoid.Setup(_collection, _selector);
            _humanoid.SetStatsPreset(StatsPresets[_statsPresetIndex]);
            _humanoid.ResetSituation(Vector3.Zero, 0f); // idle-клип, кадр 0
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

            var canvas = new CanvasLayer();
            AddChild(canvas);
            _label = new Label { Position = new Vector2(16, 12) };
            canvas.AddChild(_label);
        }

        // --- тестовый/входной API (сигнатуры фазы 2 сохранены, внутри — делегирование HumanoidBase) ---
        public void SetCommand(Vector3 desiredDirectionTheirSpace, int desiredVelocityId)
        {
            if (desiredDirectionTheirSpace.Length() > 0.01f)
                _desiredDirection = Gpf.BluntMath.GetNormalized(desiredDirectionTheirSpace, new Vector3(0, -1, 0));
            _desiredVelocityId = Mathf.Clamp(desiredVelocityId, 0, 3);
        }

        public int GetCurrentAnimIndex() => _humanoid.GetCurrentAnimId();
        public int GetTransitionCount() => _transitions;
        public int GetStateVelocityId() => _humanoid.GetSpatialEnumVelocity();
        public float GetStateFloatVelocity() => _humanoid.GetSpatialFloatVelocity();
        public float GetStateAngle() => _humanoid.GetSpatialAngle();
        public Vector3 GetStatePosition() => _humanoid.GetSpatialPosition();

        // Один детерминированный шаг 10 мс (== кадр клипа при 100 Гц).
        public void StepOneFrame()
        {
            if (_humanoid.GetCurrentAnimId() < 0) return; // _Ready ещё не отработал

            // desiredLookAt — точка в 10 м по команде, как GetBasicMovementCommand (player.cpp:1771).
            // wantBall = false: ходунку мяч не нужен; лаб-ввод «хочу мяч» появится с клавишами
            // задачи 8.
            bool switched = _humanoid.Tick(_desiredDirection,
                Gpf.Velo.EnumToFloatVelocity(_desiredVelocityId),
                false, true, _humanoid.GetSpatialPosition() + _desiredDirection * 10f);
            if (switched) _transitions++;

            var anim = _collection.GetAnim(_humanoid.GetCurrentAnimId());
            // Применение ровно из apply-буфера тика (humanoid.cpp:763-780), не из spatial:
            // позиция и доворот идут ЦЕЛИКОМ через basePos/baseRotZ, корень клипа при noPos
            // занулён по X/Y (animation.cpp:410-415) — иначе варп сложился бы с сырым корнем дважды.
            // smooth/smoothFactor — из apply-буфера (humanoid.cpp:276-284), timeDiff = 10 мс.
            _applier.Apply(_skeleton, anim, _humanoid.GetApplyFrameNum(), 0f,
                _humanoid.GetApplyNoPos(), _humanoid.GetApplyOrientation(), _humanoid.GetApplyPosition(),
                _humanoid.GetApplySmooth(), _humanoid.GetSmoothFactor(), 10);
        }

        public override void _PhysicsProcess(double delta)
        {
            PollDirectionInput();
            StepOneFrame();
        }

        // Опрос зажатых стрелок каждый физ-кадр: сумма векторов даёт диагонали (45°/135°),
        // недостижимые при дискретной обработке одной клавиши за событие. Оси «их» пространства:
        // вперёд (0,-1,0), «их-влево» (1,0,0) — базис GpfSpace зеркалит X, поэтому это и есть
        // экранный «влево» (а прежняя раскладка Left→(-1,0,0) уводила на экранправо — баг).
        // Если ничего не нажато — держим последнее направление (скорость меняется цифрами).
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

            // стрелка команды и камера — в «их» пространстве, конверсию делает GpfSpace
            _commandArrow.Position = position + new Vector3(0, 0, 2.2f);
            _commandArrow.LookAt(_gpfSpace.ToGlobal(position + new Vector3(0, 0, 2.2f) + _desiredDirection), Vector3.Up);

            Vector3 camTargetTheirs = position + new Vector3(0, 0, 1f);
            Vector3 camTarget = _gpfSpace.ToGlobal(camTargetTheirs);
            _camera.Position = camTarget + new Vector3(0, 6f, 7f);
            _camera.LookAt(camTarget);

            _label.Text = $"{anim.GetName()}\n"
                + $"quadrant: {anim.GetVariable("quadrant_id")}   frame: {_humanoid.GetApplyFrameNum()}/{anim.GetFrameCount()}\n"
                + $"state: v={_humanoid.GetSpatialEnumVelocity()} ({_humanoid.GetSpatialFloatVelocity():F2} м/с) "
                + $"angle={Mathf.RadToDeg(_humanoid.GetSpatialAngle()):F0}°   "
                + $"cmd: v={_desiredVelocityId} dir=({_desiredDirection.X:F1},{_desiredDirection.Y:F1})   "
                + $"stats: {StatsPresets[_statsPresetIndex]:F1}\n"
                + "стрелки (две сразу — диагональ 45°/135°) — направление;  "
                + "0/1/2/3 — стойка/дриблинг/бег/спринт (медленной ходьбы в датасете нет);  "
                + "A — пресет статов 0.3/0.6/0.9";
        }

        // Направление — опросом зажатых стрелок в PollDirectionInput (даёт диагонали).
        // Здесь дискретный выбор скорости 0/1/2/3 = стойка/дриблинг/бег/спринт и пресет статов.
        public override void _UnhandledKeyInput(InputEvent ev)
        {
            if (ev is not InputEventKey k || !k.Pressed || k.Echo) return;
            switch (k.Keycode)
            {
                case Key.Key0: SetCommand(_desiredDirection, 0); break;
                case Key.Key1: SetCommand(_desiredDirection, 1); break;
                case Key.Key2: SetCommand(_desiredDirection, 2); break;
                case Key.Key3: SetCommand(_desiredDirection, 3); break;
                case Key.A:
                    // статы влияют на разгон/поворот через CalculatePhysicsVector — смена на лету
                    _statsPresetIndex = (_statsPresetIndex + 1) % StatsPresets.Length;
                    _humanoid.SetStatsPreset(StatsPresets[_statsPresetIndex]);
                    break;
            }
        }
    }
}

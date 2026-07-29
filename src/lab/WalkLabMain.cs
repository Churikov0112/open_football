using Godot;

namespace Gpf.Lab
{
    // Лаб-сцена фазы 2: палочник бегает по командам (направление/скорость), клипы выбирает
    // AnimSelector. Интеграция состояния на смене клипа — УПРОЩЕНИЕ фазы 2 (lite), реальный
    // CalculateFactualSpatialState (humanoidbase.cpp:1650-1720) приедет с варпингом в фазе 3.
    public partial class WalkLabMain : Node3D
    {
        private readonly Gpf.AnimationApplier _applier = new();
        private Gpf.AnimCollection _collection = null!;
        private Gpf.AnimSelector _selector = null!;
        private Skeleton3D _skeleton = null!;
        private Node3D _gpfSpace = null!;
        private Label _label = null!;
        private MeshInstance3D _commandArrow = null!;
        private Camera3D _camera = null!;

        // spatial state lite («их» пространство)
        private Vector3 _position;
        private float _angle;
        private int _velocityId;
        private float _floatVelocity;
        private Vector3 _relBodyDir = new Vector3(0, -1, 0);
        private int _footId = 1;

        // команда
        private Vector3 _desiredDirection = new Vector3(0, -1, 0);
        private int _desiredVelocityId;

        private int _currentAnim = -1;
        private int _frame;
        private double _timeMs;
        private int _transitions;

        public override void _Ready()
        {
            Engine.PhysicsTicksPerSecond = 100; // дисциплина ядра, только в лабе

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

            _currentAnim = _collection.GetIdleMovementAnimID();
            _frame = 0;
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

        // --- тестовый/входной API ---
        public void SetCommand(Vector3 desiredDirectionTheirSpace, int desiredVelocityId)
        {
            if (desiredDirectionTheirSpace.Length() > 0.01f)
                _desiredDirection = Gpf.BluntMath.GetNormalized(desiredDirectionTheirSpace, new Vector3(0, -1, 0));
            _desiredVelocityId = Mathf.Clamp(desiredVelocityId, 0, 3);
        }

        public int GetCurrentAnimIndex() => _currentAnim;
        public int GetTransitionCount() => _transitions;
        public int GetStateVelocityId() => _velocityId;
        public float GetStateAngle() => _angle;
        public Vector3 GetStatePosition() => _position;

        // Один детерминированный шаг 10 мс (== кадр клипа при 100 Гц).
        public void StepOneFrame()
        {
            if (_currentAnim < 0) return;
            var anim = _collection.GetAnim(_currentAnim);

            _applier.Apply(_skeleton, anim, _frame, 0f, false, _angle, _position);
            _frame++;

            if (_frame >= anim.GetFrameCount() - 1)
                AdvanceToNextAnim(anim);
        }

        private void AdvanceToNextAnim(Gpf.Animation finished)
        {
            // интеграция lite (см. шапку класса)
            _position += Gpf.BluntMath.GetRotated2D(finished.GetTranslation(), _angle);
            _angle = Gpf.BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi, _angle + finished.GetOutgoingAngle());
            _velocityId = Gpf.Velo.FloatToEnumVelocity(finished.GetOutgoingVelocity());
            _floatVelocity = Gpf.Velo.RangeVelocity(finished.GetOutgoingVelocity());
            _relBodyDir = _selector.ForceIntoAllowedBodyDirectionVec(
                Gpf.BluntMath.GetRotated2D(new Vector3(0, -1, 0), finished.GetOutgoingBodyAngle()));
            _footId = finished.GetOutgoingFootId();

            int next = _selector.SelectMovementAnim(
                _position, _angle, _velocityId, _floatVelocity, _relBodyDir, _footId,
                _desiredDirection, Gpf.Velo.EnumToFloatVelocity(_desiredVelocityId),
                true, _position + _desiredDirection * 10f);
            _currentAnim = next >= 0 ? next : _collection.GetIdleMovementAnimID();
            _frame = 0;
            _transitions++;
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
            if (_currentAnim < 0) return;
            var anim = _collection.GetAnim(_currentAnim);

            // стрелка команды и камера — в «их» пространстве, конверсию делает GpfSpace
            _commandArrow.Position = _position + new Vector3(0, 0, 2.2f);
            _commandArrow.LookAt(_gpfSpace.ToGlobal(_position + new Vector3(0, 0, 2.2f) + _desiredDirection), Vector3.Up);

            Vector3 camTargetTheirs = _position + new Vector3(0, 0, 1f);
            Vector3 camTarget = _gpfSpace.ToGlobal(camTargetTheirs);
            _camera.Position = camTarget + new Vector3(0, 6f, 7f);
            _camera.LookAt(camTarget);

            _label.Text = $"{anim.GetName()}\n"
                + $"quadrant: {anim.GetVariable("quadrant_id")}   frame: {_frame}/{anim.GetFrameCount()}\n"
                + $"state: v={_velocityId} angle={Mathf.RadToDeg(_angle):F0}°   "
                + $"cmd: v={_desiredVelocityId} dir=({_desiredDirection.X:F1},{_desiredDirection.Y:F1})\n"
                + "стрелки (две сразу — диагональ 45°/135°) — направление;  "
                + "0/1/2/3 — стойка/дриблинг/бег/спринт (медленной ходьбы в датасете нет)";
        }

        // Направление — опросом зажатых стрелок в PollDirectionInput (даёт диагонали).
        // Здесь только дискретный выбор скорости: 0/1/2/3 = стойка/дриблинг/бег/спринт.
        public override void _UnhandledKeyInput(InputEvent ev)
        {
            if (ev is not InputEventKey k || !k.Pressed || k.Echo) return;
            switch (k.Keycode)
            {
                case Key.Key0: SetCommand(_desiredDirection, 0); break;
                case Key.Key1: SetCommand(_desiredDirection, 1); break;
                case Key.Key2: SetCommand(_desiredDirection, 2); break;
                case Key.Key3: SetCommand(_desiredDirection, 3); break;
            }
        }
    }
}

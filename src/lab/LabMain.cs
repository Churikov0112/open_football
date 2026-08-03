using Godot;
using System.Collections.Generic;

namespace Gpf.Lab
{
    // Лаб-сцена фазы 1 порта GameplayFootball: палочник + плеер .anim-клипов.
    // ←/→ — смена клипа, Space — пауза, R — с начала. Главная сцена проекта не затронута.
    public partial class LabMain : Node3D
    {
        private readonly List<string> _clipPaths = new();
        private readonly Gpf.AnimationApplier _applier = new();
        private readonly List<MeshInstance3D> _touchMarkers = new();
        private Gpf.Animation? _anim;
        private int _clipIndex;
        private Skeleton3D _skeleton = null!;
        private Node3D _gpfSpace = null!;
        private Label _label = null!;
        private double _timeMs;
        private bool _paused;

        public override void _Ready()
        {
            // Дисциплина ядра — фикс-тик 100 Гц. С фазы 4 то же значение стоит глобально в
            // project.godot (включая матч); здесь оставлено ради независимости лабы от настроек.
            Engine.PhysicsTicksPerSecond = 100;

            var builder = new Gpf.SkeletonBuilder();
            _gpfSpace = builder.BuildAxisWrapper();
            AddChild(_gpfSpace);
            _skeleton = builder.BuildUtilitySkeleton();
            _gpfSpace.AddChild(_skeleton);
            var stickman = new StickmanRenderer();
            _gpfSpace.AddChild(stickman);
            stickman.Setup(_skeleton);

            SetupEnvironment();
            SetupUi();

            ScanClips("res://assets/gpf/animations");
            _clipPaths.Sort();
            GD.Print($"[LAB] clips: {_clipPaths.Count}");
            if (_clipPaths.Count > 0) LoadClip(0);
        }

        private void SetupEnvironment()
        {
            var floor = new MeshInstance3D
            {
                Mesh = new PlaneMesh { Size = new Vector2(20, 20) },
                MaterialOverride = new StandardMaterial3D
                    { AlbedoColor = new Color(0.13f, 0.33f, 0.15f) },
            };
            AddChild(floor);

            var light = new DirectionalLight3D();
            light.RotationDegrees = new Vector3(-55, 30, 0);
            AddChild(light);

            var cam = new Camera3D { Position = new Vector3(2.5f, 1.7f, 3.0f) };
            AddChild(cam);
            cam.LookAt(new Vector3(0, 1, 0));
        }

        private void SetupUi()
        {
            var canvas = new CanvasLayer();
            AddChild(canvas);
            _label = new Label { Position = new Vector2(16, 12) };
            canvas.AddChild(_label);
        }

        private void ScanClips(string dir)
        {
            using var d = DirAccess.Open(dir);
            if (d == null) return;
            d.ListDirBegin();
            for (string f = d.GetNext(); f != ""; f = d.GetNext())
            {
                string path = dir + "/" + f;
                if (d.CurrentIsDir()) { if (!f.StartsWith(".")) ScanClips(path); }
                else if (f.EndsWith(".anim")) _clipPaths.Add(path);
            }
            d.ListDirEnd();
        }

        private void LoadClip(int index)
        {
            if (_clipPaths.Count == 0) return;
            int n = _clipPaths.Count;
            _clipIndex = ((index % n) + n) % n;
            _anim = new Gpf.Animation();
            _anim.LoadFromFile(_clipPaths[_clipIndex]);
            _timeMs = 0;

            foreach (var m in _touchMarkers) m.QueueFree();
            _touchMarkers.Clear();
            for (int i = 0; i < _anim.GetTouchCount(); i++)
            {
                var marker = new MeshInstance3D
                {
                    Mesh = new SphereMesh { Radius = 0.11f, Height = 0.22f },
                    Position = _anim.GetTouchPosition(i), // клип-пространство == GpfSpace
                    MaterialOverride = new StandardMaterial3D
                    {
                        AlbedoColor = new Color(1f, 0.6f, 0.1f, 0.5f),
                        Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
                        ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
                    },
                };
                _gpfSpace.AddChild(marker);
                _touchMarkers.Add(marker);
            }
        }

        public override void _Process(double delta)
        {
            if (_anim == null || _anim.GetFrameCount() == 0) return;
            if (!_paused)
            {
                _timeMs += delta * 1000.0;
                double lengthMs = _anim.GetFrameCount() * 10.0;
                if (_timeMs >= lengthMs) _timeMs -= lengthMs; // цикл
            }
            int frame = (int)(_timeMs / 10.0);
            float offset = (float)(_timeMs - frame * 10.0);
            _applier.Apply(_skeleton, _anim, frame, offset);

            string touches = "";
            for (int i = 0; i < _anim.GetTouchCount(); i++)
                touches += $" @{_anim.GetTouchFrame(i)}";
            _label.Text = $"{_anim.GetName()}  [{_clipIndex + 1}/{_clipPaths.Count}]\n"
                + $"type: {_anim.GetAnimType()}   frames: {_anim.GetFrameCount()}   frame: {frame}"
                + (touches == "" ? "" : $"   touches:{touches}") + "\n"
                + "←/→ клип   Space пауза   R сначала";
        }

        public override void _UnhandledKeyInput(InputEvent ev)
        {
            if (ev is not InputEventKey k || !k.Pressed || k.Echo) return;
            switch (k.Keycode)
            {
                case Key.Right: LoadClip(_clipIndex + 1); break;
                case Key.Left: LoadClip(_clipIndex - 1); break;
                case Key.Space: _paused = !_paused; break;
                case Key.R: _timeMs = 0; break;
            }
        }
    }
}

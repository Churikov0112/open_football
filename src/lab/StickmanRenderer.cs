using Godot;

namespace Gpf.Lab
{
    // Палочник: линии костей по глобальным позам Skeleton3D. Работает в координатах
    // скелета («их» пространство) — обязан быть братом скелета под GpfSpace с identity-трансформом.
    // Левая сторона красная, правая синяя — контроль зеркала при приёмке.
    public partial class StickmanRenderer : MeshInstance3D
    {
        // Ступни у 14-костного утилитарного скелета НЕТ: кость кончается голеностопом, а касание в
        // данных клипа объявлено впереди-ниже него. Замер по .anim (ballcontrol/walk|sprint/000,
        // walk/045): точка касания лежит в локальном базисе косточки по −Y на 0.13–0.20 м, X и Z ≈ 0.
        // Поэтому рисуем отрезок голеностоп → носок вдоль локального −Y — иначе на приёмке нога
        // визуально «не достаёт» до мяча на длину ступни, и это читается как баг доводки, которым не
        // является. Чисто презентация: ядро порта про ступни не знает (см. вики, «Что НЕ портировано»).
        private const float FootLength = 0.18f;

        private Skeleton3D? _skeleton;
        private ImmediateMesh _mesh = null!;

        public void Setup(Skeleton3D skeleton)
        {
            _skeleton = skeleton;
            _mesh = new ImmediateMesh();
            Mesh = _mesh;
            MaterialOverride = new StandardMaterial3D
            {
                ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
                VertexColorUseAsAlbedo = true,
            };
        }

        public override void _Process(double delta)
        {
            if (_skeleton == null) return;
            _mesh.ClearSurfaces();
            _mesh.SurfaceBegin(Mesh.PrimitiveType.Lines);
            for (int i = 0; i < _skeleton.GetBoneCount(); i++)
            {
                int parent = _skeleton.GetBoneParent(i);
                if (parent < 0) continue;
                string name = _skeleton.GetBoneName(i);
                _mesh.SurfaceSetColor(BoneColor(name));
                Transform3D pose = _skeleton.GetBoneGlobalPose(i);
                _mesh.SurfaceAddVertex(_skeleton.GetBoneGlobalPose(parent).Origin);
                _mesh.SurfaceAddVertex(pose.Origin);

                if (name.EndsWith("_ankle"))   // ступня: голеностоп → носок (см. FootLength)
                {
                    _mesh.SurfaceAddVertex(pose.Origin);
                    _mesh.SurfaceAddVertex(pose * new Vector3(0f, -FootLength, 0f));
                }
            }
            _mesh.SurfaceEnd();
        }

        private static Color BoneColor(string bone)
        {
            if (bone.StartsWith("left_")) return new Color(1f, 0.25f, 0.25f);
            if (bone.StartsWith("right_")) return new Color(0.3f, 0.5f, 1f);
            return Colors.White;
        }
    }
}

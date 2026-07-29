using Godot;

namespace Gpf.Lab
{
    // Палочник: линии костей по глобальным позам Skeleton3D. Работает в координатах
    // скелета («их» пространство) — обязан быть братом скелета под GpfSpace с identity-трансформом.
    // Левая сторона красная, правая синяя — контроль зеркала при приёмке.
    public partial class StickmanRenderer : MeshInstance3D
    {
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
                _mesh.SurfaceSetColor(BoneColor(_skeleton.GetBoneName(i)));
                _mesh.SurfaceAddVertex(_skeleton.GetBoneGlobalPose(parent).Origin);
                _mesh.SurfaceAddVertex(_skeleton.GetBoneGlobalPose(i).Origin);
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

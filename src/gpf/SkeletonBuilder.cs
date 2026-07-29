using Godot;

namespace Gpf
{
    // Утилитарный скелет 1:1 data/media/objects/players/player.object (позиции — дословно).
    // Скелет живёт в «их» пространстве (Z-вверх, вперёд −Y); конверсия осей — базис
    // родителя-обёртки GpfSpace, кости не трогаем. Рест-повороты .object игнорируются:
    // клип пишет джойнтам абсолютную локальную ориентацию.
    public partial class SkeletonBuilder : RefCounted
    {
        private static readonly (string Name, string Parent, Vector3 Pos)[] Bones =
        {
            ("player",         "",               new Vector3(0, 0, 0)),
            ("body",           "player",         new Vector3(0, 0, 0.96f)),
            ("middle",         "body",           new Vector3(0, 0, 0.15f)),
            ("neck",           "middle",         new Vector3(0, -0.03f, 0.5f)),
            ("left_shoulder",  "middle",         new Vector3(0.16f, -0.01f, 0.48f)),
            ("left_elbow",     "left_shoulder",  new Vector3(-0.01f, 0, -0.33f)),
            ("right_shoulder", "middle",         new Vector3(-0.16f, -0.01f, 0.48f)),
            ("right_elbow",    "right_shoulder", new Vector3(0.01f, 0, -0.33f)),
            ("left_thigh",     "body",           new Vector3(0.087f, 0, -0.01f)),
            ("left_knee",      "left_thigh",     new Vector3(0, 0, -0.42f)),
            ("left_ankle",     "left_knee",      new Vector3(0, -0.04f, -0.44f)),
            ("right_thigh",    "body",           new Vector3(-0.087f, 0, -0.01f)),
            ("right_knee",     "right_thigh",    new Vector3(0, 0, -0.42f)),
            ("right_ankle",    "right_knee",     new Vector3(0, -0.04f, -0.44f)),
        };

        public Skeleton3D BuildUtilitySkeleton()
        {
            var skel = new Skeleton3D { Name = "GpfSkeleton" };
            foreach (var b in Bones)
            {
                int idx = skel.AddBone(b.Name);
                if (b.Parent != "") skel.SetBoneParent(idx, skel.FindBone(b.Parent));
                skel.SetBoneRest(idx, new Transform3D(Basis.Identity, b.Pos));
                skel.ResetBonePose(idx);
            }
            return skel;
        }

        // Их оси → Godot: X→(−1,0,0), Y→(0,0,1), Z→(0,1,0). det=+1 (ротация, не зеркало);
        // их «вперёд» (0,−1,0) становится Godot-«вперёд» (0,0,−1), Z-вверх — Y-вверх.
        public Basis AxisConversionBasis()
            => new Basis(new Vector3(-1, 0, 0), new Vector3(0, 0, 1), new Vector3(0, 1, 0));

        public Node3D BuildAxisWrapper()
            => new Node3D { Name = "GpfSpace", Basis = AxisConversionBasis() };
    }
}

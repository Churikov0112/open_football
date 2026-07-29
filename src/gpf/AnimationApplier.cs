using Godot;

namespace Gpf
{
    // Применение кадра клипа на Skeleton3D — несглаженный путь Animation::Apply
    // (animation.cpp:370-433, 694-710): джойнты получают АБСОЛЮТНУЮ локальную ротацию,
    // player — позицию корня. Сглаживание/offsets/MovementHistory — фазы 3+.
    public partial class AnimationApplier : RefCounted
    {
        public void Apply(Skeleton3D skel, Animation anim, int frame, float timeOffsetMs,
                          bool noPos = false, float baseRotZ = 0f)
        {
            for (int i = 0; i < anim.GetTrackCount(); i++)
            {
                string name = anim.GetTrackName(i);
                int idx = skel.FindBone(name);
                if (idx < 0) continue;

                if (name == "player")
                {
                    Vector3 pos = anim.SampleRootPosition(frame, timeOffsetMs);
                    if (noPos) { pos.X = 0; pos.Y = 0; } // animation.cpp:409-412 (Z остаётся)
                    skel.SetBonePosePosition(idx, pos);
                }
                else
                {
                    Quaternion q = anim.SampleRotation(name, frame, timeOffsetMs);
                    if (name == "body" && baseRotZ != 0f) // animation.cpp:417-422
                        q = (new Quaternion(new Vector3(0, 0, 1), baseRotZ) * q).Normalized();
                    skel.SetBonePoseRotation(idx, q);
                }
            }
        }
    }
}

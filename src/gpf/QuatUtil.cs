using Godot;
using System;

namespace Gpf
{
    // Порт кватернионной математики Blunted2 (src/base/math/quaternion.cpp).
    // НЕ заменять на Godot Slerp: оригинал допускает bias>1 (экстраполяция, animation.cpp:277)
    // и мы обязаны сохранить поведение 1:1.
    public static class QuatUtil
    {
        // quaternion.cpp:426 MakeSameNeighborhood — вернуть q в полусфере reference.
        public static Quaternion SameNeighborhood(Quaternion q, Quaternion reference)
            => q.Dot(reference) < 0 ? new Quaternion(-q.X, -q.Y, -q.Z, -q.W) : q;

        // quaternion.cpp:352 GetSlerped(bias, to).
        public static Quaternion Slerp(Quaternion a, float bias, Quaternion b)
        {
            var qb = b;
            double cosHalfTheta = a.W * qb.W + a.X * qb.X + a.Y * qb.Y + a.Z * qb.Z;
            if (cosHalfTheta < 0)
            {
                qb = new Quaternion(-qb.X, -qb.Y, -qb.Z, -qb.W);
                cosHalfTheta = -cosHalfTheta;
            }
            if (Math.Abs(cosHalfTheta) >= 1.0) return a;

            double halfTheta = Math.Acos(cosHalfTheta);
            double sinHalfTheta = Math.Sqrt(1.0 - cosHalfTheta * cosHalfTheta);
            if (Math.Abs(sinHalfTheta) < 0.000001)
                return new Quaternion(
                    (float)(a.X * 0.5 + qb.X * 0.5), (float)(a.Y * 0.5 + qb.Y * 0.5),
                    (float)(a.Z * 0.5 + qb.Z * 0.5), (float)(a.W * 0.5 + qb.W * 0.5));

            double ratioA = Math.Sin((1 - bias) * halfTheta) / sinHalfTheta;
            double ratioB = Math.Sin(bias * halfTheta) / sinHalfTheta;
            return new Quaternion(
                (float)(a.X * ratioA + qb.X * ratioB), (float)(a.Y * ratioA + qb.Y * ratioB),
                (float)(a.Z * ratioA + qb.Z * ratioB), (float)(a.W * ratioA + qb.W * ratioB));
        }

        // Покомпонентный lerp (нормализует вызывающий — как GetLerped().GetNormalized() в Apply).
        public static Quaternion Lerp(Quaternion a, float bias, Quaternion b)
            => new Quaternion(
                a.X + (b.X - a.X) * bias, a.Y + (b.Y - a.Y) * bias,
                a.Z + (b.Z - a.Z) * bias, a.W + (b.W - a.W) * bias);
    }
}

using Godot;
using System;

namespace Gpf
{
    // Порт кватернионной математики Blunted2 (src/base/math/quaternion.cpp).
    // НЕ заменять на Godot Slerp: оригинал допускает bias>1 (экстраполяция, animation.cpp:277)
    // и мы обязаны сохранить поведение 1:1.
    // RefCounted (не static class) — чтобы GDScript мог звать статические методы через load().
    public partial class QuatUtil : RefCounted
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

        // Покомпонентный lerp БЕЗ нормализации — нормализует вызывающая сторона.
        // C++ GetLerped (quaternion.cpp:348-350) нормализует сам, а Apply (animation.cpp:404)
        // тут же зовёт GetNormalized() повторно; двойная нормализация тождественна одной,
        // так что результат совпадает 1:1.
        public static Quaternion Lerp(Quaternion a, float bias, Quaternion b)
            => new Quaternion(
                a.X + (b.X - a.X) * bias, a.Y + (b.Y - a.Y) * bias,
                a.Z + (b.Z - a.Z) * bias, a.W + (b.W - a.W) * bias);

        // quaternion.cpp:197-226. ВНИМАНИЕ: перестановка индексов оригинала — x=elements[0],
        // y=elements[2], z=elements[1]. НЕ заменять на Godot GetEuler (другая конвенция).
        public static void GetAngles(Quaternion q, out float x, out float y, out float z)
        {
            float ex = q.X, ey = q.Z, ez = q.Y, ew = q.W; // el[0], el[2], el[1], el[3]
            float singularityTest = ex * ey + ez * ew;
            if (singularityTest > 0.49999f || singularityTest < -0.49999f)
            {
                if (singularityTest > 0) { z = 2f * Mathf.Atan2(ex, ez); y = Mathf.Pi * 0.5f; }
                else { z = -2f * Mathf.Atan2(ex, ez); y = -Mathf.Pi * 0.5f; }
                x = 0;
                return;
            }
            float sqx = ex * ex, sqy = ey * ey, sqz = ez * ez;
            z = Mathf.Atan2(2f * ey * ew - 2f * ex * ez, 1f - 2f * sqy - 2f * sqz);
            y = Mathf.Asin(2f * ex * ey + 2f * ez * ew);
            x = Mathf.Atan2(2f * ex * ew - 2f * ey * ez, 1f - 2f * sqx - 2f * sqz);
        }

        // Мост-обёртка для GDScript-тестов (out-параметры через мост не ходят).
        public static Vector3 GetAnglesVec(Quaternion q)
        {
            GetAngles(q, out float x, out float y, out float z);
            return new Vector3(x, y, z);
        }

        // quaternion.cpp:284-296 (эквивалент конструктора Godot Quaternion(axis, angle);
        // держим свою обёртку, чтобы код порта читался как оригинал).
        public static Quaternion AngleAxis(float angle, Vector3 axis)
        {
            float half = 0.5f * angle;
            float s = Mathf.Sin(half);
            return new Quaternion(s * axis.X, s * axis.Y, s * axis.Z, Mathf.Cos(half));
        }
    }
}

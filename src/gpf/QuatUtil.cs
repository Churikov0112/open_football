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

        // quaternion.cpp:228-245 — прямая формула euclideanspace eulerToQuaternion.
        // ВНИМАНИЕ: SetAngles НЕ обратная к GetAngles (:197-226), хотя имена парные!
        //   * GetAngles читает компоненты с перестановкой (x=el[0], y=el[2], z=el[1]) и отдаёт
        //     (X,Y,Z) = (bank, attitude, heading);
        //   * SetAngles подставляет heading:=Y, attitude:=Z, bank:=X и пишет результат БЕЗ
        //     перестановки (el[1]=y, el[2]=z).
        // Две перестановки друг друга не гасят: SetAngles(GetAngles(q)) == q только для вращения
        // вокруг ОДНОЙ оси, на смешанном расходится (перекрёстные члены с sin(bank/2) меняют знак).
        // Портируем bug-for-bug: единственный вызов в оригинале (ball.cpp:509-512) — это как раз
        // пара GetAngles → масштабирование на timeStep → SetAngles над ОДНИМ кватернионом
        // (интегрирование вращения мяча). Значит асимметрия (перестановки осей не гасятся)
        // входит в само интегрирование вращения мяча и обязана быть воспроизведена задачей 2.
        // Эквивалентная запись: SetAngles(X,Y,Z) == Ry(Y) * Rz(Z) * Rx(X).
        // Трюки точности оригинала сохранены: аргумент делится на 2.0 (double), cos/sin считаются
        // в double и лишь затем сужаются до float — как `float c1 = cos(Y / 2.0)` в C++.
        public static Quaternion SetAngles(float x, float y, float z)
        {
            float c1 = (float)Math.Cos(y / 2.0);
            float s1 = (float)Math.Sin(y / 2.0);
            float c2 = (float)Math.Cos(z / 2.0);
            float s2 = (float)Math.Sin(z / 2.0);
            float c3 = (float)Math.Cos(x / 2.0);
            float s3 = (float)Math.Sin(x / 2.0);
            float c1c2 = c1 * c2;
            float s1s2 = s1 * s2;
            float ew = c1c2 * c3 - s1s2 * s3;      // elements[3]
            float ex = c1c2 * s3 + s1s2 * c3;      // elements[0]
            float ey = s1 * c2 * c3 + c1 * s2 * s3; // elements[1]
            float ez = c1 * s2 * c3 - s1 * c2 * s3; // elements[2]
            return new Quaternion(ex, ey, ez, ew);
        }

        // quaternion.cpp:314-321 GetMagnitude — нулевой кватернион и почти-нулевая длина дают 0.
        public static float GetMagnitude(Quaternion q)
        {
            if (q.X == 0f && q.Y == 0f && q.Z == 0f && q.W == 0f) return 0f;
            float magnitude = Mathf.Sqrt(q.X * q.X + q.Y * q.Y + q.Z * q.Z + q.W * q.W);
            if (magnitude < 0.000001f) return 0f;
            return magnitude;
        }

        // quaternion.cpp:159-168 GetInverse. НЕ Godot Quaternion.Inverse(): тот возвращает голое
        // сопряжение (верно лишь для единичных), а оригинал делит на МАГНИТУДУ (не на её квадрат —
        // сама по себе «неправильная» инверсия для неединичных, переносим как есть).
        public static Quaternion GetInverse(Quaternion q)
        {
            float fnorm = GetMagnitude(q);
            if (fnorm < 0.000001f) return Quaternion.Identity;
            float finvnorm = (float)(1.0 / fnorm);
            return new Quaternion(-q.X * finvnorm, -q.Y * finvnorm, -q.Z * finvnorm, q.W * finvnorm);
        }

        // quaternion.cpp:323-336 Normalize (через GetNormalized :338-342). Ветка
        // fabs(1-qmagsq) < 2.107342e-08 — приближение Ньютона оригинала для почти-единичных.
        public static Quaternion GetNormalized(Quaternion q)
        {
            double qmagsq = (double)q.X * q.X + (double)q.Y * q.Y
                          + (double)q.Z * q.Z + (double)q.W * q.W;
            if (qmagsq < 0.000001f) return Quaternion.Identity;
            double fac = Math.Abs(1.0 - qmagsq) < 2.107342e-08
                ? 2.0 / (1.0 + qmagsq)
                : 1.0 / Math.Sqrt(qmagsq);
            return new Quaternion(
                (float)(q.X * fac), (float)(q.Y * fac), (float)(q.Z * fac), (float)(q.W * fac));
        }

        // quaternion.cpp:247-264 GetAngleAxis. Внимание: acos БЕЗ клампа — на |w| чуть больше 1
        // (накопленная ошибка ненормализованного кватерниона) оригинал даёт NaN. Переносим как есть.
        // Угол выходит в [0, 2pi]; ось не нормируется, если div вырожден.
        public static void GetAngleAxis(Quaternion q, out float angle, out Vector3 axis)
        {
            angle = 2.0f * Mathf.Acos(q.W);
            double div = Mathf.Sqrt(1.0f - q.W * q.W); // std::sqrt(float) -> float, затем в double
            if (div < 0.000001f) axis = new Vector3(q.X, q.Y, q.Z);
            else axis = new Vector3((float)(q.X / div), (float)(q.Y / div), (float)(q.Z / div));
        }

        // quaternion.cpp:403-406 GetRotationTo: `to * this->GetInverse()`.
        // Godot-умножение кватернионов совпадает с Quaternion::operator* оригинала
        // (quaternion.cpp:133-142 — обычный гамильтонов продукт, тот же порядок членов).
        public static Quaternion GetRotationTo(Quaternion from, Quaternion to)
            => to * GetInverse(from);

        // quaternion.hpp:75-77 GetRotationAngle — инлайн в заголовке (не в .cpp).
        public static float GetRotationAngle(Quaternion q, Quaternion reference)
            => 2.0f * Mathf.Acos(Mathf.Clamp(
                q.X * reference.X + q.Y * reference.Y + q.Z * reference.Z + q.W * reference.W,
                -1.0f, 1.0f)); // GetDotProduct — quaternion.cpp:344-346

        // quaternion.cpp:408-424 GetRotationMultipliedBy — масштаб угла вокруг той же оси.
        // std::fmod == оператор % для float в C# (усечённый остаток, знак делимого).
        public static Quaternion GetRotationMultipliedBy(Quaternion q, float factor)
        {
            GetAngleAxis(q, out float angle, out Vector3 axis);
            if (angle > Mathf.Pi) angle -= 2.0f * Mathf.Pi; // range -pi .. pi
            angle = angle * factor % (2.0f * Mathf.Pi);     // remove multiples of 2pi
            return GetNormalized(AngleAxis(angle, axis));   // SetAngleAxis + GetNormalized
        }
    }
}

using Godot;
using System;
using System.Globalization;

namespace Gpf
{
    // Порт математики Blunted2 (src/base/math/bluntmath.{hpp,cpp}, src/base/math/vector3.hpp,
    // src/base/utils.cpp) + FixAngle (animcollection.hpp:50-55). Всё в «их» осях: 2D = плоскость XY,
    // Z-вверх. RefCounted (не static class) — чтобы GDScript мог звать статические методы через load().
    public partial class BluntMath : RefCounted
    {
        // bluntmath.hpp:46-49
        public static float Curve(float source, float bias)
            => (Mathf.Sin((source - 0.5f) * Mathf.Pi) * 0.5f + 0.5f) * bias + source * (1.0f - bias);

        // bluntmath.cpp:34-39
        public static float NormalizedClamp(float v, float min, float max)
            => (Mathf.Clamp(v, min, max) - min) / (max - min);

        // bluntmath.cpp:94-100
        public static float ModulateIntoRange(float min, float max, float v)
        {
            float step = max - min;
            float newValue = v;
            while (newValue < min) newValue += step;
            while (newValue > max) newValue -= step;
            return newValue;
        }

        // bluntmath.cpp:61-63 (n >= 0 → 1)
        public static int SignSide(float n) => n >= 0 ? 1 : -1;

        // bluntmath.cpp:65-67
        public static bool IsOdd(int n) => (n & 1) != 0;

        // animcollection.hpp:50-55: «движковый» угол → футбольный (база «вниз по Y», не «вправо по X»)
        public static float FixAngle(float angle)
            => ModulateIntoRange(-Mathf.Pi, Mathf.Pi, angle + 0.5f * Mathf.Pi);

        // Семантика atof/atoi: пусто/мусор → 0, никаких исключений (в оригинале везде atof(GetVariable(...)))
        public static float AtoF(string s)
            => float.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out float v) ? v : 0f;

        public static int AtoI(string s)
            => int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out int v) ? v : 0;

        // base/utils.cpp:222-237 (пустая строка → (0,0,0); < 3 компонент — остаток нули)
        public static Vector3 GetVectorFromString(string s)
        {
            if (string.IsNullOrEmpty(s)) return Vector3.Zero;
            string[] tok = s.Split(',');
            var v = Vector3.Zero;
            if (tok.Length > 0) v.X = AtoF(tok[0].Trim());
            if (tok.Length > 1) v.Y = AtoF(tok[1].Trim());
            if (tok.Length > 2) v.Z = AtoF(tok[2].Trim());
            return v;
        }

        // base/utils.cpp:213-220
        public static string GetStringFromVector(Vector3 v)
            => string.Format(CultureInfo.InvariantCulture, "{0:F6}, {1:F6}, {2:F6}", v.X, v.Y, v.Z);

        // vector3.hpp:325-333 (Z не трогается)
        public static Vector3 GetRotated2D(Vector3 v, float angle)
        {
            float c = Mathf.Cos(angle), s = Mathf.Sin(angle);
            return new Vector3(v.X * c - v.Y * s, v.Y * c + v.X * s, v.Z);
        }

        // vector3.hpp:276-280: [0, 2pi)
        public static float GetAngle2D(Vector3 v)
        {
            float angle = Mathf.Atan2(v.Y, v.X);
            if (angle < 0) angle += 2f * Mathf.Pi;
            return angle;
        }

        // vector3.hpp:283-289: [-pi, pi], знак с минусом перед atan2 — портировать в точности
        public static float GetAngle2D(Vector3 v, Vector3 test)
        {
            float angle = -Mathf.Atan2(v.X * test.Y - v.Y * test.X, v.X * test.X + v.Y * test.Y);
            return ModulateIntoRange(-Mathf.Pi, Mathf.Pi, angle);
        }

        // Vector3::GetNormalized(fallback): нулевая длина → fallback
        public static Vector3 GetNormalized(Vector3 v, Vector3 fallback)
        {
            float len = v.Length();
            return len == 0f ? fallback : v / len;
        }

        // vector3.hpp:336-339
        public static Vector3 Get2D(Vector3 v) => new Vector3(v.X, v.Y, 0f);
    }
}

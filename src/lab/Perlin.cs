using Godot;

namespace Gpf.Lab
{
    // Порт src/misc/perlin.cpp|.h оригинала (класс Ken Perlin с flipcode) — зависимость
    // генератора газона (ProceduralPitch). Слой лабы, в Gpf.* не едет: в оригинале это misc-модуль,
    // который зовёт только proceduralpitch.cpp.
    //
    // Оригинал сидит решётку через CRT srand()/rand() (perlin.cpp:40, :63, :107, :182-194).
    // Эталон-exe собран MSVC (см. .scratch/oracle/run-commands.md), поэтому портируется
    // именно MSVC-ГСЧ: state = state*214013 + 2531011, выход (state >> 16) & 0x7fff.
    // У C++ состояние rand() глобально на процесс, но init() двух перлинов не перемежается
    // (оба Get() впервые зовутся из последовательного цикла заполнения perlinTex), так что
    // локальное состояние на экземпляр даёт ту же последовательность.
    public class Perlin
    {
        private const int SampleSize = 1024; // perlin.h:7 SAMPLE_SIZE
        private const int B = SampleSize;    // perlin.cpp:14
        private const int BM = SampleSize - 1; // perlin.cpp:15
        private const int N = 0x1000;        // perlin.cpp:17

        private readonly int _octaves;    // mOctaves
        private readonly float _frequency; // mFrequency
        private readonly float _amplitude; // mAmplitude
        private readonly int _seed;       // mSeed
        private bool _start = true;       // mStart

        private readonly int[] _p = new int[SampleSize + SampleSize + 2];      // p
        private readonly float[] _g1 = new float[SampleSize + SampleSize + 2]; // g1
        private readonly float[,] _g2 = new float[SampleSize + SampleSize + 2, 2]; // g2
        private readonly float[,] _g3 = new float[SampleSize + SampleSize + 2, 3]; // g3

        // MSVC CRT rand(): LCG 214013·x + 2531011, старшие 15 бит.
        private uint _randState;
        private void SRand(int seed) => _randState = (uint)seed;
        private int Rand()
        {
            unchecked { _randState = _randState * 214013u + 2531011u; }
            return (int)((_randState >> 16) & 0x7fff);
        }

        // perlin.cpp:235-242
        public Perlin(int octaves, float freq, float amp, int seed)
        {
            _octaves = octaves;
            _frequency = freq;
            _amplitude = amp;
            _seed = seed;
        }

        // perlin.h:16-21
        public float Get(float x, float y)
        {
            float vecX = x;
            float vecY = y;
            return PerlinNoise2D(ref vecX, ref vecY);
        }

        // perlin.cpp:211-231 perlin_noise_2D: vec масштабируется частотой ОДИН раз, затем
        // удваивается на октаву; амплитуда стартует с mAmplitude и половинится.
        private float PerlinNoise2D(ref float vecX, ref float vecY)
        {
            int terms = _octaves;
            float result = 0.0f;
            float amp = _amplitude;

            vecX *= _frequency;
            vecY *= _frequency;

            for (int i = 0; i < terms; i++)
            {
                result += Noise2(vecX, vecY) * amp;
                vecX *= 2.0f;
                vecY *= 2.0f;
                amp *= 0.5f;
            }

            return result;
        }

        // perlin.cpp:21-22 макросы
        private static float SCurve(float t) => t * t * (3.0f - 2.0f * t);
        private static float Lerp(float t, float a, float b) => a + t * (b - a);

        // perlin.cpp:24-29 макрос setup: t = vec + N, целая часть в решётку по маске BM,
        // дробная — в r0/r1. (int)t — усечение C++, вход всегда положителен (N = 4096).
        private static void Setup(float vec, out int b0, out int b1, out float r0, out float r1)
        {
            float t = vec + N;
            b0 = ((int)t) & BM;
            b1 = (b0 + 1) & BM;
            r0 = t - (int)t;
            r1 = r0 - 1.0f;
        }

        // perlin.cpp:55-97 noise2
        private float Noise2(float vecX, float vecY)
        {
            if (_start) // :61-66 — ленивый init на первом обращении, с srand(mSeed)
            {
                SRand(_seed);
                _start = false;
                Init();
            }

            Setup(vecX, out int bx0, out int bx1, out float rx0, out float rx1); // :68
            Setup(vecY, out int by0, out int by1, out float ry0, out float ry1); // :69

            int i = _p[bx0]; // :71
            int j = _p[bx1]; // :72

            int b00 = _p[i + by0]; // :74
            int b10 = _p[j + by0]; // :75
            int b01 = _p[i + by1]; // :76
            int b11 = _p[j + by1]; // :77

            float sx = SCurve(rx0); // :79
            float sy = SCurve(ry0); // :80

            // :82 at2(rx, ry) = rx*q[0] + ry*q[1]
            float At2(int q, float rx, float ry) => rx * _g2[q, 0] + ry * _g2[q, 1];

            float u = At2(b00, rx0, ry0); // :84-85
            float v = At2(b10, rx1, ry0); // :86-87
            float a = Lerp(sx, u, v);     // :88

            u = At2(b01, rx0, ry1);       // :90-91
            v = At2(b11, rx1, ry1);       // :92-93
            float b = Lerp(sx, u, v);     // :94

            return Lerp(sy, a, b);        // :96
        }

        // perlin.cpp:31-53 noise1 — МЁРТВЫЙ в этом порте (живой путь — только noise2 через Get),
        // перенесён дословно вместе с модулем.
        private float Noise1(float arg)
        {
            if (_start)
            {
                SRand(_seed);
                _start = false;
                Init();
            }

            Setup(arg, out int bx0, out int bx1, out float rx0, out float rx1); // :45

            float sx = SCurve(rx0);            // :47
            float u = rx0 * _g1[_p[bx0]];      // :49
            float v = rx1 * _g1[_p[bx1]];      // :50
            return Lerp(sx, u, v);             // :52
        }

        // perlin.cpp:99-151 noise3 — МЁРТВЫЙ (как noise1), перенесён дословно.
        private float Noise3(float vecX, float vecY, float vecZ)
        {
            if (_start)
            {
                SRand(_seed);
                _start = false;
                Init();
            }

            Setup(vecX, out int bx0, out int bx1, out float rx0, out float rx1); // :112
            Setup(vecY, out int by0, out int by1, out float ry0, out float ry1); // :113
            Setup(vecZ, out int bz0, out int bz1, out float rz0, out float rz1); // :114

            int i = _p[bx0]; // :116
            int j = _p[bx1]; // :117

            int b00 = _p[i + by0]; // :119
            int b10 = _p[j + by0]; // :120
            int b01 = _p[i + by1]; // :121
            int b11 = _p[j + by1]; // :122

            float t = SCurve(rx0);  // :124
            float sy = SCurve(ry0); // :125
            float sz = SCurve(rz0); // :126

            // :128 at3(rx, ry, rz)
            float At3(int q, float rx, float ry, float rz)
                => rx * _g3[q, 0] + ry * _g3[q, 1] + rz * _g3[q, 2];

            float u = At3(b00 + bz0, rx0, ry0, rz0); // :130
            float v = At3(b10 + bz0, rx1, ry0, rz0); // :131
            float a = Lerp(t, u, v);                 // :132

            u = At3(b01 + bz0, rx0, ry1, rz0);       // :134
            v = At3(b11 + bz0, rx1, ry1, rz0);       // :135
            float b = Lerp(t, u, v);                 // :136

            float c = Lerp(sy, a, b);                // :138

            u = At3(b00 + bz1, rx0, ry0, rz1);       // :140
            v = At3(b10 + bz1, rx1, ry0, rz1);       // :141
            a = Lerp(t, u, v);                       // :142

            u = At3(b01 + bz1, rx0, ry1, rz1);       // :144
            v = At3(b11 + bz1, rx1, ry1, rz1);       // :145
            b = Lerp(t, u, v);                       // :146

            float d = Lerp(sy, a, b);                // :148

            return Lerp(sz, c, d);                   // :150
        }

        // perlin.cpp:153-161
        private static void Normalize2(float[,] g, int i)
        {
            float s = Mathf.Sqrt(g[i, 0] * g[i, 0] + g[i, 1] * g[i, 1]);
            s = 1.0f / s;
            g[i, 0] *= s;
            g[i, 1] *= s;
        }

        // perlin.cpp:163-173
        private static void Normalize3(float[,] g, int i)
        {
            float s = Mathf.Sqrt(g[i, 0] * g[i, 0] + g[i, 1] * g[i, 1] + g[i, 2] * g[i, 2]);
            s = 1.0f / s;
            g[i, 0] *= s;
            g[i, 1] *= s;
            g[i, 2] *= s;
        }

        // perlin.cpp:175-208 init: порядок обращений к rand() внутри витка (g1 → g2 → g3)
        // и перестановка решётки — священны, они и есть «форма» шума.
        private void Init()
        {
            int i, j, k;

            for (i = 0; i < B; i++) // :179-189
            {
                _p[i] = i;
                _g1[i] = (float)((Rand() % (B + B)) - B) / B;
                for (j = 0; j < 2; j++)
                    _g2[i, j] = (float)((Rand() % (B + B)) - B) / B;
                Normalize2(_g2, i);
                for (j = 0; j < 3; j++)
                    _g3[i, j] = (float)((Rand() % (B + B)) - B) / B;
                Normalize3(_g3, i);
            }

            while (--i != 0) // :191-196 — i входит равным B, тело крутится для B-1..1
            {
                k = _p[i];
                _p[i] = _p[j = Rand() % B];
                _p[j] = k;
            }

            for (i = 0; i < B + 2; i++) // :198-206 — удвоение решётки хвостом
            {
                _p[B + i] = _p[i];
                _g1[B + i] = _g1[i];
                for (j = 0; j < 2; j++)
                    _g2[B + i, j] = _g2[i, j];
                for (j = 0; j < 3; j++)
                    _g3[B + i, j] = _g3[i, j];
            }
        }
    }
}

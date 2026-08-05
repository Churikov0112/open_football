using Godot;
using System.Threading.Tasks;

namespace Gpf.Lab
{
    // Порт src/onthepitch/proceduralpitch.cpp ЦЕЛИКОМ — генератор текстур газона: полосы покоса
    // (нормал-карта), перлин-шум с «каналами» синусов, виньетка затемнения к краям, разметка из
    // overlay.png. Слой лабы, в Gpf.* не едет: в оригинале это модуль, который зовёт Match на
    // конструкции (match.cpp:220-226). Все числа — оригинала, как есть; тюнинг запрещён.
    //
    // Мёртвая рисовалка разметки (DrawLines/BmpRect/BmpArc/ConvertCoord/DrawMud) перенесена
    // дословно и НЕ вызывается — как в оригинале (вызовы закомментированы, :318-320): вся
    // разметка приходит из overlay.png (4096×2048 с альфой). Оживлять запрещено — включённая
    // рисовалка поверх overlay даст картинку, которой нет у эталон-exe.
    //
    // Случайность — ДВА потока, как в оригинале:
    //  - бросок ширины полос покоса (:455, random(0,1)) — единственное число из
    //    ПРЕЗЕНТАЦИОННОГО GpfRng (тикет .scratch/oracle/issues/17-...);
    //  - попиксельный шум и смещения перлин-выборки — fastrandom (bluntmath.hpp:34-44): LCG
    //    214013·x + 2531011 с ОБЩИМ состоянием, сид от времени; параллельные чанки гоняют его
    //    без синхронизации — как boost-треды оригинала. Детерминизма пикселей нет по построению.
    // Перлины сидятся временем (time(NULL) / time(NULL)+139882, :423-424).
    //
    // Выход — картинки В ПАМЯТИ (ImageTexture), запекание на диск запрещено. У оригинала
    // CreateChunk перезаписывает ресурсы pitch_0i.png / pitch_specular_0i / pitch_normal_0i
    // (:347-380); наш аналог этого шва — подмена текстур в уже назначенных материалах поля,
    // делает её оркестратор (StadiumLabMain.ApplyPitchTextures).
    public partial class ProceduralPitch : RefCounted
    {
        // Ключ конфига оригинала graphics_pitchredtoblueratio, дефолт 0.5 (:64); конфига в
        // порте нет — живёт дефолт.
        private const float PitchRedToBlueRatio = 0.5f;

        private const string SeamlessPng = "res://assets/gpf/media/textures/pitch/seamlessgrass08.png";
        private const string OverlayPng = "res://assets/gpf/media/textures/pitch/overlay.png";

        // Глобалы модуля (:19-30). Живут только на время GeneratePitch.
        private static float[] _perlinTex = System.Array.Empty<float>();
        private static int _perlinTexW;
        private static int _perlinTexH;

        private static Vector3[] _seamlessTex = System.Array.Empty<Vector3>();
        private static int _seamlessTexW;
        private static int _seamlessTexH;

        private static Vector3[] _overlayTex = System.Array.Empty<Vector3>();
        private static float[] _overlayAlphaTex = System.Array.Empty<float>();
        private static int _overlayTexW;
        private static int _overlayTexH;

        // fastrandom (bluntmath.hpp:34-44). Состояние ОБЩЕЕ и без синхронизации — гонка чанков
        // есть и в оригинале. max_uint*1.0f = 4294967295 → во float это 2^32.
        private static uint _fastrandseed;
        private static void FastRandomSeed()
            => _fastrandseed = (uint)Time.GetUnixTimeFromSystem(); // :35 — std::time(0)

        private static float FastRandom(float min, float max) // :39-44
        {
            float range = max - min;
            float tmp = (_fastrandseed / 4294967295.0f) * range + min;
            unchecked { _fastrandseed = 214013u * _fastrandseed + 2531011u; }
            return tmp;
        }

        // vector3.hpp:261-268 GetLength — квирк оригинала: длина < 1e-6 обнуляется.
        private static float GetLength(Vector3 v)
        {
            float length = Mathf.Sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z);
            if (length < 0.000001f) length = 0f;
            return length;
        }

        // :32-51 BilinearSample<T> — две инстанциации шаблона (float и Vector3).
        private static float BilinearSample(float[] tex, float x, float y, int w, int h)
        {
            int intX1 = (int)Mathf.Floor(x);
            int intY1 = (int)Mathf.Floor(y);
            int intX2 = ((int)Mathf.Floor(x) + 1) % w;
            int intY2 = ((int)Mathf.Floor(y) + 1) % h;
            float x1y1 = tex[intY1 * w + intX1];
            float x2y1 = tex[intY1 * w + intX2];
            float x1y2 = tex[intY2 * w + intX1];
            float x2y2 = tex[intY2 * w + intX2];
            float xBias = x - intX1;
            float yBias = y - intY1;
            return (x1y1 * (1.0f - xBias) + x2y1 * xBias) * (1.0f - yBias) +
                   (x1y2 * (1.0f - xBias) + x2y2 * xBias) * yBias;
        }

        private static Vector3 BilinearSample(Vector3[] tex, float x, float y, int w, int h)
        {
            int intX1 = (int)Mathf.Floor(x);
            int intY1 = (int)Mathf.Floor(y);
            int intX2 = ((int)Mathf.Floor(x) + 1) % w;
            int intY2 = ((int)Mathf.Floor(y) + 1) % h;
            Vector3 x1y1 = tex[intY1 * w + intX1];
            Vector3 x2y1 = tex[intY1 * w + intX2];
            Vector3 x1y2 = tex[intY2 * w + intX1];
            Vector3 x2y2 = tex[intY2 * w + intX2];
            float xBias = x - intX1;
            float yBias = y - intY1;
            return (x1y1 * (1.0f - xBias) + x2y1 * xBias) * (1.0f - yBias) +
                   (x1y2 * (1.0f - xBias) + x2y2 * xBias) * yBias;
        }

        // :53-123 GetPitchDiffuseColor. SDL_MapRGB заменён прямой записью байтов: float→Uint8
        // в C++ — усечение к нулю, здесь (byte) после клампа — то же.
        private static void GetPitchDiffuseColor(float xCoord, float yCoord,
            out byte outR, out byte outG, out byte outB)
        {
            float texMultiplier = 0.3f;          // :55
            float texScale = 0.32f;              // :56
            float randomNoiseMultiplier = 0.0f;  // :57
            float perlinNoiseMultiplier = 0.4f;  // :58
            float brightness = 2.0f;             // :59

            float r, g, b;

            float contrast = 0.4f;                       // :63 — g <=> rb; ниже = меньше сатурации
            float rToB = PitchRedToBlueRatio * 2.0f;     // :64 — 0..2, больше = краснее
            r = ((35 - contrast * 10) * rToB) * brightness;          // :65
            g = 46 * brightness;                                     // :66
            b = ((25 - contrast * 10) * (2.0f - rToB)) * brightness; // :67

            float seamlessX = ((xCoord / GpfPitch.PitchFullHalfW) * 0.5f + 0.5f)
                * _seamlessTexW * 18.0f * texScale; // :69
            float seamlessY = ((yCoord / GpfPitch.PitchFullHalfH) * 0.5f + 0.5f)
                * _seamlessTexH * 12.0f * texScale; // :70
            seamlessX %= _seamlessTexW; // :71 — fmod, вход неотрицателен
            seamlessY %= _seamlessTexH; // :72
            Vector3 tex = BilinearSample(_seamlessTex, seamlessX, seamlessY,
                _seamlessTexW, _seamlessTexH); // :74
            r = r * (1.0f - texMultiplier) + tex.X * texMultiplier; // :75
            g = g * (1.0f - texMultiplier) + tex.Y * texMultiplier; // :76
            b = b * (1.0f - texMultiplier) + tex.Z * texMultiplier; // :77

            float perlX = ((xCoord / GpfPitch.PitchFullHalfW) * 0.5f + 0.5f) * _perlinTexW; // :79
            float perlY = ((yCoord / GpfPitch.PitchFullHalfH) * 0.5f + 0.5f) * _perlinTexH; // :80
            float randomSpread = 2.5f;          // :81
            float randomX = FastRandom(-1, 1);  // :82
            perlX = Mathf.Clamp(perlX + randomX * randomSpread, 0, _perlinTexW - 1); // :83
            float randomY = FastRandom(-1, 1);  // :84
            perlY = Mathf.Clamp(perlY + randomY * randomSpread, 0, _perlinTexH - 1); // :85
            float perlinNoise = BilinearSample(_perlinTex, perlX, perlY,
                _perlinTexW, _perlinTexH) - 0.5f; // :86
            float perlinNoiseR = perlinNoise; // :87
            float perlinNoiseG = perlinNoise; // :88
            float perlinNoiseB = perlinNoise; // :89

            // :91-98 mud — закомментирован в оригинале:
            // if (noise < 0.1) {
            //   float bias = noise / 1.0;
            //   r = (r * bias) + r * 1.0 * (1 - bias);
            //   g = (g * bias) + g * 0.9 * (1 - bias);
            //   b = (b * bias) + b * 0.9 * (1 - bias);
            // }

            float randomNoise = 0.0f; // :100
            if (randomNoiseMultiplier > 0.0f) randomNoise = FastRandom(-1, 1); // :101 — мёртвая ветка (множитель 0), броска НЕТ
            r += ((perlinNoiseR * perlinNoiseMultiplier) + (randomNoise * randomNoiseMultiplier)) * 40.0f; // :102
            g += ((perlinNoiseG * perlinNoiseMultiplier) + (randomNoise * randomNoiseMultiplier)) * 40.0f; // :103
            b += ((perlinNoiseB * perlinNoiseMultiplier) + (randomNoise * randomNoiseMultiplier)) * 40.0f; // :104

            // фейковое ambient occlusion (:106-111) — виньетка от центра, доли поля ЛИНИЙ (55/36)
            Vector3 lightPos = new Vector3(0, 0, 0); // :107
            float darkness = 1.0f - Mathf.Pow(
                Mathf.Clamp(GetLength(lightPos - new Vector3(
                    xCoord / GpfPitch.PitchHalfW, yCoord / GpfPitch.PitchHalfH, 0)) * 0.7f, 0.0f, 1.0f),
                1.5f) * 0.18f; // :108
            r *= darkness; // :109
            g *= darkness; // :110
            b *= darkness; // :111

            float overlayX = ((xCoord / GpfPitch.PitchFullHalfW) * 0.5f + 0.5f) * _overlayTexW; // :113
            float overlayY = ((yCoord / GpfPitch.PitchFullHalfH) * 0.5f + 0.5f) * _overlayTexH; // :114
            Vector3 overlay = BilinearSample(_overlayTex, overlayX, overlayY,
                _overlayTexW, _overlayTexH); // :115
            float overlayAlpha = BilinearSample(_overlayAlphaTex, overlayX, overlayY,
                _overlayTexW, _overlayTexH); // :116
            r = Mathf.Clamp(r * (1.0f - overlayAlpha) + overlay.X * overlayAlpha, 0, 255); // :117
            g = Mathf.Clamp(g * (1.0f - overlayAlpha) + overlay.Y * overlayAlpha, 0, 255); // :118
            b = Mathf.Clamp(b * (1.0f - overlayAlpha) + overlay.Z * overlayAlpha, 0, 255); // :119

            outR = (byte)r; // :121 SDL_MapRGB — float→Uint8 усечением
            outG = (byte)g;
            outB = (byte)b;
        }

        // :125-141 GetPitchSpecularColor
        private static void GetPitchSpecularColor(float xCoord, float yCoord,
            out byte outR, out byte outG, out byte outB)
        {
            float baseVal = 2.0f;   // :127
            float noisefac = 18.0f; // :128

            float perlX = ((xCoord / GpfPitch.PitchFullHalfW) * 0.5f + 0.5f) * _perlinTexW; // :130
            float perlY = ((yCoord / GpfPitch.PitchFullHalfH) * 0.5f + 0.5f) * _perlinTexH; // :131
            float randomSpread = 2.5f;          // :132
            float randomX = FastRandom(-1, 1);  // :133
            perlX = Mathf.Clamp(perlX + randomX * randomSpread, 0, _perlinTexW - 1); // :134
            float randomY = FastRandom(-1, 1);  // :135
            perlY = Mathf.Clamp(perlY + randomY * randomSpread, 0, _perlinTexH - 1); // :136
            float noise = baseVal + BilinearSample(_perlinTex, perlX, perlY,
                _perlinTexW, _perlinTexH) * noisefac; // :137

            outR = (byte)noise; // :139
            outG = (byte)noise;
            outB = (byte)noise;
        }

        // :143 xmod — МЁРТВЫЙ (нигде не вызывается и в оригинале), перенесён дословно.
        private static float Xmod(float coord, float repeat)
            => coord - repeat * Mathf.Floor(coord / repeat);

        // :145-157 GetSmoothGrassDirection — синус по полосам + повторное curve-обострение.
        private static float GetSmoothGrassDirection(float coord, float repeat,
            int transitionSharpness = 5)
        {
            float iteration = Mathf.Floor(coord / repeat); // :146
            float bias = coord - repeat * iteration;       // :147 — 0..1 на ДВЕ полосы
            bias = Mathf.Sin(bias * 2 * Mathf.Pi) * 0.5f + 0.5f; // :148
            for (int i = 0; i < transitionSharpness; i++)  // :149-151
            {
                bias = BluntMath.Curve(bias, 1.0f);
            }

            // обратно в диапазон -1..1 (:153-156)
            bias *= 2.0f;
            bias -= 1.0f;
            return bias;
        }

        // :159-189 GetPitchNormalColor: полосы покоса только в поле ЛИНИЙ (55×36), шум — везде.
        private static void GetPitchNormalColor(float xCoord, float yCoord, float repeatMultiplier,
            out byte outR, out byte outG, out byte outB)
        {
            float noisefac = 0.06f; // :161

            Vector3 normal = new Vector3(0, 0, 1); // :163

            if (Mathf.Abs(xCoord) < GpfPitch.PitchHalfW
                && Mathf.Abs(yCoord) < GpfPitch.PitchHalfH) // :165
            {
                float xRepeat = 11.0f * repeatMultiplier; // :167
                float yRepeat = 11.0f * repeatMultiplier; // :168
                float xStrength = 0.12f; // :169
                float yStrength = 0.1f;  // :170 — поперечный покос глушит эти полосы, потому слабее

                int transitionSharpness = 5; // :172
                if (repeatMultiplier > 0.75f) transitionSharpness = 7; // :173 — шире полосы = больше обострения
                normal += new Vector3(
                    GetSmoothGrassDirection(yCoord / yRepeat, 1.0f, transitionSharpness) * yStrength,
                    GetSmoothGrassDirection(xCoord / xRepeat, 1.0f, transitionSharpness) * xStrength,
                    0); // :174
            }

            normal.X += FastRandom(-1, 1) * noisefac; // :178
            normal.Y += FastRandom(-1, 1) * noisefac; // :179

            normal = normal.Normalized(); // :181 — вектор гарантированно ненулевой (Z ≈ 1)

            normal.X = normal.X * 0.5f + 0.5f; // :183
            normal.Y = normal.Y * 0.5f + 0.5f; // :184
            normal.Z = normal.Z * 0.5f + 0.5f; // :185

            outR = (byte)(normal.X * 255); // :187
            outG = (byte)(normal.Y * 255);
            outB = (byte)(normal.Z * 255);
        }

        // ------------------------------------------------------------------------------------
        // Мёртвая рисовалка разметки (:191-287): вызовы закомментированы в оригинале
        // (:318-320), перенесена дословно и НЕ вызывается. Битмап — RGB по 3 байта на пиксель.

        // :191-202
        private static void ConvertCoord(int resX, int resY, float x1, float y1,
            int offsetW, int offsetH, out float x, out float y)
        {
            x = x1;
            y = y1;
            // в масштаб битмапа
            x *= resX;
            x /= GpfPitch.PitchFullHalfW;
            y *= resY;
            y /= GpfPitch.PitchFullHalfH;
            // какая из 4 четвертей рисуется — зеркалим соответственно
            if (offsetW == -1) x = resX - x - 1;
            if (offsetH == -1) y = resY - y - 1;
        }

        // :204-224
        private static void BmpRect(byte[] bitmap, int resX, int resY,
            float x1, float y1, float x2, float y2, int offsetW, int offsetH)
        {
            ConvertCoord(resX, resY, x1, y1, offsetW, offsetH, out float rx1, out float ry1);
            ConvertCoord(resX, resY, x2, y2, offsetW, offsetH, out float rx2, out float ry2);

            if (rx2 < rx1) { float tmp = rx2; rx2 = rx1; rx1 = tmp; }
            if (ry2 < ry1) { float tmp = ry2; ry2 = ry1; ry1 = tmp; }

            for (int xi = (int)Mathf.Ceil(rx1); xi <= (int)Mathf.Floor(rx2); xi++)
            {
                for (int yi = (int)Mathf.Ceil(ry1); yi <= (int)Mathf.Floor(ry2); yi++)
                {
                    int idx = (yi * resX + xi) * 3;
                    bitmap[idx + 0] = (byte)(bitmap[idx + 0] * 0.5 + 100); // :217
                    bitmap[idx + 1] = (byte)(bitmap[idx + 1] * 0.5 + 100); // :218
                    bitmap[idx + 2] = (byte)(bitmap[idx + 2] * 0.5 + 100); // :219
                }
            }
        }

        // :226-252
        private static void BmpArc(byte[] bitmap, int resX, int resY,
            float x1, float y1, float radius, float begin, float end, int offsetW, int offsetH)
        {
            int steps = (int)(resX * 0.03f * radius); // :228 — «hackish approximation» оригинала
            float step = Mathf.Abs(end - begin) / steps; // :229
            float currentRad = begin;
            for (int i = 0; i < steps; i++)
            {
                float x = x1 + Mathf.Sin(currentRad) * radius;           // :233
                float y = y1 + Mathf.Cos(Mathf.Pi + currentRad) * radius; // :234

                ConvertCoord(resX, resY, x, y, offsetW, offsetH, out float rxf, out float ryf);
                int rx = (int)Mathf.Round(rxf);
                int ry = (int)Mathf.Round(ryf);
                if (rx >= 0 && rx < resX && ry >= 0 && ry < resY)
                {
                    int idx = (ry * resX + rx) * 3;
                    bitmap[idx + 0] = (byte)(bitmap[idx + 0] * 0.5 + 100); // :244
                    bitmap[idx + 1] = (byte)(bitmap[idx + 1] * 0.5 + 100); // :245
                    bitmap[idx + 2] = (byte)(bitmap[idx + 2] * 0.5 + 100); // :246
                }
                currentRad += step;
            }
        }

        // :254-282 — рисуется только нижне-правая четверть, остальные зеркалятся offsetW/offsetH
        private static void DrawLines(byte[] diffuseBitmap, int resX, int resY,
            int offsetW, int offsetH)
        {
            float pitchHalfW = GpfPitch.PitchHalfW;
            float pitchHalfH = GpfPitch.PitchHalfH;
            float lineHalfW = GpfPitch.LineHalfW;

            BmpRect(diffuseBitmap, resX, resY, pitchHalfW - lineHalfW, 0, pitchHalfW + lineHalfW, pitchHalfH + lineHalfW, offsetW, offsetH); // :258 лицевая
            BmpRect(diffuseBitmap, resX, resY, 0, pitchHalfH - lineHalfW, pitchHalfW - lineHalfW, pitchHalfH + lineHalfW, offsetW, offsetH); // :259 боковая
            BmpRect(diffuseBitmap, resX, resY, 0, 0, lineHalfW * 0.5f, pitchHalfH - lineHalfW, offsetW, offsetH); // :260 центральная — почему пол-полуширины, не знал и автор

            // штрафная 16.5 м (:262-264)
            BmpRect(diffuseBitmap, resX, resY, pitchHalfW - 16.5f - lineHalfW, 0, pitchHalfW - 16.5f + lineHalfW, 20.15f - lineHalfW, offsetW, offsetH);
            BmpRect(diffuseBitmap, resX, resY, pitchHalfW - 16.5f - lineHalfW, 20.15f - lineHalfW, pitchHalfW - lineHalfW, 20.15f + lineHalfW, offsetW, offsetH);

            // вратарская (полуширина 9.16) (:266-268)
            BmpRect(diffuseBitmap, resX, resY, pitchHalfW - 5.5f - lineHalfW, 0, pitchHalfW - 5.5f + lineHalfW, 9.16f - lineHalfW, offsetW, offsetH);
            BmpRect(diffuseBitmap, resX, resY, pitchHalfW - 5.5f - lineHalfW, 9.16f - lineHalfW, pitchHalfW - lineHalfW, 9.16f + lineHalfW, offsetW, offsetH);

            BmpArc(diffuseBitmap, resX, resY, 0, 0, 9.15f, 0.5f * Mathf.Pi, 1f * Mathf.Pi, offsetW, offsetH); // :270 центральный круг
            BmpArc(diffuseBitmap, resX, resY, pitchHalfW - 11, 0, 9.15f, 1.208f * Mathf.Pi, 1.5f * Mathf.Pi, offsetW, offsetH); // :271 дуга штрафной

            BmpArc(diffuseBitmap, resX, resY, pitchHalfW, pitchHalfH, 0.5f, 1.55f * Mathf.Pi, 2f * Mathf.Pi, offsetW, offsetH); // :273 угловой сектор

            // точка пенальти (:275-277)
            BmpArc(diffuseBitmap, resX, resY, pitchHalfW - 11, 0, 0.08f, 0.5f * Mathf.Pi, 1.5f * Mathf.Pi, offsetW, offsetH);
            BmpArc(diffuseBitmap, resX, resY, pitchHalfW - 11, 0, 0.04f, 0.5f * Mathf.Pi, 1.5f * Mathf.Pi, offsetW, offsetH);

            // центральная точка (:279-281)
            BmpArc(diffuseBitmap, resX, resY, 0, 0, 0.08f, 0.5f * Mathf.Pi, 1.0f * Mathf.Pi, offsetW, offsetH);
            BmpArc(diffuseBitmap, resX, resY, 0, 0, 0.04f, 0.5f * Mathf.Pi, 1.0f * Mathf.Pi, offsetW, offsetH);
        }

        // :284-287 DrawMud — и в оригинале только заготовка в комментарии:
        // void DrawMud(SDL_PixelFormat *pixelFormat, Uint32 *diffuseBitmap, int resX, int resY,
        //              signed int offsetW, signed int offsetH) {}

        // ------------------------------------------------------------------------------------

        // Выход генератора: по 4 чанка каждой карты (индекс 0..3 = чанки 1..4 оригинала) плюс
        // выпавший бросок ширины полос — лаба печатает его для приёмки «обе ширины наблюдаются».
        public sealed class Result
        {
            public readonly ImageTexture[] Diffuse = new ImageTexture[4];
            public readonly ImageTexture[] Specular = new ImageTexture[4];
            public readonly ImageTexture[] Normal = new ImageTexture[4];
            public float GrassNormalRepeatMultiplier;
        }

        private sealed class ChunkData
        {
            public byte[] Diffuse = System.Array.Empty<byte>();
            public byte[] Specular = System.Array.Empty<byte>();
            public byte[] Normal = System.Array.Empty<byte>();
        }

        // :289-384 CreateChunk минус загрузка в ресурсы (:347-380 — см. шапку класса): чанк
        // считает три битмапа. Гоняется параллельно, single fastrandseed — как в оригинале.
        private static ChunkData CreateChunk(int i, int resX, int resY,
            int resSpecularX, int resSpecularY, int resNormalX, int resNormalY,
            float grassNormalRepeatMultiplier)
        {
            int offsetW, offsetH; // :291-295
            if (i == 1 || i == 3) offsetW = -1; else offsetW = 0;
            if (i == 1 || i == 2) offsetH = -1; else offsetH = 0;

            var chunk = new ChunkData
            {
                Diffuse = new byte[resX * resY * 3],
                Specular = new byte[resSpecularX * resSpecularY * 3],
                Normal = new byte[resNormalX * resNormalY * 3],
            };

            for (int x = 0; x < resX; x++) // :310-316
            {
                for (int y = 0; y < resY; y++)
                {
                    float xCoord = x / (resX * 1.0f) * GpfPitch.PitchFullHalfW
                        + GpfPitch.PitchFullHalfW * offsetW; // :312
                    float yCoord = y / (resY * 1.0f) * GpfPitch.PitchFullHalfH
                        + GpfPitch.PitchFullHalfH * offsetH; // :313
                    GetPitchDiffuseColor(xCoord, yCoord, out byte r, out byte g, out byte b);
                    int idx = (y * resX + x) * 3;
                    chunk.Diffuse[idx] = r; chunk.Diffuse[idx + 1] = g; chunk.Diffuse[idx + 2] = b;
                }
            }
            // :318 //DrawLines(pitchDiffuseSurf->format, diffuseBitmap, resX, resY, offsetW, offsetH);
            // :320 //DrawMud(pitchDiffuseSurf->format, diffuseBitmap, resX, resY, offsetW, offsetH);
            for (int x = 0; x < resSpecularX; x++) // :321-327
            {
                for (int y = 0; y < resSpecularY; y++)
                {
                    float xCoord = x / (resSpecularX * 1.0f) * GpfPitch.PitchFullHalfW
                        + GpfPitch.PitchFullHalfW * offsetW; // :323
                    float yCoord = y / (resSpecularY * 1.0f) * GpfPitch.PitchFullHalfH
                        + GpfPitch.PitchFullHalfH * offsetH; // :324
                    GetPitchSpecularColor(xCoord, yCoord, out byte r, out byte g, out byte b);
                    int idx = (y * resSpecularX + x) * 3;
                    chunk.Specular[idx] = r; chunk.Specular[idx + 1] = g; chunk.Specular[idx + 2] = b;
                }
            }
            for (int x = 0; x < resNormalX; x++) // :329-335
            {
                for (int y = 0; y < resNormalY; y++)
                {
                    float xCoord = x / (resNormalX * 1.0f) * GpfPitch.PitchFullHalfW
                        + GpfPitch.PitchFullHalfW * offsetW; // :331
                    float yCoord = y / (resNormalY * 1.0f) * GpfPitch.PitchFullHalfH
                        + GpfPitch.PitchFullHalfH * offsetH; // :332
                    GetPitchNormalColor(xCoord, yCoord, grassNormalRepeatMultiplier,
                        out byte r, out byte g, out byte b);
                    int idx = (y * resNormalX + x) * 3;
                    chunk.Normal[idx] = r; chunk.Normal[idx + 1] = g; chunk.Normal[idx + 2] = b;
                }
            }

            return chunk;
        }

        // Чтение входной текстуры в массивы модуля (:388-419). Импортированный ресурс
        // разжимается и приводится к RGBA8, чтение — прямым индексом в данные.
        private static Image LoadRgba(string path)
        {
            var image = GD.Load<Texture2D>(path).GetImage();
            if (image.IsCompressed()) image.Decompress();
            image.Convert(Image.Format.Rgba8);
            return image;
        }

        // :386-470 GeneratePitch. presentationRng — ЕДИНСТВЕННОЕ обращение к презентационному
        // ГСЧ: бросок ширины полос покоса (:455). Разрешения передаёт вызывающий
        // (release-ветка match.cpp:223 — 2048/1024, 1024/512, 2048/1024 на чанк).
        public static Result GeneratePitch(int resX, int resY, int resSpecularX, int resSpecularY,
            int resNormalX, int resNormalY, Gpf.GpfRng presentationRng)
        {
            // Сид fastrandom — от времени. Оригинал сидит раз на процесс (main.cpp:295,
            // fastrandomseed()); у нас — раз на генерацию, источник тот же.
            FastRandomSeed();

            // seamlessgrass08.png (:388-401)
            Image seamless = LoadRgba(SeamlessPng);
            _seamlessTexW = seamless.GetWidth();
            _seamlessTexH = seamless.GetHeight();
            _seamlessTex = new Vector3[_seamlessTexW * _seamlessTexH];
            byte[] seamlessData = seamless.GetData();
            for (int x = 0; x < _seamlessTexW; x++)
            {
                for (int y = 0; y < _seamlessTexH; y++)
                {
                    int idx = (y * _seamlessTexW + x) * 4;
                    _seamlessTex[y * _seamlessTexW + x] = new Vector3(
                        seamlessData[idx], seamlessData[idx + 1], seamlessData[idx + 2]);
                }
            }

            // overlay.png (:403-419) — вся разметка и потёртости приходят отсюда
            Image overlay = LoadRgba(OverlayPng);
            _overlayTexW = overlay.GetWidth();
            _overlayTexH = overlay.GetHeight();
            _overlayTex = new Vector3[_overlayTexW * _overlayTexH];
            _overlayAlphaTex = new float[_overlayTexW * _overlayTexH];
            byte[] overlayData = overlay.GetData();
            for (int x = 0; x < _overlayTexW; x++)
            {
                for (int y = 0; y < _overlayTexH; y++)
                {
                    int idx = (y * _overlayTexW + x) * 4;
                    _overlayTex[y * _overlayTexW + x] = new Vector3(
                        overlayData[idx], overlayData[idx + 1], overlayData[idx + 2]);
                    // :415 — деление на 256, не 255: квирк оригинала, альфа максимум ~0.996
                    _overlayAlphaTex[y * _overlayTexW + x] = overlayData[idx + 3] / 256.0f;
                }
            }

            float scale = 0.06f; // :421

            // :423-424 — сиды от времени, два отдельных обращения, как два time(NULL)
            var perlin1 = new Perlin(4, 0.06f * scale, 0.5f,
                (int)Time.GetUnixTimeFromSystem());          // низкая частота
            var perlin2 = new Perlin(4, 0.14f * scale, 0.5f,
                (int)Time.GetUnixTimeFromSystem() + 139882); // средняя частота
            // :425 — perlin3 закомментирован в оригинале: Perlin(4, 25.4/20.0, 3, 423423)
            _perlinTexW = 1600; // :426
            _perlinTexH = 1000; // :427
            _perlinTex = new float[_perlinTexW * _perlinTexH];

            // «случайная решётка каналов» из синусов (:430-437)
            float noiseFactor = 0.15f; // :432
            float sinScale = 4.0f;     // :433 — меньше = крупнее
            var ynoise = new float[_perlinTexH];
            for (int y = 0; y < _perlinTexH; y++)
            {
                ynoise[y] = (Mathf.Sin(y / (float)_perlinTexH * 13 * sinScale)
                    + Mathf.Sin(y / (float)_perlinTexH * 43 * sinScale)
                    + Mathf.Sin(y / (float)_perlinTexH * 107 * sinScale)
                    + Mathf.Sin(y / (float)_perlinTexH * 245 * sinScale)) * 0.25f; // :436
            }

            for (int x = 0; x < _perlinTexW; x++) // :439-452
            {
                float xnoise = (Mathf.Sin(x / (float)_perlinTexW * 15 * sinScale)
                    + Mathf.Sin(x / (float)_perlinTexW * 41 * sinScale)
                    + Mathf.Sin(x / (float)_perlinTexW * 109 * sinScale)
                    + Mathf.Sin(x / (float)_perlinTexW * 241 * sinScale)) * 0.25f; // :440
                for (int y = 0; y < _perlinTexH; y++)
                {
                    float noise = xnoise * 0.65f + ynoise[y] * 0.35f; // :442
                    noise = BluntMath.Curve(noise * 0.5f + 0.5f, 0.4f) * 2.0f - 1.0f; // :443 — компрессия
                    int idx = y * _perlinTexW + x;
                    _perlinTex[idx] = perlin1.Get(x, y) * 0.4f + perlin2.Get(x, y) * 0.6f; // :445-446
                    _perlinTex[idx] = _perlinTex[idx] * 1.7f + 0.5f; // :447 — перлин в основном в -0.5..0.5, растянуть
                    _perlinTex[idx] += (BluntMath.NormalizedClamp(noise, -0.9f, 0.9f) * 2.0f - 1.0f)
                        * noiseFactor; // :448 — срез с обеих сторон, графический эффект
                    _perlinTex[idx] = Mathf.Clamp(_perlinTex[idx], 0.2f, 0.8f); // :449
                    _perlinTex[idx] = BluntMath.Curve(_perlinTex[idx], 0.4f);   // :450
                }
            }

            // :454-462 — бросок ширины полос ДО спавна потоков, из презентационного ГСЧ (:455);
            // 4 чанка параллельно (boost::thread у оригинала)
            float grassNormalRepeatMultiplier = (presentationRng.Uniform(0f, 1f) > 0.5f) ? 1.0f : 0.5f;
            var tasks = new Task<ChunkData>[4];
            for (int i = 0; i < 4; i++)
            {
                int chunkIndex = i + 1;
                tasks[i] = Task.Run(() => CreateChunk(chunkIndex, resX, resY,
                    resSpecularX, resSpecularY, resNormalX, resNormalY,
                    grassNormalRepeatMultiplier));
            }
            Task.WaitAll(tasks);

            // Аналог перезаписи ресурсов pitch_*_0i.png (:347-380): картинки собираются в
            // ImageTexture на вызывающем потоке; в материалы их ставит оркестратор. Диффуз у
            // оригинала SRGB8 (:363) — 3D-конвейер Godot так же читает альбедо как sRGB;
            // спекуляр и нормаль — RGB8 (:370, :377); мипмапы есть у всех трёх (:363-377).
            var result = new Result { GrassNormalRepeatMultiplier = grassNormalRepeatMultiplier };
            for (int i = 0; i < 4; i++)
            {
                ChunkData chunk = tasks[i].Result;
                result.Diffuse[i] = MakeTexture(chunk.Diffuse, resX, resY);
                result.Specular[i] = MakeTexture(chunk.Specular, resSpecularX, resSpecularY);
                result.Normal[i] = MakeTexture(chunk.Normal, resNormalX, resNormalY);
            }

            // :464-469 — освобождение массивов модуля
            _perlinTex = System.Array.Empty<float>();
            _overlayTex = System.Array.Empty<Vector3>();
            _overlayAlphaTex = System.Array.Empty<float>();
            _seamlessTex = System.Array.Empty<Vector3>();

            return result;
        }

        private static ImageTexture MakeTexture(byte[] rgb, int w, int h)
        {
            var image = Image.CreateFromData(w, h, false, Image.Format.Rgb8, rgb);
            image.GenerateMipmaps();
            return ImageTexture.CreateFromImage(image);
        }
    }
}

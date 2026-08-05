using Godot;
using System.Collections.Generic;

namespace Gpf.Lab
{
    // Презентация матча, портированная ДОСЛОВНО из методов `Match` оригинала: подмена рекламных
    // щитов (`RandomizeAdboards`, match.cpp:526-585) и случайное солнце (`SetRandomSunParams`,
    // match.cpp:493-524). Сюда же тикет 07 положит камеру (`UpdateIngameCamera`, :723).
    // Деформация сетки — тоже методы `Match` (:2140-2215), но со своим состоянием, поэтому
    // живёт отдельным экземплярным классом рядом: `GoalNetting.cs`.
    //
    // Почему не в `Gpf.*`: в оригинале это матч-собственность, и фаза 8 забирает этот файл в
    // настоящий матч-слой ЦЕЛИКОМ. Почему не прошито в оркестратор лабы: тогда переезд означал
    // бы переписывание, а не перенос.
    //
    // Все числа — оригинала, как есть. Оба потребителя кормятся ПРЕЗЕНТАЦИОННЫМ `GpfRng`
    // (второй экземпляр, тикет .scratch/oracle/issues/17-...): геймплейный поток трогать нельзя,
    // иначе нулевой дифф трасс умрёт без ошибки в логике.
    // RefCounted (не static class) — иначе GDScript-проверки не видят скрипт через load();
    // через мост доступны только статические МЕТОДЫ (тот же паттерн, что у GpfPitch).
    public partial class MatchPresentation : RefCounted
    {
        private const string AdboardDir = "res://assets/gpf/media/textures/adboards";

        // Условие оригинала (:569): идент диффуза НАЧИНАЕТСЯ с "ad_placeholder". Идент — базовое
        // имя файла ресурса (resourcemanager.hpp:47), поэтому сравниваем базовое имя.
        private const string PlaceholderPrefix = "ad_placeholder";

        // --- щиты ---------------------------------------------------------------------------

        // Материалы с плейсхолдер-диффузом получают случайную текстуру из набора адбордов.
        // Работает по записям `.ase` ДО сборки материалов: в оригинале подмена тоже происходит
        // на конструкции матча, до первого кадра (match.cpp:182).
        //
        // Порядок обращений к ГСЧ совпадает с оригиналом: тот идёт по объектам стадиона, а
        // ад-объекты лежат в `test.ase` строго по возрастанию `*MATERIAL_REF` (3..25) — значит
        // обход по индексу материала даёт ту же последовательность бросков (23 штуки).
        public static void RandomizeAdboards(List<AseMaterials.Entry> entries, Gpf.GpfRng rng)
        {
            List<string> files = AdboardFiles();
            if (files.Count == 0) return; // :543

            foreach (var entry in entries)
            {
                if (!entry.Diffuse.GetFile().StartsWith(PlaceholderPrefix)) continue;

                // :571. ВНИМАНИЕ, ошибка оригинала переносится как есть: диапазон
                // random(0, size − 1.001) при 16 файлах даёт floor 0..14 — последний файл
                // набора не выбирается НИКОГДА. Это видно глазами (одна реклама не встречается),
                // и «починить» её значит разойтись с эталон-exe.
                int index = (int)Mathf.Floor(rng.Uniform(0f, files.Count - 1.001f));
                entry.Diffuse = $"{AdboardDir}/{files[index]}";
                entry.SpecularAmount = 0.2f;  // :572
                entry.Shininess = 0.1f;       // :573
            }
        }

        // Порт DirectoryParser::Parse("media/textures/adboards", "png", ...) (:534). Сортировка
        // добавлена нами: у оригинала порядок отдаёт файловая система, у нас он обязан быть
        // воспроизводимым, иначе один и тот же сид даёт разные щиты на разных машинах.
        private static List<string> AdboardFiles()
        {
            var files = new List<string>();
            foreach (string name in DirAccess.GetFilesAt(AdboardDir))
                if (name.EndsWith(".png")) files.Add(name);
            files.Sort(System.StringComparer.Ordinal);
            return files;
        }

        // Мост для GDScript-проверок: List<Entry> через CSharpScript не передать.
        public static Godot.Collections.Array<Godot.Collections.Dictionary> DescribeAdboards(
            string asePath, ulong seed)
        {
            List<AseMaterials.Entry> entries = AseMaterials.Load(asePath);
            RandomizeAdboards(entries, new Gpf.GpfRng(seed));
            return AseMaterials.Describe(entries);
        }

        // --- солнце -------------------------------------------------------------------------

        // Порт SetRandomSunParams (match.cpp:493-524). Позиция солнца — в «их» осях (X — длина
        // поля, Y — ширина, Z — вверх), поэтому узел света обязан жить под `GpfSpace`.
        //
        // ОТСТУПЛЕНИЕ: у оригинала это точечный свет радиуса 1 000 000 в 10 км от центра, то
        // есть практически направленный; у нас DirectionalLight3D, которому важен только поворот.
        // Позиция всё равно выставляется — дословно, ради читаемости переноса.
        // Второе отступление: цвет оригинала выходит за 1.0 по компонентам (до ~1.8), а Godot
        // держит цвет и яркость раздельно, поэтому вектор разложен на LightColor × LightEnergy;
        // произведение равно формуле оригинала.
        public static void SetRandomSunParams(DirectionalLight3D sun, Gpf.GpfRng rng)
        {
            const float brightness = 1.0f;                 // :497
            const float averageHeightMultiplier = 1.3f;    // :500

            // :501. Диапазон броска шире, чем клампы: солнце чаще оказывается у предела.
            var sunPos = new Vector3(
                Mathf.Clamp(rng.Uniform(-1.7f, 1.7f), -1.0f, 1.0f),
                Mathf.Clamp(rng.Uniform(-1.7f, 1.7f), -1.0f, 1.0f),
                averageHeightMultiplier);
            sunPos = sunPos.Normalized();                  // :502

            // :503 — «солнце чаще со стороны камеры по умолчанию: свет в лицо игрокам читается
            // яснее». `&&` в C++ ленив ПО ПРАВОМУ операнду, поэтому бросок делается всегда —
            // порядок обращений к ГСЧ от результата не зависит.
            float sideRoll = rng.Uniform(0f, 1f);
            if (sideRoll > 0.5f && sunPos.Y > 0.25f) sunPos.Y = -sunPos.Y;

            sun.Position = sunPos * 10000.0f;              // :504

            // :506-508 — радиус 1 000 000 у точечного света оригинала. У DirectionalLight3D
            // радиуса нет: перенос сохранён комментарием, а не мёртвым полем.

            Vector3 sunColorNoon = new Vector3(0.9f, 0.8f, 1.0f) * 1.4f;  // :510
            Vector3 sunColorDusk = new Vector3(1.4f, 0.9f, 0.7f) * 1.2f;  // :511

            float noonBias = Mathf.Pow(
                Gpf.BluntMath.NormalizedClamp(sunPos.Z, 0.5f, 1.0f), 1.2f);          // :513
            Vector3 sunColor = sunColorNoon * noonBias + sunColorDusk * (1.0f - noonBias); // :514

            var randomAddition = new Vector3(
                rng.Uniform(-0.1f, 0.1f), rng.Uniform(-0.1f, 0.1f), rng.Uniform(-0.1f, 0.1f));
            randomAddition *= 1.2f;                        // :517
            sunColor += randomAddition;                    // :518
            sunColor *= brightness;                        // :523

            // Ориентация: локальная −Z узла — куда свет идёт, значит +Z смотрит на солнце.
            // Вектор «вверх» для LookingAt задаёт только крен (для направленного света он ни на
            // что не влияет); берём «их» верх, а на почти-зенитном солнце — «их» ширину, иначе
            // базис вырожден.
            Vector3 up = Mathf.Abs(sunPos.Z) > 0.999f ? new Vector3(0, 1, 0) : new Vector3(0, 0, 1);
            sun.Basis = Basis.LookingAt(-sunPos, up);

            float energy = Mathf.Max(sunColor.X, Mathf.Max(sunColor.Y, sunColor.Z));
            sun.LightColor = energy > 0f
                ? new Color(sunColor.X / energy, sunColor.Y / energy, sunColor.Z / energy)
                : new Color(0f, 0f, 0f);
            sun.LightEnergy = energy;
        }
    }
}

using Godot;
using System.Collections.Generic;
using System.Globalization;

namespace Gpf.Lab
{
    // Материалы стадиона приходят в рантайм ТАК ЖЕ, КАК В ОРИГИНАЛЕ: `.glb` несёт только
    // геометрию и имена слотов `mat<NN>`, а карты и скаляры читаются из `*MATERIAL_LIST`
    // версионированного `.ase` при загрузке сцены (зеркало `aseloader.cpp:39-98`).
    //
    // Почему не запечь текстуры в `.glb`: генератору газона (тикет 04) нужно писать свои
    // картинки в материалы поля, а подмена щитов (`RandomizeAdboards`, тикет 09) — заменять
    // диффуз по имени файла. Оба невозможны, если карты зашиты в ассет.
    //
    // Один источник правды — сам `.ase`: по нему же `check_gpf_stadium.gd` сверяет набор
    // материалов, а `check_gpf_ase_materials.gd` — карты, скаляры и назначение по слотам.
    public partial class AseMaterials : RefCounted
    {
        // Отсутствующий MAP_DIFFUSE оригинал подменяет строкой "orange.jpg" (aseloader.cpp:78)
        // и резолвит её по БАЗОВОМУ имени через ResourceManager (resourcemanager.hpp:47).
        // У нас файл лежит в textures/, поэтому путь задан явно.
        public const string DiffuseFallback = "res://assets/gpf/media/textures/orange.jpg";

        // Пути в *BITMAP записаны от каталога data/ оригинала ("media/..."), наш зеркальный
        // корень — assets/gpf/ (тикет 01).
        private const string MediaRoot = "res://assets/gpf/";

        // Геометрический проход оригинала отбрасывает фрагмент по альфе диффуза
        // (`data/media/shaders/simple.frag:27`, `if (base.a < 0.12) discard;`) — это касается
        // ВСЕЙ геометрии, а не выбранных материалов. Без него сетка ворот и трибуны рисуются
        // сплошными прямоугольниками.
        private const float AlphaScissor = 0.12f;

        public sealed class Entry
        {
            public string Name = "";
            public string Diffuse = "";
            public string Bump = "";
            public string Shine = "";
            public string SelfIllum = "";
            public float Shininess;        // *MATERIAL_SHINE
            public float SpecularAmount;   // *MATERIAL_SHINESTRENGTH
            public float SelfIllumination; // *MATERIAL_SELFILLUM
        }

        // Разбор `*MATERIAL_LIST`. Порядок списка = `*MATERIAL_REF` объектов = номер слота
        // `mat<NN>` в `.glb`. Читается только шапка файла: за первым `*GEOMOBJECT` материалов нет.
        public static List<Entry> Load(string asePath)
        {
            var result = new List<Entry>();
            using var file = FileAccess.Open(asePath, FileAccess.ModeFlags.Read);
            if (file == null)
            {
                GD.PushError($"AseMaterials: не открыть {asePath} ({FileAccess.GetOpenError()})");
                return result;
            }

            Entry? current = null;
            string pendingMap = "";
            int expected = -1;

            while (!file.EofReached())
            {
                string line = file.GetLine().StripEdges();
                if (line.Length == 0) continue;

                if (line.StartsWith("*GEOMOBJECT")) break;

                string tag = Tag(line);
                switch (tag)
                {
                    case "*MATERIAL_COUNT":
                        expected = (int)ParseFloat(Value(line));
                        break;
                    case "*MATERIAL":
                        current = new Entry();
                        result.Add(current);
                        pendingMap = "";
                        break;
                    case "*MATERIAL_NAME":
                        if (current != null) current.Name = Quoted(line);
                        break;
                    case "*MAP_DIFFUSE":
                    case "*MAP_BUMP":
                    case "*MAP_SHINE":
                    case "*MAP_SELFILLUM":
                        pendingMap = tag;
                        break;
                    case "*BITMAP":
                        if (current != null && pendingMap.Length > 0)
                        {
                            string path = Resolve(Quoted(line));
                            switch (pendingMap)
                            {
                                case "*MAP_DIFFUSE": current.Diffuse = path; break;
                                case "*MAP_BUMP": current.Bump = path; break;
                                case "*MAP_SHINE": current.Shine = path; break;
                                case "*MAP_SELFILLUM": current.SelfIllum = path; break;
                            }
                            pendingMap = "";
                        }
                        break;
                    case "*MATERIAL_SHINE":
                        if (current != null) current.Shininess = ParseFloat(Value(line));
                        break;
                    case "*MATERIAL_SHINESTRENGTH":
                        if (current != null) current.SpecularAmount = ParseFloat(Value(line));
                        break;
                    case "*MATERIAL_SELFILLUM":
                        if (current != null) current.SelfIllumination = ParseFloat(Value(line));
                        break;
                }
            }

            foreach (var entry in result)
                if (entry.Diffuse.Length == 0) entry.Diffuse = DiffuseFallback; // :78

            if (expected >= 0 && result.Count != expected)
                GD.PushError($"AseMaterials: {asePath} — *MATERIAL_COUNT {expected}, "
                    + $"а разобрано {result.Count}");
            return result;
        }

        // Строит материал Godot по записи `.ase`.
        //
        // ОТСТУПЛЕНИЕ, неизбежное: у оригинала отложенный рендер со своим шейдером
        // (`simple.frag`), где materialparams = (shininess, specular_amount, self_illumination)
        // складываются в G-буфер, а у Godot — PBR. Числа переносятся как есть, но смысл каналов
        // сходится лишь приблизительно:
        //   shininess (глянцевость 3ds Max) → Roughness = 1 − shininess;
        //   specular_amount               → MetallicSpecular (уровень блика);
        //   self_illumination             → Emission.
        // Карта MAP_SHINE у оригинала модулирует ИМЕННО specular_amount (`simple.frag:35`),
        // а в StandardMaterial3D слота «карта блика» нет — карта разбирается, но не подключается.
        public static StandardMaterial3D Build(Entry entry)
        {
            var mat = new StandardMaterial3D
            {
                ResourceName = entry.Name,
                AlbedoTexture = LoadTexture(entry.Diffuse),
                Roughness = Mathf.Clamp(1f - entry.Shininess, 0f, 1f),
                MetallicSpecular = Mathf.Clamp(entry.SpecularAmount, 0f, 1f),
                // Порог оригинала, общий для всей геометрии (simple.frag:27).
                Transparency = BaseMaterial3D.TransparencyEnum.AlphaScissor,
                AlphaScissorThreshold = AlphaScissor,
            };

            var bump = LoadTexture(entry.Bump);
            if (bump != null)
            {
                mat.NormalEnabled = true;
                mat.NormalTexture = bump;
            }

            var illum = LoadTexture(entry.SelfIllum);
            if (illum != null)
            {
                mat.EmissionEnabled = true;
                mat.EmissionTexture = illum;
            }
            else if (entry.SelfIllumination > 0f)
            {
                mat.EmissionEnabled = true;
                mat.EmissionEnergyMultiplier = entry.SelfIllumination;
            }
            return mat;
        }

        // Назначает материалы поверхностям загруженного `.glb` по имени слота `mat<NN>`.
        // Возвращает число назначенных поверхностей. Материал ставится ПЕРЕКРЫТИЕМ
        // (surface override), а не в сам ресурс меша: меш импортирован и разделяется между
        // экземплярами сцены.
        public static int Apply(Node sceneRoot, string asePath)
            => ApplyEntries(sceneRoot, Load(asePath), asePath);

        // То же, но по УЖЕ разобранным записям: между разбором и назначением вклинивается
        // подмена рекламных щитов (MatchPresentation.RandomizeAdboards) — в оригинале она тоже
        // правит материалы до первого кадра, а не готовые меши.
        public static int ApplyEntries(Node sceneRoot, List<Entry> entries, string asePath = "")
        {
            if (entries.Count == 0) return 0;

            var built = new StandardMaterial3D?[entries.Count];
            var meshes = new List<MeshInstance3D>();
            Collect(sceneRoot, meshes);

            int applied = 0;
            foreach (var mi in meshes)
            {
                if (mi.Mesh == null) continue;
                for (int s = 0; s < mi.Mesh.GetSurfaceCount(); s++)
                {
                    Material? slot = mi.Mesh.SurfaceGetMaterial(s);
                    int index = SlotIndex(slot?.ResourceName ?? "");
                    if (index < 0 || index >= entries.Count)
                    {
                        GD.PushWarning($"AseMaterials: {mi.Name}#{s} — слот "
                            + $"'{slot?.ResourceName}' не разбирается как mat<NN> по {asePath}");
                        continue;
                    }
                    StandardMaterial3D material = built[index] ??= Build(entries[index]);
                    mi.SetSurfaceOverrideMaterial(s, material);
                    applied++;
                }
            }
            return applied;
        }

        // Мост для GDScript-проверок: статические методы через CSharpScript видны, а List<Entry>
        // и StandardMaterial3D-фабрика — нет.
        public static Godot.Collections.Array<Godot.Collections.Dictionary> Describe(string asePath)
            => Describe(Load(asePath));

        public static Godot.Collections.Array<Godot.Collections.Dictionary> Describe(
            List<Entry> entries)
        {
            var array = new Godot.Collections.Array<Godot.Collections.Dictionary>();
            foreach (var e in entries)
            {
                array.Add(new Godot.Collections.Dictionary
                {
                    { "name", e.Name },
                    { "diffuse", e.Diffuse },
                    { "bump", e.Bump },
                    { "shine", e.Shine },
                    { "selfillum", e.SelfIllum },
                    { "shininess", e.Shininess },
                    { "specular", e.SpecularAmount },
                    { "illumination", e.SelfIllumination },
                });
            }
            return array;
        }

        // "mat07" → 7; всё прочее → −1.
        private static int SlotIndex(string slotName)
        {
            if (!slotName.StartsWith("mat")) return -1;
            return int.TryParse(slotName.Substring(3), NumberStyles.Integer,
                CultureInfo.InvariantCulture, out int index) ? index : -1;
        }

        private static string Resolve(string bitmap)
        {
            string path = bitmap.Replace('\\', '/');
            int at = path.IndexOf("media/", System.StringComparison.Ordinal);
            return at < 0 ? MediaRoot + "media/" + path : MediaRoot + path.Substring(at);
        }

        private static Texture2D? LoadTexture(string path)
        {
            if (path.Length == 0) return null;
            if (!ResourceLoader.Exists(path))
            {
                GD.PushWarning($"AseMaterials: нет текстуры {path}");
                return null;
            }
            return GD.Load<Texture2D>(path);
        }

        private static void Collect(Node node, List<MeshInstance3D> into)
        {
            if (node is MeshInstance3D hit) into.Add(hit);
            foreach (var child in node.GetChildren()) Collect(child, into);
        }

        private static string Tag(string line)
        {
            int space = line.IndexOf(' ');
            int tab = line.IndexOf('\t');
            int end = space < 0 ? tab : (tab < 0 ? space : Mathf.Min(space, tab));
            return end < 0 ? line : line.Substring(0, end);
        }

        private static string Value(string line)
        {
            string[] parts = line.Split(new[] { ' ', '\t' },
                System.StringSplitOptions.RemoveEmptyEntries);
            return parts.Length > 1 ? parts[1] : "";
        }

        private static string Quoted(string line)
        {
            int first = line.IndexOf('"');
            int last = line.LastIndexOf('"');
            return (first < 0 || last <= first) ? "" : line.Substring(first + 1, last - first - 1);
        }

        private static float ParseFloat(string s) =>
            float.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out float v) ? v : 0f;
    }
}

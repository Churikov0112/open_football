using Godot;
using System.Collections.Generic;

namespace Gpf.Lab
{
    // Видимое тело для лаб-сцен: оригинальный игрок GameplayFootball, собранный
    // tools/build_gpf_fullbody.py на тех же 14 костях. ВРЕМЕННАЯ заглушка вместо
    // палочника — смаггл, точку касания и зазор нога-мяч на палках не оценить.
    // Своя модель (MPFB2, gpf_makehuman.glb) сюда не подключается, см. вики
    // «презентация-и-ассеты».
    //
    // Общий код на три лабы: anim_lab, ball_lab, walk_lab. Нет файла — вызывающий
    // работает палочником, как раньше.
    public static class LabBody
    {
        public const string Path = "res://assets/models/gpf_fullbody.glb";

        private static readonly StandardMaterial3D Flat = new()
        {
            AlbedoColor = new Color(0.72f, 0.70f, 0.68f),
            Roughness = 0.65f,
        };

        // Экспорт Z-вверх (export_yup=False), поэтому модель встаёт прямо под
        // GpfSpace без доворотов. Меш собран из 12 частей — забираем ВСЕ, иначе
        // заливка и скрытие достанутся одной двенадцатой.
        public static Skeleton3D? Load(Node3D parent, List<MeshInstance3D> parts)
        {
            if (!ResourceLoader.Exists(Path)) return null;
            var inst = GD.Load<PackedScene>(Path).Instantiate<Node3D>();
            parent.AddChild(inst);
            var skel = Find(inst);
            if (skel == null) { inst.QueueFree(); return null; }
            Collect(skel, parts);
            return skel;
        }

        // Зазоры и силуэт по текстурам читаются хуже, чем по ровной заливке: за
        // форму принимается рисунок.
        public static void SetFlat(List<MeshInstance3D> parts, bool flat)
        {
            foreach (var part in parts) part.MaterialOverride = flat ? Flat : null;
        }

        public static string Hint(List<MeshInstance3D> parts)
            => parts.Count == 0 ? "" : "   M меш/кости   T текстуры/заливка";

        private static Skeleton3D? Find(Node node)
        {
            if (node is Skeleton3D hit) return hit;
            foreach (var child in node.GetChildren())
            {
                var found = Find(child);
                if (found != null) return found;
            }
            return null;
        }

        private static void Collect(Node node, List<MeshInstance3D> into)
        {
            if (node is MeshInstance3D hit) into.Add(hit);
            foreach (var child in node.GetChildren()) Collect(child, into);
        }
    }
}

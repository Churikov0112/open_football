# Геометрия стадиона GameplayFootball (.ase, Apache 2.0) → четыре .glb для лаб порта.
#
# Что собирается:
#   test.ase    (1642 объекта, 31 материал) → gpf_stadium.glb — трибуны, стены, щиты
#   pitch.ase   (4 квадранта)               → gpf_pitch.glb   — рамка поля под газон
#   goals.ase   (18 объектов, 2 материала)  → gpf_goals.glb   — штанги и сетка
#   generic.ase (1 объект)                  → gpf_ball.glb    — мяч
#
# Читает исходники ИЗ РЕПОЗИТОРИЯ (assets/gpf/media/, тикет 01) — второй проект на диске
# для сборки не нужен.
#
# ОСИ. Сцена порта живёт в «их» пространстве: X — длина поля, Y — ширина, Z — вверх.
# Автоконверсию glTF в Y-up давит `export_yup=False`, так что координаты в .glb совпадают
# с *MESH_VERTEX оригинала один в один (проверяет tests/check_gpf_stadium.gd). Прецедент —
# tools/build_gpf_fullbody.py.
#
# ПОЗИЦИИ УЗЛОВ. *TM_POS/*TM_ROW3 игнорируются: оригинал их не читает, вершины уже мировые
# (aseloader.cpp кладёт vertex_cache как есть). А вот ПОВОРОТ узла (*TM_ROW0..2) применяется
# к НОРМАЛЯМ (aseloader.cpp:227-239) — и это не косметика: двусторонние панели сетки ворот
# сделаны одной геометрией с противоположными строками TM_ROW2, и без поворота нормали
# совпадут, а экспортёр склеит панели в одну — сетка потеряет половину вершин.
#
# МАТЕРИАЛЫ. Объекты клеятся ПО МАТЕРИАЛУ: один меш на *MATERIAL_REF (SplitGeometry
# оригинала — движковый CPU-куллинг, не портируется). Слот материала называется `mat<NN>`,
# где NN — индекс в *MATERIAL_LIST; имя объекта несёт ещё и читаемое имя материала.
# Карты и скаляры В .GLB НЕ ЕДУТ: текстуры назначает рантайм-загрузчик лабы, иначе
# генератору газона некуда писать (решение 6 спеки фазы 7).
#
# ODE-коллизия из .object игнорируется — отскок считает Gpf.Ball.
#
# ВОСПРОИЗВОДИМОСТЬ: повторный прогон на Blender 5.1.2 (hash ec6e62d40fa9) даёт .glb,
# проходящий tests/check_gpf_stadium.gd. Побайтовая идентичность не требуется и не проверяется.
#
# Запуск (без аргументов собирает все четыре; можно перечислить имена .glb):
#   & "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background \
#       --python tools/build_gpf_stadium.py
# Godot новые .glb сам не подхватит — после сборки нужен проход импорта, иначе
# ResourceLoader.exists() говорит «нет файла»:
#   & "<godot exe>" --path "<repo>" --headless --import

import os
import sys
import importlib.util

import bpy
from mathutils import Vector

BLENDER_PINNED = (5, 1, 2)

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)
MEDIA = os.path.join(REPO, "assets", "gpf", "media")
MODELS = os.path.join(REPO, "assets", "models")

TARGETS = [
    ("objects/stadiums/test/test.ase", "gpf_stadium.glb"),
    ("objects/stadiums/test/pitch.ase", "gpf_pitch.glb"),
    ("objects/stadiums/goals.ase", "gpf_goals.glb"),
    ("objects/balls/generic.ase", "gpf_ball.glb"),
]

# Порог `PrepareGoalNetting` (match.cpp:2149-2151): pitchHalfW + 0.06, отсекает штанги.
# Тут используется только для отчёта — проверяет число check_gpf_stadium.gd.
NETTING_THRESHOLD = 55.06


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(TOOLS, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ase = _load("import_gpf_fullbody")


def rotate_normal(n, rows):
    """Нормаль узла в мировые. Оригинал: normal *= rotation_matrix (aseloader.cpp:255),
    а Vector3::operator*=(Matrix3) (vector3.cpp:107-112) — это СТРОКА-вектор на матрицу,
    то есть линейная комбинация строк TM_ROW0..2. Строки нормируются (aseloader.cpp:237-239).
    """
    if not rows:
        return Vector(n)
    v = Vector((0.0, 0.0, 0.0))
    for k in range(3):
        v += Vector(rows[k]) * n[k]
    return v


def normalized_rows(tm):
    """Три строки *TM_ROW0..2, нормированные. Пустой список, если узел их не дал."""
    rows = []
    for row in tm[:3]:
        v = Vector(row)
        rows.append(v.normalized() if v.length > 1e-9 else Vector((0.0, 0.0, 0.0)))
    return rows if len(rows) == 3 else []


def merge_by_material(objects, material_index, material_name):
    """Объекты одного *MATERIAL_REF → один меш. Вершины НЕ свариваются: счёт вершин сетки
    ворот на сторону — контрактное число приёмки (1138), сварка его уронит."""
    verts = []
    faces = []
    loop_uvs = []
    loop_normals = []

    for obj in objects:
        base = len(verts)
        verts.extend(obj["verts"])
        rows = normalized_rows(obj["tm"])
        has_uv = bool(obj["tfaces"]) and bool(obj["uvs"])

        for face_i, face in enumerate(obj["faces"]):
            faces.append((face[0] + base, face[1] + base, face[2] + base))

            normals = obj["normals"].get(face_i)
            for corner in range(3):
                if normals and len(normals) == 3:
                    loop_normals.append(rotate_normal(normals[corner], rows).normalized())
                else:
                    # Оригинал считает отсутствие MESH_NORMALS фатальным
                    # (aseloader.cpp:158-159); мы не падаем, но и не выдумываем.
                    loop_normals.append(Vector((0.0, 0.0, 1.0)))

            if has_uv:
                tface = obj["tfaces"][face_i]
                for corner in range(3):
                    loop_uvs.append(obj["uvs"][tface[corner]])
            else:
                loop_uvs.extend([(0.0, 0.0)] * 3)

    name = "mat%02d_%s" % (material_index, sanitize(material_name))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.validate()

    # Ловушка: validate() выкидывает вырожденные грани, и тогда поугловые массивы UV и
    # нормалей разъезжаются с полигонами. Молча этого допускать нельзя.
    if len(mesh.polygons) != len(faces):
        raise SystemExit("%s: validate() оставил %d граней из %d — поугловые данные "
                         "разъехались" % (name, len(mesh.polygons), len(faces)))

    layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        poly.use_smooth = True
        for loop_i in poly.loop_indices:
            layer.data[loop_i].uv = loop_uvs[loop_i]

    mesh.normals_split_custom_set([tuple(n) for n in loop_normals])
    mesh.update()

    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)

    # Материал — пустышка, несущая только ИМЯ: карты и скаляры читает рантайм-загрузчик
    # лабы из *MATERIAL_LIST того же .ase. Никаких текстурных нод, иначе они запекутся
    # в .glb и переживут подмену материала (в том числе газонную).
    mat = bpy.data.materials.new("mat%02d" % material_index)
    ob.data.materials.append(mat)
    return ob


def sanitize(name):
    return "".join(c if c.isalnum() else "_" for c in name).strip("_").lower()


def build(rel, out_name):
    src = os.path.join(MEDIA, rel.replace("/", os.sep))
    if not os.path.exists(src):
        raise SystemExit("нет исходника %s — сначала тикет 01" % src)

    bpy.ops.wm.read_factory_settings(use_empty=True)

    materials = ase.parse_materials(src)
    objects = [o for o in ase.parse_ase(src) if o["verts"] and o["faces"]]

    by_material = {}
    for obj in objects:
        by_material.setdefault(obj["material"], []).append(obj)

    unknown = [ref for ref in by_material if ref < 0 or ref >= len(materials)]
    if unknown:
        raise SystemExit("%s: объекты ссылаются на несуществующие материалы %s"
                         % (rel, sorted(unknown)))

    print("\n=== %s: %d объектов, %d материалов ===" % (rel, len(objects), len(materials)))
    parts = []
    for ref in sorted(by_material):
        ob = merge_by_material(by_material[ref], ref, materials[ref]["name"])
        parts.append(ob)
        print("  %-34s из %4d объектов: %6d вершин, %6d граней"
              % (ob.name, len(by_material[ref]), len(ob.data.vertices),
                 len(ob.data.polygons)))

    missing = [i for i in range(len(materials)) if i not in by_material]
    if missing:
        print("  !! материалы без единого объекта: %s — check_gpf_stadium это завалит"
              % missing)

    report(parts)

    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)

    out_path = os.path.join(MODELS, out_name)
    bpy.ops.export_scene.gltf(
        filepath=out_path, export_format="GLB", export_yup=False,
        use_selection=True, export_animations=False, export_skins=False,
        export_normals=True, export_texcoords=True, export_materials="EXPORT",
    )
    print("  сохранено: %s" % out_path)


def report(parts):
    lo = [1e30] * 3
    hi = [-1e30] * 3
    total = 0
    netting = {"-": 0, "+": 0}
    for p in parts:
        for v in p.data.vertices:
            for k in range(3):
                lo[k] = min(lo[k], v.co[k])
                hi[k] = max(hi[k], v.co[k])
            total += 1
            if abs(v.co.x) > NETTING_THRESHOLD:
                netting["-" if v.co.x < 0 else "+"] += 1
    print("  габарит: X %.3f..%.3f  Y %.3f..%.3f  Z %.3f..%.3f, вершин %d"
          % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], total))
    if netting["-"] or netting["+"]:
        print("  вершин за |x| > %.2f: %d слева, %d справа"
              % (NETTING_THRESHOLD, netting["-"], netting["+"]))


def main():
    if bpy.app.version[:3] != BLENDER_PINNED:
        print("!! Blender %s, скрипт зафиксирован на %s — результат не гарантирован"
              % (".".join(str(x) for x in bpy.app.version[:3]),
                 ".".join(str(x) for x in BLENDER_PINNED)))

    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    wanted = set(argv)

    for rel, out_name in TARGETS:
        if wanted and out_name not in wanted:
            continue
        build(rel, out_name)


if __name__ == "__main__":
    main()

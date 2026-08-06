# Метрика силуэта для СОБРАННОГО .glb со скином — общая линейка веток.
#
# gpf_fit.py меряет болванку, которую строит сам, и другой моделью его не
# накормить. Здесь замеряется готовый ассет, поэтому MPFB2-тело и Hunyuan-тело
# проходят через один и тот же код: разница в числах — разница геометрии, а не
# двух реализаций замера (решено 2026-08-04, ветка Hunyuan).
#
# Поза — те же 15° отведения, что просили у референса: в рест-позе руки висят
# вплотную к торсу, сегмент строки не делится, и ширину торса измерить нечем.
#
# Запуск:
#   & "<blender>" --background --python tools/gpf_fit_model.py -- \
#       "<repo>/assets/models/gpf_hunyuan.glb" "<repo>/assets/refs/ref_front.png" "<out_dir>"

import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import gpf_silhouette  # noqa: E402
import gpf_style  # noqa: E402

ARM_ABDUCTION_DEG = 15.0     # столько же, сколько просили у референса

ANATOMICAL_LABELS = [
    "плечи", "грудь", "грудь низ", "рёбра", "талия", "живот", "таз", "пах",
    "бедро верх", "бедро", "бедро низ", "колено", "голень", "икра",
    "голень низ", "лодыжка",
]


def fill_interior(mask):
    """Заливает дырки внутри силуэта, оставляя щель между ногами.

    Референсы из assets/refs сняты на сером фоне, и костюм фигуры почти в тон:
    порог gpf_silhouette даёт не залитый силуэт, а только кромки и складки —
    маска рассыпается на 8 сегментов поперёк тела, и landmarks принимает дырку
    на животе за пах (проверено на ref_front.png 2026-08-04).

    Фон заливается от рамки обрезанного bbox: всё, куда заливка не дошла, —
    внутренность тела. Щель между ногами открыта снизу, поэтому переживает.
    """
    import numpy as np

    rows = np.flatnonzero(mask.any(axis=1))
    cols = np.flatnonzero(mask.any(axis=0))
    if rows.size == 0:
        return mask
    y0, y1 = max(0, rows[0] - 2), min(mask.shape[0], rows[-1] + 3)
    x0, x1 = max(0, cols[0] - 2), min(mask.shape[1], cols[-1] + 3)
    crop = mask[y0:y1, x0:x1]

    free = ~crop
    outside = np.zeros_like(crop)
    outside[0, :] = outside[-1, :] = True
    outside[:, 0] = outside[:, -1] = True
    outside &= free
    while True:
        grown = outside.copy()
        grown[1:, :] |= outside[:-1, :]
        grown[:-1, :] |= outside[1:, :]
        grown[:, 1:] |= outside[:, :-1]
        grown[:, :-1] |= outside[:, 1:]
        grown &= free
        if grown.sum() == outside.sum():
            break
        outside = grown

    filled = mask.copy()
    filled[y0:y1, x0:x1] = crop | (free & ~outside)
    return filled


def import_upright(path):
    """Импорт .glb + разворот в вертикаль (у нас export_yup=False)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before]

    meshes = [o for o in objs if o.type == "MESH"]
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    span_y = max(p.y for p in pts) - min(p.y for p in pts)
    span_z = max(p.z for p in pts) - min(p.z for p in pts)
    if span_y > span_z:
        rot = Matrix.Rotation(math.radians(-90), 4, "X")
        for o in objs:
            if o.parent is None:
                o.matrix_world = rot @ o.matrix_world
        bpy.context.view_layer.update()
    return objs


def a_pose(arm_obj, angle_deg=ARM_ABDUCTION_DEG):
    """Отводит руки от корпуса. Знак отрицательный: рука висит вдоль −Z, и
    поворот на +θ вокруг Y уводит её внутрь торса (грабля gpf_fit)."""
    angle = math.radians(angle_deg)
    for side, sign in (("left", 1.0), ("right", -1.0)):
        pb = arm_obj.pose.bones[f"{side}_shoulder"]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((0.0, 1.0, 0.0), -sign * angle)
    bpy.context.view_layer.update()


def silhouette_material(body):
    """Эмиссивный белый: силуэт снимается БЕЗ освещения, иначе затенённые бока
    уходят в фон и маска рвётся."""
    mat = bpy.data.materials.new("silhouette")
    mat.use_nodes = True
    tree = mat.node_tree
    tree.nodes.clear()
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(emission.outputs[0], output.inputs[0])
    body.data.materials.clear()
    body.data.materials.append(mat)


def shoot_silhouette(model_path, out_dir):
    """Рендерит силуэт модели и возвращает путь к PNG."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    objs = import_upright(model_path)
    body = [o for o in objs if o.type == "MESH"][0]
    arms = [o for o in objs if o.type == "ARMATURE"]
    print("модель: %s — %d полигонов, %d вершин, костей %s"
          % (os.path.basename(model_path), len(body.data.polygons),
             len(body.data.vertices),
             len(arms[0].data.bones) if arms else "нет скина"))
    if arms:
        a_pose(arms[0])

    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(depsgraph)
    coords = [evaluated.matrix_world @ v.co for v in evaluated.to_mesh().vertices]
    lo_z, hi_z = min(c.z for c in coords), max(c.z for c in coords)

    silhouette_material(body)
    gpf_style.setup_scene(background=(0.0, 0.0, 0.0))
    shot = os.path.join(out_dir, "fit_%s.png"
                        % os.path.splitext(os.path.basename(model_path))[0])
    gpf_style.render_ortho(shot, lo_z, hi_z, "front")
    return shot


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    model_path = argv[0] if argv else "assets/models/gpf_hunyuan.glb"
    ref_path = argv[1] if len(argv) > 1 else "assets/refs/ref_front.png"
    out_dir = argv[2] if len(argv) > 2 else "."

    for path in (model_path, ref_path):
        if not os.path.exists(path):
            print("нет файла: %s" % path)
            return

    bpy.ops.wm.read_factory_settings(use_empty=True)

    # Эталоном может быть и картинка-референс, и другая модель: сравнение веток
    # между собой не зависит от того, читается ли референс (ref_front.png на
    # сером фоне маску не даёт, см. fill_interior).
    if ref_path.lower().endswith(".glb"):
        ref_shot = shoot_silhouette(ref_path, out_dir)
        ref_label = os.path.basename(ref_path)
    else:
        ref_shot = ref_path
        ref_label = "референс"
    shot = shoot_silhouette(model_path, out_dir)

    # Заливка идёт по ОБЕИМ маскам: для чистого рендера она идемпотентна,
    # для картинки-референса — единственный шанс получить сплошной силуэт.
    our_mask = fill_interior(gpf_silhouette.load_mask(shot))
    ref_mask = fill_interior(gpf_silhouette.load_mask(ref_shot))
    for name, mask in (("модель", our_mask), (ref_label, ref_mask)):
        sh, cr, top, bottom = gpf_silhouette.landmarks(mask)
        h = float(bottom - top + 1)
        print("%-9s размер %dx%d, плечи t=%.3f, пах t=%.3f"
              % (name, mask.shape[1], mask.shape[0], (sh - top) / h, (cr - top) / h))

    ours = gpf_silhouette.anatomical_profile(our_mask)
    reference = gpf_silhouette.anatomical_profile(ref_mask)

    print("\n=== силуэт: модель против референса ===")
    print("u: 0 плечи → 1 пах → 2 стопы. Голова и стопы не сверяются.\n")
    gpf_silhouette.compare(reference, ours, ANATOMICAL_LABELS)


if __name__ == "__main__":
    main()

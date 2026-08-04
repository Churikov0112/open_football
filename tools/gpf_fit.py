# Сверка болванки с референсом по силуэту.
#
# Рендерит тело ортографически в A-позе, извлекает профиль ширин и сравнивает
# с профилем, снятым с референсной картинки. Ответ — не «похоже на 82 %», а
# «на высоте 0.55 талия уже референса на 12 %», то есть сразу видно, какое
# число в PROPORTIONS править.
#
# A-поза обязательна: у референса руки отведены, а в рест-позе болванки они
# прижаты — торс и руки сливаются в один сегмент строки, и ширину торса
# измерить нечем.
#
# Запуск:
#   & "<blender>" --background --python tools/gpf_fit.py -- \
#       "assets/refs/body_front.png" "<out_dir>"

import math
import os
import sys

import bpy
from mathutils import Quaternion

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import build_gpf_blockout as blockout  # noqa: E402
import gpf_silhouette  # noqa: E402
import gpf_style  # noqa: E402
from build_gpf_rig import build, world_heads  # noqa: E402

ARM_ABDUCTION_DEG = 15.0     # столько же, сколько просили у референса

# Голову и стопы у референса не сверяем: голова там заметно крупнее принятой
# стилизации, стопы проработаны детальнее, чем нам нужно. Меряем корпус и
# конечности — там пропорции и мышцы взяты как ориентир.
FIT_RANGE = (0.20, 0.92)

# Подписи уровней — чтобы в отчёте было видно не только число, но и что это.
ANATOMICAL_LABELS = [
    "плечи", "грудь", "грудь низ", "рёбра", "талия", "живот", "таз", "пах",
    "бедро верх", "бедро", "бедро низ", "колено", "голень", "икра",
    "голень низ", "лодыжка",
]


def a_pose(arm_obj):
    """Отвести руки от корпуса, как на референсе."""
    angle = math.radians(ARM_ABDUCTION_DEG)
    for side, sign in (("left", 1.0), ("right", -1.0)):
        bone = arm_obj.pose.bones[f"{side}_shoulder"]
        bone.rotation_mode = "QUATERNION"
        # Ось Y — «вперёд-назад» в пространстве оригинала, вокруг неё рука
        # разводится в стороны. Знак ОТРИЦАТЕЛЬНЫЙ: рука висит вдоль −Z, и
        # поворот на +θ уводит её к оси тела, внутрь торса, а не наружу.
        bone.rotation_quaternion = Quaternion((0.0, 1.0, 0.0), -sign * angle)
    bpy.context.view_layer.update()


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ref_path = argv[0] if argv else "assets/refs/body_front.png"
    out_dir = argv[1] if len(argv) > 1 else "."

    if not os.path.exists(ref_path):
        print("нет референса: %s" % ref_path)
        return

    bpy.ops.wm.read_factory_settings(use_empty=True)
    heads = world_heads()
    arm_obj = build(heads)
    arm_obj.data.bones["player"].use_deform = False

    if blockout.PROPORTIONS["organic"]:
        body, zones = blockout.build_organic(heads)
        blockout.skin_organic(body, zones, arm_obj, heads)
    else:
        body = blockout.skin(blockout.build_parts(heads), arm_obj, heads)
    blockout.straighten(arm_obj)
    a_pose(arm_obj)

    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(depsgraph)
    coords = [evaluated.matrix_world @ v.co for v in evaluated.to_mesh().vertices]
    lo_z = min(c.z for c in coords)
    hi_z = max(c.z for c in coords)

    # Силуэт снимаем БЕЗ освещения: затенённые бока уходили в фон, маска рвалась
    # на куски и «самый широкий сегмент» подхватывал руку вместо торса.
    gpf_style.setup_scene(background=(0.0, 0.0, 0.0))
    mat = bpy.data.materials.new("silhouette")
    mat.use_nodes = True
    tree = mat.node_tree
    tree.nodes.clear()
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(emission.outputs[0], output.inputs[0])
    body.data.materials.append(mat)
    body.material_slots[0].link = "OBJECT"
    body.material_slots[0].material = mat

    shot = os.path.join(out_dir, "fit_front.png")
    gpf_style.render_ortho(shot, lo_z, hi_z, "front")

    our_mask = gpf_silhouette.load_mask(shot)
    ref_mask = gpf_silhouette.load_mask(ref_path)
    for name, mask in (("модель", our_mask), ("референс", ref_mask)):
        sh, cr, top, bottom = gpf_silhouette.landmarks(mask)
        h = float(bottom - top + 1)
        print("%-9s размер %dx%d, плечи t=%.3f, пах t=%.3f, сегментов на плечах %d"
              % (name, mask.shape[1], mask.shape[0], (sh - top) / h, (cr - top) / h,
                 len(gpf_silhouette._row_segments(mask[sh]))))

    ours = gpf_silhouette.anatomical_profile(our_mask)
    reference = gpf_silhouette.anatomical_profile(ref_mask)

    print("\n=== силуэт: модель против референса ===")
    print("u: 0 плечи → 1 пах → 2 стопы. Голова и стопы не сверяются.\n")
    gpf_silhouette.compare(reference, ours, ANATOMICAL_LABELS)


if __name__ == "__main__":
    main()

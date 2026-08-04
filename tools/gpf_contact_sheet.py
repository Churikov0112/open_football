# Контактный лист: несколько вариантов пропорций в одном кадре, рядом.
#
# Смысл — сходимость. Показывать по одному варианту за итерацию медленно и
# нечестно: глаз сравнивает с памятью, а не с альтернативой. Рядом в одном
# кадре, при одном свете и одной камере, разница видна сразу.
#
# Геометрия строится без скиннинга — лист нужен для выбора силуэта, а не для
# проверки деформации (её меряет tests/_probe_deform.gd).
#
# Запуск:
#   & "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background \
#       --python tools/gpf_contact_sheet.py -- "<out>.png"

import copy
import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import build_gpf_blockout as blockout  # noqa: E402
import gpf_anim  # noqa: E402
import gpf_style  # noqa: E402
from build_gpf_rig import BONES, build, world_heads  # noqa: E402

# Поза для оценки: рест не годится — руки висят вплотную и сливаются с торсом.
POSE_CLIP = "assets/gpf/animations/movement/sprint/000_idlelevel1.anim"
POSE_FRAME = 8

SPACING = 0.95   # метры между фигурами

# Каждый вариант — патч поверх базовых PROPORTIONS. Правится только «мясо»:
# длины костей фиксированы скелетом порта и здесь не участвуют.
VARIANTS = [
    ("лофты", {
        "organic": False,
        "head_radius": (0.126, 0.134, 0.144),
        "head_center_z": 1.778,
        "deltoid_r": 0.090,
        "deltoid_out": 0.042,
        "hand_size": (0.038, 0.023, 0.058),
        "profiles.torso": [
            (0.00, 0.148, 0.110), (0.16, 0.136, 0.098), (0.34, 0.118, 0.089),
            (0.60, 0.152, 0.109), (0.84, 0.184, 0.124), (1.00, 0.166, 0.108),
        ],
        "profiles.upperarm": [(0.00, 0.055, 0.055), (0.28, 0.059, 0.058), (1.00, 0.044, 0.043)],
        "profiles.forearm": [(0.00, 0.046, 0.045), (0.18, 0.047, 0.046), (1.00, 0.030, 0.029)],
        "profiles.thigh": [(0.00, 0.101, 0.097), (0.14, 0.104, 0.100), (1.00, 0.065, 0.063)],
    }),
    ("органика", {}),
]

def patched(base, patch):
    """Патч с поддержкой 'profiles.<имя>' — иначе профиль пришлось бы дублировать."""
    out = copy.deepcopy(base)
    for key, value in patch.items():
        if key.startswith("profiles."):
            out["profiles"][key.split(".", 1)[1]] = value
        else:
            out[key] = value
    return out


def build_variant(props, x_offset, material, tracks=None):
    heads = world_heads()
    arm_obj = build(heads)
    arm_obj.data.bones["player"].use_deform = False

    original = blockout.PROPORTIONS
    blockout.PROPORTIONS = props
    try:
        if props.get("organic"):
            body, zones = blockout.build_organic(heads)
            blockout.skin_organic(body, zones, arm_obj, heads)
        else:
            body = blockout.skin(blockout.build_parts(heads), arm_obj, heads)
    finally:
        blockout.PROPORTIONS = original

    blockout.straighten(arm_obj)
    bpy.ops.object.shade_smooth()

    if tracks:
        gpf_anim.apply_pose(arm_obj, tracks, POSE_FRAME, BONES)

    arm_obj.location.x += x_offset      # меш — ребёнок арматуры, едет следом
    body.data.materials.append(material)
    return arm_obj


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_png = argv[0] if argv else "contact_sheet.png"

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = gpf_style.setup_scene()
    material = gpf_style.vinyl_material("vinyl", gpf_style.VINYL["blockout"])

    tracks = None
    if os.path.exists(POSE_CLIP):
        tracks = gpf_anim.load(POSE_CLIP)
        print("поза: %s кадр %d" % (POSE_CLIP, POSE_FRAME))
    else:
        print("клип не найден, рендер в рест-позе: %s" % POSE_CLIP)

    total = len(VARIANTS)
    span = SPACING * (total - 1)
    for i, (label, patch) in enumerate(VARIANTS):
        props = patched(blockout.PROPORTIONS, patch)
        build_variant(props, -span / 2 + i * SPACING, material, tracks)
        print("%d. %s" % (i + 1, label))

    # Дистанцию считаем из угла обзора, а не подбираем: число фигур меняется,
    # и «магическое» расстояние то обрезает головы, то оставляет пустое поле.
    width_px, height_px = 420 * total, 980
    lens, sensor = 70.0, 36.0
    tan_h = (sensor / 2.0) / lens
    tan_v = (sensor * height_px / width_px / 2.0) / lens

    need_w = span + 1.05          # фигуры плюс поля по бокам
    need_h = 2.15                 # рост с запасом на позу
    distance = max(need_w / 2.0 / tan_h, need_h / 2.0 / tan_v) * 1.04

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    target = Vector((0.0, 0.0, 0.98))
    cam.location = (0.0, -distance, target.z)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    scene.render.resolution_x = width_px
    scene.render.resolution_y = height_px
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    print("контактный лист: %s" % out_png)


if __name__ == "__main__":
    main()

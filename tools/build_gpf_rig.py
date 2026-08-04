# Строит «линейку» — арматуру Blender 1:1 по утилитарному скелету порта
# (src/gpf/SkeletonBuilder.cs, он же data/media/objects/players/player.object).
# Это подложка для всей будущей геометрии персонажа: длины костей менять нельзя,
# на них завязаны коллизии мяча и точки касания в ядре порта.
#
# Пространство совпадает у GPF и Blender: Z — вверх, «вперёд» — −Y. Конверсию в
# Godot-оси делает обёртка GpfSpace в рантайме, здесь ничего не поворачиваем.
#
# Запуск:
#   & "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background \
#       --python tools/build_gpf_rig.py -- "<repo>/assets/models/gpf_rig.blend"

import sys
import bpy
from mathutils import Vector

# Смещения относительно родителя — дословно из SkeletonBuilder.cs.
BONES = [
    ("player",         "",               (0, 0, 0)),
    ("body",           "player",         (0, 0, 0.96)),
    ("middle",         "body",           (0, 0, 0.15)),
    ("neck",           "middle",         (0, -0.03, 0.5)),
    ("left_shoulder",  "middle",         (0.16, -0.01, 0.48)),
    ("left_elbow",     "left_shoulder",  (-0.01, 0, -0.33)),
    ("right_shoulder", "middle",         (-0.16, -0.01, 0.48)),
    ("right_elbow",    "right_shoulder", (0.01, 0, -0.33)),
    ("left_thigh",     "body",           (0.087, 0, -0.01)),
    ("left_knee",      "left_thigh",     (0, 0, -0.42)),
    ("left_ankle",     "left_knee",      (0, -0.04, -0.44)),
    ("right_thigh",    "body",           (-0.087, 0, -0.01)),
    ("right_knee",     "right_thigh",    (0, 0, -0.42)),
    ("right_ankle",    "right_knee",     (0, -0.04, -0.44)),
]

# Клип пишет джойнтам ориентацию, а сустав без ребёнка её всё равно получает —
# значит терминальной кости нужен хвост. Направление и длина здесь выбраны под
# скиннинг видимой геометрии, на анимацию они не влияют.
# Базовый рост оригинала — 1.92 м (humanoidbase.cpp:102, zMultiplier = playerHeight/1.92);
# neck сидит на 1.61, значит на шею с головой остаётся 0.31.
TIPS = {
    "neck":         ((0, 0, 1),      0.31),   # шея + голова одним блоком
    "left_elbow":   ((-0.03, 0, -1), 0.28),   # предплечье + кисть
    "right_elbow":  ((0.03, 0, -1),  0.28),
    "left_ankle":   ((0, -1, 0),     0.25),   # стопа вперёд (−Y)
    "right_ankle":  ((0, -1, 0),     0.25),
}

# Корень несёт позицию игрока в мире и ничего не деформирует — хвост условный.
ROOT_TIP = ((0, 0, 1), 0.10)


def world_heads():
    """Абсолютные позиции суставов: смещения в BONES заданы от родителя."""
    heads = {}
    for name, parent, off in BONES:
        base = heads[parent] if parent else Vector((0, 0, 0))
        heads[name] = base + Vector(off)
    return heads


def children_of(name):
    return [b for b, p, _ in BONES if p == name]


def build(heads):
    arm_data = bpy.data.armatures.new("GpfSkeleton")
    arm_obj = bpy.data.objects.new("GpfSkeleton", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    edit = {}
    for name, _parent, _off in BONES:
        bone = arm_data.edit_bones.new(name)
        bone.head = heads[name]

        kids = children_of(name)
        if name == "player":
            direction, length = ROOT_TIP
            bone.tail = bone.head + Vector(direction).normalized() * length
        elif name in TIPS:
            direction, length = TIPS[name]
            bone.tail = bone.head + Vector(direction).normalized() * length
        elif len(kids) == 1:
            bone.tail = heads[kids[0]]
        else:
            # Развилка (body → middle+бёдра, middle → шея+плечи): ведём кость
            # к «главному» ребёнку — тому, что продолжает ось тела вверх.
            main = "middle" if name == "body" else "neck"
            bone.tail = heads[main]
        edit[name] = bone

    for name, parent, _off in BONES:
        if parent:
            edit[name].parent = edit[parent]
            edit[name].use_connect = False

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def report(arm_obj, heads):
    print("\n=== GPF rig — контрольная таблица ===")
    print(f"{'кость':<16}{'head (x,y,z)':<28}{'длина':>8}  рест-базис")
    for name, _parent, _off in BONES:
        bone = arm_obj.data.bones[name]
        h = heads[name]
        m = bone.matrix_local.to_3x3()
        identity = all(
            abs(m[r][c] - (1.0 if r == c else 0.0)) < 1e-6
            for r in range(3) for c in range(3)
        )
        print(
            f"{name:<16}"
            f"({h.x:>7.3f},{h.y:>7.3f},{h.z:>7.3f})     "
            f"{bone.length:>8.3f}  "
            f"{'Identity' if identity else 'повёрнут'}"
        )

    top = heads["neck"].z + TIPS["neck"][1]
    print(f"\nмакушка (конец neck): {top:.3f} м")
    print(f"таз (body):           {heads['body'].z:.3f} м")
    print(f"плечи:                {heads['left_shoulder'].z:.3f} м")
    print(f"колено:               {heads['left_knee'].z:.3f} м")
    print(f"лодыжка:              {heads['left_ankle'].z:.3f} м")
    print(f"бедро / голень:       {0.42:.3f} / {0.44:.3f} м")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_path = argv[0] if argv else "gpf_rig.blend"

    bpy.ops.wm.read_factory_settings(use_empty=True)
    heads = world_heads()
    arm_obj = build(heads)
    report(arm_obj, heads)

    bpy.ops.wm.save_as_mainfile(filepath=out_path)
    print(f"\nсохранено: {out_path}")


if __name__ == "__main__":
    main()

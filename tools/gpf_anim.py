# Минимальный парсер .anim датасета GameplayFootball для Blender.
#
# Нужен затем, чтобы оценивать силуэт в ИГРОВОЙ позе, а не в рест-позе: в ресте
# руки висят вплотную к торсу и сливаются с ним, поэтому судить по нему о форме
# нельзя — игрок такой позы почти никогда не принимает.
#
# Формат (см. docs/wiki/порт-gameplayfootball.md): до XML-хвоста идут CSV-строки
# треков, `player` несёт только позицию корня (frame,x,y,z), остальные 13 —
# АБСОЛЮТНУЮ ЛОКАЛЬНУЮ ориентацию джойнта (frame,qx,qy,qz,qw). Ключи разрежены,
# между ними интерполируем. Кадр = 10 мс.
#
# ВНИМАНИЕ на порядок компонент: в файле (как в Godot) кватернион идёт
# x,y,z,w — а mathutils.Quaternion принимает w,x,y,z.

import io

from mathutils import Matrix, Quaternion, Vector


def load(path):
    """{имя трека: [(кадр, [значения]), ...]} — только CSV-часть, XML не нужен."""
    tracks = {}
    with io.open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("<"):
                break
            parts = line.split(",")
            name = parts[0]
            if name == "extension":
                # extension,football,... — данные касания мяча, не трек кости.
                continue
            rest = parts[1:]
            stride = 4 if name == "player" else 5

            keys = []
            for i in range(0, len(rest) - stride + 1, stride):
                frame = int(float(rest[i]))
                keys.append((frame, [float(x) for x in rest[i + 1:i + stride]]))
            if keys:
                tracks[name] = keys
    return tracks


def _bracket(keys, frame):
    """Пара ключей вокруг кадра и доля между ними."""
    if frame <= keys[0][0]:
        return keys[0], keys[0], 0.0
    if frame >= keys[-1][0]:
        return keys[-1], keys[-1], 0.0
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a[0] <= frame <= b[0]:
            span = b[0] - a[0]
            return a, b, 0.0 if span == 0 else (frame - a[0]) / span
    return keys[-1], keys[-1], 0.0


def rotation(tracks, name, frame):
    # У корня в треке лежит ПОЗИЦИЯ, а не кватернион — вращения у него нет.
    keys = None if name == "player" else tracks.get(name)
    if not keys:
        return Quaternion()
    a, b, t = _bracket(keys, frame)
    qa = Quaternion((a[1][3], a[1][0], a[1][1], a[1][2]))   # x,y,z,w → w,x,y,z
    qb = Quaternion((b[1][3], b[1][0], b[1][1], b[1][2]))
    if qa.dot(qb) < 0.0:            # ближняя дуга
        qb.negate()
    return qa.slerp(qb, t).normalized() if t > 0.0 else qa.normalized()


def root_position(tracks, name="player", frame=0):
    keys = tracks.get(name)
    if not keys:
        return Vector((0, 0, 0))
    a, b, t = _bracket(keys, frame)
    return Vector(a[1]).lerp(Vector(b[1]), t)


def apply_pose(arm_obj, tracks, frame, bones_order):
    """Ставит позу арматуре: клип задаёт локальную ориентацию в осях родителя.

    Глобальные матрицы считаем сами и присваиваем `pose_bone.matrix` (это
    armature space). Порядок — от родителя к ребёнку, иначе Blender пересчитает
    ребёнка по ещё не обновлённому родителю.
    """
    import bpy

    globals_ = {}
    for name, parent, _offset in bones_order:
        rest_local = arm_obj.data.bones[name].matrix_local
        offset = rest_local.to_translation()
        if parent:
            offset = offset - arm_obj.data.bones[parent].matrix_local.to_translation()

        local = Matrix.Translation(offset) @ rotation(tracks, name, frame).to_matrix().to_4x4()
        globals_[name] = (globals_[parent] @ local) if parent else local

    for name, _parent, _offset in bones_order:
        arm_obj.pose.bones[name].matrix = globals_[name]
        bpy.context.view_layer.update()

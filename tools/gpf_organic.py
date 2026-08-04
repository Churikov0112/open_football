# Органическая оболочка тела: метаболы вместо склеенных лофтов.
#
# Зачем. Раздельные лофты по частям дают «трубки»: между торсом и бедром,
# плечом и торсом видны уступы и щели, тело не перетекает. Референсы держатся
# ровно на обратном — на непрерывных объёмах, которые переходят друг в друга.
#
# Как. Вдоль каждой кости расставляются метаболы-шары с радиусом из профиля;
# метаболы сливаются гладко и дают единую поверхность с переменным сечением.
#
# Веса при этом НЕ ломаются, хотя оболочка стала цельной: барьер весов не
# обязан совпадать с барьером геометрии. Зона вершины определяется поиском
# ближайшей исходной части через BVH — то есть вершина кисти найдёт кисть,
# даже если геометрически сидит внутри бедра.

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

# Шаг расстановки шаров — ДОЛЯ радиуса, а не константа: фиксированный шаг
# крупнее радиуса превращает тонкие сегменты (предплечье, голень) в бусы.
BALL_STEP_RATIO = 0.5
BALL_STEP_MIN = 0.011
# Разрешение полигонизации: чем мельче, тем плотнее и глаже итоговый меш.
RESOLUTION = 0.021
# Порог слияния. Больше — толще «мясо» на стыках и выше риск перепонок.
THRESHOLD = 0.55
# Изоповерхность метабола проходит ЗАМЕТНО внутри заданного радиуса (поле
# убывает, порог отсекает часть), поэтому радиусы надо увеличивать, а не
# уменьшать. Значение подобрано по габариту: цель — та же ширина, что у лофтов.
RADIUS_SCALE = 1.34
# Выравнивание сетки после полигонизации и целевой полигонаж.
REMESH_VOXEL = 0.019
DECIMATE_RATIO = 0.32


def _profile_radius(profile, t):
    """Линейная интерполяция (rx, ry) по профилю в точке t."""
    if t <= profile[0][0]:
        return profile[0][1], profile[0][2]
    if t >= profile[-1][0]:
        return profile[-1][1], profile[-1][2]
    for i in range(len(profile) - 1):
        t0, rx0, ry0 = profile[i]
        t1, rx1, ry1 = profile[i + 1]
        if t0 <= t <= t1:
            k = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return rx0 + (rx1 - rx0) * k, ry0 + (ry1 - ry0) * k
    return profile[-1][1], profile[-1][2]


def build_shell(families, name="OrganicBody"):
    """families: {семья: [(p0, p1, profile)]} → один меш-объект.

    Семья — это барьер слияния: метаболы Blender сливаются только внутри
    одного семейства (оно определяется именем объекта до точки). Без такого
    разделения руки, висящие вплотную к торсу, поглощаются им, а ноги
    срастаются до колен — получается кокон вместо фигуры.
    """
    # Возвращаем ОСТРОВА раздельно: зона вершины должна определяться островом,
    # а не расстоянием до доноров. Рука висит внутри силуэта торса, и по
    # расстоянию граница гуляет по боку — вершина торса получает кости руки,
    # улетает с ней и тянет за собой связанную поверхность («паруса»).
    shells = {}
    for family, segments in families.items():
        shells[family] = _build_family(family, segments)
        print("  остров %s: %d вершин" % (family, len(shells[family].data.vertices)))
    return shells


def _build_family(family, segments):
    mball = bpy.data.metaballs.new(family)
    mball.resolution = RESOLUTION
    mball.render_resolution = RESOLUTION
    mball.threshold = THRESHOLD
    obj = bpy.data.objects.new(family, mball)
    bpy.context.collection.objects.link(obj)

    for p0, p1, profile in segments:
        a = Vector(p0)
        b = Vector(p1)
        length = (b - a).length
        min_radius = min(rx for _t, rx, _ry in profile) * RADIUS_SCALE
        step = max(BALL_STEP_MIN, min_radius * BALL_STEP_RATIO)
        count = max(2, int(round(length / step)) + 1)

        for i in range(count):
            t = i / (count - 1)
            rx, ry = _profile_radius(profile, t)
            # BALL, а не ELLIPSOID: у эллипсоида с нулевыми осями поле
            # вырождается и полигонизация даёт пустой меш. Сплющенность по
            # глубине добираем масштабом объекта после конвертации.
            elem = mball.elements.new(type="BALL")
            elem.co = a.lerp(b, t)
            elem.radius = rx * RADIUS_SCALE

    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.context.view_layer.update()
    bpy.ops.object.convert(target="MESH")
    mesh_obj = bpy.context.active_object

    # Полигонизация метаболов неравномерна: в зонах сильного слияния (пах,
    # подмышка) сетка вырождается в «месиво». Voxel-remesh выравнивает её и
    # заодно режет полигонаж. Делается ПООСТРОВНО — на объединённом меше он
    # склеил бы руки с торсом.
    if REMESH_VOXEL > 0.0:
        mod = mesh_obj.modifiers.new("Remesh", "REMESH")
        mod.mode = "VOXEL"
        mod.voxel_size = REMESH_VOXEL
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if DECIMATE_RATIO < 1.0:
        mod = mesh_obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = DECIMATE_RATIO
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return mesh_obj


def assign_zones(shell, donors):
    """vertex_index → имя части, по ближайшей поверхности исходных лофтов.

    Именно это позволяет сварить тело в одну оболочку, не возвращая протечку
    весов: геометрия слитая, а принадлежность вершины считается по донорам.
    """
    trees = {}
    for part, objects in donors.items():
        verts = []
        faces = []
        for obj in objects:
            offset = len(verts)
            matrix = obj.matrix_world
            verts.extend([matrix @ v.co for v in obj.data.vertices])
            for poly in obj.data.polygons:
                idx = [i + offset for i in poly.vertices]
                for k in range(1, len(idx) - 1):
                    faces.append((idx[0], idx[k], idx[k + 1]))
        if faces:
            trees[part] = BVHTree.FromPolygons(verts, faces)

    zones = {}
    matrix = shell.matrix_world
    for v in shell.data.vertices:
        world = matrix @ v.co
        distances = {}
        for part, tree in trees.items():
            hit = tree.find_nearest(world)
            if hit[0] is not None:
                distances[part] = (hit[0] - world).length
        if distances:
            zones[v.index] = sorted(distances.items(), key=lambda kv: kv[1])
    return zones

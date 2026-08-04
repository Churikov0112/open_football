# Серая болванка тела на скелете порта — не арт, а измерительный инструмент:
# показывает, где 14 костей ломают деформацию, и проверяет, что рест-базисы
# после «выпрямления» совпадают с Identity, которого ждёт Gpf.SkeletonBuilder.
#
# Геометрия — примитивы по сегментам костей, сгруппированные в 8 логических
# частей по схеме оригинала (`fullbody.ase`). Веса аналитические, и вершина
# видит только кости своей части — см. `skin()`, там же почему это важно.
# Пропорции взяты под референс (стройный футболист, базовый рост 1.92 м), но
# это заведомо черновик: болванка меряет деформацию, а не изображает игрока.
#
# Запуск (второй аргумент — необязательное превью .png):
#   & "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background \
#       --python tools/build_gpf_blockout.py -- "<repo>/assets/models/gpf_blockout.glb"

import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from build_gpf_rig import BONES, TIPS, build, children_of, world_heads  # noqa: E402
import gpf_organic  # noqa: E402
import gpf_style  # noqa: E402

# Пропорции — единственное место, где их можно и нужно крутить. Длины костей
# сюда НЕ входят: они фиксированы скелетом порта, менять нельзя. Крутится только
# «мясо» — объёмы, ширина плеч, размер головы.
#
# Ориентиры из референсов («виниловая фигурка»): ~7 голов роста при базовых
# 1.92 м, слегка увеличенная голова, широкие плечи, упрощённые кисти.
# Ограничение снизу — замеры `_probe_deform.gd`: бедро и колено схлопываются
# до 0.26, поэтому там нельзя делать тонко, иначе излом станет виден.
PROPORTIONS = {
    "head_radius": (0.121, 0.128, 0.134),   # X, Y, Z полуоси головы
    "head_center_z": 1.788,
    "neck_r": (0.058, 0.053),
    # Плечевой сустав скелета узок (полуразмах 0.16 против 0.18–0.20 у человека),
    # поэтому дельту выносим мешем наружу — кость при этом не трогаем.
    "deltoid_r": 0.074,
    "deltoid_out": 0.030,
    "upperarm_r": (0.058, 0.045),
    "forearm_r": (0.043, 0.031),
    "hand_size": (0.031, 0.026, 0.042),
    "pelvis_r": (0.146, 0.138),
    "pelvis_squash": 0.78,
    "trunk_r": (0.126, 0.170),              # талия → грудь (уже сустава 0.16!)
    "trunk_squash": 0.70,
    "trunk_top_z": 1.60,
    "thigh_r": (0.092, 0.064),
    "shin_r": (0.064, 0.043),
    "foot_size": (0.094, 0.250, 0.080),
    # Органическая оболочка (метаболы) даёт перетекающие объёмы, но в анимации
    # рвётся перепонками: в рест-позе руки прижаты к торсу, их метаболы
    # перекрываются, и при отведении руки граница тянется. Лечится bind-позой
    # с отведёнными руками (как у оригинала) — до тех пор путь по умолчанию
    # лофтовый. См. docs/wiki/открытые-вопросы.md.
    "organic": False,          # метаболы вместо склеенных лофтов
    "subdiv": 0,               # Catmull-Clark стягивает примитивы — держим 0
    "cone_verts": 20,          # мягкость даёт плотность сечения, не subdivision

    # Профили — (t вдоль кости, полуширина, полуглубина). Здесь живёт характер
    # фигуры: талия, грудь, икра, бицепс. Тело не круглое в плане, поэтому
    # ширина и глубина задаются раздельно.
    "profiles": {
        "torso": [                      # таз → талия → грудь → плечи
            (0.00, 0.099, 0.078),       # низ скруглён, иначе таз — блин
            (0.07, 0.170, 0.123),       # таз шире бёдер: их верх должен утонуть
            (0.20, 0.157, 0.113),
            (0.38, 0.143, 0.106),       # талия — самое узкое место
            (0.62, 0.168, 0.120),
            (0.85, 0.188, 0.128),       # грудь — самое широкое
            (0.95, 0.168, 0.110),
            (1.00, 0.092, 0.074),       # сходится к шее, а не обрывается полкой
        ],
        "neck": [(0.00, 0.050, 0.047), (0.35, 0.058, 0.054), (1.00, 0.050, 0.047)],
        "upperarm": [               # начало широкое — это и есть дельта
            (0.00, 0.034, 0.032),   # скруглённая макушка плеча, не погон
            (0.09, 0.072, 0.068),
            (0.22, 0.068, 0.064),
            (0.45, 0.051, 0.049),
            (1.00, 0.038, 0.037),
        ],
        "forearm": [(0.00, 0.030, 0.029), (0.10, 0.041, 0.040), (0.25, 0.040, 0.039),
                    (1.00, 0.027, 0.026)],
        "thigh": [(0.00, 0.049, 0.047), (0.10, 0.074, 0.071), (0.24, 0.076, 0.072),
                  (1.00, 0.049, 0.047)],
        "shin": [                       # икра — характерная форма ноги футболиста
            (0.00, 0.054, 0.053),
            (0.24, 0.060, 0.057),
            (0.72, 0.038, 0.037),
            (1.00, 0.034, 0.033),
        ],
    },
}

DELTOID_R = PROPORTIONS["deltoid_r"]


def cone(name, p0, p1, r0, r1, verts=None, squash_y=1.0):
    """Конический сегмент между двумя точками; squash_y сплющивает по глубине."""
    verts = verts or PROPORTIONS["cone_verts"]
    direction = Vector(p1) - Vector(p0)
    length = direction.length
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts, radius1=r0, radius2=r1, depth=length,
        location=(Vector(p0) + direction / 2),
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction)
    if squash_y != 1.0:
        obj.scale = (1.0, squash_y, 1.0)
    return obj


def loft(name, p0, p1, profile, verts=None):
    """Оболочка по сечениям вдоль отрезка p0→p1.

    Конус задаёт форму двумя числами и потому даёт «доску»; профиль —
    список `(t, rx, ry)` вдоль оси, и именно он несёт характер: талия, грудь,
    икра, бицепс. `t` — доля пути от p0 к p1, `rx`/`ry` — полуширина и
    полуглубина сечения (глубина отдельно, потому что тело не круглое в плане).
    """
    import math

    verts = verts or PROPORTIONS["cone_verts"]
    a = Vector(p0)
    b = Vector(p1)
    axis = (b - a).normalized()

    # Устойчивый базис сечения: берём oporу, заведомо не параллельную оси.
    ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((0, 1, 0))
    right = axis.cross(ref).normalized()
    fwd = axis.cross(right).normalized()

    rings = []
    for t, rx, ry in profile:
        center = a.lerp(b, t)
        ring = []
        for i in range(verts):
            angle = 2.0 * math.pi * i / verts
            ring.append(center + right * (rx * math.cos(angle))
                        + fwd * (ry * math.sin(angle)))
        rings.append(ring)

    coords = [v for ring in rings for v in ring]
    faces = []
    for r in range(len(rings) - 1):
        base_a = r * verts
        base_b = (r + 1) * verts
        for i in range(verts):
            j = (i + 1) % verts
            faces.append((base_a + i, base_a + j, base_b + j, base_b + i))
    faces.append(tuple(range(verts - 1, -1, -1)))                       # нижняя крышка
    faces.append(tuple(range(len(coords) - verts, len(coords))))        # верхняя

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in coords], [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def blob(name, center, radii):
    """Сплющенная сфера — голова, кисти, дельты."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = radii
    return obj


def box(name, center, size):
    bpy.ops.mesh.primitive_cube_add(location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    return obj


# Схема разбиения — из оригинала (fullbody.ase: body, head, arm×2, sock×2,
# shoe×2, sole×2, knee×2). Часть задаёт СПИСОК костей, которым разрешено тянуть
# её вершины, и это единственный барьер против протечки весов: в рест-позе
# кисть геометрически сидит внутри бедра, и любой автоскиннинг по общей
# поверхности склеивает руку с ногой (замерено — 12,4 % вершин).
# body покрывает 7 костей ровно как оригинал (joints 0,1,2,3,5,7,10) — торс
# дотягивается до плеч и бёдер, но не до локтей, коленей и лодыжек.
PART_BONES = {
    # Плеч и бёдер здесь НЕТ, в отличие от оригинала: у него веса рисованные и
    # аккуратные, а аналитическая обратная степень при близкой кости плеча даёт
    # доминирующий вклад и растягивает торс парусом на развороте корпуса.
    # Руки и ноги — отдельные объекты, стык с ними и так жёсткий.
    "body": ["body", "middle", "neck"],
}

# Множитель влияния кости внутри части. Плечи и бёдра нужны торсу только чтобы
# края следовали за конечностями; на полной силе они растягивают его в стороны.
BONE_INFLUENCE = {
    ("body", "left_shoulder"): 0.25,
    ("body", "right_shoulder"): 0.25,
    ("body", "left_thigh"): 0.35,
    ("body", "right_thigh"): 0.35,
    ("body", "neck"): 0.30,
}

PART_BONES.update({
    "head": ["neck"],
    "arm_left": ["left_shoulder", "left_elbow"],
    "arm_right": ["right_shoulder", "right_elbow"],
    "leg_left": ["left_thigh", "left_knee"],
    "leg_right": ["right_thigh", "right_knee"],
    "foot_left": ["left_knee", "left_ankle"],
    "foot_right": ["right_knee", "right_ankle"],
})


def body_segments(h):
    """[(p0, p1, профиль, часть)] — описание тела одним списком.

    Из него строится и органическая оболочка (метаболы), и доноры зон
    (лофты), поэтому источник обязан быть один: разъедутся — веса лягут мимо.
    """
    p = PROPORTIONS
    prof = p["profiles"]
    out = [
        (h["body"], (0, -0.02, p["trunk_top_z"]), prof["torso"], "body"),
        (h["neck"], (0, -0.025, 1.70), prof["neck"], "head"),
    ]

    # Голова — сегмент по вертикали с «бочкообразным» профилем: метаболы
    # превращают его в округлый объём, а лофт-донор даёт ту же зону.
    hr = p["head_radius"]
    cz = p["head_center_z"]
    out.append((
        (0, -0.020, cz - hr[2] * 0.52), (0, -0.020, cz + hr[2] * 0.52),
        [(0.00, hr[0] * 0.55, hr[1] * 0.55), (0.28, hr[0] * 0.94, hr[1] * 0.94),
         (0.62, hr[0], hr[1]), (1.00, hr[0] * 0.58, hr[1] * 0.58)],
        "head",
    ))

    for side, sx in (("left", 1.0), ("right", -1.0)):
        sh = h[f"{side}_shoulder"]
        el = h[f"{side}_elbow"]
        tip_dir, tip_len = TIPS[f"{side}_elbow"]
        wrist = Vector(el) + Vector((sx * tip_dir[0], tip_dir[1], tip_dir[2])).normalized() * tip_len
        hs = p["hand_size"]

        out.append((sh, el, prof["upperarm"], f"arm_{side}"))
        out.append((el, wrist, prof["forearm"], f"arm_{side}"))
        out.append((
            wrist, wrist - Vector((0, 0, hs[2] * 1.6)),
            [(0.00, hs[0] * 0.9, hs[1] * 1.1), (0.45, hs[0], hs[1] * 1.2),
             (1.00, hs[0] * 0.6, hs[1] * 0.8)],
            f"arm_{side}",
        ))

        th = h[f"{side}_thigh"]
        kn = h[f"{side}_knee"]
        an = h[f"{side}_ankle"]
        fs = p["foot_size"]
        out.append((th, kn, prof["thigh"], f"leg_{side}"))
        out.append((kn, an, prof["shin"], f"leg_{side}"))
        out.append((
            (an[0], an[1], an[2]), (an[0], an[1] - fs[1] * 0.80, fs[2] * 0.40),
            [(0.00, fs[0] * 0.52, fs[2] * 0.50), (0.55, fs[0] * 0.50, fs[2] * 0.42),
             (1.00, fs[0] * 0.36, fs[2] * 0.30)],
            f"foot_{side}",
        ))

    return out


# На сколько метров сегмент продлевается НАЗАД по своей оси, внутрь соседа.
# Стык при этом прячется под поверхностью, и части перестают читаться
# отдельными трубками — при том, что форма задаётся ровно профилем и меняется
# предсказуемо (в отличие от метаболов, см. открытые-вопросы).
# Плечо не утапливается: его ось смотрит вверх от сустава, а торс там уже
# кончился (trunk_top 1.60) — продление торчало бы наружу.
EMBED = {
    "neck": 0.075,
    "forearm": 0.050,
    "hand": 0.030,
    "thigh": 0.100,
    "shin": 0.060,
    "foot": 0.045,
}


def embed(p0, p1, profile, back):
    """Продлить начало сегмента назад по оси, сузив кончик — чтобы утонул."""
    a = Vector(p0)
    b = Vector(p1)
    length = (b - a).length
    if back <= 0.0 or length <= 0.0:
        return p0, p1, profile

    direction = (b - a).normalized()
    total = length + back
    shifted = [((t * length + back) / total, rx, ry) for t, rx, ry in profile]
    tip = (0.0, shifted[0][1] * 0.86, shifted[0][2] * 0.86)
    return a - direction * back, b, [tip] + shifted


def build_parts(h):
    """(объект, часть) для каждого куска тела. «Вперёд» — −Y."""
    parts = []

    p = PROPORTIONS
    prof = p["profiles"]

    # Торс — ОДИН лофт от таза до плеч: талия и грудь должны быть одной
    # непрерывной формой, иначе на стыке таз/грудь появляется ступенька.
    parts.append((loft("torso", h["body"], (0, -0.02, p["trunk_top_z"]), prof["torso"]), "body"))

    # Шея и голова одной костью. Макушка должна встать на 1.92.
    parts.append((loft("neck", *embed(h["neck"], (0, -0.025, 1.70), prof["neck"],
                                      EMBED["neck"])), "head"))
    parts.append((blob("head", (0, -0.020, p["head_center_z"]), p["head_radius"]), "head"))

    for side, sx in (("left", 1.0), ("right", -1.0)):
        sh = h[f"{side}_shoulder"]
        el = h[f"{side}_elbow"]
        tip_dir, tip_len = TIPS[f"{side}_elbow"]
        wrist = Vector(el) + Vector((sx * tip_dir[0], tip_dir[1], tip_dir[2])).normalized() * tip_len

        parts.append((loft(f"{side}_upperarm", sh, el, prof["upperarm"]), f"arm_{side}"))
        parts.append((loft(f"{side}_forearm",
                           *embed(el, wrist, prof["forearm"], EMBED["forearm"])), f"arm_{side}"))
        parts.append((blob(f"{side}_hand", wrist - Vector((0, 0, 0.035 - EMBED["hand"])),
                           p["hand_size"]), f"arm_{side}"))

        th = h[f"{side}_thigh"]
        kn = h[f"{side}_knee"]
        an = h[f"{side}_ankle"]
        parts.append((loft(f"{side}_thigh",
                           *embed(th, kn, prof["thigh"], EMBED["thigh"])), f"leg_{side}"))
        parts.append((loft(f"{side}_shin",
                           *embed(kn, an, prof["shin"], EMBED["shin"])), f"leg_{side}"))
        # Стопа — жёсткий блок от лодыжки вперёд: кости носка нет и не будет.
        fs = p["foot_size"]
        parts.append((box(f"{side}_foot",
                          (an[0], an[1] - 0.095 + EMBED["foot"] * 0.5, fs[2] / 2), fs),
                      f"foot_{side}"))

    return parts


WEIGHT_FALLOFF = 4.5   # чем больше, тем локальнее влияние кости


def bone_segment(name, heads):
    """Отрезок кости в мире: до ребёнка, а у терминальных — по хвосту из TIPS."""
    kids = children_of(name)
    p0 = heads[name]
    if kids:
        main = kids[0]
        if name == "body":
            main = "middle"
        elif name == "middle":
            main = "neck"
        return p0, heads[main]

    direction, length = TIPS[name]
    d = Vector(direction)
    if name.startswith("right_"):
        d.x = -d.x
    return p0, p0 + d.normalized() * length


def point_to_segment(p, a, b):
    ab = b - a
    denom = ab.dot(ab)
    t = 0.0 if denom < 1e-9 else max(0.0, min(1.0, (p - a).dot(ab) / denom))
    return (p - (a + ab * t)).length


def skin(parts, arm_obj, heads):
    """Веса аналитические, и вершина видит ТОЛЬКО кости своей части.

    Именно разбиение на части — единственный барьер против протечки весов.
    В рест-позе кисть геометрически сидит внутри бедра, поэтому любой
    автоскиннинг по общей поверхности склеивает руку с ногой (замерено
    `_probe_deform.gd`: 1067 вершин из 8616, растяжение до ×22). Оригинал не
    решал это хитрым скиннингом — у него `fullbody.ase` просто разрезан на 12
    объектов, и вес не пересекает границу объекта. Повторяем ту же схему.

    Вес кости — обратная степень расстояния до её отрезка; сумма нормализуется.
    """
    segments = {b: bone_segment(b, heads) for b, _p, _o in BONES if b != "player"}

    for obj, part in parts:
        allowed = PART_BONES[part]
        groups = {b: obj.vertex_groups.new(name=b) for b in allowed}
        matrix = obj.matrix_world

        for v in obj.data.vertices:
            world = matrix @ v.co
            raw = []
            for b in allowed:
                a, c = segments[b]
                d = point_to_segment(world, Vector(a), Vector(c))
                w = 1.0 / max(d, 0.005) ** WEIGHT_FALLOFF
                raw.append((b, w * BONE_INFLUENCE.get((part, b), 1.0)))

            total = sum(w for _b, w in raw)
            for b, w in raw:
                if w / total > 0.01:
                    groups[b].add([v.index], w / total, "REPLACE")

    bpy.ops.object.select_all(action="DESELECT")
    for obj, _ in parts:
        obj.select_set(True)
    body = parts[0][0]
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()      # группы вершин сливаются по именам
    body.name = "GpfBlockout"
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.parent_set(type="ARMATURE_NAME")   # берём готовые группы
    print(f"веса: аналитические по частям ({len(PART_BONES)} частей)")

    # Мягкость «винила» — subdivision поверх уже назначенных весов (Blender их
    # интерполирует) плюс гладкие нормали. Части при этом остаются раздельными.
    bpy.context.view_layer.objects.active = body
    if PROPORTIONS["subdiv"] > 0:
        sub = body.modifiers.new("Subdiv", "SUBSURF")
        sub.levels = sub.render_levels = PROPORTIONS["subdiv"]
        bpy.ops.object.modifier_apply(modifier=sub.name)
    bpy.ops.object.shade_smooth()

    return body


# Смежность зон. Барьер против протечки остаётся (рука и нога не смежны),
# но на стыках веса смешиваются — иначе жёсткая граница рвёт деформацию:
# вершина в подмышке улетает целиком с рукой, а оставшаяся без весов вовсе
# стоит на месте, растягивая соседей в «крылья».
ADJACENT = {
    frozenset(("body", "head")),
    frozenset(("body", "arm_left")), frozenset(("body", "arm_right")),
    frozenset(("body", "leg_left")), frozenset(("body", "leg_right")),
    frozenset(("leg_left", "foot_left")), frozenset(("leg_right", "foot_right")),
}
# Смешивание нужно ВНУТРИ острова: торс и ноги — связная поверхность, и жёсткая
# граница зон рвёт её в паху (замер: сжатие 0.03, растяжение ×11.7). Руке оно
# больше не вредит — она отдельный остров, её доноры в расчёт не попадают.
BLEND_RANGE = 0.055  # м: насколько глубоко соседняя зона подмешивается


def skin_organic(shell, zones, arm_obj, heads):
    """Веса цельной оболочке: кости берутся по ЗОНЕ вершины, не по объекту.

    Оболочка слитая, поэтому «часть» вершины больше не задаётся геометрией —
    её даёт `gpf_organic.assign_zones` поиском ближайшего донора. Дальше всё
    как в `skin()`: только кости своей части, обратная степень расстояния.
    """
    segments = {b: bone_segment(b, heads) for b, _p, _o in BONES if b != "player"}
    groups = {}
    matrix = shell.matrix_world

    for v in shell.data.vertices:
        ranked = zones.get(v.index)
        if not ranked:
            continue
        part, near = ranked[0]
        world = matrix @ v.co

        allowed = list(PART_BONES[part])
        for other, distance in ranked[1:]:
            if (distance - near) < BLEND_RANGE and frozenset((part, other)) in ADJACENT:
                allowed.extend(b for b in PART_BONES[other] if b not in allowed)

        raw = []
        for b in allowed:
            a, c = segments[b]
            d = point_to_segment(world, Vector(a), Vector(c))
            w = 1.0 / max(d, 0.005) ** WEIGHT_FALLOFF
            raw.append((b, w * BONE_INFLUENCE.get((part, b), 1.0)))

        total = sum(w for _b, w in raw)
        kept = [(b, w / total) for b, w in raw if w / total > 0.01]
        if not kept:                       # без веса вершина застынет и порвёт меш
            kept = [(max(raw, key=lambda bw: bw[1])[0], 1.0)]
        for b, w in kept:
            if b not in groups:
                groups[b] = shell.vertex_groups.new(name=b)
            groups[b].add([v.index], w, "REPLACE")

    bpy.ops.object.select_all(action="DESELECT")
    shell.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.parent_set(type="ARMATURE_NAME")
    bpy.context.view_layer.objects.active = shell
    bpy.ops.object.shade_smooth()
    return shell


def build_organic(heads):
    """Цельное тело: метаболы дают перетекающие объёмы, лофты — только зоны."""
    segments = body_segments(heads)

    # Руки — своя семья метаболов: висят вплотную к торсу и иначе тонут в нём.
    def family_of(part):
        return "Arm" + part.split("_")[1].capitalize() if part.startswith("arm_") else "Body"

    families = {}
    parts_of_family = {}
    for a, b, prof, part in segments:
        family = family_of(part)
        families.setdefault(family, []).append((a, b, prof))
        parts_of_family.setdefault(family, set()).add(part)

    shells = gpf_organic.build_shell(families)

    merged_zones = {}
    offset = 0
    islands = []
    for family, shell_obj in shells.items():
        # Доноры строим ТОЛЬКО из частей этого острова: вершине руки нечего
        # искать в торсе, и наоборот.
        donors = {}
        for a, b, prof, part in segments:
            if family_of(part) != family:
                continue
            donors.setdefault(part, []).append(
                loft(f"donor_{part}_{len(donors.get(part, []))}", a, b, prof))

        zones = gpf_organic.assign_zones(shell_obj, donors)
        for objects in donors.values():
            for obj in objects:
                bpy.data.objects.remove(obj, do_unlink=True)

        islands.append(shell_obj)
        for index, ranked in zones.items():
            merged_zones[index + offset] = ranked
        offset += len(shell_obj.data.vertices)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in islands:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = islands[0]
    if len(islands) > 1:
        bpy.ops.object.join()
    shell = bpy.context.active_object
    shell.name = "GpfBlockout"

    counts = {}
    for ranked in merged_zones.values():
        counts[ranked[0][0]] = counts.get(ranked[0][0], 0) + 1
    print("зоны: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    return shell, merged_zones


def straighten(arm_obj):
    """Рест-базис в Identity: кость вдоль мирового +Y, roll 0, head на месте.

    Веса живут в именованных группах вершин и переориентацию переживают; поза
    покоя не меняется (matrix_channel = pose·matrix_local⁻¹ = I), поэтому меш
    не деформируется — меняются только базисы, которые уедут в inverse bind.
    """
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in arm_obj.data.edit_bones:
        bone.tail = bone.head + Vector((0, bone.length, 0))
        bone.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")


def check_rest(arm_obj):
    bad = []
    for name, _parent, _off in BONES:
        m = arm_obj.data.bones[name].matrix_local.to_3x3()
        if any(abs(m[r][c] - (1.0 if r == c else 0.0)) > 1e-6
               for r in range(3) for c in range(3)):
            bad.append(name)
    if bad:
        print(f"!! рест-базис НЕ Identity у {len(bad)} костей: {', '.join(bad)}")
    else:
        print(f"рест-базис Identity у всех {len(BONES)} костей — совпадает со SkeletonBuilder")
    return not bad


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_path = argv[0] if argv else "gpf_blockout.glb"
    png_path = argv[1] if len(argv) > 1 else ""

    bpy.ops.wm.read_factory_settings(use_empty=True)
    heads = world_heads()
    arm_obj = build(heads)
    arm_obj.data.bones["player"].use_deform = False

    if PROPORTIONS["organic"]:
        body, zones = build_organic(heads)
        skin_organic(body, zones, arm_obj, heads)
    else:
        body = skin(build_parts(heads), arm_obj, heads)
    straighten(arm_obj)
    ok = check_rest(arm_obj)

    lo = min((body.matrix_world @ v.co).z for v in body.data.vertices)
    hi = max((body.matrix_world @ v.co).z for v in body.data.vertices)
    width = max(abs((body.matrix_world @ v.co).x) for v in body.data.vertices) * 2
    print(f"габарит меша: низ {lo:.3f} / верх {hi:.3f} / рост {hi - lo:.3f} м, ширина {width:.3f} м")
    print(f"полигонов: {len(body.data.polygons)}, вершин: {len(body.data.vertices)}")

    bpy.ops.object.select_all(action="SELECT")
    # Z-up наружу: датасет и скелет живут в осях оригинала, конверсию в Godot
    # делает обёртка GpfSpace — экспортёр поворачивать сцену не должен.
    bpy.ops.export_scene.gltf(
        filepath=out_path, export_format="GLB", export_yup=False,
        use_selection=True, export_skins=True, export_animations=False,
    )
    print(f"\nсохранено: {out_path}")
    print("рест-контракт:", "OK" if ok else "НАРУШЕН")

    if png_path:
        mat = gpf_style.vinyl_material("vinyl_blockout", gpf_style.VINYL["blockout"])
        body.data.materials.append(mat)
        gpf_style.setup_scene()
        for view in ("front", "three_quarter"):
            gpf_style.render(png_path.replace(".png", f"_{view}.png"), lo, hi, view)


if __name__ == "__main__":
    main()

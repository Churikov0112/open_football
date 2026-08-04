# Тело персонажа из MakeHuman (MPFB2) на утилитарном GPF-скелете.
#
# Спайк-решение 2026-08-04: источник геометрии — MPFB2 (анатомия + единая
# топология для будущих морфов лица), скелет — неизменный 14-костный GPF
# (длины костей фиксированы, на них завязаны коллизии мяча и точки касания).
#
# Конвейер внутри:
#   1. MPFB2 создаёт тело (макро-параметры MACRO), риг game_engine с рисоваными
#      весами; хелперы отбрасываются (остаётся группа body, 13380 вершин).
#   2. Тело позируется родным ригом в рест GPF (руки вниз, ноги вертикально)
#      и запекается evaluated-мешем.
#   3. Веса ремапятся: группы MH-костей складываются в 14 GPF-костей (REMAP).
#   4. Сегментный варп: на каждой GPF-кости аффинное преобразование
#      MH-сегмент → GPF-сегмент (конечности — с осевым масштабом, терминальные
#      кости — жёстко), смешивание по ремапнутым весам (LBS) даёт гладкость.
#   5. Арматура из build_gpf_rig, «выпрямление» в Identity-рест, экспорт
#      export_yup=False (пространство GPF доезжает до GpfSpace нетронутым).
#
# Запуск:
#   & "<blender>" --background --python tools/build_gpf_makehuman.py -- \
#       "<repo>/assets/models/gpf_makehuman.glb" ["<preview>.png"] ["<src>.blend"]

import os
import sys
import importlib.util

import bpy
from mathutils import Matrix, Vector

TOOLS = os.path.dirname(os.path.abspath(__file__))


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(TOOLS, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rig_mod = _load("build_gpf_rig")
gpf_style = _load("gpf_style")

# Макро-параметры MakeHuman. height подобран так, чтобы макушка вышла ~1.92 м
# (базовый рост GPF). cupsize обязан быть 0: дефолт 0.5 даёт мужской фигуре
# грудь. muscle/weight подняты по вердикту 2026-08-04 («тощий, дистрофичный»);
# метрика силуэта при этом уступает референсу — вкус пользователя главнее.
MACRO = dict(height=0.69, muscle=0.9, weight=0.6, gender=1.0, age=0.45,
             proportions=0.7, cupsize=0.0, firmness=1.0)

# Детальные таргеты поверх макро: спортивность, которой макро-слайдеры не дают
# (бёдра/голени/руки объёмнее, живот в тонусе, плечи чуть шире).
DETAIL_TARGETS = {
    "l-upperleg-muscle-incr": 0.6, "r-upperleg-muscle-incr": 0.6,
    "l-lowerleg-muscle-incr": 0.6, "r-lowerleg-muscle-incr": 0.6,
    "l-upperarm-muscle-incr": 0.6, "r-upperarm-muscle-incr": 0.6,
    "l-upperarm-shoulder-muscle-incr": 0.4, "r-upperarm-shoulder-muscle-incr": 0.4,
    "l-lowerarm-muscle-incr": 0.4, "r-lowerarm-muscle-incr": 0.4,
    "stomach-tone-incr": 0.6,
    # measure-bust-circ-incr НЕ включать: раздувает рёберную клетку буграми
    # («рёбра выпирают», вердикт 2026-08-04).
    # measure-shoulder-dist-incr НЕ включать: плечевой сустав скелета на 0.16,
    # раздвинутые ключицы после варпа складываются «эполетами» над плечами.
}

FINGERS = [f"{f}_{i:02d}" for f in ("thumb", "index", "middle", "ring", "pinky")
           for i in (1, 2, 3)]

# MH game_engine → GPF. Каждая группа-источник складывается в группу-приёмник;
# протечка рука<->нога исключена по построению — веса MH локальны конечности.
REMAP = {
    "body":           ["Root", "pelvis", "spine_01"],
    "middle":         ["spine_02", "spine_03", "clavicle_l", "clavicle_r"],
    "neck":           ["neck_01", "head"],
    "left_shoulder":  ["upperarm_l"],
    "right_shoulder": ["upperarm_r"],
    "left_elbow":     ["lowerarm_l", "hand_l"] + [f + "_l" for f in FINGERS],
    "right_elbow":    ["lowerarm_r", "hand_r"] + [f + "_r" for f in FINGERS],
    "left_thigh":     ["thigh_l"],
    "right_thigh":    ["thigh_r"],
    "left_knee":      ["calf_l"],
    "right_knee":     ["calf_r"],
    "left_ankle":     ["foot_l", "ball_l"],
    "right_ankle":    ["foot_r", "ball_r"],
}


def create_body():
    from bl_ext.blender_org.mpfb.services.humanservice import HumanService
    from bl_ext.blender_org.mpfb.services.targetservice import TargetService

    mac = TargetService.get_default_macro_info_dict()
    mac.update(MACRO)
    body = HumanService.create_human(macro_detail_dict=mac)
    # Таргеты — ДО рига: add_builtin_rig подгоняет суставы под текущую форму.
    for name, weight in DETAIL_TARGETS.items():
        TargetService.load_target(body, TargetService.target_full_path(name),
                                  weight=weight)
    arm = HumanService.add_builtin_rig(body, "game_engine", import_weights=True)
    return body, arm


def gpf_joints():
    """Абсолютные позиции суставов GPF + направления терминальных костей."""
    heads = rig_mod.world_heads()
    tips = {}
    for name, (direction, length) in rig_mod.TIPS.items():
        tips[name] = heads[name] + Vector(direction).normalized() * length
    return heads, tips


def align_chain(arm, chain):
    """Позирует цепочку: каждой кости — мировое направление на её цель.

    chain: [(имя_кости, направление_Vector), ...] от корня цепочки к концу.
    Вращение вокруг head в мировых осях; после каждой кости — update, чтобы
    дети пересчитались.
    """
    for bone_name, target_dir in chain:
        pb = arm.pose.bones[bone_name]
        head = arm.matrix_world @ pb.head
        tail = arm.matrix_world @ pb.tail
        cur = (tail - head).normalized()
        rot = cur.rotation_difference(Vector(target_dir).normalized()).to_matrix().to_4x4()
        world = arm.matrix_world @ pb.matrix
        pivot = Matrix.Translation(head)
        pb.matrix = arm.matrix_world.inverted() @ (pivot @ rot @ pivot.inverted() @ world)
        bpy.context.view_layer.update()


def pose_to_gpf_rest(arm, heads, tips):
    """Руки вниз и ноги вертикально — рест GPF (I-поза).

    Ключицы подводят плечевой сустав MH ровно в сустав GPF ещё позой: тогда
    аффине руки при варпе почти без переноса, и трапеции не тянутся вверх
    («вздёрнутые плечи» первой итерации).
    """
    for side, s in (("left", "l"), ("right", "r")):
        clav = arm.pose.bones[f"clavicle_{s}"]
        clav_head = arm.matrix_world @ clav.head
        # Полный подвод ключицей = «shrug», трапеции торчат буграми; половина
        # вертикали позой, остаток доберёт варп — бугров нет, вздёрнутости нет.
        cur_tip = arm.matrix_world @ arm.pose.bones[f"upperarm_{s}"].head
        target = heads[f"{side}_shoulder"].lerp(cur_tip, 0.5)
        align_chain(arm, [(f"clavicle_{s}", target - clav_head)])
    up_l = (heads["left_elbow"] - heads["left_shoulder"])
    lo_l = (tips["left_elbow"] - heads["left_elbow"])
    up_r = (heads["right_elbow"] - heads["right_shoulder"])
    lo_r = (tips["right_elbow"] - heads["right_elbow"])
    thigh = (heads["left_knee"] - heads["left_thigh"])
    shin = (heads["left_ankle"] - heads["left_knee"])
    align_chain(arm, [("upperarm_l", up_l), ("lowerarm_l", lo_l)])
    align_chain(arm, [("upperarm_r", up_r), ("lowerarm_r", lo_r)])
    align_chain(arm, [("thigh_l", thigh), ("calf_l", shin)])
    align_chain(arm, [("thigh_r", thigh), ("calf_r", shin)])


def posed_mh_joints(arm):
    joints = {}
    for pb in arm.pose.bones:
        joints[pb.name] = arm.matrix_world @ pb.head
    return joints


def bake(body):
    """Запекает shape keys + позу арматуры в новый меш (vgroups переживают)."""
    dg = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(
        body.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = body.data
    body.data = baked
    bpy.data.meshes.remove(old)
    body.shape_key_clear() if body.data.shape_keys else None
    body.modifiers.clear()


def drop_helpers(body):
    """Оставляет только вершины группы body (13380 штук базового меша MH)."""
    import bmesh
    gi = body.vertex_groups.find("body")
    keep = set()
    for v in body.data.vertices:
        for g in v.groups:
            if g.group == gi and g.weight > 0.5:
                keep.add(v.index)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    doomed = [v for v in bm.verts if v.index not in keep]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()


def remap_weights(body):
    """MH-группы → 14 GPF-групп, нормализация."""
    src_index = {}
    for gpf_bone, mh_bones in REMAP.items():
        for mh in mh_bones:
            gi = body.vertex_groups.find(mh)
            if gi >= 0:
                src_index[gi] = gpf_bone
    merged = {}  # vert -> {gpf_bone: weight}
    for v in body.data.vertices:
        acc = {}
        for g in v.groups:
            gpf_bone = src_index.get(g.group)
            if gpf_bone and g.weight > 0:
                acc[gpf_bone] = acc.get(gpf_bone, 0.0) + g.weight
        total = sum(acc.values())
        if total > 0:
            merged[v.index] = {b: w / total for b, w in acc.items()}
    for g in list(body.vertex_groups):
        body.vertex_groups.remove(g)
    groups = {name: body.vertex_groups.new(name=name) for name in REMAP}
    for vi, acc in merged.items():
        for bone, w in acc.items():
            groups[bone].add([vi], w, "REPLACE")
    orphans = len(body.data.vertices) - len(merged)
    if orphans:
        print(f"!! вершин без веса после ремапа: {orphans}")
    return merged


def build_affines(mh, heads, tips, crown_src, crown_dst):
    """Аффинное преобразование на каждую GPF-кость: MH-сегмент → GPF-сегмент.

    Конечности — поворот + осевой масштаб (обхваты не трогаем), терминальные
    кости (шея+голова, предплечье+кисть, стопа) — жёсткий перенос без масштаба:
    кисть/стопу/голову не сжимаем под длину костяного хвоста. Торс — один
    общий сегмент таз→шея на body и middle, чтобы не рвать живот.
    """
    def seg(a_src, b_src, a_dst, b_dst, axial=True, scale_all=None):
        d_src = (b_src - a_src)
        d_dst = (b_dst - a_dst)
        k = d_dst.length / d_src.length if axial else 1.0
        if scale_all is not None:
            k = scale_all
        rot = d_src.normalized().rotation_difference(d_dst.normalized()).to_matrix()
        n = d_src.normalized()

        def apply(v, a_src=a_src, a_dst=a_dst, rot=rot, n=n, k=k,
                  axial=axial, scale_all=scale_all):
            d = v - a_src
            if scale_all is not None:
                d = d * k
            elif axial:
                along = d.dot(n)
                d = d + n * (along * (k - 1.0))
            return a_dst + rot @ d
        return apply

    torso_seg = seg(mh["pelvis"], mh["neck_01"], heads["body"], heads["neck"])
    # Профиль ширины торса по высоте (t: 0 таз → 1 шея), референс «V-атлет»
    # 2026-08-04: талия уже, грудь шире, у плеч резкий скат — верх торса обязан
    # быть УЖЕ плечевого сустава 0.16, иначе руки тонут в торсе (грабля
    # болванки, см. презентация-и-ассеты).
    # Пик груди на t≈0.65; ширина несётся вверх почти до плеч (референс: грудь
    # НЕ сужается к плечам), скат остаётся только у самой шеи. Дельты надуты
    # (deltoid_pad) и в силуэте всё равно шире торса — руки не тонут.
    # Пик груди умеренный: 1.12 давал «ромб» (вердикт 2026-08-04).
    TORSO_PROFILE = [(0.0, 1.0), (0.34, 0.92), (0.65, 0.97), (0.88, 0.85),
                     (1.0, 0.75)]
    z0, z1 = heads["body"].z, heads["neck"].z

    def torso_width(t):
        for (ta, ka), (tb, kb) in zip(TORSO_PROFILE, TORSO_PROFILE[1:]):
            if t <= tb:
                return ka + (kb - ka) * (t - ta) / (tb - ta)
        return TORSO_PROFILE[-1][1]

    def torso(v, _seg=torso_seg, z0=z0, z1=z1):
        out = _seg(v)
        t = min(max((out.z - z0) / (z1 - z0), 0.0), 1.0)
        out.x *= torso_width(t)
        return out
    aff = {"body": torso, "middle": torso}
    # голова: жёстко к шее + равномерный масштаб до макушки 1.92
    head_k = (tips["neck"].z - heads["neck"].z) / max(crown_src - mh["neck_01"].z, 1e-6)
    aff["neck"] = seg(mh["neck_01"], mh["head"], heads["neck"], tips["neck"],
                      scale_all=head_k)
    for side, s in (("left", "l"), ("right", "r")):
        aff[f"{side}_shoulder"] = seg(mh[f"upperarm_{s}"], mh[f"lowerarm_{s}"],
                                      heads[f"{side}_shoulder"], heads[f"{side}_elbow"])
        aff[f"{side}_elbow"] = seg(mh[f"lowerarm_{s}"], mh[f"hand_{s}"],
                                   heads[f"{side}_elbow"], tips[f"{side}_elbow"],
                                   axial=False)
        aff[f"{side}_thigh"] = seg(mh[f"thigh_{s}"], mh[f"calf_{s}"],
                                   heads[f"{side}_thigh"], heads[f"{side}_knee"])
        aff[f"{side}_knee"] = seg(mh[f"calf_{s}"], mh[f"foot_{s}"],
                                  heads[f"{side}_knee"], heads[f"{side}_ankle"])
        aff[f"{side}_ankle"] = seg(mh[f"foot_{s}"], mh[f"ball_{s}"],
                                   heads[f"{side}_ankle"], tips[f"{side}_ankle"],
                                   axial=False)
    return aff


# Дельту выносим ЗА плечевой сустав (кость трогать нельзя, сустав узкий 0.16 —
# ограничение скелета, решение то же, что планировалось болванке). Вместо
# плоского сдвига по X — сферическое надувание дельтовидного шара вокруг
# сустава: вершина уходит ОТ центра шара, пропорционально весу плечевой кости
# и близости к суставу. Решение «гнать голое тело к референсу» (2026-08-04).
DELTOID_INFLATE = 0.8    # доля радиального смещения в пике
DELTOID_RADIUS = 0.13     # радиус влияния вокруг центра шара

# Грудные «пластины» винилового референса: вынос вперёд (−Y) ПЛАТО, а не
# горбом — горб с пиком в центре усиливает каплевидное обвисание базовой
# груди MH («обвисшие», вердикт 2026-08-04). Узкая кромка снизу даёт чёткий
# «накаченный» нижний край.
PEC_PUSH = 0.035
PEC_Z = (1.32, 1.54)      # высоты зоны грудных
PEC_X = (0.015, 0.17)      # от грудины до края груди
PEC_EDGE = 0.025          # ширина скругления кромок плато
PEC_X_TOP = 0.25          # ширина пластины у верхней кромки (до дельт)


def deltoid_pad(body, weights, heads):
    for side in ("left", "right"):
        sign = 1.0 if side == "left" else -1.0
        # Центр шара чуть снаружи и выше сустава — там сидит дельтовидная.
        center = heads[f"{side}_shoulder"] + Vector((sign * 0.02, 0.0, 0.01))
        for v in body.data.vertices:
            acc = weights.get(v.index)
            if not acc:
                continue
            w = acc.get(f"{side}_shoulder", 0.0)
            if w <= 0.0:
                continue
            offset = v.co - center
            d = offset.length
            if d >= DELTOID_RADIUS or d < 1e-6:
                continue
            fall = 1.0 - d / DELTOID_RADIUS
            push = offset * (DELTOID_INFLATE * w * fall)
            # Вверх не надуваем: рост шара вверх задирает трапецию «пикой».
            if push.z > 0.0:
                push.z *= 0.15
            v.co += push


def pec_pad(body, weights):
    """Плоская квадратная грудная пластина (винил-референс): вершины зоны
    проецируются на общую переднюю плоскость, а не выпячиваются горбом —
    два округлых холма читались «обвисшей грудью»."""
    z0, z1 = PEC_Z
    x0, x1 = PEC_X

    def plateau(t, lo, hi):
        """1.0 внутри зоны, плавный спад к кромкам шириной PEC_EDGE."""
        return max(0.0, min(1.0, (t - lo) / PEC_EDGE, (hi - t) / PEC_EDGE))

    def factor(v):
        acc = weights.get(v.index)
        if not acc:
            return 0.0
        w = acc.get("middle", 0.0) + acc.get("body", 0.0)
        if w <= 0.0 or v.co.y > -0.02:      # только передняя сторона
            return 0.0
        # Пластина — трапеция: кверху шире (до PEC_X_TOP), тянется к дельтам
        # и связывает торс с руками (вердикт 2026-08-04).
        tz = min(max((v.co.z - z0) / (z1 - z0), 0.0), 1.0)
        x_hi = x1 + (PEC_X_TOP - x1) * tz
        return w * plateau(v.co.z, z0, z1) * plateau(abs(v.co.x), x0, x_hi)

    zone = [(v, f) for v in body.data.vertices
            for f in (factor(v),) if f > 0.0]
    if not zone:
        return
    # Плоскость пластины: чуть впереди самой выступающей точки зоны.
    y_plate = min(v.co.y for v, _f in zone) - PEC_PUSH * 0.3
    for v, f in zone:
        v.co.y += (y_plate - v.co.y) * min(1.0, f * 1.2)


def smooth_zone(body, predicate, iterations=3, factor=0.5):
    """Сглаживает вершины по предикату: скульптовые накладки без сглаживания
    оставляют грань на границе весов («подплечники»); тем же приёмом гасятся
    соски на груди — винил их не предполагает."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    zone = [v for v in bm.verts if predicate(v.co)]
    for _ in range(iterations):
        bmesh.ops.smooth_vert(bm, verts=zone, factor=factor,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(body.data)
    bm.free()


def smooth_shoulders(body, heads, radius=0.15):
    centers = [heads["left_shoulder"], heads["right_shoulder"]]
    smooth_zone(body, lambda co: any((co - c).length < radius for c in centers))


def smooth_pecs(body):
    z0, z1 = PEC_Z
    smooth_zone(body,
                lambda co: co.y < -0.02 and z0 <= co.z <= z1
                and abs(co.x) <= PEC_X[1] + 0.02,
                iterations=2, factor=0.5)


def nipple_indices(body):
    """Индексы вершин сосков — брать ПОСЛЕ drop_helpers, ДО remap_weights
    (ремап удаляет группы MH)."""
    idx = set()
    for name in ("nipple", "nippleTip"):
        gi = body.vertex_groups.find(name)
        if gi < 0:
            continue
        for v in body.data.vertices:
            if any(g.group == gi and g.weight > 0.1 for g in v.groups):
                idx.add(v.index)
    return idx


def flatten_nipples(body, idx):
    """Винил сосков не предполагает: агрессивное сглаживание только их вершин
    втягивает бугорок в поверхность груди."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    zone = [bm.verts[i] for i in idx]
    for _ in range(10):
        bmesh.ops.smooth_vert(bm, verts=zone, factor=1.0,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(body.data)
    bm.free()


def warp(body, weights, affines):
    """LBS по ремапнутым весам: v' = Σ w_b · A_b(v). Гладкость — из весов."""
    for v in body.data.vertices:
        acc = weights.get(v.index)
        if not acc:
            continue
        out = Vector((0, 0, 0))
        for bone, w in acc.items():
            out += affines[bone](v.co) * w
        v.co = out


def fit_report(mh, heads, tips, crown_src):
    print("\n=== подгонка: суставы MH (после позы) против GPF ===")
    pairs = [
        ("таз",        mh["pelvis"],     heads["body"]),
        ("шея",        mh["neck_01"],    heads["neck"]),
        ("плечо L",    mh["upperarm_l"], heads["left_shoulder"]),
        ("локоть L",   mh["lowerarm_l"], heads["left_elbow"]),
        ("бедро L",    mh["thigh_l"],    heads["left_thigh"]),
        ("колено L",   mh["calf_l"],     heads["left_knee"]),
        ("лодыжка L",  mh["foot_l"],     heads["left_ankle"]),
    ]
    worst = 0.0
    for label, a, b in pairs:
        d = (a - b).length
        worst = max(worst, d)
        print(f"  {label:<10} MH ({a.x:+.3f},{a.y:+.3f},{a.z:+.3f})"
              f"  GPF ({b.x:+.3f},{b.y:+.3f},{b.z:+.3f})  Δ {d * 100:5.1f} см")
    print(f"  макушка MH {crown_src:.3f} → цель {tips['neck'].z:.3f}")
    print(f"  худшее расхождение до варпа: {worst * 100:.1f} см")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_path = argv[0] if argv else "gpf_makehuman.glb"
    png_path = argv[1] if len(argv) > 1 else ""
    blend_path = argv[2] if len(argv) > 2 else ""

    # Пустая сцена: дефолтные Cube/Light/Camera не должны уезжать в .blend.
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    body, mh_arm = create_body()
    heads, tips = gpf_joints()

    pose_to_gpf_rest(mh_arm, heads, tips)
    mh = posed_mh_joints(mh_arm)
    bake(body)
    drop_helpers(body)

    dg = bpy.context.evaluated_depsgraph_get()
    crown_src = max(v.co.z for v in body.evaluated_get(dg).data.vertices)
    fit_report(mh, heads, tips, crown_src)

    nipples = nipple_indices(body)
    weights = remap_weights(body)
    affines = build_affines(mh, heads, tips, crown_src, tips["neck"].z)
    warp(body, weights, affines)
    deltoid_pad(body, weights, heads)
    # pec_pad/smooth_pecs НЕ звать: скульптовые «пластины» дали чужеродную
    # грудь («голлум», вердикт 2026-08-04) — грудные остаются родные MH
    # (firmness 1.0, соски приплюснуты).
    smooth_shoulders(body, heads)
    flatten_nipples(body, nipples)

    bpy.data.objects.remove(mh_arm, do_unlink=True)

    arm_obj = rig_mod.build(heads)
    arm_obj.data.bones["player"].use_deform = False
    body.parent = arm_obj
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)

    blockout = _load("build_gpf_blockout")
    blockout.straighten(arm_obj)
    ok = blockout.check_rest(arm_obj)

    lo = min(v.co.z for v in body.data.vertices)
    hi = max(v.co.z for v in body.data.vertices)
    width = max(abs(v.co.x) for v in body.data.vertices) * 2
    print(f"габарит меша: низ {lo:.3f} / верх {hi:.3f} / рост {hi - lo:.3f} м, "
          f"ширина {width:.3f} м")
    print(f"полигонов: {len(body.data.polygons)}, вершин: {len(body.data.vertices)}")

    if blend_path:
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)
        print(f"исходник: {blend_path}")

    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm_obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=out_path, export_format="GLB", export_yup=False,
        use_selection=True, export_skins=True, export_animations=False,
    )
    print(f"\nсохранено: {out_path}")
    print("рест-контракт:", "OK" if ok else "НАРУШЕН")

    if png_path:
        mat = gpf_style.vinyl_material("vinyl_mh", gpf_style.VINYL["blockout"])
        body.data.materials.append(mat)
        gpf_style.setup_scene()
        for view in ("front", "three_quarter"):
            gpf_style.render(png_path.replace(".png", f"_{view}.png"), lo, hi, view)


if __name__ == "__main__":
    main()

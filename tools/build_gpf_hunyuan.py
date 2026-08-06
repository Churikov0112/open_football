# Тело персонажа из Hunyuan 3D Studio на утилитарном GPF-скелете.
#
# Параллельная ветка к build_gpf_makehuman.py (решено 2026-08-04): тот же
# 14-костный скелет, тот же выход-контракт, другой источник геометрии.
# Hunyuan сгенерировал меш по нашему же референсу assets/refs/ref_front.png,
# поэтому силуэт совпадает с ним по построению — вопрос ветки в том, окупает
# ли это потерю морфов и модульности MPFB2. Сравнение — tools/gpf_fit_model.py.
#
# Главная разница с MPFB2-конвейером: у сырья НЕТ ни скелета, ни весов, ни
# рест-позы. Отсюда три шага, которых там нет:
#   1. Нормализация: сырьё приходит ростом 1.158 «юнита» и Z-up через Blender-
#      экспортёр Hunyuan; тянем макушку на 1.92 м (базовый рост оригинала).
#   2. Веса переносятся с gpf_makehuman.glb — он уже скинут на эти 14 костей
#      с нулевой протечкой. Донор позируется в позу сырья ПЕРЕД переносом:
#      Data Transfer ищет ближайшую поверхность, и на разных позах он берёт
#      вес торса на руку.
#   3. Распозирование: сырьё слеплено с руками, отведёнными на ~20°, а рест
#      GPF — руки строго вниз. Вершины возвращаются в рест обратной LBS
#      (та же математика, что у заглушки в build_gpf_fullbody.py).
#
# Запуск:
#   & "<blender>" --background --python tools/build_gpf_hunyuan.py -- \
#       "<repo>/assets/models/gpf_hunyuan.glb" ["<preview>.png"] ["<src>.blend"]

import importlib.util
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(TOOLS, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rig_mod = _load("build_gpf_rig")
blockout = _load("build_gpf_blockout")
gpf_style = _load("gpf_style")

SRC = os.path.join(REPO, "assets/models/hunyuan_src/body_raw.glb")
DONOR = os.path.join(REPO, "assets/models/gpf_makehuman.glb")

# Столько же полигонов, сколько у MPFB2-тела (13378) — иначе сравнение веток
# упирается в разный полигонаж, а не в форму.
TARGET_TRIS = 13378

CROWN = 1.92          # базовый рост оригинала (humanoidbase.cpp:102)

ARM_BONES = ("left_shoulder", "left_elbow", "right_shoulder", "right_elbow")
LEG_BONES = ("left_thigh", "left_knee", "left_ankle",
             "right_thigh", "right_knee", "right_ankle")


def import_glb(path):
    """Импортирует .glb и возвращает появившиеся объекты."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def fix_upright(objs):
    """Ставит фигуру вертикально по Z.

    Наши .glb экспортированы с export_yup=False (в файле уже Z-вверх), а
    импортёр Blender безусловно считает файл Y-up и кладёт фигуру на спину.
    Признак — габарит по Y выше, чем по Z.
    """
    meshes = [o for o in objs if o.type == "MESH"]
    if not meshes:
        return
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    span_y = max(p.y for p in pts) - min(p.y for p in pts)
    span_z = max(p.z for p in pts) - min(p.z for p in pts)
    if span_y <= span_z:
        return
    rot = Matrix.Rotation(math.radians(-90), 4, "X")
    for o in objs:
        if o.parent is None:
            o.matrix_world = rot @ o.matrix_world
    bpy.context.view_layer.update()
    print("  (фигура лежала — развёрнута в вертикаль)")


def apply_transforms(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def normalize(body):
    """Макушка на CROWN, стопы на z=0, ось фигуры на x=0."""
    apply_transforms(body)
    co = [v.co for v in body.data.vertices]
    lo, hi = min(c.z for c in co), max(c.z for c in co)
    k = CROWN / (hi - lo)
    cx = 0.5 * (min(c.x for c in co) + max(c.x for c in co))
    cy = 0.5 * (min(c.y for c in co) + max(c.y for c in co))
    for v in body.data.vertices:
        v.co = Vector(((v.co.x - cx) * k, (v.co.y - cy) * k, (v.co.z - lo) * k))
    print(f"  масштаб x{k:.4f}: рост {hi - lo:.3f} → {CROWN:.3f} м")
    return k


def _row_clusters(xs, gap):
    """Одномерная кластеризация координат — разделяет руку, торс и вторую руку."""
    xs = sorted(xs)
    out = [[xs[0]]]
    for x in xs[1:]:
        if x - out[-1][-1] > gap:
            out.append([x])
        else:
            out[-1].append(x)
    return out


def measure_arm_angle(body, heads):
    """Угол отведения руки от вертикали, градусы.

    Меряется по центрам «рукавных» кластеров на нескольких высотах ниже
    плеча: на фронтальном срезе рука даёт отдельный сегмент по краю, торс —
    центральный. Прямая через центры и даёт наклон.
    """
    sh = heads["left_shoulder"]
    samples = []
    for frac in (0.20, 0.28, 0.36, 0.44, 0.52, 0.60):
        z = sh.z - frac * sh.z * 0.55
        band = [v.co for v in body.data.vertices if abs(v.co.z - z) < 0.012]
        if len(band) < 12:
            continue
        clusters = _row_clusters([c.x for c in band], gap=0.02)
        right = clusters[-1]
        if len(clusters) < 3 or (right[-1] - right[0]) > 0.25:
            continue                      # рука ещё слита с торсом
        samples.append((z, 0.5 * (right[0] + right[-1])))
    if len(samples) < 2:
        print("  !! угол руки замерить не удалось, беру 0°")
        return 0.0
    dz = samples[0][0] - samples[-1][0]
    dx = samples[-1][1] - samples[0][1]
    angle = math.degrees(math.atan2(dx, dz))
    print(f"  угол отведения руки: {angle:.1f}° (по {len(samples)} срезам)")
    return angle


def pose_arms(arm, angle_deg):
    """Отводит плечевые кости на угол — и у донора, и у нашего скелета.

    Знак отрицательный: рука висит вдоль −Z, поворот на +θ вокруг Y уводит её
    внутрь торса (грабля gpf_fit.a_pose).
    """
    angle = math.radians(angle_deg)
    for side, sign in (("left", 1.0), ("right", -1.0)):
        pb = arm.pose.bones[f"{side}_shoulder"]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((0.0, 1.0, 0.0), -sign * angle)
    bpy.context.view_layer.update()


def bake_posed(obj):
    """Запекает позу арматуры в меш (группы вершин переживают).

    matrix_world сохраняется вручную: сброс parent без этого роняет объект в
    начало координат вместе с parent_inverse, и донор расходится с приёмником
    на метр — Data Transfer тогда переносит пустоту.
    """
    dg = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(
        obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.data = baked
    bpy.data.meshes.remove(old)
    obj.modifiers.clear()
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = world
    bpy.context.view_layer.update()


def decimate(body, target_tris):
    bpy.context.view_layer.objects.active = body
    before = len(body.data.polygons)
    if before <= target_tris:
        return
    mod = body.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = target_tris / float(before)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print(f"  decimate: {before} → {len(body.data.polygons)} полигонов")


def smooth_weights(body, iterations=4, factor=0.5):
    """Усредняет веса вершины с соседями по рёбрам.

    Обязательный шаг: перенос по ближайшей поверхности даёт ступеньку веса
    там, где донор и приёмник расходятся формой (пах, подмышка), и на позе
    спринта оттуда лезут треугольные шипы — растяжение ребра до 17.9x против
    4.2x у рисованых весов MPFB2 (замер 2026-08-04).

    Делается кодом, а не bpy.ops.object.vertex_group_smooth: у оператора
    poll() валится в фоновом Blender («context is incorrect»), и результат
    зависит от режима и активной группы.
    """
    names = {g.index: g.name for g in body.vertex_groups}
    nbr = [[] for _ in range(len(body.data.vertices))]
    for e in body.data.edges:
        a, b = e.vertices
        nbr[a].append(b)
        nbr[b].append(a)

    weights = [{} for _ in range(len(body.data.vertices))]
    for v in body.data.vertices:
        for g in v.groups:
            if g.weight > 0.0:
                weights[v.index][names[g.group]] = g.weight

    for _ in range(iterations):
        updated = []
        for i, own in enumerate(weights):
            if not nbr[i]:
                updated.append(own)
                continue
            mean = {}
            for j in nbr[i]:
                for bone, w in weights[j].items():
                    mean[bone] = mean.get(bone, 0.0) + w
            k = float(len(nbr[i]))
            blend = {}
            for bone in set(own) | set(mean):
                blend[bone] = ((1.0 - factor) * own.get(bone, 0.0)
                               + factor * mean.get(bone, 0.0) / k)
            total = sum(blend.values())
            if total > 0.0:
                blend = {b: w / total for b, w in blend.items() if w / total > 0.001}
            updated.append(blend)
        weights = updated

    groups = {g.name: g for g in body.vertex_groups}
    for name, g in groups.items():
        g.remove(range(len(body.data.vertices)))
    for i, acc in enumerate(weights):
        for bone, w in acc.items():
            groups[bone].add([i], w, "REPLACE")


def transfer_weights(donor, target):
    """Веса донора → приёмник по ближайшей поверхности.

    POLYINTERP_NEAREST (интерполяция по ближайшему полигону), а не
    NEAREST — вершинный вариант даёт ступеньки на границах групп.
    """
    def span(o):
        pts = [o.matrix_world @ v.co for v in o.data.vertices]
        return (min(p.z for p in pts), max(p.z for p in pts),
                max(abs(p.x) for p in pts) * 2)

    d_lo, d_hi, d_w = span(donor)
    t_lo, t_hi, t_w = span(target)
    print(f"  донор   z {d_lo:.3f}..{d_hi:.3f}, ширина {d_w:.3f}")
    print(f"  приёмник z {t_lo:.3f}..{t_hi:.3f}, ширина {t_w:.3f}")
    if abs(d_hi - t_hi) > 0.15:
        print("  !! донор и приёмник разошлись по высоте — перенос будет мусорным")

    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    donor.select_set(True)
    bpy.context.view_layer.objects.active = donor      # активный = источник
    # Слои групп в приёмнике надо СОЗДАТЬ отдельным оператором: data_transfer
    # сам их не заводит и молча переносит в пустоту.
    bpy.ops.object.datalayout_transfer(
        data_type="VGROUP_WEIGHTS", use_delete=False,
        layers_select_src="ALL", layers_select_dst="NAME",
    )
    bpy.ops.object.data_transfer(
        data_type="VGROUP_WEIGHTS",
        vert_mapping="POLYINTERP_NEAREST",
        layers_select_src="ALL",
        layers_select_dst="NAME",
        mix_mode="REPLACE",
    )
    bpy.context.view_layer.objects.active = target
    smooth_weights(target)
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    weighted = sum(1 for v in target.data.vertices if v.groups)
    print(f"  групп: {len(target.vertex_groups)}, вершин с весом: "
          f"{weighted} из {len(target.data.vertices)}")


def vertex_weights(body):
    """{индекс вершины: {кость: вес}} по текущим группам."""
    names = {g.index: g.name for g in body.vertex_groups}
    out = {}
    for v in body.data.vertices:
        acc = {names[g.group]: g.weight for g in v.groups if g.weight > 0.0}
        if acc:
            out[v.index] = acc
    return out


def unpose(body, arm, weights):
    """Вершины из позы сырья обратно в рест: v' = (Σ wᵢ·Mᵢ)⁻¹ · v.

    Смешиваются матрицы, а не результаты — обратное преобразование тогда
    точное для той же LBS, которой вершина спозирована.
    """
    mats = {}
    for name, _parent, _off in rig_mod.BONES:
        rest = arm.data.bones[name].matrix_local
        mats[name] = arm.pose.bones[name].matrix @ rest.inverted()

    moved = 0
    for v in body.data.vertices:
        acc = weights.get(v.index)
        if not acc:
            continue
        blended = Matrix(((0.0,) * 4,) * 4)
        total = 0.0
        for bone, w in acc.items():
            m = mats.get(bone)
            if m is None:
                continue
            for r in range(4):
                for c in range(4):
                    blended[r][c] += m[r][c] * w
            total += w
        if total <= 1e-6:
            continue
        for r in range(4):
            for c in range(4):
                blended[r][c] /= total
        before = v.co.copy()
        v.co = blended.inverted() @ v.co
        if (v.co - before).length > 1e-4:
            moved += 1

    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix()
    bpy.context.view_layer.update()
    print(f"  распозировано вершин: {moved} из {len(body.data.vertices)}")


def leak_probe(body, weights):
    """Протечка рука↔нога — барьер, который MPFB2-ветка держит на нуле."""
    leaked = 0
    for acc in weights.values():
        arm_w = sum(acc.get(b, 0.0) for b in ARM_BONES)
        leg_w = sum(acc.get(b, 0.0) for b in LEG_BONES)
        if arm_w > 0.01 and leg_w > 0.01:
            leaked += 1
    print(f"протечка рука↔нога: {leaked} из {len(body.data.vertices)} вершин")
    return leaked


def fit_report(body, heads):
    """Куда сели анатомические ориентиры сырья относительно суставов скелета."""
    co = [v.co for v in body.data.vertices]

    def width_at(z, tol=0.012):
        band = [c for c in co if abs(c.z - z) < tol]
        if not band:
            return 0.0, 0
        return max(c.x for c in band) - min(c.x for c in band), len(band)

    print("\n=== посадка сырья на скелет ===")
    for label, z in (("плечи", heads["left_shoulder"].z),
                     ("таз", heads["body"].z),
                     ("бедро", heads["left_thigh"].z),
                     ("колено", heads["left_knee"].z),
                     ("лодыжка", heads["left_ankle"].z)):
        w, n = width_at(z)
        print(f"  {label:<9} z={z:.3f}  ширина силуэта {w:.3f} м  (вершин в срезе {n})")
    lo, hi = min(c.z for c in co), max(c.z for c in co)
    print(f"  габарит: низ {lo:.3f} / верх {hi:.3f} / рост {hi - lo:.3f} м")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_path = argv[0] if argv else "gpf_hunyuan.glb"
    png_path = argv[1] if len(argv) > 1 else ""
    blend_path = argv[2] if len(argv) > 2 else ""

    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    heads = rig_mod.world_heads()

    print("сырьё:", SRC)
    raw = import_glb(SRC)
    fix_upright(raw)
    body = [o for o in raw if o.type == "MESH"][0]
    body.name = "gpf_hunyuan"
    normalize(body)
    decimate(body, TARGET_TRIS)
    angle = measure_arm_angle(body, heads)
    fit_report(body, heads)

    print("\nдонор весов:", DONOR)
    donor_objs = import_glb(DONOR)
    fix_upright(donor_objs)
    donor = [o for o in donor_objs if o.type == "MESH"][0]
    donor_arm = [o for o in donor_objs if o.type == "ARMATURE"][0]
    print(f"  донор: {len(donor.data.polygons)} полигонов, "
          f"{len(donor.vertex_groups)} групп, кости: {len(donor_arm.data.bones)}")
    pose_arms(donor_arm, angle)
    bake_posed(donor)
    apply_transforms(donor)

    print("\nперенос весов")
    transfer_weights(donor, body)
    weights = vertex_weights(body)
    leak_probe(body, weights)

    print("\nраспозирование в рест GPF")
    arm_obj = rig_mod.build(heads)
    arm_obj.data.bones["player"].use_deform = False
    pose_arms(arm_obj, angle)
    unpose(body, arm_obj, weights)

    bpy.data.objects.remove(donor, do_unlink=True)
    bpy.data.objects.remove(donor_arm, do_unlink=True)

    body.parent = arm_obj
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj

    blockout.straighten(arm_obj)
    ok = blockout.check_rest(arm_obj)

    co = [v.co for v in body.data.vertices]
    lo, hi = min(c.z for c in co), max(c.z for c in co)
    print(f"габарит меша: низ {lo:.3f} / верх {hi:.3f} / рост {hi - lo:.3f} м, "
          f"ширина {max(abs(c.x) for c in co) * 2:.3f} м")
    print(f"полигонов: {len(body.data.polygons)}, вершин: {len(body.data.vertices)}")

    if blend_path:
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)
        print(f"исходник: {blend_path}")

    # Материалы сырья выбрасываются: стиль проекта — матовый винил БЕЗ карт
    # (gpf_style), а три 4K-текстуры Hunyuan раздували выход до 22.5 МБ против
    # 0.9 МБ у MPFB2-тела. Сырьё с текстурами лежит в hunyuan_src.
    body.data.materials.clear()

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
        for slot in list(body.material_slots):
            body.data.materials.clear()
        mat = gpf_style.vinyl_material("vinyl_hunyuan", gpf_style.VINYL["blockout"])
        body.data.materials.append(mat)
        gpf_style.setup_scene()
        for view in ("front", "three_quarter"):
            gpf_style.render(png_path.replace(".png", f"_{view}.png"), lo, hi, view)


if __name__ == "__main__":
    main()

# Оригинальная модель игрока GameplayFootball (fullbody.ase, Apache 2.0) на нашем
# 14-костном GPF-скелете — ВРЕМЕННАЯ ЗАГЛУШКА для лаб-сцен.
#
# Зачем. Палочник не даёт судить о смагглах, точках касания и зазоре нога-мяч:
# нечему касаться. Оригинальный меш слеплен ровно на эти кости, уже одет
# (гетры, бутсы отдельными объектами) и весами не протекает по построению —
# значит даёт честную картинку за часы, а не за дни. Своя модель (MPFB2,
# assets/models/gpf_makehuman.glb) остаётся принятой базой на будущее; сюда она
# не подключается — решение 2026-08-04.
#
# Ключевое место — БИНД-ПОЗА. Меш слеплен НЕ в нашем ресте: humanoidbase.cpp:208
# грузит media/animations/base.anim.util и вычитает её из всех клипов, «чтобы
# fullbody-мешу не нужны были нулевые углы». Наш AnimationApplier так не делает —
# он пишет кватернионы клипа в кости как есть, то есть рест у нас Identity (руки
# вниз, ноги вертикально). Поэтому вершины прогоняются через ОБРАТНУЮ LBS-матрицу
# базовой позы (unpose) и садятся в наш рест; после этого клипы играются как на
# любой другой нашей модели.
#
# Джойнты оригинала → наши кости: player в список узлов не входит, поэтому
# jointID = индекс в BONES минус один (см. JOINT_BONES). Сверка: объект `body`
# весится на 0,1,2,3,5,7,10 = таз, середина, шея, оба плеча, оба бедра.
#
# Кит своей заливкой: клубные формы оригинала (databases/default/images_teams/) —
# трейдмарки, не берём. Раскладку документирует databases/default/template_kit.png
# (shirt front/back, shorts front/back, right/left sock), по ней и растеризуем.
#
# Запуск:
#   & "<blender>" --background --python tools/build_gpf_fullbody.py -- \
#       "<GameplayFootball>/data" "<repo>/assets/models/gpf_fullbody.glb" ["<preview>.png"]

import os
import sys
import importlib.util

import bpy
import numpy as np
from mathutils import Matrix, Vector

TOOLS = os.path.dirname(os.path.abspath(__file__))


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(TOOLS, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rig_mod = _load("build_gpf_rig")
blockout = _load("build_gpf_blockout")
gpf_anim = _load("gpf_anim")
ase = _load("import_gpf_fullbody")

# jointID в vertex colors → имя кости. `player` узлом-джойнтом не считается
# (humanoidbase.cpp: humanoidNode->GetNodes собирает потомков), отсюда сдвиг.
JOINT_BONES = [name for name, _parent, _off in rig_mod.BONES if name != "player"]

# Материал ASE (*MATERIAL_REF) → чем красим. Имена материалов внутри файла:
# 0 front, 1 side — подложки моделлера (не используются), дальше настоящие.
MATERIALS = {
    2: ("shoe",      "objects/players/textures/shoe.jpg"),
    3: ("knee",      "objects/players/textures/skin.jpg"),
    4: ("shoe_sole", "objects/players/textures/shoe_sole.jpg"),
    5: ("arm",       "objects/players/textures/skin.jpg"),
    6: ("skin",      "objects/players/textures/skin.jpg"),
    7: ("kit",       None),      # None — рисуем сами, см. build_kit_image
}

# Плоский двухцветный кит. Цвета нейтральные: ничей клуб не угадывается.
KIT_SIZE = 512
KIT_SHIRT = (0.16, 0.28, 0.62)      # рубашка и гетры
KIT_SHORTS = (0.88, 0.88, 0.90)     # шорты
# Границы зон по вертикали текстуры, СНЯТЫ С template_kit.png (не подобраны):
# рубашка v≥0.589, шорты 0.434..0.589, ниже 0.427 — гетры. Тело раскатано
# непрерывной полосой (v монотонен по высоте), поэтому цвет выбирается ПО ТЕКСЕЛЮ,
# а не по грани: классификация граней даёт зубчатый пояс по рёбрам треугольников.
KIT_SHIRT_BOTTOM_V = 0.589
KIT_SHORTS_BOTTOM_V = 0.434


def unpose_matrices(arm_obj):
    """{кость: матрица base-позы} — ею меш переводится из базовой позы в рест.

    M = pose · rest⁻¹ в armature space: именно её Blender применяет к вершине
    при скиннинге. Значит обратная к смешанной по весам M возвращает вершину,
    слепленную в базовой позе, в рест.
    """
    tracks = gpf_anim.load(os.path.join(REPO, "assets/gpf/animations/base.anim.util"))
    gpf_anim.apply_pose(arm_obj, tracks, 0, rig_mod.BONES)

    mats = {}
    for name, _parent, _off in rig_mod.BONES:
        rest = arm_obj.data.bones[name].matrix_local
        mats[name] = arm_obj.pose.bones[name].matrix @ rest.inverted()

    # Поза больше не нужна: меш уедет в рест, арматура обязана остаться в ресте.
    for pb in arm_obj.pose.bones:
        pb.matrix_basis = Matrix()
    bpy.context.view_layer.update()
    return mats


def unpose_vertex(co, bones, mats):
    """Вершина из базовой позы в рест: (Σ wᵢ·Mᵢ)⁻¹ · v.

    Смешиваем матрицы, а не результаты — так обратное преобразование точное
    для той же LBS, которой вершина была спозирована.
    """
    blended = Matrix(((0,) * 4,) * 4)
    total = 0.0
    for joint, weight in bones:
        m = mats[JOINT_BONES[joint]]
        for r in range(4):
            for c in range(4):
                blended[r][c] += m[r][c] * weight
        total += weight
    if total <= 0.0:
        return Vector(co)
    for r in range(4):
        for c in range(4):
            blended[r][c] /= total
    return blended.inverted() @ Vector(co)


def build_kit_image(objects):
    """Плоский кит: заливка по зонам шаблона, обрезанная UV-треугольниками.

    Заливать одни прямоугольники нельзя — вне островов текселей быть не должно,
    иначе по краям рубашки лезет фон; поэтому цвет кладётся только туда, куда
    смотрит хоть один треугольник кит-материала.
    """
    px = np.zeros((KIT_SIZE, KIT_SIZE, 4), dtype=np.float32)
    px[:, :, 3] = 1.0

    ys, xs = np.mgrid[0:KIT_SIZE, 0:KIT_SIZE]
    zone = np.where(ys >= KIT_SHIRT_BOTTOM_V * (KIT_SIZE - 1), 0,
                    np.where(ys >= KIT_SHORTS_BOTTOM_V * (KIT_SIZE - 1), 1, 0))
    palette = np.array([KIT_SHIRT, KIT_SHORTS], dtype=np.float32)

    for obj in objects:
        if obj["material"] != 7 or not obj["tfaces"]:
            continue
        for tface in obj["tfaces"]:
            uv = [obj["uvs"][i] for i in tface]
            tri = np.array([[u * (KIT_SIZE - 1), v * (KIT_SIZE - 1)] for u, v in uv])
            x0, y0 = np.floor(tri.min(axis=0)).astype(int) - 1
            x1, y1 = np.ceil(tri.max(axis=0)).astype(int) + 1
            x0, y0 = max(x0, 0), max(y0, 0)
            x1, y1 = min(x1, KIT_SIZE - 1), min(y1, KIT_SIZE - 1)
            if x1 <= x0 or y1 <= y0:
                continue

            sub_x = xs[y0:y1 + 1, x0:x1 + 1]
            sub_y = ys[y0:y1 + 1, x0:x1 + 1]
            (ax, ay), (bx, by), (cx, cy) = tri
            den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(den) < 1e-9:
                continue
            w0 = ((by - cy) * (sub_x - cx) + (cx - bx) * (sub_y - cy)) / den
            w1 = ((cy - ay) * (sub_x - cx) + (ax - cx) * (sub_y - cy)) / den
            # Допуск: без него по швам между треугольниками остаются чёрные
            # пиксели — при билинейной выборке они лезут на модель полосами.
            inside = (w0 > -0.02) & (w1 > -0.02) & (w0 + w1 < 1.02)
            block = px[y0:y1 + 1, x0:x1 + 1]
            block[inside, :3] = palette[zone[y0:y1 + 1, x0:x1 + 1][inside]]

    image = bpy.data.images.new("gpf_kit", width=KIT_SIZE, height=KIT_SIZE)
    image.pixels = px.ravel()
    return image


def make_material(name, image):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.7
    bsdf.inputs["Specular IOR Level"].default_value = 0.25
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def load_materials(data_dir, objects):
    """{MATERIAL_REF: bpy.Material}. Текстуры кожи и бутс — родные из оригинала."""
    kit_image = build_kit_image(objects)
    out = {}
    for ref, (name, rel) in MATERIALS.items():
        if rel is None:
            out[ref] = make_material("gpf_" + name, kit_image)
            continue
        path = os.path.join(data_dir, "media", rel.replace("/", os.sep))
        if not os.path.exists(path):
            print("!! нет текстуры %s — материал %s останется серым" % (path, name))
            out[ref] = bpy.data.materials.new("gpf_" + name)
            continue
        out[ref] = make_material("gpf_" + name, bpy.data.images.load(path))
    return out


def build_part(obj, weights, mats, materials):
    """Один объект оригинала → меш в нашем ресте, с UV, весами и материалом."""
    verts = [unpose_vertex(co, weights.get(i, []), mats)
             for i, co in enumerate(obj["verts"])]

    # Префикс обязателен: объект оригинала `body` называется как кость `body`,
    # и glTF в таком случае переименовывает КОСТЬ (в body_2) — контракт скелета
    # падает на ровном месте.
    name = "part_" + obj["name"]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], obj["faces"])
    mesh.validate()

    if obj["tfaces"] and obj["uvs"]:
        layer = mesh.uv_layers.new(name="UVMap")
        for face_i, poly in enumerate(mesh.polygons):
            tface = obj["tfaces"][face_i]
            for corner, loop_i in enumerate(poly.loop_indices):
                layer.data[loop_i].uv = obj["uvs"][tface[corner]]

    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)

    groups = {}
    for vi, bones in weights.items():
        for joint, weight in bones:
            name = JOINT_BONES[joint]
            if name not in groups:
                groups[name] = ob.vertex_groups.new(name=name)
            groups[name].add([vi], weight, "REPLACE")

    material = materials.get(obj["material"])
    if material is not None:
        ob.data.materials.append(material)
    return ob


def report_fit(parts):
    """Ловушка на неправильную бинд-позу: сустав обязан лежать ВНУТРИ своей части.

    Меш, распозированный с ошибкой, выглядит правдоподобно, но стоит не там, где
    кость, — и тогда зазор нога-мяч в лабе врёт. Числами это видно сразу.
    """
    heads = rig_mod.world_heads()
    by_name = {p.name: p for p in parts}
    print("\nсустав внутри своей части (бинд-поза):")
    for part_name, joint in (("part_shoe_left", "left_ankle"),
                             ("part_shoe_right", "right_ankle"),
                             ("part_knee_left", "left_knee"),
                             ("part_knee_right", "right_knee"),
                             ("part_head", "neck")):
        p = by_name.get(part_name)
        if p is None:
            continue
        co = [v.co for v in p.data.vertices]
        lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
        hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
        j = heads[joint]
        inside = all(lo[k] - 0.02 <= j[k] <= hi[k] + 0.02 for k in range(3))
        print("  %-16s %-12s сустав (%.3f %.3f %.3f) в бокс X %.3f..%.3f Z %.3f..%.3f  %s"
              % (part_name, joint, j.x, j.y, j.z, lo.x, hi.x, lo.z, hi.z,
                 "OK" if inside else "!! СНАРУЖИ"))


def assemble(data_dir, verbose=True):
    """(арматура, части) — модель в нашем ресте. Сцена уже должна быть пустой."""
    src = os.path.join(data_dir, "media", "objects", "players", "models", "fullbody.ase")
    objects = [o for o in ase.parse_ase(src) if o["verts"]]

    heads = rig_mod.world_heads()
    arm_obj = rig_mod.build(heads)
    arm_obj.data.bones["player"].use_deform = False
    # Выпрямление ДО позирования: apply_pose строит глобальные матрицы из одних
    # кватернионов клипа, то есть считает базисы костей единичными. Спозируй
    # раньше — и в дельту базовой позы уедет ещё и смена базиса (меш разлетается
    # до 5 м роста, проверено).
    blockout.straighten(arm_obj)
    mats = unpose_matrices(arm_obj)

    weights_by_obj = {o["name"]: ase.decode_weights(o) for o in objects}
    materials = load_materials(data_dir, objects)

    if verbose:
        print("\n%-13s %6s %6s  %s" % ("объект", "верш", "граней", "кости"))
    parts = []
    for obj in objects:
        weights = weights_by_obj[obj["name"]]
        ob = build_part(obj, weights, mats, materials)
        ob.parent = arm_obj
        ob.modifiers.new("Armature", "ARMATURE").object = arm_obj
        parts.append(ob)
        if verbose:
            used = sorted({JOINT_BONES[j] for b in weights.values() for j, _ in b})
            print("%-13s %6d %6d  %s" % (obj["name"], len(obj["verts"]),
                                         len(obj["faces"]), ", ".join(used)))
    return arm_obj, parts


def main():
    global REPO
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    data_dir = argv[0]
    out_path = argv[1] if len(argv) > 1 else "gpf_fullbody.glb"
    png_path = argv[2] if len(argv) > 2 else ""
    REPO = os.path.dirname(TOOLS)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    arm_obj, parts = assemble(data_dir)

    ok = blockout.check_rest(arm_obj)

    lo = min(min(v.co.z for v in p.data.vertices) for p in parts)
    hi = max(max(v.co.z for v in p.data.vertices) for p in parts)
    width = max(max(abs(v.co.x) for v in p.data.vertices) for p in parts) * 2
    print("\nгабарит в ресте: низ %.3f / верх %.3f / рост %.3f м, ширина %.3f м"
          % (lo, hi, hi - lo, width))
    print("полигонов: %d, вершин: %d"
          % (sum(len(p.data.polygons) for p in parts),
             sum(len(p.data.vertices) for p in parts)))
    report_fit(parts)

    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    arm_obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=out_path, export_format="GLB", export_yup=False,
        use_selection=True, export_skins=True, export_animations=False,
    )
    print("\nсохранено: %s" % out_path)
    print("рест-контракт:", "OK" if ok else "НАРУШЕН")

    if png_path:
        ase.render_preview(png_path, lo, hi)


if __name__ == "__main__":
    main()

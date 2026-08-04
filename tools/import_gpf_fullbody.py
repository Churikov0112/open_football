# Импорт оригинальной модели игрока GameplayFootball (.ase, Apache 2.0) в Blender —
# как референс топологии, разбиения на части и схемы скиннинга. НЕ для использования
# как финальный ассет: ~32 вершины на часть, стиль реалистичный низкополи 2010-х.
#
# Формат ASE (3ds Max ASCII) у Blender не поддержан, парсер здесь минимальный:
# берём только то, что нужно — вершины, грани, vertex colors и цветовые грани,
# плюс UV и номер материала (их читает build_gpf_fullbody.py, собирающий ассет).
#
# Веса скиннинга закодированы в vertex colors (humanoidbase.cpp:318-320,
# gamedefines.cpp:86-93): цвет из файла умножается на 255 и округляется, затем
#   jointID = floor(c / 10)        weight = (c - jointID * 10) / 9
# — три канала = до трёх костей на вершину, веса нормализуются суммой.
# Цвет привязан к вершине через *MESH_CFACE параллельно *MESH_FACE.
#
# Запуск:
#   & "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background \
#       --python tools/import_gpf_fullbody.py -- "<...>/models/fullbody.ase" "<out>.blend"

import io
import os
import sys

import bpy


def parse_ase(path):
    """[{name, verts, faces, colors, cfaces}] — по одному на *GEOMOBJECT."""
    objects = []
    current = None

    with io.open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            t = line.split()
            if not t:
                continue
            tag = t[0]

            if tag == "*GEOMOBJECT":
                current = {"name": "", "verts": [], "faces": [], "colors": [], "cfaces": [],
                           "uvs": [], "tfaces": [], "material": -1}
                objects.append(current)
            elif current is None:
                continue
            elif tag == "*NODE_NAME" and not current["name"]:
                current["name"] = line.split('"')[1] if '"' in line else t[1]
            elif tag == "*MESH_VERTEX":
                current["verts"].append((float(t[2]), float(t[3]), float(t[4])))
            elif tag == "*MESH_FACE":
                # *MESH_FACE 0: A: 0 B: 1 C: 2 AB: ... — индексы в токенах 3/5/7
                current["faces"].append((int(t[3]), int(t[5]), int(t[7])))
            elif tag == "*MESH_VERTCOL":
                current["colors"].append((float(t[2]), float(t[3]), float(t[4])))
            elif tag == "*MESH_CFACE":
                current["cfaces"].append((int(t[2]), int(t[3]), int(t[4])))
            elif tag == "*MESH_TVERT":
                current["uvs"].append((float(t[2]), float(t[3])))
            elif tag == "*MESH_TFACE":
                current["tfaces"].append((int(t[2]), int(t[3]), int(t[4])))
            elif tag == "*MATERIAL_REF":
                current["material"] = int(t[1])

    return objects


def decode_weights(obj):
    """vertex_index -> [(jointID, weight)], нормализованные. Цвет ищем через cface."""
    per_vertex = {}
    for face_i, face in enumerate(obj["faces"]):
        if face_i >= len(obj["cfaces"]):
            break
        cface = obj["cfaces"][face_i]
        for corner in range(3):
            vi = face[corner]
            if vi in per_vertex:
                continue
            ci = cface[corner]
            if ci >= len(obj["colors"]):
                continue

            # Нормировка как в оригинале (humanoidbase.cpp:328-337): делитель —
            # сумма ВСЕХ трёх каналов, включая те, что потом отбрасываются по
            # порогу 0.01. Поэтому оставшиеся веса дают чуть меньше единицы.
            bones = []
            total = 0.0
            decoded = []
            for channel in obj["colors"][ci]:
                c = round(channel * 255.0)
                joint = int(c // 10)
                weight = (c - joint * 10.0) / 9.0
                decoded.append((joint, weight))
                total += weight
            if total > 0.0:
                for joint, weight in decoded:
                    if weight > 0.01:
                        bones.append([joint, weight / total])
            per_vertex[vi] = bones

    return per_vertex


def build(obj):
    mesh = bpy.data.meshes.new(obj["name"])
    mesh.from_pydata(obj["verts"], [], obj["faces"])
    mesh.validate()
    mesh.update()

    ob = bpy.data.objects.new(obj["name"], mesh)
    bpy.context.collection.objects.link(ob)

    weights = decode_weights(obj)
    groups = {}
    for vi, bones in weights.items():
        for joint, weight in bones:
            name = "joint_%02d" % joint
            if name not in groups:
                groups[name] = ob.vertex_groups.new(name=name)
            groups[name].add([vi], weight, "REPLACE")

    joints_used = sorted({j for bones in weights.values() for j, _ in bones})
    return ob, joints_used


def render_preview(out_png, lo_z, hi_z):
    """Превью в фоне: Blender рендерит headless надёжно, камера — три четверти."""
    from mathutils import Vector

    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"

    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    target = Vector((0.0, 0.0, (lo_z + hi_z) * 0.5))
    cam.location = (1.7, -2.9, target.z + 0.35)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    for loc, energy in (((3, -4, 5), 4.0), ((-4, -2, 2), 1.5)):
        light_data = bpy.data.lights.new("key", type="SUN")
        light_data.energy = energy
        light = bpy.data.objects.new("key", light_data)
        light.location = loc
        light.rotation_euler = (0.9, 0.1, 0.6)
        bpy.context.collection.objects.link(light)

    scene.world = bpy.data.worlds.new("w")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.18, 0.21, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6

    scene.render.resolution_x = 700
    scene.render.resolution_y = 900
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    print("превью: %s" % out_png)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src = argv[0]
    out_path = argv[1] if len(argv) > 1 else "fullbody.blend"
    png_path = argv[2] if len(argv) > 2 else ""

    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = parse_ase(src)

    print("\n=== %s: %d объектов ===" % (os.path.basename(src), len(objects)))
    print("%-14s %6s %6s %7s  %s" % ("объект", "верш", "граней", "цветов", "джойнты"))

    lo = [1e9] * 3
    hi = [-1e9] * 3
    for obj in objects:
        if not obj["verts"]:
            continue
        ob, joints_used = build(obj)
        print("%-14s %6d %6d %7d  %s" % (
            obj["name"], len(obj["verts"]), len(obj["faces"]), len(obj["colors"]),
            ", ".join(str(j) for j in joints_used)))
        for v in obj["verts"]:
            for k in range(3):
                lo[k] = min(lo[k], v[k])
                hi[k] = max(hi[k], v[k])

    print("\nгабарит модели: X %.3f..%.3f  Y %.3f..%.3f  Z %.3f..%.3f (рост %.3f м)"
          % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], hi[2] - lo[2]))

    bpy.ops.wm.save_as_mainfile(filepath=out_path)
    print("сохранено: %s" % out_path)

    if png_path:
        render_preview(png_path, lo[2], hi[2])


if __name__ == "__main__":
    main()

# Locked-сцена и «виниловый» материал — единая точка правды для всех рендеров
# персонажа. Смысл фиксации: пока свет, камера и материал гуляют, сравнение двух
# итераций ничего не значит — за форму принимается блик. Меняем здесь, и меняется
# сразу везде.
#
# Стиль (по референсам): матовый пластик/глина, мягкие градиенты на объёме,
# НИКАКИХ текстур кожи и карт нормалей — только цвет и лёгкий подповерхностный
# рассеиватель. Форма должна читаться силуэтом и светотенью, а не детализацией.

import bpy

# Свет намеренно мягкий и с трёх сторон: жёсткий key даёт контрастные тени,
# в которых любая форма выглядит убедительнее, чем она есть.
LIGHTS = (
    # (позиция, поворот, энергия) — key спереди-слева, fill справа, rim сзади
    ((3.0, -4.0, 4.5), (0.95, 0.10, 0.62), 3.2),
    ((-4.0, -2.5, 2.0), (1.25, 0.00, -0.95), 1.1),
    ((-1.5, 3.5, 3.0), (1.05, 0.00, 3.55), 2.0),
)

CAMERAS = {
    "front": (0.0, -4.0, 0.0),
    "three_quarter": (2.0, -3.4, 0.25),
    "side": (3.9, -0.3, 0.0),
}

VINYL = {
    "skin": (0.78, 0.60, 0.48),
    "kit": (0.13, 0.22, 0.72),
    "shorts": (0.90, 0.90, 0.92),
    "blockout": (0.74, 0.72, 0.70),
}


def vinyl_material(name, color):
    """Матовый пластик: без карт, roughness высокий, чуть SSS для мягкости."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.62
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.28
    for key, value in (("Subsurface Weight", 0.06), ("Subsurface Radius", None)):
        if key in bsdf.inputs and value is not None:
            bsdf.inputs[key].default_value = value
    return mat


def setup_scene(background=(0.16, 0.18, 0.21)):
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"

    for location, rotation, energy in LIGHTS:
        data = bpy.data.lights.new("light", type="AREA")
        data.energy = energy * 120.0
        data.size = 3.0
        light = bpy.data.objects.new("light", data)
        light.location = location
        light.rotation_euler = rotation
        bpy.context.collection.objects.link(light)

    scene.world = bpy.data.worlds.new("locked")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*background, 1.0)
    bg.inputs[1].default_value = 0.55

    scene.render.resolution_x = 640
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    return scene


def render(out_png, lo_z, hi_z, view="three_quarter"):
    """Один кадр из locked-сцены. Камера всегда целится в центр фигуры."""
    from mathutils import Vector

    scene = bpy.context.scene
    target = Vector((0.0, 0.0, (lo_z + hi_z) * 0.5))
    offset = CAMERAS.get(view, CAMERAS["three_quarter"])

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 55.0          # длинный фокус: меньше перспективных искажений
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (offset[0], offset[1], target.z + offset[2])
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    print("рендер: %s" % out_png)


def render_ortho(out_png, lo_z, hi_z, view="front", margin=1.06):
    """Ортографический кадр — для метрики силуэта.

    Перспектива искажает пропорции, и метрика мерила бы искажение вместо
    формы; референс тоже просился строго ортографическим.
    """
    from mathutils import Vector

    scene = bpy.context.scene
    height = (hi_z - lo_z)
    target = Vector((0.0, 0.0, (lo_z + hi_z) * 0.5))

    cam_data = bpy.data.cameras.new("cam_ortho")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = height * margin
    cam = bpy.data.objects.new("cam_ortho", cam_data)
    bpy.context.collection.objects.link(cam)

    direction = {"front": (0.0, -4.0, 0.0), "side": (4.0, 0.0, 0.0)}[view]
    cam.location = (direction[0], direction[1], target.z)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    scene.render.resolution_x = 700
    scene.render.resolution_y = int(700 * margin * height / (height * margin))
    scene.render.resolution_y = 980
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    return out_png

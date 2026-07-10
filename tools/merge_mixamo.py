import bpy
import sys
import os

# Аргументы после "--": <src_dir> <out_glb>
argv = sys.argv[sys.argv.index("--") + 1:]
src_dir = argv[0]
out_path = argv[1]

# Чистая пустая сцена
bpy.ops.wm.read_factory_settings(use_empty=True)

# Шим совместимости: некоторые Mixamo-экспорты кладут в FBX объект света. Импортёр
# io_scene_fbx этой сборки Blender 5.1 при импорте света всегда пишет
# lamp.cycles.cast_shadow — атрибута, которого в этой версии Cycles-API больше нет,
# и падает AttributeError, ломая импорт всего файла (а не только света; свет нам
# всё равно не нужен — импортированные объекты анимационных клипов мы позже удаляем
# целиком). Класс настроек Cycles-света не зарегистрирован в bpy.types по фиксированному
# имени до создания реального светового datablock — создаём временный, чтобы получить
# настоящий класс, патчим его, временный datablock удаляем.
_tmp_light = bpy.data.lights.new("tmp_shim_light", type='POINT')
_cycles_light_cls = type(_tmp_light.cycles)
if not hasattr(_cycles_light_cls, "cast_shadow"):
    _cycles_light_cls.cast_shadow = bpy.props.BoolProperty(default=True)
bpy.data.lights.remove(_tmp_light)

# 1) Импорт персонажа со скином (T-pose)
bpy.ops.import_scene.fbx(filepath=os.path.join(src_dir, "character.fbx"),
                         automatic_bone_orientation=True)
main_arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
if main_arm.animation_data is None:
    main_arm.animation_data_create()
# убрать возможный T-pose action, чтобы не экспортировался лишний клип
main_arm.animation_data.action = None

# 2) Импорт анимаций, перенос экшенов на главный армейчер через NLA-треки.
# Берём ЛЮБОЙ *.fbx в src_dir, кроме character.fbx; имя файла (без .fbx) → имя анимации.
# Так добавление клипа = положить файл + пересобрать, без правки этого скрипта.
anim_files = {}
for fname in sorted(os.listdir(src_dir)):
    if not fname.lower().endswith(".fbx"):
        continue
    if fname.lower() == "character.fbx":
        continue
    anim_files[os.path.splitext(fname)[0].lower()] = fname

# Клипы, приехавшие с root motion → морозим трансляцию корневой кости (in-place).
# Значение — какие оси индексов pose.bones["Hips"].location (В BLENDER, до экспорта)
# морозить. ВАЖНО: это ЛОКАЛЬНЫЕ оси кости в её собственном (повёрнутом
# automatic_bone_orientation) базисе — они НЕ совпадают ни с мировыми Blender X/Y/Z,
# ни напрямую с осями экспортированного glTF Position3D-трека (Blender-экспортёр
# переставляет оси при экспорте bone-local кривых). Проверено эмпирически на
# tackle.fbx двумя независимыми способами: (1) в Blender — world_z_delta (мировая
# высота Hips через matrix_world) / local_index1_delta = ровно 0.01 (масштаб
# армейчера) на всех сэмплированных кадрах; (2) в готовом glb — с заморозкой (0,2)
# (индекс 1 живой) итоговый Position3D-трек Hips даёт дугу амплитудой ~0.71м
# (совпадает с (1): 0.998м стоя -> 0.286м низшая точка подката -> 0.949м подъём, без
# дрейфа — реальное движение, не баг), а при заморозке (0,1) (индекс 1 замороженный,
# как было по ошибке в первом фиксе) эта дуга исчезает и остаётся плоским нулём —
# именно так воспроизводится баг "зависания в воздухе". Индексы 0 и 2 — горизонталь
# (мелкий джиттер ~±0.1-0.2м на новом in-place источнике, безопасно морозить).
# roll_left/roll_right: вертикаль и так ничтожна (~5-6см) — глушим все три оси.
# Клип падения (fallen_idle) в IN_PLACE_CLIPS не входит — там опускание таза к земле
# это и есть само падение. standing_up тоже не трогаем (его forward-дрейф естественен).
IN_PLACE_CLIPS = {
    "tackle": (0, 2),
    "roll_left": (0, 1, 2),
    "roll_right": (0, 1, 2),
}

def _action_fcurves(act):
    # Blender 4.4+ "layered actions": legacy Action.fcurves may not exist on
    # actions imported this way (this repo builds with Blender 5.1) — walk
    # layers -> strips -> per-slot channelbag instead.
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    fcurves = []
    for layer in act.layers:
        for strip in layer.strips:
            for slot in act.slots:
                cb = strip.channelbag(slot)
                if cb is not None:
                    fcurves.extend(cb.fcurves)
    return fcurves

def freeze_root_translation(imp_arm, act, axes):
    # Корневая кость Mixamo (без родителя), обычно "mixamorig:Hips".
    root_bone = None
    for b in imp_arm.data.bones:
        if b.parent is None:
            root_bone = b.name
            break
    if root_bone is None:
        print("IN_PLACE: не найдена корневая кость, пропуск")
        return
    path = 'pose.bones["%s"].location' % root_bone
    for fc in _action_fcurves(act):
        if fc.data_path == path and fc.array_index in axes:
            if not fc.keyframe_points:
                continue
            first = fc.keyframe_points[0].co[1]
            for kp in fc.keyframe_points:
                kp.co[1] = first
                kp.handle_left[1] = first
                kp.handle_right[1] = first
            fc.update()
    print("IN_PLACE: заморожена трансляция Hips (оси %s) для action %s" % (axes, act.name))

if not anim_files:
    raise RuntimeError("В %s не найдено ни одного FBX-клипа (кроме character.fbx)" % src_dir)

print("MERGE_ANIMS: " + ", ".join(anim_files.keys()))

for anim_name, fname in anim_files.items():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(src_dir, fname),
                             automatic_bone_orientation=True)
    new_objs = [o for o in bpy.data.objects if o not in before]
    imp_arm = next(o for o in new_objs if o.type == 'ARMATURE')
    act = imp_arm.animation_data.action
    act.name = anim_name
    if anim_name in IN_PLACE_CLIPS:
        freeze_root_translation(imp_arm, act, IN_PLACE_CLIPS[anim_name])
    start = int(act.frame_range[0])
    track = main_arm.animation_data.nla_tracks.new()
    track.name = anim_name
    track.strips.new(anim_name, start, act)
    # удалить импортированные объекты (армейчер+меши), сам экшен остаётся в NLA
    for o in new_objs:
        bpy.data.objects.remove(o, do_unlink=True)

# 3) Экспорт единого glb: каждый NLA-трек → отдельная анимация с его именем
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    export_animation_mode='NLA_TRACKS',
    export_animations=True,
)
print("MERGE_OK")

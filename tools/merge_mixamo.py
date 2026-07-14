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
# ни напрямую с осями экспортированного glTF Position3D-трека.
#
# ЭМПИРИКА tackle.fbx (сырые Blender-единицы, до заморозки):
#   local_index=0 range=26.5   (латеральное смещение — горизонталь)
#   local_index=1 range=71.3   (от -5.6 «стоя» до -76.9 — ПРИСЕД ТАЗА, т.е. ВЕРТИКАЛЬ)
#   local_index=2 range=442.7  (монотонный уезд вперёд — слайд, горизонталь)
# Ключ: Blender local_index=1 экспортируется в glTF/Godot Position3D-ось Z, а у кости Hips
# именно локальная Z = мировая вертикаль (проверено rest-базисом Hips в Godot-скелете:
# local Z -> skeleton +Y). Т.е. index=1 — это ОПУСКАНИЕ ТЕЛА к земле в подкате, а НЕ
# горизонтальный дрейф. Прежняя версия морозила все три (0,1,2) и пришпиливала таз на
# высоте первого кадра («стоя») весь клип → подкатчик ВИСЕЛ В ВОЗДУХЕ. Поэтому для tackle
# морозим ТОЛЬКО горизонталь (0, 2), а вертикаль (1) оставляем живой — таз садится к земле.
# roll_left/roll_right пока морозим все три (жалоб на них нет; их вертикаль мелкая ~12.8).
# fallen_idle/standing_up в IN_PLACE_CLIPS не входят — там опускание/подъём таза естественны.
IN_PLACE_CLIPS = {
    "tackle": (0, 2),
    "roll_left": (0, 1, 2),
    "roll_right": (0, 1, 2),
    # --- Вратарь ---
    # Оси Hips.location (Blender-local): 0=латераль, 1=вертикаль(таз), 2=вперёд.
    # Нижние нырки/боковой шаг — морозим горизонтали (0,2), вертикаль(1) живая (таз садится клипом),
    # как tackle: заморозка вертикали → «висит в воздухе». Верхние нырки — морозим ВСЁ (0,1,2):
    # всю дугу (вбок+вверх) двигает физика divevel.y, поза «в прыжке» — в костях. Начальные оси
    # для catch/catch_top/drop_kick — (0,2); подтвердить сэмпл-скриптом, при подскоке
    # catch_top перевести в (0,1,2).
    "keeper_body_block_l": (0, 2),
    "keeper_body_block_r": (0, 2),
    "keeper_diving_save_l": (0, 1, 2),
    "keeper_diving_save_r": (0, 1, 2),
    "keeper_catch": (0, 2),
    "keeper_catch_top": (0, 2),
    "keeper_sidestep": (0, 2),
    "keeper_drop_kick": (0, 2),
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

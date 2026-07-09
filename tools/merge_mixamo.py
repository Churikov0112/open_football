import bpy
import sys
import os

# Аргументы после "--": <src_dir> <out_glb>
argv = sys.argv[sys.argv.index("--") + 1:]
src_dir = argv[0]
out_path = argv[1]

# Чистая пустая сцена
bpy.ops.wm.read_factory_settings(use_empty=True)

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

# Клипы, приехавшие с root motion → морозим ВСЮ трансляцию корневой кости (делаем
# in-place, включая вертикаль — см. freeze_root_translation). Для уже-in-place клипов
# это no-op. standing_up НЕ трогаем.
IN_PLACE_CLIPS = {"tackle", "roll_left", "roll_right"}

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

def freeze_root_translation(imp_arm, act):
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
    # Морозим ВСЕ три оси (0,1,2) — горизонталь (индексы 0,1 → Godot X,Z) и вертикаль
    # (индекс 2 → Godot Y). Изначально вертикаль оставляли живой ("естественный боб"),
    # но у tackle.fbx она оказалась не бобом, а НЕОГРАНИЧЕННЫМ ДРЕЙФОМ (Hips монотонно
    # уезжает вверх ~4.4м за клип при исходном масштабе 0.01 — на экране это подкатчик,
    # зависающий в воздухе). У roll_left/roll_right вертикальная амплитуда и так мала
    # (~5-6см), так что полная заморозка ничего не портит визуально.
    for fc in _action_fcurves(act):
        if fc.data_path == path and fc.array_index in (0, 1, 2):
            if not fc.keyframe_points:
                continue
            first = fc.keyframe_points[0].co[1]
            for kp in fc.keyframe_points:
                kp.co[1] = first
                kp.handle_left[1] = first
                kp.handle_right[1] = first
            fc.update()
    print("IN_PLACE: заморожена трансляция Hips (все оси) для action %s" % act.name)

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
        freeze_root_translation(imp_arm, act)
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

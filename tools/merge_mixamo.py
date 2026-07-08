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

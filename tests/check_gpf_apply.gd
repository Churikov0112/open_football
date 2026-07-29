extends SceneTree
# Применение кадра: джойнт — абсолютная локальная ротация, player — позиция корня.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func quat_close(a: Quaternion, b: Quaternion, eps := 1.0e-4) -> bool:
	var d1 := absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) + absf(a.w - b.w)
	var d2 := absf(a.x + b.x) + absf(a.y + b.y) + absf(a.z + b.z) + absf(a.w + b.w)
	return minf(d1, d2) < eps

func _initialize() -> void:
	var ok := true
	var skel: Skeleton3D = load("res://src/gpf/SkeletonBuilder.cs").new().BuildUtilitySkeleton()
	get_root().add_child(skel)  # глобальные позы требуют дерева
	var anim = load("res://src/gpf/Animation.cs").new()
	anim.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	var applier = load("res://src/gpf/AnimationApplier.cs").new()

	# Мост C#→GDScript не переносит значения по умолчанию (default_args пуст),
	# поэтому noPos/baseRotZ всегда передаются явно.
	applier.Apply(skel, anim, 12, 0.0, false, 0.0)

	# body: локальная ротация == ключ кадра 12 из файла.
	var body := skel.find_bone("body")
	if not quat_close(skel.get_bone_pose_rotation(body),
			Quaternion(0.060027, -0.163966, -0.174606, 0.969033)):
		print("CHECK FAIL: body pose → ", skel.get_bone_pose_rotation(body)); ok = false

	# player: позиция корня == ключ кадра 12.
	var root := skel.find_bone("player")
	if not vec_eq(skel.get_bone_pose_position(root), Vector3(-0.30, -0.461739, -0.05)):
		print("CHECK FAIL: root pose → ", skel.get_bone_pose_position(root)); ok = false

	# Глобальная поза body = позиция корня + рест-смещение (0,0,0.96): корень не вращается.
	if not vec_eq(skel.get_bone_global_pose(body).origin, Vector3(-0.30, -0.461739, 0.91)):
		print("CHECK FAIL: body global → ", skel.get_bone_global_pose(body).origin); ok = false

	# Позиция джойнтов не затронута ротацией: рест middle остался (0,0,0.15) локально.
	var middle := skel.find_bone("middle")
	if not vec_eq(skel.get_bone_pose_position(middle), Vector3(0, 0, 0.15)):
		print("CHECK FAIL: middle позиция сползла → ", skel.get_bone_pose_position(middle)); ok = false

	# noPos: X,Y корня зануляются, Z остаётся.
	applier.Apply(skel, anim, 12, 0.0, true, 0.0)
	if not vec_eq(skel.get_bone_pose_position(root), Vector3(0, 0, -0.05)):
		print("CHECK FAIL: noPos → ", skel.get_bone_pose_position(root)); ok = false

	skel.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

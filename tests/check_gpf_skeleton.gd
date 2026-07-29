extends SceneTree
# Скелет: 14 костей, иерархия, рест-позы из player.object, базис конверсии осей.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-6) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var builder = load("res://src/gpf/SkeletonBuilder.cs").new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()

	if skel.get_bone_count() != 14:
		print("CHECK FAIL: bone count → ", skel.get_bone_count()); ok = false

	# Иерархия: пары (кость, родитель).
	var parents := {
		"body": "player", "middle": "body", "neck": "middle",
		"left_shoulder": "middle", "left_elbow": "left_shoulder",
		"right_shoulder": "middle", "right_elbow": "right_shoulder",
		"left_thigh": "body", "left_knee": "left_thigh", "left_ankle": "left_knee",
		"right_thigh": "body", "right_knee": "right_thigh", "right_ankle": "right_knee",
	}
	for bone in parents:
		var idx := skel.find_bone(bone)
		if idx < 0:
			print("CHECK FAIL: нет кости ", bone); ok = false; continue
		var pidx := skel.get_bone_parent(idx)
		if pidx < 0 or skel.get_bone_name(pidx) != parents[bone]:
			print("CHECK FAIL: родитель ", bone, " → ", skel.get_bone_name(pidx) if pidx >= 0 else "нет"); ok = false
	if skel.get_bone_parent(skel.find_bone("player")) != -1:
		print("CHECK FAIL: player должен быть корнем"); ok = false

	# Рест-позы (player.object, дословно).
	var rests := {
		"player": Vector3(0, 0, 0), "body": Vector3(0, 0, 0.96), "middle": Vector3(0, 0, 0.15),
		"neck": Vector3(0, -0.03, 0.5),
		"left_shoulder": Vector3(0.16, -0.01, 0.48), "left_elbow": Vector3(-0.01, 0, -0.33),
		"right_shoulder": Vector3(-0.16, -0.01, 0.48), "right_elbow": Vector3(0.01, 0, -0.33),
		"left_thigh": Vector3(0.087, 0, -0.01), "left_knee": Vector3(0, 0, -0.42),
		"left_ankle": Vector3(0, -0.04, -0.44),
		"right_thigh": Vector3(-0.087, 0, -0.01), "right_knee": Vector3(0, 0, -0.42),
		"right_ankle": Vector3(0, -0.04, -0.44),
	}
	for bone in rests:
		var idx := skel.find_bone(bone)
		if idx >= 0 and not vec_eq(skel.get_bone_rest(idx).origin, rests[bone]):
			print("CHECK FAIL: rest ", bone, " → ", skel.get_bone_rest(idx).origin); ok = false

	# Базис конверсии: собственная ротация, «их вперёд» (0,-1,0) → Godot (0,0,-1), «их верх» → (0,1,0).
	var wrapper: Node3D = builder.BuildAxisWrapper()
	var b: Basis = wrapper.basis
	if absf(b.determinant() - 1.0) > 1.0e-6:
		print("CHECK FAIL: det базиса → ", b.determinant()); ok = false
	if not vec_eq(b * Vector3(0, -1, 0), Vector3(0, 0, -1)):
		print("CHECK FAIL: их-вперёд → ", b * Vector3(0, -1, 0)); ok = false
	if not vec_eq(b * Vector3(0, 0, 1), Vector3(0, 1, 0)):
		print("CHECK FAIL: их-верх → ", b * Vector3(0, 0, 1)); ok = false

	skel.free()
	wrapper.free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

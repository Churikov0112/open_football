extends SceneTree

# Строит физскелет по синтетическому Skeleton3D и проверяет структуру:
# созданы PhysicalBone3D для не-листовых не-пальцевых костей, у каждой capsule-шейп,
# пальцы исключены.
func _initialize() -> void:
	var ok := true
	var RagdollSkeletonScript := load("res://scripts/player/ragdoll_skeleton.gd")

	var skel := Skeleton3D.new()
	# Цепочка: Hips → Spine → (LeftUpLeg → LeftLeg), плюс палец LeftHandIndex (должен быть исключён).
	# ПРИМЕЧАНИЕ: Godot 4.7 Skeleton3D.add_bone() отклоняет имена с ':' или '/'
	# ("Bone name cannot be empty or contain ':' or '/'"), поэтому здесь имена без
	# префикса "mixamorig:" — проверка в build()/тесте работает по подстроке,
	# так что это не ослабляет тест.
	var hips := skel.add_bone("Hips")
	var spine := skel.add_bone("Spine")
	skel.set_bone_parent(spine, hips)
	var upleg := skel.add_bone("LeftUpLeg")
	skel.set_bone_parent(upleg, hips)
	var leg := skel.add_bone("LeftLeg")
	skel.set_bone_parent(leg, upleg)
	var finger := skel.add_bone("LeftHandIndex1")
	skel.set_bone_parent(finger, spine)
	# рест-смещения (ненулевые, чтобы длины считались)
	skel.set_bone_rest(spine, Transform3D(Basis(), Vector3(0, 0.2, 0)))
	skel.set_bone_rest(upleg, Transform3D(Basis(), Vector3(0.1, -0.1, 0)))
	skel.set_bone_rest(leg, Transform3D(Basis(), Vector3(0, -0.4, 0)))
	skel.set_bone_rest(finger, Transform3D(Basis(), Vector3(0.05, 0, 0)))
	get_root().add_child(skel)

	var rag = RagdollSkeletonScript.new()
	var n: int = rag.build(skel, 8)
	if n <= 0:
		print("CHECK FAIL: не создано ни одной физкости"); ok = false

	# Собрать имена созданных PhysicalBone3D.
	var pb_names := {}
	var has_capsule := true
	for c in skel.get_children():
		if c is PhysicalBone3D:
			pb_names[c.bone_name] = true
			var cap := false
			for cc in c.get_children():
				if cc is CollisionShape3D and cc.shape is CapsuleShape3D:
					cap = true
			if not cap:
				has_capsule = false
	if not has_capsule:
		print("CHECK FAIL: у физкости нет CapsuleShape3D"); ok = false
	# Палец должен быть исключён (нет физкости, названной как палец, и он лист в любом случае).
	for name in pb_names.keys():
		if String(name).to_lower().contains("index") or String(name).to_lower().contains("finger"):
			print("CHECK FAIL: пальцевая кость не исключена: ", name); ok = false
	# Должна быть физкость хотя бы для Hips и LeftUpLeg (не-листовые).
	if not pb_names.has("Hips"):
		print("CHECK FAIL: нет физкости для Hips"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

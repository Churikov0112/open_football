extends SceneTree

# Строит физскелет по синтетическому Skeleton3D и проверяет структуру:
# созданы PhysicalBone3D для не-листовых не-пальцевых костей, у каждой capsule-шейп,
# пальцы исключены.
#
# build() читает skeleton.global_transform (масштаб предка) — это требует, чтобы узел
# был по-настоящему в дереве, а не просто добавлен той же функцией (add_child в
# _initialize() не гарантирует это синхронно в headless SceneTree). Поэтому build()
# и проверки отложены на первый кадр _process(), как в check_ragdoll_real_skeleton.gd.

var _skel: Skeleton3D
var _done := false

func _initialize() -> void:
	_skel = Skeleton3D.new()
	# Цепочка: Hips → Spine → (LeftUpLeg → LeftLeg), плюс палец LeftHandIndex (должен быть исключён).
	# ПРИМЕЧАНИЕ: Godot 4.7 Skeleton3D.add_bone() отклоняет имена с ':' или '/'
	# ("Bone name cannot be empty or contain ':' or '/'"), поэтому здесь имена без
	# префикса "mixamorig:" — проверка в build()/тесте работает по подстроке,
	# так что это не ослабляет тест.
	var hips := _skel.add_bone("Hips")
	var spine := _skel.add_bone("Spine")
	_skel.set_bone_parent(spine, hips)
	var upleg := _skel.add_bone("LeftUpLeg")
	_skel.set_bone_parent(upleg, hips)
	var leg := _skel.add_bone("LeftLeg")
	_skel.set_bone_parent(leg, upleg)
	var finger := _skel.add_bone("LeftHandIndex1")
	_skel.set_bone_parent(finger, spine)
	# рест-смещения (ненулевые, чтобы длины считались)
	_skel.set_bone_rest(spine, Transform3D(Basis(), Vector3(0, 0.2, 0)))
	_skel.set_bone_rest(upleg, Transform3D(Basis(), Vector3(0.1, -0.1, 0)))
	_skel.set_bone_rest(leg, Transform3D(Basis(), Vector3(0, -0.4, 0)))
	_skel.set_bone_rest(finger, Transform3D(Basis(), Vector3(0.05, 0, 0)))
	get_root().add_child(_skel)

func _process(_delta: float) -> bool:
	if _done:
		return true
	if _skel == null or not _skel.is_inside_tree():
		return false
	_done = true

	var ok := true
	var RagdollSkeletonScript := load("res://scripts/player/ragdoll_skeleton.gd")
	var rag = RagdollSkeletonScript.new()
	var n: int = rag.build(_skel, 8)
	if n <= 0:
		print("CHECK FAIL: не создано ни одной физкости"); ok = false

	# Собрать имена созданных PhysicalBone3D.
	var pb_names := {}
	var has_capsule := true
	for c in _skel.get_children():
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
	# Должна быть физкость для Hips, Spine (единственный ребёнок которого — исключённый
	# палец: регрессия на конфликт leaf-test/sizing) и LeftUpLeg (не-листовые).
	if not pb_names.has("Hips"):
		print("CHECK FAIL: нет физкости для Hips"); ok = false
	if not pb_names.has("Spine"):
		print("CHECK FAIL: нет физкости для Spine (единственный ребёнок — исключённый палец)"); ok = false
	if not pb_names.has("LeftUpLeg"):
		print("CHECK FAIL: нет физкости для LeftUpLeg"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true

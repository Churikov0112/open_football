extends SceneTree

# Строит физскелет по РЕАЛЬНОМУ Skeleton3D из assets/models/footballer.glb и проверяет,
# что билдер действительно работает на настоящих именах костей Mixamo (не только на
# синтетическом тесте) — в частности, что предплечья/руки не теряются из-за бага
# leaf-detection (единственный ребёнок предплечья — исключённая кисть).
func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _initialize() -> void:
	var ok := true

	var packed: PackedScene = load("res://assets/models/footballer.glb")
	if packed == null:
		print("CHECK FAIL: не удалось загрузить footballer.glb")
		quit(1)
		return

	var instance := packed.instantiate()
	get_root().add_child(instance)

	var skel := _find_skeleton(instance)
	if skel == null:
		print("CHECK FAIL: Skeleton3D не найден в footballer.glb")
		quit(1)
		return

	var RagdollSkeletonScript := load("res://scripts/player/ragdoll_skeleton.gd")
	var rag = RagdollSkeletonScript.new()
	var n: int = rag.build(skel, 8)

	print("Построено физкостей: ", n)

	var names: Array = []
	for c in skel.get_children():
		if c is PhysicalBone3D:
			names.append(String(c.bone_name))
	print("Имена (первые 15): ", names.slice(0, 15))

	if n <= 5:
		print("CHECK FAIL: слишком мало физкостей построено: ", n); ok = false

	var has_hips := false
	var has_forearm := false
	var has_excluded := false
	var excluded_substrings := ["finger", "index", "thumb", "hand", "toe"]
	for bone_name in names:
		var lower: String = String(bone_name).to_lower()
		if lower.contains("hips"):
			has_hips = true
		if lower.contains("forearm"):
			has_forearm = true
		for ex in excluded_substrings:
			if lower.contains(ex):
				has_excluded = true

	if not has_hips:
		print("CHECK FAIL: среди построенных костей нет 'hips'"); ok = false
	if not has_forearm:
		print("CHECK FAIL: среди построенных костей нет 'forearm' (предплечья потеряны?)"); ok = false
	if has_excluded:
		print("CHECK FAIL: среди построенных костей есть исключённая (палец/кисть/носок)"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

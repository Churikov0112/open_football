extends SceneTree

# Строит физскелет по РЕАЛЬНОМУ Skeleton3D из assets/models/footballer.glb и проверяет,
# что билдер действительно работает на настоящих именах костей Mixamo (не только на
# синтетическом тесте) — в частности, что предплечья/руки не теряются из-за бага
# leaf-detection (единственный ребёнок предплечья — исключённая кисть), и что капсулы
# получаются в человеческом мировом масштабе (не за счёт масштаба предка Skeleton3D).
#
# build() сам читает skeleton.global_transform (нужен реальный масштаб предка) — это
# требует, чтобы узел был по-настоящему в дереве, а не просто добавлен той же функцией
# (add_child в _initialize() не гарантирует это синхронно в headless SceneTree, в отличие
# от боевого пути через PlayerVisual._ready(), который вызывается только когда узел уже
# полностью в дереве). Поэтому build() и все проверки отложены на первый кадр _process().

var _skel: Skeleton3D
var _done := false

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _initialize() -> void:
	var packed: PackedScene = load("res://assets/models/footballer.glb")
	if packed == null:
		print("CHECK FAIL: не удалось загрузить footballer.glb")
		quit(1)
		return

	var instance := packed.instantiate()
	get_root().add_child(instance)

	_skel = _find_skeleton(instance)
	if _skel == null:
		print("CHECK FAIL: Skeleton3D не найден в footballer.glb")
		quit(1)
		return

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

	print("Построено физкостей: ", n)

	var names: Array = []
	for c in _skel.get_children():
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

	# Санити на РЕАЛЬНЫЙ мировой размер капсул: Skeleton3D часто сидит под масштабированным
	# предком (Mixamo: 0.01, cm→m без запекания), а PhysicalBone3D всегда работает в
	# настоящих метрах — без поправки на масштаб капсулы получаются в 1/scale раз больше
	# (человеческая кость ~9-15 "сырых" единиц превращается в 9-15 МЕТРОВ). Держим диапазон
	# широким (человеческие сегменты костей примерно 0.02–1.0м), чтобы не биться о живой тюнинг.
	for c in _skel.get_children():
		if c is PhysicalBone3D:
			for cc in c.get_children():
				if cc is CollisionShape3D and cc.shape is CapsuleShape3D:
					var cap: CapsuleShape3D = cc.shape
					var world_height: float = cap.height * cc.global_transform.basis.get_scale().y
					if world_height > 1.0 or world_height < 0.02:
						print("CHECK FAIL: капсула '", c.bone_name, "' мирового размера ", world_height,
							"м — не в человеческом диапазоне 0.02–1.0м (масштаб предка не учтён?)")
						ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true

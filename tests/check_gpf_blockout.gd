extends SceneTree

# Болванка персонажа обязана прийти из Blender на скелете, побитово совпадающем
# с Gpf.SkeletonBuilder: те же имена, та же иерархия, те же рест-позиции и
# ЕДИНИЧНЫЙ рест-базис. AnimationApplier пишет джойнтам абсолютную локальную
# ориентацию (SetBonePoseRotation замещает рест, а не композируется с ним) —
# любой поворот в ресте развернёт конечность на этот угол.

# Переопределяется переменной окружения GPF_MODEL (пусто → болванка) —
# контракт скелета обязателен для любого тела на GPF-скелете.
var MODEL: String = OS.get_environment("GPF_MODEL") if OS.get_environment("GPF_MODEL") != "" \
		else "res://assets/models/gpf_blockout.glb"
const EPS := 0.0005

var _fails := 0


func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("  FAIL: ", msg)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _initialize() -> void:
	print("== check_gpf_blockout ==")

	if not ResourceLoader.exists(MODEL):
		_fail("нет модели %s — собери tools/build_gpf_blockout.py" % MODEL)
		_done()
		return

	var packed: PackedScene = load(MODEL)
	var root: Node = packed.instantiate()
	var skel: Skeleton3D = _find_skeleton(root)
	if skel == null:
		_fail("в %s нет Skeleton3D" % MODEL)
		root.free()
		_done()
		return

	var builder = load("res://src/gpf/SkeletonBuilder.cs").new()
	var ref_skel: Skeleton3D = builder.BuildUtilitySkeleton()

	print("костей: болванка %d, эталон %d" % [skel.get_bone_count(), ref_skel.get_bone_count()])
	if skel.get_bone_count() != ref_skel.get_bone_count():
		_fail("число костей разошлось")

	for ref_idx in ref_skel.get_bone_count():
		var name: String = ref_skel.get_bone_name(ref_idx)
		var idx: int = skel.find_bone(name)
		if idx < 0:
			_fail("нет кости '%s'" % name)
			continue

		var ref_rest: Transform3D = ref_skel.get_bone_rest(ref_idx)
		var rest: Transform3D = skel.get_bone_rest(idx)

		var d: float = (rest.origin - ref_rest.origin).length()
		if d > EPS:
			_fail("'%s' рест-позиция %v против эталонной %v (расхождение %.4f м)"
					% [name, rest.origin, ref_rest.origin, d])

		if not rest.basis.is_equal_approx(Basis.IDENTITY):
			_fail("'%s' рест-базис не единичный: %s" % [name, rest.basis])

		# Иерархия: у порта она задаёт, в чьём пространстве живёт ориентация клипа.
		var ref_parent: String = ("" if ref_skel.get_bone_parent(ref_idx) < 0
				else ref_skel.get_bone_name(ref_skel.get_bone_parent(ref_idx)))
		var parent: String = ("" if skel.get_bone_parent(idx) < 0
				else skel.get_bone_name(skel.get_bone_parent(idx)))
		if parent != ref_parent:
			_fail("'%s' родитель '%s', эталон '%s'" % [name, parent, ref_parent])

	root.free()
	ref_skel.free()
	_done()


func _done() -> void:
	if _fails == 0:
		print("OK: скелет болванки совпадает с Gpf.SkeletonBuilder")
	else:
		print("ПРОВАЛЕНО: %d расхождений" % _fails)
	quit(1 if _fails > 0 else 0)

extends SceneTree

# В headless-SceneTree add_child в _initialize НЕ запускает _ready синхронно — дерево
# ещё не крутит кадры. Поэтому инстансим здесь, а проверку делаем в _process, когда
# узел уже is_node_ready().

var _inst: Node

func _initialize() -> void:
	var scene := load("res://scenes/player_visual.tscn") as PackedScene
	if scene == null:
		print("CHECK FAIL: не загрузилась scenes/player_visual.tscn")
		quit(1)
		return
	_inst = scene.instantiate()
	root.add_child(_inst)  # _ready отложится до первого кадра

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null

func _process(_delta: float) -> bool:
	if _inst == null or not _inst.is_node_ready():
		return false  # ждём, пока отработает _ready
	var ok := true
	# One-shot стейты подката/перекатов/вставания должны быть зарегистрированы.
	var want := ["tackle", "roll_left", "roll_right", "standing_up"]
	for a in want:
		if not _inst.has_action(a):
			print("CHECK FAIL: нет one-shot стейта под действие '%s'" % a)
			ok = false
		else:
			print("CHECK: действие '%s' → стейт есть" % a)
	# Дремлющий физскелет должен быть построен в _ready.
	var skel := _find_skeleton(_inst)
	if skel == null:
		print("CHECK FAIL: не найден Skeleton3D в инстансе player_visual")
		ok = false
	else:
		var bone_count := 0
		for c in skel.get_children():
			if c is PhysicalBone3D:
				bone_count += 1
		if bone_count <= 0:
			print("CHECK FAIL: 0 PhysicalBone3D под Skeleton3D — ragdoll не построен")
			ok = false
		else:
			print("CHECK: найдено %d PhysicalBone3D под Skeleton3D" % bone_count)
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true

extends SceneTree
## hold_pose('throw_in') замораживает визуал на кадре 0 (TimeScale=0); несуществующий клип → false;
## последующий trigger() восстанавливает скорость проигрывания.

var _inst: Node

func _initialize() -> void:
	var scene := load("res://scenes/player_visual.tscn") as PackedScene
	if scene == null:
		print("CHECK FAIL: не загрузилась scenes/player_visual.tscn")
		quit(1)
		return
	_inst = scene.instantiate()
	root.add_child(_inst)

func _process(_delta: float) -> bool:
	if _inst == null or not _inst.is_node_ready():
		return false
	var ok := true
	# hold_pose существующего клипа → true и TimeScale=0.
	if not _inst.hold_pose("throw_in"):
		print("CHECK FAIL: hold_pose('throw_in') вернул false")
		ok = false
	else:
		var scale: float = _inst._anim_tree.get(&"parameters/TimeScale/scale")
		if not is_equal_approx(scale, 0.0):
			print("CHECK FAIL: после hold_pose TimeScale=%f, ожидалось 0" % scale)
			ok = false
	# hold_pose несуществующего клипа → false.
	if _inst.hold_pose("no_such_clip"):
		print("CHECK FAIL: hold_pose несуществующего клипа вернул true")
		ok = false
	# trigger() снимает заморозку — TimeScale снова > 0.
	if not _inst.trigger("throw_in"):
		print("CHECK FAIL: trigger('throw_in') вернул false")
		ok = false
	else:
		var scale2: float = _inst._anim_tree.get(&"parameters/TimeScale/scale")
		if scale2 <= 0.0:
			print("CHECK FAIL: после trigger TimeScale=%f, ожидалось >0" % scale2)
			ok = false
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true

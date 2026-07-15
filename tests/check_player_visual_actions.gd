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

func _process(_delta: float) -> bool:
	if _inst == null or not _inst.is_node_ready():
		return false  # ждём, пока отработает _ready
	var ok := true
	# Действия, для которых у нас есть клипы в footballer.glb.
	var want := ["kick", "pass", "penalty_l", "penalty_r", "throw_in"]
	for a in want:
		if not _inst.has_action(a):
			print("CHECK FAIL: нет one-shot стейта под действие '%s'" % a)
			ok = false
		else:
			print("CHECK: действие '%s' → стейт есть" % a)
	if _inst.has_action("no_such_action"):
		print("CHECK FAIL: has_action вернул true для несуществующего действия")
		ok = false
	# consume_root_motion в покое (без активного клипа удара) не падает и возвращает 0.
	var rm: float = _inst.consume_root_motion()
	if rm != 0.0:
		print("CHECK FAIL: consume_root_motion в покое = %f, ожидалось 0" % rm)
		ok = false
	else:
		print("CHECK: consume_root_motion в покое = 0")
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true

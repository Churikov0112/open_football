extends SceneTree

# Проверяет, что PlayerVisual регистрирует все one-shot стейты, нужные для анимационного
# падения жертвы подката (Path B): подкат, поза «лежит», перекаты, вставание.
#
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
	# One-shot стейты цепочки падения (подкат/лежит/перекаты/вставание) должны быть зарегистрированы.
	var want := ["tackle", "fallen_idle", "roll_left", "roll_right", "standing_up"]
	for a in want:
		if not _inst.has_action(a):
			print("CHECK FAIL: нет one-shot стейта под клип '%s'" % a)
			ok = false
		else:
			print("CHECK: клип '%s' → стейт есть" % a)
	# Негативный кейс: несуществующий клип не должен резолвиться в стейт.
	if _inst.has_action("no_such_clip"):
		print("CHECK FAIL: has_action вернул true для несуществующего клипа")
		ok = false
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true

extends SceneTree

# add_child в _initialize не запускает _ready синхронно (дерево не крутит кадры),
# поэтому инстансим здесь, а проверяем в _process по is_node_ready().
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
	var at := _inst.get_node_or_null(^"AnimTree")
	if at == null:
		print("CHECK FAIL: нет узла AnimTree")
		print("CHECK FAIL"); quit(1); return true
	# playback существует по новому пути (значит StateMachine внутри BlendTree подключён)
	if at.get(&"parameters/sm/playback") == null:
		print("CHECK FAIL: нет parameters/sm/playback")
		ok = false
	# TimeScale-параметр читается/пишется
	at.set(&"parameters/TimeScale/scale", 2.0)
	if not is_equal_approx(at.get(&"parameters/TimeScale/scale"), 2.0):
		print("CHECK FAIL: parameters/TimeScale/scale не выставился, got=", at.get(&"parameters/TimeScale/scale"))
		ok = false
	# one-shot стейты по-прежнему резолвятся
	if not _inst.has_action("pass"):
		print("CHECK FAIL: has_action('pass') == false после перестройки дерева")
		ok = false
	# KEEPER-локомоция: стейт keeper_sidestep создан (клип есть в glb).
	if not _inst.has_loco_state(PlayerVisual.LOCO_KEEPER_SIDE):
		print("CHECK FAIL: нет стейта локомоции keeper_sidestep")
		ok = false
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true

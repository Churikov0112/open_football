extends SceneTree
## Seam Фазы 2: player.tscn имеет корень Player с brain(); Brain кэширует _body и отдаёт дефолты;
## set_active переключает физпроцесс. Работа отложена на _process (root не is_inside_tree() в
## _initialize — тот же паттерн, что в check_player_factory.gd).

var _done: bool = false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var ok := true

	var body := preload("res://scenes/player.tscn").instantiate()
	root.add_child(body)
	if not (body is Player):
		ok = false; print("CHECK FAIL: root is not Player")
	if body.brain() != null:
		ok = false; print("CHECK FAIL: brain() should be null before attach")

	var b := Brain.new()
	b.name = "Brain"
	body.add_child(b)                       # _ready → _body = get_parent()
	if body.brain() != b:
		ok = false; print("CHECK FAIL: brain() did not find the child Brain")
	if b.body() != body:
		ok = false; print("CHECK FAIL: Brain._body is not the parent body")
	if b.movement_intent() != Vector3.ZERO:
		ok = false; print("CHECK FAIL: movement_intent default not ZERO")
	if b.speed_scale() != 0.0:
		ok = false; print("CHECK FAIL: speed_scale default not 0")

	b.set_active(true)
	if not b.is_physics_processing():
		ok = false; print("CHECK FAIL: set_active(true) did not enable physics process")
	b.set_active(false)
	if b.is_physics_processing():
		ok = false; print("CHECK FAIL: set_active(false) did not disable physics process")

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true

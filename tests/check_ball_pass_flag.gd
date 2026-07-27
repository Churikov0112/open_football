extends SceneTree
## Флаг бэк-паса: note_pass_from ставит; set_dribbler и block_in_flight снимают.
## Мяч создаём кодом (RigidBody3D + скрипт), как check_ball_state.gd — без match.tscn/ball.tscn
## (у последней дочерние узлы без parent=".", standalone instantiate падает; скрипт мяча в игре
## крепится кодом в match_manager). Всё синхронно: флаг-методы не зависят от _ready/физкадров.

func _initialize() -> void:
	var ball := RigidBody3D.new()
	ball.set_script(load("res://scripts/ball/ball_controller.gd"))
	root.add_child(ball)
	_run(ball)

func _run(ball) -> void:
	var ok := true
	if ball.pass_from_team() != &"":
		print("CHECK FAIL: начальный флаг не пуст"); ok = false
	ball.note_pass_from(&"team_1")
	if ball.pass_from_team() != &"team_1":
		print("CHECK FAIL: note_pass_from не поставил"); ok = false
	ball.block_in_flight()
	if ball.pass_from_team() != &"":
		print("CHECK FAIL: block_in_flight не снял флаг"); ok = false
	ball.note_pass_from(&"team_2")
	ball.set_dribbler(null)   # любой трап/касание снимает
	if ball.pass_from_team() != &"":
		print("CHECK FAIL: set_dribbler не снял флаг"); ok = false
	if ok:
		print("CHECK PASS: back-pass flag set/clear")
		quit(0)
	else:
		quit(1)

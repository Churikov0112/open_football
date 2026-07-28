extends SceneTree
## Пас НА вратаря наводится/долетает, но НЕ отдаёт ему управление (гейт role_gk в fire_pass):
## вратарь остаётся ИИ (controlled_player НЕ становится вратарём), сам соберёт мяч в ноги позже.
var _mm; var _f := 0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f < 8:
		return
	_mm.set_kickoff_active(false)
	var keeper = _mm._team_home.keeper()
	var passer = _mm.controlled_player
	if keeper == null or passer == null:
		print("CHECK FAIL: нет keeper/passer"); quit(1); return
	# Прочих полевых team_1 — далеко, чтобы select_target выбрал ИМЕННО вратаря.
	for n in _mm.get_tree().get_nodes_in_group("team_1"):
		if n != passer and not n.is_in_group("role_gk"):
			n.global_position = Vector3(100, 0.5, 100)
	# Пасующий — в 15 м перед вратарём, мяч ему в ноги, прицел строго на вратаря.
	var into: float = signf(-keeper.brain().goal_line_z)
	passer.global_position = keeper.global_position + Vector3(0, 0, into * 15.0)
	var ball = _mm.ball
	ball.global_position = passer.global_position + Vector3(0, 0.1, 0)
	ball.set_dribbler(passer, true)
	var aim: Vector3 = keeper.global_position - passer.global_position
	aim.y = 0.0
	var pass_short: int = MatchManager.ChargeAction.PASS_SHORT
	_mm._action_executor.fire_pass(pass_short, passer, 0.7, aim.normalized())
	# Управление НЕ должно уйти на вратаря (гейт role_gk).
	if _mm.controlled_player == keeper:
		print("CHECK FAIL: пас на вратаря отдал ему управление"); quit(1); return
	print("CHECK PASS: pass to keeper does not hand control (keeper stays AI)"); quit(0); return

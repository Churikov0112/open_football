extends SceneTree
## Бэк-пас: мяч, ПОМЕЧЕННЫЙ намеренным пасом своей команды, вратарь берёт НЕ руками, а в ноги
## (dribbler==keeper, НЕ is_caught) → OUTFIELD. Медленный мяч в зоне трапа у вратаря.
var _mm; var _k; var _b; var _f := 0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 8:
		_mm.set_kickoff_active(false)
		_k = _mm._team_home.keeper(); _b = _k.brain()
		# Кладём медленный мяч у ног вратаря и помечаем его пасом СВОЕЙ (team_1) команды.
		var kp = _k.global_position
		_mm.ball.global_position = Vector3(kp.x, FootballConstants.BALL_RADIUS + 0.02, kp.z + signf(-_b.goal_line_z) * 0.4)
		_mm.ball.linear_velocity = Vector3(0, 0, signf(-_b.goal_line_z) * -1.0)  # тихо катится во вратаря
		_mm.ball.set_dribbler(null)             # OPEN
		_mm.ball.note_pass_from(&"team_1")      # намеренный пас своего
		_mm.ball.state = _mm.ball.BallState.FLIGHT   # эмулируем «летящий» для рефлекса
		_b.on_ball_contact()
		return
	if _f == 20:
		if _mm.ball.is_caught():
			print("CHECK FAIL: вратарь взял бэк-пас РУКАМИ"); quit(1); return
		if _mm.ball.dribbler != _k:
			print("CHECK FAIL: вратарь не трапнул бэк-пас в ноги (dribbler=", _mm.ball.dribbler, ")"); quit(1); return
		if _b._state != _b.State.OUTFIELD:
			print("CHECK FAIL: не в OUTFIELD после бэк-паса (state=", _b._state, ")"); quit(1); return
		print("CHECK PASS: keeper backpass → outfield (no hands)"); quit(0); return

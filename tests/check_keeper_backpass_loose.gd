extends SceneTree
## Бэк-пас без явной метки (перенято из OpenSoccer «не беру мяч своих»): БЕСХОЗНЫЙ МЕДЛЕННЫЙ мяч,
## последним трогал СВОЙ полевой (last_touch, не note_pass_from) → вратарь берёт НЕ руками, а в
## ноги (dribbler==keeper, НЕ is_caught) → OUTFIELD. Контроль: быстрый мяч своих так НЕ берётся.
var _mm; var _k; var _b; var _mate; var _f := 0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 8:
		_mm.set_kickoff_active(false)
		_k = _mm._team_home.keeper(); _b = _k.brain()
		for n in _mm.get_tree().get_nodes_in_group("team_1"):
			if not n.is_in_group("role_gk"):
				_mate = n; break
		if _mate == null:
			print("CHECK FAIL: нет полевого team_1 для last_touch"); quit(1); return
		# Медленный бесхозный мяч у ног вратаря, последним трогал СВОЙ полевой (без note_pass_from).
		var kp = _k.global_position
		_mm.ball.global_position = Vector3(kp.x, FootballConstants.BALL_RADIUS + 0.02, kp.z + signf(-_b.goal_line_z) * 0.4)
		_mm.ball.linear_velocity = Vector3(0, 0, signf(-_b.goal_line_z) * -1.0)  # тихо катится во вратаря (< CAP)
		_mm.ball.set_dribbler(null)             # OPEN (бесхозный)
		_mm.ball.note_touch(_mate)              # последним трогал СВОЙ полевой (не флаг паса)
		_mm.ball.state = _mm.ball.BallState.FLIGHT
		_b.on_ball_contact()
		return
	if _f == 20:
		if _mm.ball.is_caught():
			print("CHECK FAIL: вратарь взял мяч своих РУКАМИ"); quit(1); return
		if _mm.ball.dribbler != _k:
			print("CHECK FAIL: вратарь не трапнул мяч своих в ноги (dribbler=", _mm.ball.dribbler, ")"); quit(1); return
		if _b._state != _b.State.OUTFIELD:
			print("CHECK FAIL: не в OUTFIELD после приёма мяча своих (state=", _b._state, ")"); quit(1); return
		print("CHECK PASS: keeper takes own slow loose ball to feet (OpenSoccer-style, no flag)"); quit(0); return

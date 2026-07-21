extends SceneTree
## Headless-проверка чистых функций GoalKickLogic.

func _init() -> void:
	var ok := true
	ok = _check_spot() and ok
	ok = _check_runup() and ok
	ok = _check_clear_inside() and ok
	ok = _check_clear_outside_depth() and ok
	ok = _check_clear_outside_width() and ok
	if ok:
		print("CHECK PASS: goal_kick_logic")
		quit(0)
	else:
		print("CHECK FAIL: goal_kick_logic")
		quit(1)

func _check_spot() -> bool:
	# Ворота Home на -52.5, into=+1 (в поле), линия вратарской 5.5 м.
	var s := GoalKickLogic.spot_position(-52.5, 1.0, 5.5, 0.12)
	if not (is_equal_approx(s.x, 0.0) and is_equal_approx(s.y, 0.12) and is_equal_approx(s.z, -47.0)):
		print("  FAIL spot: ", s)
		return false
	return true

func _check_runup() -> bool:
	# Бьющий позади мяча вдоль -forward, латерально под правую ногу.
	var spot := Vector3(0.0, 0.12, -47.0)
	var p := GoalKickLogic.runup_placement(spot, Vector3(0, 0, 1), 3.0, 0.5, "penalty_r", 0.5)
	if not (is_equal_approx(p.x, 0.5) and is_equal_approx(p.z, -50.0) and is_equal_approx(p.y, 0.5)):
		print("  FAIL runup: ", p)
		return false
	return true

func _check_clear_inside() -> bool:
	# Соперник в штрафной (rel=7.5 в [0,16.5], |x|<20.16) → вытолкнут за 16.5 + запас.
	var out := GoalKickLogic.push_out_of_penalty_area(Vector3(5, 0.5, -45), -52.5, 1.0, 16.5, 20.16, 1.0)
	if not (is_equal_approx(out.x, 5.0) and is_equal_approx(out.z, -35.0) and is_equal_approx(out.y, 0.5)):
		print("  FAIL clear_inside: ", out)
		return false
	return true

func _check_clear_outside_depth() -> bool:
	# rel=22.5 > 16.5 → без изменений.
	var pos := Vector3(5, 0.5, -30)
	var out := GoalKickLogic.push_out_of_penalty_area(pos, -52.5, 1.0, 16.5, 20.16, 1.0)
	if not out.is_equal_approx(pos):
		print("  FAIL clear_outside_depth: ", out)
		return false
	return true

func _check_clear_outside_width() -> bool:
	# |x|=25 > 20.16 → без изменений.
	var pos := Vector3(25, 0.5, -45)
	var out := GoalKickLogic.push_out_of_penalty_area(pos, -52.5, 1.0, 16.5, 20.16, 1.0)
	if not out.is_equal_approx(pos):
		print("  FAIL clear_outside_width: ", out)
		return false
	return true

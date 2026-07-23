extends SceneTree
## Headless-проверка чистых функций BoundaryLogic (классификация выхода + точки рестарта).
## Поле: half_len=52.5, half_width=34, goal_half_width=3.66, ball_radius=0.11.

const HL := 52.5
const HW := 34.0
const GHW := 3.66
const R := 0.11

func _init() -> void:
	var ok := true
	ok = _check_inside() and ok
	ok = _check_touchline() and ok
	ok = _check_goal_line_wide() and ok
	ok = _check_goal_mouth_not_out() and ok
	ok = _check_throw_spot() and ok
	ok = _check_corner_spot() and ok
	ok = _check_goal_kick_spot() and ok
	if ok:
		print("CHECK PASS: boundary_logic")
		quit(0)
	else:
		print("CHECK FAIL: boundary_logic")
		quit(1)

func _check_inside() -> bool:
	var e := BoundaryLogic.classify(Vector3(10, 0.11, 10), HL, HW, GHW, R)
	if e != BoundaryLogic.Exit.NONE:
		print("  FAIL inside: ", e); return false
	return true

func _check_touchline() -> bool:
	# x=34.5 > 34+0.11 → аут.
	var e := BoundaryLogic.classify(Vector3(34.5, 0.11, 10), HL, HW, GHW, R)
	if e != BoundaryLogic.Exit.TOUCHLINE:
		print("  FAIL touchline: ", e); return false
	return true

func _check_goal_line_wide() -> bool:
	# z=-53 < -(52.5+0.11), |x|=5 > goal_half_width → за лицевой мимо ворот.
	var e := BoundaryLogic.classify(Vector3(5, 0.11, -53.0), HL, HW, GHW, R)
	if e != BoundaryLogic.Exit.GOAL_LINE_NEG:
		print("  FAIL goal_line_neg: ", e); return false
	var e2 := BoundaryLogic.classify(Vector3(-5, 0.11, 53.0), HL, HW, GHW, R)
	if e2 != BoundaryLogic.Exit.GOAL_LINE_POS:
		print("  FAIL goal_line_pos: ", e2); return false
	return true

func _check_goal_mouth_not_out() -> bool:
	# z=-53, |x|=2 < goal_half_width (в створе) → это гол, НЕ аут-за-лицевой → NONE.
	var e := BoundaryLogic.classify(Vector3(2, 0.5, -53.0), HL, HW, GHW, R)
	if e != BoundaryLogic.Exit.NONE:
		print("  FAIL goal_mouth: ", e); return false
	return true

func _check_throw_spot() -> bool:
	# Проекция на ближайшую боковую (x=+34), z сохраняется, y=ball_radius.
	var s := BoundaryLogic.throw_in_spot(Vector3(34.5, 0.5, 12.0), HW, R)
	if not (is_equal_approx(s.x, 34.0) and is_equal_approx(s.z, 12.0) and is_equal_approx(s.y, R)):
		print("  FAIL throw_spot: ", s); return false
	return true

func _check_corner_spot() -> bool:
	# Выход за -Z, x>0 → угловой флаг (+HW-inset, -HL+inset).
	var s := BoundaryLogic.corner_spot(Vector3(5, 0.5, -53.0), HL, HW, BoundaryLogic.Exit.GOAL_LINE_NEG, 0.5, R)
	if not (is_equal_approx(s.x, 33.5) and is_equal_approx(s.z, -52.0) and is_equal_approx(s.y, R)):
		print("  FAIL corner_spot: ", s); return false
	return true

func _check_goal_kick_spot() -> bool:
	# Удар от ворот на -Z: центр линии вратарской (x=0, z=-HL+ga_depth).
	var s := BoundaryLogic.goal_kick_spot(BoundaryLogic.Exit.GOAL_LINE_NEG, HL, 5.5, R)
	if not (is_equal_approx(s.x, 0.0) and is_equal_approx(s.z, -47.0) and is_equal_approx(s.y, R)):
		print("  FAIL goal_kick_spot: ", s); return false
	return true

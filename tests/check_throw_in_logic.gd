extends SceneTree
## Headless-проверка чистых функций ThrowInLogic + правила 2 м (push_out_of_radius).

func _init() -> void:
	var ok := true
	ok = _check_aut_positive() and ok
	ok = _check_aut_negative() and ok
	ok = _check_base_heading() and ok
	ok = _check_placement() and ok
	ok = _check_encroach() and ok
	if ok:
		print("CHECK PASS: throw_in_logic")
		quit(0)
	else:
		print("CHECK FAIL: throw_in_logic")
		quit(1)

func _check_aut_positive() -> bool:
	# Мяч у правой боковой (x>0) → точка на линии x=+34, z сохраняется, y=радиус.
	var p := ThrowInLogic.aut_point(Vector3(30, 1.0, 10), 34.0, 0.11)
	if not (is_equal_approx(p.x, 34.0) and is_equal_approx(p.z, 10.0) and is_equal_approx(p.y, 0.11)):
		print("  FAIL aut_positive: ", p)
		return false
	return true

func _check_aut_negative() -> bool:
	var p := ThrowInLogic.aut_point(Vector3(-20, 1.0, -5), 34.0, 0.11)
	if not (is_equal_approx(p.x, -34.0) and is_equal_approx(p.z, -5.0)):
		print("  FAIL aut_negative: ", p)
		return false
	return true

func _check_base_heading() -> bool:
	# Правая линия (+34) → в поле это -X; левая (-34) → +X.
	var r := ThrowInLogic.base_heading(34.0)
	var l := ThrowInLogic.base_heading(-34.0)
	if not (r.is_equal_approx(Vector3(-1, 0, 0)) and l.is_equal_approx(Vector3(1, 0, 0))):
		print("  FAIL base_heading: r=", r, " l=", l)
		return false
	return true

func _check_placement() -> bool:
	# За линией снаружи поля: aut - в_поле*offset. y = body_y.
	var p := ThrowInLogic.thrower_placement(Vector3(34, 0.11, 10), Vector3(-1, 0, 0), 0.5, 0.5)
	if not (is_equal_approx(p.x, 34.5) and is_equal_approx(p.z, 10.0) and is_equal_approx(p.y, 0.5)):
		print("  FAIL placement: ", p)
		return false
	return true

func _check_encroach() -> bool:
	# Соперник в 0.5 м от точки вброса (<2) → вытолкнут ровно на 2 м вдоль (pos-spot); y сохраняется.
	var out := FreeKickLogic.push_out_of_radius(Vector3(34.5, 0.5, 10), Vector3(34, 0.11, 10), 2.0)
	if not (is_equal_approx(out.x, 36.0) and is_equal_approx(out.z, 10.0) and is_equal_approx(out.y, 0.5)):
		print("  FAIL encroach: ", out)
		return false
	return true

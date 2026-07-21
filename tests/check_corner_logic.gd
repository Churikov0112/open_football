extends SceneTree
## Headless-проверка чистых функций CornerLogic.

func _init() -> void:
	var ok := true
	ok = _check_side() and ok
	ok = _check_spot() and ok
	ok = _check_foot() and ok
	ok = _check_peak() and ok
	ok = _check_targets() and ok
	ok = _check_short() and ok
	ok = _check_short_start() and ok
	ok = _check_runup() and ok
	if ok:
		print("CHECK PASS: corner_logic")
		quit(0)
	else:
		print("CHECK FAIL: corner_logic")
		quit(1)

func _check_side() -> bool:
	if not (is_equal_approx(CornerLogic.side_for_player(20.0), 1.0)
			and is_equal_approx(CornerLogic.side_for_player(-5.0), -1.0)
			and is_equal_approx(CornerLogic.side_for_player(0.0), 1.0)):
		print("  FAIL side")
		return false
	return true

func _check_spot() -> bool:
	# Правый угол атакуемой линии Home (z=-52.5): x чуть меньше 34, z чуть больше -52.5 (в поле), y=BALL_RADIUS.
	var s := CornerLogic.corner_spot(1.0, 34.0, -52.5, 0.5, 0.11)
	if not (is_equal_approx(s.x, 33.5) and is_equal_approx(s.z, -52.0) and is_equal_approx(s.y, 0.11)):
		print("  FAIL spot: ", s)
		return false
	var l := CornerLogic.corner_spot(-1.0, 34.0, -52.5, 0.5, 0.11)
	if not (is_equal_approx(l.x, -33.5) and is_equal_approx(l.z, -52.0)):
		print("  FAIL spot left: ", l)
		return false
	return true

func _check_foot() -> bool:
	if CornerLogic.foot_for_side(1.0) != "penalty_l" or CornerLogic.foot_for_side(-1.0) != "penalty_r":
		print("  FAIL foot")
		return false
	return true

func _check_peak() -> bool:
	var head := CornerLogic.peak_for_stick_y(1.0, 4.0, 7.0, 12.0)
	var mid := CornerLogic.peak_for_stick_y(0.0, 4.0, 7.0, 12.0)
	var sv := CornerLogic.peak_for_stick_y(-1.0, 4.0, 7.0, 12.0)
	if not (is_equal_approx(head, 4.0) and is_equal_approx(mid, 7.0) and is_equal_approx(sv, 12.0)):
		print("  FAIL peak endpoints: ", head, " ", mid, " ", sv)
		return false
	# Монотонность: чем ниже стик, тем выше дуга.
	if not (head < mid and mid < sv):
		print("  FAIL peak monotonic")
		return false
	return true

func _check_targets() -> bool:
	var t := CornerLogic.box_target_positions(-52.5, 1.0, 6.0, 11.0, 0.5)
	if t.size() != 2:
		print("  FAIL targets size")
		return false
	# Обе цели в поле от линии (z = -52.5 + 1*11 = -41.5), по разные стороны от центра.
	var a: Vector3 = t[0]
	var b: Vector3 = t[1]
	if not (is_equal_approx(a.z, -41.5) and is_equal_approx(b.z, -41.5) and a.x < 0.0 and b.x > 0.0):
		print("  FAIL targets pos: ", a, " ", b)
		return false
	return true

func _check_short() -> bool:
	# Короткая опция: вглубь поля от угла (z сдвинут на into*dist), x ближе к центру.
	var spot := CornerLogic.corner_spot(1.0, 34.0, -52.5, 0.5, 0.11)
	var p := CornerLogic.short_option_pos(spot, 1.0, 1.0, 7.0, 0.5)
	if not (p.z > spot.z and absf(p.x) < absf(spot.x) and is_equal_approx(p.y, 0.5)):
		print("  FAIL short: ", p)
		return false
	return true

func _check_short_start() -> bool:
	# Правый угол (side=1) атакуемой линии Home (z=-52.5): старт в штрафной, на стороне угла (x>0),
	# в поле от линии (z > goal_line_z).
	var p := CornerLogic.short_mate_start_pos(1.0, -52.5, 1.0, 3.0, 6.0, 0.5)
	if not (is_equal_approx(p.x, 3.0) and is_equal_approx(p.z, -46.5) and is_equal_approx(p.y, 0.5)):
		print("  FAIL short_start: ", p)
		return false
	var l := CornerLogic.short_mate_start_pos(-1.0, -52.5, 1.0, 3.0, 6.0, 0.5)
	if l.x >= 0.0:
		print("  FAIL short_start left side: ", l)
		return false
	return true

func _check_runup() -> bool:
	# Правый угол Home (side=1, into=1): x=33.5, z=-52.0. Боковая линия x=34, линия ворот z=-52.5.
	var spot := CornerLogic.corner_spot(1.0, 34.0, -52.5, 0.5, 0.11)
	var runup := 2.8
	var dr := CornerLogic.runup_dir(1.0, 1.0, "penalty_r", 30.0)
	var dl := CornerLogic.runup_dir(1.0, 1.0, "penalty_l", 30.0)
	# Обе горизонтальные и единичные.
	if not (is_equal_approx(dr.y, 0.0) and is_equal_approx(dl.y, 0.0)
			and is_equal_approx(dr.length(), 1.0) and is_equal_approx(dl.length(), 1.0)):
		print("  FAIL runup unit/horizontal: ", dr, " ", dl)
		return false
	# Правая нога: старт (spot - dir*runup) ЗА боковой линией (x>34) и ПЕРЕД линией ворот (z>-52.5).
	var sr := spot - dr * runup
	if not (sr.x > 34.0 and sr.z > -52.5):
		print("  FAIL runup R region (ожидалось x>34, z>-52.5): ", sr)
		return false
	# Левая нога: старт ЗА линией ворот (z<-52.5).
	var sl := spot - dl * runup
	if sl.z >= -52.5:
		print("  FAIL runup L region (ожидалось z<-52.5): ", sl)
		return false
	# Ноги заходят с явно разных сторон.
	if dr.angle_to(dl) < deg_to_rad(30.0):
		print("  FAIL runup feet too similar: angle=", rad_to_deg(dr.angle_to(dl)))
		return false
	return true

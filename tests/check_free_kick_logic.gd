extends SceneTree
## Headless-проверка чистых функций FreeKickLogic.

func _init() -> void:
	var ok := true
	ok = _check_base_heading() and ok
	ok = _check_rotate_clamp() and ok
	ok = _check_launch_monotonic() and ok
	ok = _check_scatter_bounded() and ok
	ok = _check_curl_sign_and_clamp() and ok
	ok = _check_near_far() and ok
	ok = _check_wall_count() and ok
	ok = _check_wall_line_and_bodies() and ok
	ok = _check_wall_jump() and ok
	ok = _check_keeper_pos() and ok
	if ok:
		print("CHECK PASS: free_kick_logic")
		quit(0)
	else:
		print("CHECK FAIL: free_kick_logic")
		quit(1)

func _check_base_heading() -> bool:
	var h := FreeKickLogic.base_heading(Vector3(10, 0.11, -20.0), Vector3(0, 0, -52.5))
	# Должно смотреть к воротам: z-компонента отрицательна, длина ~1.
	if h.z >= 0.0 or not is_equal_approx(h.length(), 1.0):
		print("  FAIL base_heading: ", h)
		return false
	return true

func _check_rotate_clamp() -> bool:
	var base := Vector3(0, 0, -1)
	var cur := base
	# Гоним стик вправо долго — угол не должен превысить arc.
	for i in range(500):
		cur = FreeKickLogic.rotate_heading(cur, base, 1.0, 1.6, 0.05, 1.221)
	var ang := absf(base.signed_angle_to(cur, Vector3.UP))
	if ang > 1.221 + 0.001:
		print("  FAIL rotate_clamp: ang=", ang)
		return false
	return true

func _check_launch_monotonic() -> bool:
	var lo := FreeKickLogic.launch_velocity(Vector3(0, 0, -1), 0.0, 16.0, 34.0, 4.0, 22.0)
	var hi := FreeKickLogic.launch_velocity(Vector3(0, 0, -1), 1.0, 16.0, 34.0, 4.0, 22.0)
	# Скорость растёт с зарядом; высота вылета (vy) растёт с зарядом.
	if not (hi.length() > lo.length() and hi.y > lo.y and lo.y >= 0.0):
		print("  FAIL launch_monotonic: lo=", lo, " hi=", hi)
		return false
	return true

func _check_scatter_bounded() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var base := Vector3(0, 0, -1) * 20.0
	for i in range(500):
		var v := FreeKickLogic.apply_scatter(base, 6.0, rng)
		# Отклонение направления не больше ~sqrt(2)*6° ≈ 8.5°.
		if rad_to_deg(base.angle_to(v)) > 10.0:
			print("  FAIL scatter_bounded at i=", i, " ang=", rad_to_deg(base.angle_to(v)))
			return false
	# Нулевой разброс не меняет вектор.
	var same := FreeKickLogic.apply_scatter(base, 0.0, rng)
	if not same.is_equal_approx(base):
		print("  FAIL scatter zero: ", same)
		return false
	return true

func _check_curl_sign_and_clamp() -> bool:
	var pos := FreeKickLogic.curl_from_stick(2.0, 6.0, 9.0)   # 12 → кламп 9
	var neg := FreeKickLogic.curl_from_stick(-2.0, 6.0, 9.0)  # -12 → -9
	if not (is_equal_approx(pos.z, 9.0) and is_equal_approx(neg.z, -9.0) and is_equal_approx(pos.x, 0.0) and is_equal_approx(pos.y, 0.0)):
		print("  FAIL curl: ", pos, " ", neg)
		return false
	# Малый ввод — линейно.
	var small := FreeKickLogic.curl_from_stick(0.5, 6.0, 9.0)  # 3.0
	if not is_equal_approx(small.z, 3.0):
		print("  FAIL curl small: ", small)
		return false
	return true

func _check_near_far() -> bool:
	# Мяч правее центра (x>0): ближняя штанга — правая (+x).
	var nf := FreeKickLogic.near_far_posts(Vector3(15, 0.11, -20.0), 0.0, 3.66, -52.5)
	var near: Vector3 = nf[0]
	var far: Vector3 = nf[1]
	if not (near.x > 0.0 and far.x < 0.0):
		print("  FAIL near_far right: ", nf)
		return false
	# Мяч левее (x<0): ближняя — левая.
	var nf2 := FreeKickLogic.near_far_posts(Vector3(-15, 0.11, -20.0), 0.0, 3.66, -52.5)
	if nf2[0].x >= 0.0:
		print("  FAIL near_far left: ", nf2)
		return false
	return true

func _check_wall_count() -> bool:
	var far := FreeKickLogic.wall_count(45.0, 40.0, 25.0, 2, 5)   # >far → 0
	var near := FreeKickLogic.wall_count(20.0, 40.0, 25.0, 2, 5)  # <near → max
	var mid := FreeKickLogic.wall_count(32.5, 40.0, 25.0, 2, 5)   # середина → между
	if not (far == 0 and near == 5 and mid >= 2 and mid <= 5):
		print("  FAIL wall_count: far=", far, " near=", near, " mid=", mid)
		return false
	return true

func _check_wall_line_and_bodies() -> bool:
	# Дальний штрафной: стенка в 9.15 м от мяча на линии мяч→ближняя штанга.
	var from := Vector3(10, 0.11, -20.0)
	var near := Vector3(3.66, 0.0, -52.5)
	var wl := FreeKickLogic.wall_line(from, near, -52.5, 9.15, 0.5)
	if wl["on_line"]:
		print("  FAIL wall_line far should not be on_line")
		return false
	var center: Vector3 = wl["center"]
	if absf(Vector2(center.x - from.x, center.z - from.z).length() - 9.15) > 0.01:
		print("  FAIL wall_line dist: ", center)
		return false
	var bodies := FreeKickLogic.wall_body_positions(center, wl["right"], 4, 0.62)
	if bodies.size() != 4:
		print("  FAIL wall bodies count: ", bodies.size())
		return false
	# Интервал между соседями = spacing.
	var d: float = (bodies[1] - bodies[0]).length()
	if absf(d - 0.62) > 0.001:
		print("  FAIL wall spacing: ", d)
		return false
	# Близкий штрафной (< 9.15 до ворот) → на линию ворот.
	var wl2 := FreeKickLogic.wall_line(Vector3(0, 0.11, -47.0), Vector3(3.66, 0, -52.5), -52.5, 9.15, 0.5)
	if not wl2["on_line"] or not is_equal_approx(wl2["center"].z, -52.5):
		print("  FAIL wall_line near-goal: ", wl2)
		return false
	return true

func _check_wall_jump() -> bool:
	var ball_pos := Vector3(10, 0.11, -20.0)
	var wall_center := Vector3(6.0, 0.5, -25.0)
	# Высокий мяч (перелетает стоящих, но в досягаемости прыжка) → прыгать.
	var high_vel := (wall_center + Vector3(0, 2.6, 0) - ball_pos).normalized() * 22.0
	var jump := FreeKickLogic.wall_should_jump(ball_pos, high_vel, wall_center, 2.2, 2.9, 9.8)
	# Низкий настильный мяч → не прыгать.
	var low_vel := (wall_center + Vector3(0, 0.3, 0) - ball_pos).normalized() * 22.0
	var no_jump := FreeKickLogic.wall_should_jump(ball_pos, low_vel, wall_center, 2.2, 2.9, 9.8)
	if no_jump:
		print("  FAIL wall_jump: низкий мяч не должен вызывать прыжок")
		return false
	# Мяч, улетающий от стенки (назад) → не прыгать.
	var away := FreeKickLogic.wall_should_jump(ball_pos, Vector3(0, 5, 20), wall_center, 2.2, 2.9, 9.8)
	if away:
		print("  FAIL wall_jump: мяч от стенки")
		return false
	return true

func _check_keeper_pos() -> bool:
	var from := Vector3(15, 0.11, -20.0)
	var nf := FreeKickLogic.near_far_posts(from, 0.0, 3.66, -52.5)
	var kp := FreeKickLogic.keeper_position(from, nf[0], nf[1], 3.66, 1.5, -52.5, 0.5)
	# Вратарь между штанг (|x| <= half_width), в поле от линии (z > goal_line_z), на земле.
	if absf(kp.x) > 3.66 + 0.001 or kp.z <= -52.5 or not is_equal_approx(kp.y, 0.5):
		print("  FAIL keeper_pos: ", kp)
		return false
	return true

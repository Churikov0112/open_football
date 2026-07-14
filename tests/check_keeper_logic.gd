extends SceneTree

func _initialize() -> void:
	var ok := true

	# line_position: X следует за мячом (в пределах створа), Z сходит с линии под близкий мяч.
	# Ворота Away на +52.5; в поле = -Z. Мяч на линии (dz=0) → макс. выход off=max_off_line.
	var lp := KeeperLogic.line_position(Vector3(1.0, 0, 40.0), 52.5, 3.66, 0.08, 2.5)
	if not is_equal_approx(lp.x, 1.0):
		print("CHECK FAIL: line_position x → ", lp.x); ok = false
	# dz = |40-52.5| = 12.5 → off = clamp(2.5 - 0.08*12.5, 0, 2.5) = 1.5 → z = 52.5 - 1.5 = 51.0
	if not is_equal_approx(lp.z, 51.0):
		print("CHECK FAIL: line_position z narrow → ", lp.z); ok = false
	# X клампится к полуширине створа.
	var lp2 := KeeperLogic.line_position(Vector3(10.0, 0, 52.5), 52.5, 3.66, 0.08, 2.5)
	if not is_equal_approx(lp2.x, 3.66):
		print("CHECK FAIL: line_position x clamp → ", lp2.x); ok = false

	# shot_intercept: проекция на плоскость z=goal_line_z.
	# Мяч в (0,0.5,40), скорость (2,1,25) → t=(52.5-40)/25=0.5 → point=(1, 1.0, 52.5)
	var si := KeeperLogic.shot_intercept(Vector3(0, 0.5, 40.0), Vector3(2, 1, 25), 52.5)
	if not si.is_equal_approx(Vector3(1.0, 1.0, 52.5)):
		print("CHECK FAIL: shot_intercept → ", si); ok = false
	# Мяч летит ОТ линии (vz<0) → нет пересечения впереди → возвращает позицию мяча.
	var si2 := KeeperLogic.shot_intercept(Vector3(0, 0.5, 40.0), Vector3(0, 0, -10), 52.5)
	if not si2.is_equal_approx(Vector3(0, 0.5, 40.0)):
		print("CHECK FAIL: shot_intercept away → ", si2); ok = false

	# is_on_target: в створе / мимо по ширине и высоте.
	if not KeeperLogic.is_on_target(Vector3(2.0, 1.5, 52.5), 3.66, 2.44):
		print("CHECK FAIL: on_target inside"); ok = false
	if KeeperLogic.is_on_target(Vector3(5.0, 1.5, 52.5), 3.66, 2.44):
		print("CHECK FAIL: on_target wide"); ok = false
	if KeeperLogic.is_on_target(Vector3(0.0, 3.0, 52.5), 3.66, 2.44):
		print("CHECK FAIL: on_target over bar"); ok = false

	# save_decision: 6 зон + NONE. Вратарь на (0,0,52).
	# близко+низко → CATCH
	var d1 := KeeperLogic.save_decision(Vector3(0.5, 0.5, 52.5), Vector3(0, 0, 52), 1.4, 3.66, 1.3)
	if d1.action != KeeperLogic.SaveAction.CATCH:
		print("CHECK FAIL: decision CATCH → ", d1.action); ok = false
	# близко+высоко → CATCH_TOP
	var d2 := KeeperLogic.save_decision(Vector3(0.5, 2.0, 52.5), Vector3(0, 0, 52), 1.4, 3.66, 1.3)
	if d2.action != KeeperLogic.SaveAction.CATCH_TOP:
		print("CHECK FAIL: decision CATCH_TOP → ", d2.action); ok = false
	# нижний угол влево (dx<0) → DIVE_LOW_L
	var d3 := KeeperLogic.save_decision(Vector3(-3.0, 0.5, 52.5), Vector3(0, 0, 52), 1.4, 3.66, 1.3)
	if d3.action != KeeperLogic.SaveAction.DIVE_LOW_L:
		print("CHECK FAIL: decision DIVE_LOW_L → ", d3.action); ok = false
	# верхний угол вправо (dx>0) → DIVE_HIGH_R
	var d4 := KeeperLogic.save_decision(Vector3(3.0, 2.0, 52.5), Vector3(0, 0, 52), 1.4, 3.66, 1.3)
	if d4.action != KeeperLogic.SaveAction.DIVE_HIGH_R:
		print("CHECK FAIL: decision DIVE_HIGH_R → ", d4.action); ok = false
	# за пределами прыжка → NONE
	var d5 := KeeperLogic.save_decision(Vector3(6.0, 0.5, 52.5), Vector3(0, 0, 52), 1.4, 3.66, 1.3)
	if d5.action != KeeperLogic.SaveAction.NONE:
		print("CHECK FAIL: decision NONE → ", d5.action); ok = false

	# time_to_intercept: расстояние/скорость.
	# мяч (0,0,40)→(0,0,52.5) при скорости 25 м/с → t=12.5/25=0.5
	var tti := KeeperLogic.time_to_intercept(Vector3(0, 0, 40), Vector3(0, 0, 25), Vector3(0, 0, 52.5))
	if not is_equal_approx(tti, 0.5):
		print("CHECK FAIL: time_to_intercept → ", tti); ok = false
	if KeeperLogic.time_to_intercept(Vector3(0,0,40), Vector3.ZERO, Vector3(0,0,52.5)) != INF:
		print("CHECK FAIL: time_to_intercept still"); ok = false

	# should_commit_dive: рано (мяч далеко по времени) — не прыгаем; в окне — прыгаем.
	# нырок к цели на 3 м при dive_speed=14 → dive_time≈0.214; lead=0.08 → окно≈0.294
	var far := KeeperLogic.should_commit_dive(0.6, Vector3(0,0,52), Vector3(3,0.5,52.5), 14.0, 0.08)
	if far:
		print("CHECK FAIL: commit too early"); ok = false
	var now := KeeperLogic.should_commit_dive(0.25, Vector3(0,0,52), Vector3(3,0.5,52.5), 14.0, 0.08)
	if not now:
		print("CHECK FAIL: commit in window"); ok = false

	# resolve_save: центр всегда ловля, верх-угол всегда отбой, низ-угол по скорости.
	if not KeeperLogic.resolve_save(KeeperLogic.SaveAction.CATCH, 40.0, 18.0):
		print("CHECK FAIL: resolve CATCH always"); ok = false
	if not KeeperLogic.resolve_save(KeeperLogic.SaveAction.CATCH_TOP, 40.0, 18.0):
		print("CHECK FAIL: resolve CATCH_TOP always"); ok = false
	if KeeperLogic.resolve_save(KeeperLogic.SaveAction.DIVE_HIGH_L, 5.0, 18.0):
		print("CHECK FAIL: resolve HIGH always parry"); ok = false
	if not KeeperLogic.resolve_save(KeeperLogic.SaveAction.DIVE_LOW_R, 10.0, 18.0):
		print("CHECK FAIL: resolve LOW slow catch"); ok = false
	if KeeperLogic.resolve_save(KeeperLogic.SaveAction.DIVE_LOW_R, 25.0, 18.0):
		print("CHECK FAIL: resolve LOW fast parry"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

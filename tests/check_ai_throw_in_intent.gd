extends SceneTree
## Headless-проверка AIThrowInIntent через фейковый сабкласс с переопределённым _now_msec().
## Доворот прогоняется через ТУ ЖЕ FreeKickLogic.rotate_heading (THROW_AIM_SPEED/THROW_AIM_ARC), что
## использует контроллер, — проверяем реальную сходимость heading.

class _FakeATI extends AIThrowInIntent:
	var t := 0
	func _now_msec() -> int: return t

func _init() -> void:
	var ok := true
	var into := Vector3(1, 0, 0)
	var aim_dir := Vector3(0.7, 0.0, 0.7).normalized()   # цель под 45° в поле (внутри ±90°)
	var a := _FakeATI.new(into, aim_dir, 0.5)

	var think_ms := int(FootballConstants.AI_THROWIN_THINK_TIME * 1000.0)
	a.t = think_ms - 50
	ok = _expect(a.aim_axis() == Vector2.ZERO, "до THINK: стик молчит") and ok
	ok = _expect(a.charge_start_variant() == -1, "до THINK: заряд не стартует") and ok

	var heading := into
	var dt := 1.0 / 60.0
	a.t = think_ms
	var frames := 0
	while frames < 600:
		var stick := a.aim_axis().x
		heading = FreeKickLogic.rotate_heading(heading, into, stick,
			FootballConstants.THROW_AIM_SPEED, dt, FootballConstants.THROW_AIM_ARC)
		a.t += int(dt * 1000.0)
		frames += 1
	ok = _expect(heading.dot(aim_dir) > 0.99, "heading сошёлся к aim_dir (dot=" + str(heading.dot(aim_dir)) + ")") and ok

	ok = _expect(a.charge_start_variant() == 0, "charge_start = 0 после доворота") and ok
	ok = _expect(a.charge_start_variant() == -1, "charge_start только раз") and ok
	ok = _expect(a.charge_committed() == false, "сразу после старта — не коммит") and ok
	a.t += int(0.5 * FootballConstants.THROW_CHARGE_MAX_TIME * 1000.0) + 10
	ok = _expect(a.charge_committed() == true, "коммит после power_ratio*THROW_CHARGE_MAX_TIME") and ok

	ok = _expect(a.foot_switch() == 0 and a.modifier_held() == false and a.has_fixed_aim() == false, "дефолты no-op") and ok

	if ok:
		print("CHECK PASS: ai_throw_in_intent")
		quit(0)
	else:
		print("CHECK FAIL: ai_throw_in_intent")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

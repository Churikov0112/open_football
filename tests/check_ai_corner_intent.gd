extends SceneTree
## Headless-проверка AICornerIntent через фейковый сабкласс с переопределённым _now_msec().
## Доворот прогоняется через ТУ ЖЕ FreeKickLogic.rotate_heading (с CORNER_AIM_SPEED/CORNER_AIM_ARC),
## что использует контроллер, — проверяем реальную сходимость heading к aim_dir.

class _FakeAC extends AICornerIntent:
	var t := 0
	func _now_msec() -> int: return t

func _init() -> void:
	var ok := true
	var base := Vector3(0.0, 0.0, 1.0)                 # базовый heading (в створ)
	var aim := Vector3(0.5, 0.0, 0.87).normalized()    # цель правее (~30°, внутри CORNER_AIM_ARC)
	var a := _FakeAC.new(base, aim, 1, 0.5)            # variant=lob, power_ratio=0.5

	var think_ms := int(FootballConstants.AI_CORNER_THINK_TIME * 1000.0)
	a.t = think_ms - 50
	ok = _expect(a.aim_axis() == Vector2.ZERO, "до THINK: стик молчит") and ok
	ok = _expect(a.charge_start_variant() == -1, "до THINK: заряд не стартует") and ok

	# Доворот через ту же математику, что у контроллера.
	var heading := base
	var dt := 1.0 / 60.0
	a.t = think_ms
	var frames := 0
	while frames < 600:
		var stick := a.aim_axis().x
		heading = FreeKickLogic.rotate_heading(heading, base, stick,
			FootballConstants.CORNER_AIM_SPEED, dt, FootballConstants.CORNER_AIM_ARC)
		a.t += int(dt * 1000.0)
		frames += 1
	ok = _expect(heading.dot(aim) > 0.99, "heading сошёлся к aim_dir (dot=" + str(heading.dot(aim)) + ")") and ok

	# Заряд стартует после доворота, отдаёт variant один раз.
	ok = _expect(a.charge_start_variant() == 1, "charge_start отдаёт variant (lob=1) после доворота") and ok
	ok = _expect(a.charge_start_variant() == -1, "charge_start только раз") and ok
	ok = _expect(a.charge_committed() == false, "сразу после старта — не коммит") and ok
	var charge_ms := int(0.5 * FootballConstants.CORNER_CHARGE_MAX_TIME * 1000.0)
	a.t += charge_ms + 10
	ok = _expect(a.charge_committed() == true, "коммит после power_ratio*CORNER_CHARGE_MAX_TIME") and ok

	# Короткую опцию ИИ v1 не зовёт.
	ok = _expect(a.secondary() == false, "secondary (короткая опция) — no-op у ИИ v1") and ok
	ok = _expect(a.foot_switch() == 0 and a.modifier_held() == false, "прочие дефолты no-op") and ok

	if ok:
		print("CHECK PASS: ai_corner_intent")
		quit(0)
	else:
		print("CHECK FAIL: ai_corner_intent")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

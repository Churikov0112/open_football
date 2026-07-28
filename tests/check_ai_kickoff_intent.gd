extends SceneTree
## Headless-проверка AIKickoffIntent через фейковый сабкласс с переопределённым _now_msec()
## (скриптуем время без sleep, как AIKickerIntent). Ключевая проверка — не знак стика "на бумаге",
## а РЕАЛЬНАЯ сходимость: прогоняем aim_axis() через ТУ ЖЕ FreeKickLogic.rotate_heading, что
## использует контроллер, и проверяем, что heading действительно приходит к направлению на партнёра.

class _FakeAKO extends AIKickoffIntent:
	var t := 0
	func _now_msec() -> int: return t

func _init() -> void:
	var ok := true
	var kicker_pos := Vector3(0.0, 0.5, -0.5)
	var base_heading := Vector3(0.0, 0.0, 1.0)      # team_1: лицом на свою половину (+Z)
	var partner_pos := Vector3(8.0, 0.5, 6.0)        # партнёр правее и на своей половине
	var a := _FakeAKO.new(kicker_pos, base_heading, partner_pos)

	var think_ms := int(FootballConstants.AI_KICKOFF_THINK_TIME * 1000.0)
	a.t = think_ms - 50
	ok = _expect(a.aim_axis() == Vector2.ZERO, "до THINK: стик молчит") and ok
	ok = _expect(a.charge_start_variant() == -1, "до THINK: заряд не стартует") and ok

	# Прогоняем доворот через ТУ ЖЕ математику, что использует контроллер.
	var heading := base_heading
	var dt := 1.0 / 60.0
	a.t = think_ms
	var frames := 0
	while frames < 600:   # запас (10с симулированного времени) — реальная длительность динамическая
		var stick := a.aim_axis().x
		heading = FreeKickLogic.rotate_heading(heading, base_heading, stick,
			FootballConstants.KICKOFF_AIM_SPEED, dt, FootballConstants.KICKOFF_AIM_ARC)
		a.t += int(dt * 1000.0)
		frames += 1
	var target_dir := Vector3(partner_pos.x - kicker_pos.x, 0.0, partner_pos.z - kicker_pos.z).normalized()
	var dot := heading.dot(target_dir)
	ok = _expect(dot > 0.99, "heading сошёлся к направлению на партнёра (dot=" + str(dot) + ")") and ok

	# Заряд стартует только ПОСЛЕ доворота (a.t уже далеко за think+turn к этому моменту).
	ok = _expect(a.charge_start_variant() == 0, "заряд стартует после доворота") and ok
	ok = _expect(a.charge_start_variant() == -1, "charge_start только раз") and ok
	ok = _expect(a.charge_committed() == false, "сразу после старта — не коммит") and ok
	var charge_ms := int(FootballConstants.AI_KICKOFF_CHARGE_RATIO * FootballConstants.KICKOFF_CHARGE_MAX_TIME * 1000.0)
	a.t += charge_ms + 10
	ok = _expect(a.charge_committed() == true, "коммит после расчётного заряда") and ok

	# Дефолты: без ноги/модификатора/вторички/фикс-прицела.
	ok = _expect(a.foot_switch() == 0 and a.modifier_held() == false and a.secondary() == false, "дефолты no-op") and ok
	ok = _expect(a.has_fixed_aim() == false, "кикофф — направленческий, не fixed-aim") and ok

	if ok:
		print("CHECK PASS: ai_kickoff_intent")
		quit(0)
	else:
		print("CHECK FAIL: ai_kickoff_intent")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

extends SceneTree
## Headless-проверка AIGoalKickIntent через фейковый сабкласс с переопределённым _now_msec().
## Как check_ai_kickoff_intent: доворот прогоняется через ТУ ЖЕ FreeKickLogic.rotate_heading
## (с GK_AIM_SPEED/GK_AIM_ARC), что использует контроллер, — проверяем реальную сходимость heading.

class _FakeAGK extends AIGoalKickIntent:
	var t := 0
	func _now_msec() -> int: return t

func _init() -> void:
	var ok := true
	var attack_dir := Vector3(0.0, 0.0, 1.0)          # вверх поля
	var aim_dir := Vector3(0.6, 0.0, 0.8).normalized() # цель правее (~37°, внутри GK_AIM_ARC)
	var a := _FakeAGK.new(attack_dir, aim_dir, 1, 0.5)  # variant=lob, power_ratio=0.5

	var think_ms := int(FootballConstants.AI_GOALKICK_THINK_TIME * 1000.0)
	a.t = think_ms - 50
	ok = _expect(a.aim_axis() == Vector2.ZERO, "до THINK: стик молчит") and ok
	ok = _expect(a.charge_start_variant() == -1, "до THINK: заряд не стартует") and ok

	# Доворот через ту же математику, что у контроллера.
	var heading := attack_dir
	var dt := 1.0 / 60.0
	a.t = think_ms
	var frames := 0
	while frames < 600:
		var stick := a.aim_axis().x
		heading = FreeKickLogic.rotate_heading(heading, attack_dir, stick,
			FootballConstants.GK_AIM_SPEED, dt, FootballConstants.GK_AIM_ARC)
		a.t += int(dt * 1000.0)
		frames += 1
	ok = _expect(heading.dot(aim_dir) > 0.99, "heading сошёлся к aim_dir (dot=" + str(heading.dot(aim_dir)) + ")") and ok

	# Заряд стартует после доворота, отдаёт variant один раз.
	ok = _expect(a.charge_start_variant() == 1, "charge_start отдаёт variant (lob=1) после доворота") and ok
	ok = _expect(a.charge_start_variant() == -1, "charge_start только раз") and ok
	ok = _expect(a.charge_committed() == false, "сразу после старта — не коммит") and ok
	var charge_ms := int(0.5 * FootballConstants.GK_CHARGE_MAX_TIME * 1000.0)
	a.t += charge_ms + 10
	ok = _expect(a.charge_committed() == true, "коммит после power_ratio*GK_CHARGE_MAX_TIME") and ok

	# Дефолты.
	ok = _expect(a.foot_switch() == 0 and a.modifier_held() == false and a.secondary() == false, "дефолты no-op") and ok
	ok = _expect(a.has_fixed_aim() == false, "удар от ворот — направленческий, не fixed-aim") and ok

	if ok:
		print("CHECK PASS: ai_goal_kick_intent")
		quit(0)
	else:
		print("CHECK FAIL: ai_goal_kick_intent")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

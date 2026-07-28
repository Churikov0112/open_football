extends SceneTree
## Headless-проверка AIKickerIntent через фейковый сабкласс с переопределённым _now_msec()
## (скриптуем время без sleep). Опирается на автолоад FootballConstants (доступен в -s).

class _FakeAKI extends AIKickerIntent:
	var t := 0
	func _now_msec() -> int: return t

func _init() -> void:
	var ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var a := _FakeAKI.new(rng)   # _init читает _now_msec()=t=0 → _start_msec=0

	var think_ms := int(FootballConstants.AI_PENALTY_THINK_TIME * 1000.0)
	var charge_ms := int(FootballConstants.AI_PENALTY_CHARGE_RATIO * FootballConstants.PEN_CHARGE_MAX_TIME * 1000.0)

	# До окончания обдумывания заряд не стартует.
	a.t = think_ms - 100
	ok = _expect(a.charge_start_variant() == -1, "до THINK: charge_start = -1") and ok
	# После — стартует один раз (вариант 0), латчит.
	a.t = think_ms + 50
	ok = _expect(a.charge_start_variant() == 0, "после THINK: charge_start = 0") and ok
	ok = _expect(a.charge_start_variant() == -1, "charge_start только раз") and ok
	# Коммит — после CHARGE_RATIO*MAX от старта заряда (старт был на think_ms+50).
	ok = _expect(a.charge_committed() == false, "до заряда: не коммит") and ok
	a.t = think_ms + 50 + charge_ms + 10
	ok = _expect(a.charge_committed() == true, "после заряда: коммит") and ok

	# Фикс-прицел: стабилен и внутри створа.
	ok = _expect(a.has_fixed_aim() == true, "has_fixed_aim true") and ok
	var t1 := a.aim_target()
	var t2 := a.aim_target()
	ok = _expect(t1 == t2, "aim_target стабилен") and ok
	var hw := FootballConstants.GOAL_WIDTH * 0.5 * FootballConstants.AI_PENALTY_AIM_SPREAD
	ok = _expect(absf(t1.x) <= hw + 0.001 and t1.y >= 0.3 - 0.001 and t1.y <= FootballConstants.GOAL_HEIGHT * 0.7 + 0.001, "aim_target в створе") and ok

	# foot/modifier — no-op.
	ok = _expect(a.foot_switch() == 0 and a.modifier_held() == false, "foot/modifier no-op") and ok

	if ok:
		print("CHECK PASS: ai_kicker_intent")
		quit(0)
	else:
		print("CHECK FAIL: ai_kicker_intent")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

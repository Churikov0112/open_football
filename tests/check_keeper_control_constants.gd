extends SceneTree
## Новые KEEPER-константы существуют и в разумных диапазонах.
## Прямой доступ к константам (FootballConstants.X резолвится статически), не через `in`/.get()
## на инстансе автозагрузки — тот при запуске через -s на этапе компиляции не резолвится.

func _in_range(nm: String, v: float, lo: float, hi: float) -> bool:
	if v < lo or v > hi:
		print("CHECK FAIL: ", nm, "=", v, " вне [", lo, ",", hi, "]")
		return false
	return true

func _initialize() -> void:
	var ok := true
	ok = _in_range("KEEPER_DIST_CHARGE_MAX", FootballConstants.KEEPER_DIST_CHARGE_MAX, 0.2, 3.0) and ok
	ok = _in_range("KEEPER_HAND_THROW_CHARGE", FootballConstants.KEEPER_HAND_THROW_CHARGE, 0.05, 1.0) and ok
	ok = _in_range("KEEPER_HAND_ROLL_DIST", FootballConstants.KEEPER_HAND_ROLL_DIST, 3.0, 25.0) and ok
	ok = _in_range("KEEPER_HAND_THROW_DIST", FootballConstants.KEEPER_HAND_THROW_DIST, 10.0, 60.0) and ok
	ok = _in_range("KEEPER_HANDS_MOVE_SPEED", FootballConstants.KEEPER_HANDS_MOVE_SPEED, 0.3, 1.0) and ok
	ok = _in_range("KEEPER_SIX_SECOND_TIME", FootballConstants.KEEPER_SIX_SECOND_TIME, 5.0, 8.0) and ok
	ok = _in_range("AI_KEEPER_THINK_TIME", FootballConstants.AI_KEEPER_THINK_TIME, 0.0, 3.0) and ok
	# Порог тап↔удержание < максимума заряда (иначе бросок недостижим).
	if FootballConstants.KEEPER_HAND_THROW_CHARGE >= FootballConstants.KEEPER_DIST_CHARGE_MAX:
		print("CHECK FAIL: THROW_CHARGE >= DIST_CHARGE_MAX"); ok = false
	# Банд броска дальше банда раската.
	if FootballConstants.KEEPER_HAND_THROW_DIST <= FootballConstants.KEEPER_HAND_ROLL_DIST:
		print("CHECK FAIL: THROW_DIST <= ROLL_DIST"); ok = false
	if ok:
		print("CHECK PASS: keeper control constants")
		quit(0)
	else:
		quit(1)

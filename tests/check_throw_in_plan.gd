extends SceneTree
## Headless-проверка чистого скорера ThrowInPlan.choose. Тюнинг — литералами (класс не читает
## FootballConstants). into = +X (перпендикуляр в поле), attack_dir = +Z (вверх поля), spot в нуле.

const MIN := 6.0
const MAX := 22.0
const ARC := PI / 2.0
const BSP := 12.0
const OPP := 8.0
const CHW := 1.2
const CSP := 0.06
const UPW := 1.0

func _init() -> void:
	var ok := true
	var spot := Vector3.ZERO
	var into := Vector3(1, 0, 0)
	var up := Vector3(0, 0, 1)

	# (а) Открытый кандидат в секторе и дальности → выбран, power_ratio = инверсия lerp.
	var a := ThrowInPlan.choose(spot, into, up, ARC, [Vector3(10, 0, 3)], [],
		MIN, MAX, BSP, OPP, CHW, CSP, UPW)
	var dist_a := Vector3(10, 0, 3).length()
	ok = _expect(a["index"] == 0, "а: выбран кандидат") and ok
	ok = _expect(absf(a["power_ratio"] - clampf(inverse_lerp(MIN, MAX, dist_a), 0.0, 1.0)) < 0.001, "а: power_ratio = инверсия lerp") and ok
	ok = _expect(a["aim_dir"].dot(Vector3(10, 0, 3).normalized()) > 0.99, "а: aim_dir на кандидата") and ok

	# power_ratio монотонен по дистанции (дальше = больше).
	var a_far := ThrowInPlan.choose(spot, into, up, ARC, [Vector3(20, 0, 0)], [],
		MIN, MAX, BSP, OPP, CHW, CSP, UPW)
	ok = _expect(a_far["power_ratio"] > a["power_ratio"], "power_ratio растёт с дистанцией") and ok

	# (б) Перекрытый коридор → кандидат исключён → фолбэк (index -1).
	var blocked := ThrowInPlan.choose(spot, into, up, ARC, [Vector3(10, 0, 0)], [Vector3(5, 0, 0)],
		MIN, MAX, BSP, OPP, CHW, CSP, UPW)
	ok = _expect(blocked["index"] == -1, "б: перехваченный исключён → фолбэк") and ok

	# (в) Вне дальности (слишком близко) → index -1 + самодостаточный фолбэк.
	var none := ThrowInPlan.choose(spot, into, up, ARC, [Vector3(2, 0, 0)], [],
		MIN, MAX, BSP, OPP, CHW, CSP, UPW)
	ok = _expect(none["index"] == -1, "в: вне дальности → index -1") and ok
	ok = _expect(none["aim_dir"].dot(into) > 0.99 and absf(none["power_ratio"] - 0.5) < 0.001, "в: фолбэк = в поле, ratio 0.5") and ok

	# (г) Гейт сектора: кандидат за ±90° (позади линии) не выбирается.
	var behind := ThrowInPlan.choose(spot, into, up, ARC, [Vector3(-1, 0, 10)], [],
		MIN, MAX, BSP, OPP, CHW, CSP, UPW)
	ok = _expect(behind["index"] == -1, "г: за сектором → исключён") and ok

	if ok:
		print("CHECK PASS: throw_in_plan")
		quit(0)
	else:
		print("CHECK FAIL: throw_in_plan")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

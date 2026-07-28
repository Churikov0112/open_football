extends SceneTree
## Headless-проверка чистого скорера CornerPlan.choose (lob-first). Тюнинг — литералами (класс не
## читает FootballConstants). spot в нуле, base_heading = attack_dir = +Z (в створ/вверх поля).

const ARC := 1.4
const G_MIN := 2.0
const G_MAX := 18.0
const L_MIN := 18.0
const L_MAX := 50.0
const L_BIAS := 6.0
const PT_MIN := 0.3
const PT_MAX := 0.9
const PS_MIN := 8.0
const PS_MAX := 20.0
const OPP := 8.0
const CHW := 1.2
const CSP := 0.06
const UPW := 1.0

func _c(candidates: Array, opponents: Array) -> Dictionary:
	var z := Vector3(0, 0, 1)
	return CornerPlan.choose(Vector3.ZERO, z, z, ARC, candidates, opponents,
		G_MIN, G_MAX, L_MIN, L_MAX, L_BIAS, PT_MIN, PT_MAX, PS_MIN, PS_MAX, OPP, CHW, CSP, UPW)

func _init() -> void:
	var ok := true

	# (а) Цель в lob-диапазоне и секторе → навес (variant 1), power = инверсия lerp по lob-дальности.
	var tgt_a := Vector3(3, 0, 25)
	var a := _c([tgt_a], [])
	ok = _expect(a["index"] == 0 and a["variant"] == 1, "а: цель в штрафной → навес (variant 1)") and ok
	ok = _expect(absf(a["power_ratio"] - clampf(inverse_lerp(L_MIN, L_MAX, tgt_a.length()), 0.0, 1.0)) < 0.001, "а: power = инверсия lerp lob") and ok
	ok = _expect(a["aim_dir"].dot(tgt_a.normalized()) > 0.99, "а: aim_dir на цель") and ok

	# (б) Цель чуть ближе нижней кромки навеса, но в пределах bias → всё ещё навес, power клампится в 0.
	var b := _c([Vector3(0, 0, 14)], [])
	ok = _expect(b["variant"] == 1 and b["power_ratio"] < 0.001, "б: цель в bias-зоне → навес на мин. заряде") and ok

	# (в) Цель слишком близка для навеса, но в наземном диапазоне и коридор чист → короткий пас (variant 0).
	var c := _c([Vector3(0, 0, 10)], [])
	ok = _expect(c["index"] == 0 and c["variant"] == 0, "в: близкая цель, чистый коридор → наземный (variant 0)") and ok

	# (г) Та же близкая цель, но коридор перекрыт соперником → недостижима → фолбэк (index -1).
	var d := _c([Vector3(0, 0, 10)], [Vector3(0, 0, 5)])
	ok = _expect(d["index"] == -1, "г: наземный коридор перекрыт → фолбэк") and ok

	# (д) Фолбэк самодостаточен: aim_dir = base_heading (+Z), variant lob, power 0.5.
	var e := _c([Vector3(0, 0, 1)], [])
	ok = _expect(e["index"] == -1 and e["variant"] == 1, "д: вне диапазонов → index -1, навес") and ok
	ok = _expect(e["aim_dir"].dot(Vector3(0, 0, 1)) > 0.99 and absf(e["power_ratio"] - 0.5) < 0.001, "д: фолбэк = в створ, ratio 0.5") and ok

	# (е) Гейт дуги: цель за ±ARC от base_heading (сбоку, ~90°) исключена → фолбэк.
	var f := _c([Vector3(25, 0, 0)], [])
	ok = _expect(f["index"] == -1, "е: цель за сектором дуги → исключена") and ok

	if ok:
		print("CHECK PASS: corner_plan")
		quit(0)
	else:
		print("CHECK FAIL: corner_plan")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

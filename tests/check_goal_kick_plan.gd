extends SceneTree
## Headless-проверка чистого скорера GoalKickPlan.choose. Тюнинг — литералами (класс не читает
## FootballConstants). attack_dir = +Z (вверх поля), spot в начале координат — скорер работает с
## (candidate - spot) в плоскости XZ.

# Тюнинг-литералы (совпадают со значениями секции GOAL KICK / PASS в football_constants).
const GMIN := 12.0
const GMAX := 45.0
const LMIN := 18.0
const LMAX := 55.0
const PMINT := 0.3
const PMAXT := 0.7
const PMINS := 15.0
const PMAXS := 40.0
const OPP := 8.0
const CHW := 1.2
const CSP := 0.06
const ARC := 1.2
const UPW := 1.0

func _init() -> void:
	var ok := true
	var spot := Vector3.ZERO
	var up := Vector3(0.0, 0.0, 1.0)

	# (а) Открытый ближний свой в ground-диапазоне → ground (variant 0), index 0.
	var a := GoalKickPlan.choose(spot, up, ARC, [Vector3(0, 0, 20)], [],
		GMIN, GMAX, LMIN, LMAX, PMINT, PMAXT, PMINS, PMAXS, OPP, CHW, CSP, UPW)
	ok = _expect(a["index"] == 0, "а: выбран единственный кандидат") and ok
	ok = _expect(a["variant"] == 0, "а: ground при чистом коридоре") and ok
	ok = _expect(absf(a["power_ratio"] - (20.0 - GMIN) / (GMAX - GMIN)) < 0.001, "а: power_ratio = инверсия lerp") and ok
	ok = _expect(a["aim_dir"].dot(up) > 0.99, "а: aim_dir на кандидата") and ok

	# power_ratio монотонен по дистанции.
	var a_far := GoalKickPlan.choose(spot, up, ARC, [Vector3(0, 0, 40)], [],
		GMIN, GMAX, LMIN, LMAX, PMINT, PMAXT, PMINS, PMAXS, OPP, CHW, CSP, UPW)
	ok = _expect(a_far["power_ratio"] > a["power_ratio"], "power_ratio растёт с дистанцией") and ok

	# (б) Тот же кандидат: чистый коридор → ground; перекрытый → падение в lob (variant 1).
	var clear := GoalKickPlan.choose(spot, up, ARC, [Vector3(0, 0, 30)], [],
		GMIN, GMAX, LMIN, LMAX, PMINT, PMAXT, PMINS, PMAXS, OPP, CHW, CSP, UPW)
	ok = _expect(clear["variant"] == 0, "б: без соперников — ground") and ok
	var blocked := GoalKickPlan.choose(spot, up, ARC, [Vector3(0, 0, 30)], [Vector3(0, 0, 15)],
		GMIN, GMAX, LMIN, LMAX, PMINT, PMAXT, PMINS, PMAXS, OPP, CHW, CSP, UPW)
	ok = _expect(blocked["index"] == 0 and blocked["variant"] == 1, "б: перекрытый низ → lob на того же") and ok

	# (в) Все вне диапазона (слишком близко) → index -1, но выход самодостаточен (lob вперёд).
	var none := GoalKickPlan.choose(spot, up, ARC, [Vector3(0, 0, 5)], [],
		GMIN, GMAX, LMIN, LMAX, PMINT, PMAXT, PMINS, PMAXS, OPP, CHW, CSP, UPW)
	ok = _expect(none["index"] == -1, "в: недостижимый → index -1") and ok
	ok = _expect(none["variant"] == 1 and absf(none["power_ratio"] - 1.0) < 0.001, "в: фолбэк lob полной силой") and ok
	ok = _expect(none["aim_dir"].dot(up) > 0.99, "в: фолбэк-направление = attack_dir") and ok

	# (д) Гейт дуги: широкий кандидат (угол > ARC) не выбирается даже будучи «дальше»; берётся прямой.
	var wide := Vector3(100, 0, 10)     # atan2(100,10) ≈ 84° > 68.75° (1.2 рад)
	var straight := Vector3(0, 0, 25)
	var g := GoalKickPlan.choose(spot, up, ARC, [wide, straight], [],
		GMIN, GMAX, LMIN, LMAX, PMINT, PMAXT, PMINS, PMAXS, OPP, CHW, CSP, UPW)
	ok = _expect(g["index"] == 1, "д: широкий за дугой отсеян, выбран прямой") and ok

	if ok:
		print("CHECK PASS: goal_kick_plan")
		quit(0)
	else:
		print("CHECK FAIL: goal_kick_plan")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

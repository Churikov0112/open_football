extends SceneTree
## Headless-проверка RefereeLogic. team_defending_neg=2 (team_2 защищает -Z ворота).

const HL := 52.5
const PA_DEPTH := 16.5
const PA_HW := 20.16
const TDN := 2   # team_defending_neg

func _init() -> void:
	var ok := true
	ok = _check_throw_in() and ok
	ok = _check_corner() and ok
	ok = _check_goal_kick() and ok
	ok = _check_foul_free_kick() and ok
	ok = _check_foul_penalty() and ok
	ok = _check_select_taker() and ok
	if ok:
		print("CHECK PASS: referee_logic")
		quit(0)
	else:
		print("CHECK FAIL: referee_logic")
		quit(1)

func _check_throw_in() -> bool:
	# Аут, последним касался team_1 → вброс исполняет team_2.
	var r := RefereeLogic.ball_out_restart(BoundaryLogic.Exit.TOUCHLINE, 1, TDN)
	if not (r["restart"] == RefereeLogic.Restart.THROW_IN and r["team"] == 2):
		print("  FAIL throw_in: ", r); return false
	return true

func _check_corner() -> bool:
	# За -Z (защищает team_2), последним касался team_2 (защищающийся) → угловой, бьёт team_1.
	var r := RefereeLogic.ball_out_restart(BoundaryLogic.Exit.GOAL_LINE_NEG, 2, TDN)
	if not (r["restart"] == RefereeLogic.Restart.CORNER and r["team"] == 1):
		print("  FAIL corner: ", r); return false
	return true

func _check_goal_kick() -> bool:
	# За -Z, последним касался team_1 (атакующий) → удар от ворот, бьёт team_2 (защита).
	var r := RefereeLogic.ball_out_restart(BoundaryLogic.Exit.GOAL_LINE_NEG, 1, TDN)
	if not (r["restart"] == RefereeLogic.Restart.GOAL_KICK and r["team"] == 2):
		print("  FAIL goal_kick: ", r); return false
	return true

func _check_foul_free_kick() -> bool:
	# team_1 фолит в центре поля против team_2 → штрафной team_2, не пенальти.
	var r := RefereeLogic.foul_restart(Vector3(0, 0, 0), 1, 2, HL, TDN, PA_DEPTH, PA_HW)
	if not (r["restart"] == RefereeLogic.Restart.FREE_KICK and r["team"] == 2):
		print("  FAIL foul_free_kick: ", r); return false
	return true

func _check_foul_penalty() -> bool:
	# team_2 (защищает -Z) фолит в СВОЕЙ штрафной (z=-45, |x|<20.16) против team_1 → пенальти team_1.
	var r := RefereeLogic.foul_restart(Vector3(3, 0, -45.0), 2, 1, HL, TDN, PA_DEPTH, PA_HW)
	if not (r["restart"] == RefereeLogic.Restart.PENALTY and r["team"] == 1):
		print("  FAIL foul_penalty: ", r); return false
	# team_1 (атакующий) фолит в той же штрафной → обычный штрафной team_2, НЕ пенальти.
	var r2 := RefereeLogic.foul_restart(Vector3(3, 0, -45.0), 1, 2, HL, TDN, PA_DEPTH, PA_HW)
	if not (r2["restart"] == RefereeLogic.Restart.FREE_KICK and r2["team"] == 2):
		print("  FAIL foul_penalty_attacker: ", r2); return false
	return true

func _check_select_taker() -> bool:
	var spot := Vector3(10, 0, 10)
	var positions := [Vector3(0, 0, 0), Vector3(9, 0, 9), Vector3(-5, 0, -5)]
	var idx := RefereeLogic.select_taker(spot, positions)
	if idx != 1:
		print("  FAIL select_taker: ", idx); return false
	if RefereeLogic.select_taker(spot, []) != -1:
		print("  FAIL select_taker empty"); return false
	return true

class_name RefereeLogic
extends Object
## Чистое разрешение рестарта. НИКОГДА не читает FootballConstants — тюнинг/размеры параметрами.
## Команды кодируются int: 1 = team_1, 2 = team_2, 0 = неизвестно.

enum Restart { THROW_IN = 0, CORNER = 1, GOAL_KICK = 2, KICKOFF = 3, FREE_KICK = 4, PENALTY = 5 }

## Противоположная команда. 0 (неизвестно) → 1 как защитный дефолт (судья вызывает только при
## валидном last_touch; дефолт лишь чтобы не вернуть 0).
static func opposite(team: int) -> int:
	return 1 if team == 2 else 2 if team == 1 else 1

## Рестарт при выходе мяча за линию. team в результате — ИСПОЛНЯЮЩАЯ команда.
## Аут → команда, противоположная last_touch. За лицевой: если касался защищающийся (чьи это
## ворота) → угловой (бьёт атакующий); если атакующий → удар от ворот (бьёт защита).
static func ball_out_restart(exit: int, last_touch_team: int, team_defending_neg: int) -> Dictionary:
	if exit == BoundaryLogic.Exit.TOUCHLINE:
		return { "restart": Restart.THROW_IN, "team": opposite(last_touch_team) }
	var defender := team_defending_neg if exit == BoundaryLogic.Exit.GOAL_LINE_NEG else opposite(team_defending_neg)
	if last_touch_team == defender:
		return { "restart": Restart.CORNER, "team": opposite(defender) }
	return { "restart": Restart.GOAL_KICK, "team": defender }

## Рестарт при фоле подката. team — исполняющая (пострадавшая) команда. Пенальти — только если
## точка фола внутри штрафной площади, которую ЗАЩИЩАЕТ команда фолившего; иначе штрафной.
static func foul_restart(foul_pos: Vector3, fouler_team: int, fouled_team: int, half_len: float, team_defending_neg: int, pa_depth: float, pa_half_width: float) -> Dictionary:
	var defends_neg := fouler_team == team_defending_neg
	var goal_z := -half_len if defends_neg else half_len
	var into := 1.0 if defends_neg else -1.0
	var rel := (foul_pos.z - goal_z) * into   # 0 на линии ворот фолившего, растёт в поле
	var in_box := absf(foul_pos.x) <= pa_half_width and rel >= 0.0 and rel <= pa_depth
	var restart := Restart.PENALTY if in_box else Restart.FREE_KICK
	return { "restart": restart, "team": fouled_team }

## Индекс ближайшей к spot позиции (кто бьёт = ближайший подходящий). -1 если пусто.
static func select_taker(spot: Vector3, positions: Array) -> int:
	var best := -1
	var best_d := INF
	for i in positions.size():
		var d: float = (positions[i] as Vector3).distance_squared_to(spot)
		if d < best_d:
			best_d = d
			best = i
	return best

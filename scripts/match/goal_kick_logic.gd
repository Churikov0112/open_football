class_name GoalKickLogic
extends Object
## Чистая математика удара от ворот. НИКОГДА не читает FootballConstants — тюнинг параметрами.

## Точка мяча: центр линии вратарской площади (X=0, Z = линия ворот + into*глубина площади).
static func spot_position(goal_line_z: float, into: float, ga_depth: float, ball_radius: float) -> Vector3:
	return Vector3(0.0, ball_radius, goal_line_z + into * ga_depth)

## Расстановка вратаря-бьющего за мячом на разбег: назад вдоль -forward на runup_dist,
## латеральный сдвиг под опорную ногу (правая → правее вдоль forward.cross(UP)). y = body_y.
static func runup_placement(spot: Vector3, forward: Vector3, runup_dist: float, foot_lateral: float, foot: String, body_y: float) -> Vector3:
	var right := forward.cross(Vector3.UP).normalized()
	var side := 1.0 if foot == "penalty_r" else -1.0
	var p := spot - forward * runup_dist + right * (-side * foot_lateral)
	p.y = body_y
	return p

## Если pos внутри штрафной площади у goal_line_z (по ширине И по глубине от линии) — вытолкнуть
## его за 16.5-метровую линию (+ margin запаса), в поле (по into). Иначе вернуть pos без изменений.
## Правило: соперники бьющей команды до ввода мяча не могут находиться в штрафной.
static func push_out_of_penalty_area(pos: Vector3, goal_line_z: float, into: float, pa_depth: float, pa_half_width: float, margin: float) -> Vector3:
	var in_width := absf(pos.x) <= pa_half_width
	var rel := (pos.z - goal_line_z) * into   # 0 на линии ворот, растёт в поле
	var in_depth := rel >= 0.0 and rel <= pa_depth
	if in_width and in_depth:
		var out := pos
		out.z = goal_line_z + into * (pa_depth + margin)
		return out
	return pos

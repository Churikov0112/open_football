class_name KeeperLogic
extends Object
## Чистая математика вратаря. НИКОГДА не читает FootballConstants — тюнинг параметрами.

enum SaveAction { NONE, CATCH, CATCH_TOP, DIVE_LOW_L, DIVE_LOW_R, DIVE_HIGH_L, DIVE_HIGH_R }

## Где вратарю стоять: X следует за мячом (клампится к створу), Z сходит с линии в поле
## тем дальше, чем ближе мяч (сужение угла), но не дальше max_off_line.
static func line_position(ball_pos: Vector3, goal_line_z: float, goal_half_width: float, narrow_gain: float, max_off_line: float) -> Vector3:
	var x := clampf(ball_pos.x, -goal_half_width, goal_half_width)
	var dz := absf(ball_pos.z - goal_line_z)
	var off := clampf(max_off_line - narrow_gain * dz, 0.0, max_off_line)
	var into_field := -1.0 if goal_line_z > 0.0 else 1.0
	return Vector3(x, 0.0, goal_line_z + into_field * off)

## Точка пересечения траектории удара с плоскостью линии ворот (z=goal_line_z).
## Если мяч не движется к линии впереди — возвращает позицию мяча (нет пересечения).
static func shot_intercept(ball_pos: Vector3, ball_vel: Vector3, goal_line_z: float) -> Vector3:
	var vz := ball_vel.z
	if absf(vz) < 0.001:
		return ball_pos
	var t := (goal_line_z - ball_pos.z) / vz
	if t < 0.0:
		return ball_pos
	return ball_pos + ball_vel * t

## Попадает ли точка пересечения в створ (по |x| и по высоте).
static func is_on_target(intercept: Vector3, goal_half_width: float, goal_height: float) -> bool:
	return absf(intercept.x) <= goal_half_width and intercept.y <= goal_height and intercept.y >= -0.1

## По геометрии: поймать на месте (центр) / нырнуть (угол, низ или верх) / недосягаемо.
## dx<0 = мяч слева от вратаря (вратарь лицом в поле -Z → его левая рука = -X).
static func save_decision(intercept: Vector3, keeper_pos: Vector3, reach_radius: float, dive_range: float, high_threshold: float) -> Dictionary:
	var dx := intercept.x - keeper_pos.x
	var horiz := absf(dx)
	var high := intercept.y >= high_threshold
	if horiz <= reach_radius:
		return {"action": SaveAction.CATCH_TOP if high else SaveAction.CATCH, "target": intercept}
	if horiz <= dive_range:
		if high:
			return {"action": SaveAction.DIVE_HIGH_L if dx < 0.0 else SaveAction.DIVE_HIGH_R, "target": intercept}
		return {"action": SaveAction.DIVE_LOW_L if dx < 0.0 else SaveAction.DIVE_LOW_R, "target": intercept}
	return {"action": SaveAction.NONE, "target": intercept}

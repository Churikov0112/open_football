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
## ЧИСЛЕННО, тем же интегратором, что и настоящий мяч: гравитация по Y + драг
## (drag_xz/drag_y — множители скорости ЗА ФИЗКАДР dt, как в ball_controller).
## Драг критичен: при drag_xz=0.985 мяч теряет ~60% горизонтальной скорости в секунду,
## реальный полёт дольше наивного t=dz/vz, и мяч опускается на 0.3–0.5 м НИЖЕ чистой
## баллистики. Наивный расчёт завышал высоту → вратарь «пропускал над перекладиной»
## мячи, реально летящие под неё. drag=1.0 (по умолчанию) → чистая баллистика.
## Если мяч не движется к линии впереди (или затухает, не долетев) — возвращает позицию мяча.
static func shot_intercept(ball_pos: Vector3, ball_vel: Vector3, goal_line_z: float, gravity: float, drag_xz: float = 1.0, drag_y: float = 1.0, dt: float = 1.0 / 60.0) -> Vector3:
	if absf(ball_vel.z) < 0.001:
		return ball_pos
	if (goal_line_z - ball_pos.z) / ball_vel.z < 0.0:
		return ball_pos  # летит ОТ линии
	var pos := ball_pos
	var vel := ball_vel
	var t := 0.0
	while t < 3.0:
		var prev := pos
		# Полушаг гравитации до и после сдвига (leapfrog): при drag=1 парабола точная.
		vel.y -= 0.5 * gravity * dt
		pos += vel * dt
		vel.y -= 0.5 * gravity * dt
		vel.x *= drag_xz
		vel.z *= drag_xz
		vel.y *= drag_y
		t += dt
		if (goal_line_z - prev.z) * (goal_line_z - pos.z) <= 0.0:
			var seg := pos.z - prev.z
			var f := clampf((goal_line_z - prev.z) / seg, 0.0, 1.0) if absf(seg) > 0.000001 else 0.0
			var hit := prev.lerp(pos, f)
			return Vector3(hit.x, maxf(hit.y, 0.0), goal_line_z)
	return ball_pos  # затух в драге, до линии не долетает

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

## Сколько мячу лететь до точки пересечения (по его скорости). Стоящий мяч → INF.
static func time_to_intercept(ball_pos: Vector3, ball_vel: Vector3, intercept: Vector3) -> float:
	var speed := ball_vel.length()
	if speed < 0.001:
		return INF
	return ball_pos.distance_to(intercept) / speed

## Пора ли стартовать нырок: мячу до точки лететь не дольше, чем нырку до неё доехать
## (расстояние/скорость) + запас на раскрытие позы. Раньше — ждём/подшагиваем.
static func should_commit_dive(t_to_intercept: float, keeper_pos: Vector3, target: Vector3, dive_speed: float, lead_margin: float) -> bool:
	if dive_speed <= 0.0:
		return true
	var dive_time := keeper_pos.distance_to(target) / dive_speed
	return t_to_intercept <= dive_time + lead_margin

## Ловить или отбивать. Центр — всегда ловля; верхний угол — всегда отбой; нижний угол —
## ловля медленного, отбой быстрого. (Диктуется имеющимися анимациями.)
static func resolve_save(action: int, ball_speed: float, catch_max_speed: float) -> bool:
	match action:
		SaveAction.CATCH, SaveAction.CATCH_TOP:
			return true
		SaveAction.DIVE_HIGH_L, SaveAction.DIVE_HIGH_R:
			return false
		SaveAction.DIVE_LOW_L, SaveAction.DIVE_LOW_R:
			return ball_speed <= catch_max_speed
		_:
			return false

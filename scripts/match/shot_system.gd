class_name ShotSystem
extends Object

## Контекст «удар vs вынос»: далеко от чужих ворот ИЛИ повёрнут не к ним → вынос.
static func wants_clearance(shooter_pos: Vector3, goal_center: Vector3, facing: Vector3,
		clearance_dist: float, facing_dot_min: float) -> bool:
	var to_goal := goal_center - shooter_pos
	to_goal.y = 0.0
	var dist := to_goal.length()
	if dist > clearance_dist:
		return true
	if dist < 0.001:
		return false
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length() < 0.001:
		return false
	return f.normalized().dot(to_goal.normalized()) < facing_dot_min

## Точка прицела в створе. side_bias/charge задают угол/высоту, потом разброс scatter_m (RNG).
## Заряд поднимает точку (сильный удар выше — риск через перекладину на over_lift метров).
static func goal_aim_point(goal_center: Vector3, half_width: float, height: float,
		side_bias: float, charge_ratio: float, over_lift: float, scatter_m: float,
		rng: RandomNumberGenerator) -> Vector3:
	var cr := clampf(charge_ratio, 0.0, 1.0)
	var x := goal_center.x + clampf(side_bias, -1.0, 1.0) * half_width
	var y := lerpf(0.25, height + over_lift, cr)
	x += rng.randf_range(-scatter_m, scatter_m)
	y += rng.randf_range(-scatter_m * 0.6, scatter_m * 0.6)
	return Vector3(x, maxf(y, 0.05), goal_center.z)

## Баллистическая стартовая скорость: горизонталь = horizontal_speed, попадает в точку to
## (по высоте — через компенсацию гравитации за время полёта). Общая для bullet и curl.
static func ballistic_to(from: Vector3, to: Vector3, horizontal_speed: float, gravity: float) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := flat.length()
	if dist < 0.001:
		return Vector3.ZERO
	var hs := maxf(horizontal_speed, 0.001)
	var t := dist / hs
	var vy := (to.y - from.y) / t + 0.5 * gravity * t
	return flat.normalized() * hs + Vector3.UP * vy

## Знак кручения: в какую сторону от прямой «на центр ворот» смотрит игрок — в тот угол крутим.
## +1 / -1 (знак подбирается тюнингом живьём — см. ручную приёмку).
static func curl_side(shooter_pos: Vector3, goal_center: Vector3, facing: Vector3) -> float:
	var straight := goal_center - shooter_pos
	straight.y = 0.0
	var f := Vector3(facing.x, 0.0, facing.z)
	if straight.length() < 0.001 or f.length() < 0.001:
		return 1.0
	var cross := straight.normalized().cross(f.normalized()).y
	return 1.0 if cross >= 0.0 else -1.0

## Вектор _curl для ball.launch_curl: .z — боковая составляющая (через left=vel×UP),
## .y — подъём (дуга). .x не используется движком.
static func curl_vector(side: float, curl_strength: float, lift: float) -> Vector3:
	return Vector3(0.0, lift, side * curl_strength)

## Вынос: мощно по направлению aim_dir (facing/стик) вдаль, с подъёмом lift.
static func clearance_velocity(aim_dir: Vector3, power: float, lift: float) -> Vector3:
	var d := Vector3(aim_dir.x, 0.0, aim_dir.z)
	if d.length() < 0.001:
		return Vector3.ZERO
	return d.normalized() * power + Vector3.UP * lift

## Разброс прицела (м): растёт с зарядом и дистанцией. На максимуме заряда — «велик риск промаха».
static func scatter_meters(base_m: float, charge_ratio: float, distance: float, dist_ref: float) -> float:
	var cr := clampf(charge_ratio, 0.0, 1.0)
	var dist_factor := clampf(distance / maxf(dist_ref, 0.001), 0.5, 1.5)
	return base_m * (0.5 + cr) * dist_factor

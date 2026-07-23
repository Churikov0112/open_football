class_name PenaltyLogic
extends Object
## Чистая математика пенальти. НИКОГДА не читает FootballConstants — тюнинг параметрами.

## Зоны прыжка вратаря (слепой выбор). CENTER = остался в центре.
enum Zone { LOW_L, HIGH_L, LOW_R, HIGH_R, CENTER }

## Сдвиг маркера прицела по плоскости ворот (X = ширина, Y = высота над газоном),
## кламп в рамку + небольшой овершут за штанги/перекладину (можно целиться впритирку/мимо).
static func move_reticle(cur: Vector2, stick: Vector2, speed: float, dt: float, half_width: float, height: float, overhang: float) -> Vector2:
	var next := cur + stick * speed * dt
	next.x = clampf(next.x, -(half_width + overhang), half_width + overhang)
	next.y = clampf(next.y, 0.0, height + overhang)
	return next

## Радиус круга разброса растёт с зарядом силы.
static func spread_radius(charge_ratio: float, min_r: float, max_r: float) -> float:
	return lerpf(min_r, max_r, clampf(charge_ratio, 0.0, 1.0))

## Скорость мяча растёт с зарядом силы.
static func power_speed(charge_ratio: float, min_speed: float, max_speed: float) -> float:
	return lerpf(min_speed, max_speed, clampf(charge_ratio, 0.0, 1.0))

## Равномерный семпл точки внутри диска (радиус через sqrt(u) — иначе центр перегружен).
static func sample_in_disc(center: Vector2, radius: float, rng: RandomNumberGenerator) -> Vector2:
	var ang := rng.randf() * TAU
	var r := radius * sqrt(rng.randf())
	return center + Vector2(cos(ang), sin(ang)) * r

## Точка плоскости ворот (xy) → мир. xy.x — смещение от центра створа, xy.y — высота над газоном.
static func plane_point_to_world(xy: Vector2, goal_center_x: float, goal_line_z: float) -> Vector3:
	return Vector3(goal_center_x + xy.x, xy.y, goal_line_z)

## Случайная зона нырка: 1 из 5 (включая CENTER).
static func random_dive_zone(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, 4)

## Квадрант стика → зона нырка. stick.x: лево<0/право>0; stick.y: низ<0/верх>0 (уже
## инвертированный aim_axis). Длина ниже deadzone → CENTER.
static func stick_to_zone(stick: Vector2, deadzone: float) -> int:
	if stick.length() < deadzone:
		return Zone.CENTER
	if stick.x < 0.0:
		return Zone.HIGH_L if stick.y > 0.0 else Zone.LOW_L
	return Zone.HIGH_R if stick.y > 0.0 else Zone.LOW_R

## Репрезентативная точка зоны на линии ворот (куда целит нырок). L = -X, R = +X
## (согласовано с KeeperLogic.save_decision: dx<0 → левый нырок).
static func zone_target(zone: int, goal_center_x: float, half_width: float, low_y: float, high_y: float, lateral: float, goal_line_z: float) -> Vector3:
	var x := goal_center_x
	var y := low_y
	match zone:
		Zone.LOW_L:
			x = goal_center_x - lateral
			y = low_y
		Zone.HIGH_L:
			x = goal_center_x - lateral
			y = high_y
		Zone.LOW_R:
			x = goal_center_x + lateral
			y = low_y
		Zone.HIGH_R:
			x = goal_center_x + lateral
			y = high_y
		Zone.CENTER:
			x = goal_center_x
			y = low_y
	x = clampf(x, -half_width, half_width)
	return Vector3(x, y, goal_line_z)

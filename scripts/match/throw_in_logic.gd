class_name ThrowInLogic
extends Object
## Чистая математика вброса из аута. НИКОГДА не читает FootballConstants — тюнинг параметрами.

## Точка аута: проекция мяча на ближайшую боковую линию (X = ±half_width по знаку ball.x,
## Z мяча, Y = радиус мяча).
static func aut_point(ball_pos: Vector3, half_width: float, ball_radius: float) -> Vector3:
	var sx := 1.0 if ball_pos.x >= 0.0 else -1.0
	return Vector3(sx * half_width, ball_radius, ball_pos.z)

## Базовое направление вброса — перпендикуляр к боковой линии, внутрь поля.
## Правая линия (aut_x>0) → в поле это -X; левая → +X.
static func base_heading(aut_x: float) -> Vector3:
	return Vector3(-1.0, 0.0, 0.0) if aut_x >= 0.0 else Vector3(1.0, 0.0, 0.0)

## Расстановка вбрасывающего за боковой линией снаружи поля: aut минус направление-в-поле на
## behind_offset (т.е. на behind_offset НАРУЖУ от линии). y = body_y.
static func thrower_placement(aut: Vector3, into_field: Vector3, behind_offset: float, body_y: float) -> Vector3:
	var p := aut - into_field * behind_offset
	p.y = body_y
	return p

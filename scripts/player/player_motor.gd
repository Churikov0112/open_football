class_name PlayerMotor
extends Node

## Желаемая скорость из намерения. Плоский dir нормализуется; пустой → ноль.
static func desired_velocity(dir: Vector3, top_speed: float, speed_scale: float) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.1:
		return Vector3.ZERO
	return flat.normalized() * top_speed * speed_scale

## Интеграция скорости: разгон темпом accel, торможение (desired≈0) темпом decel.
static func integrate_velocity(current: Vector3, desired: Vector3, accel: float, decel: float, delta: float) -> Vector3:
	var rate := accel if desired.length() > 0.1 else decel
	var v := current.move_toward(desired, rate * delta)
	v.y = 0.0
	return v

## Сглаженный доворот угла (рыскание) к цели.
static func smooth_yaw(current_yaw: float, target_yaw: float, turn_rot: float, delta: float) -> float:
	return lerp_angle(current_yaw, target_yaw, clampf(turn_rot * delta, 0.0, 1.0))

## Крен корпуса (градусы) от нормированного бокового ускорения и разгона по скорости.
static func lean_deg(lateral_norm: float, speed_ramp: float, max_bank_deg: float) -> float:
	return clampf(lateral_norm, -1.0, 1.0) * max_bank_deg * clampf(speed_ramp, 0.0, 1.0)

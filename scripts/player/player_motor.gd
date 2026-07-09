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

## Экспоненциальное сглаживание скаляра к цели темпом rate (1/сек).
static func smooth_scalar(current: float, target: float, rate: float, delta: float) -> float:
	return lerpf(current, target, clampf(rate * delta, 0.0, 1.0))

## Вертикальная скорость: на земле обнуляется (стоим на полу), в воздухе копит g.
static func gravity_step(vy: float, grounded: bool, gravity: float, delta: float) -> float:
	if grounded:
		return 0.0
	return vy - gravity * delta

var _intent_dir: Vector3 = Vector3.ZERO
var _intent_scale: float = 1.0
var _locked: bool = false
var _body: CharacterBody3D
var _visual: PlayerVisual
var _lean_deg: float = 0.0
var _vy: float = 0.0

func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_warning("PlayerMotor: родитель не CharacterBody3D — motor выключен")
		set_physics_process(false)
		return
	_body.up_direction = Vector3.UP
	_body.floor_snap_length = 0.3
	for c in _body.get_children():
		if c is PlayerVisual:
			_visual = c
			break

## Передать намерение движения (мировой dir, нормализуется внутри). Зовётся каждый кадр.
func set_move_intent(dir: Vector3, speed_scale: float = 1.0) -> void:
	_intent_dir = dir
	_intent_scale = speed_scale

## Заблокировать управление (commit-действие / такл): скорость гаснет до 0, ввод игнорится.
func set_control_locked(on: bool) -> void:
	_locked = on

## Найти дочерний PlayerMotor у произвольного узла (общая логика для AI/match_manager).
static func find_on(node: Node) -> PlayerMotor:
	if node == null:
		return null
	for c in node.get_children():
		if c is PlayerMotor:
			return c
	return null

func _physics_process(delta: float) -> void:
	if _body == null or delta <= 0.0:
		return

	# Намерение: ноль, если заблокированы или сбиты (fallen).
	var locked_or_fallen := _locked or _body.is_in_group("fallen")
	var desired := Vector3.ZERO
	if not locked_or_fallen:
		desired = PlayerMotor.desired_velocity(_intent_dir, FootballConstants.LOCO_TOP_SPEED, _intent_scale)

	var prev := _body.velocity
	# Заблокирован/сбит: скорость гасится мгновенно, а не decel-темпом —
	# иначе move_and_slide() ниже продолжает толкать тело остаточной скоростью
	# (двойное движение поверх ручного move_and_collide() в подкате).
	var new_vel := Vector3.ZERO if locked_or_fallen else \
		PlayerMotor.integrate_velocity(prev, desired, FootballConstants.LOCO_ACCEL, FootballConstants.LOCO_DECEL, delta)
	var speed := new_vel.length()

	# Доворот тела к направлению движения (тело остаётся вертикальным).
	if speed > FootballConstants.LOCO_TURN_MIN_SPEED:
		var target_yaw := atan2(-new_vel.x, -new_vel.z)
		_body.rotation.y = PlayerMotor.smooth_yaw(_body.rotation.y, target_yaw, FootballConstants.LOCO_TURN_ROT, delta)

	# Banking: боковая компонента ускорения относительно направления взгляда.
	var accel_vec := (new_vel - prev) / delta
	var right := _body.global_transform.basis.x
	var lateral := right.dot(accel_vec) / FootballConstants.LOCO_ACCEL
	var ramp := speed / (0.5 * FootballConstants.LOCO_TOP_SPEED)

	# Вертикаль: гравитация + приземление на пол-коллайдер (вместо ручного пина Y).
	# Пока сбиты (fallen) — телом владеет ragdoll/оркестратор, motor вертикаль не трогает.
	if _body.is_in_group("fallen"):
		_vy = 0.0
		new_vel.y = 0.0
	else:
		_vy = PlayerMotor.gravity_step(_vy, _body.is_on_floor(), FootballConstants.GRAVITY, delta)
		new_vel.y = _vy
	_body.velocity = new_vel
	_body.move_and_slide()
	if _body.is_on_floor():
		_vy = 0.0

	# Сырой целевой крен скачет вместе с ускорением (WASD — не аналоговый ввод,
	# направление меняется мгновенно) — сглаживаем само значение, а не только вход в него.
	var target_lean := PlayerMotor.lean_deg(lateral, ramp, FootballConstants.LOCO_MAX_BANK_DEG)
	_lean_deg = PlayerMotor.smooth_scalar(_lean_deg, target_lean, FootballConstants.LOCO_BANK_SMOOTH, delta)

	if _visual != null:
		_visual.set_locomotion(new_vel)
		_visual.set_lean(_lean_deg)

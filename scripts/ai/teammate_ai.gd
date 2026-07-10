extends CharacterBody3D

@export var ball: RigidBody3D
@export var speed: float = 6.0
@export var controlled_player: CharacterBody3D
@export var teammate_home_goal: Node3D

var field_length: float = FootballConstants.HALF_FIELD_LENGTH
var field_width: float = FootballConstants.HALF_FIELD_WIDTH
var _wander_timer: float = 0.0

enum Role { SUPPORT, RECEIVING, CHASING }
var _role: Role = Role.SUPPORT
var _pass_dir: Vector3 = Vector3.ZERO
var _pass_lead: float = 0.0

## Менеджер зовёт это на партнёре, которому летит пас: перейти в режим выхода на приём.
func begin_receiving(pass_dir: Vector3, lead: float) -> void:
	_role = Role.RECEIVING
	_pass_dir = pass_dir
	_pass_lead = lead

func end_receiving() -> void:
	if _role == Role.RECEIVING:
		_role = Role.SUPPORT


func _motor() -> PlayerMotor:
	return PlayerMotor.find_on(self)

func _base_scale() -> float:
	return speed / FootballConstants.LOCO_TOP_SPEED


func _physics_process(delta: float) -> void:
	if not ball or not is_instance_valid(ball):
		return

	if is_in_group("fallen"):
		return

	# If human controls this player → skip
	if controlled_player == self:
		return

	var has_dribbler: bool = ball.has_method(&"set_dribbler") and ball.dribbler

	match _role:
		Role.RECEIVING:
			_move_to_receive(delta)
			return
		_:
			if has_dribbler and ball.dribbler == controlled_player:
				_position_for_pass(delta)
			else:
				_chase_ball(delta)


func _position_for_pass(delta: float) -> void:
	var carrier_pos := controlled_player.global_position
	# Position ahead of the carrier at a good passing distance (~10m)
	# and slightly to the side, alternating based on field position
	var side_sign := 1.0 if carrier_pos.x < 0 else -1.0
	var target := carrier_pos + Vector3(0, 0, -10.0) + Vector3(side_sign * 6.0, 0, 0)

	target.x = clamp(target.x, -field_width + 4, field_width - 4)
	target.z = clamp(target.z, -field_length + 4, field_length - 4)
	target.y = global_position.y

	var dir := (target - global_position).normalized()
	dir.y = 0.0
	_move_or_wander(dir, delta)


## Выход на приём: в ноги — к предсказанной точке мяча; на ход — вперёд по вектору паса.
func _move_to_receive(delta: float) -> void:
	var target: Vector3
	if _pass_lead > 0.0:
		target = global_position + _pass_dir.normalized() * _pass_lead
	else:
		var predicted := ball.global_position + ball.linear_velocity * FootballConstants.PASS_RECEIVE_PREDICT_WINDOW
		target = predicted
	target.y = global_position.y
	var dir := (target - global_position)
	dir.y = 0.0
	# Приём завершён, когда мяч у нас — вернёт менеджер через end_receiving(); тут просто бежим.
	_move_or_wander(dir.normalized(), delta)


func _chase_ball(delta: float) -> void:
	var target := ball.global_position
	target.y = global_position.y

	var dir := (target - global_position).normalized()
	dir.y = 0.0
	_move_or_wander(dir, delta)


func _move_or_wander(dir: Vector3, delta: float) -> void:
	if dir.length() > 0.1:
		var m := _motor()
		if m != null:
			m.set_move_intent(dir, _base_scale())
	else:
		_wander(delta)


func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(0.5, 1.5)
	# Gentle sinusoidal movement for a natural idling look
	var wander_x := sin(Time.get_ticks_msec() * 0.001 + global_position.z) * 0.5
	var wander_z := cos(Time.get_ticks_msec() * 0.001 + global_position.x) * 0.5
	var wander_dir := Vector3(wander_x, 0, wander_z).normalized()
	var m := _motor()
	if m != null:
		m.set_move_intent(wander_dir, _base_scale() * 0.3)

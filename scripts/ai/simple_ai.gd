extends CharacterBody3D

@export var ball: RigidBody3D
@export var speed: float = 6.5
@export var home_goal: Node3D
@export var target_node: Node3D

var can_kick: bool = true
var field_length: float = FootballConstants.HALF_FIELD_LENGTH
var _wander_timer: float = 0.0
var wants_to_tackle: bool = false
var tackle_cooldown: float = 0.0


func _motor() -> PlayerMotor:
	return PlayerMotor.find_on(self)

## Скорость этого ИИ относительно общей максимальной — сохраняет прежний относительный темп.
func _base_scale() -> float:
	return speed / FootballConstants.LOCO_TOP_SPEED


func _physics_process(delta: float) -> void:
	if not ball or not is_instance_valid(ball):
		return

	if is_in_group("fallen"):
		return

	if wants_to_tackle:
		return

	if _is_dribbling():
		_dribble_toward_goal(delta)
	elif target_node and is_instance_valid(target_node):
		_chase_target(target_node, delta)
	else:
		_chase_ball(delta)

	# Tackle decision
	tackle_cooldown -= delta
	if tackle_cooldown < 0.0:
		tackle_cooldown = 0.0
	if tackle_cooldown <= 0.0:
		var target: Node3D = null
		if ball.has_method(&"set_dribbler") and ball.dribbler and ball.dribbler.is_in_group("team_1"):
			target = ball.dribbler
		elif ball.has_method(&"get_last_touch") and ball.get_last_touch() and ball.get_last_touch().is_in_group("team_1"):
			target = ball.get_last_touch()
		if target:
			var dist := global_position.distance_to(target.global_position)
			if dist < FootballConstants.AI_TACKLE_RANGE:
				wants_to_tackle = true
				tackle_cooldown = FootballConstants.AI_TACKLE_COOLDOWN


func _is_dribbling() -> bool:
	return ball.has_method(&"set_dribbler") and is_instance_valid(ball) and ball.dribbler == self


func _chase_target(target: Node3D, delta: float) -> void:
	var to_target := target.global_position - global_position
	var dir := to_target.normalized()
	dir.y = 0.0

	_move_or_wander(dir, delta)

	# If close enough to ball while chasing, attempt to kick
	var ball_dist := global_position.distance_to(ball.global_position)
	if ball_dist < 1.8 and can_kick:
		_kick_towards_goal()


func _chase_ball(delta: float) -> void:
	var to_ball := ball.global_position - global_position
	var dist := to_ball.length()
	var dir := to_ball.normalized()
	dir.y = 0.0

	_move_or_wander(dir, delta)

	if dist < 1.8 and can_kick:
		_kick_towards_goal()


func _dribble_toward_goal(delta: float) -> void:
	var target: Vector3
	if home_goal:
		target = home_goal.global_position
	else:
		target = Vector3(0, 0, -field_length)

	var to_target := target - global_position
	var dist := to_target.length()
	var dir := to_target.normalized()
	dir.y = 0.0

	_move_or_wander(dir, delta, 0.8)

	if dist < 20.0 and can_kick:
		ball.release_dribble()
		_kick_towards_goal()


func _move_or_wander(dir: Vector3, delta: float, speed_multiplier: float = 1.0) -> void:
	if dir.length() > 0.1:
		var m := _motor()
		if m != null:
			m.set_move_intent(dir, _base_scale() * speed_multiplier)
	else:
		_wander(delta, speed_multiplier)


func _wander(delta: float, speed_multiplier: float = 1.0) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(0.5, 1.5)
	# Gentle sinusoidal movement for a natural idling look
	var wander_x := sin(Time.get_ticks_msec() * 0.001 + global_position.z) * 0.5
	var wander_z := cos(Time.get_ticks_msec() * 0.001 + global_position.x) * 0.5
	var wander_dir := Vector3(wander_x, 0, wander_z).normalized()
	var m := _motor()
	if m != null:
		m.set_move_intent(wander_dir, _base_scale() * 0.3 * speed_multiplier)


func _kick_towards_goal() -> void:
	if not ball or not is_instance_valid(ball):
		return
	if not ball.has_method(&"kick"):
		return
	var target: Vector3
	if home_goal:
		target = home_goal.global_position
	else:
		target = Vector3(0, 0, -field_length)
	# Add X offset for shot variety so shots don't always go center
	target.x += randf_range(-2.0, 2.0)
	var dir := (target - ball.global_position).normalized()
	dir.y = 0.2
	ball.kick(dir, 10.0)
	can_kick = false
	await get_tree().create_timer(0.8).timeout
	can_kick = true

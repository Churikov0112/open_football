extends CharacterBody3D

@export var ball: RigidBody3D
@export var speed: float = 5.0
@export var home_goal: Node3D

var can_kick: bool = true
var field_length: float = FootballConstants.HALF_FIELD_LENGTH


func _physics_process(delta: float) -> void:
	if not ball or not is_instance_valid(ball):
		return

	if _is_dribbling():
		_dribble_toward_goal(delta)
	else:
		_chase_ball(delta)


func _is_dribbling() -> bool:
	return ball.has_method(&"set_dribbler") and is_instance_valid(ball) and ball.dribbler == self


func _chase_ball(delta: float) -> void:
	var to_ball := ball.global_position - global_position
	var dist := to_ball.length()
	var dir := to_ball.normalized()
	dir.y = 0.0

	if dir.length() > 0.1:
		global_position.x += dir.x * speed * delta
		global_position.z += dir.z * speed * delta
		var target_angle := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 8.0 * delta)

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

	if dir.length() > 0.1:
		var dribble_speed := speed * 0.8
		global_position.x += dir.x * dribble_speed * delta
		global_position.z += dir.z * dribble_speed * delta
		var target_angle := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 8.0 * delta)

	if dist < 25.0 and can_kick:
		ball.release_dribble()
		_kick_towards_goal()


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
	var dir := (target - ball.global_position).normalized()
	dir.y = 0.2
	ball.kick(dir, 10.0)
	can_kick = false
	await get_tree().create_timer(0.8).timeout
	can_kick = true

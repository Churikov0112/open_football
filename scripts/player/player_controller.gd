extends CharacterBody3D

@export var speed: float = 7.0
@export var acceleration: float = 12.0
@export var ball: Node3D

var team_id: int = 0
var is_ai: bool = false


func _physics_process(delta: float) -> void:
	if is_ai or not is_multiplayer_authority():
		return
	var input_dir := Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_forward", &"move_back")
	)
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
		if direction.length() > 0.1:
			var target_angle := atan2(-direction.x, -direction.z)
			rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)
	velocity.y -= 9.8 * delta
	move_and_slide()


func _input(event: InputEvent) -> void:
	if is_ai:
		return
	if event.is_action_pressed(&"kick"):
		_kick_ball()
	if event.is_action_pressed(&"pass"):
		_pass_ball()


func _kick_ball() -> void:
	if not ball or not is_instance_valid(ball):
		return
	var dist := global_position.distance_to(ball.global_position)
	if dist > 2.0:
		return
	var dir := (ball.global_position - global_position).normalized()
	dir.y = 0.3
	var kick_force := 15.0
	if ball is RigidBody3D:
		ball.apply_central_force(dir * kick_force)


func _pass_ball() -> void:
	if not ball or not is_instance_valid(ball):
		return
	var dist := global_position.distance_to(ball.global_position)
	if dist > 2.0:
		return
	var dir := (ball.global_position - global_position).normalized()
	dir.y = 0.1
	var pass_force := 10.0
	if ball is RigidBody3D:
		ball.apply_central_force(dir * pass_force)

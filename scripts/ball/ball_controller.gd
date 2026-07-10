extends RigidBody3D

@export var drag_factor: float = 0.985
@export var air_resistance: float = 0.999

@export var dribble_forward_distance: float = 0.5
@export var dribble_height: float = 0.08
@export var dribble_max_speed: float = 12.0

var dribbler: Node3D
var last_kicker: Node3D
var _last_release_time: int = 0
var _release_cooldown_msec: int = 500
var _last_kick_time: int = 0
var _kick_cooldown_msec: int = 1500
var _dribbler_prev_pos: Vector3 = Vector3.ZERO
var _pending_impulse: Vector3 = Vector3.ZERO

enum BallState { OPEN, TRAPPED, FLIGHT, CAUGHT }
var state: BallState = BallState.OPEN
var _curl: Vector3 = Vector3.ZERO


func _ready() -> void:
	_football_texture()
	var phys_mat := PhysicsMaterial.new()
	phys_mat.bounce = 0.4
	physics_material_override = phys_mat


func _football_texture() -> void:
	var mesh_instance := $Mesh as MeshInstance3D
	if not mesh_instance:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.metallic = 0.0
	mat.roughness = 0.4
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for i in range(12):
		var cx := 30 + randi() % 196
		var cy := 30 + randi() % 196
		_draw_hexagon(img, cx, cy, 18, Color(0.1, 0.1, 0.1))
	var tex := ImageTexture.create_from_image(img)
	mat.albedo_texture = tex
	mesh_instance.material_override = mat


func _draw_hexagon(img: Image, cx: float, cy: float, r: float, color: Color) -> void:
	for x in range(int(cx - r), int(cx + r + 1)):
		for y in range(int(cy - r), int(cy + r + 1)):
			var dx := x - cx
			var dy := y - cy
			var dist := sqrt(dx * dx + dy * dy)
			if dist <= r:
				var angle := atan2(dy, dx)
				var test_angle := fmod(angle + PI / 6, PI / 3) - PI / 6
				var test_dist := dist * cos(test_angle)
				if test_dist <= r * cos(PI / 6) and dist <= r:
					img.set_pixel(x, y, color)


func set_dribbler(node: Node3D) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_release_time < _release_cooldown_msec:
		return
	if node and node == last_kicker and now - _last_kick_time < _kick_cooldown_msec:
		return
	dribbler = node
	_dribbler_prev_pos = node.global_position if node else Vector3.ZERO
	state = BallState.TRAPPED if node else BallState.OPEN


func release_dribble() -> void:
	if dribbler:
		dribbler = null
		_last_release_time = Time.get_ticks_msec()
	_dribbler_prev_pos = Vector3.ZERO
	state = BallState.OPEN


## Текущий владелец мяча (нейтральное имя поверх legacy-поля dribbler).
func player() -> Node3D:
	return dribbler


func clear_last_kicker() -> void:
	last_kicker = null
	_last_kick_time = 0


func get_dribble_direction() -> Vector3:
	if not dribbler or not is_instance_valid(dribbler):
		return Vector3.FORWARD
	return _get_movement_direction()


## Read-only версия get_dribble_direction() — НЕ трогает _dribbler_prev_pos.
## _integrate_forces() каждый физический тик читает И пишет _dribbler_prev_pos, чтобы
## посчитать скорость дриблера (pos_delta = player_pos - _dribbler_prev_pos; player_vel =
## pos_delta/dt). match_manager._process() вызывает get_dribble_direction() КАЖДЫЙ
## РЕНДЕР-КАДР во время зарядки паса (для маркера прицеливания) — если вызвать
## мутирующий геттер, он обнулит дельту раньше, чем до неё доберётся _integrate_forces(),
## и measured pos_delta занизится → мяч отстаёт/дёргается от дриблера при любой зарядке
## паса. Поэтому здесь используем только текущую ориентацию тела (facing), как в
## fallback-ветке _direction_from_delta()/_get_movement_direction(), но без трекинга
## дельты позиции и без побочных эффектов. НЕ "упрощай" обратно в get_dribble_direction() —
## это вернёт гонку.
func peek_dribble_direction() -> Vector3:
	if not dribbler or not is_instance_valid(dribbler):
		return Vector3.FORWARD
	var facing := -dribbler.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		return facing.normalized()
	return Vector3.FORWARD


func kick(direction: Vector3, power: float) -> void:
	last_kicker = dribbler
	_last_kick_time = Time.get_ticks_msec()
	release_dribble()
	state = BallState.FLIGHT
	_pending_impulse = direction * power


## Задать мячу готовую стартовую скорость (в отличие от kick(), где power — импульс, а dir
## не нормализован). velocity — уже посчитанная баллистика (PassSystem.launch_ground/launch_lob).
## Импульс = velocity*mass, т.к. _integrate_forces применяет vel += _pending_impulse/mass.
func launch(velocity: Vector3) -> void:
	last_kicker = dribbler
	_last_kick_time = Time.get_ticks_msec()
	release_dribble()
	state = BallState.FLIGHT
	_pending_impulse = velocity * mass


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var vel := state.linear_velocity

	if dribbler and is_instance_valid(dribbler):
		var player_pos := dribbler.global_position
		var dt := state.step

		var pos_delta := player_pos - _dribbler_prev_pos
		_dribbler_prev_pos = player_pos
		pos_delta.y = 0.0

		var move_dir := _direction_from_delta(pos_delta)
		var target := player_pos \
			+ move_dir * dribble_forward_distance \
			+ Vector3.UP * dribble_height

		if pos_delta.length_squared() > 0.001 and dt > 0:
			var player_vel := pos_delta / dt
			player_vel = player_vel.limit_length(15.0)
			var disp := target - state.transform.origin
			var correction := disp * 30.0
			correction = correction.limit_length(12.0)
			vel.x = player_vel.x + correction.x
			vel.z = player_vel.z + correction.z
		else:
			var disp := target - state.transform.origin
			var correction := disp * 10.0
			correction = correction.limit_length(dribble_max_speed)
			vel.x = correction.x
			vel.z = correction.z

		vel.y *= air_resistance
	else:
		vel.x *= drag_factor
		vel.z *= drag_factor
		vel.y *= air_resistance

	if _pending_impulse.length_squared() > 0:
		vel += _pending_impulse / mass
		_pending_impulse = Vector3.ZERO

	state.linear_velocity = vel


func _direction_from_delta(pos_delta: Vector3) -> Vector3:
	if pos_delta.length_squared() > 0.0001:
		return pos_delta.normalized()
	var facing := -dribbler.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		return facing.normalized()
	return Vector3.FORWARD


func _get_movement_direction() -> Vector3:
	var pos_delta := dribbler.global_position - _dribbler_prev_pos
	_dribbler_prev_pos = dribbler.global_position
	pos_delta.y = 0.0
	if pos_delta.length_squared() > 0.0001:
		return pos_delta.normalized()

	var facing := -dribbler.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		return facing.normalized()

	return Vector3.FORWARD

extends CharacterBody3D

@export var ball: RigidBody3D
# Было 6.5 — заметно медленнее человека (LOCO_TOP_SPEED=8.0), из-за чего человек почти
# всегда мог убежать/догнать при подкате, а ИИ — почти никогда. Подняли до 8.0, вровень
# с обычным бегом человека; спринт (LOCO_SPRINT_SPEED=12.0, только у человека) остаётся
# реальным преимуществом для отрыва.
@export var speed: float = 8.0
@export var home_goal: Node3D
@export var target_node: Node3D

var can_kick: bool = true
var field_length: float = FootballConstants.HALF_FIELD_LENGTH
var _wander_timer: float = 0.0

## DEBUG: кого маркировать (ставит менеджер при DEBUG_MARK_TEAMMATE) — встаём в линию паса к нему.
var mark_target: Node3D = null
var wants_to_tackle: bool = false
var tackle_cooldown: float = 0.0

var _intercepting: bool = false
var _intercept_point: Vector3 = Vector3.ZERO
var _intercept_react_left: float = 0.0


func _motor() -> PlayerMotor:
	return PlayerMotor.find_on(self)

## Скорость этого ИИ относительно общей максимальной — сохраняет прежний относительный темп.
func _base_scale() -> float:
	return speed / FootballConstants.LOCO_TOP_SPEED

## Менеджер зовёт это, если геометрия коридора дала перехват (с учётом шанса «зевка»).
## Соперник реагирует не мгновенно (задержка), затем бежит к точке пересечения.
func begin_intercept(point: Vector3) -> void:
	_intercepting = true
	_intercept_point = point
	_intercept_react_left = FootballConstants.AI_INTERCEPT_REACT


func _physics_process(delta: float) -> void:
	if FootballConstants.DEBUG_DISABLE_OPPONENT:
		var dm := _motor()
		if dm != null:
			dm.set_move_intent(Vector3.ZERO)
		return

	if not ball or not is_instance_valid(ball):
		return

	if is_in_group("fallen"):
		return

	if wants_to_tackle:
		return

	if _intercepting:
		_intercept_react_left -= delta
		if _intercept_react_left > 0.0:
			return  # задержка реакции — фора игроку
		var caught: bool = ball.has_method(&"set_dribbler") and ball.dribbler == self
		var arrived := global_position.distance_to(_intercept_point) < 1.0
		if caught or arrived:
			_intercepting = false
		else:
			var dir := (_intercept_point - global_position)
			dir.y = 0.0
			var m := _motor()
			if m != null:
				m.set_move_intent(dir.normalized(), _base_scale())
			return

	if FootballConstants.DEBUG_MARK_TEAMMATE:
		# DEBUG-режим: не гоняемся за мячом/воротами — только держим тиммейта под опекой.
		# Перехват (выше) и подкат (ниже) остаются живыми — это и есть предмет теста.
		_mark(delta)
	elif _is_dribbling():
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


## DEBUG-маркировка: встаём между мячом и тиммейтом (в линию паса) на DEBUG_MARK_DISTANCE,
## чтобы честный перехват и подкат реально срабатывали при пасе на этого тиммейта.
func _mark(delta: float) -> void:
	if mark_target == null or not is_instance_valid(mark_target):
		_wander(delta)
		return
	var tpos := mark_target.global_position
	var to_ball := ball.global_position - tpos
	to_ball.y = 0.0
	var off: Vector3
	if to_ball.length() > 0.1:
		off = to_ball.normalized() * FootballConstants.DEBUG_MARK_DISTANCE
	else:
		off = Vector3(0, 0, FootballConstants.DEBUG_MARK_DISTANCE)  # мяч у ног тиммейта → чуть в сторону наших ворот (+Z)
	var target := tpos + off
	target.y = global_position.y
	var dir := (target - global_position)
	dir.y = 0.0
	_move_or_wander(dir, delta)


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

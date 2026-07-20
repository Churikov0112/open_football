extends Brain

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

var _gng_timer: float = 0.0
var _gng_lateral_sign: float = 1.0

## Менеджер зовёт это на партнёре, которому летит пас: перейти в режим выхода на приём.
func begin_receiving(pass_dir: Vector3, lead: float) -> void:
	_role = Role.RECEIVING
	_pass_dir = pass_dir
	_pass_lead = lead

func end_receiving() -> void:
	if _role == Role.RECEIVING:
		_role = Role.SUPPORT


## Отдавший «стенку» переходит в атакующий рывок (спринт вперёд-в-сторону от принимающего),
## предлагая себя под возврат в течение PASS_WALL_WINDOW секунд.
func begin_give_and_go(receiver_pos: Vector3) -> void:
	_body.add_to_group("giving_run")
	_gng_timer = FootballConstants.PASS_WALL_WINDOW
	# сторона рывка — противоположная принимающему (разводим фланги)
	_gng_lateral_sign = -1.0 if receiver_pos.x >= _body.global_position.x else 1.0


func _base_scale() -> float:
	return speed / FootballConstants.LOCO_TOP_SPEED

## Направление атаки нашей команды (team_1 атакует −Z в 1-м тайме). Одно место — готово к
## half-time-свапу (полная централизация на менеджерский _attack_dir_z — отдельная задача).
func _attack_dir() -> Vector3:
	return Vector3(0, 0, -1)

## Владеет ли мячом НАША команда (кто-то из team_1 — дриблер): тогда предлагаем себя под пас,
## а не бежим в мяч.
func _team_has_ball() -> bool:
	return ball.has_method(&"set_dribbler") and ball.dribbler != null and ball.dribbler.is_in_group("team_1")


func _physics_process(delta: float) -> void:
	if not ball or not is_instance_valid(ball):
		return

	if _body.is_in_group("fallen"):
		return

	if _body.is_in_group("giving_run"):
		_gng_timer -= delta
		var got_ball: bool = ball.has_method(&"set_dribbler") and ball.dribbler == _body
		if _gng_timer <= 0.0 or got_ball or _role == Role.RECEIVING:
			_body.remove_from_group("giving_run")
			_role = Role.SUPPORT
		else:
			var attack := _attack_dir()  # атакуем к −Z (через хелпер — готово к half-time)
			var target := _body.global_position + attack * FootballConstants.PASS_WALL_RUN_FORWARD \
				+ Vector3(_gng_lateral_sign * FootballConstants.PASS_WALL_RUN_LATERAL, 0, 0)
			target.x = clamp(target.x, -field_width + 4, field_width - 4)
			target.z = clamp(target.z, -field_length + 4, field_length - 4)
			var dir := (target - _body.global_position)
			dir.y = 0.0
			# Единственное исключение из «ИИ не спринтует» — телеграфируемый рывок.
			_drive(dir.normalized(), FootballConstants.LOCO_SPRINT_SPEED / FootballConstants.LOCO_TOP_SPEED)
			return

	# If human controls this player → skip
	if controlled_player == _body:
		return

	match _role:
		Role.RECEIVING:
			_move_to_receive(delta)
			return
		_:
			# Наша команда владеет мячом → предлагаем себя под пас (позиция поддержки), НЕ бежим в
			# мяч. К мячу идём только когда он ничейный/в борьбе (никто из наших не владеет).
			if _team_has_ball():
				_position_for_pass(delta)
			else:
				_chase_ball(delta)


func _position_for_pass(delta: float) -> void:
	# Носитель — фактический дриблер нашей команды (человек или второй игрок), не обязательно
	# управляемый. Встаём впереди носителя по атаке + сбоку на пас-дистанции — предлагаем себя
	# (сам оффсет и есть расстановка: не липнем к носителю).
	var carrier: Node3D = ball.dribbler if _team_has_ball() else controlled_player
	var carrier_pos := carrier.global_position
	var side_sign := 1.0 if carrier_pos.x < 0 else -1.0
	var target := carrier_pos + _attack_dir() * 10.0 + Vector3(side_sign * 6.0, 0, 0)

	target.x = clamp(target.x, -field_width + 4, field_width - 4)
	target.z = clamp(target.z, -field_length + 4, field_length - 4)
	target.y = _body.global_position.y

	var dir := (target - _body.global_position).normalized()
	dir.y = 0.0
	_move_or_wander(dir, delta)


## Выход на приём: в ноги — к предсказанной точке мяча; на ход — вперёд по вектору паса.
func _move_to_receive(delta: float) -> void:
	var target: Vector3
	if _pass_lead > 0.0:
		target = _body.global_position + _pass_dir.normalized() * _pass_lead
	else:
		target = PassSystem.receive_point(_body.global_position, ball.global_position, ball.linear_velocity,
			FootballConstants.PASS_RECEIVE_LEAD_TIME, FootballConstants.PASS_RECEIVE_ONLINE_DOT)
	target.y = _body.global_position.y
	var dir := (target - _body.global_position)
	dir.y = 0.0
	# Приём завершён, когда мяч у нас — вернёт менеджер через end_receiving(); тут просто бежим.
	_move_or_wander(dir.normalized(), delta)


func _chase_ball(delta: float) -> void:
	var target := ball.global_position
	target.y = _body.global_position.y

	var dir := (target - _body.global_position).normalized()
	dir.y = 0.0
	_move_or_wander(dir, delta)


func _move_or_wander(dir: Vector3, delta: float) -> void:
	if dir.length() > 0.1:
		_drive(dir, _base_scale())
	else:
		_wander(delta)


func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(0.5, 1.5)
	# Gentle sinusoidal movement for a natural idling look
	var wander_x := sin(Time.get_ticks_msec() * 0.001 + _body.global_position.z) * 0.5
	var wander_z := cos(Time.get_ticks_msec() * 0.001 + _body.global_position.x) * 0.5
	var wander_dir := Vector3(wander_x, 0, wander_z).normalized()
	_drive(wander_dir, _base_scale() * 0.3)

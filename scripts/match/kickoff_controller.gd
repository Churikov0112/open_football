extends Node
## Контроллер кикоффа (Этап 1 роадмапа). Автомат IDLE→SETUP→AIM→STRIKE. С первого дня читает
## только KickerIntent/SetPiecePresentation — прямых Input.* тут никогда не было. Бьющий —
## первый полевой бьющей команды; партнёр — второй полевой той же команды (единственный
## кандидат на приём паса). Математика — KickoffLogic + переиспользуемые FreeKickLogic/PassSystem.

signal struck

enum Phase { IDLE, SETUP, AIM, STRIKE }

var _manager: Node
var _ball: RigidBody3D
var _camera_pivot: Node3D
var _power_bar: ProgressBar

var _phase: int = Phase.IDLE
var _kicking_team: int = 1
var _kicker: CharacterBody3D
var _partner: CharacterBody3D
var _spot: Vector3 = Vector3.ZERO
var _base_heading: Vector3 = Vector3.FORWARD
var _heading: Vector3 = Vector3.FORWARD
var _attack_sign: float = -1.0
var _kicker_pos: Vector3 = Vector3.ZERO

var _charging: bool = false
var _charge: float = 0.0
var _pending_ratio: float = 1.0
var _locked: bool = false
var _contact_connected := false
var _intent: KickerIntent
var _presentation: SetPiecePresentation

func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar

func is_active() -> bool:
	return _phase != Phase.IDLE

## Владеет ли текущий источник камерой розыгрыша — match_manager проверяет это перед парковкой
## _kickoff_cam_pose (при Role.NONE, т.е. человек не участвует ни в одной роли, камера НЕ трогается).
func camera_is_owned() -> bool:
	return _presentation != null and _presentation.owns_camera()

## Human-дефолт источника намерения бьющего кикофф.
func _default_intent() -> KickerIntent:
	return HumanKickerIntent.new({
		"aim_lat": [&"move_left", &"move_right"],
		"charges": [[&"pass_short", 0]],
	})

## Старт кикоффа для kicking_team (1 или 2). intent/presentation опциональны — null → Human-дефолт
## + презентация роли KICKER (человек всегда бьющий по умолчанию, как и остальные пять стандартов).
func start(kicking_team: int, intent: KickerIntent = null, presentation: SetPiecePresentation = null) -> void:
	if _phase != Phase.IDLE:
		return
	_kicking_team = kicking_team
	_intent = intent if intent != null else _default_intent()
	_presentation = presentation if presentation != null else SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
	_setup()

func _setup() -> void:
	var kicking: Team = _manager._team_home if _kicking_team == 1 else _manager._team_away
	var defending: Team = _manager._team_away if _kicking_team == 1 else _manager._team_home
	var kicking_outfield: Array = kicking.outfield()
	if kicking_outfield.size() < 2:
		return   # некому пасовать — отменяем (симметрично throw_in's «некому вбрасывать»)
	_phase = Phase.SETUP
	_manager.set_kickoff_active(true)
	_manager.set_field_ai_active(false)
	_attack_sign = kicking.attack_z_sign
	var placement := KickoffLogic.kicker_placement(_attack_sign, FootballConstants.KICKOFF_KICKER_OFFSET, 0.5)
	_base_heading = placement["base_heading"]
	_kicker_pos = placement["pos"]
	_heading = _base_heading
	_spot = Vector3(0.0, FootballConstants.BALL_RADIUS, 0.0)
	if _ball.has_method(&"release_dribble"):
		_ball.release_dribble()
	if _ball.has_method(&"clear_last_kicker"):
		_ball.clear_last_kicker()
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = _spot
	_kicker = kicking_outfield[0]
	_partner = kicking_outfield[1]
	for body in kicking_outfield:
		if body == _kicker:
			continue
		_place_supporting(body, kicking.attack_z_sign, false)
	for body in defending.outfield():
		_place_supporting(body, defending.attack_z_sign, true)
	_place_kicker()
	# Управление кикером забираем ТОЛЬКО когда бьёт локальный человек (Role.KICKER). При ИИ-кикоффе
	# (Role.NONE) человек продолжает управлять своим полевым — иначе управление уходит на чужое тело.
	if _presentation.owns_hud():
		_manager.assign_controlled_player(_kicker)
	_charging = false
	_charge = 0.0
	_locked = false
	_update_camera_pose()
	_phase = Phase.AIM

## Полевой (кроме кикера): на home_pos, клэмп на свою половину; для не бьющей команды — ещё и
## вне центрального круга. Мотор залочен (весь розыгрыш заморожен одним разом — как у остальных
## пяти стандартов; продолжающийся per-frame enforcement не нужен).
func _place_supporting(body: CharacterBody3D, attack_sign: float, enforce_circle: bool) -> void:
	var pos: Vector3 = body.get_meta(&"home_pos", body.global_position)
	pos = KickoffLogic.clamp_to_own_half(pos, attack_sign, FootballConstants.KICKOFF_HALF_MARGIN)
	if enforce_circle:
		pos = FreeKickLogic.push_out_of_radius(pos, Vector3.ZERO, FootballConstants.CENTER_CIRCLE_RADIUS)
	pos.y = body.global_position.y
	body.global_position = pos
	var m := PlayerMotor.find_on(body)
	if m != null:
		m.set_control_locked(true)
		m.set_move_intent(Vector3.ZERO)

## Кикер — вплотную к мячу, смещён на ЧУЖУЮ половину (attack_sign-направление), лицом на свою
## половину (base_heading) — правило клэмпа/круга на него НЕ распространяется. Позиция/heading —
## из KickoffLogic.kicker_placement (см. _setup) — та же формула, что диспетчер уже использовал
## для построения AIKickoffIntent, кэширована в _kicker_pos, не пересчитывается заново.
func _place_kicker() -> void:
	_kicker.global_position = _kicker_pos
	_kicker.look_at(_kicker.global_position + _base_heading, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
		km.set_move_intent(Vector3.ZERO)
		km.set_face_direction(_base_heading)

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_pin_ball()
			_aim_update(delta)
		Phase.STRIKE:
			pass
	_update_camera_pose()

## Держим мяч на точке до удара (как у остальных стандартов с мячом в центре расстановки).
func _pin_ball() -> void:
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = _spot

func _aim_update(delta: float) -> void:
	var stick_x := _intent.aim_axis().x
	if not _locked:
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
				FootballConstants.KICKOFF_AIM_SPEED, delta, FootballConstants.KICKOFF_AIM_ARC)
		if _intent.charge_start_variant() >= 0:
			_start_charge()
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.KICKOFF_CHARGE_MAX_TIME, 0.0, 1.0)
		if _presentation.owns_hud():
			_power_bar.visible = true
			_power_bar.value = ratio
			var fill := _power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _intent.charge_committed():
			_fire_charge(ratio)

func _start_charge() -> void:
	_charging = true
	_locked = true
	_charge = 0.0

func _fire_charge(ratio: float) -> void:
	_charging = false
	if _presentation.owns_hud():
		_power_bar.visible = false
	_pending_ratio = ratio
	_begin_strike()

func _begin_strike() -> void:
	_phase = Phase.STRIKE
	var vis := _kicker_visual()
	if vis != null and not _contact_connected:
		vis.action_contact.connect(_on_kicker_contact, CONNECT_ONE_SHOT)
		_contact_connected = true
	if vis == null or not vis.trigger("pass"):
		_on_kicker_contact("pass")   # фолбэк без анимации — бьём сразу

func _on_kicker_contact(_action: String) -> void:
	_contact_connected = false
	var from: Vector3 = _ball.global_position
	var to: Vector3
	if is_instance_valid(_partner):
		to = Vector3(_partner.global_position.x, from.y, _partner.global_position.z)
	else:
		to = from + _heading * 10.0
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	var speed := PassSystem.ground_pass_speed(dist, _pending_ratio,
		FootballConstants.PASS_GROUND_MIN_TRAVEL_TIME, FootballConstants.PASS_GROUND_MAX_TRAVEL_TIME,
		FootballConstants.PASS_GROUND_MIN_SPEED, FootballConstants.PASS_GROUND_MAX_SPEED)
	var vel := PassSystem.launch_ground(from, to, speed)
	if _ball.has_method(&"launch"):
		_ball.launch(vel, true)
	if _ball.has_method(&"note_kicker"):
		_ball.note_kicker(_kicker)
	# Метка намеренного паса СВОЕЙ команды: кикофф-пас назад летит к своим воротам, и без метки
	# вратарь бьющей команды трактует его как удар в створ (выбегает и ныряет за мячом своих).
	# Вратаря СОПЕРНИКА метка не глушит (флаг != его группа).
	if _ball.has_method(&"note_pass_from"):
		_ball.note_pass_from(&"team_1" if _kicker.is_in_group("team_1") else &"team_2")
	struck.emit()
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(false)
	# Передача управления на партнёра + receive-assist — только при человеческом кикоффе (Role.KICKER).
	# При ИИ-кикоффе (Role.NONE) партнёр — красное тело, управлять им человек не должен.
	if _presentation.owns_hud():
		if is_instance_valid(_partner) and _manager.has_method(&"assign_controlled_player"):
			_manager.assign_controlled_player(_partner)
		_release()
		if is_instance_valid(_partner) and _manager.has_method(&"begin_pass_receive"):
			_manager.begin_pass_receive(_partner)
	else:
		_release()

func _release() -> void:
	if is_instance_valid(_kicker):
		var km := PlayerMotor.find_on(_kicker)
		if km != null:
			km.set_face_direction(Vector3.ZERO)
			km.set_control_locked(false)
	for body in _manager._team_home.outfield() + _manager._team_away.outfield():
		if body == _kicker:
			continue
		var m := PlayerMotor.find_on(body)
		if m != null:
			m.set_control_locked(false)
	if _manager.is_celebrating():
		_manager.set_field_ai_active(false)
	else:
		_manager.set_field_ai_active(true)
	_manager.set_kickoff_active(false)
	_phase = Phase.IDLE

func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	if not _presentation.owns_camera():
		return
	var eye := _spot - _heading * FootballConstants.KICKOFF_CAM_BACK + Vector3(0.0, FootballConstants.KICKOFF_CAM_HEIGHT, 0.0)
	var look := _spot + _heading * 4.0 + Vector3(0.0, FootballConstants.KICKOFF_CAM_LOOK_Y, 0.0)
	var t := Transform3D.IDENTITY
	t.origin = eye
	t = t.looking_at(look, Vector3.UP)
	_manager.set_kickoff_cam_pose(t)

func _kicker_visual() -> PlayerVisual:
	if _kicker == null:
		return null
	for c in _kicker.get_children():
		if c is PlayerVisual:
			return c
	return null

extends Node
## Контроллер удара от ворот (Фаза A). Автомат IDLE→SETUP→AIM→STRIKE. Бьющий — вратарь.
## Мяч в центре линии вратарской; A — наземный пас, B — навес; стик крутит направление вылета
## до самого контакта (камера фиксируется на коммите — финт). Соперники бьющей команды
## вытесняются из штрафной. Математика — GoalKickLogic + переиспользуемые PassSystem/KeeperLogic.

signal struck

enum Phase { IDLE, SETUP, AIM, STRIKE }

var _manager: Node
var _ball: RigidBody3D
var _camera_pivot: Node3D
var _power_bar: ProgressBar
var _keeper: CharacterBody3D
var _keeper_brain: Node

var _phase: int = Phase.IDLE
var _kicker: CharacterBody3D           # = вратарь
var _opp_group: StringName = &"team_1"  # группа соперников бьющей команды (расчистка штрафной)
var _goal_line_z: float = 0.0
var _into: float = 1.0
var _spot: Vector3 = Vector3.ZERO
var _forward: Vector3 = Vector3.FORWARD     # вверх поля от линии ворот (направление разбега)
var _base_heading: Vector3 = Vector3.FORWARD
var _heading: Vector3 = Vector3.FORWARD     # направление вылета мяча (крутится стиком до контакта)
var _cam_heading: Vector3 = Vector3.FORWARD # направление камеры (замирает на коммите)
var _foot: String = "penalty_r"

var _charging: bool = false
var _charge: float = 0.0
var _charge_kind: String = ""          # "ground" (A) / "lob" (B)
var _pending_ratio: float = 1.0
var _pending_kind: String = ""
var _locked: bool = false              # коммит нажат (камера зафиксирована)
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

## Старт удара от ворот: бьющий = вратарь, его ворота = goal_line_z.
func start(kicker: CharacterBody3D, goal_line_z: float, intent: KickerIntent = null, presentation: SetPiecePresentation = null) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_keeper = kicker   # удар от ворот бьёт САМ вратарь (не защищающийся)
	_keeper_brain = kicker.brain() if kicker != null and kicker.has_method(&"brain") else null
	_goal_line_z = goal_line_z
	_into = -signf(goal_line_z)   # в поле от линии ворот
	_foot = FootballConstants.GK_DEFAULT_FOOT
	_intent = intent if intent != null else _default_intent()
	_presentation = presentation if presentation != null else SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
	# Соперники бьющей команды (по группе бьющего) — общее правило, без хардкода.
	_opp_group = &"team_2" if kicker.is_in_group("team_1") else &"team_1"
	_setup()

## Human-дефолт источника намерения бьющего удар от ворот (прежние Input-чтения контроллера).
func _default_intent() -> KickerIntent:
	return HumanKickerIntent.new({
		"aim_lat": [&"move_left", &"move_right"],
		"foot": [&"foot_left", &"foot_right"],
		"charges": [[&"pass_short", 0], [&"pass_lob", 1]],   # 0 = ground, 1 = lob
	})

func _setup() -> void:
	_phase = Phase.SETUP
	_manager.set_goal_kick_active(true)
	_manager.set_field_ai_active(false)
	# Точка мяча — центр линии вратарской; направление разбега/прицела — вверх поля.
	_spot = GoalKickLogic.spot_position(_goal_line_z, _into, FootballConstants.GOAL_AREA_DEPTH, FootballConstants.BALL_RADIUS)
	_base_heading = Vector3(0.0, 0.0, _into).normalized()
	_heading = _base_heading
	_cam_heading = _base_heading
	_forward = _base_heading
	# Мяч на точку.
	if _ball.has_method(&"release_dribble"):
		_ball.release_dribble()
	if _ball.has_method(&"clear_last_kicker"):
		_ball.clear_last_kicker()
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = _spot
	# Вратарь — в пассивный режим бьущего (чистит состояние, отпускает мяч, глушит свою логику).
	if _keeper_brain != null and _keeper_brain.has_method(&"set_goalkick_mode"):
		_keeper_brain.set_goalkick_mode(true)
	# Расстановка вратаря за мячом на разбег, лицом вверх поля.
	_place_kicker()
	# Чистый idle (на случай, если вратарь был в другой позе).
	var kvis := _kicker_visual()
	if kvis != null:
		kvis.cancel_action()
		kvis.recover()
	# Правило: соперники бьющей команды — вне штрафной у goal_line_z.
	_clear_opponent_box()
	# Правило: НИКОГО (даже своей команды), кроме вратаря, — во вратарской ±5м.
	_clear_goal_area_buffer()
	_charging = false
	_charge = 0.0
	_locked = false
	_update_camera_pose()
	_phase = Phase.AIM

## Расстановка вратаря позади мяча на разбег, мотор залочен, лицом по _forward.
func _place_kicker() -> void:
	_kicker.global_position = GoalKickLogic.runup_placement(_spot, _forward,
		FootballConstants.GK_RUNUP_DIST, FootballConstants.GK_FOOT_LATERAL, _foot, 0.5)
	_kicker.look_at(_kicker.global_position + _forward, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
		km.set_move_intent(Vector3.ZERO)
		km.set_face_direction(_forward)

func _set_foot(f: String) -> void:
	if f == _foot:
		return
	_foot = f
	_place_kicker()

## Все полевые соперники бьющей команды внутри штрафной у goal_line_z — за 16.5-линию.
func _clear_opponent_box() -> void:
	for n in _manager.get_tree().get_nodes_in_group(_opp_group):
		if not is_instance_valid(n) or n == _keeper or not (n is Node3D):
			continue
		var adjusted := GoalKickLogic.push_out_of_penalty_area(n.global_position, _goal_line_z, _into,
			FootballConstants.PENALTY_AREA_DEPTH, FootballConstants.PENALTY_AREA_WIDTH * 0.5,
			FootballConstants.GK_ENCROACH_MARGIN)
		if not adjusted.is_equal_approx(n.global_position):
			n.global_position = adjusted
		var m := PlayerMotor.find_on(n)
		if m != null:
			m.set_control_locked(true)
			m.set_move_intent(Vector3.ZERO)

## Никто (ОБЕ команды, включая свою же), кроме вратаря, не должен стоять во вратарской площади
## ±GK_CLEAR_MARGIN. Отдельно от _clear_opponent_box (та трогает только соперников и на полную
## штрафную) — это узкая зона вокруг самих ворот, но касается ВСЕХ полевых без исключения.
func _clear_goal_area_buffer() -> void:
	var bodies := _manager.get_tree().get_nodes_in_group(&"team_1")
	bodies += _manager.get_tree().get_nodes_in_group(&"team_2")
	for n in bodies:
		if not is_instance_valid(n) or n == _keeper or not (n is Node3D):
			continue
		var adjusted := GoalKickLogic.push_out_of_goal_area(n.global_position, _goal_line_z, _into,
			FootballConstants.GOAL_AREA_DEPTH, FootballConstants.GOAL_AREA_WIDTH * 0.5,
			FootballConstants.GK_CLEAR_MARGIN)
		if not adjusted.is_equal_approx(n.global_position):
			n.global_position = adjusted
		var m := PlayerMotor.find_on(n)
		if m != null:
			m.set_control_locked(true)
			m.set_move_intent(Vector3.ZERO)

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_pin_ball()
			_aim_update(delta)
		Phase.STRIKE:
			_strike_update(delta)
	_update_camera_pose()

## Держим мяч на точке до удара (иначе остаточная скорость укатит драгом). Снимается в STRIKE.
func _pin_ball() -> void:
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = _spot

func _aim_update(delta: float) -> void:
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога определяется выбранным бьющим).
	var fs := _intent.foot_switch()
	if fs == -1:
		_set_foot("penalty_l")
	elif fs == 1:
		_set_foot("penalty_r")
	var stick_x := _intent.aim_axis().x
	# Стик крутит направление вылета мяча — и до, и после коммита (доводка/финт).
	if absf(stick_x) > 0.15:
		_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
			FootballConstants.GK_AIM_SPEED, delta, FootballConstants.GK_AIM_ARC)
	if not _locked:
		_cam_heading = _heading   # камера едет за прицелом только до коммита
		var v := _intent.charge_start_variant()
		if v == 0:
			_start_charge("ground")
		elif v == 1:
			_start_charge("lob")
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.GK_CHARGE_MAX_TIME, 0.0, 1.0)
		if _presentation.owns_hud():
			_power_bar.visible = true
			_power_bar.value = ratio
			var fill := _power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _intent.charge_committed():
			_fire_charge(ratio)

## Коммит: фиксируем камеру (_locked), копим силу. _heading продолжает крутиться до контакта.
func _start_charge(kind: String) -> void:
	_charging = true
	_locked = true
	_charge = 0.0
	_charge_kind = kind

func _fire_charge(ratio: float) -> void:
	_charging = false
	if _presentation.owns_hud():
		_power_bar.visible = false
	_pending_ratio = ratio
	_begin_strike(_charge_kind)

## Запуск разбега: лочим мотор, играем клип ноги, ждём action_contact.
func _begin_strike(kind: String) -> void:
	_pending_kind = kind
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
	_phase = Phase.STRIKE
	var vis := _kicker_visual()
	if vis != null and not _contact_connected:
		vis.action_contact.connect(_on_kicker_contact, CONNECT_ONE_SHOT)
		_contact_connected = true
	if vis == null or not vis.trigger(_foot):
		_on_kicker_contact("penalty")   # фолбэк без анимации — бьём сразу

func _strike_update(delta: float) -> void:
	# Доводка продолжается на разбеге вплоть до контакта.
	var stick_x := _intent.aim_axis().x
	if absf(stick_x) > 0.15:
		_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
			FootballConstants.GK_AIM_SPEED, delta, FootballConstants.GK_AIM_ARC)
	var vis := _kicker_visual()
	if vis == null:
		return
	var advance: float = vis.consume_root_motion()
	if advance > 0.0:
		_kicker.global_position += _forward * advance

func _on_kicker_contact(_action: String) -> void:
	_contact_connected = false
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var from: Vector3 = _ball.global_position
	var flat := Vector3(_heading.x, 0.0, _heading.z).normalized()
	if _pending_kind == "ground":
		# Наземный пас: дальность по заряду вдоль прицела; скорость выведена из дистанции.
		var land_dist := lerpf(FootballConstants.GK_GROUND_MIN_DIST, FootballConstants.GK_GROUND_MAX_DIST, _pending_ratio)
		var to := from + flat * land_dist
		to.y = from.y
		var speed := PassSystem.ground_pass_speed(land_dist, _pending_ratio,
			FootballConstants.PASS_GROUND_MIN_TRAVEL_TIME, FootballConstants.PASS_GROUND_MAX_TRAVEL_TIME,
			FootballConstants.PASS_GROUND_MIN_SPEED, FootballConstants.PASS_GROUND_MAX_SPEED)
		var vel := PassSystem.launch_ground(from, to, speed)
		if _ball.has_method(&"launch"):
			_ball.launch(vel, true)
	else:
		# Навес дугой: дальность и высота по заряду; горизонталь с поправкой на драг (иначе недолёт).
		var land_dist := lerpf(FootballConstants.GK_LOB_MIN_DIST, FootballConstants.GK_LOB_MAX_DIST, _pending_ratio)
		var peak := lerpf(FootballConstants.GK_LOB_PEAK_MIN, FootballConstants.GK_LOB_PEAK_MAX, _pending_ratio)
		var land := from + flat * land_dist
		land.y = FootballConstants.BALL_RADIUS
		var lob := PassSystem.launch_lob(from, land, peak, g)
		var vy: float = lob.y
		var flight_t: float = (2.0 * vy / g) if g > 0.01 else 0.0
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		var hspeed := KeeperLogic.drag_horizontal_speed(land_dist, flight_t, _ball.drag_factor, dt)
		var vel := flat * hspeed + Vector3.UP * vy
		if _ball.has_method(&"launch"):
			_ball.launch(vel, false)
	# Мяч лежал на точке (dribbler=null) → помечаем бьющего явно (анти-самоблок/кулдаун).
	if _ball.has_method(&"note_kicker"):
		_ball.note_kicker(_kicker)
	# Метка намеренного паса своей команды (розыгрыш от ворот — доставка своим).
	if _ball.has_method(&"note_pass_from"):
		_ball.note_pass_from(&"team_1" if _kicker.is_in_group("team_1") else &"team_2")
	struck.emit()
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(false)
	# Розыгрыш окончен — сразу в обычную игру. Управление НЕ передаём (остаётся у человека на team_1).
	_release()

func _release() -> void:
	if _keeper_brain != null and _keeper_brain.has_method(&"set_goalkick_mode"):
		_keeper_brain.set_goalkick_mode(false)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_face_direction(Vector3.ZERO)
		km.set_control_locked(false)
	# Гол с удара от ворот (напр. автогол) — заморозку празднования держит _celebrate_then_reset.
	if _manager.is_celebrating():
		_manager.set_field_ai_active(false)
	else:
		_manager.set_field_ai_active(true)
	_manager.set_goal_kick_active(false)
	_phase = Phase.IDLE

## Фикс-камера от 3-го лица за вратарём (за точкой вдоль -cam_heading), смотрит вверх поля.
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	if not _presentation.owns_camera():
		return
	var eye := _spot - _cam_heading * FootballConstants.GK_CAM_BACK + Vector3(0.0, FootballConstants.GK_CAM_HEIGHT, 0.0)
	var look := _spot + _cam_heading * 4.0 + Vector3(0.0, FootballConstants.GK_CAM_LOOK_Y, 0.0)
	var t := Transform3D.IDENTITY
	t.origin = eye
	t = t.looking_at(look, Vector3.UP)
	_manager.set_goal_kick_cam_pose(t)

func _kicker_visual() -> PlayerVisual:
	if _kicker == null:
		return null
	for c in _kicker.get_children():
		if c is PlayerVisual:
			return c
	return null

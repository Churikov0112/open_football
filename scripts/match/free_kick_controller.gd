extends Node
## Контроллер розыгрыша штрафного (Фаза A). Автомат SETUP→AIM→STRIKE→WATCH. Прицел направлением
## (heading), сила=высота, кручёный «доводом» стика до контакта. Математика — FreeKickLogic.
## Стенка/пас/навес наполняются в хуках ниже.

signal struck

enum Phase { IDLE, SETUP, AIM, STRIKE, WATCH }

var _manager: Node
var _ball: RigidBody3D
var _camera_pivot: Node3D
var _power_bar: ProgressBar
var _keeper: CharacterBody3D

var _phase: int = Phase.IDLE
var _kicker: CharacterBody3D
var _goal_line_z: float = 0.0
var _spot: Vector3 = Vector3.ZERO
var _base_heading: Vector3 = Vector3.FORWARD
var _heading: Vector3 = Vector3.FORWARD
var _foot: String = "penalty_r"

var _charging: bool = false
var _charge: float = 0.0
var _curl_accum: float = 0.0
var _locked: bool = false            # heading/камера зафиксированы (после нажатия kick)

var _fk_rng := RandomNumberGenerator.new()
var _pending_launch: Vector3 = Vector3.ZERO
var _pending_curl: Vector3 = Vector3.ZERO
var _contact_connected := false
var _watch_timer: float = 0.0

# Хуки-состояния для стенки/тиммейтов.
var _wall_bodies: Array = []
var _mates: Array = []
var _ball_in_flight_watch := false

func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar, keeper: CharacterBody3D) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar
	_keeper = keeper
	_fk_rng.randomize()

func is_active() -> bool:
	return _phase != Phase.IDLE

## Старт штрафного: точка = позиция бьющего (мяч телепортируется туда), ворота вратаря.
func start(kicker: CharacterBody3D, goal_line_z: float) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_foot = FootballConstants.FK_DEFAULT_FOOT
	_setup()

func _setup() -> void:
	_phase = Phase.SETUP
	_manager.set_free_kick_active(true)
	_manager.set_field_ai_active(false)
	# Точка удара = позиция бьющего (горизонталь), мяч кладём туда.
	_spot = Vector3(_kicker.global_position.x, FootballConstants.BALL_RADIUS, _kicker.global_position.z)
	var goal_center := Vector3(0.0, 0.0, _goal_line_z)
	_base_heading = FreeKickLogic.base_heading(_spot, goal_center)
	_heading = _base_heading
	# Мяч на точку.
	if _ball.has_method(&"release_dribble"):
		_ball.release_dribble()
	if _ball.has_method(&"clear_last_kicker"):
		_ball.clear_last_kicker()
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = _spot
	# Бьющий за мячом на длину разбега, лицом по heading; латеральный сдвиг под опорную ногу.
	var side := 1.0 if _foot == "penalty_r" else -1.0
	var right := _heading.cross(Vector3.UP).normalized()
	_kicker.global_position = _spot - _heading * FootballConstants.FK_RUNUP_DIST \
		+ right * (-side * FootballConstants.FK_FOOT_LATERAL) \
		+ Vector3(0.0, 0.5 - FootballConstants.BALL_RADIUS, 0.0)
	_kicker.look_at(_kicker.global_position + _heading, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
		km.set_move_intent(Vector3.ZERO)
		km.set_face_direction(_heading)
	# Вратарь: реактивный режим штрафного (позиция-якорь, сейв ВКЛ).
	if _keeper != null and _keeper.has_method(&"set_freekick_anchor"):
		var nf := FreeKickLogic.near_far_posts(_spot, 0.0, FootballConstants.GOAL_WIDTH * 0.5, _goal_line_z)
		var kpos := FreeKickLogic.keeper_position(_spot, nf[0], nf[1], FootballConstants.GOAL_WIDTH * 0.5,
			FootballConstants.FK_KEEPER_STEP_OUT, _goal_line_z, 0.5)
		_keeper.set_freekick_anchor(kpos)
	# Оборона (стенка) + атакующие (тиммейт/цели).
	_spawn_defense()
	_spawn_mates()
	_charging = false
	_charge = 0.0
	_curl_accum = 0.0
	_locked = false
	_ball_in_flight_watch = false
	_update_camera_pose()
	_phase = Phase.AIM

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_aim_update(delta)
		Phase.STRIKE:
			_strike_update(delta)
			_update_wall_jumps(delta)
		Phase.WATCH:
			_update_wall_jumps(delta)
			_watch_timer -= delta
			if _watch_timer <= 0.0:
				_release()
	_update_camera_pose()

func _aim_update(delta: float) -> void:
	var stick_x := Input.get_axis(&"move_left", &"move_right")
	# До нажатия kick: стик крутит heading (камера едет). После нажатия: heading зафиксирован,
	# боковой ввод копится в закрутку.
	if not _locked:
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
				FootballConstants.FK_AIM_SPEED, delta, FootballConstants.FK_AIM_ARC)
			var km := PlayerMotor.find_on(_kicker)
			if km != null:
				km.set_face_direction(_heading)
		# Пас/навес доступны до нажатия удара.
		if Input.is_action_just_pressed(&"pass_short"):
			_fire_pass("pass_short", 1.0); return
		if Input.is_action_just_pressed(&"pass_through"):
			_fire_pass("pass_through", 1.0); return
		if Input.is_action_just_pressed(&"pass_lob"):
			_fire_pass("pass_lob", 1.0); return
	# Заряд удара.
	if Input.is_action_just_pressed(&"kick"):
		_charging = true
		_locked = true            # фиксируем heading и камеру
		_charge = 0.0
		_curl_accum = 0.0
	if _charging:
		_charge += delta
		_curl_accum += Input.get_axis(&"move_left", &"move_right") * delta   # копим боковой ввод → curl
		var ratio := clampf(_charge / FootballConstants.FK_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or Input.is_action_just_released(&"kick"):
			_fire_shot(ratio)

func _fire_shot(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	var vel := FreeKickLogic.launch_velocity(_heading, ratio,
		FootballConstants.FK_POWER_MIN_SPEED, FootballConstants.FK_POWER_MAX_SPEED,
		FootballConstants.FK_ELEV_MIN, FootballConstants.FK_ELEV_MAX)
	var spread := FreeKickLogic.scatter_degrees(ratio, FootballConstants.FK_SPREAD_MIN_DEG, FootballConstants.FK_SPREAD_MAX_DEG)
	vel = FreeKickLogic.apply_scatter(vel, spread, _fk_rng)
	_pending_launch = vel
	_pending_curl = FreeKickLogic.curl_from_stick(_curl_accum, FootballConstants.FK_CURL_SCALE, FootballConstants.FK_CURL_MAX)
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

func _strike_update(_delta: float) -> void:
	var vis := _kicker_visual()
	if vis == null:
		return
	var advance: float = vis.consume_root_motion()
	if advance > 0.0:
		_kicker.global_position += _heading * advance

func _on_kicker_contact(_action: String) -> void:
	_contact_connected = false
	if _pending_curl.length_squared() > 0.0001:
		if _ball.has_method(&"launch_curl"):
			_ball.launch_curl(_pending_launch, _pending_curl, false)
	else:
		if _ball.has_method(&"launch"):
			_ball.launch(_pending_launch, false)
	_ball_in_flight_watch = true      # включаем наблюдение за прыжком стенки
	struck.emit()
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(false)
	_phase = Phase.WATCH
	_watch_timer = FootballConstants.FK_WATCH_TIME

func _release() -> void:
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_face_direction(Vector3.ZERO)
		km.set_control_locked(false)
	if _keeper != null and _keeper.has_method(&"clear_freekick_anchor"):
		_keeper.clear_freekick_anchor()
	_convert_bodies()                 # стенка/тиммейты → обычный ИИ
	_manager.set_field_ai_active(true)
	_manager.set_free_kick_active(false)
	_phase = Phase.IDLE

func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	var eye := _spot - _heading * FootballConstants.FK_CAM_BACK + Vector3(0.0, FootballConstants.FK_CAM_HEIGHT, 0.0)
	var look := _spot + _heading * 4.0 + Vector3(0.0, FootballConstants.FK_CAM_LOOK_Y, 0.0)
	var t := Transform3D.IDENTITY
	t.origin = eye
	t = t.looking_at(look, Vector3.UP)
	_manager.set_free_kick_cam_pose(t)

func _kicker_visual() -> PlayerVisual:
	if _kicker == null:
		return null
	for c in _kicker.get_children():
		if c is PlayerVisual:
			return c
	return null

# ── Хуки (наполняются в следующих задачах) ────────────────────────────────────
func _spawn_defense() -> void:
	pass   # Task 7

func _spawn_mates() -> void:
	pass   # Task 9

func _update_wall_jumps(_delta: float) -> void:
	pass   # Task 7

func _convert_bodies() -> void:
	pass   # Tasks 7, 9

func _fire_pass(_action: String, _ratio: float) -> void:
	pass   # Task 9

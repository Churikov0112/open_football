extends Node
## Базовый контроллер ОДНОГО пенальти (Фаза A). Автомат SETUP→AIM→STRIKE; на ударе испускает
## `struck` и при release_after_strike отдаёт мяч в обычную игру. Математика — PenaltyLogic.

signal struck

enum Phase { IDLE, SETUP, AIM, STRIKE }

var release_after_strike: bool = true

var _manager: Node
var _ball: RigidBody3D
var _camera_pivot: Node3D
var _power_bar: ProgressBar
var _keeper: CharacterBody3D

var _phase: int = Phase.IDLE
var _kicker: CharacterBody3D
var _goal_line_z: float = 0.0
var _into: float = 1.0
var _forward: Vector3 = Vector3.FORWARD   # горизонталь от точки к воротам
var _spot: Vector3 = Vector3.ZERO

var _foot: String = "penalty_r"            # нога удара (ключ ACTION_CLIPS)
var _aim: Vector2 = Vector2.ZERO            # точка прицела на плоскости ворот (x от центра, y высота)
var _charge: float = 0.0
var _charging: bool = false
var _chip: bool = false
var _reticle_visible: bool = true          # future: скрыть для честной игры за вратаря (Фаза B)

var _pen_rng := RandomNumberGenerator.new()
var _reticle: MeshInstance3D
var _pending_launch: Vector3 = Vector3.ZERO
var _struck_zone: int = -1
var _contact_connected := false

func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar, keeper: CharacterBody3D) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar
	_keeper = keeper
	_pen_rng.randomize()
	_build_reticle()

## Старт одиночного пенальти в атакуемые ворота (goal_line_z вратаря).
func start_single(kicker: CharacterBody3D, goal_line_z: float) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -1.0 if goal_line_z > 0.0 else 1.0
	_foot = FootballConstants.PEN_DEFAULT_FOOT
	release_after_strike = true
	_setup()

func _setup() -> void:
	_phase = Phase.SETUP
	_manager.set_penalty_active(true)
	_manager.set_field_ai_active(false)
	# Точка пенальти и вектор к воротам.
	_spot = Vector3(0.0, FootballConstants.BALL_RADIUS, _goal_line_z + _into * FootballConstants.PENALTY_SPOT_DIST)
	_forward = Vector3(0.0, 0.0, -_into)   # от точки к воротам (goal_line_z по -_into от точки)
	# Мяч на точку.
	if _ball.has_method(&"release_dribble"):
		_ball.release_dribble()
	if _ball.has_method(&"clear_last_kicker"):
		_ball.clear_last_kicker()
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = _spot
	# Бьющий за мячом (в сторону от ворот) на длину разбега, лицом к воротам; в обычном idle.
	# Латеральный сдвиг под опорную ногу: правая нога → чуть ЛЕВЕЕ (от камеры), левая → зеркально.
	# «Лево» игрока при взгляде на ворота = -_into по X.
	var side := -_into if _foot == "penalty_r" else _into
	_kicker.global_position = _spot - _forward * FootballConstants.PEN_RUNUP_DIST \
		+ Vector3(side * FootballConstants.PEN_FOOT_LATERAL, 0.5 - FootballConstants.BALL_RADIUS, 0.0)
	_kicker.look_at(_kicker.global_position + _forward, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		# Лочим (гасит остаточную скорость бега сразу — иначе тело дрейфует и мотор доворачивает
		# корпус по вектору движения) и жёстко смотрим на ворота через set_face_direction.
		km.set_control_locked(true)
		km.set_move_intent(Vector3.ZERO)
		km.set_face_direction(_forward)
	# Вратарь: пенальти-режим (центр, keeper_idle, реактивный сейв off).
	if _keeper != null and _keeper.has_method(&"set_penalty_mode"):
		_keeper.set_penalty_mode(true)
	# Прицел в центр створа.
	_aim = Vector2(0.0, FootballConstants.PEN_RETICLE_START_Y)
	_charge = 0.0
	_charging = false
	_chip = false
	_struck_zone = -1
	_update_camera_pose()
	_phase = Phase.AIM

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_aim_update(delta)
		Phase.STRIKE:
			_strike_update(delta)
	_update_reticle()
	_update_camera_pose()

func _aim_update(delta: float) -> void:
	# Прицел стиком/стрелками: X = ширина, вверх стика = выше в воротах (инвертируем Y).
	var aim_stick := Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		-Input.get_axis(&"move_forward", &"move_back"))
	if aim_stick.length() > 0.15:
		_aim = PenaltyLogic.move_reticle(_aim, aim_stick, FootballConstants.PEN_RETICLE_SPEED, delta,
			FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.GOAL_HEIGHT, FootballConstants.PEN_AIM_OVERHANG)
	else:
		# Нет ввода — метка плавно, но быстро возвращается в центр створа.
		var center := Vector2(0.0, FootballConstants.PEN_RETICLE_START_Y)
		_aim = _aim.lerp(center, clampf(FootballConstants.PEN_RETICLE_RETURN * delta, 0.0, 1.0))
	# Заряд силы: удержание kick; черпачок — combo_modifier + kick.
	if Input.is_action_just_pressed(&"kick"):
		_charging = true
		_charge = 0.0
		_chip = Input.is_action_pressed(&"combo_modifier")
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.PEN_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or Input.is_action_just_released(&"kick"):
			_fire(ratio)

func _fire(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	var from: Vector3 = _ball.global_position
	# Итоговая точка = прицел + случай внутри круга разброса.
	var spread := PenaltyLogic.spread_radius(ratio, FootballConstants.PEN_SPREAD_MIN_R, FootballConstants.PEN_SPREAD_MAX_R)
	var sampled := PenaltyLogic.sample_in_disc(_aim, spread, _pen_rng)
	var target := PenaltyLogic.plane_point_to_world(sampled, 0.0, _goal_line_z)
	var g := _ball_gravity()
	if _chip:
		var peak := lerpf(FootballConstants.PEN_CHIP_PEAK_MIN, FootballConstants.PEN_CHIP_PEAK_MAX, ratio)
		# Приземление НЕ на линии, а ЗА ней (в сетке) на уровне газона — тогда на плоскости ворот мяч
		# ещё в воздухе с ходом (уверенно залетает, а не падает у линии и закатывается). X — по прицелу.
		var land := Vector3(target.x, FootballConstants.BALL_RADIUS, _goal_line_z - _into * FootballConstants.PEN_CHIP_OVERSHOOT)
		# Баллистика launch_lob не учитывает драг мяча — за ~1.4с высокой дуги он съедает горизонталь
		# и черпачок не долетает. Берём вертикаль из launch_lob, а горизонталь считаем с поправкой на
		# драг (как вратарский навес), чтобы дуга реально доставала до точки приземления.
		var lob := PassSystem.launch_lob(from, land, peak, g)
		var vy: float = lob.y
		var flight_t: float = (2.0 * vy / g) if g > 0.01 else 0.0
		var flat := Vector2(land.x - from.x, land.z - from.z)
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		var hspeed := KeeperLogic.drag_horizontal_speed(flat.length(), flight_t, _ball.drag_factor, dt)
		var hdir := Vector3(flat.x, 0.0, flat.y).normalized() if flat.length() > 0.001 else _forward
		_pending_launch = hdir * hspeed + Vector3.UP * vy
	else:
		var speed := PenaltyLogic.power_speed(ratio, FootballConstants.PEN_POWER_MIN_SPEED, FootballConstants.PEN_POWER_MAX_SPEED)
		_pending_launch = ShotSystem.ballistic_to(from, target, speed, g)
	# Зона вратаря выбирается вслепую заранее, коммитим на контакте.
	_struck_zone = PenaltyLogic.random_dive_zone(_pen_rng)
	# Запускаем клип удара (root motion) и ждём action_contact.
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)  # телом на разбеге владеет root motion (мотор не мешает)
	_phase = Phase.STRIKE
	var vis := _kicker_visual()
	if vis != null and not _contact_connected:
		vis.action_contact.connect(_on_kicker_contact, CONNECT_ONE_SHOT)
		_contact_connected = true
	if vis == null or not vis.trigger(_foot):
		_on_kicker_contact("penalty")  # фолбэк без анимации — бьём сразу

func _strike_update(_delta: float) -> void:
	# Root-motion разбег: двигаем тело бьющего к воротам на продвижение корня за кадр.
	var vis := _kicker_visual()
	if vis == null:
		return
	var advance: float = vis.consume_root_motion()
	if advance > 0.0:
		_kicker.global_position += _forward * advance

func _on_kicker_contact(_action: String) -> void:
	_contact_connected = false
	if _ball.has_method(&"launch"):
		_ball.launch(_pending_launch, false)
	if _keeper != null and _keeper.has_method(&"begin_penalty_dive"):
		_keeper.begin_penalty_dive(_struck_zone)
	struck.emit()
	if release_after_strike:
		_release()

## Отдать управление в обычную игру: снять пенальти-режим, вернуть камеру/ИИ, разлочить бьющего.
func _release() -> void:
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_face_direction(Vector3.ZERO)   # снова доворот по вектору движения (обычная игра)
		km.set_control_locked(false)
	_manager.set_field_ai_active(true)
	_manager.set_penalty_active(false)
	if _reticle != null:
		_reticle.visible = false
	_phase = Phase.IDLE

func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	# Фикс-камера за бьющим (за точкой, в сторону от ворот), смотрит в ворота.
	var eye := _spot - _forward * FootballConstants.PEN_CAM_BACK + Vector3(0.0, FootballConstants.PEN_CAM_HEIGHT, 0.0)
	var look := Vector3(0.0, FootballConstants.PEN_CAM_LOOK_Y, _goal_line_z)
	var t := Transform3D.IDENTITY
	t.origin = eye
	t = t.looking_at(look, Vector3.UP)
	_manager.set_penalty_cam_pose(t)

func _build_reticle() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.28
	mesh.outer_radius = 0.35
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.1)  # жёлтое кольцо
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mesh.material = mat
	_reticle = MeshInstance3D.new()
	_reticle.name = "PenaltyReticle"
	_reticle.mesh = mesh
	_reticle.rotation.x = deg_to_rad(90)  # тор в плоскости ворот (лицом к камере/полю)
	_reticle.visible = false
	add_child(_reticle)

func _update_reticle() -> void:
	if _reticle == null:
		return
	var show_it := _phase == Phase.AIM and _reticle_visible
	_reticle.visible = show_it
	if not show_it:
		return
	_reticle.global_position = PenaltyLogic.plane_point_to_world(_aim, 0.0, _goal_line_z)
	var ratio := clampf(_charge / FootballConstants.PEN_CHARGE_MAX_TIME, 0.0, 1.0) if _charging else 0.0
	var r := PenaltyLogic.spread_radius(ratio, FootballConstants.PEN_SPREAD_MIN_R, FootballConstants.PEN_SPREAD_MAX_R)
	var s := maxf(0.3, r / 0.35)
	_reticle.scale = Vector3(s, 1.0, s)

func _kicker_visual() -> PlayerVisual:
	if _kicker == null:
		return null
	for c in _kicker.get_children():
		if c is PlayerVisual:
			return c
	return null

func _ball_gravity() -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return g * _ball.gravity_scale

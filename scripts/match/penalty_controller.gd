extends Node
## Базовый контроллер ОДНОГО пенальти (Фаза A). Автомат SETUP→AIM→STRIKE; на ударе испускает
## `struck` и при release_after_strike отдаёт мяч в обычную игру. Математика — PenaltyLogic.

signal struck

enum Phase { IDLE, SETUP, AIM, STRIKE, WATCH }

var release_after_strike: bool = true

var _manager: Node
var _ball: RigidBody3D
var _camera_pivot: Node3D
var _power_bar: ProgressBar
var _keeper: CharacterBody3D
var _keeper_brain: Node

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
var _watch_timer: float = 0.0
var _intent: KickerIntent
var _presentation: SetPiecePresentation
var _keeper_intent: KeeperIntent
var _keeper_marker: MeshInstance3D

func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar, keeper: CharacterBody3D) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar
	_keeper = keeper
	_keeper_brain = keeper.brain() if keeper != null and keeper.has_method(&"brain") else null
	_pen_rng.randomize()
	_build_reticle()
	_build_keeper_marker()
	_presentation = SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)

## Локальный человек сейчас играет бьющего (а не вратаря/наблюдателя)? Для match_manager —
## скрывать ли маркер controlled_player на время розыгрыша (K: бьющий — ИИ, маркер над ним лишний).
func kicker_is_local_human() -> bool:
	return _presentation != null and _presentation.owns_hud()

## Human-дефолт источника намерения пенальти-бьющего (ровно прежние Input-чтения контроллера).
func _default_intent() -> KickerIntent:
	return HumanKickerIntent.new({
		"aim_lat": [&"move_left", &"move_right"],
		"aim_vert": [&"move_forward", &"move_back"],
		"foot": [&"foot_left", &"foot_right"],
		"charges": [[&"kick", 0]],
		"modifier": &"combo_modifier",
	})

## Старт одиночного пенальти в атакуемые ворота (goal_line_z вратаря).
func start_single(kicker: CharacterBody3D, goal_line_z: float, intent: KickerIntent = null, presentation: SetPiecePresentation = null, keeper_intent: KeeperIntent = null) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -1.0 if goal_line_z > 0.0 else 1.0
	_foot = FootballConstants.PEN_DEFAULT_FOOT
	release_after_strike = true
	_intent = intent if intent != null else _default_intent()   # свежий intent на каждый пенальти (латч сброшен)
	if presentation != null:
		_presentation = presentation
	_keeper_intent = keeper_intent if keeper_intent != null else AIKeeperIntent.new(_pen_rng)   # дефолт = слепой ИИ (поведение P)
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
	_place_kicker()
	# Вратарь: пенальти-режим (центр, keeper_idle, реактивный сейв off).
	if _keeper_brain != null and _keeper_brain.has_method(&"set_penalty_mode"):
		_keeper_brain.set_penalty_mode(true)
	# Правило: все, кроме бьющего и вратаря, — за мяч и вне штрафной (радиус 9.15 м от точки).
	_clear_box()
	# Прицел в центр створа.
	_aim = Vector2(0.0, FootballConstants.PEN_RETICLE_START_Y)
	_charge = 0.0
	_charging = false
	_chip = false
	_struck_zone = -1
	_update_camera_pose()
	_phase = Phase.AIM

## Расстановка бьющего за мячом лицом к воротам, латеральный сдвиг под опорную ногу.
## Латеральный сдвиг под опорную ногу: правая нога → чуть ЛЕВЕЕ (от камеры), левая → зеркально.
## «Лево» игрока при взгляде на ворота = -_into по X.
func _place_kicker() -> void:
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

## Очистить штрафную: все полевые (обе команды), кроме бьющего и вратаря, отходят ЗА мяч
## (дальше от ворот) и за радиус 9.15 м от точки — по правилу их до удара не должно быть в
## штрафной/дуге. Поле-ИИ уже заморожен (set_field_ai_active(false)), так что стоят где поставили.
func _clear_box() -> void:
	var bodies := _manager.get_tree().get_nodes_in_group("team_1")
	bodies += _manager.get_tree().get_nodes_in_group("team_2")
	var behind := -_forward   # от ворот в поле (за мяч)
	var right := _forward.cross(Vector3.UP).normalized()
	var i := 0
	for n in bodies:
		if not is_instance_valid(n) or n == _kicker or n == _keeper or not (n is Node3D):
			continue
		var lateral := (float(i) - 0.5) * 5.0   # разнести вбок, чтобы не стояли стопкой
		var pos: Vector3 = _spot + behind * FootballConstants.FK_WALL_DIST + right * lateral
		pos.y = n.global_position.y
		n.global_position = pos
		var m := PlayerMotor.find_on(n)
		if m != null:
			m.set_control_locked(true)
			m.set_move_intent(Vector3.ZERO)
		i += 1

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_aim_update(delta)
		Phase.STRIKE:
			_strike_update(delta)
		Phase.WATCH:
			# Держим пенальти-вид ещё PEN_WATCH_TIME после удара (смотрим исход), затем возвращаем игру.
			_watch_timer -= delta
			if _watch_timer <= 0.0:
				_release()
	_update_reticle()
	_update_keeper_marker()
	_update_camera_pose()

func _aim_update(delta: float) -> void:
	# Позиционирование вратаря телом (K): человек стиком водит вратаря по линии; ИИ step_lateral()=0 → стоит.
	if _keeper_brain != null and _keeper_brain.has_method(&"set_penalty_step"):
		_keeper_brain.set_penalty_step(_keeper_intent.step_lateral())
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога определяется выбранным бьющим).
	var fs := _intent.foot_switch()
	if fs == -1 and _foot != "penalty_l":
		_foot = "penalty_l"
		_place_kicker()
	elif fs == 1 and _foot != "penalty_r":
		_foot = "penalty_r"
		_place_kicker()
	# Прицел: ИИ — фиксированная цель сразу; человек — стик/стрелки (интеграция + возврат к центру).
	if _intent.has_fixed_aim():
		_aim = _intent.aim_target()
	else:
		var aim_stick := _intent.aim_axis()
		if aim_stick.length() > 0.15:
			_aim = PenaltyLogic.move_reticle(_aim, aim_stick, FootballConstants.PEN_RETICLE_SPEED, delta,
				FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.GOAL_HEIGHT, FootballConstants.PEN_AIM_OVERHANG)
		else:
			# Нет ввода — метка плавно, но быстро возвращается в центр створа.
			var center := Vector2(0.0, FootballConstants.PEN_RETICLE_START_Y)
			_aim = _aim.lerp(center, clampf(FootballConstants.PEN_RETICLE_RETURN * delta, 0.0, 1.0))
	# Заряд силы: удержание kick; черпачок — combo_modifier + kick.
	if _intent.charge_start_variant() >= 0:
		_charging = true
		_charge = 0.0
		_chip = _intent.modifier_held()
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.PEN_CHARGE_MAX_TIME, 0.0, 1.0)
		if _presentation.owns_hud():
			_power_bar.visible = true
			_power_bar.value = ratio
			var fill := _power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _intent.charge_committed():
			_fire(ratio)

func _fire(ratio: float) -> void:
	_charging = false
	# Старт разбега бьющего: фиксируем X вратаря на линии (дальше стик = направление прыжка, на контакте).
	if _keeper_brain != null and _keeper_brain.has_method(&"freeze_penalty_position"):
		_keeper_brain.freeze_penalty_position()
	if _presentation.owns_hud():
		_power_bar.visible = false
	var from: Vector3 = _ball.global_position
	# Итоговая точка = прицел + случай внутри круга разброса.
	var spread := PenaltyLogic.spread_radius(ratio, FootballConstants.PEN_SPREAD_MIN_R, FootballConstants.PEN_SPREAD_MAX_R)
	var sampled := PenaltyLogic.sample_in_disc(_aim, spread, _pen_rng)
	var target := PenaltyLogic.plane_point_to_world(sampled, 0.0, _goal_line_z)
	var g := _ball_gravity()
	if _chip:
		# Сила задаёт дальность приземления (недолёт/в ворота/перелёт → промахнуться можно). Направление
		# по прицелу (target на линии), точка приземления — вдоль него на chip_dist от мяча, на газоне.
		var peak := lerpf(FootballConstants.PEN_CHIP_PEAK_MIN, FootballConstants.PEN_CHIP_PEAK_MAX, ratio)
		var chip_dist := lerpf(FootballConstants.PEN_CHIP_DIST_MIN, FootballConstants.PEN_CHIP_DIST_MAX, ratio)
		var chip_dir := Vector3(target.x - from.x, 0.0, target.z - from.z)
		chip_dir = chip_dir.normalized() if chip_dir.length() > 0.001 else _forward
		var land := from + chip_dir * chip_dist
		land.y = FootballConstants.BALL_RADIUS
		# launch_lob не учитывает драг мяча — берём из неё вертикаль, а горизонталь с поправкой на драг.
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
	# Мяч лежал на точке (dribbler=null) → launch пометил last_kicker=null. Помечаем бьющего явно
	# (анти-самоблок/кулдаун) — иначе бьющий мог бы блокировать/трогать собственный удар.
	if _ball.has_method(&"note_kicker"):
		_ball.note_kicker(_kicker)
	_struck_zone = _keeper_intent.dive_zone()   # срез зоны в момент удара (человек-вратарь мог крутить до последнего)
	if _keeper_brain != null and _keeper_brain.has_method(&"begin_penalty_dive"):
		_keeper_brain.begin_penalty_dive(_struck_zone)
	struck.emit()
	if release_after_strike:
		# Не переключаем камеру сразу (иначе рывок на самом ударе) — держим пенальти-вид PEN_WATCH_TIME,
		# затем _release. Разбег/root motion уже не двигаем: тело разлочим, чтоб не стояло вкопанным.
		var km := PlayerMotor.find_on(_kicker)
		if km != null:
			km.set_control_locked(false)
		_phase = Phase.WATCH
		_watch_timer = FootballConstants.PEN_WATCH_TIME

## Отдать управление в обычную игру: снять пенальти-режим, вернуть камеру/ИИ, разлочить бьющего.
func _release() -> void:
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_face_direction(Vector3.ZERO)   # снова доворот по вектору движения (обычная игра)
		km.set_control_locked(false)
	# Гол с пенальти: НЕ размораживаем поле-ИИ — заморозку празднования держит и снимает
	# _celebrate_then_reset (как при обычном голе с игры). Иначе игроки бегут к мячу посреди
	# празднования. Пенальти новых тел не спавнит — достаточно просто не трогать заморозку.
	if not _manager.is_celebrating():
		_manager.set_field_ai_active(true)
	_manager.set_penalty_active(false)
	if _reticle != null:
		_reticle.visible = false
	_phase = Phase.IDLE

func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	if not _presentation.owns_camera():
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
	var show_it := _phase == Phase.AIM and _reticle_visible and _presentation.owns_hud()
	_reticle.visible = show_it
	if not show_it:
		return
	_reticle.global_position = PenaltyLogic.plane_point_to_world(_aim, 0.0, _goal_line_z)
	var ratio := clampf(_charge / FootballConstants.PEN_CHARGE_MAX_TIME, 0.0, 1.0) if _charging else 0.0
	var r := PenaltyLogic.spread_radius(ratio, FootballConstants.PEN_SPREAD_MIN_R, FootballConstants.PEN_SPREAD_MAX_R)
	var s := maxf(0.3, r / 0.35)
	_reticle.scale = Vector3(s, 1.0, s)

## Cyan-маркер над вратарём (конус вершиной вниз) — показывается, когда локальный человек играет
## роль вратаря (K-тест). Строится один раз, позиционируется каждый кадр в _update_keeper_marker.
func _build_keeper_marker() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.12
	mesh.height = 0.22
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.9, 1.0)   # cyan (как маркер управляемого игрока)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mesh.material = mat
	_keeper_marker = MeshInstance3D.new()
	_keeper_marker.name = "KeeperMarker"
	_keeper_marker.mesh = mesh
	_keeper_marker.rotation.z = PI   # вершина вниз (указывает на вратаря)
	_keeper_marker.visible = false
	add_child(_keeper_marker)

## Позиция/видимость cyan-маркера вратаря: над головой _keeper, пока роль локального человека = KEEPER.
func _update_keeper_marker() -> void:
	if _keeper_marker == null:
		return
	var show_it := _phase != Phase.IDLE and _keeper != null and _presentation.owns_keeper_marker()
	_keeper_marker.visible = show_it
	if show_it:
		_keeper_marker.global_position = _keeper.global_position + Vector3(0.0, 2.3, 0.0)

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

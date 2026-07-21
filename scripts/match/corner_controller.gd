extends Node
## Контроллер розыгрыша углового (Фаза A). Автомат SETUP→AIM→STRIKE. Прицел heading (стик-X),
## высота навеса (стик-Y до нажатия B), заряд (A наземный пас / B навес), закрутка стиком на
## разбеге. Математика — CornerLogic + переиспользуемые FreeKickLogic/PassSystem/KeeperLogic.

signal struck

enum Phase { IDLE, SETUP, AIM, STRIKE }

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
var _side: float = 1.0
var _spot: Vector3 = Vector3.ZERO
var _base_heading: Vector3 = Vector3.FORWARD
var _heading: Vector3 = Vector3.FORWARD
var _foot: String = "penalty_r"
var _peak_height: float = 7.0        # высота дуги навеса (стик-Y), фиксируется при нажатии B

var _charging: bool = false
var _charge: float = 0.0
var _charge_kind: String = ""        # "ground" (A) / "lob" (B)
var _curl_accum: float = 0.0
var _locked: bool = false

var _pending_kind: String = ""
var _pending_ratio: float = 1.0
var _contact_connected := false

var _cn_rng := RandomNumberGenerator.new()
var _spawned: Array = []             # [{body, team_group}]
var _short_mate: CharacterBody3D     # партнёр под короткую опцию (RB)
var _short_called: bool = false
var _short_target: Vector3 = Vector3.ZERO

func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar, keeper: CharacterBody3D) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar
	_keeper = keeper
	_keeper_brain = keeper.brain() if keeper != null and keeper.has_method(&"brain") else null
	_cn_rng.randomize()

func is_active() -> bool:
	return _phase != Phase.IDLE

## Старт углового: сторона по X игрока в момент вызова; ворота вратаря (goal_line_z).
func start(kicker: CharacterBody3D, goal_line_z: float) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -signf(goal_line_z)
	_side = CornerLogic.side_for_player(kicker.global_position.x)
	_foot = CornerLogic.foot_for_side(_side)
	_setup()

func _setup() -> void:
	_phase = Phase.SETUP
	_cleanup_spawned()
	_manager.set_corner_active(true)
	_manager.set_field_ai_active(false)
	_spot = CornerLogic.corner_spot(_side, FootballConstants.HALF_FIELD_WIDTH, _goal_line_z,
		FootballConstants.CORNER_INSET, FootballConstants.BALL_RADIUS)
	var goal_center := Vector3(0.0, 0.0, _goal_line_z)
	_base_heading = FreeKickLogic.base_heading(_spot, goal_center)
	_heading = _base_heading
	# Мяч в угол.
	if _ball.has_method(&"release_dribble"):
		_ball.release_dribble()
	if _ball.has_method(&"clear_last_kicker"):
		_ball.clear_last_kicker()
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = _spot
	_place_kicker()
	# Бьющий в чистый idle.
	var kvis := _kicker_visual()
	if kvis != null:
		kvis.cancel_action()
		kvis.recover()
	# Вратарь: якорь у створа (реактивная ловля/дайв уже работают).
	if _keeper_brain != null and _keeper_brain.has_method(&"set_freekick_anchor"):
		_keeper_brain.set_freekick_anchor(Vector3(0.0, 0.5, _goal_line_z + _into * FootballConstants.FK_KEEPER_STEP_OUT))
	_spawn_targets()
	_spawn_defenders()
	_peak_height = FootballConstants.CORNER_LOB_PEAK_STANDARD
	_charging = false
	_charge = 0.0
	_curl_accum = 0.0
	_locked = false
	_short_called = false
	_update_camera_pose()
	_phase = Phase.AIM

## Расстановка бьющего за мячом вдоль -base_heading, латеральный сдвиг под опорную ногу.
func _place_kicker() -> void:
	var side_sign := 1.0 if _foot == "penalty_r" else -1.0
	var right := _base_heading.cross(Vector3.UP).normalized()
	_kicker.global_position = _spot - _base_heading * FootballConstants.CORNER_RUNUP_DIST \
		+ right * (-side_sign * FootballConstants.CORNER_FOOT_LATERAL) \
		+ Vector3(0.0, 0.5 - FootballConstants.BALL_RADIUS, 0.0)
	_kicker.look_at(_kicker.global_position + _base_heading, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
		km.set_move_intent(Vector3.ZERO)
		km.set_face_direction(_base_heading)

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_aim_update(delta)
		Phase.STRIKE:
			_strike_update(delta)
	_update_camera_pose()

func _aim_update(delta: float) -> void:
	var stick_x := Input.get_axis(&"move_left", &"move_right")
	var stick_y := -Input.get_axis(&"move_forward", &"move_back")
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога от выбранного бьющего).
	if Input.is_action_just_pressed(&"foot_left"):
		_set_foot("penalty_l")
	elif Input.is_action_just_pressed(&"foot_right"):
		_set_foot("penalty_r")
	# RB — позвать ближайшего партнёра на короткую опцию.
	if Input.is_action_just_pressed(&"corner_call"):
		_call_short_mate()
	_drive_short_mate(delta)
	if not _locked:
		# Стик-X крутит heading (камера едет). Стик-Y задаёт высоту навеса (до нажатия B).
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
				FootballConstants.CORNER_AIM_SPEED, delta, FootballConstants.CORNER_AIM_ARC)
		_peak_height = CornerLogic.peak_for_stick_y(stick_y, FootballConstants.CORNER_LOB_PEAK_HEAD,
			FootballConstants.CORNER_LOB_PEAK_STANDARD, FootballConstants.CORNER_LOB_PEAK_SVECHA)
		# A = наземный пас, B = навес.
		if Input.is_action_just_pressed(&"pass_short"):
			_start_charge("ground")
		elif Input.is_action_just_pressed(&"pass_lob"):
			_start_charge("lob")
	if _charging:
		_charge += delta
		if _charge_kind == "lob":
			_curl_accum += stick_x * delta   # закрутка копится только для навеса
		var ratio := clampf(_charge / FootballConstants.CORNER_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _charge_released():
			_fire_charge(ratio)

func _set_foot(f: String) -> void:
	if f == _foot:
		return
	_foot = f
	_place_kicker()

func _charge_released() -> bool:
	if _charge_kind == "lob":
		return not Input.is_action_pressed(&"pass_lob")
	return not Input.is_action_pressed(&"pass_short")

func _start_charge(kind: String) -> void:
	_charging = true
	_locked = true
	_charge = 0.0
	_curl_accum = 0.0
	_charge_kind = kind

func _fire_charge(ratio: float) -> void:
	_charging = false
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
		_on_kicker_contact("penalty")   # фолбэк без анимации

func _strike_update(delta: float) -> void:
	if _pending_kind == "lob":
		_curl_accum += Input.get_axis(&"move_left", &"move_right") * delta
	var vis := _kicker_visual()
	if vis == null:
		return
	var advance: float = vis.consume_root_motion()
	if advance > 0.0:
		_kicker.global_position += _base_heading * advance

func _on_kicker_contact(_action: String) -> void:
	_contact_connected = false
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var from: Vector3 = _ball.global_position
	var flat := Vector3(_heading.x, 0.0, _heading.z).normalized()
	var receiver: CharacterBody3D = _select_receiver()
	if _pending_kind == "ground":
		# Короткий наземный пас; сила = скорость (заряд).
		var speed := lerpf(FootballConstants.CORNER_PASS_MIN_SPEED, FootballConstants.CORNER_PASS_MAX_SPEED, _pending_ratio)
		var vel := PassSystem.launch_ground(from, from + flat, speed)
		if _ball.has_method(&"launch"):
			_ball.launch(vel, true)
	else:
		# Навес: точка приземления = позиция цели (или heading × дальность заряда, если цели нет).
		var land: Vector3
		if is_instance_valid(receiver):
			land = Vector3(receiver.global_position.x, FootballConstants.BALL_RADIUS, receiver.global_position.z)
		else:
			var land_dist := lerpf(FootballConstants.CORNER_LOB_MIN_DIST, FootballConstants.CORNER_LOB_MAX_DIST, _pending_ratio)
			land = from + flat * land_dist
			land.y = FootballConstants.BALL_RADIUS
		var to_land := Vector3(land.x - from.x, 0.0, land.z - from.z)
		var land_dist2 := to_land.length()
		var land_dir := to_land.normalized() if land_dist2 > 0.001 else flat
		# launch_lob не учитывает драг → берём вертикаль из неё, горизонталь с поправкой на драг.
		var lob := PassSystem.launch_lob(from, land, _peak_height, g)
		var vy: float = lob.y
		var flight_t: float = (2.0 * vy / g) if g > 0.01 else 0.0
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		var hspeed := KeeperLogic.drag_horizontal_speed(land_dist2, flight_t, _ball.drag_factor, dt)
		var vel := land_dir * hspeed + Vector3.UP * vy
		var curl := FreeKickLogic.curl_from_stick(_curl_accum, FootballConstants.CORNER_CURL_SCALE, FootballConstants.CORNER_CURL_MAX)
		if curl.length_squared() > 0.0001 and _ball.has_method(&"launch_curl"):
			_ball.launch_curl(vel, curl, false)
		elif _ball.has_method(&"launch"):
			_ball.launch(vel, false)
	struck.emit()
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(false)
	# Управление получателю ДО _release()/конверта тел (та же причина, что в FK).
	if is_instance_valid(receiver) and _manager.has_method(&"assign_controlled_player"):
		_manager.assign_controlled_player(receiver)
	_release(receiver)
	if is_instance_valid(receiver) and _manager.has_method(&"begin_pass_receive"):
		_manager.begin_pass_receive(receiver)

## Тиммейт-получатель: лучший по совпадению направления от мяча с heading (dot, порог).
func _select_receiver() -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_dot := 0.2
	var from: Vector3 = _ball.global_position
	var h := Vector3(_heading.x, 0.0, _heading.z).normalized()
	var candidates: Array = []
	for entry in _spawned:
		if entry["team_group"] == &"team_1":
			candidates.append(entry["body"])
	if is_instance_valid(_short_mate):
		candidates.append(_short_mate)
	for b in candidates:
		if not is_instance_valid(b):
			continue
		var d := Vector3(b.global_position.x - from.x, 0.0, b.global_position.z - from.z)
		if d.length() < 0.1:
			continue
		var dt := d.normalized().dot(h)
		if dt > best_dot:
			best_dot = dt
			best = b
	return best

# ── RB короткая опция ─────────────────────────────────────────────────────────
func _call_short_mate() -> void:
	if _short_called or not is_instance_valid(_short_mate):
		return
	_short_called = true
	_short_target = CornerLogic.short_option_pos(_spot, _side, _into, FootballConstants.CORNER_SHORT_DIST, 0.5)
	var pm := PlayerMotor.find_on(_short_mate)
	if pm != null:
		pm.set_control_locked(false)

func _drive_short_mate(_delta: float) -> void:
	if not _short_called or not is_instance_valid(_short_mate):
		return
	var pm := PlayerMotor.find_on(_short_mate)
	if pm == null:
		return
	var d := _short_target - _short_mate.global_position
	d.y = 0.0
	if d.length() > 0.8:
		pm.set_move_intent(d.normalized(), 1.0)
	else:
		pm.set_move_intent(Vector3.ZERO)

# ── Спавны ─────────────────────────────────────────────────────────────────────
func _spawn_targets() -> void:
	var positions := CornerLogic.box_target_positions(_goal_line_z, _into,
		FootballConstants.CORNER_TARGET_LATERAL, FootballConstants.CORNER_TARGET_DEPTH, 0.5)
	for pos in positions:
		_spawned.append({"body": _make_body(&"team_1", Color(0.1, 0.1, 0.9), pos), "team_group": &"team_1"})
	# Короткая опция — атакующий В ШТРАФНОЙ (у ближней штанги, на стороне угла), пока не позвали
	# RB — оттуда выбегает к бьющему (short_option_pos), а не наоборот.
	var short_pos := CornerLogic.short_mate_start_pos(_side, _goal_line_z, _into,
		FootballConstants.CORNER_SHORT_START_LATERAL, FootballConstants.CORNER_SHORT_START_DEPTH, 0.5)
	_short_mate = _make_body(&"team_1", Color(0.1, 0.1, 0.9), short_pos)
	_spawned.append({"body": _short_mate, "team_group": &"team_1"})

func _spawn_defenders() -> void:
	var into := _into
	for sx in [-1.0, 1.0]:
		var pos := Vector3(sx * FootballConstants.CORNER_TARGET_LATERAL * 0.7, 0.5,
			_goal_line_z + into * (FootballConstants.CORNER_TARGET_DEPTH - 3.0))
		_spawned.append({"body": _make_body(&"team_2", Color(0.9, 0.1, 0.1), pos), "team_group": &"team_2"})

func _make_body(team_group: StringName, color: Color, pos: Vector3) -> CharacterBody3D:
	var cfg := PlayerConfig.new()
	cfg.team_group = team_group
	cfg.role = PlayerConfig.Role.FWD if team_group == &"team_1" else PlayerConfig.Role.DEF
	cfg.kit_color = color
	cfg.spawn_pos = pos
	cfg.display_name = "CornerBody"
	cfg.control_mode = PlayerConfig.ControlMode.AI
	cfg.ai_script = null                 # без ИИ до _convert_bodies
	cfg.connect_action_signals = true
	var team_node: Team = _manager._team_home if team_group == &"team_1" else _manager._team_away
	var p := PlayerFactory.spawn(cfg, team_node)
	p.add_to_group("corner_spawned")
	var pm := PlayerMotor.find_on(p)
	if pm != null:
		pm.set_control_locked(true)
		pm.set_move_intent(Vector3.ZERO)
	return p

func _cleanup_spawned() -> void:
	for n in _manager.get_tree().get_nodes_in_group("corner_spawned"):
		if is_instance_valid(n) and n != _kicker:
			n.queue_free()
	_spawned.clear()
	_short_mate = null

## Только реальный получатель (если был) остаётся в матче — конвертируется в постоянного
## ИИ-тиммейта и снимается с группы corner_spawned (иначе следующий угловой его деспавнит или,
## если он же станет бьющим следующего углового, «застрянет» навсегда защищённым от очистки).
## Все остальные заспавненные тела (незадействованные цели/защитники) — деспавнятся сразу, иначе
## состав матча растёт без ограничения с каждым угловым.
func _convert_bodies(receiver: CharacterBody3D) -> void:
	var mate := preload("res://scripts/ai/teammate_ai.gd")
	for entry in _spawned:
		var b: CharacterBody3D = entry["body"]
		if not is_instance_valid(b):
			continue
		if b == receiver:
			b.remove_from_group("corner_spawned")
			var pm := PlayerMotor.find_on(b)
			if pm != null:
				pm.set_control_locked(false)
			var brain := mate.new()
			brain.name = "Brain"
			b.add_child(brain)
			brain.ball = _ball
			brain.controlled_player = _manager.controlled_player
		else:
			b.queue_free()

func _release(receiver: CharacterBody3D) -> void:
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_face_direction(Vector3.ZERO)
		km.set_control_locked(false)
	if _keeper_brain != null and _keeper_brain.has_method(&"clear_freekick_anchor"):
		_keeper_brain.clear_freekick_anchor()
	_convert_bodies(receiver)
	# Гол с углового: не размораживаем поле-ИИ (заморозку празднования снимет _celebrate_then_reset).
	if _manager.is_celebrating():
		_manager.set_field_ai_active(false)
	else:
		_manager.set_field_ai_active(true)
	_manager.set_corner_active(false)
	_phase = Phase.IDLE

## Фикс-камера от 3-го лица за бьющим (за углом, смотрит по heading). Держится только до контакта —
## на _release() _corner_active сбрасывается и обычная камера возвращается сама.
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	var eye := _spot - _heading * FootballConstants.CORNER_CAM_BACK + Vector3(0.0, FootballConstants.CORNER_CAM_HEIGHT, 0.0)
	var look := _spot + _heading * 4.0 + Vector3(0.0, FootballConstants.CORNER_CAM_LOOK_Y, 0.0)
	var t := Transform3D.IDENTITY
	t.origin = eye
	t = t.looking_at(look, Vector3.UP)
	_manager.set_corner_cam_pose(t)

func _kicker_visual() -> PlayerVisual:
	if _kicker == null:
		return null
	for c in _kicker.get_children():
		if c is PlayerVisual:
			return c
	return null

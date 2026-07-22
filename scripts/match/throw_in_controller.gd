extends Node
## Контроллер вброса из аута (Фаза A). Автомат IDLE→SETUP→AIM→STRIKE. Бьющий — ближайший к точке
## аута полевой игрок team_1. Мяч в руках; стик крутит направление+тело+камеру (сектор ±90° в
## поле); A задаёт силу; на 13/33 клипа мяч летит дугой. После выпуска управление — тому, кому
## летит мяч. Математика — ThrowInLogic + переиспользуемые FreeKickLogic/PassSystem/KeeperLogic.

signal struck

enum Phase { IDLE, SETUP, AIM, STRIKE }

var _manager: Node
var _ball: RigidBody3D
var _camera_pivot: Node3D
var _power_bar: ProgressBar

var _phase: int = Phase.IDLE
var _thrower: CharacterBody3D
var _opp_group: StringName = &"team_2"
var _spot: Vector3 = Vector3.ZERO           # точка вброса (на боковой линии)
var _into: Vector3 = Vector3.RIGHT          # перпендикуляр в поле (базовое направление)
var _heading: Vector3 = Vector3.RIGHT       # направление вылета (= тело = камера), кламп ±90°

var _charging: bool = false
var _charge: float = 0.0
var _pending_ratio: float = 1.0
var _locked: bool = false                   # A нажата (направление зафиксировано)
var _contact_connected := false

func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar

func is_active() -> bool:
	return _phase != Phase.IDLE

## Старт вброса: точка = проекция мяча на ближайшую боковую линию; бьющий = ближайший team_1.
func start() -> void:
	if _phase != Phase.IDLE:
		return
	_spot = ThrowInLogic.aut_point(_ball.global_position,
		FootballConstants.HALF_FIELD_WIDTH, FootballConstants.BALL_RADIUS)
	_into = ThrowInLogic.base_heading(_spot.x)
	_heading = _into
	_thrower = _nearest_team1(_spot, null)
	if _thrower == null:
		return   # некому вбрасывать — отменяем старт
	_opp_group = &"team_2" if _thrower.is_in_group("team_1") else &"team_1"
	_setup()

func _setup() -> void:
	_phase = Phase.SETUP
	_manager.set_throw_in_active(true)
	# Расстановка вбрасывающего за линией, лицом в поле, мотор залочен.
	_thrower.global_position = ThrowInLogic.thrower_placement(_spot, _into,
		FootballConstants.THROW_BEHIND_OFFSET, 0.5)
	_thrower.look_at(_thrower.global_position + _into, Vector3.UP)
	var tm := PlayerMotor.find_on(_thrower)
	if tm != null:
		tm.set_control_locked(true)
		tm.set_move_intent(Vector3.ZERO)
		tm.set_face_direction(_into)
	# Мяч в руки вбрасывающего (CAUGHT — приклеен к точке ПОСЕРЕДИНЕ между ладонями каждый кадр;
	# гол забить нельзя).
	var vis := _thrower_visual()
	if vis != null and _ball.has_method(&"catch"):
		var hold: Node3D = vis.get_two_hand_hold_attachment()
		if hold != null:
			if _ball.has_method(&"clear_last_kicker"):
				_ball.clear_last_kicker()
			_ball.catch(_thrower, hold)
	# Стойка замаха (первый кадр throw_in, заморожен).
	if vis != null:
		vis.hold_pose("throw_in")
	# Правило 2 м: соперники вбрасывающего не ближе THROW_ENCROACH_DIST к точке вброса.
	_clear_opponents_from_spot()
	# Управление — на вбрасывающего (человек драйвит прицел); полевой AI заморожен.
	_manager.assign_controlled_player(_thrower)
	_manager.set_field_ai_active(false)
	_charging = false
	_charge = 0.0
	_locked = false
	_update_camera_pose()
	_phase = Phase.AIM

## Ближайший к точке `to` полевой игрок team_1 (вратарь исключён по группе role_gk), кроме exclude.
func _nearest_team1(to: Vector3, exclude: Node) -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_d := INF
	for n in _manager.get_tree().get_nodes_in_group(&"team_1"):
		if not is_instance_valid(n) or n == exclude or n.is_in_group(&"role_gk") or not (n is CharacterBody3D):
			continue
		var d := Vector3(n.global_position.x - to.x, 0.0, n.global_position.z - to.z).length_squared()
		if d < best_d:
			best_d = d
			best = n
	return best

## Соперники вбрасывающего ближе THROW_ENCROACH_DIST к точке вброса — вытолкнуть + залочить мотор.
func _clear_opponents_from_spot() -> void:
	for n in _manager.get_tree().get_nodes_in_group(_opp_group):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var adjusted := FreeKickLogic.push_out_of_radius(n.global_position, _spot,
			FootballConstants.THROW_ENCROACH_DIST)
		if not adjusted.is_equal_approx(n.global_position):
			n.global_position = adjusted
		var m := PlayerMotor.find_on(n)
		if m != null:
			m.set_control_locked(true)
			m.set_move_intent(Vector3.ZERO)

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_aim_update(delta)
		Phase.STRIKE:
			pass
	_update_camera_pose()

func _aim_update(delta: float) -> void:
	if not _locked:
		var stick_x := Input.get_axis(&"move_left", &"move_right")
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _into, stick_x,
				FootballConstants.THROW_AIM_SPEED, delta, FootballConstants.THROW_AIM_ARC)
		# Тело доворачивается вместе с направлением.
		var tm := PlayerMotor.find_on(_thrower)
		if tm != null:
			tm.set_face_direction(_heading)
		if Input.is_action_just_pressed(&"pass_short"):
			_start_charge()
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.THROW_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or not Input.is_action_pressed(&"pass_short"):
			_fire_charge(ratio)

## Коммит: направление фиксируется, начинается набор силы.
func _start_charge() -> void:
	_charging = true
	_locked = true
	_charge = 0.0

func _fire_charge(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	_pending_ratio = ratio
	_begin_strike()

## Запуск клипа броска: снимаем стойку (trigger), ждём action_contact.
func _begin_strike() -> void:
	_phase = Phase.STRIKE
	var vis := _thrower_visual()
	if vis != null and not _contact_connected:
		vis.action_contact.connect(_on_thrower_contact, CONNECT_ONE_SHOT)
		_contact_connected = true
	if vis == null or not vis.trigger("throw_in"):
		_on_thrower_contact("throw_in")   # фолбэк без анимации — бросаем сразу

func _on_thrower_contact(_action: String) -> void:
	_contact_connected = false
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var from: Vector3 = _ball.global_position
	var flat := Vector3(_heading.x, 0.0, _heading.z).normalized()
	# Дуга: дальность и высота по заряду; горизонталь с поправкой на драг (иначе недолёт).
	var land_dist := lerpf(FootballConstants.THROW_MIN_DIST, FootballConstants.THROW_MAX_DIST, _pending_ratio)
	var peak := lerpf(FootballConstants.THROW_PEAK_MIN, FootballConstants.THROW_PEAK_MAX, _pending_ratio)
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
	# Мяч был CAUGHT (dribbler=вбрасывающий) → помечаем бьющего (анти-самоблок/кулдаун).
	if _ball.has_method(&"note_kicker"):
		_ball.note_kicker(_thrower)
	struck.emit()
	# Управление — тому, кому летит мяч (ближайший team_1 к приземлению, кроме вбрасывающего).
	var receiver := _nearest_team1(land, _thrower)
	if receiver != null:
		_manager.assign_controlled_player(receiver)
		if _manager.has_method(&"begin_pass_receive"):
			_manager.begin_pass_receive(receiver)
	_release()

func _release() -> void:
	var tm := PlayerMotor.find_on(_thrower)
	if tm != null:
		tm.set_face_direction(Vector3.ZERO)
		tm.set_control_locked(false)
	# Гол во время вброса (напр. рикошет) — заморозку празднования держит _celebrate_then_reset.
	if _manager.is_celebrating():
		_manager.set_field_ai_active(false)
	else:
		_manager.set_field_ai_active(true)
	_manager.set_throw_in_active(false)
	_phase = Phase.IDLE

## Фикс-камера 3-го лица за вбрасывающим (за точкой вдоль -heading), смотрит в поле.
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	var eye := _spot - _heading * FootballConstants.THROW_CAM_BACK + Vector3(0.0, FootballConstants.THROW_CAM_HEIGHT, 0.0)
	var look := _spot + _heading * FootballConstants.THROW_CAM_AHEAD + Vector3(0.0, FootballConstants.THROW_CAM_LOOK_Y, 0.0)
	var t := Transform3D.IDENTITY
	t.origin = eye
	t = t.looking_at(look, Vector3.UP)
	_manager.set_throw_in_cam_pose(t)

func _thrower_visual() -> PlayerVisual:
	if _thrower == null:
		return null
	for c in _thrower.get_children():
		if c is PlayerVisual:
			return c
	return null

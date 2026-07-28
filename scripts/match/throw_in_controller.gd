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
var _intent: KickerIntent
var _presentation: SetPiecePresentation
var _block_wall: StaticBody3D = null    # невидимая стена 2 м вокруг точки при живой защите
var _blocked_bodies: Array = []         # защитники, которым временно добавлен бит стены в mask

func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar

func is_active() -> bool:
	return _phase != Phase.IDLE

## Владеет ли источник камерой розыгрыша — match_manager проверяет перед парковкой (Role.NONE,
## ИИ-вброс: камера НЕ трогается, остаётся обычная ТВ/3-е лицо).
func camera_is_owned() -> bool:
	return _presentation != null and _presentation.owns_camera()

## Старт вброса: точка = проекция мяча на ближайшую боковую линию; бьющий = ближайший team_1.
func start(team: int = 1, intent: KickerIntent = null, presentation: SetPiecePresentation = null) -> void:
	if _phase != Phase.IDLE:
		return
	_intent = intent if intent != null else _default_intent()
	_presentation = presentation if presentation != null else SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
	_spot = ThrowInLogic.aut_point(_ball.global_position,
		FootballConstants.HALF_FIELD_WIDTH, FootballConstants.BALL_RADIUS)
	_into = ThrowInLogic.base_heading(_spot.x)
	_heading = _into
	var group: StringName = &"team_1" if team == 1 else &"team_2"
	_thrower = _nearest_teammate(_spot, group, null)
	if _thrower == null:
		return   # некому вбрасывать — отменяем старт
	_opp_group = &"team_2" if _thrower.is_in_group("team_1") else &"team_1"
	_setup()

## Human-дефолт источника намерения вбрасывающего (ровно прежние Input-чтения контроллера).
func _default_intent() -> KickerIntent:
	return HumanKickerIntent.new({
		"aim_lat": [&"move_left", &"move_right"],
		"charges": [[&"pass_short", 0]],
	})

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
	# Управление — вбрасывающему ТОЛЬКО когда бьёт человек (Role.NONE не отдаёт team_2-тело человеку).
	if _presentation.owns_hud():
		_manager.assign_controlled_player(_thrower)
	# Человек вбрасывает → морозим всё поле. ИИ-соперник → морозим только вбрасывающую команду,
	# защищающаяся (человек) играет; правило 2 м держит физическая стена (см. _build_block_wall).
	if _presentation.owns_camera():
		_manager.set_field_ai_active(false)
	else:
		var kicking_group: StringName = &"team_1" if _thrower.is_in_group("team_1") else &"team_2"
		_manager.set_field_ai_active(false, kicking_group)
		_build_block_wall()
	_charging = false
	_charge = 0.0
	_locked = false
	_update_camera_pose()
	_phase = Phase.AIM

## Ближайший к точке `to` полевой игрок team_1 (вратарь исключён по группе role_gk), кроме exclude.
func _nearest_teammate(to: Vector3, group: StringName, exclude: Node) -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_d := INF
	for n in _manager.get_tree().get_nodes_in_group(group):
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
		# Лочим соперника ТОЛЬКО при человеческом вбросе (соперники — ИИ). При ИИ-вбросе соперники —
		# команда человека: разово оттолкнули от точки, но НЕ лочим (правило 2 м держит стена).
		if _presentation != null and _presentation.owns_camera():
			var m := PlayerMotor.find_on(n)
			if m != null:
				m.set_control_locked(true)
				m.set_move_intent(Vector3.ZERO)

## Невидимая стена правила 2 м для живой защиты (ИИ-вброс): цилиндр радиуса THROW_ENCROACH_DIST
## вокруг точки на слое SETPIECE_BLOCK_LAYER, который слушают ТОЛЬКО защитники (временный бит в mask)
## — упираются и слайдят через move_and_slide, без телепорта. Мяч/вбрасывающая команда бита не имеют.
func _build_block_wall() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = FootballConstants.SETPIECE_BLOCK_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = FootballConstants.THROW_ENCROACH_DIST
	shape.height = 4.0
	col.shape = shape
	body.add_child(col)
	body.global_position = Vector3(_spot.x, 2.0, _spot.z)
	_manager.add_child(body)
	_block_wall = body
	_blocked_bodies.clear()
	for n in _manager.get_tree().get_nodes_in_group(_opp_group):
		if not is_instance_valid(n) or not (n is CollisionObject3D):
			continue
		(n as CollisionObject3D).collision_mask |= FootballConstants.SETPIECE_BLOCK_LAYER
		_blocked_bodies.append(n)

func _teardown_block_wall() -> void:
	for n in _blocked_bodies:
		if is_instance_valid(n) and n is CollisionObject3D:
			(n as CollisionObject3D).collision_mask &= ~FootballConstants.SETPIECE_BLOCK_LAYER
	_blocked_bodies.clear()
	if _block_wall != null and is_instance_valid(_block_wall):
		_block_wall.queue_free()
	_block_wall = null

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_aim_update(delta)
		Phase.STRIKE:
			pass
	_update_camera_pose()

func _aim_update(delta: float) -> void:
	if not _locked:
		var stick_x := _intent.aim_axis().x
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _into, stick_x,
				FootballConstants.THROW_AIM_SPEED, delta, FootballConstants.THROW_AIM_ARC)
		# Тело доворачивается вместе с направлением.
		var tm := PlayerMotor.find_on(_thrower)
		if tm != null:
			tm.set_face_direction(_heading)
		if _intent.charge_start_variant() >= 0:
			_start_charge()
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.THROW_CHARGE_MAX_TIME, 0.0, 1.0)
		if _presentation.owns_hud():
			_power_bar.visible = true
			_power_bar.value = ratio
			var fill := _power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _intent.charge_committed():
			_fire_charge(ratio)

## Коммит: направление фиксируется, начинается набор силы.
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
	# Метка намеренного паса своей команды: вброс от партнёра вратарю по правилам тоже нельзя
	# брать руками — и она же глушит сейв-рефлекс своего вратаря на вброс назад.
	if _ball.has_method(&"note_pass_from"):
		_ball.note_pass_from(&"team_1" if _thrower.is_in_group("team_1") else &"team_2")
	struck.emit()
	# Управление получателю — ТОЛЬКО при человеческом вбросе (Role.NONE не отдаёт красное тело).
	if _presentation.owns_hud():
		var recv_group: StringName = &"team_1" if _thrower.is_in_group("team_1") else &"team_2"
		var receiver := _nearest_teammate(land, recv_group, _thrower)
		if receiver != null:
			_manager.assign_controlled_player(receiver)
			if _manager.has_method(&"begin_pass_receive"):
				_manager.begin_pass_receive(receiver)
	_release()

func _release() -> void:
	_teardown_block_wall()
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
	if not _presentation.owns_camera():
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

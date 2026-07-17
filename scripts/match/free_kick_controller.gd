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
var _charge_kind: String = ""        # что заряжаем: "shot" / "ground" / "lob"
var _pending_ratio: float = 1.0      # заряд паса/навеса, применяется на контакте
var _curl_accum: float = 0.0
var _locked: bool = false            # heading/камера зафиксированы (после нажатия кнопки)

var _fk_rng := RandomNumberGenerator.new()
var _pending_kind: String = ""       # "shot" / "ground" / "lob" — что запускаем на контакте
var _pending_launch: Vector3 = Vector3.ZERO
var _pending_curl: Vector3 = Vector3.ZERO
var _contact_connected := false
var _watch_timer: float = 0.0

# Хуки-состояния для стенки/тиммейтов.
var _wall_bodies: Array = []
var _mates: Array = []
var _ball_in_flight_watch := false
var _watch_elapsed: float = 0.0
var _hidden_dummies: Array = []      # debug-болванки, спрятанные на время штрафного

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
	# Убираем тела, заспавненные ПРОШЛЫМ штрафным (иначе накапливаются, а их конвертированный
	# teammate_ai бежит к новому мячу и мешает бить). Бьющего не трогаем.
	_cleanup_spawned()
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
	var right := _base_heading.cross(Vector3.UP).normalized()
	_kicker.global_position = _spot - _base_heading * FootballConstants.FK_RUNUP_DIST \
		+ right * (-side * FootballConstants.FK_FOOT_LATERAL) \
		+ Vector3(0.0, 0.5 - FootballConstants.BALL_RADIUS, 0.0)
	_kicker.look_at(_kicker.global_position + _base_heading, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
		km.set_move_intent(Vector3.ZERO)
		km.set_face_direction(_base_heading)
	# Бьющий — в чистый idle: сбрасываем любое текущее действие/one-shot (если перед штрафным
	# делали что-то другое — подкат/пас/удар — иначе бьющий стоит в чужой позе до разбега).
	var kvis := _kicker_visual()
	if kvis != null:
		kvis.cancel_action()
		kvis.recover()
	# Вратарь: реактивный режим штрафного (позиция-якорь, сейв ВКЛ).
	if _keeper != null and _keeper.has_method(&"set_freekick_anchor"):
		var nf := FreeKickLogic.near_far_posts(_spot, 0.0, FootballConstants.GOAL_WIDTH * 0.5, _goal_line_z)
		var kpos := FreeKickLogic.keeper_position(_spot, nf[0], nf[1], FootballConstants.GOAL_WIDTH * 0.5,
			FootballConstants.FK_KEEPER_STEP_OUT, _goal_line_z, 0.5)
		_keeper.set_freekick_anchor(kpos)
	# Прячем debug-болванки стенки (тестовое scaffolding), чтобы не засоряли розыгрыш.
	_hide_debug_dummies()
	# Никто (свои/чужие, кроме бьющего и вратаря) не должен стоять в коридоре мяч→стенка —
	# расчищаем ДО спавна стенки/своих (сама стенка намеренно встаёт на этой линии).
	_clear_corridor()
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
			_watch_elapsed += delta
			# Ранний выход: мяч уже вышел в обычную игру (пас принят, перехват стенкой, ловля
			# вратарём — мяч не в FLIGHT) — снимаем лок камеры раньше таймера.
			var ball_live: bool = _watch_elapsed > 0.15 and _ball.has_method(&"is_flight") and not bool(_ball.is_flight())
			if ball_live or _watch_timer <= 0.0:
				_release()
	_update_camera_pose()

func _aim_update(delta: float) -> void:
	var stick_x := Input.get_axis(&"move_left", &"move_right")
	# До нажатия kick: стик крутит heading (камера едет). После нажатия: heading зафиксирован,
	# боковой ввод копится в закрутку.
	if not _locked:
		if absf(stick_x) > 0.15:
			# Крутим направление вылета (камеру). Бьющего НЕ доворачиваем — он смотрит на мяч
			# (_base_heading), чтобы разбег всегда шёл к мячу.
			_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
				FootballConstants.FK_AIM_SPEED, delta, FootballConstants.FK_AIM_ARC)
		# Старт заряда: удар / наземный пас / навес — все через удержание кнопки (сила растёт).
		if Input.is_action_just_pressed(&"kick"):
			_start_charge("shot")
		elif Input.is_action_just_pressed(&"pass_short") or Input.is_action_just_pressed(&"pass_through"):
			_start_charge("ground")
		elif Input.is_action_just_pressed(&"pass_lob"):
			_start_charge("lob")
	if _charging:
		_charge += delta
		if _charge_kind == "shot":
			_curl_accum += stick_x * delta   # закрутка копится только для удара
		var ratio := clampf(_charge / FootballConstants.FK_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _charge_released():
			_fire_charge(ratio)

## Старт заряда действия (удар/пас/навес): фиксируем heading/камеру, копим силу.
func _start_charge(kind: String) -> void:
	_charging = true
	_locked = true
	_charge = 0.0
	_curl_accum = 0.0
	_charge_kind = kind

## Кнопка текущего заряжаемого действия отпущена?
func _charge_released() -> bool:
	match _charge_kind:
		"shot":
			return not Input.is_action_pressed(&"kick")
		"lob":
			return not Input.is_action_pressed(&"pass_lob")
		_:
			return not (Input.is_action_pressed(&"pass_short") or Input.is_action_pressed(&"pass_through"))

## Отпустили (или макс. заряд): удар считает вектор сразу; пас/навес запоминают ratio до контакта.
func _fire_charge(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	if _charge_kind == "shot":
		_fire_shot(ratio)
	else:
		_pending_ratio = ratio
		_begin_strike(_charge_kind)

func _fire_shot(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	var vel := FreeKickLogic.launch_velocity(_heading, ratio,
		FootballConstants.FK_POWER_MIN_SPEED, FootballConstants.FK_POWER_MAX_SPEED,
		FootballConstants.FK_ELEV_MIN, FootballConstants.FK_ELEV_MAX)
	var spread := FreeKickLogic.scatter_degrees(ratio, FootballConstants.FK_SPREAD_MIN_DEG, FootballConstants.FK_SPREAD_MAX_DEG)
	vel = FreeKickLogic.apply_scatter(vel, spread, _fk_rng)
	vel = _apply_goal_magnet(vel)   # лёгкое подтягивание к воротам
	_pending_launch = vel
	# _pending_curl НЕ считаем здесь — стик ещё двигается во время разбега (_strike_update),
	# закрутка фиксируется на самом контакте (_on_kicker_contact), как и задумано.
	_begin_strike("shot")

## Общий запуск разбега: лочим мотор, играем клип ноги, ждём action_contact.
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

## Подмешивание направления на центр ворот к горизонтали удара (магнетизм).
func _apply_goal_magnet(vel: Vector3) -> Vector3:
	var from: Vector3 = _ball.global_position
	var to_goal := Vector3(0.0 - from.x, 0.0, _goal_line_z - from.z)
	if to_goal.length() < 0.5:
		return vel
	to_goal = to_goal.normalized()
	var h := Vector3(vel.x, 0.0, vel.z)
	var speed_h := h.length()
	if speed_h < 0.1:
		return vel
	var dir := h.normalized().lerp(to_goal, FootballConstants.FK_GOAL_MAGNET).normalized()
	return Vector3(dir.x * speed_h, vel.y, dir.z * speed_h)

func _strike_update(delta: float) -> void:
	# Закрутка копится ВСЮ дистанцию «нажатие kick → контакт», включая разбег — не только пока
	# держали кнопку. Раньше накопление останавливалось на _fire_shot (до разбега), из-за чего
	# закрутка ощущалась пропавшей — стик двигали именно во время бега к мячу.
	if _pending_kind == "shot":
		_curl_accum += Input.get_axis(&"move_left", &"move_right") * delta
	var vis := _kicker_visual()
	if vis == null:
		return
	var advance: float = vis.consume_root_motion()
	if advance > 0.0:
		# Разбег ВСЕГДА к мячу (фиксированный _base_heading), а не по камере (_heading задаёт
		# только направление вылета мяча). Иначе поворот камеры при прицеле уводил бьющего вбок.
		_kicker.global_position += _base_heading * advance

func _on_kicker_contact(_action: String) -> void:
	_contact_connected = false
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var from: Vector3 = _ball.global_position
	var flat := Vector3(_heading.x, 0.0, _heading.z).normalized()
	# Для паса/навеса заранее выбираем получателя (тиммейт по направлению паса) — до запуска мяча.
	var receiver: CharacterBody3D = _select_receiver() if _pending_kind != "shot" else null
	if _pending_kind == "shot":
		# Закрутка фиксируется здесь — на самом контакте, весь путь стика с момента нажатия учтён.
		_pending_curl = FreeKickLogic.curl_from_stick(_curl_accum, FootballConstants.FK_CURL_SCALE, FootballConstants.FK_CURL_MAX)
	match _pending_kind:
		"ground":
			# Наземный пас в направлении камеры (heading), настильно; сила = скорость (заряд).
			var speed := lerpf(FootballConstants.FK_PASS_MIN_SPEED, FootballConstants.FK_PASS_MAX_SPEED, _pending_ratio)
			var vel := PassSystem.launch_ground(from, from + flat, speed)
			if _ball.has_method(&"launch"):
				_ball.launch(vel, true)
		"lob":
			# Навес дугой в направлении камеры; сила = дальность приземления и высота дуги (заряд).
			var land_dist := lerpf(FootballConstants.FK_LOB_MIN_DIST, FootballConstants.FK_LOB_MAX_DIST, _pending_ratio)
			var peak := lerpf(FootballConstants.FK_LOB_PEAK_MIN, FootballConstants.FK_LOB_PEAK_MAX, _pending_ratio)
			var land := from + flat * land_dist
			land.y = FootballConstants.BALL_RADIUS
			# launch_lob не учитывает драг мяча → недолёт. Берём вертикаль из неё, а горизонталь —
			# с поправкой на драг (как черпачок пенальти), чтобы навес реально долетал до точки.
			var lob := PassSystem.launch_lob(from, land, peak, g)
			var vy: float = lob.y
			var flight_t: float = (2.0 * vy / g) if g > 0.01 else 0.0
			var dt := 1.0 / float(Engine.physics_ticks_per_second)
			var hspeed := KeeperLogic.drag_horizontal_speed(land_dist, flight_t, _ball.drag_factor, dt)
			var vel := flat * hspeed + Vector3.UP * vy
			if _ball.has_method(&"launch"):
				_ball.launch(vel, false)
		_:
			# Удар (прямой/кручёный) — вектор посчитан заранее в _fire_shot.
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
	if _pending_kind == "shot":
		# Удар — держим фикс-вид, смотрим полёт.
		_phase = Phase.WATCH
		_watch_timer = FootballConstants.FK_WATCH_TIME
		_watch_elapsed = 0.0
	else:
		# Пас/навес — розыгрыш окончен, сразу в обычную игру. Управление передаём тиммейту, в
		# которого шёл пас (играем за команду), чтобы человек вёл именно его к мячу.
		_release()
		if is_instance_valid(receiver):
			_manager.controlled_player = receiver
			for entry in _mates:
				var mb = entry["body"]
				if is_instance_valid(mb):
					mb.controlled_player = receiver

func _release() -> void:
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_face_direction(Vector3.ZERO)
		km.set_control_locked(false)
	if _keeper != null and _keeper.has_method(&"clear_freekick_anchor"):
		_keeper.clear_freekick_anchor()
	_convert_bodies()                 # стенка/тиммейты → обычный ИИ
	_restore_debug_dummies()          # возвращаем спрятанные debug-болванки
	_manager.set_field_ai_active(true)
	_manager.set_free_kick_active(false)
	_phase = Phase.IDLE

## Фикс-камера от 3-го лица за бьющим (за точкой, в сторону от направления удара), смотрит по
## heading. До нажатия kick — «едет» вслед за прицелом (heading меняется в _aim_update). После
## нажатия heading фиксируется (_locked) — камера естественно замирает («лок» после удара),
## без отдельной логики: пересчёт идёт из тех же _spot/_heading, которые больше не меняются.
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

# ── Очистка тел прошлого штрафного ────────────────────────────────────────────
## Деспавн тел стенки/своих, заспавненных прошлым розыгрышем (чтобы не накапливались и их ИИ
## не мешал новому штрафному). Текущего бьющего (controlled_player) НЕ трогаем.
func _cleanup_spawned() -> void:
	for n in _manager.get_tree().get_nodes_in_group("fk_spawned"):
		if is_instance_valid(n) and n != _kicker:
			n.queue_free()
	_wall_bodies.clear()
	_mates.clear()


# ── Расчистка коридора удара ───────────────────────────────────────────────────
## Никто (ни свои, ни чужие — кроме бьющего и вратаря) не должен физически стоять между мячом
## и стенкой: выталкиваем их вбок за пределы коридора. Если стенки нет (дальний штрафной) —
## расчищать нечего, пропускаем.
func _clear_corridor() -> void:
	var dist_to_goal := absf(_spot.z - _goal_line_z)
	var count := FreeKickLogic.wall_count(dist_to_goal, FootballConstants.FK_WALL_FAR_DIST,
		FootballConstants.FK_WALL_NEAR_DIST, FootballConstants.FK_WALL_MIN_PLAYERS, FootballConstants.FK_WALL_MAX_PLAYERS)
	if count <= 0:
		return
	var nf := FreeKickLogic.near_far_posts(_spot, 0.0, FootballConstants.GOAL_WIDTH * 0.5, _goal_line_z)
	var wl := FreeKickLogic.wall_line(_spot, nf[0], _goal_line_z, FootballConstants.FK_WALL_DIST, 0.5)
	var to: Vector3 = wl["center"]
	var bodies := _manager.get_tree().get_nodes_in_group("team_1")
	bodies += _manager.get_tree().get_nodes_in_group("team_2")
	for n in bodies:
		if not is_instance_valid(n) or n == _kicker or n == _keeper or not (n is Node3D):
			continue
		var adjusted := FreeKickLogic.push_out_of_corridor(n.global_position, _spot, to, FootballConstants.FK_CORRIDOR_HALF_WIDTH)
		if not adjusted.is_equal_approx(n.global_position):
			n.global_position = adjusted

# ── Стенка ────────────────────────────────────────────────────────────────────
func _spawn_defense() -> void:
	_wall_bodies.clear()
	var dist_to_goal := absf(_spot.z - _goal_line_z)
	var count := FreeKickLogic.wall_count(dist_to_goal, FootballConstants.FK_WALL_FAR_DIST,
		FootballConstants.FK_WALL_NEAR_DIST, FootballConstants.FK_WALL_MIN_PLAYERS, FootballConstants.FK_WALL_MAX_PLAYERS)
	if count <= 0:
		return
	var nf := FreeKickLogic.near_far_posts(_spot, 0.0, FootballConstants.GOAL_WIDTH * 0.5, _goal_line_z)
	var wl := FreeKickLogic.wall_line(_spot, nf[0], _goal_line_z, FootballConstants.FK_WALL_DIST, 0.5)
	var positions := FreeKickLogic.wall_body_positions(wl["center"], wl["right"], count, FootballConstants.FK_WALL_SPACING)
	for pos in positions:
		var body := _make_wall_body(pos)
		_wall_bodies.append({"body": body, "jumping": false, "jump_t": 0.0, "base_y": body.global_position.y})

## Создать статичное тело стенки (team_2, лицом к мячу), пока без ИИ-скрипта.
func _make_wall_body(pos: Vector3) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "WallMember"
	p.global_position = pos
	var visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	p.add_child(visual)
	p.add_child(PlayerMotor.new())
	visual.apply_appearance({"kit_color": Color(0.9, 0.1, 0.1)})
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.5
	shape.radius = 0.3
	col.shape = shape
	col.position = Vector3(0, 0.25, 0)
	p.add_child(col)
	_manager.add_child(p)
	p.add_to_group("team_2")
	p.add_to_group("fk_spawned")
	p.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	p.collision_mask = FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
	# Лицом к мячу, мотор залочен (стоит на месте).
	p.look_at(Vector3(_spot.x, pos.y, _spot.z), Vector3.UP)
	var pm := PlayerMotor.find_on(p)
	if pm != null:
		pm.set_control_locked(true)
		pm.set_move_intent(Vector3.ZERO)
	return p

## Каждый кадр после удара: решаем прыжок стенки и ведём вертикальную дугу прыгнувших тел.
func _update_wall_jumps(delta: float) -> void:
	if not _ball_in_flight_watch:
		return
	for entry in _wall_bodies:
		var b: CharacterBody3D = entry["body"]
		if not is_instance_valid(b):
			continue
		if not entry["jumping"]:
			# Прыжок по таймингу подлёта: стартуем, когда до плоскости стенки ≈ время подъёма
			# (половина FK_WALL_JUMP_TIME), чтобы пик прыжка совпал с приходом мяча.
			var should := FreeKickLogic.wall_should_jump(_ball.global_position, _ball.linear_velocity,
				b.global_position, FootballConstants.FK_WALL_JUMP_TIME * 0.5)
			if should:
				entry["jumping"] = true
				entry["jump_t"] = 0.0
				b.add_to_group("fallen")   # чтобы PlayerMotor не пинил Y во время прыжка
				var v := _wall_visual(b)
				if v != null:
					v.play_oneshot(&"jumping_wall")
		else:
			entry["jump_t"] += delta
			var tt: float = entry["jump_t"] / FootballConstants.FK_WALL_JUMP_TIME
			if tt >= 1.0:
				b.global_position.y = entry["base_y"]
				b.remove_from_group("fallen")
				entry["jumping"] = false
				entry["jump_t"] = FootballConstants.FK_WALL_JUMP_TIME + 1.0   # больше не прыгаем
				var v := _wall_visual(b)
				if v != null:
					v.recover()
			else:
				var arc: float = sin(tt * PI)   # 0→1→0
				b.global_position.y = entry["base_y"] + arc * FootballConstants.FK_WALL_JUMP_HEIGHT

func _wall_visual(b: Node) -> PlayerVisual:
	for c in b.get_children():
		if c is PlayerVisual:
			return c
	return null

## Стенка → обычный team_2-ИИ (simple_ai). Тела не удаляются, а вливаются в игру.
## _wall_bodies НЕ очищаем (спавн чистит на старте) — чтобы состояние было инспектируемо.
func _convert_bodies() -> void:
	var ai_script := preload("res://scripts/ai/simple_ai.gd")
	for entry in _wall_bodies:
		var b: CharacterBody3D = entry["body"]
		if not is_instance_valid(b):
			continue
		if b.is_in_group("fallen"):
			b.remove_from_group("fallen")
			b.global_position.y = entry["base_y"]
		var pm := PlayerMotor.find_on(b)
		if pm != null:
			pm.set_control_locked(false)
		b.set_script(ai_script)
		b.set_physics_process(true)
		b.ball = _ball
		b.home_goal = _manager.get_node_or_null("GoalHome/GoalArea")
	# Свои (тиммейт/цели) → обычный team_1-ИИ (teammate_ai). _mates НЕ очищаем (спавн чистит на старте).
	var mate_script := preload("res://scripts/ai/teammate_ai.gd")
	for entry in _mates:
		var mb: CharacterBody3D = entry["body"]
		if not is_instance_valid(mb):
			continue
		var mpm := PlayerMotor.find_on(mb)
		if mpm != null:
			mpm.set_control_locked(false)
		mb.set_script(mate_script)
		mb.set_physics_process(true)
		mb.ball = _ball
		mb.controlled_player = _manager.controlled_player

# ── Пас/навес ─────────────────────────────────────────────────────────────────
func _spawn_mates() -> void:
	_mates.clear()
	var right := _heading.cross(Vector3.UP).normalized()
	# Тиммейт рядом с бьющим (для короткого паса).
	var mate_pos := _spot + right * FootballConstants.FK_MATE_LATERAL - _heading * FootballConstants.FK_MATE_BACK
	mate_pos.y = 0.5
	_mates.append({"body": _make_mate_body(mate_pos), "is_target": false})
	# 1-2 атакующих у ворот (цель для навеса), по разные стороны от центра.
	var into := signf(_goal_line_z) * -1.0   # от ворот в поле (к центру)
	var depth_z := _goal_line_z + into * FootballConstants.FK_TARGET_DEPTH
	for sx in [-1.0, 1.0]:
		var tp := Vector3(sx * FootballConstants.FK_TARGET_LATERAL, 0.5, depth_z)
		_mates.append({"body": _make_mate_body(tp), "is_target": true})

## Создать статичное тело своей команды (team_1), пока без ИИ-скрипта.
func _make_mate_body(pos: Vector3) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "FKMate"
	p.global_position = pos
	var visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	p.add_child(visual)
	p.add_child(PlayerMotor.new())
	visual.apply_appearance({"kit_color": Color(0.1, 0.1, 0.9)})
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.5
	shape.radius = 0.3
	col.shape = shape
	col.position = Vector3(0, 0.25, 0)
	p.add_child(col)
	_manager.add_child(p)
	p.add_to_group("team_1")
	p.add_to_group("fk_spawned")
	p.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	p.collision_mask = FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
	var pm := PlayerMotor.find_on(p)
	if pm != null:
		pm.set_control_locked(true)
		pm.set_move_intent(Vector3.ZERO)
	return p

## Тиммейт, в которого направлен пас: максимально совпадающий с heading (по dot от мяча).
func _select_receiver() -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_dot := 0.2   # порог выравнивания направления
	var from: Vector3 = _ball.global_position
	var h := Vector3(_heading.x, 0.0, _heading.z).normalized()
	for entry in _mates:
		var b = entry["body"]
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

# ── Debug-болванки (тестовое scaffolding) ────────────────────────────────────
## Прячем стоячие debug-болванки стенки на время штрафного (визуал + коллизия), чтобы они не
## засоряли розыгрыш. В реальной игре их нет — это временный тест-инструмент.
func _hide_debug_dummies() -> void:
	_hidden_dummies.clear()
	for n in _manager.get_children():
		if n is CharacterBody3D and String(n.name).begins_with("WallDummy"):
			_hidden_dummies.append({"node": n, "layer": n.collision_layer})
			n.visible = false
			n.collision_layer = 0

func _restore_debug_dummies() -> void:
	for entry in _hidden_dummies:
		var n = entry["node"]
		if is_instance_valid(n):
			n.visible = true
			n.collision_layer = entry["layer"]
	_hidden_dummies.clear()

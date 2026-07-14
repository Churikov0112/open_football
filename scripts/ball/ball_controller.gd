extends RigidBody3D

@export var drag_factor: float = 0.985
@export var air_resistance: float = 0.999

@export var dribble_forward_distance: float = 0.5
@export var dribble_height: float = 0.08
@export var dribble_max_speed: float = 12.0

var dribbler: Node3D
var last_kicker: Node3D
var _last_release_time: int = 0
var _release_cooldown_msec: int = 500
var _last_kick_time: int = 0
var _kick_cooldown_msec: int = 1500
var _kick_grace_body: PhysicsBody3D = null   # бьющий, временно исключён из коллизии (см. _begin_kick_grace)
const KICK_GRACE_MSEC := 350   # окно после удара, пока мяч НЕ сталкивается с самим бьющим
var _dribbler_prev_pos: Vector3 = Vector3.ZERO
var _pending_impulse: Vector3 = Vector3.ZERO

enum BallState { OPEN, TRAPPED, FLIGHT, CAUGHT }
var state: BallState = BallState.OPEN
var _curl: Vector3 = Vector3.ZERO
var _dribble_dir: Vector3 = Vector3.FORWARD  # закоммиченное направление дриблинга (меняется на «догнал»)
var _dribble_intent: Vector3 = Vector3.ZERO  # желаемое направление толчка от владельца (стик); ZERO → facing
var _dribble_push_extra: float = 0.0         # доп. сила толчка (спринт) от владельца, м/с
var _was_far: bool = true                    # мяч был вне зоны догона → следующий контакт = толчок
var _dribble_chasing: bool = false           # true → мяч ушёл, владелец должен БЕЖАТЬ к мячу (гистерезис)
var _dribble_suppressed: bool = false        # true → НЕ толкать мяч (идёт зарядка/commit паса-удара) → одно касание
var _wobble_dir_n: float = 0.0               # плавный случайный дрейф направления удержания [-1..1] (спринт-неточность)
var _wobble_lead_n: float = 0.0              # плавный случайный дрейф дистанции удержания [-1..1]
var _flat_flight: bool = false               # true → настильный удар: держим мяч на газоне (vy=0), без подскока
var _hold_node: Node3D = null                # узел-«руки» вратаря: пока CAUGHT, мяч приклеен к нему


func _ready() -> void:
	_football_texture()
	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = 0.4
	phys_mat.bounce = 0.35
	physics_material_override = phys_mat
	continuous_cd = true           # быстрый удар не должен туннелировать сквозь игрока/штангу
	max_contacts_reported = 2
	contact_monitor = true


func _football_texture() -> void:
	var mesh_instance := $Mesh as MeshInstance3D
	if not mesh_instance:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.metallic = 0.0
	mat.roughness = 0.4
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for i in range(12):
		var cx := 30 + randi() % 196
		var cy := 30 + randi() % 196
		_draw_hexagon(img, cx, cy, 18, Color(0.1, 0.1, 0.1))
	var tex := ImageTexture.create_from_image(img)
	mat.albedo_texture = tex
	mesh_instance.material_override = mat


func _draw_hexagon(img: Image, cx: float, cy: float, r: float, color: Color) -> void:
	for x in range(int(cx - r), int(cx + r + 1)):
		for y in range(int(cy - r), int(cy + r + 1)):
			var dx := x - cx
			var dy := y - cy
			var dist := sqrt(dx * dx + dy * dy)
			if dist <= r:
				var angle := atan2(dy, dx)
				var test_angle := fmod(angle + PI / 6, PI / 3) - PI / 6
				var test_dist := dist * cos(test_angle)
				if test_dist <= r * cos(PI / 6) and dist <= r:
					img.set_pixel(x, y, color)


## force=true — принять мяч немедленно, минуя кулдауны релиза/кикера (для адресата паса:
## короткий/слабый пас доходит быстрее кулдауна релиза (500мс), иначе приём блокируется и
## мяч проносит мимо).
func set_dribbler(node: Node3D, force: bool = false) -> void:
	if not force:
		var now := Time.get_ticks_msec()
		if now - _last_release_time < _release_cooldown_msec:
			return
		if node and node == last_kicker and now - _last_kick_time < _kick_cooldown_msec:
			return
	dribbler = node
	_dribbler_prev_pos = node.global_position if node else Vector3.ZERO
	state = BallState.TRAPPED if node else BallState.OPEN
	_set_player_collision(false)  # трапнутый/бесхозный мяч не сталкивается с капсулами игроков
	if node:
		var f := -node.global_transform.basis.z
		f.y = 0.0
		_dribble_dir = f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD
		_dribble_intent = Vector3.ZERO  # сбрасываем стик прежнего владельца (иначе утечёт к новому/ИИ)
		_dribble_push_extra = 0.0
		_was_far = true
		_dribble_chasing = false  # старт с мячом у ног → ведём стиком, не догоняем (иначе орбита на месте)
		_dribble_suppressed = false


## Желаемое направление ТОЛЧКА мяча от владельца (стик человека) + доп. сила (спринт).
## ZERO-направление → на «догнал» возьмём facing владельца (путь ИИ, который intent не задаёт).
func set_dribble_intent(dir: Vector3, push_extra: float = 0.0) -> void:
	_dribble_push_extra = push_extra
	var d := dir
	d.y = 0.0
	if d.length() > 0.001:
		_dribble_intent = d.normalized()


## Нужно ли владельцу БЕЖАТЬ к мячу (мяч ушёл далеко) vs вести стиком (мяч у ног).
## Считается с гистерезисом в _integrate_forces (CHASE_DIST/CATCH_DIST), чтобы не дёргалось.
func should_chase() -> bool:
	return _dribble_chasing


## Подавить дриблинг-толчок (пока владелец заряжает/выполняет пас-удар) → мяч ждёт у ног,
## чтобы касание было ровно одно (сам пас/удар), а не «дриблинг-толчок + пас» (двойное касание).
func set_dribble_suppressed(on: bool) -> void:
	_dribble_suppressed = on


## Вратарь поймал мяч в РУКИ: мяч приклеивается к hold_node (точка рук) и висит там (CAUGHT),
## пока не будет выброшен (launch/kick). В отличие от set_dribbler (мяч у ног, дриблинг).
func catch(holder: Node3D, hold_node: Node3D) -> void:
	print("[BALL] catch() at ", global_position, " hold_node=", hold_node)
	dribbler = holder
	_hold_node = hold_node
	state = BallState.CAUGHT
	_flat_flight = false
	_curl = Vector3.ZERO
	_set_player_collision(false)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Мяч сейчас в руках вратаря (приклеен)?
func is_caught() -> bool:
	return state == BallState.CAUGHT


func release_dribble() -> void:
	if dribbler:
		dribbler = null
		_last_release_time = Time.get_ticks_msec()
	_dribbler_prev_pos = Vector3.ZERO
	_hold_node = null
	state = BallState.OPEN
	_set_player_collision(false)


## Текущий владелец мяча (нейтральное имя поверх legacy-поля dribbler).
func player() -> Node3D:
	return dribbler


## Мяч сейчас в полёте (после удара/паса)? Нейтральный предикат без доступа к enum извне.
func is_flight() -> bool:
	return state == BallState.FLIGHT


## Блок в полёте: контакт летящего мяча с игроком гасит скорость, сбрасывает кручение и роняет
## мяч в OPEN (коллизия с игроками выключается). Дальше — обычная борьба за подбор. Хук под
## вратарский сейв — отдельная SaveArea в будущем; пока обычный блок.
func block_in_flight() -> void:
	linear_velocity *= 0.25
	angular_velocity = Vector3.ZERO
	_curl = Vector3.ZERO
	_flat_flight = false
	state = BallState.OPEN
	_set_player_collision(false)


## Вратарский отбой: гасит скорость ×damp, перенаправляет мяч НАРУЖУ (по direction, чуть
## вверх), роняет в OPEN, коллизию с игроками выключает. В отличие от block_in_flight()
## (просто гасит на месте) — задаёт направление отскока от ворот.
func parry(direction: Vector3, damp: float) -> void:
	var speed := linear_velocity.length() * damp
	_curl = Vector3.ZERO
	_flat_flight = false
	state = BallState.OPEN
	_set_player_collision(false)
	var out := direction
	out.y = 0.0
	if out.length() < 0.001:
		out = Vector3(0, 0, 1)
	out = out.normalized()
	out.y = 0.5   # немного вверх, чтобы отбитый мяч читался
	linear_velocity = out.normalized() * speed


## Слой игроков в маске мяча — ВКЛючаем только в полёте (блок/перехват), иначе капсула игрока
## толкала бы мяч на дриблинге/подборе (ломает близкий контроль, подскок). Bit2 = PLAYER.
func _set_player_collision(on: bool) -> void:
	var pbit := FootballConstants.PLAYER_COLLISION_MASK
	if on:
		collision_mask |= pbit
	else:
		collision_mask &= ~pbit
		_end_kick_grace()   # полёт кончился — персональное исключение бьющего больше не нужно


## Грейс от САМОБЛОКА: удар с места стартует у самых ног (после авто-добегания к мячу игрок
## может стоять вплотную/поверх мяча — вне полёта мяч прозрачен для капсул). Включение
## коллизии мяч↔игроки в launch()/kick() давало мгновенный контакт с САМИМ бьющим →
## _on_ball_collision → block_in_flight() тихо гасил собственный удар в OPEN — вратарь такого
## «удара» не видел вовсе (is_flight()=false). Исключаем бьющего из коллизии мяча на первые
## KICK_GRACE_MSEC полёта; снятие — отложенно (см. _end_kick_grace) и по концу полёта.
func _begin_kick_grace(kicker: Node) -> void:
	_end_kick_grace()
	var body := kicker as PhysicsBody3D
	if body != null and is_instance_valid(body):
		_kick_grace_body = body
		add_collision_exception_with(body)


## Снять грейс. Само remove — отложенно: зовётся и из физических коллбеков
## (_integrate_forces / body_entered), где менять исключения сразу нельзя.
func _end_kick_grace() -> void:
	if _kick_grace_body != null and is_instance_valid(_kick_grace_body):
		call_deferred(&"remove_collision_exception_with", _kick_grace_body)
	_kick_grace_body = null


func clear_last_kicker() -> void:
	last_kicker = null
	_last_kick_time = 0


func get_dribble_direction() -> Vector3:
	if not dribbler or not is_instance_valid(dribbler):
		return Vector3.FORWARD
	return _get_movement_direction()


## Read-only версия get_dribble_direction() — НЕ трогает _dribbler_prev_pos.
## _integrate_forces() каждый физический тик читает И пишет _dribbler_prev_pos, чтобы
## посчитать скорость дриблера (pos_delta = player_pos - _dribbler_prev_pos; player_vel =
## pos_delta/dt). match_manager._process() вызывает get_dribble_direction() КАЖДЫЙ
## РЕНДЕР-КАДР во время зарядки паса (для маркера прицеливания) — если вызвать
## мутирующий геттер, он обнулит дельту раньше, чем до неё доберётся _integrate_forces(),
## и measured pos_delta занизится → мяч отстаёт/дёргается от дриблера при любой зарядке
## паса. Поэтому здесь используем только текущую ориентацию тела (facing), как в
## fallback-ветке _direction_from_delta()/_get_movement_direction(), но без трекинга
## дельты позиции и без побочных эффектов. НЕ "упрощай" обратно в get_dribble_direction() —
## это вернёт гонку.
func peek_dribble_direction() -> Vector3:
	if not dribbler or not is_instance_valid(dribbler):
		return Vector3.FORWARD
	var facing := -dribbler.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		return facing.normalized()
	return Vector3.FORWARD


func kick(direction: Vector3, power: float) -> void:
	last_kicker = dribbler
	_last_kick_time = Time.get_ticks_msec()
	release_dribble()
	state = BallState.FLIGHT
	_curl = Vector3.ZERO         # прямой удар не крутится
	_flat_flight = false
	_set_player_collision(true)  # в полёте мяч сталкивается с игроками (блок/перехват)
	_begin_kick_grace(last_kicker)   # но НЕ с самим бьющим (анти-самоблок)
	_pending_impulse = direction * power


## Задать мячу готовую стартовую скорость (в отличие от kick(), где power — импульс, а dir
## не нормализован). velocity — уже посчитанная баллистика (PassSystem.launch_ground/launch_lob).
## Импульс = velocity*mass, т.к. _integrate_forces применяет vel += _pending_impulse/mass.
func launch(velocity: Vector3, flat: bool = false) -> void:
	last_kicker = dribbler
	_last_kick_time = Time.get_ticks_msec()
	release_dribble()
	state = BallState.FLIGHT
	_curl = Vector3.ZERO         # низовой/навесной пас не крутится (кручёный — через launch_curl)
	_flat_flight = flat          # настильный удар: держим на газоне, без подскока
	_set_player_collision(true)  # в полёте мяч сталкивается с игроками (блок/перехват)
	_begin_kick_grace(last_kicker)   # но НЕ с самим бьющим (анти-самоблок)
	_pending_impulse = velocity * mass


## Запуск с кручением: как launch(), но задаёт вектор _curl (Magnus в _integrate_forces).
## curl.z — боковая составляющая (через left = vel×UP), curl.y — подъём (для дуги). Для
## кручёного удара Фазы 1; ShotSystem посчитает velocity и curl.
func launch_curl(velocity: Vector3, curl: Vector3, flat: bool = false) -> void:
	last_kicker = dribbler
	_last_kick_time = Time.get_ticks_msec()
	release_dribble()
	state = BallState.FLIGHT
	_curl = curl
	_flat_flight = flat          # настильный кручёный: держим на газоне, без подскока
	_set_player_collision(true)
	_begin_kick_grace(last_kicker)   # но НЕ с самим бьющим (анти-самоблок)
	_pending_impulse = velocity * mass


func _integrate_forces(state_body: PhysicsDirectBodyState3D) -> void:
	var vel := state_body.linear_velocity

	# Отложенный импульс (kick/launch) применяется В НАЧАЛЕ интеграции, ДО веток состояний.
	# Раньше он применялся в самом конце — и на первом кадре после удара С МЕСТА ветка FLIGHT
	# видела ещё нулевую скорость мяча → «полёт кончился» (< FLIGHT_END_SPEED) → мяч тихо падал
	# в OPEN, а импульс прилетал уже ПОСЛЕ: мяч летел в ворота на полной скорости, но НЕ в
	# FLIGHT — вратарь такого удара не видел вовсе. С разбега мяч уже движется со скоростью
	# дриблинга (> порога), поэтому баг проявлялся только на ударах с места.
	if _pending_impulse.length_squared() > 0:
		vel += _pending_impulse / mass
		_pending_impulse = Vector3.ZERO

	# Пойман в руки: приклеиваем мяч к точке рук вратаря, скорость держим в нуле.
	if state == BallState.CAUGHT:
		if _hold_node != null and is_instance_valid(_hold_node):
			var t := state_body.transform
			t.origin = _hold_node.global_position
			state_body.transform = t
		state_body.linear_velocity = Vector3.ZERO
		return

	if state == BallState.TRAPPED and dribbler and is_instance_valid(dribbler):
		var player_pos := dribbler.global_position
		var dt := state_body.step

		var pos_delta := player_pos - _dribbler_prev_pos
		_dribbler_prev_pos = player_pos
		pos_delta.y = 0.0

		var player_vel := Vector3.ZERO
		if dt > 0.0:
			player_vel = (pos_delta / dt).limit_length(15.0)
		var player_speed := player_vel.length()

		var gap := state_body.transform.origin - player_pos
		gap.y = 0.0
		var gd := gap.length()

		# Гистерезис: мяч вырвался дальше CHASE → «догон» (свободный ролл, игрок бежит к мячу);
		# догнал ближе CATCH → снова под контролем. Между — держим текущий режим (без флип-флопа).
		if gd > FootballConstants.DRIBBLE_CHASE_DIST:
			_dribble_chasing = true
		elif gd < FootballConstants.DRIBBLE_CATCH_DIST:
			_dribble_chasing = false

		if _dribble_chasing:
			# Мяч вырвался — свободно катится с трением, игрок догоняет (match_manager ведёт к мячу).
			vel.x *= FootballConstants.DRIBBLE_ROLL_DRAG
			vel.z *= FootballConstants.DRIBBLE_ROLL_DRAG
		else:
			# Под контролем: удерживаем мяч в точке впереди. Lead растёт со скоростью — плотно
			# на медленном (мяч у ног, не пробежать мимо), далеко на бегу. Скорость мяча =
			# скорость игрока + подтягивание к точке, сглаженно (лаг = «живость»). Заряд/стоп
			# (suppressed) → плотное удержание (базовый lead), чтобы пас/остановка были чистыми.
			var pdir := _dribble_intent
			if pdir.length_squared() < 0.0001:
				pdir = _dribble_dir
			_dribble_dir = pdir
			var lead := FootballConstants.DRIBBLE_LEAD_BASE
			if not _dribble_suppressed:
				lead += (player_speed + _dribble_push_extra) * FootballConstants.DRIBBLE_LEAD_PER_SPEED
			# Спринт-неточность: плавный случайный увод направления и дистанции удержания,
			# масштаб по силе спринта (доля от DRIBBLE_SPRINT_PUSH_EXTRA). Дрейф не по-кадровый:
			# копится с затуханием (*0.99 + маленький рандом) → медленное «плавание», не джиттер.
			var pdir_w := pdir
			var sprint_factor := 0.0
			if FootballConstants.DRIBBLE_SPRINT_PUSH_EXTRA > 0.0:
				sprint_factor = clampf(_dribble_push_extra / FootballConstants.DRIBBLE_SPRINT_PUSH_EXTRA, 0.0, 1.0)
			if sprint_factor > 0.01 and not _dribble_suppressed:
				_wobble_dir_n = clampf(_wobble_dir_n * 0.98 + randf_range(-0.15, 0.15), -1.0, 1.0)
				_wobble_lead_n = clampf(_wobble_lead_n * 0.98 + randf_range(-0.15, 0.15), -1.0, 1.0)
				pdir_w = pdir.rotated(Vector3.UP, deg_to_rad(FootballConstants.DRIBBLE_SPRINT_WOBBLE_ANGLE) * _wobble_dir_n * sprint_factor)
				lead += FootballConstants.DRIBBLE_SPRINT_WOBBLE_LEAD * _wobble_lead_n * sprint_factor
			else:
				_wobble_dir_n *= 0.9
				_wobble_lead_n *= 0.9
			var front := player_pos + pdir_w * lead
			var to_front := front - state_body.transform.origin
			to_front.y = 0.0
			var desired := player_vel + to_front * FootballConstants.DRIBBLE_CONTROL_GAIN
			var flat_vel := Vector3(vel.x, 0.0, vel.z)
			var blended := flat_vel.lerp(desired, FootballConstants.DRIBBLE_CONTROL_LERP)
			vel.x = blended.x
			vel.z = blended.z
		vel.y *= air_resistance
	else:
		if state == BallState.FLIGHT:
			# Magnus: боковой (через left = vel×UP) + подъёмный импульс, с затуханием — дуга
			# кручёного удара, живёт поверх обычной баллистики и переживает отскоки.
			# ТОЛЬКО в воздухе: на газоне (мяч у земли) кручение не заносит — иначе при слабом
			# затухании (_curl держится долго) мяч «крутит» катясь по полю.
			var horiz := Vector3(vel.x, 0.0, vel.z)
			var airborne := state_body.transform.origin.y > FootballConstants.BALL_RADIUS + 0.15
			if (airborne or _flat_flight) and _curl.length_squared() > 0.0001 and horiz.length() > 0.5:
				var left := horiz.normalized().cross(Vector3.UP)
				vel += (left * _curl.z + Vector3.UP * _curl.y) * state_body.step * FootballConstants.MAGNUS_FORCE
				_curl *= FootballConstants.MAGNUS_DECAY
			# Полёт закончился, когда мяч почти остановился — снова OPEN, коллизия с игроками
			# выключается (чтобы капсула подбирающего не сбивала/подкидывала мяч). Порог низкий,
			# чтобы быстрый летящий мяч блокировался стенкой, а не выпадал из FLIGHT рано.
			# Грейс от самоблока истёк — мяч уже отлетел от бьющего, коллизия с ним снова нужна
			# (напр., отскок от штанги обратно в него).
			if _kick_grace_body != null and Time.get_ticks_msec() - _last_kick_time > KICK_GRACE_MSEC:
				_end_kick_grace()
			if _flat_flight:
				vel.y = 0.0   # настильный удар катится по газону, без подскока
			if Vector3(vel.x, 0.0, vel.z).length() < FootballConstants.FLIGHT_END_SPEED:
				state = BallState.OPEN
				_curl = Vector3.ZERO
				_flat_flight = false
				_set_player_collision(false)
		vel.x *= drag_factor
		vel.z *= drag_factor
		vel.y *= air_resistance

	state_body.linear_velocity = vel


func _direction_from_delta(pos_delta: Vector3) -> Vector3:
	if pos_delta.length_squared() > 0.0001:
		return pos_delta.normalized()
	var facing := -dribbler.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		return facing.normalized()
	return Vector3.FORWARD


func _get_movement_direction() -> Vector3:
	var pos_delta := dribbler.global_position - _dribbler_prev_pos
	_dribbler_prev_pos = dribbler.global_position
	pos_delta.y = 0.0
	if pos_delta.length_squared() > 0.0001:
		return pos_delta.normalized()

	var facing := -dribbler.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		return facing.normalized()

	return Vector3.FORWARD

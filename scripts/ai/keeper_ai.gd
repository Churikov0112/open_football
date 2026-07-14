extends CharacterBody3D
## AI-вратарь: позиционирование на линии + сейв (ловля/нырок/отбой) + вынос мяча.
## Движение — через PlayerMotor; нырок — свой move_and_collide при заблокированном моторе
## (как подкат). Вся математика — в KeeperLogic (чистые функции).

@export var ball: RigidBody3D
var goal_line_z: float = 0.0
var save_area: Area3D
var hold_point: Node3D   # узел-«руки»: пойманный мяч приклеивается сюда
var manager: Node   # match_manager — для проверки празднования гола

enum State { POSITION, DIVE, CATCHING, HOLD, DISTRIBUTE }
var _state: int = State.POSITION
var _wired: bool = false
var _pass_through: bool = false   # true → идёт miss_top: мяч НЕ ловим (пропускаем в ворота)

# Сейв.
var _react_left: float = 0.0
var _reacting: bool = false
var _current_action: int = KeeperLogic.SaveAction.NONE
var _dive_vel: Vector3 = Vector3.ZERO
var _dive_time_left: float = 0.0
var _state_timer: float = 0.0
var _distribute_fired: bool = false
var _ground_y: float = 0.5   # уровень газона (высота тела в стойке), для приземления после нырка
var _high_roll: int = -1   # бросок «взять/пропустить» высокий центр (зона 2.0..2.5): -1=нет, 0=пропуск, 1=ловля


func _motor() -> PlayerMotor:
	return PlayerMotor.find_on(self)


func _visual() -> PlayerVisual:
	for c in get_children():
		if c is PlayerVisual:
			return c
	return null


## Скорость перемещения по линии относительно общей максимальной.
func _base_scale() -> float:
	return 1.0


## Одноразовая проводка: стиль локомоции + подписка на сейв-зону и сигнал касания.
func _ensure_wired() -> void:
	if _wired:
		return
	_wired = true
	_ground_y = global_position.y   # запоминаем уровень газона (высоту стойки)
	var v := _visual()
	if v != null:
		v.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)
		if not v.action_contact.is_connected(_on_visual_contact):
			v.action_contact.connect(_on_visual_contact)
		# Точка рук на кости кисти (мяч движется вместе с рукой); если кость не нашлась —
		# остаётся фиксированный HoldPoint (грудь), переданный из match_manager.
		var bone_hold := v.get_hold_attachment()
		if bone_hold != null:
			hold_point = bone_hold
	# Контакт мяча — геометрически (см. _catch_radius_hit), не через Area3D: сфера-детектор
	# ненадёжно ловила быстрый мяч во вратаря (проходил сквозь). save_area больше не используется.


func _physics_process(delta: float) -> void:
	if not ball or not is_instance_valid(ball):
		return
	_ensure_wired()
	# Празднование гола: новых сейвов/выносов не начинаем (иначе вратарь ловит осевший в сетке
	# мяч и выносит его уже ПОСЛЕ гола). Но ТЕКУЩИЙ нырок доигрываем до конца анимации —
	# не дёргаем в idle посреди прыжка.
	if manager != null and manager.is_celebrating():
		if _state == State.DIVE:
			_dive(delta)   # доигрываем нырок, idle придёт по завершении клипа
			return
		if _state == State.HOLD or _state == State.DISTRIBUTE:
			# Страховка: не уносить пойманный мяч в стойку приклеенным к руке — отпустить.
			if ball.has_method(&"is_caught") and ball.is_caught() and ball.dribbler == self:
				ball.release_dribble()
			_finish_dive()   # мяч во время празднования не выбиваем — в стойку
		var mm := _motor()
		if mm != null:
			mm.set_move_intent(Vector3.ZERO)
			var into := -1.0 if goal_line_z > 0.0 else 1.0
			mm.set_face_direction(Vector3(0.0, 0.0, into))
		return
	match _state:
		State.POSITION:
			_position(delta)
		State.DIVE:
			_dive(delta)
		State.CATCHING:
			_catching(delta)
		State.HOLD:
			_hold(delta)
		State.DISTRIBUTE:
			_distribute(delta)


## Держим линию: X за мячом, лицом к мячу, лёгкий выход под угол. При ударе в створ —
## реагируем с задержкой, затем ловим на месте / стартуем нырок по таймингу.
func _position(delta: float) -> void:
	var m := _motor()
	if m == null:
		return
	# Режим «тревоги» по дистанции мяча: близко → стойка готовности + приставные шаги (KEEPER),
	# далеко → обычный расслабленный idle/бег (NORMAL).
	var v := _visual()
	if v != null:
		var dist_z := absf(ball.global_position.z - goal_line_z)
		v.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER if dist_z < FootballConstants.KEEPER_ALERT_DIST else PlayerVisual.LOCO_STYLE_NORMAL)
	# РЕФЛЕКС: мяч летит к воротам И уже в радиусе рук вратаря — ловим/пропускаем СХОДУ, каждый
	# кадр, надёжно (не зависит от выравнивания с точкой удара). Это чинит scoop/catch «во вратаря».
	if ball.is_flight() and _heading_at_goal() and _catch_radius_hit():
		var by := ball.global_position.y
		print("[KEEPER] REFLEX hit: ball=", ball.global_position, " kpr=", global_position, " y=", by)
		if _should_catch_high(by):
			ball.catch(self, hold_point)
			_begin_central_catch(by)
		else:
			_begin_miss_top()
		return
	# Смотрим В ПОЛЕ (к бьющему), а не на мяч: иначе при ударе мимо/в створ вратарь
	# разворачивается вслед залетевшему мячу и ныряет спиной. Доминанта — направление поля,
	# с лёгким доворотом к X мяча.
	var into := -1.0 if goal_line_z > 0.0 else 1.0
	m.set_face_direction(Vector3(ball.global_position.x - global_position.x, 0.0, into * 4.0))
	var target := KeeperLogic.line_position(
		ball.global_position, goal_line_z, FootballConstants.GOAL_WIDTH * 0.5,
		FootballConstants.KEEPER_LINE_NARROW_GAIN, FootballConstants.KEEPER_MAX_OFF_LINE)
	var to := target - global_position
	to.y = 0.0
	if to.length() > 0.15:
		m.set_move_intent(to.normalized(), _base_scale())
	else:
		m.set_move_intent(Vector3.ZERO)

	if not ball.is_flight():
		_reacting = false
		return
	# Мяч летит ОТ ворот (собственный вынос/отбой, пас в поле) — это НЕ удар. Без этого гейта
	# shot_intercept для улетающего мяча вырождается в позицию мяча, is_on_target ложно даёт
	# «в створе», и вратарь мгновенно ловит СВОЙ вынос обратно (петля ловля→вынос→ловля).
	if not _heading_at_goal():
		_reacting = false
		return
	# Мяч уже пересёк линию (за спиной вратаря, в сетке) — не реагируем: иначе вратарь ловит
	# осевший в сетке мяч (гол) и «спасает» его. into (объявлена выше) = направление в поле.
	if (ball.global_position.z - goal_line_z) * into < 0.2:
		_reacting = false
		return
	# Драги — с настоящего мяча (drag_factor/air_resistance за физкадр): без них прогноз
	# завышает высоту на 0.3–0.5 м и верховые удары в створ уходят в «пропуск над перекладиной».
	var intercept := KeeperLogic.shot_intercept(ball.global_position, ball.linear_velocity, goal_line_z, _ball_gravity(),
		ball.drag_factor, ball.air_resistance, 1.0 / float(Engine.physics_ticks_per_second))
	# Реагируем на удары в створ И на мимо-удары в пределах ENGAGE_MARGIN (2м) за штангой/перекладиной.
	var engage_w := FootballConstants.GOAL_WIDTH * 0.5 + FootballConstants.KEEPER_ENGAGE_MARGIN
	var ont := KeeperLogic.is_on_target(intercept, engage_w, FootballConstants.GOAL_HEIGHT + FootballConstants.KEEPER_ENGAGE_MARGIN)
	if not _reacting:
		var dball := ball.global_position.distance_to(global_position)
		var tt := KeeperLogic.time_to_intercept(ball.global_position, ball.linear_velocity, intercept)
		print("[KEEPER] shot detected intercept=", intercept, " onTarget=", ont, " dx=", intercept.x - global_position.x, " kpr_x=", global_position.x, " speed=", ball.linear_velocity.length(), " ttoi=", tt, " dist=", dball)
	if not ont:
		_reacting = false
		return
	if not _reacting:
		_reacting = true
		_react_left = FootballConstants.KEEPER_REACT
		_high_roll = -1   # свежий бросок «взять/пропустить» на этот удар
	_react_left -= delta
	if _react_left > 0.0:
		return
	# Мяч летит ВО ВРАТАРЯ (по горизонтали в пределах досягаемости) — нырок вбок не нужен,
	# ловим/пропускаем скриптованно, надёжно (без Area3D). Выше досягаемости прыжка → miss_top.
	var lateral := absf(intercept.x - global_position.x)
	var ttoi := KeeperLogic.time_to_intercept(ball.global_position, ball.linear_velocity, intercept)
	# Уже в створе перед мячом → ловим на месте (или пропускаем верхом). Упреждение: пока мяч
	# дальше окна CATCH_LEAD — стоим наготове (лицо к мячу уже задано выше), клип запускаем ровно
	# за CATCH_LEAD до подлёта, чтобы руки успели подняться (иначе catch_top срабатывал, когда мяч
	# уже у рук). Захват мяча всё равно по узкому KEEPER_REACH (см. _catching) — без «пылесоса».
	if lateral <= FootballConstants.KEEPER_REACH:
		if is_finite(ttoi) and ttoi > FootballConstants.KEEPER_CATCH_LEAD:
			return
		if _should_catch_high(intercept.y):
			print("[KEEPER] -> CENTRAL CATCH y=", intercept.y)
			_begin_central_catch(intercept.y)
		else:
			print("[KEEPER] -> MISS_TOP y=", intercept.y)
			_begin_miss_top()
		return
	# Успеваем добежать по линии до точки пересечения раньше мяча → выходим НАВСТРЕЧУ (скользим
	# к intercept.x), рефлекс/контакт поймает на подлёте. Иначе — нырок.
	var time_to_align := (lateral - FootballConstants.KEEPER_REACH) / FootballConstants.LOCO_TOP_SPEED
	if is_finite(ttoi) and time_to_align <= ttoi:
		var tx := clampf(intercept.x, -FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.GOAL_WIDTH * 0.5)
		m.set_move_intent(Vector3(signf(tx - global_position.x), 0.0, 0.0), 1.0)
		return
	var dec := KeeperLogic.save_decision(intercept, global_position,
		FootballConstants.KEEPER_REACH,
		FootballConstants.KEEPER_DIVE_RANGE + FootballConstants.KEEPER_ENGAGE_MARGIN,
		FootballConstants.KEEPER_HIGH_THRESHOLD)
	print("[KEEPER] -> DIVE action=", dec.action, " target=", dec.target, " (couldn't reach by line)")
	if dec.action == KeeperLogic.SaveAction.NONE:
		return  # совсем далеко — гол
	_begin_save(dec, ball.linear_velocity.length(), ttoi)


## Старт сейва: центр (CATCH/CATCH_TOP) — на месте (dive_vel≈0); угол — бросок к цели.
## ttoi — время до прилёта мяча: держим нырок минимум до него (+запас), иначе ранний нырок
## закончится раньше, чем мяч долетит, и вратарь встанет до сейва.
func _begin_save(dec: Dictionary, ball_speed: float, ttoi: float) -> void:
	_reacting = false
	_current_action = dec.action
	_state = State.DIVE
	var m := _motor()
	if m != null:
		m.set_control_locked(true)   # телом владеет наш move_and_collide (как подкат)
	var vis := _visual()
	var is_catch := _is_catch_action(dec.action)
	var is_high: bool = dec.action == KeeperLogic.SaveAction.DIVE_HIGH_L or dec.action == KeeperLogic.SaveAction.DIVE_HIGH_R
	var clip := _catch_clip_for_height(dec.target.y) if is_catch else _dive_clip_for(dec.target - global_position, is_high)
	# Клип нырка — фиксированная (натуральная) скорость, как в OpenSoccer; ловля на месте — 1.0.
	var spd := 1.0 if is_catch else FootballConstants.KEEPER_DIVE_ANIM_SPEED
	var clip_len := 0.0
	if vis != null:
		clip_len = vis.play_oneshot(clip, spd)
	# Держим нырок ровно на ФАКТИЧЕСКУЮ длительность клипа (длина/скорость), не сырую — иначе
	# анимация уже доиграла, а DIVE ещё тянется, и вратарь висит в последнем кадре («стойка
	# готовности»). Для медленного мяча — продлеваем до его прилёта (нужно для сейва).
	var anim_dur := (clip_len / spd) if spd > 0.01 else clip_len
	var hold_for := ttoi + 0.15 if is_finite(ttoi) else 0.3
	_dive_time_left = maxf(maxf(anim_dur, 0.3), hold_for)
	if is_catch:
		_dive_vel = Vector3.ZERO   # ловля на месте
	else:
		var target: Vector3 = dec.target
		target.x += randf_range(-1.0, 1.0) * FootballConstants.KEEPER_SAVE_ERROR
		var to := target - global_position
		# Импульс ПРОПОРЦИОНАЛЕН смещению (divevel = смещение × gain) — как OpenSoccer:
		# близкий/дальний нырок доезжают за ~одинаковое время → синхрон с фикс. клипом.
		# ТОЛЬКО горизонталь: прыжок вверх/опускание делает сам клип (вертикаль корня живая),
		# высоту мяча достаёт радиус сейв-зоны. Иначе физ-вертикаль + клип = двойная вертикаль/завис.
		_dive_vel = Vector3(to.x, 0.0, to.z) * FootballConstants.KEEPER_DIVE_GAIN
		_dive_vel = _dive_vel.limit_length(FootballConstants.KEEPER_DIVE_SPEED)


func _dive(delta: float) -> void:
	# Только горизонталь (вертикаль — в клипе). Тело держится на уровне газона.
	move_and_collide(_dive_vel * delta)
	_dive_vel.x *= FootballConstants.KEEPER_DIVE_DECAY
	_dive_vel.z *= FootballConstants.KEEPER_DIVE_DECAY
	global_position.y = _ground_y   # капсула не покидает газон — прыжок делает анимация
	# Геометрический контакт: мяч дотянулся до вратаря → ловим (по _current_action) или отбиваем.
	if ball.is_flight() and _catch_radius_hit():
		_resolve_dive_contact()
	_dive_time_left -= delta
	if _dive_time_left <= 0.0:
		if ball.has_method(&"is_caught") and ball.is_caught() and ball.dribbler == self:
			_to_hold()   # поймали в нырке — мяч в руках, держим и выносим
		else:
			_finish_dive()


## Мяч коснулся капсулы вратаря (зовёт match_manager вместо block_in_flight) — НАДЁЖНЫЙ триггер
## ловли/отбоя (физический контакт с continuous_cd, без туннелирования).
func on_ball_contact() -> void:
	print("[KEEPER] on_ball_contact state=", _state, " ball_y=", ball.global_position.y)
	if not ball.is_flight():
		return
	if _state == State.HOLD or _state == State.DISTRIBUTE:
		return
	if _pass_through:
		return
	if manager != null and manager.is_celebrating():
		return
	var by := ball.global_position.y
	if by > FootballConstants.KEEPER_JUMP_REACH:
		return  # слишком высоко — не берём (уйдёт в miss/гол)
	# Отбой во время нырка по заготовленной зоне; иначе — ловим в руки.
	if _state == State.DIVE and _current_action != KeeperLogic.SaveAction.NONE \
			and not KeeperLogic.resolve_save(_current_action, ball.linear_velocity.length(), FootballConstants.KEEPER_CATCH_MAX_SPEED):
		var out := ball.global_position - Vector3(0, 0, goal_line_z)
		out.y = 0.0
		ball.parry(out, FootballConstants.KEEPER_PARRY_DAMP)
		return
	ball.catch(self, hold_point)
	if _state != State.CATCHING and _state != State.DIVE:
		_begin_central_catch(by)


## Гравитация, которую испытывает мяч (для баллистического shot_intercept).
func _ball_gravity() -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return g * ball.gravity_scale


## Мяч летит К воротам (а не уходит/случайный)?
func _heading_at_goal() -> bool:
	var into := -1.0 if goal_line_z > 0.0 else 1.0
	return ball.linear_velocity.z * (-into) > 0.5


## Брать ли высокий центральный мяч? Ниже CERTAIN (2.0м) — всегда; выше JUMP_REACH (2.5м) — никогда;
## в полосе между ними — случайно с шансом KEEPER_HIGH_CATCH_CHANCE. Решение бросается ОДИН раз
## на удар и кэшируется (иначе вратарь переигрывал бы бросок каждый кадр). _high_roll сбрасывается
## при старте реакции на новый удар.
func _should_catch_high(y: float) -> bool:
	if y <= FootballConstants.KEEPER_HIGH_CATCH_CERTAIN:
		return true
	if y > FootballConstants.KEEPER_JUMP_REACH:
		return false
	if _high_roll < 0:
		_high_roll = 1 if randf() < FootballConstants.KEEPER_HIGH_CATCH_CHANCE else 0
	return _high_roll == 1


## Мяч в радиусе досягаемости вратаря (по горизонтали, ниже прыжка)? Геометрический детектор
## контакта вместо ненадёжной Area3D.
func _catch_radius_hit() -> bool:
	var flat := Vector2(ball.global_position.x - global_position.x, ball.global_position.z - global_position.z)
	return flat.length() <= FootballConstants.KEEPER_REACH \
		and ball.global_position.y <= FootballConstants.KEEPER_JUMP_REACH + 0.3


## Контакт в нырке: ловим (по заготовленной зоне) или отбиваем.
func _resolve_dive_contact() -> void:
	var is_catch := KeeperLogic.resolve_save(_current_action, ball.linear_velocity.length(),
		FootballConstants.KEEPER_CATCH_MAX_SPEED)
	if is_catch:
		ball.catch(self, hold_point)
	else:
		var out := ball.global_position - Vector3(0, 0, goal_line_z)
		out.y = 0.0
		ball.parry(out, FootballConstants.KEEPER_PARRY_DAMP)


## Конец нырка: без анимации вставания — сразу idle и назад на линию.
func _finish_dive() -> void:
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
	var vis := _visual()
	if vis != null:
		vis.recover()   # сразу в idle (без standing_up)
	_state = State.POSITION


## HOLD: подержать мяч в руках (idle_ball), затем перейти к выносу.
func _to_hold() -> void:
	print("[KEEPER] HOLD (caught, holding ball)")
	_state = State.HOLD
	_state_timer = FootballConstants.KEEPER_HOLD_TIME
	var m := _motor()
	if m != null:
		m.set_control_locked(true)   # держим мяч вкопанно, без дрейфа
	var vis := _visual()
	if vis != null:
		vis.play_oneshot(&"keeper_idle_ball")


func _hold(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_to_distribute()


func _to_distribute() -> void:
	print("[KEEPER] DISTRIBUTE (drop kick)")
	_state = State.DISTRIBUTE
	_distribute_fired = false
	_state_timer = 1.9   # страховка > длины клипа (1.6с) и контакта (1.25с): выбьем принудительно,
	                     # только если action_contact реально не пришёл
	var vis := _visual()
	if vis != null:
		vis.recover()                 # выйти из idle_ball one-shot в локомоцию-хаб
		vis.trigger("keeper_drop_kick")


func _distribute(delta: float) -> void:
	_state_timer -= delta
	# Страховка от зависания: сигнал касания не пришёл вовремя — выбиваем принудительно.
	if not _distribute_fired and _state_timer <= 0.0:
		print("[KEEPER] DISTRIBUTE fallback clear (no action_contact)")
		_do_clear()
	if _distribute_fired and ball.dribbler != self:
		print("[KEEPER] -> back to POSITION (cleared)")
		_state = State.POSITION


## Момент касания мяча ногой в drop kick → вынос в сторону центра поля.
func _on_visual_contact(action: String) -> void:
	if action != "keeper_drop_kick" or _state != State.DISTRIBUTE or _distribute_fired:
		return
	_do_clear()


## Выброс мяча в сторону центра поля (drop kick).
func _do_clear() -> void:
	_distribute_fired = true
	var out_z := signf(-goal_line_z)   # от ворот к центру поля
	var vel := Vector3(0, 0, out_z) * FootballConstants.KEEPER_CLEAR_SPEED + Vector3.UP * FootballConstants.KEEPER_CLEAR_LIFT
	if ball.dribbler == self or ball.is_caught():
		print("[KEEPER] clear! launch vel=", vel)
		ball.launch(vel)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)   # снова свободен — назад на линию
	_state = State.POSITION


func _is_catch_action(a: int) -> bool:
	return a == KeeperLogic.SaveAction.CATCH or a == KeeperLogic.SaveAction.CATCH_TOP


## Клип нырка по РЕАЛЬНОМУ facing вратаря: сторона (L/R) определяется его локальным «право»
## (basis.x), а не мировой осью X — иначе при смене ворот (вратарь смотрит в другую сторону)
## лево/право инвертируются, и поза нырка идёт не в ту сторону.
func _dive_clip_for(to: Vector3, is_high: bool) -> StringName:
	var right := global_transform.basis.x
	var to_right := right.dot(Vector3(to.x, 0.0, to.z))
	var r_side := to_right >= 0.0   # мяч со стороны правой руки вратаря
	if is_high:
		return &"keeper_diving_save_r" if r_side else &"keeper_diving_save_l"
	return &"keeper_body_block_r" if r_side else &"keeper_body_block_l"


## Клип ловли по высоте мяча: ноги → scoop, грудь → catch, голова → catch_head, выше головы → catch_top.
func _catch_clip_for_height(y: float) -> StringName:
	if y < FootballConstants.KEEPER_SCOOP_HEIGHT:
		return &"keeper_scoop"
	if y < FootballConstants.KEEPER_HIGH_THRESHOLD:
		return &"keeper_catch"
	if y < FootballConstants.KEEPER_HEAD_THRESHOLD:
		return &"keeper_catch_head"
	return &"keeper_catch_top"


## Скриптованная ловля мяча, летящего ВО ВРАТАРЯ: играем клип по высоте, подводимся по X к
## мячу и геометрически приклеиваем его к рукам, как только дотянулись (см. _catching).
func _begin_central_catch(y: float) -> void:
	_reacting = false   # сбросить реакцию, как _begin_save/_begin_miss_top: иначе после выноса
	                    # POSITION стартует с «дозревшим» таймером и ловит первый же кадр
	_pass_through = false
	_state = State.CATCHING
	var m := _motor()
	if m != null:
		m.set_control_locked(true)   # вкопанно, без дрейфа (выравнивание уже сделал come-to-meet)
	var vis := _visual()
	var l := 0.0
	if vis != null:
		l = vis.play_oneshot(_catch_clip_for_height(y))
	_state_timer = maxf(l, 0.4)


## Высокий центральный мяч мимо: тянемся вверх (miss_top) и пропускаем — мяч не ловим.
func _begin_miss_top() -> void:
	_reacting = false
	_pass_through = true
	_state = State.CATCHING
	var m := _motor()
	if m != null:
		m.set_control_locked(true)   # тянется вверх на месте, без дрейфа
	var vis := _visual()
	var l := 0.0
	if vis != null:
		l = vis.play_oneshot(&"keeper_miss_top")
	_state_timer = maxf(l, 0.3)


## Фаза ловли/промаха. miss_top — доигрываем и пропускаем (гол). Иначе: подводимся по X к мячу,
## геометрически приклеиваем его к рукам, как дотянулись; поймал → HOLD; мяч ушёл за линию → стойка.
func _catching(delta: float) -> void:
	_state_timer -= delta
	if _pass_through:
		var mm := _motor()
		if mm != null:
			mm.set_move_intent(Vector3.ZERO)   # miss_top на месте — иначе едет на устаревшем намерении
		if _state_timer <= 0.0:
			_pass_through = false
			_finish_dive()
		return
	# Лицом к мячу (мотор заблокирован — не двигаемся, чтобы не скользить под клипом ловли).
	var m := _motor()
	if m != null:
		var into := -1.0 if goal_line_z > 0.0 else 1.0
		m.set_face_direction(Vector3(ball.global_position.x - global_position.x, 0.0, into * 4.0))
	# Геометрический захват: мяч дотянулся → приклеиваем к рукам.
	if ball.is_flight() and _catch_radius_hit():
		ball.catch(self, hold_point)
	if ball.has_method(&"is_caught") and ball.is_caught() and ball.dribbler == self:
		if _state_timer <= 0.0:
			_to_hold()   # клип доиграл — держим мяч и выносим
		return
	# Не поймал: мяч пересёк линию (за спиной) или окно давно истекло → в стойку (гол).
	var into2 := -1.0 if goal_line_z > 0.0 else 1.0
	if (ball.global_position.z - goal_line_z) * into2 < 0.0 or _state_timer <= -1.5:
		_finish_dive()

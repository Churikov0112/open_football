extends Brain
## AI-вратарь: позиционирование на линии + сейв (ловля/нырок/отбой) + вынос мяча.
## Движение — через PlayerMotor; нырок — свой move_and_collide при заблокированном моторе
## (как подкат). Вся математика — в KeeperLogic (чистые функции).

@export var ball: RigidBody3D
var goal_line_z: float = 0.0
var save_area: Area3D
var hold_point: Node3D   # узел-«руки»: пойманный мяч приклеивается сюда
var manager: Node   # match_manager — для проверки празднования гола

enum State { POSITION, DIVE, CATCHING, HOLD, DISTRIBUTE, PLACING, CARRY, FIELD_PASS, THROWING, HANDS, OUTFIELD }
var _state: int = State.POSITION
# ВРЕМЕННЫЙ хардкод-сценарий раздачи «placing ball» (для теста полевой логики вратаря):
# HOLD → PLACING (ставит мяч рукой на газон) → CARRY (дриблинг 5м как полевой) → FIELD_PASS
# (пас 20м к центру как полевой) → POSITION. Заменяет keeper_pass/раскат (тот код сохранён).
var _place_fired: bool = false
var _carry_start: Vector3 = Vector3.ZERO
var _carry_wait: float = 0.0   # доигрываем клип опускания мяча перед стартом движения
var _field_pass_vel: Vector3 = Vector3.ZERO
var _field_pass_fired: bool = false
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

# HANDS-режим (мяч в руках, управляемый актёр — План 2).
var _hands_intent: KeeperHandsIntent = null
var _hands_presentation: SetPiecePresentation = null
var _hands_intent_override: KeeperHandsIntent = null   # тест инжектит фейк-интент, минуя диспетч
var _hands_take_control: bool = false
var _hands_timer: float = 0.0            # обратный отсчёт 6 секунд
var _hands_charging: bool = false
var _hands_charge: float = 0.0
var _hands_charge_action: int = KeeperHandsIntent.Action.NONE
var _hand_is_throw: bool = false         # true → бросок верхом (удержание), false → раскат низом (тап)
var _hand_target_pos: Vector3 = Vector3.ZERO   # точка адресата для handoff

# Пенальти-подрежим (Фаза A): держим центр, реактивный боковой сейв off; нырок — по команде.
var _penalty_mode: bool = false
var _freekick_mode: bool = false
var _goalkick_mode: bool = false
var _freekick_anchor: Vector3 = Vector3.ZERO
var _pen_struck: bool = false
var _penalty_step_lateral: float = 0.0   # последнее боковое намерение от контроллера (AIM)
var _penalty_target_x: float = 0.0       # интегрированная цель X по линии
var _penalty_frozen: bool = false        # X зафиксирован (разбег начался)


func _motor() -> PlayerMotor:
	return PlayerMotor.find_on(_body)


func _visual() -> PlayerVisual:
	for c in _body.get_children():
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
	_ground_y = _body.global_position.y   # запоминаем уровень газона (высоту стойки)
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
	# Удар от ворот: вратарь — марионетка контроллера (тот лочит мотор и ведёт разбег root-motion).
	# Собственную логику сейва/позиции глушим полностью.
	if _goalkick_mode:
		return
	# Празднование гола: новых сейвов/выносов не начинаем (иначе вратарь ловит осевший в сетке
	# мяч и выносит его уже ПОСЛЕ гола). Но ТЕКУЩИЙ нырок доигрываем до конца анимации —
	# не дёргаем в idle посреди прыжка.
	if manager != null and manager.is_celebrating():
		if _state == State.DIVE:
			_dive(delta)   # доигрываем нырок, idle придёт по завершении клипа
			return
		if _state in [State.HOLD, State.DISTRIBUTE, State.PLACING, State.CARRY, State.FIELD_PASS, State.THROWING]:
			# Страховка: не уносить пойманный/ведомый мяч в стойку — отпустить и в POSITION.
			if ball.dribbler == _body:
				ball.release_dribble()
			_finish_dive()   # мяч во время празднования не трогаем — в стойку
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
		State.PLACING:
			_placing(delta)
		State.CARRY:
			_carry(delta)
		State.FIELD_PASS:
			_field_pass(delta)
		State.THROWING:
			_throwing(delta)
		State.HANDS:
			_hands(delta)
		State.OUTFIELD:
			pass   # телом в OUTFIELD владеет менеджер (полевой путь); Задача 9


## Держим линию: X за мячом, лицом к мячу, лёгкий выход под угол. При ударе в створ —
## реагируем с задержкой, затем ловим на месте / стартуем нырок по таймингу.
func _position(delta: float) -> void:
	var m := _motor()
	if m == null:
		return
	if _penalty_mode:
		_penalty_hold(delta, m)
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
		print("[KEEPER] REFLEX hit: ball=", ball.global_position, " kpr=", _body.global_position, " y=", by)
		if _should_catch_high(by):
			ball.catch(_body, hold_point)
			_begin_central_catch(by)
		else:
			_begin_miss_top()
		return
	# Смотрим В ПОЛЕ (к бьющему), а не на мяч: иначе при ударе мимо/в створ вратарь
	# разворачивается вслед залетевшему мячу и ныряет спиной. Доминанта — направление поля,
	# с лёгким доворотом к X мяча.
	var into := -1.0 if goal_line_z > 0.0 else 1.0
	m.set_face_direction(Vector3(ball.global_position.x - _body.global_position.x, 0.0, into * 4.0))
	var target: Vector3
	if _freekick_mode:
		target = _freekick_anchor
	else:
		target = KeeperLogic.line_position(ball.global_position, goal_line_z, FootballConstants.GOAL_WIDTH * 0.5,
			FootballConstants.KEEPER_LINE_NARROW_GAIN, FootballConstants.KEEPER_MAX_OFF_LINE)
		# «Выход из ворот» (off-line advance) — ТОЛЬКО против реальной угрозы (мяч летит В створ
		# прямо сейчас), а не по голой дистанции мяча до линии. Раньше line_position реагировала
		# на любую близость мяча к линии — включая обычный пас между СВОИМИ игроками рядом со
		# штрафной (мяч ничем не угрожает воротам), и вратарь всё равно рвался вперёд на 2.5м.
		# Без угрозы держим X (следим за мячом по горизонтали) но Z фиксируем на линии ворот.
		if not (ball.is_flight() and _heading_at_goal()):
			target.z = goal_line_z + into * 0.5
	# База: вратарь-ИИ не покидает штрафную (фикс over-rush на шальной мяч рядом с боксом).
	target = KeeperPlayLogic.clamp_to_penalty_area(target, goal_line_z, into,
		FootballConstants.PENALTY_AREA_DEPTH, FootballConstants.PENALTY_AREA_WIDTH * 0.5)
	var to := target - _body.global_position
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
		var dball := ball.global_position.distance_to(_body.global_position)
		var tt := KeeperLogic.time_to_intercept(ball.global_position, ball.linear_velocity, intercept)
		print("[KEEPER] shot detected intercept=", intercept, " onTarget=", ont, " dx=", intercept.x - _body.global_position.x, " kpr_x=", _body.global_position.x, " speed=", ball.linear_velocity.length(), " ttoi=", tt, " dist=", dball)
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
	var lateral := absf(intercept.x - _body.global_position.x)
	var ttoi := KeeperLogic.time_to_intercept(ball.global_position, ball.linear_velocity, intercept)
	# Уже в створе перед мячом → ловим на месте (или пропускаем верхом). Упреждение: пока мяч
	# дальше окна CATCH_LEAD — стоим наготове (лицо к мячу уже задано выше), клип запускаем ровно
	# за CATCH_LEAD до подлёта, чтобы руки успели подняться (иначе catch_top срабатывал, когда мяч
	# уже у рук). Захват мяча всё равно по узкому KEEPER_REACH (см. _catching) — без «пылесоса».
	if lateral <= FootballConstants.KEEPER_REACH:
		# Тип действия решаем СРАЗУ (бросок кэшируется), чтобы выбрать своё упреждение: miss_top
		# (прыжок вверх) стартует раньше ловли — замах дольше.
		var will_catch := _should_catch_high(intercept.y)
		var lead: float = FootballConstants.KEEPER_CATCH_LEAD if will_catch else FootballConstants.KEEPER_MISS_LEAD
		if is_finite(ttoi) and ttoi > lead:
			return
		if will_catch:
			print("[KEEPER] -> CENTRAL CATCH y=", intercept.y)
			_begin_central_catch(intercept.y)
		else:
			print("[KEEPER] -> MISS_TOP y=", intercept.y)
			_begin_miss_top()
		return
	# Шагом (выход по линии) выходим ТОЛЬКО за близким мячом; на дальний вбок (угол) — НЫРЯЕМ,
	# даже если формально успели бы дошагать (зрелищнее, и дайв-рэндж покрывает весь створ).
	var time_to_align := (lateral - FootballConstants.KEEPER_REACH) / FootballConstants.LOCO_TOP_SPEED
	if lateral <= FootballConstants.KEEPER_SLIDE_MAX_LATERAL and is_finite(ttoi) and time_to_align <= ttoi:
		var tx := clampf(intercept.x, -FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.GOAL_WIDTH * 0.5)
		m.set_move_intent(Vector3(signf(tx - _body.global_position.x), 0.0, 0.0), 1.0)
		return
	var dec := KeeperLogic.save_decision(intercept, _body.global_position,
		FootballConstants.KEEPER_REACH,
		FootballConstants.KEEPER_DIVE_RANGE + FootballConstants.KEEPER_ENGAGE_MARGIN,
		FootballConstants.KEEPER_HIGH_THRESHOLD)
	print("[KEEPER] -> DIVE action=", dec.action, " target=", dec.target, " (couldn't reach by line)")
	if dec.action == KeeperLogic.SaveAction.NONE:
		return  # совсем далеко — гол
	_begin_save(dec, ball.linear_velocity.length(), ttoi)


## Пенальти-подрежим: держим центр линии, лицом в поле, боковой РЕАКТИВНЫЙ сейв ВЫКЛ. Рефлекс
## центрального мяча (ловля/промах по высоте прилёта) остаётся — им решается центральный удар,
## если вратарь остался в центре.
## Режим штрафного: держим оптимальную позицию-якорь, реактивный сейв ОСТАЁТСЯ включён
## (в отличие от пенальти-режима — вратарь видит мяч). Позицию считает FreeKickLogic.keeper_position.
func set_freekick_anchor(pos: Vector3) -> void:
	_freekick_mode = true
	_freekick_anchor = pos
	_penalty_mode = false
	# Чистый сброс из ЛЮБОГО состояния (нырок/ловля/раздача/вне линии) — как в пенальти-режиме,
	# но реактивный сейв остаётся ВКЛ. И сразу телепортируем на якорь (в ворота с самого начала).
	_pen_struck = false
	_reacting = false
	_pass_through = false
	_current_action = KeeperLogic.SaveAction.NONE
	_state = State.POSITION
	if ball != null and is_instance_valid(ball) and ball.dribbler == _body:
		ball.release_dribble()
	_body.global_position = Vector3(pos.x, _ground_y, pos.z)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
		m.set_move_intent(Vector3.ZERO)
	var vis := _visual()
	if vis != null:
		vis.recover()   # выйти из любого one-shot в локомоцию-хаб (idle)
		vis.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)


func clear_freekick_anchor() -> void:
	_freekick_mode = false


func set_penalty_mode(on: bool) -> void:
	_penalty_mode = on
	if on:
		# Чистый сброс из ЛЮБОГО состояния (нырок/ловля/раздача/вне линии): иначе при старте
		# пенальти из середины другого действия вратарь стоит криво / вне линии / держит мяч.
		_pen_struck = false
		_reacting = false
		_pass_through = false
		_penalty_step_lateral = 0.0
		_penalty_target_x = 0.0
		_penalty_frozen = false
		_current_action = KeeperLogic.SaveAction.NONE
		_state = State.POSITION
		if ball != null and is_instance_valid(ball) and ball.dribbler == _body:
			ball.release_dribble()
		# На линию по центру створа (как в _setup_keeper).
		var into := 1.0 if goal_line_z < 0.0 else -1.0
		_body.global_position = Vector3(0.0, _ground_y, goal_line_z + into * 0.5)
		_body.velocity = Vector3.ZERO   # гасим остаточный импульс (вратарь мог выходить/двигаться), иначе унесёт с линии
		var m := _motor()
		if m != null:
			m.set_control_locked(false)
			m.set_move_intent(Vector3.ZERO)
		var vis := _visual()
		if vis != null:
			vis.recover()   # выйти из любого one-shot (нырок/idle_ball) в локомоцию-хаб
			vis.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)


## Пассивный режим бьющего для удара от ворот. Тело/разбег/удар ведёт GoalKickController;
## вратарь чистит своё состояние, отпускает мяч и не запускает собственную логику. При off —
## возврат в POSITION (снова держит линию). НЕ телепортирует тело — расстановку делает контроллер.
func set_goalkick_mode(on: bool) -> void:
	_goalkick_mode = on
	if on:
		_reacting = false
		_pass_through = false
		_current_action = KeeperLogic.SaveAction.NONE
		_state = State.POSITION
		if ball != null and is_instance_valid(ball) and ball.dribbler == _body:
			ball.release_dribble()
		var vis := _visual()
		if vis != null:
			vis.recover()   # выйти из любого one-shot (нырок/idle_ball) в локомоцию
			# Обычный idle, не вратарская стойка — вратарь тут ведёт себя как полевой бьющий
			# (разбег/удар как у штрафного/пенальти), вратарская стойка тут неуместна.
			vis.set_locomotion_style(PlayerVisual.LOCO_STYLE_NORMAL)
	else:
		_state = State.POSITION


## Слепой нырок пенальти по выбранной зоне. Угловые — существующий _begin_save (клип/контакт/отбой
## как с игры); CENTER — остаёмся в центре, центральный рефлекс в _penalty_hold решит по высоте.
## AIM-позиционирование: контроллер каждый кадр шлёт боковое намерение стика (Human) или 0 (ИИ).
func set_penalty_step(lateral: float) -> void:
	_penalty_step_lateral = lateral

## Старт разбега бьющего: фиксируем X вратаря на линии (дальше стик = направление прыжка).
func freeze_penalty_position() -> void:
	_penalty_frozen = true


func begin_penalty_dive(zone: int) -> void:
	_pen_struck = true
	if zone == PenaltyLogic.Zone.CENTER:
		return  # остаёмся по центру; исход решит рефлекс, затем авто-сброс _penalty_mode
	_penalty_mode = false
	var action := _pen_zone_to_action(zone)
	if action == KeeperLogic.SaveAction.NONE:
		return
	var target := PenaltyLogic.zone_target(zone, 0.0, FootballConstants.GOAL_WIDTH * 0.5,
		FootballConstants.PEN_KEEPER_DIVE_LOW_Y, FootballConstants.PEN_KEEPER_DIVE_HIGH_Y,
		FootballConstants.PEN_KEEPER_DIVE_LATERAL, goal_line_z)
	# Слепой нырок — реальной ttoi нет (INF): _begin_save держит нырок по длине клипа.
	_begin_save({"action": action, "target": target}, ball.linear_velocity.length(), INF)


func _pen_zone_to_action(zone: int) -> int:
	match zone:
		PenaltyLogic.Zone.LOW_L:
			return KeeperLogic.SaveAction.DIVE_LOW_L
		PenaltyLogic.Zone.LOW_R:
			return KeeperLogic.SaveAction.DIVE_LOW_R
		PenaltyLogic.Zone.HIGH_L:
			return KeeperLogic.SaveAction.DIVE_HIGH_L
		PenaltyLogic.Zone.HIGH_R:
			return KeeperLogic.SaveAction.DIVE_HIGH_R
	return KeeperLogic.SaveAction.NONE


## Держим центр линии лицом в поле; боковой реактивный сейв не запускаем. Рефлекс центрального
## мяча решает ловлю/промах по высоте прилёта (как в обычном _position). После удара, когда угроза
## миновала (пойман/за линией/улетел), авто-снимаем пенальти-режим → обычная игра.
func _penalty_hold(delta: float, m: PlayerMotor) -> void:
	var into := -1.0 if goal_line_z > 0.0 else 1.0
	m.set_face_direction(Vector3(ball.global_position.x - _body.global_position.x, 0.0, into * 4.0))
	# Держим ПОЛНУЮ позицию на линии — центр створа (X=0) И глубину линии (Z=goal_line_z+into*0.5,
	# та же точка, куда телепортирует set_penalty_mode). Раньше корректировали только X: если вратарь
	# в момент нажатия P выходил навстречу удару, остаточная Z-скорость уносила его вперёд с линии, и
	# вернуть было некому (Z не правился) — «вратарь не на линии». Теперь возвращаем по обеим осям.
	var anchor_z := goal_line_z + into * 0.5
	# До заморозки: цель X ползёт вбок по стику (приставные шаги), кламп в пределах створа.
	if not _penalty_frozen:
		_penalty_target_x += _penalty_step_lateral * FootballConstants.KEEPER_PEN_STEP_SPEED * delta
		var lim := FootballConstants.GOAL_WIDTH * 0.5 - FootballConstants.KEEPER_PEN_STEP_MARGIN
		_penalty_target_x = clampf(_penalty_target_x, -lim, lim)
	var to := Vector3(_penalty_target_x - _body.global_position.x, 0.0, anchor_z - _body.global_position.z)
	var d := to.length()
	if d > 0.15:
		# Проп. скорость: тормозим у якоря, чтобы инерция мотора не проносила вратаря сквозь линию
		# (иначе — качание туда-сюда). Далеко — полный ход, близко — плавно к нулю.
		m.set_move_intent(to / d, clampf(d * 0.7, 0.15, 1.0))
	else:
		m.set_move_intent(Vector3.ZERO)
	# Рефлекс центрального мяча: по высоте прилёта — scoop/catch/catch_head/catch_top / miss_top.
	if ball.is_flight() and _heading_at_goal() and _catch_radius_hit():
		var by := ball.global_position.y
		if _should_catch_high(by):
			ball.catch(_body, hold_point)
			_begin_central_catch(by)
		else:
			_begin_miss_top()
		return
	# Авто-сброс режима после удара, когда мяч уже не угроза.
	if _pen_struck:
		var crossed := (ball.global_position.z - goal_line_z) * into < 0.0
		if ball.is_caught() or crossed or (ball.is_flight() and not _heading_at_goal()):
			_penalty_mode = false


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
	var clip := _catch_clip_for_height(dec.target.y) if is_catch else _dive_clip_for(dec.target - _body.global_position, is_high)
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
		var to := target - _body.global_position
		# Импульс ПРОПОРЦИОНАЛЕН смещению (divevel = смещение × gain) — как OpenSoccer:
		# близкий/дальний нырок доезжают за ~одинаковое время → синхрон с фикс. клипом.
		# ТОЛЬКО горизонталь: прыжок вверх/опускание делает сам клип (вертикаль корня живая),
		# высоту мяча достаёт радиус сейв-зоны. Иначе физ-вертикаль + клип = двойная вертикаль/завис.
		_dive_vel = Vector3(to.x, 0.0, to.z) * FootballConstants.KEEPER_DIVE_GAIN
		_dive_vel = _dive_vel.limit_length(FootballConstants.KEEPER_DIVE_SPEED)


func _dive(delta: float) -> void:
	# Только горизонталь (вертикаль — в клипе). Тело держится на уровне газона.
	_body.move_and_collide(_dive_vel * delta)
	_dive_vel.x *= FootballConstants.KEEPER_DIVE_DECAY
	_dive_vel.z *= FootballConstants.KEEPER_DIVE_DECAY
	_body.global_position.y = _ground_y   # капсула не покидает газон — прыжок делает анимация
	# Геометрический контакт: мяч дотянулся до вратаря → ловим (по _current_action) или отбиваем.
	if ball.is_flight() and _catch_radius_hit():
		_resolve_dive_contact()
	_dive_time_left -= delta
	if _dive_time_left <= 0.0:
		if ball.has_method(&"is_caught") and ball.is_caught() and ball.dribbler == _body:
			_enter_hands()   # поймали в нырке — мяч в руках, управляемый актёр (План 2)
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
	ball.catch(_body, hold_point)
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
	var flat := Vector2(ball.global_position.x - _body.global_position.x, ball.global_position.z - _body.global_position.z)
	return flat.length() <= FootballConstants.KEEPER_REACH \
		and ball.global_position.y <= FootballConstants.KEEPER_JUMP_REACH + 0.3


## Контакт в нырке: ловим (по заготовленной зоне) или отбиваем.
func _resolve_dive_contact() -> void:
	var is_catch := KeeperLogic.resolve_save(_current_action, ball.linear_velocity.length(),
		FootballConstants.KEEPER_CATCH_MAX_SPEED)
	if is_catch:
		ball.catch(_body, hold_point)
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
		# ВРЕМЕННО активна раздача БРОСКОМ ВЕРХОМ (_to_overhand_throw). Сценарии placing-ball
		# (_to_placing) и раскат низом (_to_distribute) сохранены, но не вызываются.
		_to_overhand_throw()


## Мяч пойман → HANDS: спрашиваем менеджера, кто ведёт (диспетч), берём мяч в руки, стартуем 6 сек.
## Заменяет авто-цепочку _to_hold→_hold→_to_overhand_throw для управляемого вратаря.
func _enter_hands() -> void:
	_state = State.HANDS
	_hands_timer = FootballConstants.KEEPER_SIX_SECOND_TIME
	_hands_charging = false
	_hands_charge = 0.0
	_pass_through = false
	# Источник намерения + презентация: тест инжектит override; иначе диспетч менеджера.
	if _hands_intent_override != null:
		_hands_intent = _hands_intent_override
		_hands_presentation = SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
		_hands_take_control = true
	elif manager != null and manager.has_method(&"_keeper_hands_dispatch"):
		var d: Dictionary = manager._keeper_hands_dispatch(_body)
		_hands_intent = d.get("intent", null)
		_hands_presentation = d.get("presentation", null)
		_hands_take_control = d.get("take_control", false)
	# Управление человеку: keeper становится controlled_player (голубой маркер над ним сам появится).
	if _hands_take_control and manager != null and manager.has_method(&"assign_controlled_player"):
		manager.assign_controlled_player(_body)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)   # человек/ИИ теперь ДВИГАЕТ вратаря в штрафной (не вкопанно)
	var vis := _visual()
	if vis != null:
		vis.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)
		vis.play_oneshot(&"keeper_idle_ball")   # поза удержания (carry-бленд бега — План 3)


## Вратарь сейчас владеет мячом в руках (HANDS)? Менеджер использует, чтобы НЕ двигать его своим
## полевым вводом (в HANDS телом владеет keeper_ai через KeeperHandsIntent).
func is_hands_active() -> bool:
	return _state == State.HANDS


## Текущий заряд дистанции (A/B) как доля [0..1], либо -1 если не заряжает. Менеджер рисует power-bar.
func hands_charge_ratio() -> float:
	if not _hands_charging:
		return -1.0
	return clampf(_hands_charge / FootballConstants.KEEPER_DIST_CHARGE_MAX, 0.0, 1.0)


func _hands(delta: float) -> void:
	_hands_timer -= delta
	var m := _motor()
	if m == null or _hands_intent == null:
		return
	# Движение в штрафной по move_axis, преобразованному камера-относительно НЕ нужно: вратарь и
	# камера на одной стороне; берём оси мира (x=боковое, y=вглубь поля). Кламп цели в штрафную.
	var mv := _hands_intent.move_axis()
	if mv.length() > 0.15:
		var into := -1.0 if goal_line_z > 0.0 else 1.0
		var world_dir := Vector3(mv.x, 0.0, -mv.y * into)   # стик «вверх» = вглубь поля (into)
		# Предиктивный кламп: не даём цели-намерению вывести за штрафную.
		var next_pos := _body.global_position + world_dir.normalized() * 1.0
		var clamped := KeeperPlayLogic.clamp_to_penalty_area(next_pos, goal_line_z, into,
			FootballConstants.PENALTY_AREA_DEPTH, FootballConstants.PENALTY_AREA_WIDTH * 0.5)
		var allow := clamped - _body.global_position
		allow.y = 0.0
		if allow.length() > 0.05:
			m.set_move_intent(allow.normalized(), FootballConstants.KEEPER_HANDS_MOVE_SPEED)
		else:
			m.set_move_intent(Vector3.ZERO)
		m.set_face_direction(world_dir)
	else:
		m.set_move_intent(Vector3.ZERO)
	# Жёсткий кламп позиции (страховка от инерции мотора за пределы штрафной).
	var into2 := -1.0 if goal_line_z > 0.0 else 1.0
	var boxed := KeeperPlayLogic.clamp_to_penalty_area(_body.global_position, goal_line_z, into2,
		FootballConstants.PENALTY_AREA_DEPTH, FootballConstants.PENALTY_AREA_WIDTH * 0.5)
	_body.global_position.x = boxed.x
	_body.global_position.z = boxed.z
	# Заряд-как-таймер: HAND и CLEAR_DIRECTED заряжаемые; CLEAR_CENTER/DROP — мгновенные.
	var act := _hands_intent.held_action()
	var chargeable: bool = act == KeeperHandsIntent.Action.HAND or act == KeeperHandsIntent.Action.CLEAR_DIRECTED
	if chargeable:
		_hands_charging = true
		_hands_charge_action = act
		_hands_charge = minf(_hands_charge + delta, FootballConstants.KEEPER_DIST_CHARGE_MAX)
	elif _hands_charging:
		# Отпустили заряжаемую → выпуск по накопленному заряду (Задачи 5/7 реализуют _fire_hands).
		var ratio := clampf(_hands_charge / FootballConstants.KEEPER_DIST_CHARGE_MAX, 0.0, 1.0)
		_hands_charging = false
		_fire_hands(_hands_charge_action, ratio)
		return
	elif act == KeeperHandsIntent.Action.CLEAR_CENTER:
		_fire_hands(act, 0.0)
		return
	elif act == KeeperHandsIntent.Action.DROP:
		_fire_hands(act, 0.0)
		return


## Выпуск вратарской раздачи по действию. Ветки X/B/Y наполняются в Задачах 6–9.
func _fire_hands(action: int, ratio: float) -> void:
	match action:
		KeeperHandsIntent.Action.HAND:
			_begin_hand(ratio)
		KeeperHandsIntent.Action.CLEAR_CENTER:
			_do_center_clear()
		# CLEAR_DIRECTED — Задача 7; DROP — Задача 9.
		_:
			print("[KEEPER] _fire_hands unhandled action=", action)


## Раздача рукой: тап (заряд < порога) = раскат низом ближнему; удержание = бросок верхом дальнему.
## Автонаведение по прицелу среди team_1-своих; банд дистанции растёт с зарядом.
func _begin_hand(ratio: float) -> void:
	var charge_time := ratio * FootballConstants.KEEPER_DIST_CHARGE_MAX
	_hand_is_throw = charge_time >= FootballConstants.KEEPER_HAND_THROW_CHARGE
	# Кандидаты — свои полевые (та же команда, что и вратарь), исключая себя и второго вратаря.
	# Прицел — по aim_axis. (my_group выводим из группы тела, не из хардкода team_1.)
	var my_group := &"team_1" if _body.is_in_group("team_1") else &"team_2"
	var mate_pos: Array = []
	for n in _body.get_tree().get_nodes_in_group(my_group):
		if n == _body or not is_instance_valid(n) or n.is_in_group("role_gk"):
			continue
		mate_pos.append(n.global_position)
	var aim := _hands_intent.aim_axis()
	var into := signf(-goal_line_z)
	var aim_dir := Vector3(aim.x, 0.0, -aim.y * into)
	if aim_dir.length() < 0.01:
		aim_dir = Vector3(0.0, 0.0, into)   # нет прицела → в поле
	aim_dir = aim_dir.normalized()
	var idx := KeeperPlayLogic.select_hand_target(_body.global_position, aim_dir, mate_pos, ratio,
		FootballConstants.KEEPER_HAND_ROLL_DIST, FootballConstants.KEEPER_HAND_THROW_DIST)
	if idx >= 0:
		_hand_target_pos = mate_pos[idx]
	else:
		# Фолбэк: точка по прицелу на дистанцию по банду (раскат/бросок).
		var dist := FootballConstants.KEEPER_HAND_THROW_DIST if _hand_is_throw else FootballConstants.KEEPER_HAND_ROLL_DIST
		_hand_target_pos = _body.global_position + aim_dir * dist
	_state = State.THROWING
	_distribute_fired = false
	_state_timer = 1.3
	var m := _motor()
	if m != null:
		m.set_control_locked(true)
	var vis := _visual()
	var clip := &"keeper_overhand_throw" if _hand_is_throw else &"keeper_pass"
	if vis == null or not vis.trigger(clip):
		_do_hand_release()   # фолбэк без анимации


## Выпуск по action_contact клипа руки: бросок верхом (дуга) или раскат низом (flat), к _hand_target_pos.
func _do_hand_release() -> void:
	if _distribute_fired:
		return
	_distribute_fired = true
	if ball.dribbler == _body or ball.is_caught():
		var from := _body.global_position
		var flat_to := Vector3(_hand_target_pos.x, from.y, _hand_target_pos.z)
		var dist := Vector3(flat_to.x - from.x, 0.0, flat_to.z - from.z).length()
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		if _hand_is_throw:
			# Бросок верхом: дуга через launch_lob-стиль (как _do_overhand_throw), драг-поправка.
			var g := _ball_gravity()
			var vy := sqrt(2.0 * g * FootballConstants.KEEPER_THROW_PEAK)
			var flight_t := 2.0 * vy / g
			var dir := Vector3(flat_to.x - from.x, 0.0, flat_to.z - from.z)
			dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, signf(-goal_line_z))
			var hspeed := KeeperLogic.drag_horizontal_speed(dist, flight_t, ball.drag_factor, dt)
			ball.launch(dir * hspeed + Vector3.UP * vy)
		else:
			# Раскат низом: мяч с руки на газон, катится к цели (flat), скорость из драга.
			var speed := KeeperLogic.roll_speed(maxf(dist, 1.0), ball.drag_factor, dt)
			var dir := Vector3(flat_to.x - from.x, 0.0, flat_to.z - from.z)
			dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, signf(-goal_line_z))
			var bp := ball.global_position
			ball.global_position = Vector3(bp.x, FootballConstants.BALL_RADIUS + 0.02, bp.z)
			ball.launch(dir * speed, true)
	# Управление адресату (как приём паса).
	if manager != null and manager.has_method(&"keeper_handoff_control"):
		manager.keeper_handoff_control(_hand_target_pos)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
	_hand_target_pos = Vector3.ZERO
	_state = State.POSITION


## Вынос ногой к центру поля (drop-kick), фикс-сильно. Управление — ближайшему team_1 у приземления.
func _do_center_clear() -> void:
	var into := signf(-goal_line_z)
	var vel := KeeperPlayLogic.clear_center_vector(into, FootballConstants.KEEPER_CLEAR_SPEED,
		FootballConstants.KEEPER_CLEAR_LIFT)
	var from := _body.global_position
	if ball.dribbler == _body or ball.is_caught():
		var bp := ball.global_position
		ball.global_position = Vector3(bp.x, FootballConstants.BALL_RADIUS + 0.3, bp.z)
		ball.launch(vel)
	# Точка приземления (грубо): по дальности выноса вдоль into.
	var land := from + Vector3(0.0, 0.0, into) * FootballConstants.KEEPER_THROW_DISTANCE
	if manager != null and manager.has_method(&"keeper_handoff_control"):
		manager.keeper_handoff_control(land)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
	var vis := _visual()
	if vis != null:
		vis.trigger("keeper_drop_kick")   # визуал выноса (мяч уже запущен — клип косметический)
	_state = State.POSITION


# ─────────────────────────────────────────────────────────────────────────────
# АКТИВНАЯ раздача: бросок мяча ВЕРХОМ правой рукой (по аналогии с раскатом низом keeper_pass,
# но по дуге). Мяч приклеен к руке до выпуска на замахе, затем летит навесом к центру поля.
# ─────────────────────────────────────────────────────────────────────────────

## Бросок верхом: играем keeper_overhand_throw, мяч ОСТАЁТСЯ приклеен к правой руке (CAUGHT),
## на contact (~0.65с) выпускается по дуге к центру поля.
func _to_overhand_throw() -> void:
	print("[KEEPER] THROWING (overhand throw)")
	_state = State.THROWING
	_distribute_fired = false
	_state_timer = 1.3   # страховка > длины клипа (0.97с) и контакта (0.65с)
	var m := _motor()
	if m != null:
		m.set_control_locked(true)   # стоит на месте, бросает
	var vis := _visual()
	if vis != null:
		vis.recover()                 # выйти из idle_ball one-shot в локомоцию-хаб
		vis.trigger("keeper_overhand_throw")


func _throwing(delta: float) -> void:
	_state_timer -= delta
	# Страховка: contact не пришёл — всё равно бросаем.
	if not _distribute_fired and _state_timer <= 0.0:
		print("[KEEPER] THROWING fallback (no action_contact)")
		_do_overhand_throw()


## Выпуск мяча из руки по дуге (contact keeper_overhand_throw): навес к центру поля через
## PassSystem.launch_lob (та же математика, что у полевого лоба). Затем свободен → POSITION.
func _do_overhand_throw() -> void:
	if _distribute_fired:
		return
	_distribute_fired = true
	if ball.dribbler == _body or ball.is_caught():
		var into := signf(-goal_line_z)   # от ворот в поле (к центру)
		var g := _ball_gravity()
		# Дуга: vy из высоты пика; время полёта T до возврата на ту же высоту.
		var vy := sqrt(2.0 * g * FootballConstants.KEEPER_THROW_PEAK)
		var flight_t := 2.0 * vy / g
		# Горизонталь с поправкой на драг мяча, чтобы навес реально долетел до дистанции.
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		var hspeed := KeeperLogic.drag_horizontal_speed(FootballConstants.KEEPER_THROW_DISTANCE, flight_t, ball.drag_factor, dt)
		var vel := Vector3(0.0, 0.0, into) * hspeed + Vector3.UP * vy
		print("[KEEPER] throw! vel=", vel, " hspeed=", hspeed, " vy=", vy)
		ball.launch(vel)   # дуга (flat=false) — навес
	var m := _motor()
	if m != null:
		m.set_control_locked(false)   # снова свободен — назад на линию
	_state = State.POSITION


# ─────────────────────────────────────────────────────────────────────────────
# ВРЕМЕННЫЙ хардкод-сценарий «placing ball» → полевой дриблинг → полевой пас.
# Не боевая механика вратаря, а тест переиспользования полевой логики. Направление —
# прямо в поле (+into), только для проверки.
# ─────────────────────────────────────────────────────────────────────────────

## Постановка мяча рукой на газон: играем keeper_placing_ball, мяч ОСТАЁТСЯ приклеен к руке
## (CAUGHT) — клип сам опускает руку и ставит мяч к ногам. На contact (0.95с) передаём в дриблинг.
func _to_placing() -> void:
	print("[KEEPER] PLACING (placing ball)")
	_state = State.PLACING
	_place_fired = false
	_state_timer = 1.6   # страховка > длины клипа (1.17с) и контакта (0.95с)
	var m := _motor()
	if m != null:
		m.set_control_locked(true)   # стоит на месте, ставит мяч
	var vis := _visual()
	if vis != null:
		vis.recover()                 # выйти из idle_ball one-shot в локомоцию-хаб
		vis.trigger("keeper_placing_ball")


func _placing(delta: float) -> void:
	_state_timer -= delta
	# Страховка: contact не пришёл — всё равно передаём мяч в дриблинг.
	if not _place_fired and _state_timer <= 0.0:
		print("[KEEPER] PLACING fallback trap (no action_contact)")
		_begin_carry()


## Мяч поставлен на газон (contact keeper_placing_ball) → передаём из рук в дриблинг у ног.
## Движение НЕ начинаем сразу: держим паузу _carry_wait, пока клип опускания мяча доиграет
## до конца (иначе вратарь трогается с места ещё в анимации постановки).
func _begin_carry() -> void:
	if _place_fired:
		return
	_place_fired = true
	# Из рук (CAUGHT) прямо в дриблинг (TRAPPED), force=true — мимо кулдаунов; мяч уже у ног.
	ball.set_dribbler(_body, true)
	_state = State.CARRY
	_carry_wait = 0.25   # остаток клипа keeper_placing_ball после contact (0.95с) до lock (1.17с)
	print("[KEEPER] CARRY wait (ball placed, finishing anim)")
	var m := _motor()
	if m != null:
		m.set_control_locked(true)          # ещё стоим — анимация постановки доигрывает
	var vis := _visual()
	if vis != null:
		vis.set_locomotion_style(PlayerVisual.LOCO_STYLE_NORMAL)   # обычный бег, не вратарский


## Дриблинг 1:1 как полевой: motor ведёт корпус, ball_controller ведёт мяч lead-follow.
## Фаза 1 — стоим, пока доигрывает клип опускания мяча; фаза 2 — движение до KEEPER_PLACE_DRIBBLE_DIST.
func _carry(delta: float) -> void:
	var m := _motor()
	# Фаза 1: анимация опускания ещё доигрывает — стоим на месте.
	if _carry_wait > 0.0:
		_carry_wait -= delta
		if m != null:
			m.set_move_intent(Vector3.ZERO)
		if _carry_wait <= 0.0:
			if m != null:
				m.set_control_locked(false)   # клип кончился — свободен, стартуем движение
			_carry_start = _body.global_position    # отсчёт дистанции от точки старта движения
			print("[KEEPER] CARRY move (start=", _carry_start, ")")
		return
	# Фаза 2: движение вперёд + дриблинг.
	var into := signf(-goal_line_z)   # от ворот в поле (к центру)
	var dir := Vector3(0.0, 0.0, into)
	if m != null:
		m.set_face_direction(Vector3.ZERO)   # полевой режим: корпус смотрит по движению
		m.set_move_intent(dir, 1.0)
	# Мяч потерян (отобрали/улетел) — не зависаем, назад в стойку.
	if ball.dribbler != _body:
		_finish_dive()
		return
	if _body.global_position.distance_to(_carry_start) >= FootballConstants.KEEPER_PLACE_DRIBBLE_DIST:
		_begin_field_pass()


## Пас 1:1 как полевой: считаем вектор (PassSystem), играем клип «pass» и выпускаем мяч ПО КОНТАКТУ
## анимации (как commit-action полевого), а не мгновенно. Мяч ждёт у ног (suppress), корпус стоит.
func _begin_field_pass() -> void:
	_state = State.FIELD_PASS
	_field_pass_fired = false
	_state_timer = 1.1   # страховка > contact (0.6с) кастомного тайминга keeper_field_pass
	var into := signf(-goal_line_z)
	var from := ball.global_position
	var to := from + Vector3(0.0, 0.0, into) * FootballConstants.KEEPER_PASS_DISTANCE
	var speed := PassSystem.ground_pass_speed(
		from.distance_to(to), 0.7,
		FootballConstants.PASS_GROUND_MIN_TRAVEL_TIME, FootballConstants.PASS_GROUND_MAX_TRAVEL_TIME,
		FootballConstants.PASS_GROUND_MIN_SPEED, FootballConstants.PASS_GROUND_MAX_SPEED)
	_field_pass_vel = PassSystem.launch_ground(from, to, speed)
	print("[KEEPER] FIELD PASS windup speed=", speed, " to=", to)
	var m := _motor()
	if m != null:
		m.set_control_locked(true)                       # стоим, играем пас
		m.set_move_intent(Vector3.ZERO)
		m.set_face_direction(Vector3(0.0, 0.0, into))    # лицом по направлению паса
	if ball.has_method(&"set_dribble_suppressed"):
		ball.set_dribble_suppressed(true)                # мяч ждёт у ног — одно касание = пас
	var vis := _visual()
	if vis == null or not vis.trigger("keeper_field_pass"):
		_do_field_pass_launch()                          # фолбэк без анимации


func _field_pass(delta: float) -> void:
	_state_timer -= delta
	if not _field_pass_fired and _state_timer <= 0.0:
		print("[KEEPER] FIELD PASS fallback launch (no action_contact)")
		_do_field_pass_launch()


## Контакт анимации паса → выпускаем мяч заготовленным вектором, затем свободен → POSITION.
func _do_field_pass_launch() -> void:
	if _field_pass_fired:
		return
	_field_pass_fired = true
	if ball.dribbler == _body:
		print("[KEEPER] FIELD PASS launch vel=", _field_pass_vel)
		ball.launch(_field_pass_vel)
	var into := signf(-goal_line_z)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
		m.set_face_direction(Vector3(0.0, 0.0, into))   # снова вратарский режим (лицом в поле)
	_state = State.POSITION


func _to_distribute() -> void:
	print("[KEEPER] DISTRIBUTE (pass roll)")
	_state = State.DISTRIBUTE
	_distribute_fired = false
	_state_timer = 1.9   # страховка > длины клипа (1.4с) и контакта (0.8с): раскатим принудительно,
	                     # только если action_contact реально не пришёл
	var vis := _visual()
	if vis != null:
		vis.recover()                 # выйти из idle_ball one-shot в локомоцию-хаб
		# ВРЕМЕННО: раздача пасом-раскатом вместо выноса ногой (drop_kick-код сохранён — _do_clear).
		vis.trigger("keeper_pass")


func _distribute(delta: float) -> void:
	_state_timer -= delta
	# Страховка от зависания: сигнал касания не пришёл вовремя — раскатываем принудительно.
	if not _distribute_fired and _state_timer <= 0.0:
		print("[KEEPER] DISTRIBUTE fallback roll (no action_contact)")
		_do_pass_roll()
	if _distribute_fired and ball.dribbler != _body:
		print("[KEEPER] -> back to POSITION (cleared)")
		_state = State.POSITION


## Момент касания в раздаче: placing_ball (ставит мяч → дриблинг) — активный путь;
## keeper_pass (раскат) сохранён, но сейчас не подключён.
func _on_visual_contact(action: String) -> void:
	if _goalkick_mode:
		return   # контактом на ударе от ворот владеет GoalKickController, не распас вратаря
	# HANDS-раздача рукой (План 2) переиспользует клипы keeper_pass/keeper_overhand_throw. Гейт
	# _hand_target_pos != ZERO отличает её от авто-_do_overhand_throw/_do_pass_roll — ПРИОРИТЕТ выше
	# авто-веток ниже (иначе авто-overhand перехватил бы контакт «удержания» раньше hand-release).
	if _state == State.THROWING and not _distribute_fired \
			and (action == "keeper_overhand_throw" or action == "keeper_pass") \
			and _hand_target_pos != Vector3.ZERO:
		_do_hand_release()
		return
	if action == "keeper_placing_ball" and _state == State.PLACING and not _place_fired:
		_begin_carry()
		return
	if action == "keeper_overhand_throw" and _state == State.THROWING and not _distribute_fired:
		_do_overhand_throw()
		return
	if action == "keeper_field_pass" and _state == State.FIELD_PASS and not _field_pass_fired:
		_do_field_pass_launch()
		return
	if action == "keeper_pass" and _state == State.DISTRIBUTE and not _distribute_fired:
		_do_pass_roll()


## Раскат мяча рукой по низу: отклеиваем от руки, роняем на газон под текущей позицией мяча
## и катим в сторону центра поля на KEEPER_PASS_DISTANCE (скорость выведена из драга мяча,
## flat=true — катится низом, без подскока).
func _do_pass_roll() -> void:
	_distribute_fired = true
	if ball.dribbler == _body or ball.is_caught():
		var into := signf(-goal_line_z)   # от ворот в поле (к центру)
		var dir := Vector3(0.0, 0.0, into)
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		var speed := KeeperLogic.roll_speed(FootballConstants.KEEPER_PASS_DISTANCE, ball.drag_factor, dt)
		var bp := ball.global_position
		ball.global_position = Vector3(bp.x, FootballConstants.BALL_RADIUS + 0.02, bp.z)  # был на руке → на газон
		print("[KEEPER] pass roll! speed=", speed, " dir=", dir)
		ball.launch(dir * speed, true)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)   # снова свободен — назад на линию
	_state = State.POSITION


## Выброс мяча в сторону центра поля (drop kick). ВРЕМЕННО не используется — раздача идёт
## через _do_pass_roll (keeper_pass). Оставлено для возврата к выносу ногой.
func _do_clear() -> void:
	_distribute_fired = true
	var out_z := signf(-goal_line_z)   # от ворот к центру поля
	var vel := Vector3(0, 0, out_z) * FootballConstants.KEEPER_CLEAR_SPEED + Vector3.UP * FootballConstants.KEEPER_CLEAR_LIFT
	if ball.dribbler == _body or ball.is_caught():
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
	var right := _body.global_transform.basis.x
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
		m.set_face_direction(Vector3(ball.global_position.x - _body.global_position.x, 0.0, into * 4.0))
	# Геометрический захват: мяч дотянулся → приклеиваем к рукам.
	if ball.is_flight() and _catch_radius_hit():
		ball.catch(_body, hold_point)
	if ball.has_method(&"is_caught") and ball.is_caught() and ball.dribbler == _body:
		if _state_timer <= 0.0:
			_enter_hands()   # клип доиграл — мяч в руках, управляемый актёр (План 2)
		return
	# Не поймал: мяч пересёк линию (за спиной) или окно давно истекло → в стойку (гол).
	var into2 := -1.0 if goal_line_z > 0.0 else 1.0
	if (ball.global_position.z - goal_line_z) * into2 < 0.0 or _state_timer <= -1.5:
		_finish_dive()

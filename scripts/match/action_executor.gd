class_name ActionExecutor
extends Node
## Резолюция «действия с мячом» → физический импульс. Общий commit-путь удара/паса, вынесенный
## из match_manager (Фаза 3a). Узел-компаньон менеджера (как PenaltyController/FreeKickController):
## владеет состоянием коммита (_action_*/_pending_*/_pass_rng) и звонит назад в _manager за общими
## хелперами (_aim_dir/_ai_of/_player_visual/... — вход человека и заряд остаются в менеджере до 3b).

var _manager: Node
var _ball: RigidBody3D

# Commit-действие с мячом (пас/удар): пока идёт клип, управление игроком заблокировано.
# Тайминг живёт в PlayerVisual — импульс применяется по сигналу action_contact,
# блокировка снимается по action_finished.
var _action_player: CharacterBody3D     # кто выполняет действие (управление заблокировано)
var _action_dir: Vector3 = Vector3.ZERO
var _action_power: float = 0.0

# true → kick animation is playing; ball.kick() deferred to action_contact;
# movement is NOT locked (unlike pass which uses _action_player + motor lock)
var _kick_action_active: bool = false

var _pass_rng := RandomNumberGenerator.new()
var _pending_launch: Vector3 = Vector3.ZERO
var _pending_curl: Vector3 = Vector3.ZERO
var _pending_flat: bool = false   # true → настильный удар низом (мяч катится без подскока)
var _pending_pass_team: StringName = &""   # команда пасующего для метки бэк-паса; &"" для удара (не пас)

func setup(manager: Node, ball: RigidBody3D) -> void:
	_manager = manager
	_ball = ball
	_pass_rng.randomize()

## Тело, выполняющее действие (управление заблокировано), либо null. Читает менеджер в
## _handle_player_input/_handle_dribbling — раньше это было поле _action_player.
func action_player() -> CharacterBody3D:
	return _action_player

## Идёт ли клип удара (импульс отложен до action_contact, мотор НЕ залочен). Раньше — поле
## _kick_action_active.
func is_kick_action_active() -> bool:
	return _kick_action_active


func _ground_launch(from: Vector3, aim: Vector3, power: float, facing: Vector3) -> Vector3:
	var d := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	if d.length() < 0.001:
		d = Vector3(facing.x, 0.0, facing.z)
	if d.length() < 0.001:
		d = Vector3(0.0, 0.0, _manager._attack_dir_z)
	return d.normalized() * power


## Удар: контекст решает удар в ворота vs вынос; тип (прямой/кручёный/черпачок) — по action.
## Импульс — через commit-action (ball.launch / launch_curl по action_contact), как у паса.
## Плоская скорость удара НИЗОМ: горизонталь к цели, без вертикали (vy=0) — мяч идёт по газону,
## а не по баллистической дуге. from/aim берём только по X/Z.
func fire_shot(action: int, player: CharacterBody3D, charge_ratio: float, facing_override: Vector3 = Vector3.ZERO) -> void:
	if not _ball.has_method(&"launch"):
		return
	var from: Vector3 = _ball.global_position
	var goal_center := _target_goal_center()  # чужие ворота (гибко, флипается на half-time)
	var half_w: float = FootballConstants.GOAL_WIDTH / 2.0
	var height: float = FootballConstants.GOAL_HEIGHT
	var facing: Vector3 = facing_override if facing_override.length_squared() > 0.0001 else _ball.get_dribble_direction()
	var g := _ball_gravity()
	var launch_vel: Vector3
	var curl := Vector3.ZERO
	var ground_shot := false   # настильный удар низом (короткий тап) — ставится в ветке удара

	# На ЧУЖОЙ половине (сторона атакующих ворот) — всегда удар по воротам, без выноса.
	# Вынос допустим только на своей половине. Половина определяется через _attack_dir_z
	# (тот же флип, что и целевые ворота — half-time-свап согласован).
	var on_attacking_half: bool = from.z * _manager._attack_dir_z > 0.0
	if (not on_attacking_half) and ShotSystem.wants_clearance(from, goal_center, facing,
			FootballConstants.CLEARANCE_ZONE_DIST, FootballConstants.CLEARANCE_FACING_DOT):
		# ВЫНОС: мощно по facing вдаль, без прицела в створ.
		var power := lerpf(FootballConstants.CLEARANCE_POWER, FootballConstants.CLEARANCE_POWER * 1.2, charge_ratio)
		launch_vel = ShotSystem.clearance_velocity(facing, power, FootballConstants.CLEARANCE_LIFT)
	else:
		# УДАР: прицел в створ (гибрид: авто-цель + смещение по facing + разброс).
		# curl_side даёт сторону стика; прицел (прямой/черпачок) — в ДАЛЬНИЙ угол (куда стик),
		# по тому же принципу, что и кручёный, только без Magnus. Поэтому side_bias = -curl_side.
		var side_bias := ShotSystem.aim_bias(from, goal_center, facing, FootballConstants.SHOT_AIM_SENSITIVITY)
		var dist := Vector3(goal_center.x - from.x, 0.0, goal_center.z - from.z).length()
		var scatter := ShotSystem.scatter_meters(FootballConstants.SHOT_SCATTER_BASE, charge_ratio,
			dist, FootballConstants.SHOT_SCATTER_DIST_REF)
		var aim := ShotSystem.goal_aim_point(goal_center, half_w, height, side_bias, charge_ratio,
			FootballConstants.SHOT_AIM_Y_MIN, FootballConstants.SHOT_OVER_LIFT, scatter, _pass_rng)
		# Помощь при ударе: мягкий магнит прицела внутрь рамы (гасит разброс мимо ворот).
		aim = ShotSystem.goal_assist(aim, goal_center, half_w, height,
			FootballConstants.SHOT_ASSIST, FootballConstants.SHOT_ASSIST_MARGIN)
		# Короткое нажатие (<10% заряда): прямой/кручёный удар НИЗОМ — плоский пуск (без дуги).
		# Черпачок (SHOT_CHIP) не трогаем — он всегда навесной.
		ground_shot = action != MatchManager.ChargeAction.SHOT_CHIP and charge_ratio < FootballConstants.SHOT_GROUND_CHARGE_MAX
		if ground_shot:
			aim.y = FootballConstants.SHOT_GROUND_AIM_Y
		if action == MatchManager.ChargeAction.SHOT_CHIP:
			# Черпачок: перекидывающая парабола в СТОРОНУ ворот (с учётом угла прицела), но заряд
			# задаёт И высоту дуги, И дальность приземления. Слабый — роняет близко, сильный —
			# далеко перекидывает; точным зарядом попадаешь в ворота.
			var peak := lerpf(FootballConstants.CHIP_PEAK_MIN, FootballConstants.CHIP_PEAK_MAX, charge_ratio)
			var chip_dist := lerpf(FootballConstants.CHIP_DIST_MIN, FootballConstants.CHIP_DIST_MAX, charge_ratio)
			var chip_dir := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
			if chip_dir.length() < 0.001:
				chip_dir = Vector3(facing.x, 0.0, facing.z)
			chip_dir = chip_dir.normalized()
			var chip_target := Vector3(from.x + chip_dir.x * chip_dist, from.y, from.z + chip_dir.z * chip_dist)
			launch_vel = PassSystem.launch_lob(from, chip_target, peak, g)
		else:
			# Прямой и кручёный: настильная баллистика в точку прицела.
			var power := lerpf(FootballConstants.SHOT_POWER_MIN, FootballConstants.SHOT_POWER_MAX, charge_ratio)
			if ground_shot:
				power = FootballConstants.SHOT_GROUND_POWER   # настильный удар — крепкий, несмотря на короткий тап
			if action == MatchManager.ChargeAction.SHOT_CURL:
				# Кручёный «в дальнюю девятку». Закрутка (curl_side) гнёт мяч в сторону −side —
				# это ПРАВИЛЬНАЯ дуга. Прицел РАЗВЯЗАН от закрутки: целимся так, чтобы эта дуга
				# занесла мяч в ДАЛЬНИЙ угол (на −side): при слабом заряде почти прямо в угол, при
				# сильном — короче (aim смещён на +side на CURL_AIM_OUT), закрутка добьёт в угол.
				# Направление закрутки — по стороне наклона стика (= -sign(side_bias), как раньше).
				var side := 1.0 if side_bias < 0.0 else -1.0
				# aim.x уже непрерывно наведён (goal_aim_point + assist); целимся ЗА эту точку на
				# CURL_AIM_OUT — дуга Magnus вернёт мяч в неё. Центр → почти прямой, у угла — дуга.
				aim.x += side * FootballConstants.CURL_AIM_OUT * charge_ratio
				launch_vel = _ground_launch(from, aim, power, facing) if ground_shot else ShotSystem.ballistic_to(from, aim, power, g)
				var strength := lerpf(FootballConstants.CURL_STRENGTH_MIN, FootballConstants.CURL_STRENGTH_MAX, charge_ratio)
				curl = ShotSystem.curl_vector(side, strength, FootballConstants.CURL_LIFT)
			else:
				launch_vel = _ground_launch(from, aim, power, facing) if ground_shot else ShotSystem.ballistic_to(from, aim, power, g)

	# Commit-action: импульс по action_contact, launch-путь (сентинел _action_power = -1).
	_action_player = player
	_action_dir = launch_vel
	_action_power = -1.0
	_kick_action_active = true
	_pending_launch = launch_vel
	_pending_curl = curl
	_pending_flat = ground_shot
	_pending_pass_team = &""   # удар — не пас: мяч не помечаем меткой бэк-паса
	var visual: PlayerVisual = _manager._player_visual(player)
	if visual != null and visual.trigger("kick"):
		return  # ждём action_contact
	# Фолбэк без анимации: бьём сразу
	if curl.length_squared() > 0.0001 and _ball.has_method(&"launch_curl"):
		_ball.launch_curl(launch_vel, curl, ground_shot)
	else:
		_ball.launch(launch_vel, ground_shot)
	_action_player = null
	_kick_action_active = false


## Собрать параметры паса по заряжаемому действию. Заряд множит базовую силу.
func _pass_params(action: int, charge_ratio: float) -> PassParams:
	var p := PassParams.new()
	var mult := lerpf(FootballConstants.PASS_POWER_CHARGE_MIN, FootballConstants.PASS_POWER_CHARGE_MAX, charge_ratio)
	match action:
		MatchManager.ChargeAction.PASS_SHORT:
			pass  # скорость низового паса считается по дистанции в fire_pass (ground_pass_speed)
		MatchManager.ChargeAction.PASS_WALL:
			p.is_wall = true
		MatchManager.ChargeAction.PASS_THROUGH:
			p.extra_lead = FootballConstants.PASS_THROUGH_EXTRA_LEAD
		MatchManager.ChargeAction.PASS_LOB:
			p.peak_height = FootballConstants.PASS_LOB_PEAK_HEIGHT * mult
			p.is_air = true
		MatchManager.ChargeAction.PASS_THROUGH_AIR:
			p.peak_height = FootballConstants.PASS_THROUGH_AIR_PEAK_HEIGHT * mult
			p.extra_lead = FootballConstants.PASS_THROUGH_EXTRA_LEAD
			p.is_air = true
		_:
			pass
	return p


## Позиции/скорости/узлы группы в параллельных массивах (индекс общий). Исключает except_node.
func _team_arrays(group: StringName, except_node: Node) -> Dictionary:
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var nodes: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(group):
		if n == except_node or not (n is CharacterBody3D) or not is_instance_valid(n):
			continue
		positions.append(n.global_position)
		velocities.append(n.velocity)
		nodes.append(n)
	return {"pos": positions, "vel": velocities, "nodes": nodes}


## Геометрия решает «можно ли перехватить»; шанс решает, среагирует ли соперник (не читерски-
## идеально). Если да — соперник бежит к точке пересечения (визуальный, честный перехват).
## NOTE: FootballConstants.AI_SPEED (5.0) is legacy/unused elsewhere (see CLAUDE.md's own
## caveat on it) — the opponent's REAL speed is the `speed` export on simple_ai.gd (8.0 by
## default). Read it off the node via get(), not the stale constant, or every interception
## feasibility check will be computed against a speed the opponent doesn't actually have.
func _maybe_flag_interceptor(from: Vector3, to: Vector3, launch_vel: Vector3) -> void:
	var ball_speed := Vector3(launch_vel.x, 0.0, launch_vel.z).length()
	var opps := _team_arrays(&"team_2", null)
	var opp_pos: PackedVector3Array = opps["pos"]
	var opp_nodes: Array = opps["nodes"]
	var best_time := INF
	var best_i := -1
	for i in range(opp_pos.size()):
		var speed_variant: Variant = _manager._ai_of(opp_nodes[i]).get(&"speed")
		var opp_speed: float = speed_variant if speed_variant != null else FootballConstants.AI_SPEED
		var t := PassSystem.interception_time(from, to, ball_speed, opp_pos[i],
			opp_speed, FootballConstants.PASS_CORRIDOR_HALF_WIDTH, FootballConstants.PASS_CORRIDOR_SPREAD)
		if t < best_time:
			best_time = t
			best_i = i
	if best_i < 0:
		return
	if _pass_rng.randf() > FootballConstants.AI_INTERCEPT_CHANCE:
		return  # соперник «зевнул»
	var opp: Node3D = opp_nodes[best_i]
	var opp_ai: Node = _manager._ai_of(opp)
	if opp_ai.has_method(&"begin_intercept"):
		var point := from + Vector3(launch_vel.x, 0.0, launch_vel.z).normalized() * (best_time * ball_speed)
		opp_ai.begin_intercept(point)


## Реальная гравитация мяча (RigidBody под движковую гравитацию, НЕ FootballConstants.GRAVITY).
func _ball_gravity() -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return g * _ball.gravity_scale


## Центр чужих ворот (в которые бьёт наша команда). Гибко — через _attack_dir_z, не хардкод,
## чтобы смена ворот во втором тайме меняла прицел ударов в одном месте.
func _target_goal_center() -> Vector3:
	return Vector3(0.0, 0.0, _manager._attack_dir_z * _manager.field_length)


## Выполнить пас: выбрать цель по прицелу, посчитать траекторию, применить импульс через
## commit-action (как удар), передать управление принимающему сразу.
func fire_pass(action: int, player: CharacterBody3D, charge_ratio: float, facing_override: Vector3 = Vector3.ZERO) -> void:
	if not _ball.has_method(&"launch"):
		return
	var params := _pass_params(action, charge_ratio)
	var mates := _team_arrays(&"team_1", player)
	var mate_pos: PackedVector3Array = mates["pos"]
	var mate_vel: PackedVector3Array = mates["vel"]
	var mate_nodes: Array = mates["nodes"]
	# Направление паса — по СТИКУ (а не facing тела): куда целишься, туда и пас. Стик отпущен →
	# фолбэк на facing (внутри _aim_dir). facing_override — путь очереди (там стик уже посчитан).
	var aim: Vector3 = facing_override if facing_override.length_squared() > 0.0001 else _manager._aim_dir(player)
	var idx := PassSystem.select_target(player.global_position, aim, mate_pos, mate_vel,
		FootballConstants.PASS_LEAD_GAIN, FootballConstants.PASS_DOT_BIAS, FootballConstants.PASS_MAX_RANGE)
	# Точка прицела: в ноги (короткий/навес) или на ход (through). Нет цели → по направлению прицела.
	var from := _ball.global_position
	var aim_point: Vector3
	var receiver: CharacterBody3D = null
	var ball_speed := FootballConstants.PASS_LEAD_SPEED_ESTIMATE
	if idx >= 0:
		receiver = mate_nodes[idx]
		if params.extra_lead > 0.0:
			aim_point = PassSystem.lead_point(mate_pos[idx], mate_vel[idx], from, ball_speed, params.extra_lead)
		else:
			aim_point = mate_pos[idx]
	else:
		var flat := Vector3(aim.x, 0.0, aim.z).normalized()
		aim_point = from + flat * 12.0
	# Пасы «на ход» (Y/W наземный, LB+Y верховой) — РУЧНЫЕ: направление строго по СТИКУ, дальность/
	# сила по ЗАРЯДУ (наземный до ~35 м, верховой до ~пол поля), БЕЗ автонаводки на цель и БЕЗ
	# разброса (ниже). Хендофф + receive-assist СОХРАНЕНЫ — принимающий выходит на мяч (бег на мяч);
	# управление уходит бегущему, поэтому нажатие удара на бегу ставит очередь (одно касание), а не
	# подкат. Разница типов — только высота траектории (наземный/верховой) и диапазон дальности.
	if action in [MatchManager.ChargeAction.PASS_THROUGH, MatchManager.ChargeAction.PASS_THROUGH_AIR]:
		var aim_flat := Vector3(aim.x, 0.0, aim.z)
		if aim_flat.length() < 0.001:
			aim_flat = Vector3(0.0, 0.0, _manager._attack_dir_z)
		var is_air_through := action == MatchManager.ChargeAction.PASS_THROUGH_AIR
		var space_min: float = FootballConstants.PASS_THROUGH_AIR_SPACE_MIN if is_air_through else FootballConstants.PASS_THROUGH_SPACE_MIN
		var space_max: float = FootballConstants.PASS_THROUGH_AIR_SPACE_MAX if is_air_through else FootballConstants.PASS_THROUGH_SPACE_MAX
		aim_point = from + aim_flat.normalized() * lerpf(space_min, space_max, charge_ratio)
	# Разброс точности — КРОМЕ ручных «на ход» (летят точно по стику).
	if not (action in [MatchManager.ChargeAction.PASS_THROUGH, MatchManager.ChargeAction.PASS_THROUGH_AIR]):
		var flat_dir := (aim_point - from)
		flat_dir.y = 0.0
		var spread := PassSystem.scatter_degrees(FootballConstants.PASS_SPREAD_BASE, FootballConstants.PASS_ASSIST,
			flat_dir.length(), FootballConstants.PASS_SPREAD_DIST_REF)
		flat_dir = PassSystem.apply_scatter(flat_dir, spread, _pass_rng)
		aim_point = from + flat_dir + Vector3(0.0, aim_point.y - from.y, 0.0)
	# Баллистика.
	var launch_vel: Vector3
	if params.is_air:
		var g := _ball_gravity()
		launch_vel = PassSystem.launch_lob(from, aim_point, params.peak_height, g)
	else:
		var ground_dist := (aim_point - from).length()
		var ground_speed := PassSystem.ground_pass_speed(ground_dist, charge_ratio,
			FootballConstants.PASS_GROUND_MIN_TRAVEL_TIME, FootballConstants.PASS_GROUND_MAX_TRAVEL_TIME,
			FootballConstants.PASS_GROUND_MIN_SPEED, FootballConstants.PASS_GROUND_MAX_SPEED)
		launch_vel = PassSystem.launch_ground(from, aim_point, ground_speed, FootballConstants.PASS_GROUND_LIFT)
	_maybe_flag_interceptor(from, aim_point, launch_vel)
	# Commit-action: импульс по action_contact, без блокировки мотора (как kick).
	_action_player = player
	_action_dir = launch_vel  # для пасов _action_dir несёт готовую скорость (см. on_action_contact)
	_action_power = -1.0       # маркер «это launch, а не kick»
	_kick_action_active = true
	_pending_launch = launch_vel
	_pending_curl = Vector3.ZERO  # пас не крутится (сброс остаточного curl от прошлого кручёного удара)
	_pending_flat = false         # пас — не настильный удар (сброс флага от прошлого удара низом)
	# Метка намеренного паса команды (правило бэк-паса вратаря). Проставляется на мяч в момент
	# реального launch (fallback ниже И on_action_contact) — не здесь, т.к. мяч ещё у ног.
	_pending_pass_team = &"team_1" if player.is_in_group("team_1") else &"team_2"
	# Передать управление принимающему сразу.
	if receiver != null:
		_manager.controlled_player = receiver
		_manager._sync_ai_controllers()
		_manager._manual_swap_cooldown = 30
	if receiver != null and receiver != _manager.controlled_player and _manager._ai_of(receiver).has_method(&"begin_receiving"):
		_manager._ai_of(receiver).begin_receiving(launch_vel, params.extra_lead)
	if receiver != null and receiver == _manager.controlled_player:
		_manager.begin_pass_receive(receiver)
	if params.is_wall and is_instance_valid(player) and _manager._ai_of(player).has_method(&"begin_give_and_go"):
		if receiver != null:
			_manager._ai_of(player).begin_give_and_go(receiver.global_position)
		if _ball.has_method(&"clear_last_kicker"):
			# Не await здесь напрямую: это приостановило бы весь fire_pass (включая
			# visual.trigger()/ball.launch() ниже) на 0.4с. Запускаем отдельной корутиной.
			_clear_wall_pass_cooldown()
	var visual: PlayerVisual = _manager._player_visual(player)
	if visual != null and visual.trigger("pass"):
		return
	_ball.launch(launch_vel)
	if _pending_pass_team != &"" and _ball.has_method(&"note_pass_from"):
		_ball.note_pass_from(_pending_pass_team)
	_action_player = null
	_kick_action_active = false


## Даём отдавшему «стенку» шанс принять быстрый возврат, сняв с мяча метку последнего
## игрока чуть раньше истечения ball._kick_cooldown_msec. Отдельная корутина — намеренно
## не await-ится из fire_pass, чтобы не задерживать сам пас (см. вызов выше).
func _clear_wall_pass_cooldown() -> void:
	await get_tree().create_timer(0.4).timeout
	if is_instance_valid(_ball):
		_ball.clear_last_kicker()


## Момент касания ногой: придать импульс мячу.
func on_action_contact(_action: String, player: Node) -> void:
	if player != _action_player:
		return
	# Удар/пас отложены до сигнала анимации; с подвижным дриблингом игрок за это время может
	# повернуть и пробежать МИМО мяча (мяч сзади). Если в момент контакта мяч за спиной —
	# не бьём (промах вхолостую), иначе мяч «сам улетает» из позиции за спиной. Полноценный
	# fire-on-reach (удар в момент, когда игрок дотянулся до мяча) даст Фаза 2 (очередь).
	if player is Node3D:
		var p3 := player as Node3D
		var to_ball: Vector3 = _ball.global_position - p3.global_position
		to_ball.y = 0.0
		var facing: Vector3 = -p3.global_transform.basis.z
		facing.y = 0.0
		if to_ball.length() > 0.05 and facing.length() > 0.01 \
				and facing.normalized().dot(to_ball.normalized()) < -0.2:
			return  # мяч за спиной — удар/пас не производим
	if _action_power < 0.0 and _ball.has_method(&"launch"):
		if _pending_curl.length_squared() > 0.0001 and _ball.has_method(&"launch_curl"):
			_ball.launch_curl(_pending_launch, _pending_curl, _pending_flat)
		else:
			_ball.launch(_pending_launch, _pending_flat)
		# Метка бэк-паса — ПОСЛЕ launch (launch не трогает _pass_from_team). Только для паса
		# (_pending_pass_team != &""); удар сбрасывает поле в &"" в fire_shot.
		if _pending_pass_team != &"" and _ball.has_method(&"note_pass_from"):
			_ball.note_pass_from(_pending_pass_team)
	elif _ball.has_method(&"kick"):
		_ball.kick(_action_dir, _action_power)


## Действие завершилось: вернуть управление.
func on_action_finished(_action: String, player: Node) -> void:
	if player == _action_player:
		_action_player = null
		_kick_action_active = false
		var motor: PlayerMotor = _manager._player_motor(player)
		if motor != null:
			motor.set_control_locked(false)


## Отменить действие игрока (сбили подкатом на замахе): без импульса, вернуть управление.
func cancel_action(player: Node) -> void:
	if _action_player != player:
		return
	_action_player = null
	_kick_action_active = false
	var motor: PlayerMotor = _manager._player_motor(player)
	if motor != null:
		motor.set_control_locked(false)
	var visual: PlayerVisual = _manager._player_visual(player)
	if visual != null:
		visual.cancel_action()

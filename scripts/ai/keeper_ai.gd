extends CharacterBody3D
## AI-вратарь: позиционирование на линии + сейв (ловля/нырок/отбой) + вынос мяча.
## Движение — через PlayerMotor; нырок — свой move_and_collide при заблокированном моторе
## (как подкат). Вся математика — в KeeperLogic (чистые функции).

@export var ball: RigidBody3D
var goal_line_z: float = 0.0
var save_area: Area3D

enum State { POSITION, DIVE, RECOVER, HOLD, DISTRIBUTE }
var _state: int = State.POSITION
var _wired: bool = false

# Сейв.
var _react_left: float = 0.0
var _reacting: bool = false
var _current_action: int = KeeperLogic.SaveAction.NONE
var _dive_vel: Vector3 = Vector3.ZERO
var _dive_time_left: float = 0.0
var _state_timer: float = 0.0
var _distribute_fired: bool = false


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
	var v := _visual()
	if v != null:
		v.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)
		if not v.action_contact.is_connected(_on_visual_contact):
			v.action_contact.connect(_on_visual_contact)
	if save_area != null and not save_area.body_entered.is_connected(_on_save_area_body):
		save_area.body_entered.connect(_on_save_area_body)


func _physics_process(delta: float) -> void:
	if not ball or not is_instance_valid(ball):
		return
	_ensure_wired()
	match _state:
		State.POSITION:
			_position(delta)
		State.DIVE:
			_dive(delta)
		State.RECOVER:
			_recover(delta)
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
	m.set_face_direction(ball.global_position - global_position)
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
	var intercept := KeeperLogic.shot_intercept(ball.global_position, ball.linear_velocity, goal_line_z)
	if not KeeperLogic.is_on_target(intercept, FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.GOAL_HEIGHT):
		_reacting = false
		return
	if not _reacting:
		_reacting = true
		_react_left = FootballConstants.KEEPER_REACT
	_react_left -= delta
	if _react_left > 0.0:
		return
	var dec := KeeperLogic.save_decision(intercept, global_position,
		FootballConstants.KEEPER_REACH, FootballConstants.KEEPER_DIVE_RANGE,
		FootballConstants.KEEPER_HIGH_THRESHOLD)
	var act: int = dec.action
	if act == KeeperLogic.SaveAction.NONE:
		return  # недосягаемо — гол
	if _is_catch_action(act):
		_begin_save(dec, ball.linear_velocity.length())
		return
	var ttoi := KeeperLogic.time_to_intercept(ball.global_position, ball.linear_velocity, intercept)
	if KeeperLogic.should_commit_dive(ttoi, global_position, dec.target,
			FootballConstants.KEEPER_DIVE_SPEED, FootballConstants.KEEPER_DIVE_LEAD):
		_begin_save(dec, ball.linear_velocity.length())
	else:
		# ещё рано — подшагиваем к предсказанному X по линии
		var steer := Vector3(intercept.x - global_position.x, 0, 0)
		if steer.length() > 0.05:
			m.set_move_intent(steer.normalized(), _base_scale())


## Старт сейва: центр (CATCH/CATCH_TOP) — на месте (dive_vel≈0); угол — бросок к цели.
func _begin_save(dec: Dictionary, ball_speed: float) -> void:
	_reacting = false
	_current_action = dec.action
	_state = State.DIVE
	var m := _motor()
	if m != null:
		m.set_control_locked(true)   # телом владеет наш move_and_collide (как подкат)
	var vis := _visual()
	var clip := _catch_clip(dec.action) if _is_catch_action(dec.action) else _dive_clip(dec.action)
	var clip_len := 0.0
	if vis != null:
		clip_len = vis.play_oneshot(clip)
	_dive_time_left = maxf(clip_len, 0.4)
	if _is_catch_action(dec.action):
		_dive_vel = Vector3.ZERO   # ловля на месте
	else:
		var target: Vector3 = dec.target
		target.x += randf_range(-1.0, 1.0) * FootballConstants.KEEPER_SAVE_ERROR
		var to := target - global_position
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() < 0.001:
			flat = Vector3(1, 0, 0)
		_dive_vel = flat.normalized() * FootballConstants.KEEPER_DIVE_SPEED
		_dive_vel.y = maxf(0.0, to.y) * FootballConstants.KEEPER_DIVE_LIFT_GAIN


func _dive(delta: float) -> void:
	_dive_vel.y -= FootballConstants.GRAVITY * delta
	move_and_collide(_dive_vel * delta)
	_dive_vel.x *= 0.9
	_dive_vel.z *= 0.9
	_dive_time_left -= delta
	if _dive_time_left <= 0.0:
		_to_recover()


## Контакт сейв-зоны с мячом в полёте: ловим (центр / медленный низ) или отбиваем.
func _on_save_area_body(body: Node) -> void:
	if body != ball or not ball.is_flight():
		return
	if _state != State.DIVE:
		return
	var is_catch := KeeperLogic.resolve_save(_current_action, ball.linear_velocity.length(),
		FootballConstants.KEEPER_CATCH_MAX_SPEED)
	if is_catch:
		ball.set_dribbler(self, true)
		_to_hold()
	else:
		var out := ball.global_position - Vector3(0, 0, goal_line_z)
		out.y = 0.0
		ball.parry(out, FootballConstants.KEEPER_PARRY_DAMP)
		# нырок доиграет и уйдёт в RECOVER


func _to_recover() -> void:
	_state = State.RECOVER
	var vis := _visual()
	var l := 0.0
	if vis != null:
		l = vis.play_oneshot(&"standing_up")
	_state_timer = maxf(l, 0.5)


func _recover(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		var m := _motor()
		if m != null:
			m.set_control_locked(false)
		var vis := _visual()
		if vis != null:
			vis.recover()
		_state = State.POSITION


## HOLD: подержать мяч в руках (idle_ball), затем перейти к выносу.
func _to_hold() -> void:
	_state = State.HOLD
	_state_timer = FootballConstants.KEEPER_HOLD_TIME
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
	var vis := _visual()
	if vis != null:
		vis.play_oneshot(&"keeper_idle_ball")


func _hold(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_to_distribute()


func _to_distribute() -> void:
	_state = State.DISTRIBUTE
	_distribute_fired = false
	var vis := _visual()
	if vis != null:
		vis.recover()                 # выйти из idle_ball one-shot в локомоцию-хаб
		vis.trigger("keeper_drop_kick")


func _distribute(_delta: float) -> void:
	# Ждём сигнала action_contact (см. _on_visual_contact). Страховка: если мяч уже выбит и
	# не наш — возврат на линию (на случай пропуска сигнала).
	if _distribute_fired and ball.dribbler != self:
		_state = State.POSITION


## Момент касания мяча ногой в drop kick → вынос в сторону центра поля.
func _on_visual_contact(action: String) -> void:
	if action != "keeper_drop_kick" or _state != State.DISTRIBUTE or _distribute_fired:
		return
	_distribute_fired = true
	var out_z := signf(-goal_line_z)   # от ворот к центру поля
	var vel := Vector3(0, 0, out_z) * FootballConstants.KEEPER_CLEAR_SPEED + Vector3.UP * FootballConstants.KEEPER_CLEAR_LIFT
	if ball.dribbler == self:
		ball.launch(vel)
	_state = State.POSITION


func _is_catch_action(a: int) -> bool:
	return a == KeeperLogic.SaveAction.CATCH or a == KeeperLogic.SaveAction.CATCH_TOP


func _dive_clip(a: int) -> StringName:
	match a:
		KeeperLogic.SaveAction.DIVE_LOW_L: return &"keeper_body_block_l"
		KeeperLogic.SaveAction.DIVE_LOW_R: return &"keeper_body_block_r"
		KeeperLogic.SaveAction.DIVE_HIGH_L: return &"keeper_diving_save_l"
		KeeperLogic.SaveAction.DIVE_HIGH_R: return &"keeper_diving_save_r"
		_: return &"keeper_body_block_r"


func _catch_clip(a: int) -> StringName:
	return &"keeper_catch_top" if a == KeeperLogic.SaveAction.CATCH_TOP else &"keeper_catch"

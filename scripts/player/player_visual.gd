class_name PlayerVisual
extends Node3D

## Момент касания мячом ногой (геймплей в этот миг придаёт импульс мячу).
signal action_contact(action: String)
## Действие завершилось — управление можно вернуть.
signal action_finished(action: String)

## Порог скорости (м/с), при котором бленд = полный бег (1.0).
const RUN_SPEED_FULL := 5.0
## Сглаживание бленда, 1/сек.
const BLEND_SMOOTH := 10.0

## Имена стейтов локомоции в StateMachine (LOCOMOTION = idle-хаб, из него travel в остальные).
const LOCOMOTION := &"loco_idle"
const LOCO_RUN := &"loco_run"
const LOCO_SPRINT := &"loco_sprint"
## Боковой стейт локомоции вратаря (приставные шаги вместо бега).
const LOCO_KEEPER_SIDE := &"loco_keeper_side"
## Стойка готовности вратаря (keeper_idle) — используется вместо обычного idle в KEEPER-стиле.
const LOCO_KEEPER_IDLE := &"loco_keeper_idle"
## Стиль локомоции: NORMAL (idle/run/sprint) или KEEPER (idle/keeper_sidestep, без спринта).
const LOCO_STYLE_NORMAL := 0
const LOCO_STYLE_KEEPER := 1
## Семантическое действие (trigger) → имя клипа в glb. Стейт создаётся, только если клип есть.
const ACTION_CLIPS := {
	"kick": "pass",
	"pass": "pass",
	"penalty": "penalty_kick",
	"penalty_l": "penalty_kick_l",
	"penalty_r": "penalty_kick_r",
	"throw_in": "throw_in",
	"keeper_drop_kick": "keeper_drop_kick",
	"keeper_pass": "keeper_pass",
	"keeper_placing_ball": "keeper_placing_ball",
	"keeper_field_pass": "pass",   # полевой пас вратаря: тот же клип, свой тайминг (медленнее, виден)
	"keeper_overhand_throw": "keeper_overhand_throw",
}
## Клипы, которые нужно зациклить; остальные one-shot доигрывают и авто-возвращаются.
const LOOP_CLIPS := [&"idle", &"run", &"sprint", &"fallen_idle"]

## Дополнительные one-shot стейты (подкат/падение/перекаты/вставание): travel-only, без
## авто-возврата — цепочку падения ведёт match_manager. fallen_idle зациклен (LOOP_CLIPS)
## и служит удерживаемой позой «лежит» в фазе knockdown.
const ONESHOT_CLIPS := [&"tackle", &"fallen_idle", &"roll_left", &"roll_right", &"standing_up",
	&"keeper_body_block_l", &"keeper_body_block_r", &"keeper_diving_save_l", &"keeper_diving_save_r",
	&"keeper_catch", &"keeper_catch_top", &"keeper_catch_head", &"keeper_scoop", &"keeper_miss_top", &"keeper_idle_ball"]

## Тайминг действия (реальные секунды): contact — до касания; lock — общая длительность
## до action_finished; speed — множитель скорости проигрывания (сжать замах, сохранив синхрон).
## Тюнится визуальной приёмкой. Действия без записи → contact=0, lock=длина_клипа, speed=1.
const ACTION_TIMING := {
	"kick": {"contact": 0.35, "lock": 0.5, "speed": 1.0},
	"pass": {"contact": 0.2, "lock": 0.4, "speed": 1.5},
	# Клип 1.6с: замах длинный, нога встречает мяч в самом КОНЦЕ (contact 1.45с), не на середине.
	"keeper_drop_kick": {"contact": 1.4, "lock": 1.6, "speed": 1.0},
	# Раскат рукой (1.4с): мяч приклеен к руке первые 0.8с, затем отклеивается и катится низом.
	"keeper_pass": {"contact": 0.8, "lock": 1.4, "speed": 1.0},
	# Постановка мяча рукой (1.17с): мяч приклеен к руке, к концу клипа рука ставит его на газон;
	# на contact (0.95с) передаём мяч в дриблинг (трап у ног).
	"keeper_placing_ball": {"contact": 0.95, "lock": 1.17, "speed": 1.0},
	# Полевой пас вратаря: клип pass (0.43с) на нормальной скорости 1.0×, contact в момент касания
	# мяча (≈0.3с клипа, как у полевого при 1.5×).
	"keeper_field_pass": {"contact": 0.3, "lock": 0.43, "speed": 1.0},
	# Бросок верхом рукой (0.97с): мяч приклеен к правой руке до выпуска на замахе (~0.65с), затем
	# летит по дуге.
	"keeper_overhand_throw": {"contact": 0.65, "lock": 0.97, "speed": 1.0},
	# Пенальти с разбегом (root motion, клип ~1.53с). contact — момент удара ногой (нога достаёт
	# мяч чуть раньше конца разбега); lock — общая длительность. Синхронно с PEN_RUNUP_DIST/PEN_CONTACT_TIME.
	"penalty_l": {"contact": 1.0, "lock": 1.55, "speed": 1.0},
	"penalty_r": {"contact": 1.0, "lock": 1.55, "speed": 1.0},
}

@export var model_y_offset: float = 0.0
@export var model_yaw_deg: float = 0.0

var _anim_tree: AnimationTree
var _model: Node3D
var _last_pos: Vector3
var _blend: float = 0.0
var _explicit_speed: float = -1.0  # >=0 → использовать вместо авто-замера
var _playback: AnimationNodeStateMachinePlayback
var _states: Dictionary = {}  # имя стейта one-shot → true (какие клипы реально есть)
var _ap: AnimationPlayer
var _active_action: String = ""   # выполняемое действие ("" = нет)
var _action_elapsed: float = 0.0  # прошло реальных секунд с старта действия
var _action_contact_at: float = 0.0
var _action_lock_at: float = 0.0
var _action_contact_done: bool = false
var _fall_lock: bool = false   # пока true — _process не выбирает стейт локомоции (ведёт fall-цепочка)
var _loco_style: int = LOCO_STYLE_NORMAL

## Чистое отображение скорости (м/с) в позицию бленда [0..1].
static func speed_to_blend(speed: float) -> float:
	return clampf(speed / RUN_SPEED_FULL, 0.0, 1.0)

## Анти-слайд: множитель скорости клипа бега/спринта = (speed/top)*fudge (клампится снизу).
static func run_timescale(speed: float, top_speed: float, fudge: float) -> float:
	if top_speed <= 0.0:
		return 1.0
	return maxf(0.1, (speed / top_speed) * fudge)

## Наклон корпуса (banking): крен узла Model по локальной оси Z. deg тюнится по знаку живьём.
func set_lean(deg: float) -> void:
	if _model == null:
		return
	_model.rotation.z = deg_to_rad(deg)

func _ready() -> void:
	_model = get_node_or_null(^"Model") as Node3D
	if _model == null:
		_use_fallback("нет узла Model")
		return
	_model.position.y = model_y_offset
	_model.rotation.y = deg_to_rad(model_yaw_deg)
	var ap := _find_anim_player(_model)
	if ap == null or not (ap.has_animation(&"idle") and ap.has_animation(&"run")):
		_use_fallback("нет AnimationPlayer с idle/run")
		return
	_build_anim_tree(ap)
	_last_pos = global_position

func _build_anim_tree(ap: AnimationPlayer) -> void:
	# glTF-анимации приходят незациклёнными (loop_mode=NONE). Локомоцию/лежание зацикливаем;
	# one-shot (удары/падение/вставание) оставляем незациклёнными — иначе не сработает
	# авто-возврат по AT_END.
	for anim_name in LOOP_CLIPS:
		if ap.has_animation(anim_name):
			ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

	# StateMachine: idle-хаб + run/sprint (скорость клипа привязана к реальной) + one-shot действия.
	var sm := AnimationNodeStateMachine.new()
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"idle"
	sm.add_node(LOCOMOTION, idle_node, Vector2(400, 60))
	sm.add_node(LOCO_RUN, _make_speed_state(&"run"), Vector2(400, 140))
	var sprint_clip: StringName = &"sprint" if ap.has_animation(&"sprint") else &"run"
	sm.add_node(LOCO_SPRINT, _make_speed_state(sprint_clip), Vector2(400, 220))
	# звёздчатые переходы: idle ↔ run, idle ↔ sprint (хаб = idle, travel строит путь через него)
	for st in [LOCO_RUN, LOCO_SPRINT]:
		sm.add_transition(LOCOMOTION, st, _make_transition(false))
		sm.add_transition(st, LOCOMOTION, _make_transition(false))
	# Боковой стейт вратаря (keeper_sidestep) — отдельный стейт скорости, если клип есть.
	if ap.has_animation(&"keeper_sidestep"):
		ap.get_animation(&"keeper_sidestep").loop_mode = Animation.LOOP_LINEAR
		sm.add_node(LOCO_KEEPER_SIDE, _make_speed_state(&"keeper_sidestep"), Vector2(400, 300))
		sm.add_transition(LOCOMOTION, LOCO_KEEPER_SIDE, _make_transition(false))
		sm.add_transition(LOCO_KEEPER_SIDE, LOCOMOTION, _make_transition(false))
	# Стойка готовности вратаря (keeper_idle) — стоячий стейт в KEEPER-стиле.
	if ap.has_animation(&"keeper_idle"):
		ap.get_animation(&"keeper_idle").loop_mode = Animation.LOOP_LINEAR
		var ki := AnimationNodeAnimation.new()
		ki.animation = &"keeper_idle"
		sm.add_node(LOCO_KEEPER_IDLE, ki, Vector2(600, 300))
		sm.add_transition(LOCOMOTION, LOCO_KEEPER_IDLE, _make_transition(false))
		sm.add_transition(LOCO_KEEPER_IDLE, LOCOMOTION, _make_transition(false))
		# Прямые переходы стойка↔шаги (иначе travel мелькает обычным idle через хаб).
		if ap.has_animation(&"keeper_sidestep"):
			sm.add_transition(LOCO_KEEPER_IDLE, LOCO_KEEPER_SIDE, _make_transition(false))
			sm.add_transition(LOCO_KEEPER_SIDE, LOCO_KEEPER_IDLE, _make_transition(false))
	var y := 40.0
	for action in ACTION_CLIPS:
		var clip: String = ACTION_CLIPS[action]
		if not ap.has_animation(clip):
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = clip
		sm.add_node(clip, node, Vector2(120, y))
		y += 80.0
		sm.add_transition(LOCOMOTION, clip, _make_transition(false))
		# Обратный переход — обычный кроссфейд (IMMEDIATE+xfade), а НЕ AT_END: авто-возврат по
		# концу клипа щёлкал в idle (AT_END+xfade не блендит, а держит последний кадр и снапает).
		# Возврат инициирует _process (travel в локомоцию, когда _active_action очищается на lock).
		sm.add_transition(clip, LOCOMOTION, _make_transition(false))
		_states[clip] = true

	var oneshot_added: Array[String] = []
	for clip in ONESHOT_CLIPS:
		var cs: String = String(clip)
		if not ap.has_animation(cs) or _states.has(cs):
			continue
		var onode := AnimationNodeAnimation.new()
		onode.animation = clip
		sm.add_node(cs, onode, Vector2(120, y))
		y += 80.0
		sm.add_transition(LOCOMOTION, cs, _make_transition(false))
		sm.add_transition(cs, LOCOMOTION, _make_transition(false))
		_states[cs] = true
		oneshot_added.append(cs)

	# Прямые переходы между one-shot стейтами (падение → перекат → вставание — цепочку
	# ведёт match_manager через play_oneshot). Без этого travel() между двумя one-shot
	# стейтами (нет прямого ребра) строит путь через LOCOMOTION-хаб — тот на кроссфейде
	# видимо мелькает idle между, скажем, перекатом и вставанием.
	for i in range(oneshot_added.size()):
		for j in range(oneshot_added.size()):
			if i == j:
				continue
			sm.add_transition(oneshot_added[i], oneshot_added[j], _make_transition(false))

	# Оборачиваем StateMachine в BlendTree с TimeScale — единый рычаг скорости проигрывания
	# действий (сжать замах, сохранив синхрон «нога↔мяч»). Локомоция идёт при scale=1.0.
	var bt := AnimationNodeBlendTree.new()
	bt.add_node(&"sm", sm, Vector2(200, 100))
	var ts := AnimationNodeTimeScale.new()
	bt.add_node(&"TimeScale", ts, Vector2(500, 100))
	bt.connect_node(&"TimeScale", 0, &"sm")
	bt.connect_node(&"output", 0, &"TimeScale")

	_ap = ap
	_anim_tree = AnimationTree.new()
	_anim_tree.name = "AnimTree"
	_anim_tree.tree_root = bt
	add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(ap)
	_anim_tree.active = true
	_anim_tree.set(&"parameters/TimeScale/scale", 1.0)
	# root_motion_track ставим ТОЛЬКО на время клипа удара пенальти (см. trigger) — иначе извлечение
	# движения Hips ломает вертикаль ВСЕХ клипов (вратарский idle «висит», нырки не прыгают).
	_playback = _anim_tree.get(&"parameters/sm/playback")
	if _playback != null:
		_playback.start(LOCOMOTION)

## Путь POSITION_3D-трека корневой кости (Hips) для root motion. При заданном anim_player дерево
## берёт root_node = корень модели (../Model), а треки в клипе хранятся относительно него — поэтому
## берём путь трека ПРЯМО из анимации penalty_* (напр. "Armature/Skeleton3D:mixamorig_Hips"),
## без построения пути от self (иначе лишний префикс "Model/" не резолвится → root motion = 0).
func _find_root_motion_path() -> NodePath:
	if _ap == null:
		return NodePath()
	for clip in [&"penalty_kick_r", &"penalty_kick_l"]:
		if not _ap.has_animation(clip):
			continue
		var anim := _ap.get_animation(clip)
		for ti in range(anim.get_track_count()):
			if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
				continue
			if String(anim.track_get_path(ti)).to_lower().contains("hips"):
				return anim.track_get_path(ti)
	return NodePath()

## Горизонтальное продвижение корня за прошедший кадр (игровые метры). Знак игнорируем — разбег
## прямой, контроллер двигает тело вперёд (к воротам) на эту величину. 0, если трека нет.
func consume_root_motion() -> float:
	if _anim_tree == null or _anim_tree.root_motion_track == NodePath():
		return 0.0
	var d: Vector3 = _anim_tree.get_root_motion_position()
	# POSITION-трек Hips в этом glb хранится в «сырых» единицах (импорт не проставил motion_scale),
	# поэтому get_root_motion_position() ≈ ×27 от игровых метров. PEN_ROOT_SCALE калибрует raw→метры
	# (замерено tools/measure_penalty_runup.gd: raw-путь до контакта ↔ реальный разбег Hips ~3м).
	return Vector2(d.x, d.z).length() * FootballConstants.PEN_ROOT_SCALE

## Стейт локомоции со скоростью клипа: Animation("clip") → TimeScale("speed") → output.
func _make_speed_state(clip: StringName) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var anim := AnimationNodeAnimation.new()
	anim.animation = clip
	bt.add_node(&"clip", anim, Vector2(100, 100))
	var ts := AnimationNodeTimeScale.new()
	bt.add_node(&"speed", ts, Vector2(300, 100))
	bt.connect_node(&"speed", 0, &"clip")
	bt.connect_node(&"output", 0, &"speed")
	return bt

## Переход StateMachine. auto_return=true → авто-возврат в конце клипа (AT_END/AUTO, без кроссфейда;
## сейчас не используется — ACTION-возврат делает IMMEDIATE+xfade); иначе — переход по travel() с кроссфейдом.
func _make_transition(auto_return: bool) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	if auto_return:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	else:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		t.xfade_time = 0.15
	return t

func _process(delta: float) -> void:
	if _anim_tree == null or delta <= 0.0:
		return
	var speed: float
	if _explicit_speed >= 0.0:
		speed = _explicit_speed
	else:
		var d := global_position - _last_pos
		d.y = 0.0
		speed = d.length() / delta
	_last_pos = global_position
	# Выбор стейта локомоции по порогам скорости (пока не идёт action).
	if _active_action == "" and not _fall_lock and _playback != null:
		var want := LOCOMOTION
		if _loco_style == LOCO_STYLE_KEEPER:
			if speed >= FootballConstants.LOCO_RUN_ANIM_SPEED and _sm_has(LOCO_KEEPER_SIDE):
				want = LOCO_KEEPER_SIDE
			elif _sm_has(LOCO_KEEPER_IDLE):
				want = LOCO_KEEPER_IDLE   # стойка готовности вместо обычного idle
		else:
			if speed >= FootballConstants.LOCO_SPRINT_ANIM_SPEED:
				want = LOCO_SPRINT
			elif speed >= FootballConstants.LOCO_RUN_ANIM_SPEED:
				want = LOCO_RUN
		if _playback.get_current_node() != want:
			_playback.travel(want)
	# Анти-слайд: скорость клипов run/sprint по реальной скорости.
	_anim_tree.set("parameters/sm/%s/speed/scale" % LOCO_RUN,
		PlayerVisual.run_timescale(speed, FootballConstants.LOCO_TOP_SPEED, FootballConstants.LOCO_RUN_SCALE_FUDGE))
	_anim_tree.set("parameters/sm/%s/speed/scale" % LOCO_SPRINT,
		PlayerVisual.run_timescale(speed, FootballConstants.LOCO_SPRINT_SPEED, FootballConstants.LOCO_RUN_SCALE_FUDGE))
	if _sm_has(LOCO_KEEPER_SIDE):
		_anim_tree.set("parameters/sm/%s/speed/scale" % LOCO_KEEPER_SIDE,
			PlayerVisual.run_timescale(speed, FootballConstants.LOCO_TOP_SPEED, FootballConstants.LOCO_RUN_SCALE_FUDGE))

	if _active_action != "":
		_action_elapsed += delta
		if not _action_contact_done and _action_elapsed >= _action_contact_at:
			_action_contact_done = true
			action_contact.emit(_active_action)
		if _action_elapsed >= _action_lock_at:
			var done := _active_action
			_active_action = ""
			_set_action_speed(1.0)
			action_finished.emit(done)
	# root_motion_track снимаем ПОСЛЕ завершения кроссфейда в локомоцию, а НЕ на lock: если снять
	# посреди фейда, выдвинутая вперёд поза удара (Hips применяются) блендится в idle → тело «съезжает
	# назад». Пока фейд идёт (get_fading_from_node != "") — держим извлечение (обе позы в rest).
	if _anim_tree != null and _active_action == "" and _playback != null \
			and _anim_tree.root_motion_track != NodePath():
		var cur := _playback.get_current_node()
		var in_loco := cur == LOCOMOTION or cur == LOCO_RUN or cur == LOCO_SPRINT \
			or cur == LOCO_KEEPER_IDLE or cur == LOCO_KEEPER_SIDE
		if in_loco and _playback.get_fading_from_node() == StringName():
			_anim_tree.root_motion_track = NodePath()

## Явно задать скорость (для будущих геймплей-вызовов). Vector3.ZERO → снова авто-замер.
func set_locomotion(velocity: Vector3) -> void:
	_explicit_speed = Vector3(velocity.x, 0.0, velocity.z).length()

## Стиль локомоции: NORMAL (idle/run/sprint) или KEEPER (idle/keeper_sidestep, без спринта).
func set_locomotion_style(style: int) -> void:
	_loco_style = style

## Есть ли стейт локомоции с таким именем (для тестов).
func has_loco_state(state_name: StringName) -> bool:
	return _anim_tree != null and _anim_tree.tree_root != null and _sm_has(state_name)

func _sm_has(state_name: StringName) -> bool:
	if _anim_tree == null or _anim_tree.tree_root == null:
		return false
	var sm := (_anim_tree.tree_root as AnimationNodeBlendTree).get_node(&"sm") as AnimationNodeStateMachine
	return sm != null and sm.has_node(state_name)

## Разовое действие (kick/pass/header/…): travel в one-shot стейт + запуск таймингового
## драйвера (сигналы action_contact/action_finished). Возвращает true, если действие
## стартовало (иначе — фолбэк/нет клипа, геймплей делает импульс сам).
func trigger(action: String) -> bool:
	if _playback == null:
		push_warning("PlayerVisual.trigger('%s'): AnimationTree не готов (фолбэк-капсула?)" % action)
		return false
	var state := _resolve_action(action)
	if state == "":
		push_warning("PlayerVisual.trigger('%s'): нет клипа под это действие" % action)
		return false
	_playback.travel(StringName(state))
	# root motion — только для клипов удара пенальти (разбег), у остальных трек снят (иначе
	# извлечение Hips ломает вертикаль их поз).
	if _anim_tree != null:
		if action == "penalty_l" or action == "penalty_r":
			_anim_tree.root_motion_track = _find_root_motion_path()
		else:
			_anim_tree.root_motion_track = NodePath()
	var contact := 0.0
	var lock := action_length(action)
	var speed := 1.0
	if ACTION_TIMING.has(action):
		var t: Dictionary = ACTION_TIMING[action]
		contact = float(t.get("contact", 0.0))
		lock = float(t.get("lock", lock))
		speed = float(t.get("speed", 1.0))
	if lock <= 0.0:
		lock = 0.5
	_set_action_speed(speed)
	_active_action = action
	_action_elapsed = 0.0
	_action_contact_at = contact
	_action_lock_at = lock
	_action_contact_done = false
	return true

## Отменить текущее действие без сигнала касания (напр., игрока сбили на замахе).
func cancel_action() -> void:
	if _active_action == "":
		return
	_active_action = ""
	_set_action_speed(1.0)
	if _playback != null:
		_playback.travel(LOCOMOTION)

## Проиграть one-shot клип (подкат/падение/перекат/вставание). Возвращает длину клипа (сек);
## 0.0, если клипа/стейта нет. Цепочку и тайминг ведёт вызывающий (match_manager).
## Длина one-shot клипа в секундах (0.0, если клипа нет). Нужна, чтобы посчитать скорость
## проигрывания ДО запуска (напр. вратарь синхронизирует пик сейва с подлётом мяча).
func clip_length(clip: StringName) -> float:
	if _ap != null and _ap.has_animation(clip):
		return _ap.get_animation(clip).length
	return 0.0


func play_oneshot(clip: StringName, speed: float = 1.0) -> float:
	if _playback == null or not _states.has(String(clip)):
		return 0.0
	_fall_lock = true
	_active_action = ""
	_set_action_speed(speed)   # скорость проигрывания one-shot (нырок вратаря ускоряем)
	_playback.travel(clip)
	if _ap != null and _ap.has_animation(clip):
		return _ap.get_animation(clip).length
	return 0.0

## Завершить падение: вернуть idle и снять fall-lock (возобновить локомоцию). Сбрасывает
## скорость проигрывания к 1.0 (её мог поднять ускоренный one-shot).
func recover() -> void:
	_fall_lock = false
	_set_action_speed(1.0)
	if _playback != null:
		_playback.travel(LOCOMOTION)

## Скорость проигрывания действия через TimeScale-узел BlendTree.
func _set_action_speed(s: float) -> void:
	if _anim_tree != null:
		_anim_tree.set(&"parameters/TimeScale/scale", s)

## action → имя стейта: сперва семантический маппинг ACTION_CLIPS, затем прямое имя клипа.
func _resolve_action(action: String) -> String:
	if ACTION_CLIPS.has(action) and _states.has(ACTION_CLIPS[action]):
		return ACTION_CLIPS[action]
	if _states.has(action):
		return action
	return ""

## Есть ли зарегистрированный one-shot стейт под это действие (для тестов/отладки).
func has_action(action: String) -> bool:
	return _resolve_action(action) != ""

## Длина клипа действия в секундах (0.0, если действия/клипа нет). Геймплей использует её
## для длительности commit-окна и тайминга касания мячом.
func action_length(action: String) -> float:
	var state := _resolve_action(action)
	if state == "" or _ap == null:
		return 0.0
	var anim := _ap.get_animation(StringName(state))
	return anim.length if anim != null else 0.0

## Заготовка под длящиеся состояния (sliding/fallen) — этапы 3c/3d.
func set_flag(flag: String, on: bool) -> void:
	push_warning("PlayerVisual.set_flag('%s', %s) ещё не реализован" % [flag, str(on)])

## Применить внешность при спавне. Пилот использует только "kit_color".
func apply_appearance(cfg: Dictionary) -> void:
	if cfg.has("kit_color"):
		var root: Node = _model if _model != null else self
		var n := PlayerVisual.tint_tree(root, cfg["kit_color"] as Color)
		if n == 0:
			push_warning("apply_appearance: не найдено мешей для тинта")

## Рекурсивно затинтить все MeshInstance3D под root. Возвращает число мешей.
static func tint_tree(root: Node, color: Color) -> int:
	var count := 0
	if root is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		(root as MeshInstance3D).material_override = mat
		count += 1
	for c in root.get_children():
		count += tint_tree(c, color)
	return count

func _use_fallback(reason: String) -> void:
	push_warning("PlayerVisual фолбэк-капсула: " + reason)
	var mesh := CapsuleMesh.new()
	mesh.height = 1.5
	mesh.radius = 0.3
	var mi := MeshInstance3D.new()
	mi.name = "FallbackCapsule"
	mi.mesh = mesh
	add_child(mi)

## Узел-«руки» на кости кисти модели (BoneAttachment3D) — сюда вратарь приклеивает мяч, и он
## движется вместе с рукой. Ищет кость с "hand" в имени; при отсутствии скелета/кости → null.
var _hold_attachment: Node3D = null
func get_hold_attachment() -> Node3D:
	if _hold_attachment != null and is_instance_valid(_hold_attachment):
		return _hold_attachment
	var skel := _find_skeleton(_model)
	if skel == null:
		return null
	var bone_idx := -1
	for i in range(skel.get_bone_count()):
		var n := skel.get_bone_name(i).to_lower()
		if n.contains("righthand") or n.contains("right_hand"):
			bone_idx = i
			break
	if bone_idx < 0:
		for i in range(skel.get_bone_count()):
			if skel.get_bone_name(i).to_lower().contains("hand"):
				bone_idx = i
				break
	if bone_idx < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.name = "BallHold"
	skel.add_child(ba)
	ba.bone_name = skel.get_bone_name(bone_idx)
	_hold_attachment = ba
	return ba

func _find_skeleton(n: Node) -> Skeleton3D:
	if n == null:
		return null
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

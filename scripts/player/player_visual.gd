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
## Семантическое действие (trigger) → имя клипа в glb. Стейт создаётся, только если клип есть.
const ACTION_CLIPS := {
	"kick": "pass",
	"pass": "pass",
	"penalty": "penalty_kick",
	"header": "idle_header",
	"header_alt": "idle_header_2",
	"header_jump": "idle_header_jump",
	"throw_in": "throw_in",
}
## Клипы, которые нужно зациклить; остальные one-shot доигрывают и авто-возвращаются.
const LOOP_CLIPS := [&"idle", &"run", &"sprint", &"fallen_idle"]

## Дополнительные one-shot стейты (подкат/падение/перекаты/вставание): travel-only, без
## авто-возврата — цепочку падения ведёт match_manager. fallen_idle зациклен (LOOP_CLIPS)
## и служит удерживаемой позой «лежит» в фазе knockdown.
const ONESHOT_CLIPS := [&"tackle", &"fallen_idle", &"roll_left", &"roll_right", &"standing_up"]

## Тайминг действия (реальные секунды): contact — до касания; lock — общая длительность
## до action_finished; speed — множитель скорости проигрывания (сжать замах, сохранив синхрон).
## Тюнится визуальной приёмкой. Действия без записи → contact=0, lock=длина_клипа, speed=1.
const ACTION_TIMING := {
	"kick": {"contact": 0.35, "lock": 0.5, "speed": 1.0},
	"pass": {"contact": 0.2, "lock": 0.4, "speed": 1.5},
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
		sm.add_transition(clip, LOCOMOTION, _make_transition(true))
		_states[clip] = true

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
	_playback = _anim_tree.get(&"parameters/sm/playback")
	if _playback != null:
		_playback.start(LOCOMOTION)

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

## Переход StateMachine. auto_return=true → авто-возврат в конце клипа (AT_END/AUTO);
## иначе — переход только по travel() (ENABLED, без авто-срабатывания), с кроссфейдом.
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

## Явно задать скорость (для будущих геймплей-вызовов). Vector3.ZERO → снова авто-замер.
func set_locomotion(velocity: Vector3) -> void:
	_explicit_speed = Vector3(velocity.x, 0.0, velocity.z).length()

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
func play_oneshot(clip: StringName) -> float:
	if _playback == null or not _states.has(String(clip)):
		return 0.0
	_fall_lock = true
	_active_action = ""
	_playback.travel(clip)
	if _ap != null and _ap.has_animation(clip):
		return _ap.get_animation(clip).length
	return 0.0

## Завершить падение: вернуть idle и снять fall-lock (возобновить локомоцию).
func recover() -> void:
	_fall_lock = false
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

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

class_name PlayerVisual
extends Node3D

## Порог скорости (м/с), при котором бленд = полный бег (1.0).
const RUN_SPEED_FULL := 5.0
## Сглаживание бленда, 1/сек.
const BLEND_SMOOTH := 10.0

## Имя стейта локомоции в StateMachine.
const LOCOMOTION := &"locomotion"
## Семантическое действие (trigger) → имя клипа в glb. Стейт создаётся, только если клип есть.
const ACTION_CLIPS := {
	"kick": "strike_forward",
	"pass": "pass",
	"penalty": "penalty_kick",
	"header": "idle_header",
	"header_alt": "idle_header_2",
	"header_jump": "idle_header_jump",
	"throw_in": "throw_in",
}
## Клипы, которые нужно зациклить; остальные one-shot доигрывают и авто-возвращаются.
const LOOP_CLIPS := [&"idle", &"run", &"fallen_idle"]

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

## Чистое отображение скорости (м/с) в позицию бленда [0..1].
static func speed_to_blend(speed: float) -> float:
	return clampf(speed / RUN_SPEED_FULL, 0.0, 1.0)

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

	# Локомоция: idle(0) ↔ run(1), блендится по измеренной скорости.
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"idle"
	var run_node := AnimationNodeAnimation.new()
	run_node.animation = &"run"
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(idle_node, 0.0)
	loco.add_blend_point(run_node, 1.0)

	# StateMachine: локомоция — базовый стейт; каждое one-shot действие — свой стейт,
	# вход по travel() из локомоции, авто-возврат в локомоцию по концу клипа.
	var sm := AnimationNodeStateMachine.new()
	sm.add_node(LOCOMOTION, loco, Vector2(400, 100))
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
	var target := speed_to_blend(speed)
	_blend = lerpf(_blend, target, clampf(BLEND_SMOOTH * delta, 0.0, 1.0))
	_anim_tree.set(&"parameters/sm/locomotion/blend_position", _blend)

## Явно задать скорость (для будущих геймплей-вызовов). Vector3.ZERO → снова авто-замер.
func set_locomotion(velocity: Vector3) -> void:
	_explicit_speed = Vector3(velocity.x, 0.0, velocity.z).length()

## Разовое действие (kick/pass/header/…): travel в one-shot стейт, авто-возврат в локомоцию.
## Принимает семантическое имя (см. ACTION_CLIPS) либо прямое имя клипа.
func trigger(action: String) -> void:
	if _playback == null:
		push_warning("PlayerVisual.trigger('%s'): AnimationTree не готов (фолбэк-капсула?)" % action)
		return
	var state := _resolve_action(action)
	if state == "":
		push_warning("PlayerVisual.trigger('%s'): нет клипа под это действие" % action)
		return
	_playback.travel(StringName(state))

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

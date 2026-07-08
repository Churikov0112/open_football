class_name PlayerVisual
extends Node3D

## Порог скорости (м/с), при котором бленд = полный бег (1.0).
const RUN_SPEED_FULL := 5.0
## Сглаживание бленда, 1/сек.
const BLEND_SMOOTH := 10.0

@export var model_y_offset: float = 0.0
@export var model_yaw_deg: float = 0.0

var _anim_tree: AnimationTree
var _model: Node3D
var _last_pos: Vector3
var _blend: float = 0.0
var _explicit_speed: float = -1.0  # >=0 → использовать вместо авто-замера

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
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"idle"
	var run_node := AnimationNodeAnimation.new()
	run_node.animation = &"run"
	var bs := AnimationNodeBlendSpace1D.new()
	bs.add_blend_point(idle_node, 0.0)
	bs.add_blend_point(run_node, 1.0)
	_anim_tree = AnimationTree.new()
	_anim_tree.tree_root = bs
	add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(ap)
	_anim_tree.active = true

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
	_anim_tree.set(&"parameters/blend_position", _blend)

## Явно задать скорость (для будущих геймплей-вызовов). Vector3.ZERO → снова авто-замер.
func set_locomotion(velocity: Vector3) -> void:
	_explicit_speed = Vector3(velocity.x, 0.0, velocity.z).length()

## Заготовка под one-shot (kick/header) — реализуется на этапе полного набора анимаций.
func trigger(action: String) -> void:
	push_warning("PlayerVisual.trigger('%s') ещё не реализован (пилот: только idle/run)" % action)

## Заготовка под длящиеся состояния (sliding/fallen) — будущий этап.
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

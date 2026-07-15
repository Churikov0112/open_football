extends SceneTree
## Калибровка root motion: суммируем СЫРОЙ путь PlayerVisual.consume_root_motion() (get_root_motion_position
## без масштаба) до кадра контакта (1.35с). Реальный мировой разбег ≈ 3.0м (ground-truth по Hips).
## PEN_ROOT_SCALE = 3.0 / raw_path → тогда тело за разбег проезжает ровно PEN_RUNUP_DIST=3.0м.

var _visual: Node
var _raw: float = 0.0
var _elapsed: float = 0.0
var _triggered: bool = false
var _frames: int = 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/player_visual.tscn")
	_visual = scene.instantiate()
	get_root().add_child(_visual)

func _process(delta: float) -> bool:
	if not _triggered:
		_frames += 1
		_triggered = _visual.call("trigger", "penalty_r")
		if not _triggered and _frames > 20:
			print("MEASURE FAIL: trigger не сработал")
			return true
		return false
	_raw += _visual.call("consume_root_motion")
	_elapsed += delta
	for cp in _checkpoints:
		if not _printed.has(cp) and _elapsed >= cp:
			_printed[cp] = true
			print("CUMULATIVE_RUNUP_AT ", cp, "s = ", _raw)
	if _elapsed >= 1.55:
		return true
	return false

var _checkpoints := [0.9, 1.0, 1.1, 1.2, 1.35, 1.5]
var _printed := {}

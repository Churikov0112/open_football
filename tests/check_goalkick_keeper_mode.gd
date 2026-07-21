extends SceneTree
## Headless: set_goalkick_mode переводит вратаря в пассив (флаг + State.POSITION),
## и его _physics_process не двигает тело в этом режиме.

var _mm: Node
var _kb: Node
var _elapsed: float = 0.0
var _phase: int = 0
var _pos_on: Vector3 = Vector3.ZERO

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 0.15 and _phase == 0:
		_kb = _mm._keeper_brain
		if _kb == null:
			print("CHECK FAIL: нет _keeper_brain")
			return true
		_kb.set_goalkick_mode(true)
		if not _kb._goalkick_mode:
			print("CHECK FAIL: _goalkick_mode не выставился")
			return true
		if _kb._state != 0:   # State.POSITION == 0
			print("CHECK FAIL: state != POSITION после on, state=", _kb._state)
			return true
		_pos_on = _mm._keeper.global_position
		_phase = 1
		return false
	# Несколько кадров в режиме: тело не должно уезжать (physics_process рано выходит).
	if _phase == 1 and _elapsed > 0.5:
		var moved: float = _mm._keeper.global_position.distance_to(_pos_on)
		if moved > 0.25:
			print("CHECK FAIL: вратарь сместился в goalkick-режиме на ", moved)
			return true
		_kb.set_goalkick_mode(false)
		if _kb._goalkick_mode:
			print("CHECK FAIL: _goalkick_mode не снялся")
			return true
		print("CHECK PASS: goalkick_keeper_mode")
		quit(0)
		return true
	return false

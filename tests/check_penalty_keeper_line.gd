extends SceneTree
## Регресс: во время пенальти вратарь ДОЛЖЕН держаться на линии ворот. Баг был — если вратарь в
## момент старта пенальти двигался с Z-скоростью (выходил навстречу удару), остаточный импульс уносил
## его ВПЕРЁД с линии, а _penalty_hold правил только X (Z не корректировал) → «вратарь не на линии».
## Фикс: set_penalty_mode гасит остаточную скорость + _penalty_hold держит ОБЕ оси (X и Z-глубину).
## Детерминированно: даём вратарю Z-скорость, стартуем пенальти, следим, что Z остаётся на линии.

var _mm: Node
var _frames := 0
var _started := false
var _min_z := 999.0
var _max_z := -999.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)
	physics_frame.connect(_tick)

func _tick() -> void:
	_frames += 1
	if _frames < 15:
		return  # дать сцене осесть
	var keeper: Node3D = _mm.get(&"_keeper")
	var kbrain = _mm.get(&"_keeper_brain")
	if keeper == null or kbrain == null:
		return
	if not _started:
		_started = true
		keeper.velocity = Vector3(0, 0, 9.0)   # вратарь выходил навстречу удару в момент нажатия P
		_mm.get_node("PenaltyController").start_single(_mm.controlled_player, kbrain.goal_line_z)
		_frames = 100                          # окно наблюдения после старта пенальти
		return
	if _frames <= 100 + 90:
		_min_z = minf(_min_z, keeper.global_position.z)
		_max_z = maxf(_max_z, keeper.global_position.z)
		return
	var anchor_z := -52.0   # goal_line_z(-52.5) + into(1.0)*0.5 — точка стойки на линии
	var on_line: bool = absf(keeper.global_position.z - anchor_z) < 0.6
	var no_drift: bool = (_max_z - _min_z) < 1.0
	print("SMOKE: keeper z range [", _min_z, ", ", _max_z, "] final=", keeper.global_position)
	if on_line and no_drift:
		print("CHECK PASS: keeper holds the goal line through penalty AIM")
		quit(0)
	else:
		print("CHECK FAIL: on_line=", on_line, " no_drift=", no_drift, " final=", keeper.global_position)
		quit(1)

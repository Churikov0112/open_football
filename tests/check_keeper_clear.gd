extends SceneTree
## Полный цикл AI-вратаря (team_2, ворота Away на z=-52.5): удар во вратаря → ловля → HANDS →
## AIKeeperHandsIntent сам выносит мяч к центру (CLEAR_CENTER) → мяч УЛЕТАЕТ в поле, вратарь
## снова в POSITION. Ловит петлю «ловля→раздача→мгновенная повторная ловля своей же раздачи».
## Кикофф гасим: при старте матча он держит мяч в центре и сбрасывает инъекцию удара.
## Вратарь берётся через _team_away.keeper() (полей _keeper/_keeper_brain в менеджере больше нет).

var _frames := 0
var _match_root: Node = null
var _fired := false
var _caught_seen := false

func _initialize() -> void:
	var scene := load("res://scenes/match.tscn") as PackedScene
	_match_root = scene.instantiate()
	root.add_child(_match_root)
	physics_frame.connect(_tick)

func _keeper_body() -> Node:
	return _match_root._team_away.keeper()

func _keeper_state() -> int:
	var kb: Node = _keeper_body()
	if kb == null:
		return -1
	var brain: Node = kb.brain()
	return brain._state if brain != null else -1

func _tick() -> void:
	_frames += 1
	if _frames < 10:
		return  # дать сцене осесть
	var ball := _match_root.get_node("Ball") as RigidBody3D
	if not _fired:
		_fired = true
		_match_root.set_kickoff_active(false)   # живая игра: кикофф больше не держит мяч в центре
		# Удар прямо во вратаря (ворота Away на z=-52.5): ловля на уровне груди.
		ball.global_position = Vector3(0, 1.2, -40.0)
		ball.linear_velocity = Vector3.ZERO
		ball.launch(Vector3(0, 2.0, -28.0))
		return
	if ball.is_caught():
		_caught_seen = true
	if _frames % 30 == 0:
		print("[T] f=", _frames, " keeper_state=", _keeper_state(), " ball_state=", ball.state,
			" celebrating=", _match_root.is_celebrating(), " ball=", ball.global_position)
	# Через ~6 секунд весь сценарий (ловля ~0.5с + HANDS-think ~0.8с + вынос) обязан завершиться:
	# мяч не в руках/не ведётся и унесён от ворот в поле.
	if _frames >= 10 + 360:
		if not _caught_seen:
			print("CHECK FAIL: keeper never caught the ball")
			quit(1)
			return
		var keeper_body := _keeper_body()
		if ball.is_caught() or ball.dribbler == keeper_body:
			print("CHECK FAIL: ball still held/dribbled after cycle; pos=", ball.global_position)
			quit(1)
			return
		if ball.global_position.z < -44.0:
			print("CHECK FAIL: ball still near goal (sequence stalled?); pos=", ball.global_position)
			quit(1)
			return
		print("CHECK PASS")
		quit(0)

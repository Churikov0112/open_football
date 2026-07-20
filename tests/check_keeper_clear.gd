extends SceneTree
## Полный цикл вратаря (АКТИВНАЯ раздача — бросок верхом): ловля → HOLD → THROWING → мяч УЛЕТАЕТ
## навесом в поле, вратарь снова в POSITION. Ловит петлю «ловля→раздача→мгновенная повторная
## ловля своей же раздачи» (собственный бросок не должен считаться ударом — гейт _heading_at_goal).

var _frames := 0
var _match_root: Node = null
var _fired := false
var _caught_seen := false

func _initialize() -> void:
	var scene := load("res://scenes/match.tscn") as PackedScene
	_match_root = scene.instantiate()
	root.add_child(_match_root)
	physics_frame.connect(_tick)

func _tick() -> void:
	_frames += 1
	if _frames < 10:
		return  # дать сцене осесть
	var ball := _match_root.get_node("Ball") as RigidBody3D
	if not _fired:
		_fired = true
		# Удар прямо во вратаря (ворота Home на z=-52.5): ловля на уровне груди.
		ball.global_position = Vector3(0, 1.2, -40.0)
		ball.linear_velocity = Vector3.ZERO
		ball.launch(Vector3(0, 2.0, -28.0))
		return
	if ball.is_caught():
		_caught_seen = true
	if _frames % 30 == 0:
		var keeper = _match_root.get(&"_keeper")   # после рефактора вратарь под TeamAway — берём из поля менеджера
		var kst = keeper.get(&"_state") if keeper != null else -1
		print("[T] f=", _frames, " keeper_state=", kst, " ball_state=", ball.state,
			" celebrating=", _match_root.is_celebrating(), " ball=", ball.global_position)
	# Через ~6 секунд весь сценарий (ловля ~0.5с + HOLD 1с + THROWING ~1с + полёт навеса) обязан
	# завершиться: мяч не в руках/не ведётся и унесён броском от ворот в поле.
	if _frames >= 10 + 360:
		var keeper = _match_root.get(&"_keeper")   # после рефактора вратарь под TeamAway — берём из поля менеджера
		var kst = keeper.get(&"_state") if keeper != null else -1
		if not _caught_seen:
			print("CHECK FAIL: keeper never caught the ball")
			quit(1)
			return
		if ball.is_caught() or ball.dribbler == keeper:
			print("CHECK FAIL: ball still held/dribbled after cycle; pos=", ball.global_position)
			quit(1)
			return
		if ball.global_position.z < -44.0:
			print("CHECK FAIL: ball still near goal (sequence stalled?); pos=", ball.global_position)
			quit(1)
			return
		print("CHECK PASS")
		quit(0)

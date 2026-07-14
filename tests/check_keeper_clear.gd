extends SceneTree
## Полный цикл вратаря: ловля → HOLD → DISTRIBUTE (drop kick) → вынос → мяч УЛЕТАЕТ в поле.
## Ловит петлю «ловля→вынос→мгновенная повторная ловля своего же выноса» (вратарь раз за
## разом играет вынос, а мяч остаётся у него): собственный вынос не должен считаться ударом
## (гейт _heading_at_goal) и _reacting обязан сбрасываться при старте ловли.

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
		var keeper := _match_root.get_node_or_null("Keeper")
		var kst = keeper.get(&"_state") if keeper != null else -1
		print("[T] f=", _frames, " keeper_state=", kst, " ball_state=", ball.state,
			" celebrating=", _match_root.is_celebrating(), " ball=", ball.global_position)
	# Через ~5 секунд весь цикл (ловля ~0.5с + HOLD 1с + DISTRIBUTE ≤1.5с + полёт выноса)
	# обязан завершиться: мяч не в руках и заметно унесён от ворот в поле.
	if _frames >= 10 + 300:
		if not _caught_seen:
			print("CHECK FAIL: keeper never caught the ball")
			quit(1)
			return
		if ball.is_caught():
			print("CHECK FAIL: ball still caught after clear window; pos=", ball.global_position)
			quit(1)
			return
		if ball.global_position.z < -46.0:
			print("CHECK FAIL: ball still at the goal (re-catch loop?); pos=", ball.global_position)
			quit(1)
			return
		print("CHECK PASS")
		quit(0)

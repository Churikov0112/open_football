extends SceneTree
## Регресс: вратарь НЕ должен выходить далеко из ворот, когда мяч рядом со штрафной, но НЕ
## угрожает воротам (обычный пас/дриблинг между СВОИМИ игроками — мяч не в полёте В створ).
## Баг был: KeeperLogic.line_position реагировала на голую дистанцию мяча до линии ворот,
## независимо от того, летит ли мяч угрозой или просто лежит/передаётся рядом. Фикс: off-line
## advance теперь гейтится на ball.is_flight() and _heading_at_goal() (см. keeper_ai._position).

var _mm: Node
var _frames := 0
var _phase := 0
var _start_z := 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn") as PackedScene
	_mm = scene.instantiate()
	root.add_child(_mm)
	physics_frame.connect(_tick)

func _fail(msg: String) -> void:
	print("CHECK FAIL: ", msg)
	quit(1)

func _tick() -> void:
	_frames += 1
	if _frames < 15:
		return
	var keeper: Node3D = _mm._keeper_at(-_mm.field_length)
	var kbrain = keeper.brain() if keeper != null else null
	var ball := _mm.get_node("Ball") as RigidBody3D
	if keeper == null or kbrain == null:
		return
	var goal_line_z: float = kbrain.get(&"goal_line_z")
	match _phase:
		0:
			# Мяч рядом со штрафной (в 6м от линии), но ТРАПНУТ (дриблинг) — не угроза, не в полёте.
			# Дриблер должен стоять РЯДОМ с мячом — иначе lead-follow дриблинга утащит мяч обратно
			# к текущей позиции controlled_player (далеко от штрафной).
			var pos := Vector3(2.0, 0.5, goal_line_z + 6.0)
			_mm.controlled_player.global_position = pos
			ball.global_position = pos
			ball.linear_velocity = Vector3.ZERO
			if ball.has_method(&"set_dribbler"):
				ball.set_dribbler(_mm.controlled_player, true)
			_start_z = keeper.global_position.z
			_phase = 1
			_frames = 0
			return
		1:
			if _frames < 180:
				return
			# Базовая стойка теперь — глубина центра ВРАТАРСКОЙ площади (~2.75м), не линия ворот
			# (плейтест-фикс). Регресс ловит именно «выбегание» (~14м как в исходном баге):
			# вратарь обязан остаться В ПРЕДЕЛАХ вратарской площади.
			var off_line: float = absf(keeper.global_position.z - goal_line_z)
			print("SMOKE: keeper z=", keeper.global_position.z, " goal_line_z=", goal_line_z, " off_line=", off_line)
			if off_line > FootballConstants.GOAL_AREA_DEPTH + 0.5:
				_fail("keeper advanced " + str(off_line) + "m off the line for a non-threatening dribbled ball near the box")
				return
			print("CHECK PASS: keeper does not rush out for a dribbled/passed ball near the box (no shot threat)")
			quit(0)
			return

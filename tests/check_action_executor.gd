extends SceneTree
## Фаза 3a: ActionExecutor резолвит запрос действия в импульс мяча. Гоняем на реальной сцене
## (как check_penalty_flow): ставим мяч игроку в ноги, зовём fire_pass, армим коммит, форсим
## контакт анимации (on_action_contact) и проверяем, что мячу придан импульс. Плюс — что геттеры
## action_player()/is_kick_action_active() отражают состояние коммита.

var _mm: Node
var _ax: Node
var _frames := 0
var _phase := 0
var _armed_ok := false

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)
	physics_frame.connect(_tick)

func _fail(m: String) -> void:
	print("CHECK FAIL: ", m); quit(1)

func _tick() -> void:
	_frames += 1
	if _frames < 15:
		return
	var ball := _mm.get_node("Ball") as RigidBody3D
	var player: Node3D = _mm.get(&"controlled_player")
	_ax = _mm.get(&"_action_executor")
	if _ax == null:
		_fail("нет _action_executor"); return
	if player == null:
		_fail("нет controlled_player"); return
	match _phase:
		0:
			# Кикофф при старте матча держит мяч в центре и глушит нашу инъекцию (тест старше
			# авто-кикоффа) — гасим, как в check_keeper_clear/HANDS-тестах.
			_mm.set_kickoff_active(false)
			# Мяч в ноги игроку, гасим его скорость — чистая точка старта паса.
			ball.global_position = player.global_position + Vector3(0, 0.1, 0)
			ball.linear_velocity = Vector3.ZERO
			# PASS_SHORT = значение enum ChargeAction в менеджере; берём через сам менеджер, чтобы
			# не зависеть от числового значения.
			var pass_short: int = MatchManager.ChargeAction.PASS_SHORT
			_ax.fire_pass(pass_short, player, 0.7)
			# Коммит армирован: action_player выставлен, kick-флаг для паса = true.
			_armed_ok = _ax.action_player() == player and _ax.is_kick_action_active()
			_phase = 1
			return
		1:
			# Форсим контакт анимации → импульс.
			_ax.on_action_contact("pass", player)
			_phase = 2
			_frames = 0
			return
		2:
			if _frames < 3:
				return
			var launched: bool = ball.linear_velocity.length() > 1.0
			print("SMOKE: armed=", _armed_ok, " ball_speed=", ball.linear_velocity.length())
			if _armed_ok and launched:
				print("CHECK PASS: ActionExecutor.fire_pass arms the commit and on_action_contact launches the ball")
				quit(0)
			else:
				_fail("armed=" + str(_armed_ok) + " launched=" + str(launched))

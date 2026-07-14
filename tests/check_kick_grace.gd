extends SceneTree
## Репро «самоблока» удара с места: игрок стоит ВПЛОТНУЮ к мячу (капсула перекрывает мяч —
## вне полёта мяч прозрачен для капсул, так бывает после авто-добегания к мячу), затем удар.
## Без анти-самоблок-грейса включение коллизии мяч↔игроки в launch() даёт мгновенный контакт
## с САМИМ бьющим → _on_ball_collision → block_in_flight → мяч тихо падает в OPEN и вратарь
## удара не видит. С грейсом мяч обязан остаться в FLIGHT и керпер — задетектить удар.

var _frames := 0
var _match_root: Node = null
var _fired := false

func _initialize() -> void:
	var scene := load("res://scenes/match.tscn") as PackedScene
	_match_root = scene.instantiate()
	root.add_child(_match_root)
	physics_frame.connect(_tick)

func _tick() -> void:
	_frames += 1
	if _frames < 10:
		return  # дать сцене осесть (спавны, скрипты, привязки)
	var ball := _match_root.get_node("Ball") as RigidBody3D
	var player := _match_root.get_node("PlayerHome") as CharacterBody3D
	if not _fired:
		_fired = true
		# Игрок СТОИТ НА мяче (перекрытие капсулой) — худший случай удара с места.
		player.global_position = Vector3(0, 0.5, -30.0)
		ball.global_position = Vector3(0, 0.11, -30.05)
		ball.linear_velocity = Vector3.ZERO
		ball.set_dribbler(player, true)
		ball.launch(Vector3(0, 3.0, -30.0))  # удар в сторону ворот Home (-Z)
		return
	if _frames <= 40:  # ~0.5 с полёта под наблюдением
		if not ball.is_flight():
			print("CHECK FAIL: ball left FLIGHT at frame ", _frames - 10, " state=", ball.state,
				" pos=", ball.global_position, " vel=", ball.linear_velocity.length())
			quit(1)
		return
	print("CHECK PASS")
	quit(0)

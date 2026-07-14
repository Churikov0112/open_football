extends SceneTree

# Headless-проверка стейт-машины мяча: переходы OPEN/TRAPPED/FLIGHT и launch_curl().
# Не проверяет физику/ощущение — только наблюдаемое состояние API. Всё синхронно в
# _initialize: методы стейт-машины не зависят от _ready/физических кадров.

func _initialize() -> void:
	var ok := true
	var ball := RigidBody3D.new()
	ball.set_script(load("res://scripts/ball/ball_controller.gd"))
	root.add_child(ball)

	var stub := Node3D.new()
	root.add_child(stub)

	# Нейтрализуем стартовый release-cooldown: в headless Time.get_ticks_msec() при запуске
	# может быть < _release_cooldown_msec, и первый set_dribbler иначе рано выйдет, «съев» трап.
	ball._last_release_time = -100000

	# Старт — OPEN.
	ok = _expect(ball.state == ball.BallState.OPEN, "начальное состояние OPEN") and ok

	# set_dribbler → TRAPPED, player == stub.
	ball.set_dribbler(stub)
	ok = _expect(ball.state == ball.BallState.TRAPPED, "set_dribbler → TRAPPED") and ok
	ok = _expect(ball.player() == stub, "player() == владелец") and ok
	ok = _expect(ball.dribbler == stub, "dribbler-обёртка == владелец") and ok

	# release_dribble → OPEN, player == null.
	ball.release_dribble()
	ok = _expect(ball.state == ball.BallState.OPEN, "release_dribble → OPEN") and ok
	ok = _expect(ball.player() == null, "player() == null после release") and ok

	# kick → FLIGHT, _curl обнулён (прямой удар не крутится).
	ball._last_release_time = -100000
	ball.set_dribbler(stub)
	ball.kick(Vector3.FORWARD, 15.0)
	ok = _expect(ball.state == ball.BallState.FLIGHT, "kick → FLIGHT") and ok
	ok = _expect(ball._curl.length() < 0.001, "kick обнуляет _curl") and ok

	# launch_curl → FLIGHT, _curl задан.
	ball.release_dribble()
	ball.launch_curl(Vector3(0, 0, -20), Vector3(0, 0, 3))
	ok = _expect(ball.state == ball.BallState.FLIGHT, "launch_curl → FLIGHT") and ok
	ok = _expect(ball._curl.length() > 0.01, "launch_curl задаёт _curl") and ok

	# parry: гасит скорость, перенаправляет наружу, роняет в OPEN.
	ball.state = ball.BallState.FLIGHT
	ball.linear_velocity = Vector3(0, 0, 20)   # летит в ворота (+Z)
	ball.parry(Vector3(0, 0, -1), 0.3)          # отбой наружу (-Z)
	ok = _expect(ball.state == ball.BallState.OPEN, "parry → OPEN") and ok
	ok = _expect(ball.linear_velocity.z < 0.0, "parry перенаправляет наружу") and ok
	ok = _expect(ball.linear_velocity.length() <= 20.0 * 0.3 + 6.1, "parry гасит скорость") and ok

	if ok:
		print("CHECK PASS")
		quit(0)
	else:
		print("CHECK FAIL")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

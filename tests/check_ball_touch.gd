extends SceneTree
## Headless-проверка трекинга касаний мяча (last_touch). Не чистится при блоке/релизе,
## в отличие от last_kicker. Всё синхронно — методы не зависят от физкадров.

func _initialize() -> void:
	var ok := true
	var ball := RigidBody3D.new()
	ball.set_script(load("res://scripts/ball/ball_controller.gd"))
	root.add_child(ball)
	var a := Node3D.new()
	root.add_child(a)
	var b := Node3D.new()
	root.add_child(b)
	ball._last_release_time = -100000

	ok = _expect(ball.last_touch == null, "старт: last_touch == null") and ok

	# Трап (set_dribbler) записывает касание.
	ball.set_dribbler(a)
	ok = _expect(ball.last_touch == a, "set_dribbler → last_touch = a") and ok

	# Удар записывает бьющего (a — текущий владелец).
	ball.kick(Vector3.FORWARD, 15.0)
	ok = _expect(ball.last_touch == a, "kick → last_touch = a") and ok

	# Блок НЕ чистит last_touch (в отличие от last_kicker/clear).
	ball.block_in_flight()
	ok = _expect(ball.last_touch == a, "block_in_flight не чистит last_touch") and ok

	# clear_last_kicker чистит kicker, но НЕ touch.
	ball.clear_last_kicker()
	ok = _expect(ball.last_kicker == null and ball.last_touch == a, "clear_last_kicker не трогает last_touch") and ok

	# Явное касание другим игроком.
	ball.note_touch(b)
	ok = _expect(ball.last_touch == b, "note_touch(b) → last_touch = b") and ok

	# Ловля вратарём (catch) записывает holder.
	var hold := Node3D.new()
	root.add_child(hold)
	ball.catch(a, hold)
	ok = _expect(ball.last_touch == a, "catch → last_touch = holder") and ok

	if ok:
		print("CHECK PASS: ball_touch")
		quit(0)
	else:
		print("CHECK FAIL: ball_touch")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

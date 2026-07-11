extends SceneTree

# Headless-проверка чистых функций ShotSystem (детерминизм через seeded RNG).

func _initialize() -> void:
	var ok := true
	var g := 20.0  # тестовая гравитация

	# wants_clearance: близко и лицом к воротам → НЕ вынос.
	ok = _expect(not ShotSystem.wants_clearance(Vector3(0,0,0), Vector3(0,0,-20), Vector3(0,0,-1), 30.0, 0.3), "близко+лицом → удар") and ok
	# далеко → вынос.
	ok = _expect(ShotSystem.wants_clearance(Vector3(0,0,0), Vector3(0,0,-40), Vector3(0,0,-1), 30.0, 0.3), "далеко → вынос") and ok
	# спиной к воротам → вынос.
	ok = _expect(ShotSystem.wants_clearance(Vector3(0,0,0), Vector3(0,0,-10), Vector3(0,0,1), 30.0, 0.3), "спиной → вынос") and ok

	# goal_aim_point: side_bias +1 → x у правой штанги; заряд выше → y выше. RNG сидирован.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var pr := ShotSystem.goal_aim_point(Vector3(0,0,-52.5), 3.66, 2.44, 1.0, 0.2, 0.25, 0.0, 0.0, rng)
	ok = _expect(pr.x > 3.0 and pr.z == -52.5, "side_bias +1 → правый угол створа") and ok
	var pl := ShotSystem.goal_aim_point(Vector3(0,0,-52.5), 3.66, 2.44, -1.0, 0.2, 0.25, 0.0, 0.0, rng)
	ok = _expect(pl.x < -3.0, "side_bias -1 → левый угол") and ok
	var low := ShotSystem.goal_aim_point(Vector3(0,0,-52.5), 3.66, 2.44, 0.0, 0.0, 0.25, 0.0, 0.0, rng)
	var high := ShotSystem.goal_aim_point(Vector3(0,0,-52.5), 3.66, 2.44, 0.0, 1.0, 0.25, 0.0, 0.0, rng)
	ok = _expect(high.y > low.y, "больше заряд → выше точка") and ok

	# goal_assist: assist=0 → без изменений; assist=1 → широкий прицел зажат в раму; частично → тянет внутрь.
	var wide := Vector3(10.0, 5.0, -52.5)  # заведомо мимо (x за штангой, y над перекладиной)
	var a0 := ShotSystem.goal_assist(wide, Vector3(0,0,-52.5), 3.66, 2.44, 0.0, 0.4)
	ok = _expect(a0 == wide, "assist=0 → прицел не меняется") and ok
	var a1 := ShotSystem.goal_assist(wide, Vector3(0,0,-52.5), 3.66, 2.44, 1.0, 0.4)
	ok = _expect(a1.x <= 3.66 - 0.4 + 0.001 and a1.y <= 2.44 - 0.4 + 0.001, "assist=1 → зажат в раму") and ok
	var ah := ShotSystem.goal_assist(wide, Vector3(0,0,-52.5), 3.66, 2.44, 0.5, 0.4)
	ok = _expect(ah.x < wide.x and ah.x > a1.x, "assist=0.5 → тянет внутрь, но не до конца") and ok

	# ballistic_to: с возвращённой скоростью мяч в точке to в момент t (по геометрии).
	var from := Vector3(0, 0.11, 0)
	var to := Vector3(0, 1.2, -20)
	var v := ShotSystem.ballistic_to(from, to, 18.0, g)
	var flat := Vector3(v.x, 0, v.z)
	var t := 20.0 / 18.0
	var y_at_t := from.y + v.y * t - 0.5 * g * t * t
	ok = _expect(absf(y_at_t - to.y) < 0.05, "ballistic_to попадает по высоте в момент t") and ok
	ok = _expect(absf(flat.length() - 18.0) < 0.01, "горизонтальная скорость == заданной") and ok

	# curl_vector: .z = side*strength, .y = lift.
	var cv := ShotSystem.curl_vector(-1.0, 5.0, 2.0)
	ok = _expect(absf(cv.z + 5.0) < 0.001 and absf(cv.y - 2.0) < 0.001, "curl_vector раскладка") and ok

	# clearance_velocity: направление + подъём.
	var clv := ShotSystem.clearance_velocity(Vector3(1,0,0), 20.0, 5.0)
	ok = _expect(absf(clv.x - 20.0) < 0.01 and absf(clv.y - 5.0) < 0.01, "clearance по X + подъём") and ok

	# scatter_meters: растёт с зарядом.
	ok = _expect(ShotSystem.scatter_meters(1.0, 1.0, 20.0, 20.0) > ShotSystem.scatter_meters(1.0, 0.0, 20.0, 20.0), "разброс растёт с зарядом") and ok

	# one_touch_ratio: база + вклад скорости, кламп в 0..1.
	ok = _expect(absf(ShotSystem.one_touch_ratio(0.2, 0.0, 0.02) - 0.2) < 0.001, "нет скорости → ratio = база") and ok
	ok = _expect(absf(ShotSystem.one_touch_ratio(0.2, 20.0, 0.02) - 0.6) < 0.001, "скорость 20 при gain 0.02 → +0.4") and ok
	ok = _expect(ShotSystem.one_touch_ratio(0.5, 100.0, 0.02) == 1.0, "быстрый мяч → кламп до 1.0") and ok
	ok = _expect(ShotSystem.one_touch_ratio(-0.5, 0.0, 0.02) == 0.0, "кламп снизу до 0.0") and ok

	if ok:
		print("CHECK PASS"); quit(0)
	else:
		print("CHECK FAIL"); quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

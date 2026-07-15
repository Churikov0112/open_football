extends SceneTree
## Headless-проверка чистых функций PenaltyLogic.

func _init() -> void:
	var ok := true
	ok = _check_spread_monotonic() and ok
	ok = _check_power_monotonic() and ok
	ok = _check_disc_within_radius() and ok
	ok = _check_reticle_clamp() and ok
	ok = _check_zone_coverage() and ok
	ok = _check_zone_target_frame() and ok
	ok = _check_plane_point() and ok
	if ok:
		print("CHECK PASS: penalty_logic")
		quit(0)
	else:
		print("CHECK FAIL: penalty_logic")
		quit(1)

func _check_spread_monotonic() -> bool:
	var a := PenaltyLogic.spread_radius(0.0, 0.15, 1.6)
	var b := PenaltyLogic.spread_radius(1.0, 0.15, 1.6)
	if not (is_equal_approx(a, 0.15) and is_equal_approx(b, 1.6) and b > a):
		print("  FAIL spread_monotonic: ", a, " ", b)
		return false
	return true

func _check_power_monotonic() -> bool:
	var a := PenaltyLogic.power_speed(0.0, 18.0, 34.0)
	var b := PenaltyLogic.power_speed(1.0, 18.0, 34.0)
	if not (is_equal_approx(a, 18.0) and is_equal_approx(b, 34.0)):
		print("  FAIL power_monotonic: ", a, " ", b)
		return false
	return true

func _check_disc_within_radius() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var center := Vector2(1.0, 1.0)
	for i in range(500):
		var p := PenaltyLogic.sample_in_disc(center, 0.8, rng)
		if p.distance_to(center) > 0.8 + 0.0001:
			print("  FAIL disc_within_radius at i=", i, " d=", p.distance_to(center))
			return false
	return true

func _check_reticle_clamp() -> bool:
	# Уводим стиком далеко вправо-вверх — должно клампиться в рамку+овершут.
	var cur := Vector2.ZERO
	for i in range(200):
		cur = PenaltyLogic.move_reticle(cur, Vector2(1, 1), 6.0, 0.1, 3.66, 2.44, 0.6)
	if cur.x > 3.66 + 0.6 + 0.0001 or cur.y > 2.44 + 0.6 + 0.0001:
		print("  FAIL reticle_clamp: ", cur)
		return false
	# Вниз клампится к 0.
	for i in range(200):
		cur = PenaltyLogic.move_reticle(cur, Vector2(0, -1), 6.0, 0.1, 3.66, 2.44, 0.6)
	if cur.y < -0.0001:
		print("  FAIL reticle_clamp low: ", cur)
		return false
	return true

func _check_zone_coverage() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var seen := {}
	for i in range(500):
		seen[PenaltyLogic.random_dive_zone(rng)] = true
	for z in [PenaltyLogic.Zone.LOW_L, PenaltyLogic.Zone.HIGH_L, PenaltyLogic.Zone.LOW_R, PenaltyLogic.Zone.HIGH_R, PenaltyLogic.Zone.CENTER]:
		if not seen.has(z):
			print("  FAIL zone_coverage: не выпала зона ", z)
			return false
	return true

func _check_zone_target_frame() -> bool:
	var t := PenaltyLogic.zone_target(PenaltyLogic.Zone.HIGH_R, 0.0, 3.66, 0.4, 1.9, 2.6, -52.5)
	if absf(t.x) > 3.66 + 0.0001 or not is_equal_approx(t.y, 1.9) or not is_equal_approx(t.z, -52.5):
		print("  FAIL zone_target_frame: ", t)
		return false
	# Левая зона — x отрицательный.
	var l := PenaltyLogic.zone_target(PenaltyLogic.Zone.LOW_L, 0.0, 3.66, 0.4, 1.9, 2.6, -52.5)
	if l.x >= 0.0:
		print("  FAIL zone_target_frame left: ", l)
		return false
	return true

func _check_plane_point() -> bool:
	var w := PenaltyLogic.plane_point_to_world(Vector2(1.5, 1.2), 0.0, -52.5)
	if not (is_equal_approx(w.x, 1.5) and is_equal_approx(w.y, 1.2) and is_equal_approx(w.z, -52.5)):
		print("  FAIL plane_point: ", w)
		return false
	return true

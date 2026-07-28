extends SceneTree
## Headless-проверка чистых функций KickoffLogic. Не читает FootballConstants (см. класс).

func _init() -> void:
	var ok := true

	# clamp_to_own_half: team_1 (attack_z_sign=-1) → своя половина z>=0.
	var inside := KickoffLogic.clamp_to_own_half(Vector3(3.0, 0.5, 5.0), -1.0, 1.0)
	ok = _expect(inside.is_equal_approx(Vector3(3.0, 0.5, 5.0)), "clamp: уже на своей половине — не трогать") and ok

	var outside := KickoffLogic.clamp_to_own_half(Vector3(3.0, 0.5, -5.0), -1.0, 1.0)
	ok = _expect(is_equal_approx(outside.z, 1.0) and is_equal_approx(outside.x, 3.0), "clamp: с чужой на свою (z=margin)") and ok

	# team_2 (attack_z_sign=+1) → своя половина z<=0.
	var away_inside := KickoffLogic.clamp_to_own_half(Vector3(0.0, 0.5, -5.0), 1.0, 1.0)
	ok = _expect(is_equal_approx(away_inside.z, -5.0), "clamp team_2: уже на своей половине") and ok
	var away_outside := KickoffLogic.clamp_to_own_half(Vector3(0.0, 0.5, 5.0), 1.0, 1.0)
	ok = _expect(is_equal_approx(away_outside.z, -1.0), "clamp team_2: с чужой на свою") and ok

	# На самой линии (z=0) считаем «на своей» — не двигаем.
	var on_line := KickoffLogic.clamp_to_own_half(Vector3(2.0, 0.5, 0.0), -1.0, 1.0)
	ok = _expect(is_equal_approx(on_line.z, 0.0), "clamp: на линии не трогаем") and ok

	# signed_angle_xz: известные пары направлений.
	var a90 := KickoffLogic.signed_angle_xz(Vector3(0, 0, 1), Vector3(1, 0, 0))
	ok = _expect(absf(absf(a90) - PI * 0.5) < 0.01, "signed_angle: 90° по модулю") and ok
	var a0 := KickoffLogic.signed_angle_xz(Vector3(0, 0, 1), Vector3(0, 0, 1))
	ok = _expect(absf(a0) < 0.01, "signed_angle: совпадающие направления = 0") and ok
	var a_opp_sign := KickoffLogic.signed_angle_xz(Vector3(0, 0, 1), Vector3(-1, 0, 0))
	ok = _expect(signf(a_opp_sign) != signf(a90), "signed_angle: противоположный поворот — противоположный знак") and ok

	# kicker_placement: team_1 (attack_z_sign=-1) — смещение на ЧУЖУЮ половину (-Z), лицом на свою (+Z).
	var kp1 := KickoffLogic.kicker_placement(-1.0, 0.6, 0.5)
	ok = _expect(kp1["pos"].is_equal_approx(Vector3(0.0, 0.5, -0.6)), "kicker_placement team_1: позиция на чужой половине") and ok
	ok = _expect(kp1["base_heading"].is_equal_approx(Vector3(0.0, 0.0, 1.0)), "kicker_placement team_1: heading на свою половину") and ok
	# team_2 (attack_z_sign=+1) — зеркально: смещение на +Z (чужая для team_2), heading на -Z.
	var kp2 := KickoffLogic.kicker_placement(1.0, 0.6, 0.5)
	ok = _expect(kp2["pos"].is_equal_approx(Vector3(0.0, 0.5, 0.6)), "kicker_placement team_2: позиция на чужой половине") and ok
	ok = _expect(kp2["base_heading"].is_equal_approx(Vector3(0.0, 0.0, -1.0)), "kicker_placement team_2: heading на свою половину") and ok

	# coin_flip: детерминирован при фиксированном seed, оба исхода достижимы.
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42
	ok = _expect(KickoffLogic.coin_flip(rng_a) == KickoffLogic.coin_flip(rng_b), "coin_flip: один seed — один исход") and ok
	var seen := {}
	for s in range(50):
		var r := RandomNumberGenerator.new()
		r.seed = s
		seen[KickoffLogic.coin_flip(r)] = true
	ok = _expect(seen.has(1) and seen.has(2), "coin_flip: оба исхода достижимы (team_1/team_2) на разных seed") and ok

	if ok:
		print("CHECK PASS: kickoff_logic")
		quit(0)
	else:
		print("CHECK FAIL: kickoff_logic")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

extends SceneTree
# Фаза 4, задача 7: touch-векторы (humanoid_utils.cpp:146-520) + мосты TouchVectors.cs.
# Формулы перевычисляются в самом тесте с фиксированным сидом RNG (правило global-constraints:
# опорные числа — только из формул C++, не из плана).

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func _initialize() -> void:
	var ok := true
	var TV = load("res://src/gpf/TouchVectors.cs")
	var B = load("res://src/gpf/Ball.cs")
	var RNG = load("res://src/gpf/GpfRng.cs")
	if TV == null:
		print("CHECK FAIL: TouchVectors.cs не найден")
		quit(1)
		return

	# ---------- 1. GetDifficultyFactors: покой у ног → все факторы ~0 ----------
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -0.5, 0))
	var rng = RNG.new()
	rng.Reseed(7)
	var f: Dictionary = TV.GetDifficultyFactorsBridge(ball, Vector3.ZERO, Vector3.ZERO,
		Vector3(0, -1, 0), 0.0, 0.6, 0.0, 0.6, rng)
	# позиция+0.2·dir → до мяча ~0.3 м < 0.7 → fartherAwayPenalty = 0; скорости 0 → пенальти 0
	if not feq(float(f["distance"]), 0.0, 1.0e-3) or not feq(float(f["height"]), 0.0, 1.0e-3):
		print("CHECK FAIL: DifficultyFactors в покое: ", f)
		ok = false

	# ---------- 2. GetDifficultyFactors: перевычисление штрафа расстояния ----------
	# игрок в 1.3 м от мяча (по опорной точке pos+0.2·dir):
	# fartherAwayPenalty = pow(NormalizedClamp(1.3, 0.7, 1.3), 2)·2 (:163-170)
	rng.Reseed(7)
	var pos := Vector3(0, 1.0, 0)  # мяч в (0,-0.5) → расстояние от pos+0.2·(0,-1,0) до мяча = 1.3
	var f2: Dictionary = TV.GetDifficultyFactorsBridge(ball, Vector3.ZERO, pos,
		Vector3(0, -1, 0), 0.0, 0.6, 0.0, 0.6, rng)
	var far_pen: float = pow(clampf((1.3 - 0.7) / (1.3 - 0.7), 0.0, 1.0), 2.0) * 2.0
	var dist_exp: float = far_pen * 4.0  # :175 (остальные пенальти при нулевых скоростях — 0)
	# skillPenaltyMultiplier = (1-0.6·0.5)·random(0.5,1) (:198); random — первый вызов rng с сидом 7
	var rng2 = RNG.new()
	rng2.Reseed(7)
	var skill_mult: float = (1.0 - 0.6 * 0.5) * rng2.Uniform(0.5, 1.0)
	dist_exp = clampf(dist_exp * skill_mult, 0.0, 1.0)  # :199, :202
	if not feq(float(f2["distance"]), dist_exp, 1.0e-3):
		print("CHECK FAIL: distanceFactor ", f2["distance"], " != ", dist_exp)
		ok = false

	# ---------- 3. Детерминизм GetShotVector по сиду ----------
	var shot_args := {
		"desired_direction": Vector3(0, -1, 0),
		"desired_power": 0.8,
		"touch_velocity": Vector3(0, -5, 0),
	}
	rng.Reseed(99)
	var s1: Vector3 = TV.GetShotVectorBridge(ball, shot_args, rng)
	rng.Reseed(99)
	var s2: Vector3 = TV.GetShotVectorBridge(ball, shot_args, rng)
	if s1 != s2:
		print("CHECK FAIL: GetShotVector недетерминирован при одном сиде")
		ok = false
	if s1.length() < 5.0:
		print("CHECK FAIL: удар слабее разумного: ", s1.length())
		ok = false
	# удар прижат к желаемому направлению (y-компонента доминирует и отрицательна)
	if s1.y > -absf(s1.x):
		print("CHECK FAIL: удар не туда: ", s1)
		ok = false

	# ---------- 4. BallControl толкает мяч вперёд по ходу ----------
	rng.Reseed(3)
	var bc: Vector3 = TV.GetBallControlVectorBridge(ball, Vector3(0, -1, 0), 5.0, rng)
	if bc.y >= 0.0:
		print("CHECK FAIL: ballcontrol не вперёд: ", bc)
		ok = false

	# ---------- 5. BallBodyCollider: кулдаун 150 мс и отражение (match.cpp:1926-2045) ----------
	# Мяч летит на игрока (движение оппонента недавнее → oppLastTouchBias > 0.01), сегмент кости
	# прямо на пути мяча → мяч затронут, скорость упала (кап длиной текущего движения ×0.7).
	var ball2 = B.new()
	ball2.ResetSituation(Vector3.ZERO)
	ball2.Touch(Vector3(0, -8, 0))  # мяч едет в -Y
	# «нога» вплотную к мячу: AABB сегмента (±0.12 паддинг) накрывает центр мяча (0,0,0.11) —
	# сфера-против-AABB (aabb.cpp:130-143) даёт d=0 при любом ballRadius
	var segs := [Vector3(0, -0.1, 0.0), Vector3(0, -0.1, 1.0)]
	rng.Reseed(42)
	var speed_before: float = ball2.GetMovement().length()
	var r1: Dictionary = TV.CheckBallCollisionsBridge(ball2, segs, Vector3.ZERO, Vector3.ZERO,
		1, false, false, false, 0.0, 1.0, 1.0, 1.0, 0.0, 1000, 0, rng)  # functionType 1 == movement
	if not bool(r1["touched"]) or not bool(r1["accidental_touch"]):
		print("CHECK FAIL: коллизия мяч-тело не сработала: ", r1)
		ok = false
	elif ball2.GetMovement().length() > speed_before + 1.0e-3:
		# :2033 кап + :2035 ×0.7 — скорость после отскока не выше прежней
		print("CHECK FAIL: отскок разогнал мяч: ", ball2.GetMovement().length(), " > ", speed_before)
		ok = false
	if int(r1["last_collision_time_ms"]) != 1000:
		print("CHECK FAIL: кулдаун не выставлен: ", r1)
		ok = false
	# повтор в пределах 150 мс — молчок (:1931)
	var r2: Dictionary = TV.CheckBallCollisionsBridge(ball2, segs, Vector3.ZERO, Vector3.ZERO,
		1, false, false, false, 0.0, 1.0, 1.0, 1.0, 0.0, 1100, 1000, rng)
	if bool(r2["touched"]):
		print("CHECK FAIL: кулдаун 150 мс не удержал повторную коллизию")
		ok = false
	# designated + свежих касаний матча нет → контролируемая коллизия вместо отскока (:1996-1998)
	var ball3 = B.new()
	ball3.ResetSituation(Vector3.ZERO)
	ball3.Touch(Vector3(0, -8, 0))
	var r3: Dictionary = TV.CheckBallCollisionsBridge(ball3, segs, Vector3.ZERO, Vector3.ZERO,
		1, false, false, true, 0.0, 1.0, 1.0, 0.0, 0.0, 1000, 0, rng)
	if not bool(r3["controlled_collision"]) or bool(r3["touched"]):
		print("CHECK FAIL: controlled-ветка коллизии: ", r3)
		ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

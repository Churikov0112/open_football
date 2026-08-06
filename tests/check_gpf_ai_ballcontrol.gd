extends SceneTree
# AI_GetBallControlMovement (AIfunctions.cpp:893-940) и хвост _MovementCommand
# (playercontroller.cpp:590-601) — магнит ведения: игрок с мячом бежит НЕ по стрелке, а на мяч.
# Тест перевычисляет обе формулы по C++ и сверяет с портом.
#
# Ядро тут не тикает (мяч ставится руками, гуманоида нет) — маршалинг Gpf.* не задействован.

const DIST_TO_VELO := 2.6      # gamedefines.hpp:54
const TOUCH_OFFSET_MS := 80    # gamedefines.hpp:64
const IDLE := 0.0
const DRIBBLE := 3.5
const WALK := 5.0
const SPRINT := 8.0
const IDLE_DRIBBLE := 1.8
const DRIBBLE_WALK := 4.2
const WALK_SPRINT := 6.0

var _fails := 0


func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("  FAIL: ", msg)


func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps


func veq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return a.distance_to(b) < eps


# animcollection.hpp:57-62
func range_velocity(v: float) -> float:
	if v >= IDLE_DRIBBLE and v < DRIBBLE_WALK:
		return DRIBBLE
	elif v >= DRIBBLE_WALK and v < WALK_SPRINT:
		return WALK
	elif v >= WALK_SPRINT:
		return SPRINT
	return IDLE


func nclamp(v: float, lo: float, hi: float) -> float:
	return (clampf(v, lo, hi) - lo) / (hi - lo)


# Перевычисление AI_GetBallControlMovement: [направление, скорость, точка взгляда]
func expected(ball_pos_2d: Vector3, player_pos: Vector3, body_dir: Vector3,
		desired_velocity: float) -> Array:
	var to_ball: Vector3 = ball_pos_2d - player_pos              # :897
	var to_ball_distance: float = to_ball.length()               # :898

	var auto_bias := 1.0                                         # :903
	if to_ball_distance < 0.4:                                   # :904
		auto_bias = pow(nclamp(to_ball_distance, 0.2, 0.4), 0.5)  # :905-909

	var auto_dir: Vector3 = to_ball.normalized() if to_ball.length() > 1e-6 else body_dir  # :911
	# :912 — ввод игрока НЕ участвует, на его месте направление тела
	var best_dir: Vector3 = auto_dir * auto_bias + body_dir * (1.0 - auto_bias)  # :915
	best_dir = best_dir.normalized() if best_dir.length() > 1e-6 else body_dir   # :916

	var best_velocity: float = to_ball_distance * DIST_TO_VELO   # :923-924
	if best_velocity >= DRIBBLE:                                 # :927 (иначе не квантуем)
		best_velocity = clampf(desired_velocity, best_velocity, best_velocity + 8.0)  # :931-932
		if range_velocity(best_velocity) < best_velocity:
			best_velocity = best_velocity * 0.9 + range_velocity(best_velocity) * 0.1  # :933
		if range_velocity(best_velocity) > best_velocity:
			best_velocity = best_velocity * 0.1 + range_velocity(best_velocity) * 0.9  # :934

	return [best_dir, best_velocity, player_pos + best_dir * 10.0]  # :937


func _initialize() -> void:
	print("== check_gpf_ai_ballcontrol ==")

	var A = load("res://src/gpf/AiFunctions.cs")
	var B = load("res://src/gpf/Ball.cs")
	if A == null or B == null:
		_fail("нет AiFunctions.cs/Ball.cs — сначала dotnet build")
		_done()
		return

	# ---------- 1. Мяч далеко: направление ровно на мяч, скорость от дистанции ----------
	var cases := [
		{"ball": Vector3(3.0, 0.0, 0.0), "player": Vector3.ZERO, "dir": Vector3(0, -1, 0), "vel": SPRINT},
		{"ball": Vector3(0.0, -2.0, 0.0), "player": Vector3.ZERO, "dir": Vector3(1, 0, 0), "vel": DRIBBLE},
		{"ball": Vector3(-1.5, 1.5, 0.0), "player": Vector3(1.0, 1.0, 0.0), "dir": Vector3(0, 1, 0), "vel": WALK},
		{"ball": Vector3(0.35, 0.0, 0.0), "player": Vector3.ZERO, "dir": Vector3(0, -1, 0), "vel": SPRINT},  # ближняя зона
		{"ball": Vector3(0.15, 0.0, 0.0), "player": Vector3.ZERO, "dir": Vector3(0, -1, 0), "vel": SPRINT},  # ближе порога
	]
	for c in cases:
		var ball = B.new()
		ball.ResetSituation(c["ball"])  # мяч в покое: Predict(любое) = позиция + (0,0,0.11)
		var got: Array = A.DescribeBallControlMovement(ball, c["player"], c["dir"], Vector3(1, 0, 0), c["vel"])
		# мост возвращает [время, направление, скорость, точка взгляда]
		var want: Array = expected(Vector3(c["ball"].x, c["ball"].y, 0.0), c["player"], c["dir"], c["vel"])
		if not veq(got[1], want[0]):
			_fail("направление для мяча %s: %s, ожидалось %s" % [c["ball"], got[1], want[0]])
		if not feq(got[2], want[1]):
			_fail("скорость для мяча %s: %.4f, ожидалось %.4f" % [c["ball"], got[2], want[1]])
		if not veq(got[3], want[2]):
			_fail("точка взгляда для мяча %s: %s, ожидалось %s" % [c["ball"], got[3], want[2]])

	# ---------- 2. Ввод игрока в направление НЕ входит (:912) ----------
	var ball2 = B.new()
	ball2.ResetSituation(Vector3(4.0, 0.0, 0.0))
	var a1: Array = A.DescribeBallControlMovement(ball2, Vector3.ZERO, Vector3(0, -1, 0), Vector3(0, 1, 0), SPRINT)
	var a2: Array = A.DescribeBallControlMovement(ball2, Vector3.ZERO, Vector3(0, -1, 0), Vector3(-1, 0, 0), SPRINT)
	if not veq(a1[1], a2[1]) or not feq(a1[2], a2[2]):
		_fail("ввод игрока повлиял на магнит: %s/%.3f против %s/%.3f" % [a1[1], a1[2], a2[1], a2[2]])
	if not veq(a1[1], Vector3(1, 0, 0)):
		_fail("магнит смотрит не на мяч: %s" % a1[1])

	# ---------- 3. Желаемая скорость только ограничивает сверху (:931) ----------
	# мяч в 3 м → toBallVelocity = 7.8; желаемая 3.5 НИЖЕ — берётся 7.8 (клампится снизу)
	var ball3 = B.new()
	ball3.ResetSituation(Vector3(3.0, 0.0, 0.0))
	var slow: Array = A.DescribeBallControlMovement(ball3, Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 0, 0), DRIBBLE)
	var want_slow: Array = expected(Vector3(3.0, 0.0, 0.0), Vector3.ZERO, Vector3(1, 0, 0), DRIBBLE)
	if not feq(slow[2], want_slow[1]):
		_fail("кламп скорости снизу: %.4f, ожидалось %.4f" % [slow[2], want_slow[1]])
	if slow[2] < 7.0:
		_fail("при мяче в 3 м скорость обязана быть ~7.8, а не %.2f" % slow[2])

	# ---------- 4. Мяч вплотную: направление смешивается с направлением тела (:915) ----------
	var ball4 = B.new()
	ball4.ResetSituation(Vector3(0.25, 0.0, 0.0))
	var near: Array = A.DescribeBallControlMovement(ball4, Vector3.ZERO, Vector3(0, -1, 0), Vector3(1, 0, 0), SPRINT)
	var want_near: Array = expected(Vector3(0.25, 0.0, 0.0), Vector3.ZERO, Vector3(0, -1, 0), SPRINT)
	if not veq(near[1], want_near[0]):
		_fail("ближняя зона: %s, ожидалось %s" % [near[1], want_near[0]])
	# смешивание обязано быть НЕ чистым «на мяч» и не чистым «по телу»
	if veq(near[1], Vector3(1, 0, 0)) or veq(near[1], Vector3(0, -1, 0)):
		_fail("ближняя зона не смешивает направления: %s" % near[1])

	# ---------- 5. BlendAutoMovement при autoBias = 1 (playercontroller.cpp:590-601) ----------
	var auto_dir := Vector3(1, 0, 0)
	var auto_look := Vector3(0, -1, 0)
	var blend: Array = A.DescribeBlendAutoMovement(auto_dir, 6.0, auto_look,
		Vector3(0, 1, 0), 8.0, 1.0, Vector3(2, 3, 0), Vector3(0, 1, 0))
	# [направление, скорость, точка взгляда]
	if not veq(blend[0], auto_dir):
		_fail("bias=1: направление %s, ожидалось авто %s" % [blend[0], auto_dir])
	if not feq(blend[1], 6.0):
		_fail("bias=1: скорость %.3f, ожидалось 6.0" % blend[1])
	if not veq(blend[2], Vector3(2, 3, 0) + auto_look * 10.0):
		_fail("bias=1: точка взгляда %s" % blend[2])

	# при bias = 0 команда человека проходит как есть
	var manual: Array = A.DescribeBlendAutoMovement(auto_dir, 6.0, auto_look,
		Vector3(0, 1, 0), 5.0, 0.0, Vector3.ZERO, Vector3(0, 1, 0))
	if not veq(manual[0], Vector3(0, 1, 0)) or not feq(manual[1], 5.0):
		_fail("bias=0: %s / %.3f, ожидалась ручная команда" % [manual[0], manual[1]])

	# ---------- 6. Ниже порога дриблинга направление берётся из взгляда (:597) ----------
	var slowblend: Array = A.DescribeBlendAutoMovement(auto_dir, 1.0, auto_look,
		Vector3(0, 1, 0), 1.0, 1.0, Vector3.ZERO, Vector3(0, 1, 0))
	if not veq(slowblend[0], auto_look):
		_fail("скорость ниже IdleDribbleSwitch: направление %s, ожидался взгляд %s"
				% [slowblend[0], auto_look])

	_done()


func _done() -> void:
	print("CHECK PASS" if _fails == 0 else "CHECK FAIL: %d расхождений" % _fails)
	quit(1 if _fails > 0 else 0)

extends SceneTree
# Тикет 05 фазы 7: математика трёх веток сетки ворот (ball.cpp:331-408) в Gpf.Ball за флагом
# NettingEnabled. Матч-вход — флаг «мяч в воротах» (match->IsBallInGoal(), ball.cpp:335) —
# здесь ПОДСТАВЛЯЕТСЯ РУКАМИ (Ball.BallIsInGoal): его источник CheckForGoal живёт в
# лаб-оркестраторе и трассой накроется только в гол-сценарии фазы 8. Паттерн —
# check_gpf_offsets: математика закрепляется тестом до того, как её накроет трасса.
#
# Приём — как в check_gpf_ball: тест перевычисляет один шаг интеграции (10 мс) по формулам
# C++ и сверяет с GetMovement() после Process(). Все позиции — z > 0.135 (мимо отскока,
# трения и вращения) и вдали от штанг/перекладины, вращение identity (магнус = 0), поэтому
# живые секции шага — только гравитация (:175), drag (:180-183) и сетка (:331-408).

func vec_eq(a: Vector3, b: Vector3, eps := 2.0e-3) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

# гравитация + drag — общая для всех кейсов часть шага до сетки
func grav_drag(mom: Vector3) -> Vector3:
	mom.z += -9.81 * 0.01
	var velo := mom.length()
	var dragged := velo - 0.015 * velo * velo * 0.01
	if velo > 0.0001:
		mom = mom.normalized() * dragged
	return mom

# ослабление у штанг (:358-359, :400-401): bias — от МОМЕНТА, не от позиции (квирк оригинала)
func adapted_power_fac(mom_x: float) -> float:
	var bias: float = clampf((absf(mom_x) - 55.0) * 2.0, 0.0, 1.0)
	return 1.8 + (1.0 - bias) * 3.0

func make_ball(B, pos: Vector3, mom: Vector3, in_goal: bool):
	var ball = B.new()
	ball.NettingEnabled = true
	ball.BallIsInGoal = in_goal
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(pos)
	ball.SetMomentum(mom)
	return ball

func _initialize() -> void:
	var ok := true
	var B = load("res://src/gpf/Ball.cs")
	if B == null:
		print("CHECK FAIL: Ball.cs не найден — сначала dotnet build")
		quit(1)
		return

	# netAbsorbInv после pow(0.95, timeStep*100) при timeStep 0.01 == 0.95 (:229, :236);
	# множитель power*fac*(100*timeStep) == power*fac (:361, :380, :403)

	# ---------- 1. Боковая сетка (:347-364): мяч в воротах у боковины ----------
	var ball = make_ball(B, Vector3(56.5, 3.9, 1.0), Vector3(0, 5, 0), true)
	ball.Process()
	var mom := grav_drag(Vector3(0, 5, 0))
	var net_dist: float = clampf(absf(absf(3.9) - 3.7), 0.0, 1.0)
	var power := pow(net_dist, 2.6) * -1.0 * 1.0  # -signSide(y=3.9) * inGoal(:354-355)
	mom.y = mom.y * 0.95 + power * adapted_power_fac(mom.x) * 1.0  # mom.x=0 → fac 4.8
	if not vec_eq(ball.GetMovement(), mom):
		print("CHECK FAIL: боковая сетка: ", ball.GetMovement(), " != ", mom); ok = false
	if not ball.BallTouchesNet():
		print("CHECK FAIL: боковая сетка не выставила флаг касания"); ok = false

	# ---------- 2. Ослабление у штанг: большой |momentum.x| гасит добавку (:357-359) ----------
	ball = make_ball(B, Vector3(56.5, 3.9, 1.0), Vector3(60, 5, 0), true)
	ball.Process()
	mom = grav_drag(Vector3(60, 5, 0))
	# после drag mom.x ≈ 59.4 > 55.5 → bias 1 → fac 1.8 (у штанги сетка «прибита»)
	mom.y = mom.y * 0.95 + power * adapted_power_fac(mom.x) * 1.0
	if not vec_eq(ball.GetMovement(), mom):
		print("CHECK FAIL: ослабление у штанг: ", ball.GetMovement(), " != ", mom); ok = false

	# ---------- 3. Задняя сетка (:367-383): powerFac БЕЗ ослабления ----------
	ball = make_ball(B, Vector3(58.5, 0, 1.0), Vector3(5, 0, 0), true)
	ball.Process()
	mom = grav_drag(Vector3(5, 0, 0))
	net_dist = clampf(absf(absf(58.5) - (55.0 + 2.55)), 0.0, 1.0)  # 0.95
	power = pow(net_dist, 2.6) * -1.0 * 1.0  # -signSide(x=58.5) * inGoal (:378-379)
	mom.x = mom.x * 0.95 + power * 1.8 * 1.0  # :380 — чистый powerFac
	if not vec_eq(ball.GetMovement(), mom):
		print("CHECK FAIL: задняя сетка: ", ball.GetMovement(), " != ", mom); ok = false
	if not ball.BallTouchesNet():
		print("CHECK FAIL: задняя сетка не выставила флаг касания"); ok = false

	# ---------- 4. Верхняя сетка (:386-406): с ослаблением у перекладины ----------
	ball = make_ball(B, Vector3(56.5, 0, 2.7), Vector3(0, 0, 3), true)
	ball.Process()
	mom = grav_drag(Vector3(0, 0, 3))
	net_dist = clampf(absf(absf(2.7) - 2.5), 0.0, 1.0)  # 0.2
	power = pow(net_dist, 2.6) * -1.0  # -inGoal (:397) — без signSide
	mom.z = mom.z * 0.95 + power * adapted_power_fac(mom.x) * 1.0  # mom.x=0 → fac 4.8
	if not vec_eq(ball.GetMovement(), mom):
		print("CHECK FAIL: верхняя сетка: ", ball.GetMovement(), " != ", mom); ok = false
	if not ball.BallTouchesNet():
		print("CHECK FAIL: верхняя сетка не выставила флаг касания"); ok = false

	# ---------- 5. Мяч в воротах, но НЕ у сетки: ни одна ветка не трогает момент ----------
	ball = make_ball(B, Vector3(56.5, 0, 1.0), Vector3(0, 1, 0), true)
	ball.Process()
	mom = grav_drag(Vector3(0, 1, 0))
	if not vec_eq(ball.GetMovement(), mom):
		print("CHECK FAIL: мяч в центре ворот задел сетку: ", ball.GetMovement()); ok = false
	if ball.BallTouchesNet():
		print("CHECK FAIL: флаг касания без касания"); ok = false

	# ---------- 6. Мяч в поле (не behindBackline): флаг «в воротах» сам по себе ничего не даёт ----------
	ball = make_ball(B, Vector3(54.0, 3.9, 1.0), Vector3(0, 5, 0), true)
	ball.Process()
	mom = grav_drag(Vector3(0, 5, 0))
	if not vec_eq(ball.GetMovement(), mom):
		print("CHECK FAIL: сетка сработала в поле: ", ball.GetMovement()); ok = false

	# ---------- 7. Снаружи мяч проходит СКВОЗЬ сетку (bug-for-bug, :369-373, :388-392) ----------
	# BallIsInGoal=false: живые ветки требуют флага, «внешние» закомментированы в оригинале.
	# Мяч из-за ворот пролетает заднюю сетку и створ и оказывается в поле.
	ball = make_ball(B, Vector3(58.2, 0, 1.0), Vector3(-8, 0, 0), false)
	var control = B.new()  # контроль: NettingEnabled=false — поведение до тикета
	control.ResetSituation(Vector3.ZERO)
	control.SetPosition(Vector3(58.2, 0, 1.0))
	control.SetMomentum(Vector3(-8, 0, 0))
	var passed := false
	for i in range(150):
		ball.Process()
		control.Process()
		if ball.Predict(0) != control.Predict(0):
			print("CHECK FAIL: сетка снаружи тронула мяч на тике ", i, ": ",
				ball.Predict(0), " != ", control.Predict(0)); ok = false
			break
		if ball.BallTouchesNet():
			print("CHECK FAIL: флаг касания у мяча снаружи на тике ", i); ok = false
			break
		if ball.Predict(0).x < 54.0:
			passed = true
			break
	if not passed and ok:
		print("CHECK FAIL: мяч снаружи не прошёл сквозь сетку: ", ball.Predict(0)); ok = false

	# ---------- 8. NettingEnabled=false (дефолт) — сетки нет даже с флагом «в воротах» ----------
	ball = B.new()
	ball.BallIsInGoal = true
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(56.5, 3.9, 1.0))
	ball.SetMomentum(Vector3(0, 5, 0))
	ball.Process()
	mom = grav_drag(Vector3(0, 5, 0))
	if not vec_eq(ball.GetMovement(), mom):
		print("CHECK FAIL: выключенная сетка изменила момент: ", ball.GetMovement()); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

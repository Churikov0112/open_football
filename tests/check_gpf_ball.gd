extends SceneTree
# Фаза 4, задача 2: Gpf.Ball == Ball::CalculatePrediction (ball.cpp:137-537).
# Ключевой приём: тест сам перевычисляет ОДИН шаг интеграции (10 мс) по формулам C++
# (порядок: гравитация → drag → отскок → трение → [штанги] → вращение → магнус → интеграция)
# и сверяет с Predict(10). Это пиннит порядок применения констант целиком.
#
# ПОПРАВКИ к брифу (прав C++, не бриф):
# 1. Кейс 3: кадр контакта — сам Predict(t_ms): кэш (:524) пишет nextPos ДО клампа
#    отскока следующей итерации, так что «подземная» точка — это t_ms, а соседи ±10мс
#    легитимно выше 0.115 (до контакта до ~0.17 при v~6 м/с, после отскока ~0.147).
#    Проверяем минимум z по окну {t_ms-10, t_ms, t_ms+10}.
# 2. Порог отскока в перевычислении — float32: GDScript-литерал 0.11 — это double
#    (0.110000000000000000555…), а компонент Vector3 — float32 (0.109999999403…).
#    Сравнение `pos.z < 0.11` на мяче, стоящем РОВНО на земле, в GDScript даёт true
#    (float32 промоутится до double и оказывается меньше литерала), а в C++/C#
#    float-против-float даёт false — отскока нет. Порог берём float32-округлённым.
# 3. Кейс 6: штанги проверяются ТОЛЬКО на первом шаге предсказания (firstTime,
#    ball.cpp:240) — одиночный Predict-прогон из (54.0, 3.7) пролетает сквозь штангу,
#    и это поведение оригинала (механика работает через пересчёт в Process() каждый
#    тик). Кейс разбит: 6a — мяч стартует уже в зоне контакта, отражение :291
#    перевычисляется точно; 6b — подлёт через Process(), мяч не проникает за штангу
#    и отлетает назад.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

# один шаг интеграции C++ для мяча БЕЗ вращения (rotation identity) вне штанг:
# возвращает [новый momentum, новая позиция]
func step_no_rotation(pos: Vector3, mom: Vector3) -> Array:
	var dt := 0.01
	# 0.11 в float32 — как хранит его C++/C# (см. поправку 2 в шапке)
	var radius_f: float = Vector3(0.11, 0, 0).x
	# гравитация (ball.cpp:175)
	mom.z += -9.81 * dt
	# сопротивление воздуха (:180-183)
	var velo := mom.length()
	var dragged := velo - 0.015 * velo * velo * dt
	if velo > 0.0001:
		mom = mom.normalized() * dragged
	# влияние травы (:186-191)
	var ball_bottom := pos.z - 0.11
	var grass_bias: float = clampf(1.0 - (ball_bottom / 0.025), 0.0, 1.0)
	grass_bias = pow(grass_bias, 0.7)
	# отскок (:197-205); порог — float32, как в C++ (сравнение float < float)
	var friction_factor := 0.0
	if pos.z < radius_f:
		if mom.z < 0.0:
			friction_factor = clampf((-mom.z - 0.5) / 12.0, 0.0, 1.0)
			mom.z = -mom.z * 0.62
			mom.z = maxf(mom.z - 0.06, 0.0)
		pos.z = 0.11
	# трение газона (:210-227)
	if pos.z < 0.11 + 0.025:
		var adapted_friction := 0.04 * grass_bias
		var xy := Vector3(mom.x, mom.y, 0)
		var v := xy.length()
		var new_velo := v - adapted_friction * v * v * dt
		new_velo = clampf(new_velo - 1.6 * grass_bias * dt, 0.0, 100000.0)
		if v > 0.0001:
			xy = xy.normalized() * new_velo
		mom.x = xy.x
		mom.y = xy.y
	# вращение (:413-481): при identity-вращении ballRotationMomentum = 0,
	# rotBias = 0.01*grass_bias (+0.5*friction_factor), кламп [0,1]
	if pos.z < 0.11 + 0.025:
		var rot_bias: float = 0.01 * grass_bias
		if friction_factor > 0.0:
			rot_bias += 0.5 * friction_factor
		rot_bias = clampf(rot_bias, 0.0, 1.0)
		mom.x = mom.x * (1.0 - rot_bias)
		mom.y = mom.y * (1.0 - rot_bias)
	# магнус при identity-вращении = 0 (:486-501)
	# интеграция (:506)
	pos += mom * dt
	return [mom, pos]

func _initialize() -> void:
	var ok := true
	var B = load("res://src/gpf/Ball.cs")
	if B == null:
		print("CHECK FAIL: Ball.cs не найден — сначала dotnet build")
		quit(1)
		return

	# ---------- 1. ResetSituation: все предсказания в точке покоя ----------
	var ball = B.new()
	ball.ResetSituation(Vector3(0, 0, 0))
	if not vec_eq(ball.Predict(0), Vector3(0, 0, 0.11)):
		print("CHECK FAIL: ResetSituation Predict(0) = ", ball.Predict(0)); ok = false
	if not vec_eq(ball.Predict(2990), Vector3(0, 0, 0.11)):
		print("CHECK FAIL: ResetSituation Predict(2990)"); ok = false

	# ---------- 2. Один шаг качения == перевычисление формул C++ ----------
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(0, 0, 0.11))
	ball.SetMomentum(Vector3(5, 0, 0))
	var expected: Array = step_no_rotation(Vector3(0, 0, 0.11), Vector3(5, 0, 0))
	var exp_pos: Vector3 = expected[1]
	if not vec_eq(ball.Predict(10), exp_pos, 1.0e-3):
		print("CHECK FAIL: качение, шаг 1: ", ball.Predict(10), " != ", exp_pos); ok = false

	# ---------- 3. Свободное падение: время до земли и отскок ----------
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(0, 0, 2.0))
	ball.SetMomentum(Vector3(0, 0, 0))
	# перевычисляем падение по шагам до первого контакта
	var sim_pos := Vector3(0, 0, 2.0)
	var sim_mom := Vector3.ZERO
	var steps := 0
	while sim_pos.z > 0.11 and steps < 300:
		var r: Array = step_no_rotation(sim_pos, sim_mom)
		sim_mom = r[0]
		sim_pos = r[1]
		steps += 1
	var t_ms := steps * 10
	# в окне контакта предсказание тоже должно коснуться земли (±1 кадр на накопление float);
	# сам кадр t_ms — «подземный» (кэш пишет до клампа следующего шага), соседи выше
	var land_min: float = minf(ball.Predict(t_ms - 10).z,
		minf(ball.Predict(t_ms).z, ball.Predict(t_ms + 10).z))
	if not (land_min <= 0.115):
		print("CHECK FAIL: падение — контакт не в окне ", t_ms, "±10 мс: min z = ",
			land_min); ok = false
	# после контакта мяч поднимается (отскок 0.62 жив)
	var bounced := false
	for i in range(t_ms + 10, t_ms + 400, 10):
		if ball.Predict(i).z > 0.2:
			bounced = true
			break
	if not bounced:
		print("CHECK FAIL: отскока нет"); ok = false
	# и затухает: второй пик ниже первого источника
	var peak := 0.0
	for i in range(t_ms, 3000, 10):
		peak = maxf(peak, ball.Predict(i).z)
	if peak > 1.6:
		print("CHECK FAIL: отскок не затух: пик ", peak); ok = false

	# ---------- 4. Первый шаг == новое состояние (:527-531) ----------
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(0, 0, 0.11))
	ball.SetMomentum(Vector3(5, 0, 0))
	var pred10: Vector3 = ball.Predict(10)
	ball.Process()
	if not vec_eq(ball.GetPositionBuffer(), pred10, 1.0e-4):
		print("CHECK FAIL: Process не взял Predict(10): ",
			ball.GetPositionBuffer(), " != ", pred10); ok = false
	var exp_mom: Vector3 = expected[0]
	if not vec_eq(ball.GetMovement(), exp_mom, 1.0e-3):
		print("CHECK FAIL: momentum после Process: ", ball.GetMovement(), " != ", exp_mom); ok = false

	# ---------- 5. Магнус: сильное вращение уводит мяч вбок ----------
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(0, 0, 1.0))
	ball.SetMomentum(Vector3(0, -20, 0))
	var straight: Vector3 = ball.Predict(800)
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(0, 0, 1.0))
	ball.SetRotationVec(Vector3(0, 0, 12.0), 1.0)  # z-спин
	ball.SetMomentum(Vector3(0, -20, 0))
	var curved: Vector3 = ball.Predict(800)
	if absf(curved.x - straight.x) < 0.05:
		print("CHECK FAIL: магнус не увёл мяч: dx = ", absf(curved.x - straight.x)); ok = false

	# ---------- 6a. Штанга: точное перевычисление отражения (:247-292) ----------
	# мяч УЖЕ в зоне контакта штанги (PitchHalfW=55, GoalHalfWidth=3.7): на первом же
	# шаге предсказания (firstTime) оригинал выталкивает его из капсулы и отражает momentum
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(54.85, 3.7, 1.0))
	ball.SetMomentum(Vector3(10, 0, 0))
	# перевычисление первого шага по C++: гравитация (:175) → drag (:180-183) →
	# [z=1.0: отскок/трение мимо] → штанга (:247-291) → [вращение/магнус: identity, мимо]
	# → интеграция (:506)
	var wmom := Vector3(10, 0, 0)
	wmom.z += -9.81 * 0.01
	var wvelo := wmom.length()
	wmom = wmom.normalized() * (wvelo - 0.015 * wvelo * wvelo * 0.01)
	# штанга: правая/«верхняя» ветка (:281-286), normal = normalize(2D - (55, 3.7))
	var wnormal := (Vector3(54.85, 3.7, 0) - Vector3(55.0, 3.7, 0)).normalized()  # (-1,0,0)
	var wpos := Vector3(55.0, 3.7, 0) + wnormal * (0.07 + 0.11)
	wpos.z = 1.0
	# отражение (:291): (norm(mom2D) + normal*1.1).normalized() * |mom2D| * 0.8 + (0,0,vz)
	var wmom2d := Vector3(wmom.x, wmom.y, 0)
	wmom = (wmom2d.normalized() + wnormal * 1.1).normalized() * wmom2d.length() * 0.8 \
		+ Vector3(0, 0, 1) * wmom.z
	wpos += wmom * 0.01
	if not vec_eq(ball.Predict(10), wpos, 1.0e-3):
		print("CHECK FAIL: отражение от штанги: ", ball.Predict(10), " != ", wpos); ok = false
	# и дальше в предсказании мяч летит назад
	if not (ball.Predict(500).x < 54.0):
		print("CHECK FAIL: после штанги мяч не летит назад: ", ball.Predict(500)); ok = false

	# ---------- 6b. Штанга через Process(): подлёт, без пролёта насквозь ----------
	# штанги проверяются только на firstTime (:240) — в игре это работает, потому что
	# Process() пересчитывает предсказание каждые 10 мс; допустимо проникновение до
	# одного тика пути (~0.1 м) до выталкивания, но за плоскость штанги (x=55) мяч
	# зайти не может
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(54.0, 3.7, 1.0))
	ball.SetMomentum(Vector3(10, 0, 0))
	var deflected := false
	for i in range(200):
		ball.Process()
		var p: Vector3 = ball.GetPositionBuffer()
		if p.x > 55.0:
			print("CHECK FAIL: мяч прошёл сквозь штангу: ", p, " на тике ", i); ok = false
			break
		if p.x < 53.5:
			deflected = true  # отлетел назад
			break
	if not deflected:
		print("CHECK FAIL: штанга не отразила (мяч не вернулся)"); ok = false

	# ---------- 7. Детерминизм ----------
	var b1 = B.new(); var b2 = B.new()
	for b in [b1, b2]:
		b.ResetSituation(Vector3.ZERO)
		b.SetPosition(Vector3(1, 2, 0.5))
		b.SetRotationVec(Vector3(3, -2, 5), 1.0)
		b.SetMomentum(Vector3(-7, 4, 6))
	for i in range(0, 3000, 10):
		if b1.Predict(i) != b2.Predict(i):
			print("CHECK FAIL: недетерминизм в ", i, " мс"); ok = false
			break

	# ---------- 8. Отрицательный Predict — bug-for-bug последняя точка (ball.hpp:52-55) ----------
	if ball.Predict(-5) != ball.Predict(2990):
		print("CHECK FAIL: Predict(<0) должен дать последнюю точку (unsigned-каст оригинала)"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

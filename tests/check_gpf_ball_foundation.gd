extends SceneTree
# Фаза 4, задача 1: кватернионные примитивы (quaternion.cpp), Line (line.cpp:60-71),
# GpfRng, константы поля (gamedefines.hpp). Ожидания — математические тождества и формулы C++,
# перевычисленные здесь; НЕ литералы из плана.

func feq(a: float, b: float, eps := 1.0e-5) -> bool:
	return absf(a - b) < eps

func _initialize() -> void:
	var ok := true
	var Q = load("res://src/gpf/QuatUtil.cs")
	var BM = load("res://src/gpf/BluntMath.cs")
	var RNG = load("res://src/gpf/GpfRng.cs")
	var P = load("res://src/gpf/GpfPitch.cs")
	if Q == null or BM == null or RNG == null or P == null:
		print("CHECK FAIL: C#-скрипты не найдены — сначала dotnet build")
		quit(1)
		return

	# --- SetAngles (quaternion.cpp:228-245) ---
	# ПОПРАВКА к брифу. Бриф утверждал, что SetAngles — обратная к GetAngles фазы 2
	# (`SetAngles(GetAngles(q)) == q`). В оригинале это НЕ так, и мы портируем bug-for-bug:
	#   * GetAngles (:197-226) читает компоненты с перестановкой x=el[0], y=el[2], z=el[1]
	#     и возвращает (X,Y,Z) = (bank, attitude, heading) конвенции euclideanspace;
	#   * SetAngles (:228-245) подставляет в прямую формулу euclideanspace heading:=Y,
	#     attitude:=Z, bank:=X и пишет результат БЕЗ перестановки (el[1]=y, el[2]=z).
	# Обе перестановки не гасят друг друга: круговой проход точен, только если вращение
	# вокруг одной оси, а на смешанном расходится (перекрёстные члены с sin(bank/2)).
	# Поэтому проверяем то, чем SetAngles является на самом деле.

	# (а) независимая характеризация: SetAngles(X,Y,Z) == Ry(Y) * Rz(Z) * Rx(X)
	#     (сверено численно с формулой C++; Godot-умножение кватернионов совпадает с
	#     Quaternion::operator* оригинала, quaternion.cpp:133-142 — обычный Гамильтон).
	var sx := 0.3
	var sy := -0.7
	var sz := 1.1
	var built: Quaternion = Q.SetAngles(sx, sy, sz)
	var composed: Quaternion = (Q.AngleAxis(sy, Vector3(0, 1, 0)) \
		* Q.AngleAxis(sz, Vector3(0, 0, 1))) * Q.AngleAxis(sx, Vector3(1, 0, 0))
	if not built.is_equal_approx(composed):
		print("CHECK FAIL: SetAngles != Ry(Y)*Rz(Z)*Rx(X): ", built, " vs ", composed); ok = false

	# (б) на одноосных вращениях круговой проход GetAngles→SetAngles всё же точен
	for axis in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
		var single: Quaternion = Q.AngleAxis(0.37, axis)
		var sang: Vector3 = Q.GetAnglesVec(single)
		var sback: Quaternion = Q.SetAngles(sang.x, sang.y, sang.z)
		if not (sback.is_equal_approx(single) or sback.is_equal_approx(-single)):
			print("CHECK FAIL: круговой проход по оси ", axis, ": ", sback, " vs ", single); ok = false

	# (в) пин расхождения на СМЕШАННОМ вращении — фиксируем поведение оригинала, чтобы
	#     никто не «починил» SetAngles до настоящей обратной к GetAngles.
	var src: Quaternion = Q.AngleAxis(0.37, Vector3(0.2, -0.5, 0.84).normalized())
	var ang: Vector3 = Q.GetAnglesVec(src)
	var back: Quaternion = Q.SetAngles(ang.x, ang.y, ang.z)
	if back.is_equal_approx(src) or back.is_equal_approx(-src):
		print("CHECK FAIL: SetAngles стал обратной к GetAngles — расхождение с C++"); ok = false
	if not feq(back.w, src.w, 1.0e-5) or not feq(back.x, src.x, 1.0e-5):
		print("CHECK FAIL: w/x должны совпадать даже на смешанном (симметричны по h<->a)"); ok = false

	# --- GetRotationTo (quaternion.cpp:403-406): q1.GetRotationTo(q2) * q1 == q2 ---
	var q1: Quaternion = Q.AngleAxis(0.3, Vector3(0, 0, 1))
	var q2: Quaternion = Q.AngleAxis(-0.5, Vector3(0, 1, 0)) * q1
	var rot_to: Quaternion = Q.GetRotationTo(q1, q2)
	var applied: Quaternion = rot_to * q1
	if not (applied.is_equal_approx(q2) or applied.is_equal_approx(-q2)):
		print("CHECK FAIL: GetRotationTo не доводит q1 до q2"); ok = false

	# --- GetRotationAngle (quaternion.hpp:75-77): 2*acos(clamp(dot,-1,1)) ---
	var q3: Quaternion = Q.AngleAxis(0.42, Vector3(1, 0, 0))
	var got_angle: float = Q.GetRotationAngle(q3, Quaternion.IDENTITY)
	if not feq(absf(got_angle), 0.42, 1.0e-4):
		print("CHECK FAIL: GetRotationAngle = ", got_angle); ok = false

	# --- GetRotationMultipliedBy (quaternion.cpp:408-424): удвоенный угол вокруг той же оси ---
	var half: Quaternion = Q.AngleAxis(0.2, Vector3(0, 0, 1))
	var doubled: Quaternion = Q.GetRotationMultipliedBy(half, 2.0)
	var expected_d: Quaternion = Q.AngleAxis(0.4, Vector3(0, 0, 1))
	if not (doubled.is_equal_approx(expected_d) or doubled.is_equal_approx(-expected_d)):
		print("CHECK FAIL: GetRotationMultipliedBy x2"); ok = false

	# --- LineClosestToPoint (line.cpp:60-71): 2D-проекция, u без клампа ---
	# точка над серединой отрезка (0,0)-(2,0) → u = 0.5; за концом → u > 1 (кламп у ВЫЗЫВАЮЩЕГО)
	var u: float = BM.LineClosestToPoint(Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(1, 5, 0))
	if not feq(u, 0.5):
		print("CHECK FAIL: LineClosestToPoint середина: ", u); ok = false
	u = BM.LineClosestToPoint(Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0))
	if not feq(u, 1.5):
		print("CHECK FAIL: LineClosestToPoint за концом (без клампа): ", u); ok = false
	# вырожденный отрезок → 0 (line.cpp:61-63)
	u = BM.LineClosestToPoint(Vector3(1, 1, 0), Vector3(1, 1, 0), Vector3(5, 5, 0))
	if not feq(u, 0.0):
		print("CHECK FAIL: LineClosestToPoint вырожденный: ", u); ok = false
	# Z игнорируется — проекция строго 2D (только coords[0]/[1])
	u = BM.LineClosestToPoint(Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(1, 0, 99))
	if not feq(u, 0.5):
		print("CHECK FAIL: LineClosestToPoint должен игнорировать Z: ", u); ok = false

	# --- GpfRng: детерминизм по сиду, диапазон, чувствительность к сиду ---
	var r1 = RNG.new(); r1.Reseed(42)
	var r2 = RNG.new(); r2.Reseed(42)
	var all_in_range := true
	var same := true
	var prev_vals: Array = []
	for i in 100:
		var a: float = r1.Uniform(-1.0, 1.0)
		var b: float = r2.Uniform(-1.0, 1.0)
		if a != b: same = false
		if a < -1.0 or a > 1.0: all_in_range = false
		prev_vals.append(a)
	if not same: print("CHECK FAIL: GpfRng не детерминирован по сиду"); ok = false
	if not all_in_range: print("CHECK FAIL: GpfRng вышел из [min,max]"); ok = false
	var r3 = RNG.new(); r3.Reseed(43)
	var diff_count := 0
	for i in 100:
		if r3.Uniform(-1.0, 1.0) != prev_vals[i]: diff_count += 1
	if diff_count < 90:
		print("CHECK FAIL: GpfRng слабо зависит от сида: ", diff_count); ok = false

	# --- GpfPitch: сверка с gamedefines.hpp (эти числа — данные оригинала, не тюнинг) ---
	# Читаем через мост-обёртки: через CSharpScript доступны только статические МЕТОДЫ,
	# const-поля не видны (тот же урок, что с Velo.GetAnimSprint() в фазе 3).
	if not feq(P.GetPitchHalfW(), 55.0) or not feq(P.GetPitchHalfH(), 36.0) \
			or not feq(P.GetLineHalfW(), 0.06):
		print("CHECK FAIL: размеры поля"); ok = false
	if not feq(P.GetGoalDepth(), 2.55) or not feq(P.GetGoalHeight(), 2.5) \
			or not feq(P.GetGoalHalfWidth(), 3.7):
		print("CHECK FAIL: размеры ворот"); ok = false
	if not feq(P.GetDefaultPlayerHeight(), 1.92) or P.GetDefaultTouchOffsetMs() != 80:
		print("CHECK FAIL: рост/тач-офсет"); ok = false
	if P.GetBallPredictionSizeMs() != 3000 or P.GetBallHistorySizeMs() != 4000:
		print("CHECK FAIL: размеры предсказания/истории"); ok = false
	if not feq(P.GetBallDistanceOptimizeThreshold(), 10.0):
		print("CHECK FAIL: ballDistanceOptimizeThreshold"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

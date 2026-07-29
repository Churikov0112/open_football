extends SceneTree
# Математический фундамент порта: Blunted-математика, скорости, эйлеры.

func feq(a: float, b: float, eps := 1.0e-5) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-5) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var BM = load("res://src/gpf/BluntMath.cs")
	var V = load("res://src/gpf/Velo.cs")
	if BM == null or V == null:
		print("CHECK FAIL: BluntMath.cs/Velo.cs не найдены — сначала dotnet build")
		quit(1)
		return

	# ModulateIntoRange (bluntmath.cpp:94-100)
	if not feq(BM.ModulateIntoRange(-PI, PI, 5.5509), 5.5509 - TAU):
		print("CHECK FAIL: ModulateIntoRange 5.5509 → ", BM.ModulateIntoRange(-PI, PI, 5.5509)); ok = false
	if not feq(BM.ModulateIntoRange(-PI, PI, -4.0), -4.0 + TAU):
		print("CHECK FAIL: ModulateIntoRange -4"); ok = false

	# Curve (bluntmath.hpp:46-49): sin((x-0.5)*pi)*0.5+0.5 при bias=1
	if not feq(BM.Curve(0.5, 1.0), 0.5):
		print("CHECK FAIL: Curve(0.5,1)"); ok = false
	if not feq(BM.Curve(0.25, 1.0), sin(-0.25 * PI) * 0.5 + 0.5):
		print("CHECK FAIL: Curve(0.25,1)"); ok = false
	if not feq(BM.Curve(0.25, 0.0), 0.25):
		print("CHECK FAIL: Curve(0.25,0) — bias 0 == линейно"); ok = false

	# NormalizedClamp (bluntmath.cpp:34-39)
	if not feq(BM.NormalizedClamp(5.0, 0.0, 20.0), 0.25):
		print("CHECK FAIL: NormalizedClamp"); ok = false
	if not feq(BM.NormalizedClamp(-3.0, 0.0, 6.0), 0.0):
		print("CHECK FAIL: NormalizedClamp кламп снизу"); ok = false

	# SignSide (bluntmath.cpp:61-63): n >= 0 → 1
	if BM.SignSide(0.0) != 1 or BM.SignSide(-0.001) != -1:
		print("CHECK FAIL: SignSide"); ok = false

	# FixAngle (animcollection.hpp:50-55)
	if not feq(BM.FixAngle(0.0), 0.5 * PI):
		print("CHECK FAIL: FixAngle(0)"); ok = false
	# Исправлено при TDD: bluntmath.cpp:94-100 + animcollection.hpp:50-55 дают для 1.5π ровно 0
	# (1.5π + 0.5π = 2π = один полный шаг модуляции), не -π/4 — проверено против оригинала C++.
	if not feq(BM.FixAngle(0.75 * TAU), 0.0, 1.0e-4):
		print("CHECK FAIL: FixAngle(1.5pi) → ", BM.FixAngle(0.75 * TAU)); ok = false

	# AtoF/AtoI — семантика atof/atoi: "" и мусор → 0 (не исключение)
	if not feq(BM.AtoF(""), 0.0) or not feq(BM.AtoF("0.5"), 0.5) or BM.AtoI("") != 0 or BM.AtoI("19") != 19:
		print("CHECK FAIL: AtoF/AtoI"); ok = false

	# GetVectorFromString (base/utils.cpp:222-237)
	if not vec_eq(BM.GetVectorFromString("0.5, -1, 0"), Vector3(0.5, -1, 0)):
		print("CHECK FAIL: GetVectorFromString"); ok = false
	if not vec_eq(BM.GetVectorFromString(""), Vector3.ZERO):
		print("CHECK FAIL: GetVectorFromString('')"); ok = false

	# GetRotated2D (vector3.hpp:325-333): (0,-1,0) на -45° → (sin,-cos)
	var r: Vector3 = BM.GetRotated2D(Vector3(0, -1, 0), -0.25 * PI)
	if not vec_eq(r, Vector3(-sin(0.25 * PI), -cos(0.25 * PI), 0.0)):
		print("CHECK FAIL: GetRotated2D → ", r); ok = false

	# GetAngle2D() безаргументный: [0, 2pi) (vector3.hpp:276-280)
	if not feq(BM.GetAngle2D(Vector3(-0.34, -0.378261, 0.0)), atan2(-0.378261, -0.34) + TAU, 1.0e-4):
		print("CHECK FAIL: GetAngle2D() one-arg"); ok = false
	# GetAngle2D(test): [-pi, pi], знак как в оригинале (vector3.hpp:283-289)
	# Исправлено при TDD: -atan2(0*0-(-1)*(-1), 0*(-1)+(-1)*0) = -atan2(-1,0) = +pi/2, не -pi/2 —
	# проверено построчно против оригинала C++.
	if not feq(BM.GetAngle2D(Vector3(0, -1, 0), Vector3(-1, 0, 0)), 0.5 * PI, 1.0e-4):
		print("CHECK FAIL: GetAngle2D(a,b) знак → ", BM.GetAngle2D(Vector3(0, -1, 0), Vector3(-1, 0, 0))); ok = false

	# GetNormalized(fallback): нулевой вектор → fallback
	if not vec_eq(BM.GetNormalized(Vector3.ZERO, Vector3(0, -1, 0)), Vector3(0, -1, 0)):
		print("CHECK FAIL: GetNormalized fallback"); ok = false
	# GetNormalized(fallback): почти-нулевой вектор (все оси < 1e-6) — тоже fallback, не деление на ~0
	# (vector3.cpp:170-181 проверяет каждую ось по-отдельности, не длину)
	if not vec_eq(BM.GetNormalized(Vector3(5.0e-7, 5.0e-7, 5.0e-7), Vector3(0, -1, 0)), Vector3(0, -1, 0)):
		print("CHECK FAIL: GetNormalized почти-нулевой вектор"); ok = false

	# Скорости (animcollection.hpp:57-104): корзины RangeVelocity
	if not feq(V.RangeVelocity(1.7), 0.0) or not feq(V.RangeVelocity(1.8), 3.5) \
		or not feq(V.RangeVelocity(4.2), 5.0) or not feq(V.RangeVelocity(6.0), 8.0):
		print("CHECK FAIL: RangeVelocity корзины"); ok = false
	if not feq(V.FloorVelocity(0.5), 3.5) or not feq(V.FloorVelocity(4.0), 5.0) or not feq(V.FloorVelocity(5.5), 8.0):
		print("CHECK FAIL: FloorVelocity"); ok = false
	if V.FloatToEnumVelocity(4.5) != 2 or V.FloatToEnumVelocity(0.0) != 0 or V.FloatToEnumVelocity(7.0) != 3:
		print("CHECK FAIL: FloatToEnumVelocity"); ok = false
	if not feq(V.EnumToFloatVelocity(1), 3.5):
		print("CHECK FAIL: EnumToFloatVelocity"); ok = false
	# GetVelocityID (utils.cpp:81-102): treatDribbleAsWalk схлопывает 2,3 → 1,2
	if V.GetVelocityID(3, false) != 3 or V.GetVelocityID(3, true) != 2 or V.GetVelocityID(1, true) != 1:
		print("CHECK FAIL: GetVelocityID"); ok = false

	# GetAngles (quaternion.cpp:197-226, перестановка x=el0,y=el2,z=el1):
	# body@24 клипа walk/045 → z == -pi/4 (выведено вручную из формулы оригинала)
	var QU = load("res://src/gpf/QuatUtil.cs")
	var angles: Vector3 = QU.GetAnglesVec(Quaternion(0.010774, -0.147878, -0.372312, 0.916187))
	if not feq(angles.z, -0.25 * PI, 1.0e-3):
		print("CHECK FAIL: GetAngles z → ", angles.z); ok = false
	# Чистый поворот вокруг Z на 0.3: z == 0.3
	var qz := Quaternion(Vector3(0, 0, 1), 0.3)
	if not feq(QU.GetAnglesVec(qz).z, 0.3, 1.0e-4):
		print("CHECK FAIL: GetAngles чистый Z"); ok = false
	# Гимбал-ветка (quaternion.cpp:203-213): singularityTest = ex*ey+ez*ew, где ex=q.X, ey=q.Z,
	# ez=q.Y, ew=q.W (перестановка индексов). q = (X=0.70710678, Y=0, Z=0.70710678, W=0), единичный
	# (0.5+0+0.5+0=1) → singularityTest = 0.70710678*0.70710678 + 0*0 = 0.5 > 0.49999 → северный
	# полюс: z = 2*atan2(ex, ez) = 2*atan2(0.70710678, 0) = 2*(pi/2) = pi; y = pi/2; x = 0
	# (посчитано вручную по формуле оригинала, не подогнано под вывод кода).
	var qs := Quaternion(0.70710678, 0.0, 0.70710678, 0.0)
	var angles_s: Vector3 = QU.GetAnglesVec(qs)
	if not feq(angles_s.x, 0.0, 1.0e-4) or not feq(angles_s.y, 0.5 * PI, 1.0e-4) or not feq(angles_s.z, PI, 1.0e-3):
		print("CHECK FAIL: GetAngles сингулярность → ", angles_s); ok = false

	# AngleAxis (quaternion.cpp:284-296) == конструктор Godot
	var q1: Quaternion = QU.AngleAxis(0.7, Vector3(0, 0, 1))
	if not feq(q1.z, sin(0.35), 1.0e-6) or not feq(q1.w, cos(0.35), 1.0e-6):
		print("CHECK FAIL: AngleAxis"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

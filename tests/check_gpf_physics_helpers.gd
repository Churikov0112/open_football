extends SceneTree
# Фаза 3, задача 2: хелперы физики (humanoid_utils.cpp:68-100,129-144; playerbase.cpp:131-139).
# Все ожидания перевычислены из формул C++ прямо здесь.

func feq(a: float, b: float, eps := 1.0e-5) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-5) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var PV = load("res://src/gpf/PhysicsVector.cs")
	if PV == null:
		print("CHECK FAIL: PhysicsVector.cs не найден — сначала dotnet build")
		quit(1)
		return

	# --- CalculateMovementAtFrame (humanoid_utils.cpp:68-100) ---
	# синтетические позиции: дельты 0.05 / 0.10 / 0.15 м за кадр (×100 → м/с)
	var poss: Array = [Vector3(0, 0, 0), Vector3(0, -0.05, 0), Vector3(0, -0.15, 0), Vector3(0, -0.30, 0)]
	# кадр 0 — спецслучай (:83-85): (p1-p0)*100
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 0, 1), Vector3(0, -5, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame кадр 0"); ok = false
	# последний кадр — спецслучай (:79-81): (p3-p2)*100, БЕЗ сглаживания
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 3, 1), Vector3(0, -15, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame последний кадр"); ok = false
	# кадр 1, smooth=1 (:87-97): среднее дельт кадров 1 и 2 = ((p1-p0)+(p2-p1))/2*100
	# внимание: цикл берёт frame in [frameNum-1 .. frameNum+1] с условием frame > 0,
	# т.е. дельту (p0→p1) НЕ отбрасывает (frame=1 > 0), а frame=0 отбрасывает.
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 1, 1), Vector3(0, -7.5, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame кадр 1 сглаживание → ",
			PV.CalculateMovementAtFrameArr(poss, 1, 1)); ok = false
	# кадр 2, smooth=1: среднее трёх дельт (кадры 1,2,3) = (5+10+15)/3 = 10
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 2, 1), Vector3(0, -10, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame кадр 2"); ok = false
	# smooth=0 на внутреннем кадре: одна дельта (p1→p2)*100
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 2, 0), Vector3(0, -10, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame smooth=0"); ok = false
	# Z-компонента отбрасывается Get2D (:80,:84,:90) — вертикаль корня в движение не попадает
	var poss_z: Array = [Vector3(0, 0, 0), Vector3(0, -0.05, 0.5), Vector3(0, -0.15, 1.0)]
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss_z, 0, 0), Vector3(0, -5, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame Get2D отбрасывает Z → ",
			PV.CalculateMovementAtFrameArr(poss_z, 0, 0)); ok = false
	# smoothFrames больше frameNum: окно клампится условием frame > 0 (frame может уйти в минус)
	# кадр 1, smooth=5 → окно [-4..6] ∩ [1..3] = дельты 1,2,3 → (5+10+15)/3 = 10
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 1, 5), Vector3(0, -10, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame smooth > frameNum → ",
			PV.CalculateMovementAtFrameArr(poss, 1, 5)); ok = false

	# --- StretchSprintTo (humanoid_utils.cpp:129-144) ---
	# ниже walkSprintSwitch (6.0) — без изменений
	if not feq(PV.StretchSprintTo(5.0, 7.0, 8.0), 5.0):
		print("CHECK FAIL: StretchSprintTo ниже порога"); ok = false
	# формула: 6 + (v-6) * (target-6)/(inputMax-6);  7.0: 6+1*(2/1)=8.0
	if not feq(PV.StretchSprintTo(7.0, 7.0, 8.0), 8.0):
		print("CHECK FAIL: StretchSprintTo(7,7,8) → ", PV.StretchSprintTo(7.0, 7.0, 8.0)); ok = false
	# 6.5: 6+0.5*2=7.0
	if not feq(PV.StretchSprintTo(6.5, 7.0, 8.0), 7.0):
		print("CHECK FAIL: StretchSprintTo(6.5,7,8)"); ok = false
	# ровно на пороге: 6+0*x=6
	if not feq(PV.StretchSprintTo(6.0, 7.0, 8.0), 6.0):
		print("CHECK FAIL: StretchSprintTo(6,7,8)"); ok = false
	# сжатие вниз (target < inputMax): 7.0 при target=6.5 → 6+1*(0.5/1)=6.5
	if not feq(PV.StretchSprintTo(7.0, 7.0, 6.5), 6.5):
		print("CHECK FAIL: StretchSprintTo сжатие вниз → ", PV.StretchSprintTo(7.0, 7.0, 6.5)); ok = false

	# --- GetMaxVelocity (playerbase.cpp:131-139): sprintVelocity * (0.9 + stat*0.1) ---
	# sprintVelocity == 8.0 (gamedefines.hpp:21); статы игрока лежат в [0,1] (playerdata.cpp:82).
	# Исправлено при TDD: план фазы ждал 8.8 при stat=1, но 8*(0.9+1*0.1) = 8*1.0 = 8.0 —
	# ожидания ниже перевычислены из формулы оригинала, а не взяты из плана.
	if not feq(PV.GetMaxVelocity(1.0), 8.0 * (0.9 + 1.0 * 0.1)):
		print("CHECK FAIL: GetMaxVelocity(1) → ", PV.GetMaxVelocity(1.0)); ok = false
	if not feq(PV.GetMaxVelocity(0.0), 8.0 * 0.9):
		print("CHECK FAIL: GetMaxVelocity(0) → ", PV.GetMaxVelocity(0.0)); ok = false
	if not feq(PV.GetMaxVelocity(0.6), 8.0 * 0.96):
		print("CHECK FAIL: GetMaxVelocity(0.6) → ", PV.GetMaxVelocity(0.6)); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

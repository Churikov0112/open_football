extends SceneTree
# Фаза 3, задача 3: порт CalculatePhysicsVector (humanoidbase.cpp:2014-2544).
# Ожидания — инварианты, выведенные из формул C++, и перевычисления формул на выходах.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

# первый клип по предикату (детерминированный скан)
func find_anim(c, V, type: String, in_vel: int, out_vel: int, max_out_angle: float) -> int:
	for i in c.GetAnimationCount():
		var a = c.GetAnim(i)
		if a.GetAnimType() != type: continue
		if V.FloatToEnumVelocity(a.GetIncomingVelocity()) != in_vel: continue
		if V.FloatToEnumVelocity(a.GetOutgoingVelocity()) != out_vel: continue
		if absf(a.GetOutgoingAngle()) > max_out_angle: continue
		if absf(a.GetIncomingBodyAngle()) > 0.06 * PI: continue
		return i
	return -1

func _initialize() -> void:
	var ok := true
	var V = load("res://src/gpf/Velo.cs")
	var BM = load("res://src/gpf/BluntMath.cs")
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var PV = load("res://src/gpf/PhysicsVector.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)

	var fwd := Vector3(0, -1, 0)

	var pv = PV.new()
	# страховка от зависания -s при SCRIPT ERROR: без ядра задачи 3 выходим чисто (RED)
	if not pv.has_method("CalculateForAnim"):
		print("CHECK FAIL: нет CalculateForAnim (ядро задачи 3 не собрано)")
		print("CHECK FAIL")
		quit(1)
		return

	# ---------- 1. Детерминизм + структура на прямом walk-клипе ----------
	var walk_id: int = find_anim(c, V, "movement", 2, 2, 0.06 * PI)
	if walk_id < 0:
		print("CHECK FAIL: прямой walk-клип не найден")
		print("CHECK FAIL")
		quit(1)
		return
	var walk_anim = c.GetAnim(walk_id)
	var in_vel: float = V.RangeVelocity(walk_anim.GetIncomingVelocity())

	pv.SetStats(0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
	pv.SetConfigFactors(0.5, 0.5)
	pv.SetTouchContext(0.0, 0.0)
	pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, in_vel, fwd * in_vel)
	var res1: Vector3 = pv.CalculateForAnim(c, walk_id, true, fwd * 5.0, true, fwd)
	var poss1: Array = pv.GetLastPositions()
	var rot1: float = pv.GetLastRotationOffset()
	var res2: Vector3 = pv.CalculateForAnim(c, walk_id, true, fwd * 5.0, true, fwd)
	var poss2: Array = pv.GetLastPositions()
	if res1 != res2 or poss1.size() != poss2.size() or rot1 != pv.GetLastRotationOffset():
		print("CHECK FAIL: недетерминизм"); ok = false
	for i in poss1.size():
		if poss1[i] != poss2[i]:
			print("CHECK FAIL: недетерминизм позиций, кадр ", i); ok = false
			break

	# размер: цикл :2206 шагом 10 мс кладёт точку каждый виток → ровно frameCount точек
	if poss1.size() != walk_anim.GetFrameCount():
		print("CHECK FAIL: позиций ", poss1.size(), " != frameCount ", walk_anim.GetFrameCount()); ok = false
	for i in poss1.size():
		var p: Vector3 = poss1[i]
		if p.z != 0.0:
			print("CHECK FAIL: Z != 0 в кадре ", i); ok = false
			break
	# прямой клип и прямое желание → путь уходит в -Y
	var last_p: Vector3 = poss1[poss1.size() - 1]
	if last_p.y >= -0.1:
		print("CHECK FAIL: прямой walk не уехал вперёд: ", last_p); ok = false

	# выходная idle-ность совпадает с клипом (:2459-2473, hard quantize)
	if V.FloatToEnumVelocity(res1.length()) == 0:
		print("CHECK FAIL: walk-клип дал idle-выход"); ok = false

	# rotationOffset (:2499-2503): для не-idle выхода — перевычисляем формулу на выходах
	var expected_rot: float = BM.GetAngle2D(BM.GetRotated2D(res1, -0.0), walk_anim.GetOutgoingMovement())
	if not feq(rot1, expected_rot):
		print("CHECK FAIL: rotationOffset ", rot1, " != формула ", expected_rot); ok = false

	# ---------- 2. Idle-клип: желание «стоять» → idle-выход, rotationOffset по формуле ----------
	var idle_id: int = c.GetIdleMovementAnimID()
	if idle_id < 0:
		print("CHECK FAIL: idle-клип не найден")
		print("CHECK FAIL")
		quit(1)
		return
	var idle_anim = c.GetAnim(idle_id)
	pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, 0.0, Vector3.ZERO)
	var res_idle: Vector3 = pv.CalculateForAnim(c, idle_id, true, Vector3.ZERO, true, fwd)
	if V.FloatToEnumVelocity(res_idle.length()) != 0:
		print("CHECK FAIL: idle-клип дал не-idle выход: ", res_idle.length()); ok = false
	# idle-выход → rotationOffset = toDesiredAngle_capped * physicsBias (:2502); перевычисляем:
	# desired idle → desiredVector = bodyDirRel (fwd); anim-выход idle → animOutgoingVector =
	# GetOutgoingDirection() (:2156); клип «прямо» (|animChange| <= 0.06π) → straight-кап 0.125π;
	# physicsBias movement = 1.0
	var out_dir: Vector3 = idle_anim.GetOutgoingDirection()
	var to_desired: float = BM.GetAngle2D(fwd, out_dir)
	var expected_idle_rot: float = 0.0
	if absf(to_desired) <= 0.5 * PI:
		var anim_change: float = BM.GetAngle2D(out_dir, fwd)
		if absf(anim_change) > 0.06 * PI:
			# сторона совпала/нет — оба капа тут 0.125π, ветвление не влияет (:2163-2169)
			expected_idle_rot = clampf(to_desired, -0.125 * PI, 0.125 * PI)
		else:
			expected_idle_rot = clampf(to_desired, -0.125 * PI, 0.125 * PI)
	if not feq(pv.GetLastRotationOffset(), expected_idle_rot, 1.0e-4):
		print("CHECK FAIL: rotationOffset idle ", pv.GetLastRotationOffset(),
			" != формула ", expected_idle_rot); ok = false

	# ---------- 3. Поворот: желание -45° тянет выход к желаемому ----------
	var right45: Vector3 = BM.GetRotated2D(fwd, -0.25 * PI)
	pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, in_vel, fwd * in_vel)
	var res_turn: Vector3 = pv.CalculateForAnim(c, walk_id, true, right45 * 5.0, true, right45)
	var angle_before: float = absf(BM.GetAngle2D(
		BM.GetNormalized(walk_anim.GetOutgoingMovement(), fwd), right45))
	var angle_after: float = absf(BM.GetAngle2D(BM.GetNormalized(res_turn, fwd), right45))
	if angle_after >= angle_before - 0.01:
		print("CHECK FAIL: поворот не притянул выход: до ", angle_before, " после ", angle_after); ok = false

	# ---------- 4. Стат velocity растягивает спринт ----------
	var sprint_id: int = find_anim(c, V, "movement", 3, 3, 0.06 * PI)
	if sprint_id < 0:
		print("CHECK FAIL: прямой sprint-клип не найден"); ok = false
	else:
		var sprint_anim = c.GetAnim(sprint_id)
		var sprint_in: float = V.RangeVelocity(sprint_anim.GetIncomingVelocity())
		pv.SetStats(0.6, 0.6, 1.0, 0.6, 0.6, 0.6)
		pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, sprint_in, fwd * sprint_in)
		var res_fast: Vector3 = pv.CalculateForAnim(c, sprint_id, true, fwd * 8.0, true, fwd)
		pv.SetStats(0.6, 0.6, 0.3, 0.6, 0.6, 0.6)
		pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, sprint_in, fwd * sprint_in)
		var res_slow: Vector3 = pv.CalculateForAnim(c, sprint_id, true, fwd * 8.0, true, fwd)
		if res_fast.length() < res_slow.length() - 1.0e-4:
			print("CHECK FAIL: stat_velocity 1.0 медленнее 0.3: ",
				res_fast.length(), " < ", res_slow.length()); ok = false

	# ---------- 5. Ловкость помогает доворачивать ----------
	var right90: Vector3 = BM.GetRotated2D(fwd, -0.5 * PI)
	pv.SetStats(1.0, 0.6, 0.6, 0.6, 0.6, 0.6)
	pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, in_vel, fwd * in_vel)
	var res_agile: Vector3 = pv.CalculateForAnim(c, walk_id, true, right90 * 5.0, true, right90)
	pv.SetStats(0.0, 0.6, 0.6, 0.6, 0.6, 0.6)
	pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, in_vel, fwd * in_vel)
	var res_stiff: Vector3 = pv.CalculateForAnim(c, walk_id, true, right90 * 5.0, true, right90)
	var d_agile: float = absf(BM.GetAngle2D(BM.GetNormalized(res_agile, fwd), right90))
	var d_stiff: float = absf(BM.GetAngle2D(BM.GetNormalized(res_stiff, fwd), right90))
	if d_agile > d_stiff + 1.0e-4:
		print("CHECK FAIL: agility 1.0 довернула хуже 0.0: ", d_agile, " vs ", d_stiff); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

extends SceneTree
# Фаза 3, задача 4: HumanoidBase — состояние по варпнутым позициям (humanoidbase.cpp:585-711,1622-1737).
# Ожидания — инварианты из формул C++ и жёсткие ассерты, выведенные из сырого кэша idle-клипа.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func make_humanoid(HB, c, sel):
	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	return h

func _initialize() -> void:
	var ok := true
	var V = load("res://src/gpf/Velo.cs")
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var AS = load("res://src/gpf/AnimSelector.cs")
	# страховка от зависания -s при SCRIPT ERROR: без ядра задачи 4 выходим чисто (RED)
	var HB = load("res://src/gpf/HumanoidBase.cs")
	if HB == null or not HB.new().has_method("Tick"):
		print("CHECK FAIL: нет src/gpf/HumanoidBase.cs (ядро задачи 4 не собрано)")
		print("CHECK FAIL")
		quit(1)
		return
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)
	var sel = AS.new()
	sel.Setup(c)
	var fwd := Vector3(0, -1, 0)

	# --- 0. Жёсткие ассерты первого тика: значения из сырого кэша idle-клипа ---
	# ResetSituation кладёт positions = кэш коллекции (:953), frameNum = 0; первый Tick:
	# CalculateSpatialState (:1624-1625) → position = startPos(0) + positions[0];
	# затем frameNum++ (:588) и apply (:700-705) → frameNum 1, позиция startPos + positions[1],
	# ориентация startAngle + нулевой rotationSmuggle (:965-967), noPos = true.
	var h0 = make_humanoid(HB, c, sel)
	var idle_id: int = c.GetIdleMovementAnimID()
	var idle_cache: Array = AC.BuildPositionCache(c.GetAnim(idle_id))
	# до первого Tick noPos = false — дефолт конструктора AnimApplyBuffer (humanoidbase.hpp:139)
	if h0.GetApplyNoPos():
		print("CHECK FAIL: noPos == true сразу после ResetSituation (hpp:139 даёт false)"); ok = false
	h0.Tick(fwd, 0.0, false, Vector3.ZERO)
	if h0.GetCurrentAnimId() != idle_id:
		print("CHECK FAIL: после Reset текущий клип ", h0.GetCurrentAnimId(), " != idle ", idle_id); ok = false
	var cache0: Vector3 = idle_cache[0]
	if not vec_eq(h0.GetSpatialPosition(), cache0, 1.0e-5):
		print("CHECK FAIL: spatial-позиция первого тика ", h0.GetSpatialPosition(),
			" != positions[0] кэша ", cache0); ok = false
	if h0.GetApplyFrameNum() != 1:
		print("CHECK FAIL: apply-кадр первого тика ", h0.GetApplyFrameNum(), " != 1"); ok = false
	var cache1: Vector3 = idle_cache[1]
	if not vec_eq(h0.GetApplyPosition(), cache1, 1.0e-5):
		print("CHECK FAIL: apply-позиция первого тика ", h0.GetApplyPosition(),
			" != positions[1] кэша ", cache1); ok = false
	if absf(h0.GetApplyOrientation()) > 1.0e-6:
		print("CHECK FAIL: apply-ориентация первого тика ", h0.GetApplyOrientation(), " != 0"); ok = false
	if not h0.GetApplyNoPos():
		print("CHECK FAIL: первый тик без noPos при живом кэше positions"); ok = false

	# --- 1. Стоим по idle-команде: не уезжаем, скорость idle ---
	var h = make_humanoid(HB, c, sel)
	for i in 200:
		h.Tick(fwd, 0.0, true, h.GetSpatialPosition() + fwd * 10.0)
	if h.GetSpatialEnumVelocity() != 0:
		print("CHECK FAIL: idle-команда разогнала до ", h.GetSpatialEnumVelocity()); ok = false
	if h.GetSpatialPosition().length() > 0.5:
		print("CHECK FAIL: idle уехал в ", h.GetSpatialPosition()); ok = false

	# --- 2. Спринт вперёд: инварианты состояния на каждом тике ---
	h = make_humanoid(HB, c, sel)
	# прогрев 2 тика: на самом первом тике previousPosition2D — точка ResetSituation, а позиция —
	# кадр 0 сырого кэша idle-клипа; их дельта не обязана быть нулевой (движение-инвариант
	# осмыслен со второго тика)
	h.Tick(fwd, 8.0, true, h.GetSpatialPosition() + fwd * 10.0)
	h.Tick(fwd, 8.0, true, h.GetSpatialPosition() + fwd * 10.0)
	var allowed := [Vector3(0, -1, 0)]
	for a in [-0.25, 0.25, -0.75, 0.75]:
		allowed.append(Vector3(0, -1, 0).rotated(Vector3(0, 0, 1), a * PI))
	var transitions := 0
	var t := 0
	# 6 клипов: разгон при физике медленнее lite — актуальная скорость может отставать от бакета клипа
	while transitions < 6 and t < 4000:
		var before: Vector3 = h.GetSpatialPosition()
		var switched: bool = h.Tick(fwd, 8.0, true, h.GetSpatialPosition() + fwd * 10.0)
		if switched: transitions += 1
		t += 1
		# движение == дельта позиций ×100 (:1642; smuggle-нули)
		var expected_mv: Vector3 = (h.GetSpatialPosition() - before) * 100.0
		if not vec_eq(h.GetSpatialMovement(), expected_mv, 1.0e-3):
			print("CHECK FAIL: movement != Δpos×100 на тике ", t); ok = false
			break
		# enum == бакет float (CalculateSpatialState :1670-1671)
		if h.GetSpatialEnumVelocity() != V.FloatToEnumVelocity(h.GetSpatialFloatVelocity()):
			print("CHECK FAIL: enum/float разошлись на тике ", t); ok = false
			break
		# RelBodyDirectionVec квантован в одну из 5 разрешённых (:1715)
		var best_dot := -1.0
		for av in allowed:
			var av2: Vector3 = av
			var d: float = av2.dot(h.GetRelBodyDirectionVec())
			if d > best_dot: best_dot = d
		if best_dot < 0.9999:
			print("CHECK FAIL: RelBodyDirectionVec вне решётки: ", h.GetRelBodyDirectionVec()); ok = false
			break
	if t >= 4000:
		print("CHECK FAIL: 6 смен клипа не случились за 4000 тиков"); ok = false
	# после 6 клипов разгона по спринт-команде скорость минимум walk
	if h.GetSpatialEnumVelocity() < 2:
		print("CHECK FAIL: после разгона скорость ", h.GetSpatialEnumVelocity()); ok = false
	if h.GetSpatialPosition().y > -2.0:
		print("CHECK FAIL: не уехал вперёд: ", h.GetSpatialPosition()); ok = false

	# --- 3. Детерминизм: два одинаковых прогона тик-в-тик ---
	var h1 = make_humanoid(HB, c, sel)
	var h2 = make_humanoid(HB, c, sel)
	for i in 500:
		h1.Tick(fwd, 8.0, true, h1.GetSpatialPosition() + fwd * 10.0)
		h2.Tick(fwd, 8.0, true, h2.GetSpatialPosition() + fwd * 10.0)
	if h1.GetSpatialPosition() != h2.GetSpatialPosition() or h1.GetSpatialAngle() != h2.GetSpatialAngle():
		print("CHECK FAIL: недетерминизм прогона"); ok = false

	# --- 4. apply-данные согласованы: noPos и позиция от startPos ---
	if not h.GetApplyNoPos():
		print("CHECK FAIL: apply без noPos при живом кэше positions"); ok = false

	# --- 5. Data-pinned: лерп rotationSmuggleOffset наследника (humanoid.cpp:722-742) ---
	# Для клипов после смены сверяем GetApplyOrientation() на кадре k с пересчётом формулы:
	# startAngle + begin*(1-capped) + end*capped, capped = min(1, (k+1)/min(16, effective+1));
	# 16 — beginRotationFrameCount (humanoid.cpp:724). startAngle на тике смены == spatial.Angle
	# этого тика (:648-649); begin/end — через мост-геттеры.
	var h5 = make_humanoid(HB, c, sel)
	var dir_right: Vector3 = Vector3(0, -1, 0).rotated(Vector3(0, 0, 1), -0.5 * PI)
	var pinned_any := false
	var switches_seen := 0
	var tt := 0
	while switches_seen < 4 and tt < 2000 and ok:
		var sw: bool = h5.Tick(dir_right, 8.0, true, h5.GetSpatialPosition() + dir_right * 10.0)
		tt += 1
		if not sw: continue
		switches_seen += 1
		var start_angle: float = h5.GetSpatialAngle()
		var begin_s: float = h5.GetRotationSmuggleBegin()
		var end_s: float = h5.GetRotationSmuggleEnd()
		var eff: int = c.GetAnim(h5.GetCurrentAnimId()).GetEffectiveFrameCount()
		if absf(begin_s) > 1.0e-6 or absf(end_s) > 1.0e-6:
			pinned_any = true
		# кадр 0 (тик смены) и дальше до кадра 17 (покрывает кап 16) либо до конца клипа
		var k := 0
		while ok:
			var capped: float = minf(1.0, (k + 1) / float(mini(16, eff + 1)))
			var expected_or: float = start_angle + begin_s * (1.0 - capped) + end_s * capped
			if h5.GetApplyFrameNum() != k:
				print("CHECK FAIL: apply-кадр ", h5.GetApplyFrameNum(), " != ", k); ok = false
				break
			if absf(h5.GetApplyOrientation() - expected_or) > 1.0e-4:
				print("CHECK FAIL: apply-ориентация на кадре ", k, ": ",
					h5.GetApplyOrientation(), " != формула ", expected_or); ok = false
				break
			if k >= 17:
				break
			var sw2: bool = h5.Tick(dir_right, 8.0, true, h5.GetSpatialPosition() + dir_right * 10.0)
			tt += 1
			if sw2:
				switches_seen += 1
				break # клип кончился раньше 18 кадров — захват завершён
			k += 1
	if switches_seen < 4 and ok:
		print("CHECK FAIL: секция 5 — 4 смены клипа не случились за 2000 тиков"); ok = false
	if not pinned_any:
		print("CHECK FAIL: ни одна смена клипа не дала ненулевой rotationSmuggle"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

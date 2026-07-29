extends SceneTree
# AnimSelector: стабильность сортировки, ForceInto*-таблицы, cornering bias, выбор клипа.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func _initialize() -> void:
	var ok := true
	var SelScript := load("res://src/gpf/AnimSelector.cs")
	var sel = SelScript.new()

	# ForceInto*-таблицы (humanoidbase.cpp:63-97, 2547-2606)
	var v: Vector3 = sel.ForceIntoAllowedBodyDirectionVec(Vector3(0.1, -1, 0).normalized())
	if not feq(v.x, 0.0) or not feq(v.y, -1.0):
		print("CHECK FAIL: allowed body dir → ", v); ok = false
	if not feq(sel.ForceIntoAllowedBodyDirectionAngle(0.3 * PI), 0.25 * PI):
		print("CHECK FAIL: allowed body angle"); ok = false
	if not feq(sel.ForceIntoPreferredDirectionAngle(0.09 * PI), 0.111 * PI):
		print("CHECK FAIL: preferred angle 0.09pi → 0.111pi (20°)"); ok = false
	if not feq(sel.ForceIntoPreferredDirectionAngle(0.95 * PI), 0.999 * PI):
		print("CHECK FAIL: preferred angle хвост"); ok = false

	# CalculateBiasForFastCornering (humanoid_utils.cpp:53-66):
	# нулевая скорость → 0; сзади на спринте → близко к 1
	if not feq(SelScript.CalculateBiasForFastCornering(Vector3.ZERO, Vector3(0, -5, 0), 1.0, 0.9), 0.0):
		print("CHECK FAIL: cornering bias @idle"); ok = false
	var b_back: float = SelScript.CalculateBiasForFastCornering(Vector3(0, -8, 0), Vector3(0, 8, 0), 1.0, 0.9)
	if b_back < 0.85:
		print("CHECK FAIL: cornering bias разворот на спринте → ", b_back); ok = false

	# Выбор клипа на живой коллекции
	var col = load("res://src/gpf/AnimCollection.cs").new()
	var skel: Skeleton3D = load("res://src/gpf/SkeletonBuilder.cs").new().BuildUtilitySkeleton()
	get_root().add_child(skel)
	col.Load("res://assets/gpf/animations", skel)
	sel.Setup(col)

	# Из idle лицом вперёд, команда «walk вперёд»: клип с idle-входом, движение вперёд
	var idx: int = sel.SelectMovementAnim(
		Vector3.ZERO, 0.0, 0, 0.0, Vector3(0, -1, 0), 1,
		Vector3(0, -1, 0), 5.0, true, Vector3(0, -10, 0))
	if idx < 0:
		print("CHECK FAIL: выбор из idle не дал клипа"); ok = false
	else:
		var a = col.GetAnim(idx)
		print("[selector] idle→walk fwd: ", a.GetName(), " quadrant=", a.GetVariable("quadrant_id"))
		if a.GetAnimType() != "movement":
			print("CHECK FAIL: не movement"); ok = false
		if a.GetIncomingVelocity() >= 1.8:
			print("CHECK FAIL: вход не idle"); ok = false
		var q: int = int(a.GetVariable("quadrant_id"))
		# разгоняемся вперёд: скорость квадранта dribble/walk, |угол| ≤ 20°
		if col.GetQuadrantVelocityId(q) < 1 or col.GetQuadrantVelocityId(q) > 2:
			print("CHECK FAIL: квадрант-скорость → ", col.GetQuadrantVelocityId(q)); ok = false
		if absf(col.GetQuadrantAngle(q)) > 0.12 * PI:
			print("CHECK FAIL: квадрант-угол → ", col.GetQuadrantAngle(q)); ok = false

	# Из walk вперёд, команда «walk вправо-назад» (135°): выбранный клип поворачивает в нужную сторону
	var dir135 := Vector3(0, -1, 0).rotated(Vector3(0, 0, 1), -0.75 * PI)
	var idx2: int = sel.SelectMovementAnim(
		Vector3.ZERO, 0.0, 2, 5.0, Vector3(0, -1, 0), 1,
		dir135, 5.0, true, dir135 * 10.0)
	if idx2 < 0:
		print("CHECK FAIL: выбор поворота не дал клипа"); ok = false
	else:
		var a2 = col.GetAnim(idx2)
		var q2: int = int(a2.GetVariable("quadrant_id"))
		print("[selector] walk→135: ", a2.GetName(), " quadrant angle=", col.GetQuadrantAngle(q2))
		if col.GetQuadrantAngle(q2) > -0.05:
			print("CHECK FAIL: поворот не в ту сторону: угол ", col.GetQuadrantAngle(q2)); ok = false

	# Датасет отранжирован и непуст; повторный вызов детерминирован
	var ds1: Array = sel.SelectMovementDataSet(
		Vector3.ZERO, 0.0, 0, 0.0, Vector3(0, -1, 0), 1, Vector3(0, -1, 0), 5.0, true, Vector3(0, -10, 0))
	var ds2: Array = sel.SelectMovementDataSet(
		Vector3.ZERO, 0.0, 0, 0.0, Vector3(0, -1, 0), 1, Vector3(0, -1, 0), 5.0, true, Vector3(0, -10, 0))
	if ds1.is_empty() or ds1 != ds2:
		print("CHECK FAIL: датасет пуст или недетерминирован"); ok = false

	skel.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

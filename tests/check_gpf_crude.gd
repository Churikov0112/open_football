extends SceneTree
# CrudeSelection: свойства-фильтры проверяются на живой коллекции повторной валидацией результата.

func _initialize() -> void:
	var ok := true
	var col = load("res://src/gpf/AnimCollection.cs").new()
	var skel: Skeleton3D = load("res://src/gpf/SkeletonBuilder.cs").new().BuildUtilitySkeleton()
	get_root().add_child(skel)
	col.Load("res://assets/gpf/animations", skel)
	var QueryScript := load("res://src/gpf/CrudeSelectionQuery.cs")

	# 1) movement + incoming idle strict + body dir вперёд strict:
	var q1 = QueryScript.new()
	q1.ByFunctionType = true
	q1.FunctionTypeId = 1 # FnMovement
	q1.ByIncomingVelocity = true
	q1.IncomingVelocityId = 0
	q1.IncomingVelocityStrict = true
	q1.ByIncomingBodyDirection = true
	q1.IncomingBodyDirectionStrict = true
	q1.IncomingBodyDirection = Vector3(0, -1, 0)
	var ds1: Array[int] = []
	col.CrudeSelection(ds1, q1)
	if ds1.is_empty():
		print("CHECK FAIL: q1 пуст"); ok = false
	for i in ds1:
		var a = col.GetAnim(i)
		if a.GetAnimType() != "movement":
			print("CHECK FAIL: q1 не-movement: ", a.GetName()); ok = false; break
		if a.GetIncomingVelocity() >= 1.8:
			print("CHECK FAIL: q1 не-idle вход: ", a.GetName()); ok = false; break

	# 2) то же, но incoming walk strict → в выборке нет idle-входов и нет клипов с бОльшим
	# углом корпуса, чем у запроса (:687-692)
	var q2 = QueryScript.new()
	q2.ByFunctionType = true
	q2.FunctionTypeId = 1
	q2.ByIncomingVelocity = true
	q2.IncomingVelocityId = 2
	q2.IncomingVelocityStrict = true
	q2.ByIncomingBodyDirection = true
	q2.IncomingBodyDirectionStrict = true
	q2.IncomingBodyDirection = Vector3(0, -1, 0)
	var ds2: Array[int] = []
	col.CrudeSelection(ds2, q2)
	if ds2.is_empty():
		print("CHECK FAIL: q2 пуст"); ok = false
	for i in ds2:
		var a = col.GetAnim(i)
		var vid: int = load("res://src/gpf/Velo.cs").FloatToEnumVelocity(a.GetIncomingVelocity())
		if vid != 2:
			print("CHECK FAIL: q2 strict нарушен: ", a.GetName(), " vid=", vid); ok = false; break

	# strict уже, чем нестрогий запрос
	var q2l = QueryScript.new()
	q2l.ByFunctionType = true
	q2l.FunctionTypeId = 1
	q2l.ByIncomingVelocity = true
	q2l.IncomingVelocityId = 2
	q2l.IncomingVelocityStrict = false
	var ds2l: Array[int] = []
	col.CrudeSelection(ds2l, q2l)
	if ds2l.size() < ds2.size():
		print("CHECK FAIL: нестрогий уже строгого: ", ds2l.size(), " < ", ds2.size()); ok = false
	# нестрогая матрица (:540-544): walk-запрос не пускает idle-входы
	for i in ds2l:
		if col.GetAnim(i).GetIncomingVelocity() < 1.8:
			print("CHECK FAIL: q2l пропустил idle-вход"); ok = false; break

	# 3) trap + incoming ball direction: девиация ≤ 0.25pi (или лимит из тега клипа).
	# ПОПРАВКА к брифу: бриф ставил FunctionTypeId=2 (FnBallControl), но ни один ballcontrol-клип
	# в assets/gpf не несёт тега incomingballdirection (его несут только trap/deflect/interfere), а в
	# оригинале byIncomingBallDirection выставляется лишь для Trap/Interfere/Deflect
	# (humanoid.cpp:1318-1323) — ровно для типов с этим тегом, оттого фатал :761 там не срабатывает.
	# FnBallControl отсеивал бы ВСЕ клипы (пустой ds3) и спамил PushError. Берём FnTrap (3).
	var BM = load("res://src/gpf/BluntMath.cs")
	var q3 = QueryScript.new()
	q3.ByFunctionType = true
	q3.FunctionTypeId = 3 # FnTrap
	q3.ByIncomingBallDirection = true
	q3.IncomingBallDirection = Vector3(0, -1, 0)
	var ds3: Array[int] = []
	col.CrudeSelection(ds3, q3)
	if ds3.is_empty():
		print("CHECK FAIL: q3 пуст"); ok = false
	for i in ds3:
		var a = col.GetAnim(i)
		var bd: Vector3 = BM.GetVectorFromString(a.GetVariable("incomingballdirection"))
		if bd.length() == 0.0:
			continue # клип без тега отфильтрован ошибкой — сюда не попадает
		bd.z *= 0.4
		bd = bd.normalized()
		var adapted := Vector3(0, -1, 0)
		var dev: float = absf(BM.GetAngle2D(adapted, bd))
		var max_dev: float = absf(BM.AtoF(a.GetVariable("incomingballdirection_maxdeviation")) * PI)
		if max_dev == 0.0:
			max_dev = 0.25 * PI
		if dev > max_dev + 1.0e-4:
			print("CHECK FAIL: q3 девиация ", dev, " > ", max_dev, ": ", a.GetName()); ok = false; break

	# 4) lastditch по умолчанию отсечены
	for i in ds1:
		if col.GetAnim(i).GetVariable("lastditch") == "true":
			print("CHECK FAIL: lastditch в выборке без allowLastDitchAnims"); ok = false; break

	# 5) trip по типу: каждый выбранный имеет triptype == 1
	var q5 = QueryScript.new()
	q5.ByFunctionType = true
	q5.FunctionTypeId = 12 # FnTrip
	q5.ByTripType = true
	q5.TripType = 1
	var ds5: Array[int] = []
	col.CrudeSelection(ds5, q5)
	for i in ds5:
		if int(round(BM.AtoF(col.GetAnim(i).GetVariable("triptype")))) != 1:
			print("CHECK FAIL: q5 triptype ≠ 1: ", col.GetAnim(i).GetName()); ok = false; break

	skel.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

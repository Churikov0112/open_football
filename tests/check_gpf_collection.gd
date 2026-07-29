extends SceneTree
# AnimCollection каркас: 34 квадранта, файловая загрузка ×2, переменные _PrepareAnim.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func _initialize() -> void:
	var ok := true
	var col = load("res://src/gpf/AnimCollection.cs").new()
	var skel: Skeleton3D = load("res://src/gpf/SkeletonBuilder.cs").new().BuildUtilitySkeleton()
	get_root().add_child(skel)

	# Квадранты строятся в конструкторе (animcollection.cpp:61-106): 1 idle + 3×11
	if col.GetQuadrantCount() != 34:
		print("CHECK FAIL: квадрантов → ", col.GetQuadrantCount()); ok = false
	if col.GetQuadrantVelocityId(0) != 0 or not feq(col.GetQuadrantAngle(0), 0.0):
		print("CHECK FAIL: квадрант 0 не idle"); ok = false
	# id 12 = walk 0°; id 19 = walk -45°; id 23 = sprint 0°
	if col.GetQuadrantVelocityId(12) != 2 or not feq(col.GetQuadrantAngle(12), 0.0):
		print("CHECK FAIL: квадрант 12 ≠ walk 0°"); ok = false
	if col.GetQuadrantVelocityId(19) != 2 or not feq(col.GetQuadrantAngle(19), -0.25 * PI):
		print("CHECK FAIL: квадрант 19 ≠ walk -45° → id?", col.GetQuadrantAngle(19)); ok = false
	if col.GetQuadrantVelocityId(23) != 3 or not feq(col.GetQuadrantAngle(23), 0.0):
		print("CHECK FAIL: квадрант 23 ≠ sprint 0°"); ok = false
	# позиция квадранта = (0,-1,0).Rotate2D(angle) * EnumToFloat(velocity)
	var p19: Vector3 = col.GetQuadrantPosition(19)
	if not feq(p19.x, -sin(0.25 * PI) * 5.0) or not feq(p19.y, -cos(0.25 * PI) * 5.0):
		print("CHECK FAIL: позиция квадранта 19 → ", p19); ok = false

	# Загрузка файловой части (templates подключатся в следующей задаче)
	var t0 := Time.get_ticks_msec()
	col.Load("res://assets/gpf/animations", skel)
	print("[collection] load: ", Time.get_ticks_msec() - t0, " ms, anims: ", col.GetAnimationCount())

	# 283 файла (293 минус 10 templates) × 2 зеркала = 566
	if col.GetAnimationCount() != 566:
		print("CHECK FAIL: размер коллекции → ", col.GetAnimationCount(), " (ожидалось 566)"); ok = false

	# Каждый клип обогащён; правило чётности зеркал: чётный индекс — оригинал, нечётный — _mirror
	var bad_quadrant := 0
	var bad_diff := 0
	for i in range(col.GetAnimationCount()):
		var anim = col.GetAnim(i)
		if anim.GetVariable("quadrant_id") == "": bad_quadrant += 1
		var d := float(anim.GetVariable("animdifficultyfactor"))
		if d < 0.0 or d > 1.0: bad_diff += 1
	if bad_quadrant > 0:
		print("CHECK FAIL: клипов без quadrant_id: ", bad_quadrant); ok = false
	if bad_diff > 0:
		print("CHECK FAIL: animdifficultyfactor вне [0,1]: ", bad_diff); ok = false

	# Конкретика: walk/045 → квадрант 19 (walk −45°), его зеркало → 14 (walk +45°)
	var i045 := -1
	for i in range(col.GetAnimationCount()):
		var nm: String = col.GetAnim(i).GetName()
		if nm.ends_with("movement/walk/045.anim"):
			i045 = i
			break
	if i045 < 0:
		print("CHECK FAIL: walk/045 не найден в коллекции"); ok = false
	else:
		if col.GetAnim(i045).GetVariable("quadrant_id") != "19":
			print("CHECK FAIL: quadrant walk/045 → ", col.GetAnim(i045).GetVariable("quadrant_id")); ok = false
		var mirror = col.GetAnim(i045 + 1)
		if not mirror.GetName().ends_with("_mirror"):
			print("CHECK FAIL: за оригиналом не следует зеркало"); ok = false
		elif mirror.GetVariable("quadrant_id") != "14":
			print("CHECK FAIL: quadrant зеркала → ", mirror.GetVariable("quadrant_id")); ok = false

	# Касания: у ballcontrol-клипов touchframe ≥ 0 и есть touch_bodypart; у movement touchframe = -1
	var i_bc := -1
	for i in range(col.GetAnimationCount()):
		if col.GetAnim(i).GetName().ends_with("ballcontrol/idle/000.anim"):
			i_bc = i
			break
	if i_bc < 0:
		print("CHECK FAIL: ballcontrol/idle/000 не найден"); ok = false
	else:
		if int(col.GetAnim(i_bc).GetVariable("touchframe")) < 0:
			print("CHECK FAIL: touchframe ballcontrol → ", col.GetAnim(i_bc).GetVariable("touchframe")); ok = false
		if col.GetAnim(i_bc).GetVariable("touch_bodypart") == "":
			print("CHECK FAIL: touch_bodypart пуст"); ok = false
	if i045 >= 0 and col.GetAnim(i045).GetVariable("touchframe") != "-1":
		print("CHECK FAIL: movement-клип с touchframe ≠ -1"); ok = false

	# GetQuadrantID: движение (0,-5,0) → walk 0° (id 12)
	if i045 >= 0 and col.GetQuadrantID(col.GetAnim(i045), Vector3(0, -5, 0), 0.0) != 12:
		print("CHECK FAIL: GetQuadrantID (0,-5,0) → ", col.GetQuadrantID(col.GetAnim(i045), Vector3(0, -5, 0), 0.0)); ok = false

	# GetIdleMovementAnimID указывает на idle-движение
	var idle_id: int = col.GetIdleMovementAnimID()
	if idle_id < 0 or col.GetAnim(idle_id).GetAnimType() != "movement" \
		or col.GetAnim(idle_id).GetIncomingVelocity() >= 1.8 or col.GetAnim(idle_id).GetOutgoingVelocity() >= 1.8:
		print("CHECK FAIL: GetIdleMovementAnimID → ", idle_id); ok = false

	skel.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

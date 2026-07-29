extends SceneTree
# Метаданные клипа: касания мяча (extension,football) и XML-хвост.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var AnimScript := load("res://src/gpf/Animation.cs")

	# ballcontrol/idle/000.anim: 38 кадров, 1 касание @12 (0, -0.57, 0.11), type ballcontrol.
	var bc = AnimScript.new()
	bc.LoadFromFile("res://assets/gpf/animations/ballcontrol/idle/000.anim")
	if bc.GetFrameCount() != 38:
		print("CHECK FAIL: frameCount 000 → ", bc.GetFrameCount()); ok = false
	if bc.GetTouchCount() != 1:
		print("CHECK FAIL: touchCount → ", bc.GetTouchCount()); ok = false
	elif bc.GetTouchFrame(0) != 12 or not vec_eq(bc.GetTouchPosition(0), Vector3(0.0, -0.57, 0.11)):
		print("CHECK FAIL: touch[0] → ", bc.GetTouchFrame(0), " ", bc.GetTouchPosition(0)); ok = false
	if bc.GetAnimType() != "ballcontrol":
		print("CHECK FAIL: type 000 → '", bc.GetAnimType(), "'"); ok = false
	if bc.GetVariable("baseanim") != "true":
		print("CHECK FAIL: baseanim → '", bc.GetVariable("baseanim"), "'"); ok = false
	if bc.GetVariable("nosuchtag") != "":
		print("CHECK FAIL: несуществующий тег должен давать ''"); ok = false

	# Сброс метаданных при повторной загрузке: тот же экземпляр bc (сейчас — 000.anim,
	# 1 касание, type ballcontrol) переиспользуется под другой файл без касаний.
	bc.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	if bc.GetTouchCount() != 0:
		print("CHECK FAIL: touchCount не сброшен при повторной загрузке → ", bc.GetTouchCount()); ok = false
	if bc.GetAnimType() != "movement":
		print("CHECK FAIL: type не обновился при повторной загрузке → '", bc.GetAnimType(), "'"); ok = false

	# movement/walk/045.anim: касаний нет, type movement.
	var mv = AnimScript.new()
	mv.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	if mv.GetTouchCount() != 0:
		print("CHECK FAIL: у walk/045 не должно быть касаний"); ok = false
	if mv.GetAnimType() != "movement":
		print("CHECK FAIL: type 045 → '", mv.GetAnimType(), "'"); ok = false

	# Многокасание + сортировка по кадру: extension-строка с касаниями в обратном
	# файловом порядке (20 раньше 5) должна отдаваться отсортированной по кадру.
	var multi_path := "user://gpf_multi_touch_test.anim"
	var multi_f := FileAccess.open(multi_path, FileAccess.WRITE)
	if multi_f == null:
		print("CHECK FAIL: user:// недоступен"); quit(1); return
	multi_f.store_line("player,0,0,0,0")
	multi_f.store_line("extension,football,20,1.0,2.0,0.11,5,0.0,-0.5,0.11")
	multi_f.store_line("<type>test</type>")
	multi_f.close()
	var multi = AnimScript.new()
	if not multi.LoadFromFile(multi_path):
		print("CHECK FAIL: многокасательный клип должен грузиться"); ok = false
	if multi.GetTouchCount() != 2:
		print("CHECK FAIL: touchCount многокасания → ", multi.GetTouchCount()); ok = false
	elif multi.GetTouchFrame(0) != 5 or not vec_eq(multi.GetTouchPosition(0), Vector3(0.0, -0.5, 0.11)):
		print("CHECK FAIL: touch[0] многокасания (сортировка) → ", multi.GetTouchFrame(0), " ", multi.GetTouchPosition(0)); ok = false
	elif multi.GetTouchFrame(1) != 20:
		print("CHECK FAIL: touch[1].frame многокасания → ", multi.GetTouchFrame(1)); ok = false
	if multi.GetAnimType() != "test":
		print("CHECK FAIL: type многокасания → '", multi.GetAnimType(), "'"); ok = false
	DirAccess.remove_absolute(multi_path)

	# pass/dribble/180_turn.anim: реальное многосложное значение тега + выход за границы.
	var mt = AnimScript.new()
	mt.LoadFromFile("res://assets/gpf/animations/pass/dribble/180_turn.anim")
	if mt.GetVariable("balldirection") != "0.000000,1.000000,0.000000":
		print("CHECK FAIL: balldirection 180_turn → '", mt.GetVariable("balldirection"), "'"); ok = false
	if mt.GetTouchFrame(99) != -1:
		print("CHECK FAIL: GetTouchFrame за границей должен давать -1 → ", mt.GetTouchFrame(99)); ok = false
	if not vec_eq(mt.GetTouchPosition(99), Vector3.ZERO):
		print("CHECK FAIL: GetTouchPosition за границей должен давать ZERO → ", mt.GetTouchPosition(99)); ok = false

	# Негатив: битый XML-хвост (незакрытый тег) — false, а не всплывшее исключение.
	var bad_path := "user://gpf_bad_xml_test.anim"
	var bad_f := FileAccess.open(bad_path, FileAccess.WRITE)
	if bad_f == null:
		print("CHECK FAIL: user:// недоступен"); quit(1); return
	bad_f.store_line("player,0,0.000000,0.000000,-0.120000")
	bad_f.store_line("body,0,0.031410,0.000000,0.000000,0.999507")
	bad_f.store_line("<type>")
	bad_f.close()
	var bad = AnimScript.new()
	if bad.LoadFromFile(bad_path):
		print("CHECK FAIL: битый XML-хвост должен давать false"); ok = false
	DirAccess.remove_absolute(bad_path)

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

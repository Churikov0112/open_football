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

	# movement/walk/045.anim: касаний нет, type movement.
	var mv = AnimScript.new()
	mv.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	if mv.GetTouchCount() != 0:
		print("CHECK FAIL: у walk/045 не должно быть касаний"); ok = false
	if mv.GetAnimType() != "movement":
		print("CHECK FAIL: type 045 → '", mv.GetAnimType(), "'"); ok = false

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

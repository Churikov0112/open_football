extends SceneTree
# Парсер CSV-части .anim: треки, порядок, ключи, frameCount.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func quat_eq(a: Quaternion, b: Quaternion, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps \
		and absf(a.z - b.z) < eps and absf(a.w - b.w) < eps

func _initialize() -> void:
	var ok := true

	var AnimScript := load("res://src/gpf/Animation.cs")
	if AnimScript == null:
		print("CHECK FAIL: src/gpf/Animation.cs не найден — сначала dotnet build")
		quit(1)
		return
	var anim = AnimScript.new()

	if not anim.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim"):
		print("CHECK FAIL: LoadFromFile 045.anim"); ok = false

	# 25 кадров (максимальный ключ 24), 14 треков в порядке файла.
	if anim.GetFrameCount() != 25:
		print("CHECK FAIL: frameCount 045 → ", anim.GetFrameCount()); ok = false
	if anim.GetTrackCount() != 14:
		print("CHECK FAIL: trackCount → ", anim.GetTrackCount()); ok = false
	var expected_order := ["player", "body", "middle", "neck",
		"left_shoulder", "left_elbow", "right_shoulder", "right_elbow",
		"left_thigh", "left_knee", "left_ankle",
		"right_thigh", "right_knee", "right_ankle"]
	for i in range(mini(14, anim.GetTrackCount())):
		if anim.GetTrackName(i) != expected_order[i]:
			print("CHECK FAIL: track[", i, "] → ", anim.GetTrackName(i)); ok = false

	# Разреженные ключи left_ankle: 0,3,6,12,24 (строка 11 файла).
	var la_frames: Array = anim.GetKeyFrames("left_ankle")
	if la_frames != [0, 3, 6, 12, 24]:
		print("CHECK FAIL: left_ankle keyframes → ", la_frames); ok = false

	# Точные значения из файла.
	if not quat_eq(anim.GetKeyRotation("body", 24),
			Quaternion(0.010774, -0.147878, -0.372312, 0.916187)):
		print("CHECK FAIL: body@24 → ", anim.GetKeyRotation("body", 24)); ok = false
	if not vec_eq(anim.GetKeyPosition("player", 24), Vector3(-0.64, -0.84, -0.08)):
		print("CHECK FAIL: player@24 → ", anim.GetKeyPosition("player", 24)); ok = false
	if not vec_eq(anim.GetKeyPosition("player", 0), Vector3(0.0, 0.0, -0.09)):
		print("CHECK FAIL: player@0 → ", anim.GetKeyPosition("player", 0)); ok = false

	# Сброс состояния: повторный LoadFromFile на ТОМ ЖЕ экземпляре не должен домешивать
	# треки/кадры/ключи предыдущего клипа. 000.anim (37 — макс. ключ → frameCount 38) больше
	# 045.anim (24 → 25), так что несброшенный frameCount тоже поймался бы здесь.
	if not anim.LoadFromFile("res://assets/gpf/animations/ballcontrol/idle/000.anim"):
		print("CHECK FAIL: LoadFromFile 000.anim (повторно на том же экземпляре)"); ok = false
	if anim.GetTrackCount() != 14:
		print("CHECK FAIL: trackCount после повторного LoadFromFile → ", anim.GetTrackCount()); ok = false
	if anim.GetFrameCount() != 38:
		print("CHECK FAIL: frameCount 000 → ", anim.GetFrameCount()); ok = false
	var la_frames_2: Array = anim.GetKeyFrames("left_ankle")
	if la_frames_2 != [0, 12, 26, 33, 37]:
		print("CHECK FAIL: left_ankle keyframes после повторного LoadFromFile → ", la_frames_2); ok = false

	# Смоук по всему корпусу .anim (без .anim.util): каждый файл грузится, кадры есть,
	# ровно 14 треков — на всём корпусе (293 файла, включая templates/) эмпирически
	# подтверждено, исключений нет.
	var corpus_files := _find_anim_files("res://assets/gpf/animations")
	var corpus_checked := 0
	for path in corpus_files:
		var a = AnimScript.new()
		if not a.LoadFromFile(path):
			print("CHECK FAIL: LoadFromFile корпус → ", path); ok = false
			continue
		if a.GetFrameCount() <= 0:
			print("CHECK FAIL: frameCount <= 0 → ", path); ok = false
		if a.GetTrackCount() != 14:
			print("CHECK FAIL: trackCount != 14 → ", path, " (", a.GetTrackCount(), ")"); ok = false
		corpus_checked += 1
	print("INFO: корпус .anim проверен: ", corpus_checked, " файлов")

	# Негатив: несуществующий путь.
	var missing = AnimScript.new()
	if missing.LoadFromFile("res://assets/gpf/animations/__does_not_exist__.anim"):
		print("CHECK FAIL: LoadFromFile на несуществующем пути вернул true"); ok = false

	# Негатив: битый файл (мусорная строка без нужных токенов).
	var bad_path := "user://gpf_bad_test.anim"
	var bad_f := FileAccess.open(bad_path, FileAccess.WRITE)
	if bad_f == null:
		print("CHECK FAIL: user:// недоступен"); quit(1); return
	bad_f.store_line("body,abc,1,2")
	bad_f.close()
	var bad = AnimScript.new()
	if bad.LoadFromFile(bad_path):
		print("CHECK FAIL: LoadFromFile на битом файле вернул true"); ok = false
	DirAccess.remove_absolute(bad_path)

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

func _find_anim_files(dir_path: String) -> Array:
	var result: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path := dir_path.path_join(entry)
		if dir.current_is_dir():
			result.append_array(_find_anim_files(full_path))
		elif entry.ends_with(".anim"):
			result.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return result

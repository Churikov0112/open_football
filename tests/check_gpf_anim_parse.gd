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

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

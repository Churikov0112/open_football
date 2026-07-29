extends SceneTree
# Write-API клипа: Clone (глубина), SetKeyFrame (рост frameCount), Shift (±1, синхрон касаний),
# SetVariable/SetName, CurrentFoot.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var AnimScript := load("res://src/gpf/Animation.cs")

	var src = AnimScript.new()
	src.LoadFromFile("res://assets/gpf/animations/ballcontrol/idle/000.anim")
	var src_frames: int = src.GetFrameCount()
	var src_touch_frame: int = src.GetTouchFrame(0)
	var src_touch_pos: Vector3 = src.GetTouchPosition(0)

	# Clone: та же форма...
	var copy = src.Clone()
	if copy.GetFrameCount() != src_frames or copy.GetTrackCount() != src.GetTrackCount():
		print("CHECK FAIL: Clone форма"); ok = false
	if copy.GetTouchCount() != src.GetTouchCount() or copy.GetTouchFrame(0) != src_touch_frame:
		print("CHECK FAIL: Clone касания"); ok = false
	if copy.GetAnimType() != src.GetAnimType() or copy.GetName() != src.GetName():
		print("CHECK FAIL: Clone переменные/имя"); ok = false
	if copy.GetCurrentFootId() != src.GetCurrentFootId():
		print("CHECK FAIL: Clone нога"); ok = false

	# ...но глубокая: правка копии не трогает оригинал
	copy.SetKeyFrame("player", 200, Quaternion.IDENTITY, Vector3(9, 9, 9))
	copy.SetVariable("type", "hacked")
	if src.GetFrameCount() != src_frames:
		print("CHECK FAIL: Clone мелкий — frameCount оригинала изменился"); ok = false
	if src.GetAnimType() == "hacked":
		print("CHECK FAIL: Clone мелкий — variables общие"); ok = false
	if copy.GetFrameCount() != 201:
		print("CHECK FAIL: SetKeyFrame не растит frameCount (animation.cpp:123) → ", copy.GetFrameCount()); ok = false

	# SetKeyFrame поверх существующего ключа — замена, не дубликат
	var probe = AnimScript.new()
	probe.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	probe.SetKeyFrame("player", 0, Quaternion.IDENTITY, Vector3(1, 2, -0.09))
	var p0: Vector3 = probe.GetKeyPosition("player", 0)
	if not vec_eq(p0, Vector3(1, 2, -0.09)):
		print("CHECK FAIL: SetKeyFrame замена → ", p0); ok = false
	var frames_before: Array = probe.GetKeyFrames("player")

	# Shift +1 от кадра 12: ключи >= 12 сдвинуты, frameCount+1, ключ 0 на месте
	var sh = src.Clone()
	var t_before: int = sh.GetTouchFrame(0)
	sh.Shift(1, 1)
	if sh.GetFrameCount() != src_frames + 1:
		print("CHECK FAIL: Shift +1 frameCount → ", sh.GetFrameCount()); ok = false
	if sh.GetTouchFrame(0) != t_before + 1:
		print("CHECK FAIL: Shift не сдвинул касание (шов 2) → ", sh.GetTouchFrame(0)); ok = false
	if not vec_eq(sh.GetTouchPosition(0), src_touch_pos):
		print("CHECK FAIL: Shift изменил позицию касания"); ok = false
	# Shift -1 обратно: возврат к исходной форме
	sh.Shift(1, -1)
	if sh.GetFrameCount() != src_frames or sh.GetTouchFrame(0) != t_before:
		print("CHECK FAIL: Shift -1 не вернул форму"); ok = false

	# SetVariable/SetName/нога
	var a = AnimScript.new()
	a.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	a.SetVariable("priority", "1")
	if a.GetVariable("priority") != "1":
		print("CHECK FAIL: SetVariable новый тег"); ok = false
	a.SetName("autogen test")
	if a.GetName() != "autogen test":
		print("CHECK FAIL: SetName"); ok = false
	if a.GetCurrentFootId() != 1:
		print("CHECK FAIL: дефолтная нога должна быть right=1 (animation.cpp:29)"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

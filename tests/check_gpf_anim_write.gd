extends SceneTree
# Write-API клипа: Clone (глубина), SetKeyFrame (рост frameCount), Shift (±1, синхрон касаний),
# SetVariable/SetName, CurrentFoot.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func arr_eq(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if int(a[i]) != int(b[i]):
			return false
	return true

# Ожидаемая форма списка ключей после Shift — считается из исходного массива по правилам
# animation.cpp:723-787, независимо от реализации C#.
func shifted(keys: Array, from_frame: int, offset: int) -> Array:
	var out: Array = []
	for k in keys:
		var f: int = int(k)
		if offset == 1:
			if f >= from_frame:
				f += 1
			out.append(f)
		else:
			if f == from_frame:
				continue # ключ ровно на fromFrame выбрасывается (animation.cpp:764)
			if f > from_frame:
				f -= 1
			out.append(f)
	return out

func _initialize() -> void:
	var ok := true
	var AnimScript := load("res://src/gpf/Animation.cs")

	var src = AnimScript.new()
	src.LoadFromFile("res://assets/gpf/animations/ballcontrol/idle/000.anim")
	var src_frames: int = src.GetFrameCount()
	var src_touch_frame: int = src.GetTouchFrame(0)
	var src_touch_pos: Vector3 = src.GetTouchPosition(0)
	var src_player_keys: Array = src.GetKeyFrames("player")
	var src_middle_keys: Array = src.GetKeyFrames("middle")

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
	if not arr_eq(copy.GetKeyFrames("player"), src_player_keys):
		print("CHECK FAIL: Clone ключи трека → ", copy.GetKeyFrames("player")); ok = false

	# ...но глубокая: правка копии не трогает оригинал
	copy.SetKeyFrame("player", 200, Quaternion.IDENTITY, Vector3(9, 9, 9))
	copy.SetVariable("type", "hacked")
	if src.GetFrameCount() != src_frames:
		print("CHECK FAIL: Clone мелкий — frameCount оригинала изменился"); ok = false
	if src.GetAnimType() == "hacked":
		print("CHECK FAIL: Clone мелкий — variables общие"); ok = false
	# глубина ПО ТРЕКАМ: новый ключ копии не должен просочиться в оригинал
	if src.GetKeyFrames("player").has(200) or not arr_eq(src.GetKeyFrames("player"), src_player_keys):
		print("CHECK FAIL: Clone мелкий — треки общие (ключ 200 виден в src) → ", src.GetKeyFrames("player")); ok = false
	if copy.GetFrameCount() != 201:
		print("CHECK FAIL: SetKeyFrame не растит frameCount (animation.cpp:123) → ", copy.GetFrameCount()); ok = false

	# SetKeyFrame поверх существующего ключа — замена, не дубликат
	var probe = AnimScript.new()
	probe.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	var frames_before: Array = probe.GetKeyFrames("player")
	probe.SetKeyFrame("player", 0, Quaternion.IDENTITY, Vector3(1, 2, -0.09))
	var p0: Vector3 = probe.GetKeyPosition("player", 0)
	if not vec_eq(p0, Vector3(1, 2, -0.09)):
		print("CHECK FAIL: SetKeyFrame замена → ", p0); ok = false
	if not arr_eq(probe.GetKeyFrames("player"), frames_before):
		print("CHECK FAIL: SetKeyFrame создал дубликат ключа → ", probe.GetKeyFrames("player")); ok = false

	# Shift +1 от кадра 1: ключи >= 1 сдвинуты, frameCount+1, ключ 0 на месте
	var sh = src.Clone()
	var t_before: int = sh.GetTouchFrame(0)
	sh.Shift(1, 1)
	if sh.GetFrameCount() != src_frames + 1:
		print("CHECK FAIL: Shift +1 frameCount → ", sh.GetFrameCount()); ok = false
	if not arr_eq(sh.GetKeyFrames("player"), shifted(src_player_keys, 1, 1)):
		print("CHECK FAIL: Shift +1 ключи player → ", sh.GetKeyFrames("player"), " ждали ", shifted(src_player_keys, 1, 1)); ok = false
	if not arr_eq(sh.GetKeyFrames("middle"), shifted(src_middle_keys, 1, 1)):
		print("CHECK FAIL: Shift +1 ключи middle → ", sh.GetKeyFrames("middle"), " ждали ", shifted(src_middle_keys, 1, 1)); ok = false
	if sh.GetTouchFrame(0) != t_before + 1:
		print("CHECK FAIL: Shift не сдвинул касание (шов 2) → ", sh.GetTouchFrame(0)); ok = false
	if not vec_eq(sh.GetTouchPosition(0), src_touch_pos):
		print("CHECK FAIL: Shift изменил позицию касания"); ok = false
	# Shift -1 обратно: возврат к исходной форме
	sh.Shift(1, -1)
	if sh.GetFrameCount() != src_frames or sh.GetTouchFrame(0) != t_before:
		print("CHECK FAIL: Shift -1 не вернул форму"); ok = false
	if not arr_eq(sh.GetKeyFrames("player"), src_player_keys):
		print("CHECK FAIL: Shift -1 не вернул ключи player → ", sh.GetKeyFrames("player")); ok = false
	if not arr_eq(sh.GetKeyFrames("middle"), src_middle_keys):
		print("CHECK FAIL: Shift -1 не вернул ключи middle → ", sh.GetKeyFrames("middle")); ok = false

	# Граница «>=» против «>»: у 000.anim нет ключа на кадре 1, поэтому Shift(1, ...) выше
	# эти две реализации НЕ различает. Сдвигаем от кадра, на котором ключ есть (12 — он же
	# кадр касания): при ошибочном «>» ключ 12 и касание 12 остались бы на месте.
	var edge = src.Clone()
	var pivot: int = src_touch_frame # 12
	edge.Shift(pivot, 1)
	if not arr_eq(edge.GetKeyFrames("player"), shifted(src_player_keys, pivot, 1)):
		print("CHECK FAIL: Shift +1 от кадра с ключом (>= vs >) → ", edge.GetKeyFrames("player"), " ждали ", shifted(src_player_keys, pivot, 1)); ok = false
	if edge.GetTouchFrame(0) != pivot + 1:
		print("CHECK FAIL: касание на fromFrame не сдвинулось (>= vs >) → ", edge.GetTouchFrame(0)); ok = false
	edge.Shift(pivot, -1)
	if not arr_eq(edge.GetKeyFrames("player"), src_player_keys) or edge.GetTouchFrame(0) != pivot:
		print("CHECK FAIL: Shift -1 от кадра с ключом не вернул форму → ", edge.GetKeyFrames("player")); ok = false

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

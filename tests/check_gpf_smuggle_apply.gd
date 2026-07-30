extends SceneTree
# Фаза 4, задача 5: накопление смагглов (humanoid.cpp:668-742) + apply-буфер наследника (:765-780).
# Ожидания — перевычисление косинусного ease в тесте.
# ОТКЛОНЕНИЕ от текста плана: Tick зовётся ПОЛНЫМ списком из 5 аргументов
# (dir, velo, wantBall, useDesiredLookAt, desiredLookAt) — мост GDScript↔C# не переносит
# C#-дефолт-аргументы (конвенция репо), а тач-тест лукэт не использует (false, ZERO).

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

# сумма кос-ease приращений по формуле :682-691 за кадры 0..n
func cos_ease_sum(total: Vector3, denom: int, frames: int) -> Vector3:
	var acc := Vector3.ZERO
	for f in frames:
		var value: float = cos((float(f) / float(denom) - 0.5) * PI * 2.0) + 1.0
		value = value * 0.1 + 0.9
		acc += (total / float(denom)) * value
	return acc

func _initialize() -> void:
	var ok := true
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var B = load("res://src/gpf/Ball.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)
	var sel = load("res://src/gpf/AnimSelector.cs").new()
	sel.Setup(c)
	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -0.6, 0))
	h.SetBall(ball)

	# ---------- 1. Разбежаться и догнать мяч: тач-клип выбирается, смаггл накапливается ----------
	var got_touch := false
	var touch_frame := -1
	var smuggle_at_selection := Vector3.ZERO
	for i in 600:
		h.Tick(Vector3(0, -1, 0), 3.5, true, false, Vector3.ZERO)  # want_ball = true
		if not got_touch and h.GetCurrentTouchFrame() >= 0:
			got_touch = true
			touch_frame = h.GetCurrentTouchFrame()
			smuggle_at_selection = h.GetActionSmuggle()
		if got_touch:
			break
	if not got_touch:
		print("CHECK FAIL: тач-клип не выбран за 600 тиков"); ok = false
	else:
		# ---------- 2. Накопление == кос-ease формула (:682-691) ----------
		# прогоняем до кадра касания, offset должен сойтись к сумме приращений
		var frames_run := 0
		while h.GetCurrentTouchFrame() >= 0 and h.GetCurrentFrameNum() < touch_frame \
				and frames_run < 100:
			h.Tick(Vector3(0, -1, 0), 3.5, true, false, Vector3.ZERO)
			frames_run += 1
		if h.GetCurrentTouchFrame() == touch_frame:
			var expected: Vector3 = cos_ease_sum(smuggle_at_selection, touch_frame + 1,
				h.GetCurrentFrameNum() + 1)
			var got_off: Vector3 = h.GetActionSmuggleOffset()
			# ease в сумме к touchFrame даёт ~полный смаггл; сверяем длину траектории
			if (got_off - expected).length() > 0.02 + expected.length() * 0.1:
				print("CHECK FAIL: накопление смаггла ", got_off, " != ", expected); ok = false
			# смаггл вошёл в позицию apply-буфера (:769)
			if got_off.length() > 0.005:
				var apply_pos: Vector3 = h.GetApplyPosition()
				var no_smuggle: Vector3 = h.GetApplyPositionNoSmuggle()
				if (apply_pos - no_smuggle).length() < 0.001:
					print("CHECK FAIL: смаггл не в apply-буфере"); ok = false

	# ---------- 3. smoothFactor по типам (:277-284) ----------
	# после выбора тач-клипа (ballcontrol) фактор должен быть 0.8, после movement→movement — 0.0
	if got_touch and not feq(h.GetSmoothFactor(), 0.8):
		print("CHECK FAIL: smoothFactor тач-клипа = ", h.GetSmoothFactor()); ok = false

	# ---------- 4. movement-смаггл без мяча нулевой, с мячом у ног — может быть ненулевым ----------
	var h2 = HB.new()
	h2.Setup(c, sel)
	h2.ResetSituation(Vector3(20, 20, 0), 0.0)  # мяч далеко
	var ball2 = B.new()
	ball2.ResetSituation(Vector3(0, 0, 0))
	h2.SetBall(ball2)
	for i in 50:
		h2.Tick(Vector3(0, -1, 0), 3.5, false, false, Vector3.ZERO)
	if h2.GetMovementSmuggle().length() > 1.0e-6:
		print("CHECK FAIL: movement-смаггл ненулевой при далёком мяче (гейты :2330-2332)"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

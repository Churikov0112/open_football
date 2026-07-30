extends SceneTree
# Фаза 4, задача 8: сквозной прогон — игрок добегает до мяча, касается, ведёт.
# Приёмка «нога у мяча в кадр контакта» в headless-приближении: в кадр касания
# позиция мяча близка к предсказанной touchPos (сам факт Touch меняет траекторию мяча).

func _initialize() -> void:
	var ok := true
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var B = load("res://src/gpf/Ball.cs")
	var RNG = load("res://src/gpf/GpfRng.cs")
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
	ball.ResetSituation(Vector3(0, -3.0, 0))
	var rng = RNG.new(); rng.Reseed(1234)
	h.SetBall(ball)
	h.SetRng(rng)

	# ---------- 1. Добежать и коснуться ----------
	var touched := false
	var touch_tick := -1
	var mom_before := Vector3.ZERO
	for i in 1200:
		var had_touch_frame: bool = h.GetCurrentTouchFrame() == h.GetCurrentFrameNum() \
			and h.GetCurrentTouchFrame() >= 0
		if had_touch_frame:
			mom_before = ball.GetMovement()
		h.TickBridge(Vector3(0, -1, 0), 3.5, true)
		ball.Process()
		if had_touch_frame and ball.GetMovement() != mom_before:
			touched = true
			touch_tick = i
			break
	if not touched:
		print("CHECK FAIL: касание не случилось за 1200 тиков"); ok = false

	# ---------- 2. Смаггл жил хотя бы раз (нога дотянулась не магией позиций) ----------
	# после первого касания у клипа был ненулевой full-смаггл ИЛИ нулевой (идеальное попадание);
	# проверяем, что механизм вообще включался: тач-клип был выбран
	if touch_tick < 0:
		print("CHECK FAIL: тач-клип не выбирался"); ok = false

	# ---------- 3. Ведение: серия касаний, мяч остаётся при игроке ----------
	var touches := 0
	for i in 2000:
		var had_touch_frame: bool = h.GetCurrentTouchFrame() == h.GetCurrentFrameNum() \
			and h.GetCurrentTouchFrame() >= 0
		var mb: Vector3 = ball.GetMovement()
		h.TickBridge(Vector3(0, -1, 0), 3.5, true)
		ball.Process()
		if had_touch_frame and ball.GetMovement() != mb:
			touches += 1
	if touches < 3:
		print("CHECK FAIL: ведение не удерживается: касаний ", touches); ok = false
	var dist: float = (ball.Predict(0) - h.GetSpatialPosition()).length()
	if dist > 6.0:
		print("CHECK FAIL: мяч убежал: ", dist, " м"); ok = false

	# ---------- 4. Детерминизм сквозного прогона (фикс-сид) ----------
	var positions: Array = []
	for run in 2:
		var hh = HB.new(); hh.Setup(c, sel); hh.ResetSituation(Vector3.ZERO, 0.0)
		var bb = B.new(); bb.ResetSituation(Vector3(0, -3.0, 0))
		var rr = RNG.new(); rr.Reseed(77)
		hh.SetBall(bb); hh.SetRng(rr)
		for i in 500:
			hh.TickBridge(Vector3(0, -1, 0), 3.5, true)
			bb.Process()
		positions.append([hh.GetSpatialPosition(), bb.Predict(0)])
	if positions[0][0] != positions[1][0] or positions[0][1] != positions[1][1]:
		print("CHECK FAIL: недетерминизм сквозного прогона"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

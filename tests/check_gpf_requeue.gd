extends SceneTree
# Фаза 4, задача 6: ReQueue (humanoid.cpp:140-212, :1192-1234). Поведенческие инварианты.
# Числа-пороги тест НЕ проверяет напрямую (они внутри ядра) — проверяются следствия:
# перевыбор раньше границы клипа, отсутствие ReQueue на неизменной команде, детерминизм.

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

	# ---------- 1. Резкая смена команды посреди клипа → перевыбор раньше границы ----------
	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -1.0, 0))  # мяч рядом — маска частоты активна
	h.SetBall(ball)
	# разогнаться прямо
	for i in 100:
		h.TickBridge(Vector3(0, -1, 0), 5.0, false)
	# резко назад: без ReQueue реакция ждёт границы клипа; с ReQueue — быстрее
	var id_before: int = h.GetCurrentAnimId()
	var frames_to_change := -1
	for i in 40:
		h.TickBridge(Vector3(0, 1, 0), 5.0, false)
		if h.GetCurrentAnimId() != id_before:
			frames_to_change = i
			break
	if frames_to_change < 0:
		print("CHECK FAIL: смена команды не перевыбрала клип за 40 тиков"); ok = false
	if h.GetReQueueCount() == 0:
		# допустимо, если смена пришлась ровно на границу — повторить с другим сдвигом
		var requeued := false
		for attempt in 3:
			for i in 7:
				h.TickBridge(Vector3(0, 1, 0), 5.0, false)
			for i in 40:
				h.TickBridge(Vector3(attempt - 1, -1, 0).normalized(), 5.0, false)
				if h.GetReQueueCount() > 0:
					requeued = true
					break
			if requeued: break
		if not requeued:
			print("CHECK FAIL: ReQueue ни разу не сработал"); ok = false

	# ---------- 2. Похожая команда НЕ перевыбирает (:1206-1209) ----------
	var h2 = HB.new()
	h2.Setup(c, sel)
	h2.ResetSituation(Vector3.ZERO, 0.0)
	var ball2 = B.new()
	ball2.ResetSituation(Vector3(0, -30, 0))  # мяч далеко — движение с ballDistance > 16 не requeue-ится
	h2.SetBall(ball2)
	for i in 30:
		h2.TickBridge(Vector3(0, -1, 0), 5.0, false)
	var rq_before: int = h2.GetReQueueCount()
	for i in 100:
		h2.TickBridge(Vector3(0, -1, 0), 5.0, false)  # та же команда
	if h2.GetReQueueCount() != rq_before:
		print("CHECK FAIL: ReQueue на неизменной команде (", h2.GetReQueueCount(), ")"); ok = false

	# ---------- 3. Детерминизм контура с ReQueue ----------
	var run_ids: Array = []
	for run in 2:
		var hh = HB.new()
		hh.Setup(c, sel)
		hh.ResetSituation(Vector3.ZERO, 0.0)
		var bb = B.new()
		bb.ResetSituation(Vector3(0, -1.0, 0))
		hh.SetBall(bb)
		var ids: Array = []
		for i in 150:
			hh.TickBridge(Vector3(0, -1, 0) if i < 75 else Vector3(1, 0, 0), 5.0, false)
			ids.append(hh.GetCurrentAnimId())
		run_ids.append(ids)
	if run_ids[0] != run_ids[1]:
		print("CHECK FAIL: недетерминизм контура с ReQueue"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

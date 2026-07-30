extends SceneTree
# Фаза 4, задача 4: GetBestCheatableAnimID (humanoid.cpp:1999-2323) +
# GetBodyBallDistanceAdvantage (:1859-1997) + GetFrontOfFootOffsetRel (humanoid_utils.cpp:103-115).
# Ожидания — формулы C++, перевычисленные здесь, и точные тождества выходов.
# Отклонение от брифа плана: GetTouchPosition порта принимает ИНДЕКС касания (порядковый номер),
# а не кадр — сценарий 2 ищет индекс по кадру циклом (в брифе кадр передавался как индекс).

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return (a - b).length() < eps

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

	# --- GetFrontOfFootOffsetRel: перевычисление humanoid_utils.cpp:103-115 ---
	var velo := 5.0
	var body_angle := 0.2
	var height := 0.11
	var distance: float = 0.34 + velo * 80.0 * 0.001 * 1.0
	var ffo_exp: Vector3 = Vector3(0, -distance * 0.8, 0)
	var angled: Vector3 = Vector3(0, -distance * 0.2, 0).rotated(Vector3(0, 0, 1), body_angle)
	ffo_exp = (ffo_exp + angled) * (1.0 - clampf((height - 0.11) / 4.0, 0.0, 0.5))
	var ffo_got: Vector3 = HB.GetFrontOfFootOffsetRelBridge(velo, body_angle, height)
	if not vec_eq(ffo_got, ffo_exp):
		print("CHECK FAIL: GetFrontOfFootOffsetRel ", ffo_got, " != ", ffo_exp); ok = false
	# ниже idleDribbleSwitch угол тела игнорируется (:111)
	var ffo_idle: Vector3 = HB.GetFrontOfFootOffsetRelBridge(1.0, 0.5, 0.11)
	var d_idle: float = 0.34 + 1.0 * 0.08
	if not vec_eq(ffo_idle, Vector3(0, -d_idle * 0.8, 0) + Vector3(0, -d_idle * 0.2, 0)):
		print("CHECK FAIL: GetFrontOfFootOffsetRel idle-угол не занулён"); ok = false

	# --- сцена: игрок в нуле, мяч чуть впереди на земле ---
	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -0.6, 0))  # «их-вперёд» = -Y
	h.SetBall(ball)

	# ---------- 1. Мяч у ног → ballcontrol находится ----------
	var r: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)  # 2 == BallControl (gamedefines.hpp:96)
	if int(r["id"]) < 0:
		print("CHECK FAIL: мяч у ног, ballcontrol не найден"); ok = false
	else:
		var tf: int = int(r["touch_frame"])
		var anim = c.GetAnim(int(r["id"]))
		if tf < 0 or tf >= anim.GetFrameCount():
			print("CHECK FAIL: touch_frame вне клипа: ", tf); ok = false
		# точное тождество :2238 — touchPos == предсказание мяча на кадр касания
		var expected_tp: Vector3 = ball.Predict(tf * 10)
		if not vec_eq(Vector3(r["touch_pos"]), expected_tp, 1.0e-5):
			print("CHECK FAIL: touch_pos != Predict(tf*10): ",
				r["touch_pos"], " != ", expected_tp); ok = false
		# assert :2317 — у action-смаггла нет Z
		if not feq(Vector3(r["action_smuggle"]).z, 0.0, 1.0e-6):
			print("CHECK FAIL: action_smuggle.z != 0"); ok = false
		if not feq(Vector3(r["full_smuggle"]).z, 0.0, 1.0e-6):
			print("CHECK FAIL: full_smuggle.z != 0"); ok = false

	# ---------- 2. Высокий мяч → ground-ballcontrol отвергнут (гейт 0.22, :2149) ----------
	ball.SetPosition(Vector3(0, -0.6, 1.6))
	ball.SetMomentum(Vector3.ZERO)
	var r_high: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)
	if int(r_high["id"]) >= 0:
		var got = c.GetAnim(int(r_high["id"]))
		# если нашёлся — допустимо только касание на высоте (клип с тачем выше гейта);
		# GetTouchPosition — по ИНДЕКСУ, ищем индекс касания с кадром touch_frame
		var tf_high: int = int(r_high["touch_frame"])
		var tp := Vector3.ZERO
		var found_touch := false
		for i in got.GetTouchCount():
			if got.GetTouchFrame(i) == tf_high:
				tp = got.GetTouchPosition(i)
				found_touch = true
				break
		if not found_touch:
			print("CHECK FAIL: высокий мяч: touch_frame ", tf_high,
				" не найден среди касаний клипа ", got.GetName()); ok = false
		elif tp.z < 0.8:
			print("CHECK FAIL: высокий мяч взят низким тачем: клип ", got.GetName(),
				" тач-высота ", tp.z); ok = false

	# ---------- 3. Мяч далеко → radius deny (:1970) ----------
	ball.SetPosition(Vector3(0, -5.0, 0.11))
	ball.SetMomentum(Vector3.ZERO)
	var r_far: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)
	if int(r_far["id"]) >= 0:
		print("CHECK FAIL: мяч в 5 м «дотянут»: ", c.GetAnim(int(r_far["id"])).GetName()); ok = false

	# ---------- 4. Ретейнер-сам: обход advantage (:2217), нулевой смаггл (:2280) ----------
	ball.SetPosition(Vector3(0, -0.6, 0.11))
	ball.SetMomentum(Vector3.ZERO)
	h.SetBallRetainerSelf(true)
	var r_ret: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)
	if int(r_ret["id"]) < 0:
		print("CHECK FAIL: ретейнер не нашёл клип"); ok = false
	elif Vector3(r_ret["action_smuggle"]).length() > 1.0e-6:
		print("CHECK FAIL: ретейнер: action_smuggle != 0"); ok = false
	# порядок тач-перебора (:2065-2073): первым пробуется средний тач первого клипа списка
	if int(r_ret["id"]) >= 0:
		var first_anim = c.GetAnim(int(r_ret["id"]))
		var n_touches: int = first_anim.GetTouchCount()
		@warning_ignore("integer_division")
		var mid_frame: int = first_anim.GetTouchFrame(n_touches / 2)
		if int(r_ret["touch_frame"]) != mid_frame:
			print("CHECK FAIL: ретейнер: не средний тач (", r_ret["touch_frame"],
				" != ", mid_frame, ")"); ok = false
	h.SetBallRetainerSelf(false)

	# ---------- 5. Детерминизм ----------
	var ra: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)
	var rb: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)
	if int(ra["id"]) != int(rb["id"]) or ra["touch_frame"] != rb["touch_frame"] \
			or Vector3(ra["action_smuggle"]) != Vector3(rb["action_smuggle"]):
		print("CHECK FAIL: недетерминизм"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

extends SceneTree
# Интерполяция: точный ключ, lerp позиции корня, slerp между ключами, края.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

# Кватернион с точностью до знака (q и -q — один поворот).
func quat_close(a: Quaternion, b: Quaternion, eps := 1.0e-4) -> bool:
	var d1 := absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) + absf(a.w - b.w)
	var d2 := absf(a.x + b.x) + absf(a.y + b.y) + absf(a.z + b.z) + absf(a.w + b.w)
	return minf(d1, d2) < eps

func _initialize() -> void:
	var ok := true
	var anim = load("res://src/gpf/Animation.cs").new()
	anim.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")

	# Семпл на точном ключе с offset 0 == значение ключа.
	if not quat_close(anim.SampleRotation("body", 12, 0.0),
			Quaternion(0.060027, -0.163966, -0.174606, 0.969033)):
		print("CHECK FAIL: SampleRotation body@12 → ", anim.SampleRotation("body", 12, 0.0)); ok = false

	# Позиция корня: кадр 6 между ключами 0 и 12 → линейная интерполяция.
	if not vec_eq(anim.SampleRootPosition(6, 0.0), Vector3(-0.15, -0.2308695, -0.07)):
		print("CHECK FAIL: root@6 → ", anim.SampleRootPosition(6, 0.0)); ok = false

	# Slerp между ключами: left_elbow, ключи 12 и 19, кадр 15 → bias 3/7.
	var q12 := Quaternion(-0.791526, 0.0, 0.0, 0.611136)
	var q19 := Quaternion(-0.567869, 0.0, 0.0, 0.823119)
	var expected := q12.slerp(q19, 3.0 / 7.0)
	if not quat_close(anim.SampleRotation("left_elbow", 15, 0.0), expected, 5.0e-4):
		print("CHECK FAIL: left_elbow@15 → ", anim.SampleRotation("left_elbow", 15, 0.0)); ok = false

	# Субкадровый сдвиг: bias 0.5 между семплом кадра 12 (== ключ 12) и кадра 13
	# (== slerp(ключ12, 1/7, ключ19)), затем lerp+normalize. Значение посчитано вручную.
	# (тип указан явно: вывод типа `:=` из Variant-результата C#-метода — parse error в GDScript)
	var mid: Quaternion = anim.SampleRotation("left_elbow", 12, 5.0)
	if not quat_close(mid, Quaternion(-0.7778, 0.0, 0.0, 0.6285), 1.0e-3):
		print("CHECK FAIL: субкадровый семпл left_elbow@12+5ms → ", mid); ok = false

	# Сентинел timeOffset_ms == -1 (animation.cpp:391-392): bias 0.5, как и при 5 мс.
	var sentinel: Quaternion = anim.SampleRotation("left_elbow", 12, -1.0)
	if not quat_close(sentinel, mid, 1.0e-6):
		print("CHECK FAIL: сентинел -1 != offset 5мс → ", sentinel, " vs ", mid); ok = false

	# Края: кадр ≤ 0 → первый ключ (ветка frame <= 0).
	if not quat_close(anim.SampleRotation("left_elbow", -3, 0.0),
			Quaternion(-0.402422, 0.0, 0.000001, 0.915454)):
		print("CHECK FAIL: left_elbow@-3 → ", anim.SampleRotation("left_elbow", -3, 0.0)); ok = false
	if not quat_close(anim.SampleRotation("left_elbow", 0, 0.0),
			Quaternion(-0.402422, 0.0, 0.000001, 0.915454)):
		print("CHECK FAIL: left_elbow@0 → ", anim.SampleRotation("left_elbow", 0, 0.0)); ok = false
	if not quat_close(anim.SampleRotation("left_elbow", 24, 0.0),
			Quaternion(-0.269418, 0.0, 0.0, 0.963023), 1.0e-4):
		print("CHECK FAIL: left_elbow@24 → ", anim.SampleRotation("left_elbow", 24, 0.0)); ok = false

	# За концом клипа (frameCount 25) — экстраполяция slerp(ключ19, 2.2, ключ24),
	# bias 2.2 = 1 + (1/(24-19)) * (30-24). Значение посчитано вручную.
	var extrap: Quaternion = anim.SampleRotation("left_elbow", 30, 0.0)
	if not quat_close(extrap, Quaternion(0.1242, 0.0, 0.0, 0.9923), 1.0e-3):
		print("CHECK FAIL: экстраполяция left_elbow@30 → ", extrap); ok = false

	# Трек кончился раньше frameCount: right_ankle в 000_header_jump.anim держит
	# последний ключ (кадр 60) вплоть до конца клипа (frameCount 67).
	var anim2 = load("res://src/gpf/Animation.cs").new()
	anim2.LoadFromFile("res://assets/gpf/animations/interfere/sprint/000_header_jump.anim")
	if not quat_close(anim2.SampleRotation("right_ankle", 63, 0.0),
			Quaternion(-0.242470, 0.0, 0.0, 0.970159), 1.0e-4):
		print("CHECK FAIL: right_ankle@63 (хвост трека) → ",
			anim2.SampleRotation("right_ankle", 63, 0.0)); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

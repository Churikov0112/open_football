extends SceneTree

func _initialize() -> void:
	var ok := true

	# select_target: партнёр строго по aim_dir побеждает партнёра сбоку.
	var mates_pos := PackedVector3Array([Vector3(10, 0, 0), Vector3(0, 0, 10)])
	var mates_vel := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var idx := PassSystem.select_target(Vector3.ZERO, Vector3(1, 0, 0), mates_pos, mates_vel, 0.0, 0.0, 45.0)
	if idx != 0:
		print("CHECK FAIL: select_target aligned → ", idx); ok = false
	# пустой список → -1
	if PassSystem.select_target(Vector3.ZERO, Vector3(1, 0, 0), PackedVector3Array(), PackedVector3Array(), 0.0, 0.0, 45.0) != -1:
		print("CHECK FAIL: select_target empty"); ok = false
	# все дальше max_range → -1
	var far := PackedVector3Array([Vector3(100, 0, 0)])
	if PassSystem.select_target(Vector3.ZERO, Vector3(1, 0, 0), far, PackedVector3Array([Vector3.ZERO]), 0.0, 0.0, 45.0) != -1:
		print("CHECK FAIL: select_target out of range"); ok = false

	# lead_point: движущуюся цель ведём по её скорости на время полёта мяча.
	var lp := PassSystem.lead_point(Vector3(10, 0, 0), Vector3(0, 0, 5), Vector3.ZERO, 15.0, 0.0)
	if not lp.is_equal_approx(Vector3(10, 0, 10.0 / 15.0 * 5.0)):
		print("CHECK FAIL: lead_point moving → ", lp); ok = false
	# стоящая цель → точка == позиции цели
	if not PassSystem.lead_point(Vector3(8, 0, 0), Vector3.ZERO, Vector3.ZERO, 12.0, 3.0).is_equal_approx(Vector3(8, 0, 0)):
		print("CHECK FAIL: lead_point static"); ok = false

	# launch_ground: плоский вектор к цели длиной power.
	var lg := PassSystem.launch_ground(Vector3.ZERO, Vector3(3, 0, 4), 10.0)
	if not is_equal_approx(lg.length(), 10.0) or not is_zero_approx(lg.y):
		print("CHECK FAIL: launch_ground magnitude/flat → ", lg); ok = false
	if not is_equal_approx(lg.normalized().dot(Vector3(3, 0, 4).normalized()), 1.0):
		print("CHECK FAIL: launch_ground direction"); ok = false

	# launch_lob: ре-симуляция дуги приземляет мяч ≈ в to, пик ≈ peak_height.
	var g := 20.0
	var v0 := PassSystem.launch_lob(Vector3.ZERO, Vector3(12, 0, 0), 3.0, g)
	var p := Vector3.ZERO
	var v := v0
	var dt := 1.0 / 240.0
	var peak := 0.0
	for _i in range(4000):
		v.y -= g * dt
		p += v * dt
		peak = maxf(peak, p.y)
		if p.y <= 0.0 and v.y < 0.0:
			break
	if absf(p.x - 12.0) > 0.3 or absf(p.z) > 0.3:
		print("CHECK FAIL: launch_lob landing → ", p); ok = false
	if absf(peak - 3.0) > 0.2:
		print("CHECK FAIL: launch_lob peak → ", peak); ok = false

	# interception_time: соперник на линии паса и близко → конечное время.
	var t_hit := PassSystem.interception_time(Vector3.ZERO, Vector3(20, 0, 0), 15.0, Vector3(10, 0, 0.2), 6.0, 1.2, 0.06)
	if is_inf(t_hit) or t_hit <= 0.0:
		print("CHECK FAIL: interception on-line finite → ", t_hit); ok = false
	# соперник далеко вбок → INF (вне коридора).
	if not is_inf(PassSystem.interception_time(Vector3.ZERO, Vector3(20, 0, 0), 15.0, Vector3(10, 0, 8.0), 6.0, 1.2, 0.06)):
		print("CHECK FAIL: interception off-corridor INF"); ok = false
	# соперник позади точки паса → INF.
	if not is_inf(PassSystem.interception_time(Vector3.ZERO, Vector3(20, 0, 0), 15.0, Vector3(-5, 0, 0), 6.0, 1.2, 0.06)):
		print("CHECK FAIL: interception behind INF"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

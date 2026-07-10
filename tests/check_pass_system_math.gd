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

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

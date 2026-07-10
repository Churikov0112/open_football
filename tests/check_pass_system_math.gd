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

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

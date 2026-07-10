extends SceneTree

func _initialize() -> void:
	var ok := true
	# idle при нуле
	if not is_equal_approx(PlayerVisual.speed_to_blend(0.0), 0.0):
		print("CHECK FAIL: speed 0 → ", PlayerVisual.speed_to_blend(0.0))
		ok = false
	# полный бег на/выше порога
	if not is_equal_approx(PlayerVisual.speed_to_blend(5.0), 1.0):
		print("CHECK FAIL: speed 5 → ", PlayerVisual.speed_to_blend(5.0))
		ok = false
	if not is_equal_approx(PlayerVisual.speed_to_blend(9.0), 1.0):
		print("CHECK FAIL: speed 9 (клампинг) → ", PlayerVisual.speed_to_blend(9.0))
		ok = false
	# середина
	if not is_equal_approx(PlayerVisual.speed_to_blend(2.5), 0.5):
		print("CHECK FAIL: speed 2.5 → ", PlayerVisual.speed_to_blend(2.5))
		ok = false
	# анти-слайд: scale = (speed/top)*fudge, с нижним клампом 0.1
	if not is_equal_approx(PlayerVisual.run_timescale(8.0, 8.0, 1.33), 1.33):
		print("CHECK FAIL: run_timescale full → ", PlayerVisual.run_timescale(8.0, 8.0, 1.33)); ok = false
	if not is_equal_approx(PlayerVisual.run_timescale(4.0, 8.0, 1.33), 0.665):
		print("CHECK FAIL: run_timescale half → ", PlayerVisual.run_timescale(4.0, 8.0, 1.33)); ok = false
	if not is_equal_approx(PlayerVisual.run_timescale(0.0, 8.0, 1.33), 0.1):
		print("CHECK FAIL: run_timescale clamp → ", PlayerVisual.run_timescale(0.0, 8.0, 1.33)); ok = false
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

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
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

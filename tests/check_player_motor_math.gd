extends SceneTree

func _initialize() -> void:
	var ok := true

	# desired_velocity: нормализует и масштабирует
	var dv := PlayerMotor.desired_velocity(Vector3(1, 0, 0), 8.0, 1.5)
	if not dv.is_equal_approx(Vector3(12, 0, 0)):
		print("CHECK FAIL: desired_velocity sprint → ", dv); ok = false
	if not PlayerMotor.desired_velocity(Vector3.ZERO, 8.0, 1.0).is_equal_approx(Vector3.ZERO):
		print("CHECK FAIL: desired_velocity zero"); ok = false

	# integrate_velocity: разгон из покоя темпом accel
	var acc := PlayerMotor.integrate_velocity(Vector3.ZERO, Vector3(8, 0, 0), 25.0, 20.0, 0.1)
	if not is_equal_approx(acc.length(), 2.5):
		print("CHECK FAIL: accel step → ", acc.length()); ok = false
	# торможение к нулю темпом decel
	var dec := PlayerMotor.integrate_velocity(Vector3(8, 0, 0), Vector3.ZERO, 25.0, 20.0, 0.1)
	if not is_equal_approx(dec.length(), 6.0):
		print("CHECK FAIL: decel step → ", dec.length()); ok = false

	# smooth_yaw: при turn_rot*delta ≥ 1 доходит до цели.
	# ПРИМЕЧАНИЕ: на ровно противофазном угле (0 → PI) lerp_angle детерминированно
	# выбирает направление -PI (то же самое значение по модулю 2π) — сравниваем по модулю.
	if not is_equal_approx(absf(PlayerMotor.smooth_yaw(0.0, PI, 18.0, 0.1)), PI):
		print("CHECK FAIL: smooth_yaw full"); ok = false

	# lean_deg: линейно, клампится
	if not is_equal_approx(PlayerMotor.lean_deg(1.0, 1.0, 20.0), 20.0):
		print("CHECK FAIL: lean_deg max"); ok = false
	if not is_equal_approx(PlayerMotor.lean_deg(0.5, 0.5, 20.0), 5.0):
		print("CHECK FAIL: lean_deg mid"); ok = false
	if not is_equal_approx(PlayerMotor.lean_deg(2.0, 3.0, 20.0), 20.0):
		print("CHECK FAIL: lean_deg clamp"); ok = false

	# smooth_scalar: движется к цели, не скачет мгновенно; при rate*delta≥1 доходит до цели
	var s := PlayerMotor.smooth_scalar(0.0, 20.0, 8.0, 0.1)
	if not is_equal_approx(s, 16.0):
		print("CHECK FAIL: smooth_scalar step → ", s); ok = false
	if not is_equal_approx(PlayerMotor.smooth_scalar(0.0, 20.0, 8.0, 1.0), 20.0):
		print("CHECK FAIL: smooth_scalar full"); ok = false

	# gravity_step: в воздухе копит вниз; на земле обнуляется (не накапливает бесконечно).
	if not is_equal_approx(PlayerMotor.gravity_step(0.0, false, 20.0, 0.1), -2.0):
		print("CHECK FAIL: gravity_step air → ", PlayerMotor.gravity_step(0.0, false, 20.0, 0.1)); ok = false
	if not is_equal_approx(PlayerMotor.gravity_step(-5.0, true, 20.0, 0.1), 0.0):
		print("CHECK FAIL: gravity_step grounded → ", PlayerMotor.gravity_step(-5.0, true, 20.0, 0.1)); ok = false

	# face_yaw: смотрит на -Z → yaw 0; на +X → yaw -PI/2 (та же формула, что доворот по скорости).
	if not is_equal_approx(PlayerMotor.face_yaw(Vector3.ZERO, Vector3(0, 0, -1)), 0.0):
		print("CHECK FAIL: face_yaw -Z → ", PlayerMotor.face_yaw(Vector3.ZERO, Vector3(0, 0, -1))); ok = false
	if not is_equal_approx(PlayerMotor.face_yaw(Vector3.ZERO, Vector3(1, 0, 0)), -PI / 2.0):
		print("CHECK FAIL: face_yaw +X → ", PlayerMotor.face_yaw(Vector3.ZERO, Vector3(1, 0, 0))); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

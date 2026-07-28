extends SceneTree
## KeeperPlayLogic: кламп штрафной, автонаведение руки, векторы выносов.

func _initialize() -> void:
	var ok := true
	# --- clamp_to_penalty_area: точка вне бокса → на границу; внутри → без изменений ---
	# Ворота на -52.5, в поле into=+1, глубина 16.5, полуширина 20.16.
	var inside := KeeperPlayLogic.clamp_to_penalty_area(Vector3(5, 0.5, -50.0), -52.5, 1.0, 16.5, 20.16)
	if not inside.is_equal_approx(Vector3(5, 0.5, -50.0)):
		print("CHECK FAIL: внутренняя точка сдвинута: ", inside); ok = false
	var deep := KeeperPlayLogic.clamp_to_penalty_area(Vector3(0, 0.5, -20.0), -52.5, 1.0, 16.5, 20.16)
	# rel = (-20 - -52.5)*1 = 32.5 > 16.5 → z = -52.5 + 16.5 = -36.0
	if absf(deep.z - (-36.0)) > 0.01:
		print("CHECK FAIL: глубина не заклампилась: ", deep); ok = false
	var wide := KeeperPlayLogic.clamp_to_penalty_area(Vector3(30, 0.5, -50.0), -52.5, 1.0, 16.5, 20.16)
	if absf(wide.x - 20.16) > 0.01:
		print("CHECK FAIL: ширина не заклампилась: ", wide); ok = false

	# --- select_hand_target: низкий заряд → ближний, высокий → дальний ---
	var mates := [Vector3(3, 0.5, -50), Vector3(20, 0.5, -50)]   # ближний [0], дальний [1]
	var aim := Vector3(1, 0, 0)
	var near_pick := KeeperPlayLogic.select_hand_target(Vector3(0, 0.5, -50), aim, mates, 0.0, 5.0, 25.0)
	if near_pick != 0:
		print("CHECK FAIL: низкий заряд не выбрал ближнего: ", near_pick); ok = false
	var far_pick := KeeperPlayLogic.select_hand_target(Vector3(0, 0.5, -50), aim, mates, 1.0, 5.0, 25.0)
	if far_pick != 1:
		print("CHECK FAIL: высокий заряд не выбрал дальнего: ", far_pick); ok = false

	# --- clear_center_vector: горизонталь по into, +лифт ---
	var cc := KeeperPlayLogic.clear_center_vector(1.0, 20.0, 5.0)
	if absf(cc.z - 20.0) > 0.01 or absf(cc.y - 5.0) > 0.01 or absf(cc.x) > 0.01:
		print("CHECK FAIL: clear_center_vector: ", cc); ok = false

	# --- directed_clear_vector: по aim, скорость по заряду, +лифт ---
	var dc := KeeperPlayLogic.directed_clear_vector(Vector3(1, 0, 0), 1.0, 8.0, 24.0, 4.0)
	if absf(dc.x - 24.0) > 0.01 or absf(dc.y - 4.0) > 0.01:
		print("CHECK FAIL: directed_clear_vector: ", dc); ok = false

	if ok:
		print("CHECK PASS: KeeperPlayLogic (clamp/select/clear/directed)")
		quit(0)
	else:
		quit(1)

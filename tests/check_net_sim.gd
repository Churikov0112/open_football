extends SceneTree

const NetSim = preload("res://scripts/match/net_sim.gd")

var _ok := true

func _init() -> void:
	_test_topology()
	_test_integrate()
	if _ok:
		print("CHECK PASS")
		quit(0)
	else:
		print("CHECK FAIL")
		quit(1)

func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: ", msg)
	else:
		_ok = false
		print("  FAIL: ", msg)

func _test_topology() -> void:
	var net: Dictionary = NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	# узлы: back (5*4=20) + top (5*3=15) + left (3*4=12) + right (3*4=12) = 59
	_expect(net["pos"].size() == 59, "node count == 59 (got %d)" % net["pos"].size())
	_expect(net["rest"].size() == 59, "rest parallel to pos")
	_expect(net["prev"].size() == 59, "prev parallel to pos")
	_expect(net["normal"].size() == 59, "normal parallel to pos")
	_expect(net["pinned"].size() == 59, "pinned parallel to pos")
	# свободные (интерьерные) узлы: sum (u_div-1)*(v_div-1) = back 3*2 + top 3*1 + left 1*2 + right 1*2 = 13
	var free: int = 0
	for v in net["pinned"]:
		if v == 0:
			free += 1
	_expect(free == 13, "free interior nodes == 13 (got %d)" % free)
	# rest_len совпадает с реальной длиной ребра
	var e: int = net["edges"].size() / 2
	_expect(e == net["rest_len"].size(), "one rest_len per edge")
	var bad: int = 0
	for k in range(e):
		var a: int = net["edges"][k * 2]
		var b: int = net["edges"][k * 2 + 1]
		if absf(net["pos"][a].distance_to(net["pos"][b]) - net["rest_len"][k]) > 0.0001:
			bad += 1
	_expect(bad == 0, "rest_len == actual edge length")

	# Slack: rest-длина рёбер = фактический шаг сетки × slack (запас материала).
	var nets := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2, 0.8)
	var sa: int = nets["edges"][0]
	var sb: int = nets["edges"][1]
	var span: float = nets["pos"][sa].distance_to(nets["pos"][sb])
	_expect(absf(nets["rest_len"][0] - span * 0.8) < 0.0001,
		"slack 0.8 shortens rest_len to 0.8x node spacing")
	# Контроль: без slack (по умолчанию) rest_len == фактическому шагу.
	var nett := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	var ta: int = nett["edges"][0]
	var tb: int = nett["edges"][1]
	_expect(absf(nett["rest_len"][0] - nett["pos"][ta].distance_to(nett["pos"][tb])) < 0.0001,
		"default slack 1.0 leaves rest_len == node spacing")

func _first_free(net: Dictionary) -> int:
	for i in range(net["pinned"].size()):
		if net["pinned"][i] == 0:
			return i
	return -1

func _max_edge_stretch(net: Dictionary) -> float:
	var ed: PackedInt32Array = net["edges"]
	var rl: PackedFloat32Array = net["rest_len"]
	var m := 0.0
	for k in range(ed.size() / 2):
		var cur: float = net["pos"][ed[k * 2]].distance_to(net["pos"][ed[k * 2 + 1]])
		var st: float = absf(cur - rl[k]) / rl[k]
		if st > m:
			m = st
	return m

func _test_integrate() -> void:
	# Гравитация: свободный узел проседает ниже rest; закреплённые не двигаются.
	var net := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	var free := _first_free(net)
	_expect(free >= 0, "has a free node")
	var rest_y: float = net["rest"][free].y
	# Запомним позицию любого закреплённого узла.
	var pin_idx := 0
	var pin_before: Vector3 = net["pos"][pin_idx]
	_expect(net["pinned"][pin_idx] == 1, "node 0 is pinned (panel corner)")
	var gp := {
		"gravity": 50.0, "damping": 0.9, "stiffness": 0.0, "shape_return": 0.0,
		"ball_radius": 1.0, "ball_vel_scale": 0.0, "ball_force": 0.0,
		"ball_min_speed": 0.0, "constraint_iterations": 0, "constraint_stiffness": 1.0,
	}
	for _s in range(30):
		NetSim.integrate(net, Vector3(0, -1000, 0), 0.0, gp, 0.1)
	_expect(net["pos"][free].y < rest_y - 0.01, "free node sags under gravity")
	_expect(net["pos"][pin_idx].distance_to(pin_before) < 0.0001, "pinned node did not move")

	# Толчок мяча: узел у мяча смещается наружу вдоль нормали (+z для задней панели).
	var net2 := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	var f2 := _first_free(net2)
	var rest_z: float = net2["rest"][f2].z
	# Мяч чуть «внутри» узла (со стороны поля), в радиусе влияния.
	var ball_local: Vector3 = net2["rest"][f2] - Vector3(0, 0, 0.1)
	var bp := {
		"gravity": 0.0, "damping": 0.9, "stiffness": 0.0, "shape_return": 0.0,
		"ball_radius": 1.0, "ball_vel_scale": 0.5, "ball_force": 100.0,
		"ball_min_speed": 0.0, "constraint_iterations": 0, "constraint_stiffness": 1.0,
	}
	for _s2 in range(5):
		NetSim.integrate(net2, ball_local, 5.0, bp, 0.1)
	_expect(net2["pos"][f2].z > rest_z + 0.001, "ball pushes near node outward (+z)")

	# Мяч в покое (ball_speed=0) НЕ толкает сетку: узел остаётся у rest.
	var net3 := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	var f3 := _first_free(net3)
	var rest3: Vector3 = net3["rest"][f3]
	var ball_at: Vector3 = rest3 - Vector3(0, 0, 0.05)  # мяч вплотную, но неподвижен
	var sp := {
		"gravity": 0.0, "damping": 0.9, "stiffness": 0.0, "shape_return": 20.0,
		"ball_radius": 1.0, "ball_vel_scale": 0.5, "ball_force": 100.0,
		"ball_min_speed": 1.5, "constraint_iterations": 0, "constraint_stiffness": 1.0,
	}
	for _s3 in range(20):
		NetSim.integrate(net3, ball_at, 0.0, sp, 0.1)
	_expect(net3["pos"][f3].distance_to(rest3) < 0.001, "resting ball does not push net")

	# Нерастяжимость: под нагрузкой (гравитация) рёбра держат rest-длину — ткань, не резина.
	var net4 := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	var cp := {
		"gravity": 30.0, "damping": 0.9, "stiffness": 0.0, "shape_return": 0.0,
		"ball_radius": 0.001, "ball_vel_scale": 0.0, "ball_force": 0.0,
		"ball_min_speed": 0.0, "constraint_iterations": 5, "constraint_stiffness": 1.0,
	}
	for _s4 in range(60):
		NetSim.integrate(net4, Vector3(0, -100, 0), 0.0, cp, 0.03)
	var edges4: PackedInt32Array = net4["edges"]
	var rl4: PackedFloat32Array = net4["rest_len"]
	var max_stretch := 0.0
	for ek in range(edges4.size() / 2):
		var cur: float = net4["pos"][edges4[ek * 2]].distance_to(net4["pos"][edges4[ek * 2 + 1]])
		var st: float = absf(cur - rl4[ek]) / rl4[ek]
		if st > max_stretch:
			max_stretch = st
	_expect(max_stretch < 0.06, "edges stay near rest length under load (max stretch %.3f)" % max_stretch)

	# constraint_stiffness регулирует свободу: мягкие связи дают заметно больше провиса/растяжения.
	var base_p := {
		"gravity": 30.0, "damping": 0.9, "stiffness": 0.0, "shape_return": 0.0,
		"ball_radius": 0.001, "ball_vel_scale": 0.0, "ball_force": 0.0,
		"ball_min_speed": 0.0, "constraint_iterations": 2,
	}
	var net_stiff := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	var net_soft := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	var p_stiff := base_p.duplicate()
	p_stiff["constraint_stiffness"] = 1.0
	var p_soft := base_p.duplicate()
	p_soft["constraint_stiffness"] = 0.15
	for _sc in range(60):
		NetSim.integrate(net_stiff, Vector3(0, -100, 0), 0.0, p_stiff, 0.03)
		NetSim.integrate(net_soft, Vector3(0, -100, 0), 0.0, p_soft, 0.03)
	_expect(_max_edge_stretch(net_soft) > _max_edge_stretch(net_stiff),
		"softer constraint_stiffness gives more edge freedom")

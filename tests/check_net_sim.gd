extends SceneTree

const NetSim = preload("res://scripts/match/net_sim.gd")

var _ok := true

func _init() -> void:
	_test_topology()
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

extends SceneTree
## Вратарь НЕ кандидат авто-аима паса (ActionExecutor._team_arrays исключает role_gk): пас «на
## вратаря» не отдаёт ему управление в полёте — он остаётся ИИ, сам бежит на мяч, принимает в
## ноги, и лишь тогда авто-свап делает его controlled.
var _mm; var _f := 0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f < 5:
		return
	var ax = _mm.get(&"_action_executor")
	var keeper = _mm._team_home.keeper()
	var field = null
	for n in _mm.get_tree().get_nodes_in_group("team_1"):
		if not n.is_in_group("role_gk"):
			field = n; break
	if ax == null or keeper == null or field == null:
		print("CHECK FAIL: нет executor/keeper/field"); quit(1); return
	var arr: Dictionary = ax._team_arrays(&"team_1", field)
	var nodes: Array = arr["nodes"]
	if keeper in nodes:
		print("CHECK FAIL: вратарь В кандидатах паса team_1"); quit(1); return
	if nodes.is_empty():
		print("CHECK FAIL: кандидаты паса пусты (ожидались полевые)"); quit(1); return
	for n in nodes:
		if n.is_in_group("role_gk"):
			print("CHECK FAIL: role_gk среди кандидатов: ", n); quit(1); return
	print("CHECK PASS: keeper excluded from pass-target candidates"); quit(0); return

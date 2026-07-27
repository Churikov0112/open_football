extends SceneTree
## Диспетч вратарской раздачи: team_1 → Human+KICKER+take_control; team_2 → AI+NONE.
## Хелпер handoff передаёт управление ближайшему полевому team_1.

func _initialize() -> void:
	var mm = load("res://scenes/match.tscn").instantiate()
	root.add_child(mm)
	# Дать сцене осесть один физкадр не обязательно для чистого диспетча — тела уже заспавнены в _ready.
	call_deferred("_run", mm)

func _run(mm) -> void:
	var ok := true
	var k1 = mm._team_home.keeper()   # team_1
	var k2 = mm._team_away.keeper()   # team_2
	if k1 == null or k2 == null:
		print("CHECK FAIL: вратари не заспавнены"); quit(1); return

	var d1: Dictionary = mm._keeper_hands_dispatch(k1)
	if not (d1.intent is HumanKeeperHandsIntent):
		print("CHECK FAIL: team_1 не Human intent: ", d1.intent); ok = false
	if not d1.presentation.owns_hud():
		print("CHECK FAIL: team_1 presentation не владеет HUD"); ok = false
	if not d1.take_control:
		print("CHECK FAIL: team_1 take_control не true"); ok = false

	var d2: Dictionary = mm._keeper_hands_dispatch(k2)
	if not (d2.intent is AIKeeperHandsIntent):
		print("CHECK FAIL: team_2 не AI intent: ", d2.intent); ok = false
	if d2.presentation.owns_hud():
		print("CHECK FAIL: team_2 presentation ошибочно владеет HUD"); ok = false
	if d2.take_control:
		print("CHECK FAIL: team_2 take_control ошибочно true"); ok = false

	# handoff: ставим искусственную точку у одного из team_1 полевых, проверяем захват управления.
	var field1: Array = []
	for n in mm.get_tree().get_nodes_in_group("team_1"):
		if not n.is_in_group("role_gk"):
			field1.append(n)
	if field1.is_empty():
		print("CHECK FAIL: нет полевых team_1"); quit(1); return
	var target = field1[0]
	mm.keeper_handoff_control(target.global_position)
	if mm.controlled_player != target:
		print("CHECK FAIL: handoff не передал управление ближайшему: ", mm.controlled_player); ok = false

	if ok:
		print("CHECK PASS: keeper hands dispatch + handoff")
		quit(0)
	else:
		quit(1)

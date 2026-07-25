extends SceneTree
## Headless: оба вратаря спавнятся у своих ворот; _keeper_at резолвит защищающую команду;
## группа role_gk содержит ровно двоих. (Задача 2 дополнит freeze/reset-проверками.)

var _mm: Node
var _elapsed: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < 0.3:
		return false   # ждём _ready + спавн
	var gks := _mm.get_tree().get_nodes_in_group("role_gk")
	if gks.size() != 2:
		print("CHECK FAIL: role_gk = ", gks.size(), " (ожидалось 2)"); quit(1); return true
	var fl: float = _mm.field_length
	var k_home: Node = _mm._keeper_at(-fl)   # ворота Home (-Z) защищает team_2
	var k_away: Node = _mm._keeper_at(fl)    # ворота Away (+Z) защищает team_1
	if k_home == null or k_away == null:
		print("CHECK FAIL: _keeper_at вернул null (home=", k_home, " away=", k_away, ")"); quit(1); return true
	if not k_home.is_in_group("team_2"):
		print("CHECK FAIL: вратарь у -Z не team_2"); quit(1); return true
	if not k_away.is_in_group("team_1"):
		print("CHECK FAIL: вратарь у +Z не team_1"); quit(1); return true
	if k_home.global_position.z > 0.0 or k_away.global_position.z < 0.0:
		print("CHECK FAIL: вратари не у своих ворот (z_home=", k_home.global_position.z,
			" z_away=", k_away.global_position.z, ")"); quit(1); return true

	# --- Задача 2: заморозка ИИ НЕ трогает вратарей ---
	_mm._set_ai_frozen(true)
	if not _mm._ai_of(k_home).is_physics_processing():
		print("CHECK FAIL: заморозка вырубила team_2-вратаря"); quit(1); return true
	if not _mm._ai_of(k_away).is_physics_processing():
		print("CHECK FAIL: заморозка вырубила team_1-вратаря"); quit(1); return true
	_mm._set_ai_frozen(false)

	# --- Задача 2: _reset_ball НЕ телепортит вратарей (players() включает team_1-вратаря) ---
	var moved := Vector3(5.0, 0.5, 40.0)
	k_away.global_position = moved
	_mm._reset_ball()
	if k_away.global_position.distance_to(moved) > 0.1:
		print("CHECK FAIL: _reset_ball сдвинул team_1-вратаря с ", moved,
			" на ", k_away.global_position); quit(1); return true

	print("CHECK PASS: two keepers + freeze/reset skip role_gk")
	quit(0)
	return true

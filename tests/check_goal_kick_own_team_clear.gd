extends SceneTree
## Headless: удар от ворот выталкивает из вратарской ±5м ВСЕХ полевых, включая свою же команду
## бьющего (не только соперников) — вратарь остаётся единственным, кто может там стоять.

var _mm: Node
var _gk: Node
var _elapsed: float = 0.0
var _mate: CharacterBody3D
var _goal_line_z: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed <= 0.15:
		return false
	_gk = _mm.get_node_or_null("GoalKickController")
	if _gk == null:
		print("CHECK FAIL: нет узла GoalKickController")
		return true
	_goal_line_z = -_mm.field_length
	# Бьющий — team_2-вратарь; его СВОЯ команда (team_2) должна тоже быть вытолкнута, если стоит
	# рядом с вратарской. Ставим соперника-из-своей-команды (team_2 outfielder) прямо у вратаря.
	_mate = _mm._away_outfielder()
	if _mate == null:
		print("CHECK FAIL: нет team_2 полевого игрока для теста")
		return true
	var into: float = -signf(_goal_line_z)
	_mate.global_position = Vector3(0.0, 0.5, _goal_line_z + into * 2.0)   # внутри вратарской
	_gk.start(_mm._keeper_at(-_mm.field_length), _goal_line_z)
	var into2: float = -signf(_goal_line_z)
	var rel: float = (_mate.global_position.z - _goal_line_z) * into2
	if rel < FootballConstants.GOAL_AREA_DEPTH + FootballConstants.GK_CLEAR_MARGIN - 0.01:
		print("CHECK FAIL: свой же (team_2) тиммейт вратаря НЕ вытолкнут из вратарской ±5м, rel=", rel)
		return true
	print("CHECK PASS: goal_kick_own_team_clear (rel=", rel, ")")
	quit(0)
	return true

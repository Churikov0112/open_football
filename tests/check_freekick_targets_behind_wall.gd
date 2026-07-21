extends SceneTree
## Регресс: на близком штрафном атакующие цели должны стоять ЗА стенкой (ближе к воротам), а не
## между мячом и стенкой. Плюс никакое не-стеночное тело не должно остаться в конусе мяч→стенка.

var _mm: Node
var _fk: Node
var _elapsed: float = 0.0
var _stage: int = 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < 0.3:
		return false
	match _stage:
		0:
			_fk = _mm.get_node_or_null("FreeKickController")
			if _fk == null:
				print("CHECK FAIL: нет узла FreeKickController")
				return true
			var gz: float = _mm._keeper_brain.goal_line_z
			# Близкий штрафной: бьющий в 20 м от ворот (стенка ~10.85 м от ворот).
			_mm.controlled_player.global_position = Vector3(2.0, 0.5, gz + (20.0 if gz < 0.0 else -20.0))
			_fk.start(_mm.controlled_player, gz)
			_stage = 1
			return false
		1:
			var gz: float = _fk._goal_line_z
			var spot: Vector3 = _fk._spot
			var wall_dist_from_goal: float = maxf(0.0, absf(spot.z - gz) - FootballConstants.FK_WALL_DIST)
			var ok := true
			# 1) Все цели (is_target) — ЗА стенкой (ближе к воротам).
			for e in _fk._mates:
				if not e["is_target"]:
					continue
				var b = e["body"]
				if not is_instance_valid(b):
					continue
				var d: float = absf(b.global_position.z - gz)
				if d >= wall_dist_from_goal:
					print("  FAIL: цель на %.1f м от ворот, стенка на %.1f — НЕ за стенкой" % [d, wall_dist_from_goal])
					ok = false
			# 2) Ни одно не-стеночное тело не в конусе мяч→стенка.
			var count: int = FreeKickLogic.wall_count(absf(spot.z - gz), FootballConstants.FK_WALL_FAR_DIST,
				FootballConstants.FK_WALL_NEAR_DIST, FootballConstants.FK_WALL_MIN_PLAYERS, FootballConstants.FK_WALL_MAX_PLAYERS)
			if count > 0:
				var nf: Array = FreeKickLogic.near_far_posts(spot, 0.0, FootballConstants.GOAL_WIDTH * 0.5, gz)
				var wl: Dictionary = FreeKickLogic.wall_line(spot, nf[0], gz, FootballConstants.FK_WALL_DIST, 0.5)
				var pos: Array = FreeKickLogic.wall_body_positions(wl["center"], wl["right"], count, FootballConstants.FK_WALL_SPACING)
				var el: Vector3 = pos[0]
				var er: Vector3 = pos[pos.size() - 1]
				for grp in ["team_1", "team_2"]:
					for n in _mm.get_tree().get_nodes_in_group(grp):
						if n == _fk._kicker or n == _mm._keeper or not (n is Node3D) or _fk._is_wall_body(n):
							continue
						var adj: Vector3 = FreeKickLogic.push_out_of_cone(n.global_position, spot, el, er, FootballConstants.FK_CONE_MARGIN_DEG)
						if not adj.is_equal_approx(n.global_position):
							print("  FAIL: тело ", n.name, " (", grp, ") в конусе мяч→стенка")
							ok = false
			if ok:
				print("CHECK PASS: free-kick targets behind wall, cone clear")
				quit(0)
			else:
				print("CHECK FAIL: free-kick gap not clear")
				quit(1)
			return true
	return false

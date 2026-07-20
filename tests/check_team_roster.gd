extends SceneTree
## Ростер Team: регистрация/группы/запросы, headless (тела — голые CharacterBody3D).

func _make_body(nm: String) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	b.name = nm
	return b

func _initialize() -> void:
	var ok := true
	var team := Team.new()
	team.team_group = &"team_1"
	root.add_child(team)

	var gk := _make_body("GK")
	var d1 := _make_body("D1")
	var f1 := _make_body("F1")
	team.add_player(gk, PlayerConfig.Role.GK)
	team.add_player(d1, PlayerConfig.Role.DEF)
	team.add_player(f1, PlayerConfig.Role.FWD)

	# reparent под Team
	if gk.get_parent() != team: ok = false; print("CHECK FAIL: gk not child of team")
	# группы: команда + роль
	if not gk.is_in_group("team_1"): ok = false; print("CHECK FAIL: gk missing team group")
	if not gk.is_in_group("role_gk"): ok = false; print("CHECK FAIL: gk missing role group")
	if not d1.is_in_group("role_def"): ok = false; print("CHECK FAIL: d1 missing role group")
	# упорядоченный players()
	var ps := team.players()
	if ps.size() != 3: ok = false; print("CHECK FAIL: players size ", ps.size())
	if ps[0] != gk or ps[1] != d1 or ps[2] != f1: ok = false; print("CHECK FAIL: players order")
	# by_role / keeper / outfield
	if team.by_role(PlayerConfig.Role.FWD).size() != 1 or team.by_role(PlayerConfig.Role.FWD)[0] != f1:
		ok = false; print("CHECK FAIL: by_role FWD")
	if team.keeper() != gk: ok = false; print("CHECK FAIL: keeper()")
	if team.outfield().size() != 2: ok = false; print("CHECK FAIL: outfield size")
	if team.outfield().has(gk): ok = false; print("CHECK FAIL: keeper in outfield")
	# no dup add
	team.add_player(gk, PlayerConfig.Role.GK)
	if team.players().size() != 3: ok = false; print("CHECK FAIL: dup add grew roster")
	# remove
	team.remove_player(d1)
	if team.players().size() != 2 or team.players().has(d1): ok = false; print("CHECK FAIL: remove_player")
	if d1.is_in_group("team_1"): ok = false; print("CHECK FAIL: remove kept team group")
	# invalid pruned
	f1.free()
	if team.players().size() != 1: ok = false; print("CHECK FAIL: freed body not pruned")

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

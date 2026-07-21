extends SceneTree
## PlayerFactory.spawn: сборка тела через player.tscn, регистрация в Team, слои/группы/роль/
## порядок детей/home_pos. Без ai_script (control_mode AI + ai_script=null → set_script пропущен),
## без manager (connect_action_signals=false) — изоляция от полного матча.
## Spawn + проверки — в _process (не _initialize): SceneTree.root сам ещё не is_inside_tree()
## внутри _initialize(), из-за чего Node3D.global_position ошибается "!is_inside_tree()"
## (тот же паттерн, что в check_free_kick_flow.gd — реальная работа откладывается на кадр).

var _team: Team
var _done: bool = false

func _initialize() -> void:
	_team = Team.new()
	_team.team_group = &"team_2"
	root.add_child(_team)

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	var ok := true
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_2"
	cfg.role = PlayerConfig.Role.FWD
	cfg.kit_color = Color(0.9, 0.1, 0.1)
	cfg.spawn_pos = Vector3(3, 0.5, -7)
	cfg.display_name = "TestFwd"
	cfg.connect_action_signals = false
	cfg.ai_script = null   # AI, но без скрипта → set_script пропускается

	var body := PlayerFactory.spawn(cfg, _team)

	if body == null: ok = false; print("CHECK FAIL: null body")
	if body.name != "TestFwd": ok = false; print("CHECK FAIL: name")
	if body.get_parent() != _team: ok = false; print("CHECK FAIL: not child of team")
	if not body.is_in_group("team_2"): ok = false; print("CHECK FAIL: team group")
	if not body.is_in_group("role_fwd"): ok = false; print("CHECK FAIL: role group")
	if int(body.get_meta(&"role", -1)) != PlayerConfig.Role.FWD: ok = false; print("CHECK FAIL: role meta")
	if body.collision_layer != FootballConstants.PLAYER_COLLISION_MASK: ok = false; print("CHECK FAIL: layer")
	var want_mask := FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
	if body.collision_mask != want_mask: ok = false; print("CHECK FAIL: mask")
	if body.global_position.distance_to(Vector3(3, 0.5, -7)) > 0.001: ok = false; print("CHECK FAIL: position")
	if body.get_meta(&"home_pos", Vector3.INF) != Vector3(3, 0.5, -7): ok = false; print("CHECK FAIL: home_pos meta")
	# порядок детей: PlayerVisual раньше PlayerMotor
	var kids := body.get_children()
	var vi := -1
	var mi := -1
	for i in kids.size():
		if kids[i] is PlayerVisual and vi < 0: vi = i
		if kids[i] is PlayerMotor and mi < 0: mi = i
	if vi < 0: ok = false; print("CHECK FAIL: no PlayerVisual child")
	if mi < 0: ok = false; print("CHECK FAIL: no PlayerMotor child")
	if vi >= 0 and mi >= 0 and not (vi < mi): ok = false; print("CHECK FAIL: visual not before motor")
	# find_visual
	if PlayerFactory.find_visual(body) == null: ok = false; print("CHECK FAIL: find_visual")

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true

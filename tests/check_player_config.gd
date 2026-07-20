extends SceneTree

func _initialize() -> void:
	var ok := true
	var c := PlayerConfig.new()
	# defaults
	if c.team_group != &"team_1": ok = false; print("CHECK FAIL: default team_group")
	if c.role != PlayerConfig.Role.MID: ok = false; print("CHECK FAIL: default role")
	if c.control_mode != PlayerConfig.ControlMode.AI: ok = false; print("CHECK FAIL: default control")
	if not c.connect_action_signals: ok = false; print("CHECK FAIL: default connect_action_signals")
	if c.locomotion_style != -1: ok = false; print("CHECK FAIL: default locomotion_style")
	# role_group mapping
	if PlayerConfig.role_group(PlayerConfig.Role.GK) != &"role_gk": ok = false; print("CHECK FAIL: role_gk")
	if PlayerConfig.role_group(PlayerConfig.Role.DEF) != &"role_def": ok = false; print("CHECK FAIL: role_def")
	if PlayerConfig.role_group(PlayerConfig.Role.MID) != &"role_mid": ok = false; print("CHECK FAIL: role_mid")
	if PlayerConfig.role_group(PlayerConfig.Role.FWD) != &"role_fwd": ok = false; print("CHECK FAIL: role_fwd")
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

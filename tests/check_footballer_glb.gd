extends SceneTree

func _initialize() -> void:
	var ok := true
	var path := "res://assets/models/footballer.glb"
	if not ResourceLoader.exists(path):
		push_error("CHECK FAIL: нет ресурса " + path)
		quit(1)
		return
	var packed: PackedScene = load(path)
	var inst: Node = packed.instantiate()
	var ap := _find_anim_player(inst)
	if ap == null:
		print("CHECK FAIL: AnimationPlayer не найден в glb")
		ok = false
	else:
		var anims := ap.get_animation_list()
		print("CHECK: анимации в glb = ", anims)
		for want in ["idle", "run", "roll_left", "roll_right",
				"keeper_idle", "keeper_sidestep", "keeper_body_block_l", "keeper_body_block_r",
				"keeper_diving_save_l", "keeper_diving_save_r", "keeper_catch", "keeper_catch_top",
				"keeper_catch_head",
				"keeper_idle_ball", "keeper_drop_kick", "keeper_pass", "keeper_placing_ball",
				"keeper_overhand_throw", "keeper_scoop", "keeper_miss_top"]:
			if not ap.has_animation(want):
				print("CHECK FAIL: нет анимации '" + want + "'")
				ok = false
	inst.free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

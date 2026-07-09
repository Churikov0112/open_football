extends SceneTree

# Проверяет, что у клипов из IN_PLACE_CLIPS горизонтальная позиция Hips (X,Z) почти
# не меняется вдоль клипа — т.е. root motion убран (клип in-place).
func _initialize() -> void:
	var ok := true
	var scene: PackedScene = load("res://assets/models/footballer.glb")
	if scene == null:
		print("CHECK FAIL: не загрузился footballer.glb"); quit(1); return
	var root := scene.instantiate()
	var ap := _find_ap(root)
	if ap == null:
		print("CHECK FAIL: нет AnimationPlayer в glb"); quit(1); return

	var eps := 0.05  # метры в единицах модели; дрейф больше — значит root motion остался
	for clip in ["tackle", "roll_left", "roll_right"]:
		if not ap.has_animation(clip):
			print("CHECK FAIL: нет клипа ", clip); ok = false; continue
		var anim := ap.get_animation(clip)
		var ti := _hips_position_track(anim)
		if ti < 0:
			print("CHECK FAIL: нет position-трека Hips в ", clip); ok = false; continue
		var min_x := INF; var max_x := -INF; var min_z := INF; var max_z := -INF
		for k in anim.track_get_key_count(ti):
			var v: Vector3 = anim.track_get_key_value(ti, k)
			min_x = minf(min_x, v.x); max_x = maxf(max_x, v.x)
			min_z = minf(min_z, v.z); max_z = maxf(max_z, v.z)
		var drift_x := max_x - min_x
		var drift_z := max_z - min_z
		if drift_x > eps or drift_z > eps:
			print("CHECK FAIL: ", clip, " дрейф Hips X=", drift_x, " Z=", drift_z); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null

func _hips_position_track(anim: Animation) -> int:
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D \
			and String(anim.track_get_path(t)).to_lower().contains("hips"):
			return t
	return -1

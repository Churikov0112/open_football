extends Node3D

@onready var ball: RigidBody3D = $Ball
@onready var player_home: CharacterBody3D = $PlayerHome
@onready var camera_pivot: Node3D = $CameraPivot
@onready var score_label: Label = $HUD/ScoreLabel

var home_score: int = 0
var away_score: int = 0
var player_away: CharacterBody3D
var player_teammate: CharacterBody3D
var controlled_player: CharacterBody3D
var field_length: float = FootballConstants.HALF_FIELD_LENGTH
var field_width: float = FootballConstants.HALF_FIELD_WIDTH
var controlled_player_indicator: MeshInstance3D


func _ready() -> void:
	_setup_inputs()
	_setup_grass()
	_setup_field_markings()
	_setup_ball()
	_setup_camera()
	_setup_goals()
	_setup_away_player()
	controlled_player = player_home
	_setup_teammate()
	_setup_boundaries()
	_give_ai_to_player_home()
	_setup_controlled_indicator()


func _setup_inputs() -> void:
	# NOTE: project.godot has input actions defined but they may not have
	# events bound correctly (serialization format issue). To guarantee
	# input works, we always erase and recreate all actions here.
	var input_actions := {
		&"move_left": [KEY_A, KEY_LEFT],
		&"move_right": [KEY_D, KEY_RIGHT],
		&"move_forward": [KEY_W, KEY_UP],
		&"move_back": [KEY_S, KEY_DOWN],
		&"kick": [KEY_SPACE],
		&"pass": [KEY_E],
		&"pause": [KEY_ESCAPE],
		&"swap_player": [KEY_Q],
	}
	for action in input_actions:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action)
		for keycode in input_actions[action]:
			var e := InputEventKey.new()
			e.keycode = keycode
			InputMap.action_add_event(action, e)
	print("Inputs setup OK")


func _setup_grass() -> void:
	var pitch_mesh := $Pitch/Mesh as MeshInstance3D
	if not pitch_mesh:
		return
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.0
	mat.roughness = 0.95
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var stripe_width := 16
	var j := 0
	while j < 256:
		var shade := 0.15 if (j / stripe_width) % 2 == 0 else 0.20
		for y in range(j, min(j + stripe_width, 256)):
			for x in range(256):
				img.set_pixel(x, y, Color(shade, shade * 3.0, shade * 0.8))
		j += stripe_width
	var tex := ImageTexture.create_from_image(img)
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(2.0, 1.0, 1.0)
	pitch_mesh.material_override = mat


func _make_line_mesh(size: Vector2, pos: Vector3) -> void:
	var mesh := QuadMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.global_position = pos
	mi.rotation.x = deg_to_rad(-90)
	add_child(mi)


func _make_arc_mesh(radius: float, pos: Vector3, start_angle: float, end_angle: float, segments: int = 16) -> void:
	var immediate := MeshInstance3D.new()
	var arr_mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(segments + 1):
		var t := float(i) / segments
		var a := start_angle + (end_angle - start_angle) * t
		st.add_vertex(Vector3(cos(a) * radius, 0.01, sin(a) * radius))
	arr_mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	immediate.mesh = arr_mesh
	immediate.material_override = mat
	immediate.global_position = pos
	add_child(immediate)


func _make_circle_mesh(radius: float, pos: Vector3, segments: int = 32) -> void:
	var immediate := MeshInstance3D.new()
	var arr_mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(segments + 1):
		var a := i * 2.0 * PI / segments
		st.add_vertex(Vector3(cos(a) * radius, 0.01, sin(a) * radius))
	arr_mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	immediate.mesh = arr_mesh
	immediate.material_override = mat
	immediate.global_position = pos
	add_child(immediate)


func _setup_field_markings() -> void:
	var w := field_width
	var l := field_length
	var pw := FootballConstants.LINE_THICKNESS
	# touchlines (sides) — thin along X (pw), long along Z (l*2)
	_make_line_mesh(Vector2(pw, l * 2), Vector3(-w, 0.01, 0))
	_make_line_mesh(Vector2(pw, l * 2), Vector3(w, 0.01, 0))
	# goal lines (ends) — long along X (w*2), thin along Z (pw)
	_make_line_mesh(Vector2(w * 2, pw), Vector3(0, 0.01, -l))
	_make_line_mesh(Vector2(w * 2, pw), Vector3(0, 0.01, l))
	# halfway line — long along X (w*2), thin along Z (pw)
	_make_line_mesh(Vector2(w * 2, pw), Vector3(0, 0.01, 0))
	# center circle
	_make_circle_mesh(FootballConstants.CENTER_CIRCLE_RADIUS, Vector3(0, 0.01, 0))
	# penalty areas (16.5m from goal line, 40.32m total width)
	var pa_depth := FootballConstants.PENALTY_AREA_DEPTH
	var pa_width := FootballConstants.PENALTY_AREA_WIDTH / 2.0
	# Side lines centered so they span from goal line to front of area,
	# not half behind the goal line (off the field).
	_make_line_mesh(Vector2(pw, pa_depth), Vector3(-pa_width, 0.01, -l + pa_depth / 2.0))
	_make_line_mesh(Vector2(pw, pa_depth), Vector3(pa_width, 0.01, -l + pa_depth / 2.0))
	_make_line_mesh(Vector2(pa_width * 2, pw), Vector3(0, 0.01, -l + pa_depth))
	_make_line_mesh(Vector2(pw, pa_depth), Vector3(-pa_width, 0.01, l - pa_depth / 2.0))
	_make_line_mesh(Vector2(pw, pa_depth), Vector3(pa_width, 0.01, l - pa_depth / 2.0))
	_make_line_mesh(Vector2(pa_width * 2, pw), Vector3(0, 0.01, l - pa_depth))
	# goal areas (5.5m from goal line, 18.32m total width)
	var ga_depth := FootballConstants.GOAL_AREA_DEPTH
	var ga_width := FootballConstants.GOAL_AREA_WIDTH / 2.0
	_make_line_mesh(Vector2(pw, ga_depth), Vector3(-ga_width, 0.01, -l + ga_depth / 2.0))
	_make_line_mesh(Vector2(pw, ga_depth), Vector3(ga_width, 0.01, -l + ga_depth / 2.0))
	_make_line_mesh(Vector2(ga_width * 2, pw), Vector3(0, 0.01, -l + ga_depth))
	_make_line_mesh(Vector2(pw, ga_depth), Vector3(-ga_width, 0.01, l - ga_depth / 2.0))
	_make_line_mesh(Vector2(pw, ga_depth), Vector3(ga_width, 0.01, l - ga_depth / 2.0))
	_make_line_mesh(Vector2(ga_width * 2, pw), Vector3(0, 0.01, l - ga_depth))
	# corner arcs (FIFA: radius 1.0m quarter-circle at each corner)
	const CORNER_ARC_RESOLUTION := 16
	var cr := FootballConstants.CORNER_ARC_RADIUS
	# 4 corners: (X sign, Z sign) → field extends toward opposite signs
	# Arc sweeps from one boundary line to the other within the field quadrant
	# Corners:
	#   Top-left  (-w, -l): field → +X, +Z  arc from 0 to PI/2
	#   Top-right  (w, -l): field → -X, +Z  arc from PI/2 to PI
	#   Bottom-right (w, l): field → -X, -Z  arc from PI to 3*PI/2
	#   Bottom-left (-w, l): field → +X, -Z  arc from 3*PI/2 to 2*PI
	_make_arc_mesh(cr, Vector3(-w, 0.01, -l), 0.0, PI / 2.0, CORNER_ARC_RESOLUTION)
	_make_arc_mesh(cr, Vector3(w, 0.01, -l), PI / 2.0, PI, CORNER_ARC_RESOLUTION)
	_make_arc_mesh(cr, Vector3(w, 0.01, l), PI, 3.0 * PI / 2.0, CORNER_ARC_RESOLUTION)
	_make_arc_mesh(cr, Vector3(-w, 0.01, l), 3.0 * PI / 2.0, 2.0 * PI, CORNER_ARC_RESOLUTION)
	# penalty spot (11m from goal line)
	var ps_dist := FootballConstants.PENALTY_SPOT_DIST
	var ps_radius := 0.15
	_make_circle_mesh(ps_radius, Vector3(0, 0.01, -l + ps_dist), 12)
	_make_circle_mesh(ps_radius, Vector3(0, 0.01, l - ps_dist), 12)
	# penalty arc (the "D") — radius 9.15m from penalty spot, only the arc outside the box
	var pa_radius := FootballConstants.PENALTY_ARC_RADIUS
	var pa_front_z := -l + FootballConstants.PENALTY_AREA_DEPTH
	var pa_half_w := FootballConstants.PENALTY_AREA_WIDTH / 2.0
	var from_spot_to_front := pa_front_z - (-l + ps_dist)
	var half_chord := sqrt(pa_radius * pa_radius - from_spot_to_front * from_spot_to_front)
	var arc_half_angle := atan2(half_chord, from_spot_to_front)
	# Home penalty arc (lower Z)
	_make_arc_mesh(pa_radius, Vector3(0, 0.01, -l + ps_dist),
		PI / 2.0 + arc_half_angle, PI / 2.0 - arc_half_angle, 16)
	# Away penalty arc (higher Z)
	_make_arc_mesh(pa_radius, Vector3(0, 0.01, l - ps_dist),
		-PI / 2.0 + arc_half_angle, -PI / 2.0 - arc_half_angle, 16)
	# center spot
	_make_circle_mesh(FootballConstants.CENTER_SPOT_RADIUS, Vector3(0, 0.01, 0), 12)


func _setup_ball() -> void:
	ball.script = preload("res://scripts/ball/ball_controller.gd")
	ball.set_script(ball.script)
	ball.body_entered.connect(_on_ball_collision)


func _setup_camera() -> void:
	var cam: Camera3D = $CameraPivot/Camera3D
	var cam_script = preload("res://scripts/camera/match_camera.gd")
	cam.set_script(cam_script)
	cam.target = ball


func _setup_goals() -> void:
	var goal_positions := [
		{"pos": Vector3(0, 0, -field_length), "side": "Home"},
		{"pos": Vector3(0, 0, field_length), "side": "Away"}
	]
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(1, 1, 1)
	for g in goal_positions:
		var goal_group := Node3D.new()
		goal_group.name = "Goal" + g.side
		add_child(goal_group)
		goal_group.global_position = g.pos

		var post_left := _make_post(-3.66, 0, 0)
		goal_group.add_child(post_left)
		var post_right := _make_post(3.66, 0, 0)
		goal_group.add_child(post_right)
		var crossbar := _make_crossbar(0, 2.44, 0)
		goal_group.add_child(crossbar)

		var area := Area3D.new()
		area.name = "GoalArea"
		area.add_to_group("goal")
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(7.32, 2.44, 0.5)
		col.shape = shape
		area.add_child(col)
		goal_group.add_child(area)
		area.global_position = g.pos + Vector3(0, 1.22, -0.25 if g.side == "Home" else 0.25)

		area.body_entered.connect(func(body: Node):
			if body == ball:
				if g.side == "Home":
					away_score += 1
				else:
					home_score += 1
				score_label.text = "%d : %d" % [home_score, away_score]
				_reset_ball()
		)


func _make_post(x: float, y: float, z: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.08
	mesh.bottom_radius = 0.08
	mesh.height = 2.44
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mi.material_override = mat
	mi.position = Vector3(x, 1.22, z)
	return mi


func _make_crossbar(x: float, y: float, z: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.08
	mesh.bottom_radius = 0.08
	mesh.height = 7.32
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mi.material_override = mat
	mi.position = Vector3(x, y, z)
	mi.rotation.z = deg_to_rad(90)
	return mi


func _setup_boundaries() -> void:
	var wall_height := 4.0
	var wall_thickness := 0.5
	var wall_extra := 4.0
	var total_half_z := field_length + wall_extra
	var walls := [
		{"pos": Vector3(0, wall_height/2, -total_half_z), "size": Vector3(field_width*2, wall_height, wall_thickness)},
		{"pos": Vector3(0, wall_height/2, total_half_z), "size": Vector3(field_width*2, wall_height, wall_thickness)},
		{"pos": Vector3(-field_width, wall_height/2, 0), "size": Vector3(wall_thickness, wall_height, total_half_z*2)},
		{"pos": Vector3(field_width, wall_height/2, 0), "size": Vector3(wall_thickness, wall_height, total_half_z*2)},
	]
	for w in walls:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = w.size
		col.shape = shape
		body.add_child(col)
		body.global_position = w.pos
		add_child(body)


func _give_ai_to_player_home() -> void:
	var ai_script = preload("res://scripts/ai/teammate_ai.gd")
	player_home.set_script(ai_script)
	player_home.set_physics_process(true)
	player_home.ball = ball
	player_home.controlled_player = controlled_player
	player_home.speed = 7.0
	player_home.teammate_home_goal = $GoalAway/GoalArea if has_node("GoalAway/GoalArea") else null


func _setup_away_player() -> void:
	var new_player := CharacterBody3D.new()
	new_player.name = "PlayerAway"
	new_player.global_position = Vector3(20, 0.5, 0)
	var mesh := CapsuleMesh.new()
	mesh.height = 1.5
	mesh.radius = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.1, 0.1)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	new_player.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.5
	shape.radius = 0.3
	col.shape = shape
	new_player.add_child(col)
	add_child(new_player)
	var ai_script = preload("res://scripts/ai/simple_ai.gd")
	new_player.set_script(ai_script)
	new_player.set_physics_process(true)
	new_player.ball = ball
	new_player.home_goal = $GoalHome/GoalArea if has_node("GoalHome/GoalArea") else null
	player_away = new_player


func _setup_teammate() -> void:
	var new_player := CharacterBody3D.new()
	new_player.name = "PlayerTeammate"
	new_player.global_position = Vector3(10, 0.5, 5)
	var mesh := CapsuleMesh.new()
	mesh.height = 1.5
	mesh.radius = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.9)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	new_player.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.5
	shape.radius = 0.3
	col.shape = shape
	new_player.add_child(col)
	add_child(new_player)
	var teammate_script = preload("res://scripts/ai/teammate_ai.gd")
	new_player.set_script(teammate_script)
	new_player.set_physics_process(true)
	new_player.ball = ball
	new_player.controlled_player = controlled_player
	new_player.teammate_home_goal = $GoalAway/GoalArea if has_node("GoalAway/GoalArea") else null
	player_teammate = new_player


func _process(delta: float) -> void:
	var ball_pos := ball.global_position
	camera_pivot.global_position = camera_pivot.global_position.lerp(
		Vector3(-40, camera_pivot.position.y, ball_pos.z),
		3.0 * delta
	)
	camera_pivot.look_at(Vector3(0, 0, ball_pos.z), Vector3.UP)

	if controlled_player_indicator and controlled_player:
		controlled_player_indicator.global_position = controlled_player.global_position + Vector3(0, 2.2, 0)


func _physics_process(delta: float) -> void:
	_handle_dribbling()
	_handle_player_input(delta)

	# Auto-switch control to whoever on our team has the ball
	if ball.has_method(&"set_dribbler") and ball.dribbler:
		var db: Node3D = ball.dribbler
		if (db == player_home or db == player_teammate) and db != controlled_player:
			controlled_player = db
			_sync_ai_controllers()

	# Swap player (Q) — manual switch between player_home and player_teammate
	if Input.is_action_just_pressed(&"swap_player"):
		controlled_player = player_teammate if controlled_player == player_home else player_home
		_sync_ai_controllers()

	# Set opponent's target_node to whoever on our team is dribbling
	if player_away:
		if ball.has_method(&"set_dribbler") and ball.dribbler:
			var db: Node3D = ball.dribbler
			if db == player_home or db == player_teammate:
				player_away.target_node = db
		else:
			player_away.target_node = null


func _setup_controlled_indicator() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.2
	mesh.height = 0.4

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0, 2.2, 0)
	add_child(mi)
	controlled_player_indicator = mi


func _sync_ai_controllers() -> void:
	if player_home:
		player_home.controlled_player = controlled_player
	if player_teammate:
		player_teammate.controlled_player = controlled_player


func _handle_dribbling() -> void:
	if not ball.has_method(&"release_dribble"):
		return
	if ball.dribbler:
		var dist: float = ball.dribbler.global_position.distance_to(ball.global_position)
		if dist > 3.0:
			ball.release_dribble()
		return
	for p in [player_home, player_teammate, player_away]:
		if not p or not is_instance_valid(p):
			continue
		var dist: float = p.global_position.distance_to(ball.global_position)
		if dist < 1.0:
			ball.set_dribbler(p)
			return


func _handle_player_input(delta: float) -> void:
	if not controlled_player:
		return
	var input_dir := Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_forward", &"move_back")
	)
	var cam_basis := camera_pivot.global_transform.basis
	var cam_forward := -cam_basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()
	var cam_right := cam_basis.x
	cam_right.y = 0
	cam_right = cam_right.normalized()
	var dir := (cam_forward * -input_dir.y + cam_right * input_dir.x).normalized()
	if dir.length() > 0.1:
		var speed := 8.0
		controlled_player.global_position.x = move_toward(controlled_player.global_position.x,
			controlled_player.global_position.x + dir.x * speed * delta, speed * delta)
		controlled_player.global_position.z = move_toward(controlled_player.global_position.z,
			controlled_player.global_position.z + dir.z * speed * delta, speed * delta)
		var target_angle := atan2(-dir.x, -dir.z)
		controlled_player.rotation.y = lerp_angle(controlled_player.rotation.y, target_angle, 10.0 * delta)
	if Input.is_action_just_pressed(&"kick"):
		_kick_ball(controlled_player)
	if Input.is_action_just_pressed(&"pass"):
		_pass_ball(controlled_player)


func _kick_ball(player_node: CharacterBody3D) -> void:
	if not ball.has_method(&"kick"):
		return
	var dist := player_node.global_position.distance_to(ball.global_position)
	if dist > 2.0:
		return
	# Use the ball's dribble direction (movement direction) instead of facing direction.
	var dir: Vector3 = ball.get_dribble_direction()
	dir.y = 0.3
	ball.kick(dir, 12.0)


func _pass_ball(player_node: CharacterBody3D) -> void:
	if not ball.has_method(&"kick"):
		return
	var dist := player_node.global_position.distance_to(ball.global_position)
	if dist > 2.0:
		return
	var dir: Vector3 = ball.get_dribble_direction()
	dir.y = 0.1
	ball.kick(dir, 8.0)


func _on_ball_collision(body: Node) -> void:
	pass


func _reset_ball() -> void:
	if ball.has_method(&"release_dribble"):
		ball.release_dribble()
	if ball.has_method(&"clear_last_kicker"):
		ball.clear_last_kicker()
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = Vector3(0, 0.5, 0)

	# Reset players to their starting positions
	player_home.global_position = Vector3(0, 0.5, 0)
	if player_teammate:
		player_teammate.global_position = Vector3(10, 0.5, 5)
	if player_away:
		player_away.global_position = Vector3(20, 0.5, 0)

	controlled_player = player_home
	_sync_ai_controllers()

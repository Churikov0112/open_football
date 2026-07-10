extends Node3D

@onready var ball: RigidBody3D = $Ball
@onready var player_home: CharacterBody3D = $PlayerHome
@onready var camera_pivot: Node3D = $CameraPivot
@onready var score_label: Label = $HUD/ScoreLabel
@onready var power_bar: ProgressBar = $HUD/PowerBar

var home_score: int = 0
var away_score: int = 0
var player_away: CharacterBody3D
var player_teammate: CharacterBody3D
var controlled_player: CharacterBody3D
var field_length: float = FootballConstants.HALF_FIELD_LENGTH
var field_width: float = FootballConstants.HALF_FIELD_WIDTH
var controlled_player_indicator: MeshInstance3D
var _target_indicator: MeshInstance3D

enum TackleState { NORMAL, SLIDING, RECOVERING }
enum FallState { NONE, KNOCKDOWN, ROLL_1, ROLL_2, GETUP }

var _tackle_state: TackleState = TackleState.NORMAL
var _tackle_player: CharacterBody3D
var _tackle_dir: Vector3 = Vector3.ZERO
var _tackle_dist_remaining: float = 0.0
var _tackle_clean: bool = true
var _hit_processed: bool = false
var _tackle_recovery_timer: float = 0.0
var _tackle_area: Area3D
var _tackle_foul_position: Vector3 = Vector3.ZERO
var _tackle_fouled_player: Node3D

var _fall_state: FallState = FallState.NONE
var _fall_player: CharacterBody3D
var _fall_visual: PlayerVisual
var _fall_timer: float = 0.0
var _fall_away_dir: Vector3 = Vector3.ZERO   # горизонталь: от подкатчика к жертве
var _fall_roll_clip: StringName = &"roll_left"
var _roll_len: float = 0.5
var _getup_len: float = 1.0

# Commit-действие с мячом (пас/удар): пока идёт клип, управление игроком заблокировано.
# Тайминг живёт в PlayerVisual — импульс применяется по сигналу action_contact,
# блокировка снимается по action_finished.
var _action_player: CharacterBody3D     # кто выполняет действие (управление заблокировано)
var _action_dir: Vector3 = Vector3.ZERO
var _action_power: float = 0.0
var _manual_swap_cooldown: int = 0

# true → kick animation is playing; ball.kick() deferred to action_contact;
# movement is NOT locked (unlike pass which uses _action_player + motor lock)
var _kick_action_active: bool = false

# Обобщённый заряд: одно действие заряжается за раз (удар ИЛИ один из пасов).
enum ChargeAction { NONE, SHOT, PASS_SHORT, PASS_THROUGH, PASS_LOB, PASS_WALL, PASS_THROUGH_AIR }
var _charge_action: ChargeAction = ChargeAction.NONE
var _charge_time: float = 0.0
var _charge_player: CharacterBody3D
const KICK_CHARGE_MAX_TIME: float = 0.5
const KICK_POWER_MIN: float = 12.0
const KICK_POWER_MAX: float = 25.0

var _pass_rng := RandomNumberGenerator.new()
var _pending_launch: Vector3 = Vector3.ZERO

# Receive-assist: пока летит пас, слегка подруливаем ввод человека-адресата к мячу.
var _receive_active: bool = false
var _receiver: CharacterBody3D
var _receive_timer: float = 0.0

func _is_charging() -> bool:
	return _charge_action != ChargeAction.NONE


func _ready() -> void:
	_pass_rng.randomize()
	_setup_inputs()
	_setup_floor()
	_setup_grass()
	_setup_field_markings()
	_setup_ball()
	_setup_camera()
	_setup_goals()
	_setup_away_player()
	controlled_player = player_home
	player_home.add_to_group("team_1")
	player_home.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	player_home.collision_mask = FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
	var home_mesh := player_home.get_node_or_null(^"Mesh")
	if home_mesh:
		home_mesh.queue_free()
	var home_visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	player_home.add_child(home_visual)
	player_home.add_child(PlayerMotor.new())
	home_visual.apply_appearance({"kit_color": Color(0.1, 0.1, 0.9)})
	home_visual.action_contact.connect(_on_action_contact.bind(player_home))
	home_visual.action_finished.connect(_on_action_finished.bind(player_home))
	_setup_teammate()
	_setup_boundaries()
	_give_ai_to_player_home()
	_setup_controlled_indicator()
	_setup_target_indicator()
	_setup_tackle_area()
	_setup_power_bar()


func _setup_power_bar() -> void:
	power_bar.min_value = 0.0
	power_bar.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.15, 0.6)
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	power_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.9, 0.2, 0.9)
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	power_bar.add_theme_stylebox_override("fill", fill)


func _setup_inputs() -> void:
	# Строим ввод в коде (project.godot мёртв). Движение — стрелки + левый стик; буквы WASD
	# освобождены под действия. Каждый action может иметь и клавиши, и джойпад-события.
	# key_events: клавиши. joy_buttons: кнопки геймпада. joy_axes: [оси] как [axis, value].
	var actions := {
		&"move_left":       {"keys": [KEY_LEFT],  "buttons": [], "axes": [[JOY_AXIS_LEFT_X, -1.0]]},
		&"move_right":      {"keys": [KEY_RIGHT], "buttons": [], "axes": [[JOY_AXIS_LEFT_X, 1.0]]},
		&"move_forward":    {"keys": [KEY_UP],    "buttons": [], "axes": [[JOY_AXIS_LEFT_Y, -1.0]]},
		&"move_back":       {"keys": [KEY_DOWN],  "buttons": [], "axes": [[JOY_AXIS_LEFT_Y, 1.0]]},
		&"sprint":          {"keys": [KEY_SHIFT], "buttons": [], "axes": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]},
		&"kick":            {"keys": [KEY_D],     "buttons": [JOY_BUTTON_X], "axes": []},
		&"pass_short":      {"keys": [KEY_X],     "buttons": [JOY_BUTTON_A], "axes": []},
		&"pass_through":    {"keys": [KEY_W],     "buttons": [JOY_BUTTON_Y], "axes": []},
		&"pass_lob":        {"keys": [KEY_A],     "buttons": [JOY_BUTTON_B], "axes": []},
		&"combo_modifier":  {"keys": [KEY_Q],     "buttons": [JOY_BUTTON_LEFT_SHOULDER], "axes": []},
		&"pause":           {"keys": [KEY_ESCAPE],"buttons": [JOY_BUTTON_START], "axes": []},
	}
	for action in actions:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action)
		InputMap.action_set_deadzone(action, 0.2)
		for keycode in actions[action]["keys"]:
			var ek := InputEventKey.new()
			ek.keycode = keycode
			InputMap.action_add_event(action, ek)
		for btn in actions[action]["buttons"]:
			var eb := InputEventJoypadButton.new()
			eb.button_index = btn
			InputMap.action_add_event(action, eb)
		for ax in actions[action]["axes"]:
			var em := InputEventJoypadMotion.new()
			em.axis = ax[0]
			em.axis_value = ax[1]
			InputMap.action_add_event(action, em)
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
	# Мяч остаётся на слое 1 (гол-детект и подкат-детект завязаны на это), но должен
	# сталкиваться и с питчем (слой 1), и с границами (ушли на отдельный слой) — иначе улетит за поле.
	ball.collision_mask = 1 | FootballConstants.BOUNDARY_COLLISION_LAYER
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
		body.collision_layer = FootballConstants.BOUNDARY_COLLISION_LAYER
		body.collision_mask = 0
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
	var visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	new_player.add_child(visual)
	new_player.add_child(PlayerMotor.new())
	visual.apply_appearance({"kit_color": Color(0.9, 0.1, 0.1)})
	visual.action_contact.connect(_on_action_contact.bind(new_player))
	visual.action_finished.connect(_on_action_finished.bind(new_player))
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.5
	shape.radius = 0.3
	col.shape = shape
	col.position = Vector3(0, 0.25, 0)
	new_player.add_child(col)
	add_child(new_player)
	new_player.add_to_group("team_2")
	new_player.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	new_player.collision_mask = FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
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
	var visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	new_player.add_child(visual)
	new_player.add_child(PlayerMotor.new())
	visual.apply_appearance({"kit_color": Color(0.1, 0.1, 0.9)})
	visual.action_contact.connect(_on_action_contact.bind(new_player))
	visual.action_finished.connect(_on_action_finished.bind(new_player))
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.5
	shape.radius = 0.3
	col.shape = shape
	col.position = Vector3(0, 0.25, 0)
	new_player.add_child(col)
	add_child(new_player)
	new_player.add_to_group("team_1")
	new_player.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	new_player.collision_mask = FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
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

	# Заряд: копим, пока держим кнопку заряжаемого действия.
	if _is_charging() and _charge_player == controlled_player:
		var max_time := KICK_CHARGE_MAX_TIME if _charge_action == ChargeAction.SHOT else FootballConstants.PASS_CHARGE_MAX_TIME
		_charge_time += get_process_delta_time()
		if _charge_time >= max_time:
			_charge_time = max_time
			_fire_charge()
		if _is_charging():
			var ratio := clampf(_charge_time / max_time, 0.0, 1.0)
			power_bar.value = ratio
			var fill := power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
	elif _is_charging():
		_cancel_charge()
	power_bar.visible = _is_charging() and _charge_player == controlled_player

	var show_target := _is_charging() and _charge_action != ChargeAction.SHOT and _charge_player == controlled_player
	if show_target:
		var mates := _team_arrays(&"team_1", _charge_player)
		var mate_pos: PackedVector3Array = mates["pos"]
		var mate_vel: PackedVector3Array = mates["vel"]
		var mate_nodes: Array = mates["nodes"]
		var aim: Vector3 = ball.peek_dribble_direction()
		var idx := PassSystem.select_target(_charge_player.global_position, aim, mate_pos, mate_vel,
			FootballConstants.PASS_LEAD_GAIN, FootballConstants.PASS_DOT_BIAS, FootballConstants.PASS_MAX_RANGE)
		if idx >= 0:
			var tgt: Node3D = mate_nodes[idx]
			_target_indicator.global_position = tgt.global_position + Vector3(0, 2.6, 0)
			_target_indicator.visible = true
		else:
			_target_indicator.visible = false
	else:
		_target_indicator.visible = false


func _physics_process(delta: float) -> void:
	_handle_dribbling()
	_handle_player_input(delta)

	# Auto-switch to whoever on our team has the ball (skip if Q was just pressed)
	if _manual_swap_cooldown > 0:
		_manual_swap_cooldown -= 1
	else:
		if ball.has_method(&"set_dribbler") and ball.dribbler:
			var db: Node3D = ball.dribbler
			if (db == player_home or db == player_teammate) and db != controlled_player:
				controlled_player = db
				_sync_ai_controllers()

	# Смена игрока — только в защите (мяч не у нас). В атаке combo_modifier = модификатор паса.
	if Input.is_action_just_pressed(&"combo_modifier") and not _we_possess():
		controlled_player = player_teammate if controlled_player == player_home else player_home
		_sync_ai_controllers()
		_manual_swap_cooldown = 10

	# Set opponent's target_node to whoever on our team is dribbling
	if player_away:
		if ball.has_method(&"set_dribbler") and ball.dribbler:
			var db: Node3D = ball.dribbler
			if db == player_home or db == player_teammate:
				player_away.target_node = db
		else:
			player_away.target_node = null

	_handle_tackle(delta)
	_poll_ai_tackles()

	# Автомат падения сбитого игрока (ragdoll → на живот → 2 переката → вставание).
	_process_fall(delta)

	# Receive-assist: тикаем таймаут и снимаем фазу по поимке/таймауту/смене игрока/невалидности.
	if _receive_active:
		_receive_timer -= delta
		var caught: bool = ball.has_method(&"set_dribbler") and ball.dribbler == _receiver
		if caught or _receive_timer <= 0.0 or _receiver != controlled_player or not is_instance_valid(_receiver):
			_receive_active = false
			_receiver = null


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


func _setup_target_indicator() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.2
	mesh.height = 0.4

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.2)  # жёлтый — цель паса
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	_target_indicator = mi


func _sync_ai_controllers() -> void:
	if player_home:
		player_home.controlled_player = controlled_player
	if player_teammate:
		player_teammate.controlled_player = controlled_player


func _setup_tackle_area() -> void:
	_tackle_area = Area3D.new()
	_tackle_area.name = "TackleArea"
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = FootballConstants.SLIDE_TACKLE_AREA_RADIUS
	col.shape = shape
	_tackle_area.add_child(col)
	# Мяч сидит на слое 1 (дефолтный collision_mask Area3D), но полевые игроки — на
	# PLAYER_COLLISION_MASK (bit2, см. _setup_boundaries). Без явного добавления этого бита
	# body_entered никогда не срабатывает на игрока — только на мяч. Из-за этого раньше
	# ветка попадания в игрока была "мертва" даже после включения в коде: сигнал физически
	# не приходил.
	_tackle_area.collision_mask = 1 | FootballConstants.PLAYER_COLLISION_MASK
	_tackle_area.monitoring = false
	_tackle_area.monitorable = false
	_tackle_area.body_entered.connect(_on_tackle_body_entered)
	add_child(_tackle_area)


## Статический пол на y=0: опора для локомоции и приземления ragdoll.
## ПРИМЕЧАНИЕ (отклонение от брифа): бриф просил collision_layer=1 («питч+мяч»), но
## поле-игроков collision_mask = PLAYER_COLLISION_MASK | BOUNDARY_COLLISION_LAYER
## намеренно НЕ включает слой 1 (чтобы капсула не толкала мяч физически — см. CLAUDE.md
## и хотфикс 78990c8). Проверено эмпирически: пол на слое 1 → игрок проваливается
## насквозь (is_on_floor() всегда false). Кладём пол на BOUNDARY_COLLISION_LAYER —
## его уже видят и игроки (маска 2|4), и мяч (маска 1|4) — без правки чужих масок.
func _setup_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = FootballConstants.BOUNDARY_COLLISION_LAYER
	floor_body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()  # бесконечная плоскость, нормаль +Y, y=0
	floor_body.add_child(col)
	add_child(floor_body)


func _handle_dribbling() -> void:
	if not ball.has_method(&"release_dribble"):
		return
	if ball.dribbler:
		var dist: float = ball.dribbler.global_position.distance_to(ball.global_position)
		if dist > 3.0:
			ball.release_dribble()
		return
	# Пас летит на _receiver — расширенный радиус подбора именно для него, иначе быстрый
	# мяч проносит мимо, пока receive-assist ещё довозит игрока на линию мяча.
	if _receive_active and is_instance_valid(_receiver):
		var recv_dist: float = _receiver.global_position.distance_to(ball.global_position)
		if recv_dist < FootballConstants.PASS_RECEIVE_CATCH_RADIUS:
			ball.set_dribbler(_receiver)
			if _receiver.has_method(&"end_receiving"):
				_receiver.end_receiving()
			return
	for p in [player_home, player_teammate, player_away]:
		if not p or not is_instance_valid(p):
			continue
		var dist: float = p.global_position.distance_to(ball.global_position)
		if dist < 1.0:
			ball.set_dribbler(p)
			if p.has_method(&"end_receiving"):
				p.end_receiving()
			return


func _handle_player_input(delta: float) -> void:
	if controlled_player and controlled_player.is_in_group("fallen"):
		var fallen_motor := _player_motor(controlled_player)
		if fallen_motor != null:
			fallen_motor.set_move_intent(Vector3.ZERO)
		return
	# _tackle_state общий на весь матч (не per-player) — блокировать ввод нужно, только
	# когда подкатчик — сам управляемый игрок (его слайд/recovery), иначе человек замирает
	# от ЛЮБОГО чужого подката на поле (например, ИИ-соперник промахнулся мимо, а
	# человек всё равно не мог двигаться).
	if _tackle_state != TackleState.NORMAL and controlled_player == _tackle_player:
		var blocked_motor := _player_motor(controlled_player)
		if blocked_motor != null:
			blocked_motor.set_move_intent(Vector3.ZERO)
		return
	if not controlled_player:
		return
	if _action_player == controlled_player and not _kick_action_active:
		return
	var input_vec := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var cam_basis := camera_pivot.global_transform.basis
	var cam_forward := -cam_basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()
	var cam_right := cam_basis.x
	cam_right.y = 0
	cam_right = cam_right.normalized()
	var dir := (cam_forward * -input_vec.y + cam_right * input_vec.x)
	if dir.length() > 1.0:
		dir = dir.normalized()
	# Receive-assist: пока летит пас на нас, всегда бежим на мяч — не полагаемся на то, что
	# стик уже переориентирован для нового игрока сразу после хендоффа (обычно он ещё держит
	# направление ПРЕЖНЕГО игрока), поэтому больше не "уважаем" отклонённый стик как dummy-run.
	if _receive_active and controlled_player == _receiver and is_instance_valid(ball):
		var db := (ball.global_position + ball.linear_velocity * FootballConstants.PASS_RECEIVE_PREDICT_WINDOW) - controlled_player.global_position
		db.y = 0.0
		if db.length() > 0.01:
			dir = db.normalized()
	# Аналоговый спринт: сила триггера (или 1.0 с клавиши Shift) лерпит speed_scale.
	var sprint_strength := Input.get_action_strength(&"sprint")
	var sprint_scale := lerpf(1.0, FootballConstants.LOCO_SPRINT_SPEED / FootballConstants.LOCO_TOP_SPEED, sprint_strength)
	var motor := _player_motor(controlled_player)
	if motor != null:
		motor.set_move_intent(dir, sprint_scale)

	# Kick charge system (OpenSoccer-style)
	if Input.is_action_just_pressed(&"kick"):
		if _is_charging():
			pass  # already charging, ignore
		elif _is_near_ball(controlled_player) and _is_our_dribbler(controlled_player):
			_start_charge(ChargeAction.SHOT, controlled_player)
		else:
			_try_tackle(controlled_player)

	if Input.is_action_just_released(&"kick") and _charge_action == ChargeAction.SHOT and _charge_player == controlled_player:
		_fire_charge()

	# Пасы: одна кнопка на семейство; combo_modifier в атаке выбирает «спец»-вариант.
	var combo := Input.is_action_pressed(&"combo_modifier")
	if _is_near_ball(controlled_player) and _is_our_dribbler(controlled_player):
		if Input.is_action_just_pressed(&"pass_short"):
			_start_charge(ChargeAction.PASS_WALL if combo else ChargeAction.PASS_SHORT, controlled_player)
		elif Input.is_action_just_pressed(&"pass_through"):
			_start_charge(ChargeAction.PASS_THROUGH_AIR if combo else ChargeAction.PASS_THROUGH, controlled_player)
		elif Input.is_action_just_pressed(&"pass_lob"):
			_start_charge(ChargeAction.PASS_LOB, controlled_player)
	for act in [&"pass_short", &"pass_through", &"pass_lob"]:
		if Input.is_action_just_released(act) and _is_charging() and _charge_action != ChargeAction.SHOT and _charge_player == controlled_player:
			_fire_charge()
			break


func _is_near_ball(player_node: Node3D) -> bool:
	if not ball.has_method(&"kick"):
		return false
	return player_node.global_position.distance_to(ball.global_position) <= 2.0

func _is_our_dribbler(player_node: Node3D) -> bool:
	if not ball.has_method(&"set_dribbler"):
		return false
	return ball.dribbler == player_node

## Владеет ли наша команда мячом сейчас (для контекст-зависимого combo_modifier).
func _we_possess() -> bool:
	if not (ball.has_method(&"set_dribbler") and ball.dribbler):
		return false
	return ball.dribbler == player_home or ball.dribbler == player_teammate

func _start_charge(action: ChargeAction, player_node: CharacterBody3D) -> void:
	_charge_action = action
	_charge_time = 0.0
	_charge_player = player_node
	var dir: Vector3 = ball.get_dribble_direction()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		player_node.rotation.y = atan2(-flat.x, -flat.z)

func _fire_charge() -> void:
	if not _is_charging() or not _charge_player or not is_instance_valid(_charge_player):
		_cancel_charge()
		return
	var action := _charge_action
	var player := _charge_player
	if action == ChargeAction.SHOT:
		var ratio := clampf(_charge_time / KICK_CHARGE_MAX_TIME, 0.0, 1.0)
		var power := lerpf(KICK_POWER_MIN, KICK_POWER_MAX, ratio)
		var dir: Vector3 = ball.get_dribble_direction()
		dir.y = lerpf(0.05, 0.5, ratio)  # слабый удар — низом, сильный — с подъёмом
		_cancel_charge()

		# Подключаемся к commit-action системе, но БЕЗ блокировки мотора.
		# ball.kick() будет вызван из _on_action_contact по сигналу анимации.
		_action_player = player
		_action_dir = dir
		_action_power = power
		_kick_action_active = true
		var visual := _player_visual(player)
		if visual != null and visual.trigger("kick"):
			return  # ждём action_contact
		# Фолбэк без анимации: бьём сразу
		ball.kick(dir, power)
		_action_player = null
		_kick_action_active = false
	else:
		var charge_ratio := clampf(_charge_time / FootballConstants.PASS_CHARGE_MAX_TIME, 0.0, 1.0)
		_cancel_charge()
		_fire_pass(action, player, charge_ratio)

func _cancel_charge() -> void:
	_charge_action = ChargeAction.NONE
	_charge_time = 0.0
	_charge_player = null
	power_bar.visible = false

## Собрать параметры паса по заряжаемому действию. Заряд множит базовую силу.
func _pass_params(action: ChargeAction, charge_ratio: float) -> PassParams:
	var p := PassParams.new()
	var mult := lerpf(FootballConstants.PASS_POWER_CHARGE_MIN, FootballConstants.PASS_POWER_CHARGE_MAX, charge_ratio)
	match action:
		ChargeAction.PASS_SHORT:
			pass  # скорость низового паса считается по дистанции в _fire_pass (ground_pass_speed)
		ChargeAction.PASS_WALL:
			p.is_wall = true
		ChargeAction.PASS_THROUGH:
			p.extra_lead = FootballConstants.PASS_THROUGH_EXTRA_LEAD
		ChargeAction.PASS_LOB:
			p.peak_height = FootballConstants.PASS_LOB_PEAK_HEIGHT * mult
			p.is_air = true
		ChargeAction.PASS_THROUGH_AIR:
			p.peak_height = FootballConstants.PASS_THROUGH_AIR_PEAK_HEIGHT * mult
			p.extra_lead = FootballConstants.PASS_THROUGH_EXTRA_LEAD
			p.is_air = true
		_:
			pass
	return p


## Позиции/скорости/узлы группы в параллельных массивах (индекс общий). Исключает except_node.
func _team_arrays(group: StringName, except_node: Node) -> Dictionary:
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var nodes: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(group):
		if n == except_node or not (n is CharacterBody3D) or not is_instance_valid(n):
			continue
		positions.append(n.global_position)
		velocities.append(n.velocity)
		nodes.append(n)
	return {"pos": positions, "vel": velocities, "nodes": nodes}


## Геометрия решает «можно ли перехватить»; шанс решает, среагирует ли соперник (не читерски-
## идеально). Если да — соперник бежит к точке пересечения (визуальный, честный перехват).
## NOTE: FootballConstants.AI_SPEED (5.0) is legacy/unused elsewhere (see CLAUDE.md's own
## caveat on it) — the opponent's REAL speed is the `speed` export on simple_ai.gd (8.0 by
## default). Read it off the node via get(), not the stale constant, or every interception
## feasibility check will be computed against a speed the opponent doesn't actually have.
func _maybe_flag_interceptor(from: Vector3, to: Vector3, launch_vel: Vector3) -> void:
	var ball_speed := Vector3(launch_vel.x, 0.0, launch_vel.z).length()
	var opps := _team_arrays(&"team_2", null)
	var opp_pos: PackedVector3Array = opps["pos"]
	var opp_nodes: Array = opps["nodes"]
	var best_time := INF
	var best_i := -1
	for i in range(opp_pos.size()):
		var speed_variant: Variant = opp_nodes[i].get(&"speed")
		var opp_speed: float = speed_variant if speed_variant != null else FootballConstants.AI_SPEED
		var t := PassSystem.interception_time(from, to, ball_speed, opp_pos[i],
			opp_speed, FootballConstants.PASS_CORRIDOR_HALF_WIDTH, FootballConstants.PASS_CORRIDOR_SPREAD)
		if t < best_time:
			best_time = t
			best_i = i
	if best_i < 0:
		return
	if _pass_rng.randf() > FootballConstants.AI_INTERCEPT_CHANCE:
		return  # соперник «зевнул»
	var opp: Node3D = opp_nodes[best_i]
	if opp.has_method(&"begin_intercept"):
		var point := from + Vector3(launch_vel.x, 0.0, launch_vel.z).normalized() * (best_time * ball_speed)
		opp.begin_intercept(point)


## Реальная гравитация мяча (RigidBody под движковую гравитацию, НЕ FootballConstants.GRAVITY).
func _ball_gravity() -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return g * ball.gravity_scale


## Выполнить пас: выбрать цель по прицелу, посчитать траекторию, применить импульс через
## commit-action (как удар), передать управление принимающему сразу.
func _fire_pass(action: ChargeAction, player: CharacterBody3D, charge_ratio: float) -> void:
	if not ball.has_method(&"launch"):
		return
	var params := _pass_params(action, charge_ratio)
	var mates := _team_arrays(&"team_1", player)
	var mate_pos: PackedVector3Array = mates["pos"]
	var mate_vel: PackedVector3Array = mates["vel"]
	var mate_nodes: Array = mates["nodes"]
	var aim: Vector3 = ball.get_dribble_direction()
	var idx := PassSystem.select_target(player.global_position, aim, mate_pos, mate_vel,
		FootballConstants.PASS_LEAD_GAIN, FootballConstants.PASS_DOT_BIAS, FootballConstants.PASS_MAX_RANGE)
	# Точка прицела: в ноги (короткий/навес) или на ход (through). Нет цели → по направлению прицела.
	var from := ball.global_position
	var aim_point: Vector3
	var receiver: CharacterBody3D = null
	var ball_speed := FootballConstants.PASS_LEAD_SPEED_ESTIMATE
	if idx >= 0:
		receiver = mate_nodes[idx]
		if params.extra_lead > 0.0:
			aim_point = PassSystem.lead_point(mate_pos[idx], mate_vel[idx], from, ball_speed, params.extra_lead)
		else:
			aim_point = mate_pos[idx]
	else:
		var flat := Vector3(aim.x, 0.0, aim.z).normalized()
		aim_point = from + flat * 12.0
	# Разброс точности.
	var flat_dir := (aim_point - from)
	flat_dir.y = 0.0
	var spread := PassSystem.scatter_degrees(FootballConstants.PASS_SPREAD_BASE, FootballConstants.PASS_ASSIST,
		flat_dir.length(), FootballConstants.PASS_SPREAD_DIST_REF)
	flat_dir = PassSystem.apply_scatter(flat_dir, spread, _pass_rng)
	aim_point = from + flat_dir + Vector3(0.0, aim_point.y - from.y, 0.0)
	# Баллистика.
	var launch_vel: Vector3
	if params.is_air:
		var g := _ball_gravity()
		launch_vel = PassSystem.launch_lob(from, aim_point, params.peak_height, g)
	else:
		var ground_dist := (aim_point - from).length()
		var ground_speed := PassSystem.ground_pass_speed(ground_dist, charge_ratio,
			FootballConstants.PASS_GROUND_MIN_TRAVEL_TIME, FootballConstants.PASS_GROUND_MAX_TRAVEL_TIME,
			FootballConstants.PASS_GROUND_MIN_SPEED, FootballConstants.PASS_GROUND_MAX_SPEED)
		launch_vel = PassSystem.launch_ground(from, aim_point, ground_speed)
	_maybe_flag_interceptor(from, aim_point, launch_vel)
	# Commit-action: импульс по action_contact, без блокировки мотора (как kick).
	_action_player = player
	_action_dir = launch_vel  # для пасов _action_dir несёт готовую скорость (см. _on_action_contact)
	_action_power = -1.0       # маркер «это launch, а не kick»
	_kick_action_active = true
	_pending_launch = launch_vel
	# Передать управление принимающему сразу.
	if receiver != null:
		controlled_player = receiver
		_sync_ai_controllers()
		_manual_swap_cooldown = 30
	if receiver != null and receiver != controlled_player and receiver.has_method(&"begin_receiving"):
		receiver.begin_receiving(launch_vel, params.extra_lead)
	if receiver != null and receiver == controlled_player:
		_receive_active = true
		_receiver = receiver
		_receive_timer = FootballConstants.PASS_RECEIVE_MAX_TIME
	if params.is_wall and is_instance_valid(player) and player.has_method(&"begin_give_and_go"):
		if receiver != null:
			player.begin_give_and_go(receiver.global_position)
		if ball.has_method(&"clear_last_kicker"):
			# Не await здесь напрямую: это приостановило бы весь _fire_pass (включая
			# visual.trigger()/ball.launch() ниже) на 0.4с. Запускаем отдельной корутиной.
			_clear_wall_pass_cooldown()
	var visual := _player_visual(player)
	if visual != null and visual.trigger("pass"):
		return
	ball.launch(launch_vel)
	_action_player = null
	_kick_action_active = false


## Даём отдавшему «стенку» шанс принять быстрый возврат, сняв с мяча метку последнего
## игрока чуть раньше истечения ball._kick_cooldown_msec. Отдельная корутина — намеренно
## не await-ится из _fire_pass, чтобы не задерживать сам пас (см. вызов выше).
func _clear_wall_pass_cooldown() -> void:
	await get_tree().create_timer(0.4).timeout
	if is_instance_valid(ball):
		ball.clear_last_kicker()


## Начать commit-действие с мячом: развернуть игрока, проиграть анимацию, заблокировать
## управление. Импульс мячу и снятие блокировки — по сигналам визуала (contact/finished).
## Если визуала/клипа нет (фолбэк) — импульс сразу, без блокировки.
func _start_ball_action(player_node: CharacterBody3D, dir: Vector3, power: float, action: String) -> void:
	if _action_player != null:
		return  # уже идёт действие — игнорируем повторный ввод
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		player_node.rotation.y = atan2(-flat.x, -flat.z)
	var visual := _player_visual(player_node)
	if visual != null and visual.trigger(action):
		_action_player = player_node
		_action_dir = dir
		_action_power = power
		var lock_motor := _player_motor(player_node)
		if lock_motor != null:
			lock_motor.set_control_locked(true)
	else:
		if ball.has_method(&"kick"):
			ball.kick(dir, power)  # фолбэк без анимации: бьём сразу


## Момент касания ногой: придать импульс мячу.
func _on_action_contact(_action: String, player: Node) -> void:
	if player != _action_player:
		return
	if _action_power < 0.0 and ball.has_method(&"launch"):
		ball.launch(_pending_launch)
	elif ball.has_method(&"kick"):
		ball.kick(_action_dir, _action_power)


## Действие завершилось: вернуть управление.
func _on_action_finished(_action: String, player: Node) -> void:
	if player == _action_player:
		_action_player = null
		_kick_action_active = false
		var motor := _player_motor(player)
		if motor != null:
			motor.set_control_locked(false)


## Отменить действие игрока (сбили подкатом на замахе): без импульса, вернуть управление.
func _cancel_ball_action(player: Node) -> void:
	if _action_player != player:
		return
	_action_player = null
	_kick_action_active = false
	var motor := _player_motor(player)
	if motor != null:
		motor.set_control_locked(false)
	var visual := _player_visual(player)
	if visual != null:
		visual.cancel_action()


## Найти дочерний PlayerVisual у игрового узла (визуал добавляется ребёнком при спавне).
func _player_visual(player_node: Node) -> PlayerVisual:
	if player_node == null:
		return null
	for c in player_node.get_children():
		if c is PlayerVisual:
			return c
	return null


## Найти дочерний PlayerMotor у игрового узла (добавляется ребёнком при спавне).
func _player_motor(player_node: Node) -> PlayerMotor:
	if player_node == null:
		return null
	return PlayerMotor.find_on(player_node)


func _can_tackle(tackler: Node3D) -> bool:
	# Can't tackle yourself — you have the ball
	if ball.has_method(&"set_dribbler") and ball.dribbler == tackler:
		return false

	# Check 1: opponent is actively dribbling
	if ball.has_method(&"set_dribbler") and ball.dribbler:
		if not _same_team(tackler, ball.dribbler):
			return true

	# Check 2: opponent last touched the ball
	if ball.has_method(&"get_last_touch"):
		var last: Node3D = ball.get_last_touch()
		if last and not _same_team(tackler, last):
			return true

	# Check 3: opponent exists on the field
	var opponent_group := "team_2" if tackler.is_in_group("team_1") else "team_1"
	for node in get_tree().get_nodes_in_group(opponent_group):
		if is_instance_valid(node):
			return true

	return false



func _try_tackle(player: CharacterBody3D) -> bool:
	if _tackle_state != TackleState.NORMAL:
		return false
	if not _can_tackle(player):
		return false
	_start_tackle(player, ball)
	return true


func _start_tackle(player: CharacterBody3D, target: Node3D = null) -> void:
	if _tackle_state != TackleState.NORMAL:
		return
	if not _can_tackle(player):
		return

	if not target:
		target = ball
	if not target:
		return

	# Лочим только когда такл реально стартует (после всех guard-выходов выше) —
	# иначе на раннем return лок повиснет без парной разблокировки в _tackle_recover.
	var tackler_motor := _player_motor(player)
	if tackler_motor != null:
		tackler_motor.set_control_locked(true)

	_tackle_state = TackleState.SLIDING
	_tackle_player = player
	_tackle_clean = true
	_hit_processed = false
	_tackle_fouled_player = null

	# Прицел с упреждением: цель (обычно мяч, следующий за дриблером — см. ball_controller.gd
	# velocity-matching) продолжает двигаться, пока слайд едет (~0.4с). Без упреждения
	# направление считается один раз в момент старта и потом никогда не пересчитывается —
	# движущаяся цель успевает сместиться на метр+ за время слайда, и подкат чисто проезжает
	# мимо, даже если решение о подкате было принято вовремя. lead_time — грубая (без
	# итерации схождения) оценка "сколько ехать до текущей дистанции цели".
	var to_target: Vector3 = target.global_position - player.global_position
	to_target.y = 0.0
	var lead_time := to_target.length() / FootballConstants.SLIDE_TACKLE_SPEED
	var target_velocity := Vector3.ZERO
	if target is RigidBody3D:
		target_velocity = (target as RigidBody3D).linear_velocity
	elif target is CharacterBody3D:
		target_velocity = (target as CharacterBody3D).velocity
	target_velocity.y = 0.0
	var predicted_pos: Vector3 = target.global_position + target_velocity * lead_time
	var dir: Vector3 = predicted_pos - player.global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = to_target
	_tackle_dir = dir.normalized()
	_tackle_dist_remaining = FootballConstants.SLIDE_TACKLE_RANGE

	var area_pos := player.global_position
	area_pos.y = 0.3
	_tackle_area.global_position = area_pos
	_tackle_area.monitoring = true

	var tackler_visual := _player_visual(player)
	if tackler_visual != null and tackler_visual.has_method(&"play_oneshot"):
		tackler_visual.play_oneshot(&"tackle")


func _on_tackle_body_entered(body: Node) -> void:
	if _hit_processed:
		return
	if not _tackle_player or not is_instance_valid(_tackle_player):
		return

	# Ball → clean tackle. Игрока-соперника TackleArea (радиус SLIDE_TACKLE_AREA_RADIUS=1.5,
	# щедрый — нужен, чтобы дотягиваться до мяча) больше НЕ роняет напрямую — на таком
	# расстоянии капсулы визуально не соприкасаются. Сбивание игрока — отдельная, тесная
	# проверка _check_tackle_player_hit() в _tackle_slide(), на реальном контакте капсул.
	if body == ball:
		_hit_processed = true
		_tackle_clean = true
		if ball.has_method(&"release_dribble"):
			ball.release_dribble()
		if ball.has_method(&"kick"):
			var kick_dir := _tackle_dir
			kick_dir.y = FootballConstants.SLIDE_TACKLE_BALL_DIR_Y
			ball.kick(kick_dir, FootballConstants.SLIDE_TACKLE_BALL_POWER)
		_tackle_enter_recovery()
		return

	# Same team player / игрок-соперник вне тесного радиуса → игнор


func _on_tackle_hit_player(body: CharacterBody3D, normal: Vector3) -> void:
	_hit_processed = true
	_tackle_clean = true

	# Pop the ball loose in collision direction
	if ball.has_method(&"release_dribble"):
		ball.release_dribble()
	var pop_dir := normal.normalized()
	pop_dir.y = FootballConstants.SLIDE_TACKLE_BALL_DIR_Y
	if ball.has_method(&"kick"):
		ball.kick(pop_dir, FootballConstants.SLIDE_TACKLE_BALL_POWER)

	# Уже падает — не перезапускаем цепочку.
	if body.is_in_group("fallen"):
		return
	_begin_fall(body, normal)


## Завести анимационное падение жертвы (Path B: без физ-ragdoll — он несовместим с
## масштабированным Mixamo-скелетом в Godot). Роняем в позу «лежит» (fallen_idle),
## отброс тела даём кодом, дальше 2 переката от подкатчика → вставание.
func _begin_fall(body: CharacterBody3D, normal: Vector3) -> void:
	# Re-entrancy: другое падение ещё идёт (tackle-recovery 0.5с короче цепочки падения ~3с) —
	# корректно завершаем прошлую жертву, иначе она осиротеет с вечным _fall_lock/motor-lock/fallen.
	if _fall_state != FallState.NONE:
		if is_instance_valid(_fall_player):
			_finish_fall()
		else:
			_abort_fall()
	var visual := _player_visual(body)
	if visual == null or not visual.has_method(&"play_oneshot"):
		# Фолбэк: нет визуала — просто помечаем fallen на короткое время.
		body.add_to_group("fallen")
		_fall_player = body
		_fall_visual = null
		_fall_state = FallState.GETUP
		_fall_timer = 0.0
		return
	body.add_to_group("fallen")
	_cancel_ball_action(body)
	var motor := _player_motor(body)
	if motor != null:
		motor.set_control_locked(true)

	# away-направление (от подкатчика к жертве), горизонталь.
	var away := body.global_position - _tackle_player.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = _tackle_dir
	_fall_away_dir = away.normalized()
	# Сторона переката: знак векторного (fall_away × up) относительно взгляда тела.
	var side := _fall_away_dir.cross(Vector3.UP)
	var facing := -body.global_transform.basis.z
	_fall_roll_clip = &"roll_left" if side.dot(facing) >= 0.0 else &"roll_right"
	# Yaw тела: лицом по направлению падения (перекаты/вставание идут отсюда).
	body.rotation.y = atan2(-_fall_away_dir.x, -_fall_away_dir.z)

	_fall_player = body
	_fall_visual = visual
	visual.play_oneshot(&"fallen_idle")   # роняем в позу «лежит»
	_fall_state = FallState.KNOCKDOWN
	_fall_timer = 0.0


## Автомат падения: knockdown (лежит + отброс) → 2 переката (от подкатчика) → вставание.
## Инвариант: любой выход из этой функции, который завершает/прерывает падение,
## обязан пройти через _finish_fall()/_abort_fall(), иначе _fall_visual останется
## залочен навсегда (_fall_lock у PlayerVisual снимает только recover()).
func _process_fall(delta: float) -> void:
	if _fall_state == FallState.NONE:
		return
	if _fall_player == null or not is_instance_valid(_fall_player):
		_abort_fall()
		return
	_fall_timer += delta

	match _fall_state:
		FallState.KNOCKDOWN:
			# Отброс тела в сторону от подкатчика за время KNOCKDOWN_TIME (клип fallen_idle
			# держит позу «лежит»), затем — первый перекат.
			var move := _fall_away_dir * (FootballConstants.KNOCKBACK_DISTANCE \
				/ maxf(FootballConstants.KNOCKDOWN_TIME, 0.0001)) * delta
			_fall_player.global_position += move
			if _fall_timer >= FootballConstants.KNOCKDOWN_TIME:
				_start_roll(FallState.ROLL_1)
		FallState.ROLL_1:
			_advance_roll(delta, FallState.ROLL_2)
		FallState.ROLL_2:
			_advance_roll(delta, FallState.GETUP, true)
		FallState.GETUP:
			if _fall_visual != null:
				# double-проверка: standing_up доигрался?
				if _fall_timer >= _getup_len:
					_finish_fall()
			else:
				if _fall_timer >= 0.8:  # фолбэк-ветка без визуала
					_finish_fall()


## Запустить перекат: играем клип, запоминаем длину, обнуляем таймер шага.
func _start_roll(state_while_rolling: FallState) -> void:
	_roll_len = _fall_visual.play_oneshot(_fall_roll_clip)
	if _roll_len <= 0.0:
		_roll_len = 0.5
	_fall_timer = 0.0
	_fall_state = state_while_rolling


## Продвигать активный перекат: смещать тело в сторону away, по концу клипа — следующий шаг.
func _advance_roll(delta: float, next_state: FallState, to_getup: bool = false) -> void:
	# Равномерное боковое смещение за время клипа.
	var move := _fall_away_dir * (FootballConstants.ROLL_DISTANCE / maxf(_roll_len, 0.0001)) * delta
	_fall_player.global_position += move
	if _fall_timer >= _roll_len:
		if to_getup:
			_getup_len = _fall_visual.play_oneshot(&"standing_up")
			if _getup_len <= 0.0:
				_getup_len = 1.0
			_fall_timer = 0.0
			_fall_state = FallState.GETUP
		else:
			# Запустить второй перекат.
			_roll_len = _fall_visual.play_oneshot(_fall_roll_clip)
			if _roll_len <= 0.0:
				_roll_len = 0.5
			_fall_timer = 0.0
			_fall_state = next_state


## Завершить падение: вернуть idle, снять fallen, разлочить motor.
## Единственный штатный путь очистки состояния падения.
func _finish_fall() -> void:
	if _fall_visual != null and is_instance_valid(_fall_visual):
		_fall_visual.recover()
	if is_instance_valid(_fall_player):
		_fall_player.remove_from_group("fallen")
		if _fall_player.is_in_group("giving_run"):
			_fall_player.remove_from_group("giving_run")
		var motor := _player_motor(_fall_player)
		if motor != null:
			motor.set_control_locked(false)
	_fall_player = null
	_fall_visual = null
	_fall_state = FallState.NONE


## Аварийный путь: жертва исчезла (queue_free/невалидна) посреди падения.
## Гарантирует, что visual (если он ещё жив) получает recover(), чтобы
## _fall_lock не остался взведён навсегда — см. инвариант у _process_fall.
func _abort_fall() -> void:
	if _fall_visual != null and is_instance_valid(_fall_visual):
		_fall_visual.recover()
	_fall_player = null
	_fall_visual = null
	_fall_state = FallState.NONE


func _handle_tackle(delta: float) -> void:
	match _tackle_state:
		TackleState.SLIDING:
			_tackle_slide(delta)
		TackleState.RECOVERING:
			_tackle_recover(delta)


func _tackle_slide(delta: float) -> void:
	if not _tackle_player or not is_instance_valid(_tackle_player):
		_tackle_state = TackleState.NORMAL
		return

	var step := FootballConstants.SLIDE_TACKLE_SPEED * delta

	if not FootballConstants.SLIDE_TACKLE_INPLACE:
		var motion := _tackle_dir * step
		var collision := _tackle_player.move_and_collide(motion)

		# Check what we hit
		if collision:
			var body := collision.get_collider()
			if body is CharacterBody3D and not _same_team(_tackle_player, body):
				_on_tackle_hit_player(body, collision.get_normal())
				_tackle_enter_recovery(0.5)
				return
			else:
				_tackle_dist_remaining = 0.0
				_tackle_enter_recovery()
				return

	_tackle_dist_remaining -= step

	# Keep Area3D at player feet
	var area_pos := _tackle_player.global_position
	area_pos.y = 0.3
	_tackle_area.global_position = area_pos

	if not _hit_processed and _check_tackle_player_hit():
		return

	if _tackle_dist_remaining <= 0.0:
		_tackle_enter_recovery()


## Тесная проверка сбивания игрока-соперника: в отличие от TackleArea (щедрый радиус
## SLIDE_TACKLE_AREA_RADIUS — нужен только для дотягивания до мяча), здесь порог —
## реальный контакт капсул (плюс небольшой запас), чтобы падение не выглядело
## беспричинным на расстоянии. Кандидатов берём из уже пересекающихся с TackleArea тел
## (та же физика, просто более строгий фильтр по дистанции).
func _check_tackle_player_hit() -> bool:
	for body in _tackle_area.get_overlapping_bodies():
		if not (body is CharacterBody3D) or _same_team(_tackle_player, body):
			continue
		if body.is_in_group("fallen"):
			continue
		var to_body := body.global_position - _tackle_player.global_position
		if to_body.length() > FootballConstants.SLIDE_TACKLE_HIT_RADIUS:
			continue
		_hit_processed = true
		_on_tackle_hit_player(body, to_body.normalized())
		_tackle_enter_recovery(0.5)
		return true
	return false


func _tackle_enter_recovery(recovery_time: float = -1.0) -> void:
	_tackle_state = TackleState.RECOVERING
	_tackle_recovery_timer = FootballConstants.SLIDE_TACKLE_RECOVERY_TIME if recovery_time < 0 else recovery_time
	_tackle_area.monitoring = false


func _tackle_recover(delta: float) -> void:
	_tackle_recovery_timer -= delta
	if not _tackle_player or not is_instance_valid(_tackle_player):
		_tackle_state = TackleState.NORMAL
		return

	if _tackle_recovery_timer <= 0.0:
		var trec_visual := _player_visual(_tackle_player)
		if trec_visual != null and trec_visual.has_method(&"recover"):
			trec_visual.recover()
		if not _tackle_clean and ball.has_method(&"set_dribbler"):
			ball.release_dribble()
			ball.linear_velocity = Vector3.ZERO
			ball.angular_velocity = Vector3.ZERO
			ball.global_position = _tackle_foul_position + Vector3(0, 0.5, 0)
			# Give ball to the fouled player's team
			var fouled_team := "team_1" if _tackle_fouled_player and _tackle_fouled_player.is_in_group("team_1") else "team_2"
			var nearest := _find_nearest_on_team(_tackle_foul_position, fouled_team)
			if nearest:
				ball.set_dribbler(nearest)
		var motor := _player_motor(_tackle_player)
		if motor != null:
			motor.set_control_locked(false)
		_tackle_state = TackleState.NORMAL
		_tackle_player = null


func _find_nearest_on_team(from_pos: Vector3, team_group: String) -> CharacterBody3D:
	var nearest: CharacterBody3D = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group(team_group):
		var p := node as CharacterBody3D
		if p and is_instance_valid(p):
			var d := p.global_position.distance_squared_to(from_pos)
			if d < nearest_dist:
				nearest_dist = d
				nearest = p
	return nearest


func _same_team(a: Node, b: Node) -> bool:
	return (a.is_in_group("team_1") and b.is_in_group("team_1")) \
		or (a.is_in_group("team_2") and b.is_in_group("team_2"))


func _on_ball_collision(body: Node) -> void:
	pass


func _reset_ball() -> void:
	if ball.has_method(&"release_dribble"):
		ball.release_dribble()
	if ball.has_method(&"clear_last_kicker"):
		ball.clear_last_kicker()
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = Vector3(0, 0.5, -0.6)

	# Reset players to their starting positions
	player_home.global_position = Vector3(0, 0.5, 0)
	if player_teammate:
		player_teammate.global_position = Vector3(10, 0.5, 5)
	if player_away:
		player_away.global_position = Vector3(20, 0.5, 0)

	controlled_player = player_home
	_sync_ai_controllers()


func _poll_ai_tackles() -> void:
	for node in get_tree().get_nodes_in_group("team_2"):
		var ai := node as CharacterBody3D
		if not ai or not is_instance_valid(ai):
			continue
		if "wants_to_tackle" in ai:
			if ai.wants_to_tackle:
				_start_tackle(ai)
				ai.wants_to_tackle = false

class_name MatchManager
extends Node3D

@onready var ball: RigidBody3D = $Ball
var _human_player: CharacterBody3D        # тело, которым по умолчанию управляет человек
@onready var camera_pivot: Node3D = $CameraPivot
@onready var score_label: Label = $HUD/ScoreLabel
@onready var power_bar: ProgressBar = $HUD/PowerBar

var home_score: int = 0
var away_score: int = 0
var _team_home: Team
var _team_away: Team
var controlled_player: CharacterBody3D
var field_length: float = FootballConstants.HALF_FIELD_LENGTH
var field_width: float = FootballConstants.HALF_FIELD_WIDTH
# team_1 атакует −Z в первом тайме; половина флипает знак (будущий half-time-свап).
# ОДНО место, задающее сторону чужих ворот для прицела ударов — см. _target_goal_center().
var _attack_dir_z: float = -1.0
var _controlled_marker: Polygon2D
var _match_camera: Camera3D
var _goal_nets: Dictionary = {}
var _celebrating: bool = false
var _penalty_active: bool = false
var _penalty                                   # PenaltyController
var _penalty_cam_pose: Transform3D = Transform3D.IDENTITY
var _free_kick                                 # FreeKickController
var _free_kick_active: bool = false
var _action_executor                           # ActionExecutor
var _free_kick_cam_pose: Transform3D = Transform3D.IDENTITY
var _corner                                    # CornerController
var _corner_active: bool = false
var _corner_cam_pose: Transform3D = Transform3D.IDENTITY
var _goal_kick                                 # GoalKickController
var _goal_kick_active: bool = false
var _goal_kick_cam_pose: Transform3D = Transform3D.IDENTITY
var _throw_in                                  # ThrowInController
var _throw_in_active: bool = false
var _throw_in_cam_pose: Transform3D = Transform3D.IDENTITY
var _bc_cam_eye_z: float = 0.0                 # сглаженная Z-позиция обычной broadcast-камеры
var _third_person_camera: bool = false         # DEBUG: переключение 1/3 — broadcast / вид от 3-го лица
var _tp_cam_eye: Vector3 = Vector3.ZERO        # сглаженная позиция third-person камеры

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
var _keeper: CharacterBody3D
var _keeper_brain: Node
var _tackle_foul_position: Vector3 = Vector3.ZERO
var _tackle_fouled_player: Node3D

var _fall_state: FallState = FallState.NONE
var _fall_player: CharacterBody3D
var _fall_visual: PlayerVisual
var _fall_timer: float = 0.0
var _fall_away_dir: Vector3 = Vector3.ZERO   # горизонталь: от подкатчика к жертве
var _fall_ground_y: float = 0.5              # уровень газона жертвы (пин Y на время падения)
var _fall_roll_clip: StringName = &"roll_left"
var _roll_len: float = 0.5
var _getup_len: float = 1.0

var _manual_swap_cooldown: int = 0

# Обобщённый заряд: одно действие заряжается за раз (удар ИЛИ один из пасов). Commit-состояние
# (кто выполняет действие/импульс/блокировка) переехало в ActionExecutor (Фаза 3a) — здесь
# остаётся только заряд-как-таймер (переедет в HumanBrain на Фазе 3b).
enum ChargeAction { NONE, SHOT, SHOT_CURL, SHOT_CHIP, CLEARANCE, PASS_SHORT, PASS_THROUGH, PASS_LOB, PASS_WALL, PASS_THROUGH_AIR }
var _charge_action: ChargeAction = ChargeAction.NONE
var _charge_time: float = 0.0
var _charge_player: CharacterBody3D
const KICK_CHARGE_MAX_TIME: float = 0.5

# DEBUG: цветной след за мячом (траектория удара)
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_points: PackedVector3Array = PackedVector3Array()

# Receive-assist: пока летит пас, слегка подруливаем ввод человека-адресата к мячу.
var _receive_active: bool = false
var _receiver: CharacterBody3D
var _receive_timer: float = 0.0

# Очередь действия «в одно касание»: заряжаем удар/пас, пока мяч ещё не у ног (летит пасом,
# убежал вперёд в спринт-дриблинге, или это спорный ничейный мяч), бьём в момент, когда
# игрок дотянулся до мяча.
var _queued_action: ChargeAction = ChargeAction.NONE
var _queue_player: CharacterBody3D
var _queue_ratio: float = 0.0
var _queue_timer: float = 0.0

func _is_charging() -> bool:
	return _charge_action != ChargeAction.NONE

func _is_queued() -> bool:
	return _queued_action != ChargeAction.NONE


func _ready() -> void:
	_setup_inputs()
	_setup_floor()
	_setup_grass()
	_setup_field_markings()
	_setup_ball()
	_setup_camera()
	_setup_goals()
	_team_home = Team.new()
	_team_home.name = "TeamHome"
	_team_home.team_group = &"team_1"
	_team_home.attack_z_sign = _attack_dir_z
	_team_home.kit_color = Color(0.1, 0.1, 0.9)
	_team_home.id = &"home"
	_team_home.manager = self
	_team_home.ball = ball
	add_child(_team_home)
	_team_away = Team.new()
	_team_away.name = "TeamAway"
	_team_away.team_group = &"team_2"
	_team_away.attack_z_sign = -_attack_dir_z
	_team_away.kit_color = Color(0.9, 0.1, 0.1)
	_team_away.id = &"away"
	_team_away.manager = self
	_team_away.ball = ball
	add_child(_team_away)
	_setup_away_player()
	_setup_home_player()
	_setup_teammate()
	_setup_keeper()
	_setup_boundaries()
	_setup_controlled_indicator()
	_setup_tackle_area()
	_setup_power_bar()
	_setup_ball_trail()
	_penalty = preload("res://scripts/match/penalty_controller.gd").new()
	_penalty.name = "PenaltyController"
	add_child(_penalty)
	_penalty.setup(self, ball, camera_pivot, power_bar, _keeper)
	_free_kick = preload("res://scripts/match/free_kick_controller.gd").new()
	_free_kick.name = "FreeKickController"
	add_child(_free_kick)
	_free_kick.setup(self, ball, camera_pivot, power_bar, _keeper)
	_corner = preload("res://scripts/match/corner_controller.gd").new()
	_corner.name = "CornerController"
	add_child(_corner)
	_corner.setup(self, ball, camera_pivot, power_bar, _keeper)
	_goal_kick = preload("res://scripts/match/goal_kick_controller.gd").new()
	_goal_kick.name = "GoalKickController"
	add_child(_goal_kick)
	_goal_kick.setup(self, ball, camera_pivot, power_bar, _keeper)
	_throw_in = preload("res://scripts/match/throw_in_controller.gd").new()
	_throw_in.name = "ThrowInController"
	add_child(_throw_in)
	_throw_in.setup(self, ball, camera_pivot, power_bar)
	_action_executor = ActionExecutor.new()
	_action_executor.name = "ActionExecutor"
	add_child(_action_executor)
	_action_executor.setup(self, ball)
	# Стартовая расстановка: человек с мячом в центре (соперник глубоко — см. _setup_away_player).
	ball.global_position = _human_player.global_position + Vector3(0, 0.0, -0.6)
	if ball.has_method(&"set_dribbler"):
		ball.set_dribbler(_human_player, true)


## DEBUG: линия-след за мячом. MeshInstance3D + ImmediateMesh, перестраивается каждый кадр
## из истории позиций мяча. Цвет: свежая часть яркая, хвост затухает. Выкл через DEBUG_BALL_TRAIL.
func _setup_ball_trail() -> void:
	if not FootballConstants.DEBUG_BALL_TRAIL:
		return
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.name = "BallTrail"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true  # линия видна поверх газона/мяча
	_trail.material_override = mat
	add_child(_trail)


## Дописать текущую позицию мяча в историю и перестроить линию. Свежая часть яркая, хвост
## затухает по alpha; цвет: оранжевый пока мяч в полёте (удар/пас), иначе циан.
func _update_ball_trail(ball_pos: Vector3) -> void:
	_trail_points.push_back(ball_pos)
	var max_pts: int = FootballConstants.DEBUG_BALL_TRAIL_POINTS
	while _trail_points.size() > max_pts:
		_trail_points.remove_at(0)
	_trail_mesh.clear_surfaces()
	var n := _trail_points.size()
	if n < 2:
		return
	var in_flight: bool = ball.has_method(&"is_flight") and ball.is_flight()
	var base := Color(1.0, 0.5, 0.0) if in_flight else Color(0.1, 0.9, 1.0)
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(n):
		var t := float(i) / float(n - 1)  # 0 = хвост (старое), 1 = голова (свежее)
		_trail_mesh.surface_set_color(Color(base.r, base.g, base.b, t))
		_trail_mesh.surface_add_vertex(_trail_points[i])
	_trail_mesh.surface_end()


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
		&"combo_curl":      {"keys": [KEY_E],     "buttons": [JOY_BUTTON_RIGHT_SHOULDER], "axes": []},
		&"pause":           {"keys": [KEY_ESCAPE],"buttons": [JOY_BUTTON_START], "axes": []},
		&"penalty_debug":   {"keys": [KEY_P],     "buttons": [], "axes": []},
		&"free_kick_debug": {"keys": [KEY_F],     "buttons": [], "axes": []},
		&"corner_debug":    {"keys": [KEY_C],     "buttons": [], "axes": []},
		&"goal_kick_debug": {"keys": [KEY_G],     "buttons": [], "axes": []},
		&"throw_in_debug":  {"keys": [KEY_T],     "buttons": [], "axes": []},
		&"corner_call":     {"keys": [KEY_T],     "buttons": [JOY_BUTTON_RIGHT_SHOULDER], "axes": []},
		&"foot_left":       {"keys": [KEY_L],     "buttons": [], "axes": []},
		&"foot_right":      {"keys": [KEY_R],     "buttons": [], "axes": []},
		&"camera_broadcast":    {"keys": [KEY_1], "buttons": [], "axes": []},
		&"camera_third_person": {"keys": [KEY_3], "buttons": [], "axes": []},
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
	# Мяч на слое 1 (гол/подкат-детект завязаны на это), сталкивается с питчем (1) и границами.
	# Слой ИГРОКОВ добавляется в маску ТОЛЬКО на время полёта (ball_controller, состояние FLIGHT):
	# на дриблинге/подборе капсула игрока не должна толкать мяч (иначе близкий контроль и подбор
	# ломаются — расталкивание/подскок), а блок/перехват нужны лишь для летящего мяча.
	ball.collision_mask = 1 | FootballConstants.BOUNDARY_COLLISION_LAYER
	ball.body_entered.connect(_on_ball_collision)


func _setup_camera() -> void:
	var cam: Camera3D = $CameraPivot/Camera3D
	var cam_script = preload("res://scripts/camera/match_camera.gd")
	cam.set_script(cam_script)
	_match_camera = cam


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

		# Объёмный box: задний каркас на глубине NET_DEPTH за линией ворот.
		var ds: float = -1.0 if g.side == "Home" else 1.0
		var net_z: float = ds * FootballConstants.NET_DEPTH
		var post_left_back := _make_post(-3.66, 0, net_z)
		goal_group.add_child(post_left_back)
		var post_right_back := _make_post(3.66, 0, net_z)
		goal_group.add_child(post_right_back)
		var crossbar_back := _make_crossbar(0, 2.44, net_z)
		goal_group.add_child(crossbar_back)

		# Сетка-колыхание (компонент GoalNet) на этих воротах.
		var goal_net = preload("res://scripts/match/goal_net.gd").new()
		goal_net.name = "GoalNet"
		goal_group.add_child(goal_net)
		goal_net.rotation.y = PI if g.side == "Home" else 0.0
		goal_net.initialize(ball)
		_goal_nets[g.side] = goal_net

		# Стопперы: мяч влетает в открытый перёд, тормозит о заднюю/боковые/верхнюю сетку.
		var w := FootballConstants.GOAL_WIDTH
		var h := FootballConstants.GOAL_HEIGHT
		var nd := FootballConstants.NET_DEPTH
		var t := 0.1
		goal_group.add_child(_make_net_collider(Vector3(0, h * 0.5, ds * nd), Vector3(w, h, t)))          # задняя
		goal_group.add_child(_make_net_collider(Vector3(0, h, ds * nd * 0.5), Vector3(w, t, nd)))          # верх
		goal_group.add_child(_make_net_collider(Vector3(-w * 0.5, h * 0.5, ds * nd * 0.5), Vector3(t, h, nd)))  # лево
		goal_group.add_child(_make_net_collider(Vector3(w * 0.5, h * 0.5, ds * nd * 0.5), Vector3(t, h, nd)))   # право

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
			# Мяч В РУКАХ вратаря — не гол: во время анимаций удержания/выноса кисть (и
			# приклеенный к ней мяч) может качнуться за линию — это не взятие ворот.
			if body == ball and ball.has_method(&"is_caught") and ball.is_caught():
				return
			if body == ball and not _celebrating:
				_celebrating = true
				# Вратаря НЕ замораживаем: у keeper_ai своя обработка празднования (доигрывает
				# нырок и встаёт в idle ТОЛЬКО по завершении клипа). Заморозка (стоп _physics_process
				# + лок мотора) обрывала бы это, и вратарь мгновенно вставал в idle-позу посреди нырка.
				_set_ai_frozen(true, _keeper)   # прочие ИИ стоп в idle
				if g.side == "Home":
					away_score += 1
				else:
					home_score += 1
				score_label.text = "%d : %d" % [home_score, away_score]
				var net = _goal_nets.get(g.side)
				if net:
					net.start_sim()
				_celebrate_then_reset(net)
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


func _make_net_collider(local_pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = FootballConstants.BOUNDARY_COLLISION_LAYER
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.bounce = FootballConstants.NET_BOUNCE
	pm.friction = FootballConstants.NET_FRICTION
	body.physics_material_override = pm
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = local_pos
	return body


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


func _setup_home_player() -> void:
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_1"
	cfg.role = PlayerConfig.Role.MID
	cfg.kit_color = Color(0.1, 0.1, 0.9)
	cfg.spawn_pos = Vector3(0, 0.5, 0)
	cfg.display_name = "PlayerHome"
	cfg.ai_script = preload("res://scripts/ai/teammate_ai.gd")
	cfg.connect_action_signals = true
	cfg.extra_fields = {
		&"speed": 7.0,
		&"teammate_home_goal": ($GoalAway/GoalArea if has_node("GoalAway/GoalArea") else null),
	}
	_human_player = PlayerFactory.spawn(cfg, _team_home)
	controlled_player = _human_player
	_ai_of(_human_player).set(&"controlled_player", controlled_player)


## Идёт ли празднование гола (вратарь на это время не сейвит/не выбивает мяч).
func is_celebrating() -> bool:
	return _celebrating


## Идёт ли розыгрыш пенальти (обычный ввод/ИИ/следящая камера на это время заглушены).
func is_penalty_active() -> bool:
	return _penalty_active


func set_penalty_active(on: bool) -> void:
	_penalty_active = on


func set_penalty_cam_pose(pose: Transform3D) -> void:
	_penalty_cam_pose = pose


func is_free_kick_active() -> bool:
	return _free_kick_active


func set_free_kick_active(on: bool) -> void:
	_free_kick_active = on


func set_free_kick_cam_pose(pose: Transform3D) -> void:
	_free_kick_cam_pose = pose


func is_corner_active() -> bool:
	return _corner_active


func set_corner_active(on: bool) -> void:
	_corner_active = on


func set_corner_cam_pose(pose: Transform3D) -> void:
	_corner_cam_pose = pose


func is_goal_kick_active() -> bool:
	return _goal_kick_active


func set_goal_kick_active(on: bool) -> void:
	_goal_kick_active = on


func set_goal_kick_cam_pose(pose: Transform3D) -> void:
	_goal_kick_cam_pose = pose


func is_throw_in_active() -> bool:
	return _throw_in_active


func set_throw_in_active(on: bool) -> void:
	_throw_in_active = on


func set_throw_in_cam_pose(pose: Transform3D) -> void:
	_throw_in_cam_pose = pose


## Включить приём паса для receiver — то же самое, что обычный _fire_pass() делает для
## человека-получателя (наведение стика на предсказанную позицию мяча в _handle_player_input
## + принудительный трап на любой скорости в _handle_dribbling, минуя BALL_TRAP_MAX_SPEED).
## Штрафной свой пас/навес не проводит через _fire_pass(), но должен давать тот же эффект
## «получатель сам добегает до мяча», иначе он просто стоит, пока мяч не замедлится сам.
func begin_pass_receive(receiver: CharacterBody3D) -> void:
	_receive_active = true
	_receiver = receiver
	_receive_timer = FootballConstants.PASS_RECEIVE_MAX_TIME


## Переключить controlled_player и синхронизировать всех ИИ-скриптов (см. _sync_ai_controllers).
## Публичная обёртка для внешних контроллеров (штрафной и т.п.) — ВАЖНО вызывать её ДО любой
## конвертации ИИ-тел (напр. FreeKickController._convert_bodies), которая читает
## match_manager.controlled_player для проставления своего поля controlled_player: если вызвать
## после конвертации, тела (включая самого получателя!) получат СТАРОЕ значение (прежнего
## бьющего), self-гейт `controlled_player == self` их AI-скрипта не сработает, и AI продолжит
## сам двигать мотор параллельно с человеческим вводом (борьба за один мотор).
func assign_controlled_player(p: CharacterBody3D) -> void:
	controlled_player = p
	_sync_ai_controllers()


## Глушим/возвращаем полевой ИИ на время пенальти/штрафного (вратаря НЕ трогаем — он должен
## нырять/реагировать). Тонкая обёртка над _set_ai_frozen — раньше это была отдельная слабая
## реализация (только по паре именованных игроков, без лока мотора), из-за чего ИИ-соперник
## (и любые другие team_1/team_2, напр. конвертированные штрафным тела) при старте штрафного
## НЕ останавливался: их PlayerMotor — отдельный узел со своим _physics_process, отключение
## ТОЛЬКО скрипта ИИ не мешало мотору доигрывать последнее заданное направление движения —
## соперник продолжал бежать к мячу/игроку сквозь всю расстановку.
func set_field_ai_active(on: bool) -> void:
	_set_ai_frozen(not on, _keeper)


## Останавливаем/возвращаем ИИ-игроков (team_1+team_2) в чистый idle. `keep_active` (если
## задан — вратарь для пенальти/штрафного) НЕ трогаем НИКОГДА, ни на заморозке, ни на
## разморозке: он сам управляет своим локом/мотором во время нырка (manual move_and_collide,
## мотор залочен на время дива, как у слайд-тэкла — см. CLAUDE.md), и наш безусловный
## set_control_locked(false) на разморозке посреди чужого нырка столкнул бы мотор с ручным
## движением. Отключаем скрипт-логику и лочим мотор в 0, чтобы остаточная скорость не тащила
## тело дальше по инерции (сам скрипт ИИ — отдельный узел от PlayerMotor, отключения
## физпроцесса скрипта недостаточно, мотор продолжит доигрывать последний intent, если явно
## его не залочить).
## ВАЖНО: controlled_player исключаем ТОЛЬКО на заморозке (on=true) — на разморозке (on=false)
## снимаем со ВСЕХ (кроме keep_active) безусловно. Между заморозкой (на голе/сет-писе) и
## разморозкой controlled_player может измениться (напр. сброс после гола всегда переключает
## на _human_player) — если бы разморозка тоже исключала «текущего», игрок, залоченный на
## заморозке, но ставший controlled_player к моменту разморозки, остался бы залоченным
## навсегда (мотор игнорирует ввод, маркер выбран, но тело не бежит). Разморозка чужого/не-AI
## тела безвредна — его собственный скрипт self-гейтится по `controlled_player == self`.
func _set_ai_frozen(on: bool, keep_active: Node = null) -> void:
	var bodies := get_tree().get_nodes_in_group("team_1")
	bodies += get_tree().get_nodes_in_group("team_2")
	for n in bodies:
		if not is_instance_valid(n) or n == keep_active:
			continue   # keep_active (вратарь) не трогаем НИКОГДА — сам управляет своим локом/мотором
		if on and n == controlled_player:
			continue
		_ai_of(n).set_physics_process(not on)
		var m := PlayerMotor.find_on(n)
		if m != null:
			m.set_control_locked(on)
			if on:
				m.set_move_intent(Vector3.ZERO)
		if on:
			for c in n.get_children():
				if c is PlayerVisual:
					c.cancel_action()
					c.recover()
					break


## Вратарь соперника в атакуемых человеком воротах (Away, +field_length).
func _setup_keeper() -> void:
	var goal_line_z := -field_length   # ворота Home на -field_length
	var into_field := 1.0 if goal_line_z < 0.0 else -1.0
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_2"
	cfg.role = PlayerConfig.Role.GK
	cfg.kit_color = Color(0.15, 0.7, 0.15)   # вратарь — зелёный
	cfg.spawn_pos = Vector3(0, 0.5, goal_line_z + into_field * 0.5)
	cfg.display_name = "Keeper"
	cfg.ai_script = preload("res://scripts/ai/keeper_ai.gd")
	cfg.connect_action_signals = false        # keeper_ai сам коннектит visual.action_contact
	cfg.locomotion_style = PlayerVisual.LOCO_STYLE_KEEPER
	var k := PlayerFactory.spawn(cfg, _team_away)
	var kb: Node = k.brain()                    # keeper теперь Brain-компонент
	# --- keeper-специфичные узлы (не входят в общий player.tscn) — на ТЕЛО (transform) ---
	var save_area := Area3D.new()
	save_area.name = "SaveArea"
	var sacol := CollisionShape3D.new()
	var sashape := SphereShape3D.new()
	sashape.radius = FootballConstants.KEEPER_REACH
	sacol.shape = sashape
	sacol.position = Vector3(0, FootballConstants.KEEPER_SAVE_AREA_Y, 0)
	save_area.add_child(sacol)
	save_area.collision_mask = 1   # только мяч (слой 1)
	k.add_child(save_area)
	var hold_point := Node3D.new()
	hold_point.name = "HoldPoint"
	hold_point.position = Vector3(0, 1.0, -0.45)
	k.add_child(hold_point)
	# keeper-поля (ball уже проставлен фабрикой) — на МОЗГ
	kb.goal_line_z = goal_line_z
	kb.save_area = save_area
	kb.hold_point = hold_point
	kb.manager = self
	_keeper = k
	_keeper_brain = kb


func _setup_away_player() -> void:
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_2"
	cfg.role = PlayerConfig.Role.FWD
	cfg.kit_color = Color(0.9, 0.1, 0.1)
	cfg.spawn_pos = Vector3(0, 0.5, -45)   # глубоко у защищаемых ворот (−Z): ~45 м разбега человеку
	cfg.display_name = "PlayerAway"
	cfg.ai_script = preload("res://scripts/ai/simple_ai.gd")
	cfg.connect_action_signals = true
	cfg.extra_fields = {
		&"home_goal": ($GoalHome/GoalArea if has_node("GoalHome/GoalArea") else null),
	}
	PlayerFactory.spawn(cfg, _team_away)
	# Тестовая стенка из бездействующих соперников (только пока соперник отключён флагом) —
	# удобно проверять удары/блоки. Вернём настоящего соперника → флаг false → стенки нет.
	if FootballConstants.DEBUG_DISABLE_OPPONENT:
		_spawn_wall_dummies()


## Соперник-полевой по умолчанию (первый не-вратарь team_2). До 11×11 их немного.
func _away_outfielder() -> CharacterBody3D:
	for b in _team_away.outfield():
		return b
	return null


## Стенки из стоящих болванок team_2 (для теста ударов/блоков). Требует
## DEBUG_DISABLE_OPPONENT=true (иначе они бы стали активным ИИ).
func _spawn_wall_dummies() -> void:
	_spawn_wall_line(Vector3(0.0, 0.5, -13.0), 2.0)    # разреженная (с зазорами), центр X=0
	_spawn_wall_line(Vector3(15.0, 0.5, -13.0), 0.62)  # плотная (болванки вплотную), центр X=15


## 4 болванки в линию по X, центрированы, с интервалом spacing (м).
func _spawn_wall_line(center: Vector3, spacing: float) -> void:
	for i in range(4):
		var offset := (float(i) - 1.5) * spacing
		_make_dummy_opponent(center + Vector3(offset, 0.0, 0.0))


func _make_dummy_opponent(pos: Vector3) -> void:
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_2"
	cfg.role = PlayerConfig.Role.DEF
	cfg.kit_color = Color(0.9, 0.1, 0.1)
	cfg.spawn_pos = pos
	cfg.display_name = "WallDummy"
	cfg.ai_script = preload("res://scripts/ai/simple_ai.gd")
	cfg.connect_action_signals = true
	cfg.extra_fields = {
		&"home_goal": ($GoalHome/GoalArea if has_node("GoalHome/GoalArea") else null),
	}
	PlayerFactory.spawn(cfg, _team_away)


func _setup_teammate() -> void:
	if FootballConstants.DEBUG_DISABLE_TEAMMATE:
		return   # ВРЕМЕННО: тиммейт отключён (тест вратаря) → не спавнится
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_1"
	cfg.role = PlayerConfig.Role.MID
	cfg.kit_color = Color(0.1, 0.1, 0.9)
	cfg.spawn_pos = Vector3(10, 0.5, 5)
	cfg.display_name = "PlayerTeammate"
	cfg.ai_script = preload("res://scripts/ai/teammate_ai.gd")
	cfg.connect_action_signals = true
	cfg.extra_fields = {
		&"controlled_player": controlled_player,
		&"teammate_home_goal": ($GoalAway/GoalArea if has_node("GoalAway/GoalArea") else null),
	}
	var new_player := PlayerFactory.spawn(cfg, _team_home)
	# DEBUG: соперник опекает именно этого тиммейта.
	if FootballConstants.DEBUG_MARK_TEAMMATE:
		var opp := _away_outfielder()
		if opp != null and is_instance_valid(opp):
			_ai_of(opp).set(&"mark_target", new_player)


func _process(delta: float) -> void:
	var ball_pos := ball.global_position
	# DEBUG: 1 = обычная broadcast-камера, 3 = вид от 3-го лица за управляемым игроком (удобнее тестить).
	if Input.is_action_just_pressed(&"camera_broadcast"):
		_third_person_camera = false
	elif Input.is_action_just_pressed(&"camera_third_person"):
		_third_person_camera = true

	# Пенальти/штрафной — свои фикс-камеры от 3-го лица за бьющим (см. соответствующие
	# контроллеры). Обычная игра — ТВ-трансляция: фикс. позиция сбоку и сверху поля, плавно
	# панорамирует за МЯЧОМ (не за игроком), а не следует от 3-го лица за спиной игрока —
	# если только не включён DEBUG-вид от 3-го лица (кнопка 3).
	if _penalty_active:
		camera_pivot.global_transform = _penalty_cam_pose
	elif _free_kick_active:
		camera_pivot.global_transform = _free_kick_cam_pose
	elif _corner_active:
		camera_pivot.global_transform = _corner_cam_pose
	elif _goal_kick_active:
		camera_pivot.global_transform = _goal_kick_cam_pose
	elif _throw_in_active:
		camera_pivot.global_transform = _throw_in_cam_pose
	elif _third_person_camera and controlled_player != null:
		var forward := -controlled_player.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized() if forward.length() > 0.001 else Vector3(0, 0, -1)
		var target_eye := controlled_player.global_position - forward * FootballConstants.CAMERA_TP_DISTANCE \
			+ Vector3.UP * FootballConstants.CAMERA_TP_HEIGHT
		var target_look := controlled_player.global_position + forward * FootballConstants.CAMERA_TP_LOOK_AHEAD
		_tp_cam_eye = _tp_cam_eye.lerp(target_eye, clampf(FootballConstants.CAMERA_TP_FOLLOW * delta, 0.0, 1.0))
		camera_pivot.global_position = _tp_cam_eye
		camera_pivot.look_at(target_look, Vector3.UP)
	else:
		_bc_cam_eye_z = lerpf(_bc_cam_eye_z, ball_pos.z, clampf(FootballConstants.CAMERA_BC_FOLLOW * delta, 0.0, 1.0))
		var eye := Vector3(FootballConstants.CAMERA_BC_X, FootballConstants.CAMERA_BC_HEIGHT, _bc_cam_eye_z)
		var look := Vector3(ball_pos.x, FootballConstants.CAMERA_BC_LOOK_Y, ball_pos.z)
		camera_pivot.global_position = eye
		camera_pivot.look_at(look, Vector3.UP)

	if _trail != null:
		_update_ball_trail(ball_pos)

	# Удар от ворот — бьёт вратарь, а controlled_player намеренно не трогаем (см. GoalKickController).
	# Маркер контролируемого игрока на время розыгрыша просто скрываем — он не про вратаря и не
	# про controlled_player (человек не переключался), показывать его тут нечего.
	if _goal_kick_active or _throw_in_active:
		if _controlled_marker != null:
			_controlled_marker.visible = false
	elif _controlled_marker != null and controlled_player and _match_camera != null:
		var marker_world_pos := controlled_player.global_position + Vector3(0, 2.2, 0)
		if _match_camera.is_position_behind(marker_world_pos):
			_controlled_marker.visible = false
		else:
			_controlled_marker.visible = true
			_controlled_marker.position = _match_camera.unproject_position(marker_world_pos)

	# Заряд: копим, пока держим кнопку заряжаемого действия. Во время пенальти/штрафного баром
	# владеет соответствующий контроллер — не трогаем (иначе он тут же гасится каждый кадр).
	if not _penalty_active and not _free_kick_active and not _corner_active and not _goal_kick_active and not _throw_in_active:
		if _is_charging() and _charge_player == controlled_player:
			var is_shot: bool = _charge_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]
			var max_time := KICK_CHARGE_MAX_TIME if is_shot else FootballConstants.PASS_CHARGE_MAX_TIME
			_charge_time += get_process_delta_time()
			if _charge_time >= max_time:
				_charge_time = max_time
				if _is_queued():
					_stop_queue_fix_ratio()  # мяч не у ног — фиксируем силу на макс., ждём касания
				else:
					_fire_charge()
			if _is_charging():
				var ratio := clampf(_charge_time / max_time, 0.0, 1.0)
				power_bar.value = ratio
				var fill := power_bar.get_theme_stylebox("fill")
				if fill:
					fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		elif _is_charging():
			_cancel_charge()
		power_bar.visible = (_is_charging() and _charge_player == controlled_player) \
			or (_is_queued() and _queue_player == controlled_player)



func _physics_process(delta: float) -> void:
	# Пенальти-режим: всё ведёт контроллер, обычные системы заглушены.
	if _penalty_active:
		_penalty.update(delta)
		return
	# Пенальти по P — только из чистого состояния: во время празднования гола ждёт отложенный
	# _reset_ball() (телепорт игроков/мяча), запуск пенальти в это окно ломает расстановку.
	if Input.is_action_just_pressed(&"penalty_debug") and _keeper != null and not _celebrating:
		_penalty.start_single(controlled_player, _keeper_brain.goal_line_z)
		return
	# Штрафной-режим: всё ведёт контроллер, обычные системы заглушены.
	if _free_kick_active:
		_free_kick.update(delta)
		return
	# Штрафной по F — только из чистого состояния (не во время празднования гола).
	if Input.is_action_just_pressed(&"free_kick_debug") and _keeper != null and not _celebrating:
		_free_kick.start(controlled_player, _keeper_brain.goal_line_z)
		return
	# Угловой-режим: всё ведёт контроллер, обычные системы заглушены.
	if _corner_active:
		_corner.update(delta)
		return
	# Угловой по C — только из чистого состояния (не во время празднования гола).
	if Input.is_action_just_pressed(&"corner_debug") and _keeper != null and not _celebrating:
		_corner.start(controlled_player, _keeper_brain.goal_line_z)
		return
	# Удар от ворот — свой контроллер, обычные системы заглушены.
	if _goal_kick_active:
		_goal_kick.update(delta)
		return
	# Удар от ворот по G — только из чистого состояния (не во время празднования гола). Бьющий —
	# ВРАТАРЬ (_keeper), не controlled_player: человек драйвит вратаря на время розыгрыша.
	if Input.is_action_just_pressed(&"goal_kick_debug") and _keeper != null and not _celebrating:
		_goal_kick.start(_keeper, _keeper_brain.goal_line_z)
		return
	# Вброс из аута — свой контроллер, обычные системы заглушены.
	if _throw_in_active:
		_throw_in.update(delta)
		return
	# Вброс по T — только из чистого состояния (не во время празднования гола).
	if Input.is_action_just_pressed(&"throw_in_debug") and not _celebrating:
		_throw_in.start()
		return
	# Одно касание: если действие в очереди и игрок дотянулся — бьём вместо трапа/дриблинга.
	if _try_fire_queue():
		_handle_player_input(delta)
		return
	_handle_dribbling()
	_handle_player_input(delta)

	# Auto-switch to whoever on our team has the ball (skip if Q was just pressed)
	if _manual_swap_cooldown > 0:
		_manual_swap_cooldown -= 1
	else:
		if ball.has_method(&"set_dribbler") and ball.dribbler:
			var db: Node3D = ball.dribbler
			# Под управлением всегда тот из НАШЕЙ команды, у кого мяч (любой team_1, включая
			# заспавненных штрафным тиммейтов), а не только пары именованных игроков.
			if db != controlled_player and db.is_in_group("team_1"):
				controlled_player = db
				_sync_ai_controllers()

	# Смена игрока — только в ЗАЩИТЕ: мяч не у нас И (им владеет соперник ИЛИ соперник ближе к мячу).
	# Иначе рывок-брейк-эвей (мяч вырвался в спринте, но мы к нему ближе всех — он всё ещё наш) по
	# combo_modifier ошибочно переключал управление на тиммейта. В атаке combo_modifier = модификатор
	# паса/удара, не свап. Переключаем на БЛИЖАЙШЕГО к мячу из team_1; если он уже выбран — на второго.
	var opp_has_ball: bool = ball.has_method(&"set_dribbler") and ball.dribbler and ball.dribbler.is_in_group("team_2")
	if Input.is_action_just_pressed(&"combo_modifier") and not _we_possess() \
			and (opp_has_ball or _opponent_closer_to_ball(controlled_player)):
		var team := get_tree().get_nodes_in_group("team_1")
		if team.size() > 1:
			var ball_pos := ball.global_position
			var sorted: Array = team.duplicate()
			sorted.sort_custom(func(a, b):
				return a.global_position.distance_squared_to(ball_pos) < b.global_position.distance_squared_to(ball_pos))
			var target = sorted[0]
			if target == controlled_player and sorted.size() > 1:
				target = sorted[1]
			controlled_player = target
			_sync_ai_controllers()
			_manual_swap_cooldown = 10

	# Соперник целится в того из НАШЕЙ команды, кто дриблит (по группе, не по именам).
	var opp := _away_outfielder()
	if opp != null:
		var opp_ai := _ai_of(opp)
		if ball.has_method(&"set_dribbler") and ball.dribbler and ball.dribbler.is_in_group("team_1"):
			opp_ai.target_node = ball.dribbler
		else:
			opp_ai.target_node = null

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

	# Очередь «в одно касание»: тикаем таймаут и сбрасываем по невалидности/смене/потере мяча.
	# taken_by_other = мяч успел забрать кто-то другой (соперник ИЛИ партнёр) → мы НЕ добрались
	# первыми → отменяем удар (правило спорного мяча).
	if _is_queued():
		_queue_timer -= delta
		var taken_by_other: bool = ball.has_method(&"set_dribbler") and ball.dribbler != null and ball.dribbler != _queue_player
		if _queue_timer <= 0.0 \
				or _queue_player != controlled_player or not is_instance_valid(_queue_player) \
				or _queue_player.is_in_group("fallen") \
				or taken_by_other:
			_clear_queue()


## Плоский UI-маркер контролируемого игрока — CanvasLayer + Polygon2D-треугольник, а НЕ 3D-меш
## (тот отбрасывал тень на газон, выглядело странно). Позиционируется каждый рендер-кадр через
## Camera3D.unproject_position() (world -> screen), поверх головы игрока.
func _setup_controlled_indicator() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var marker := Polygon2D.new()
	marker.polygon = PackedVector2Array([Vector2(-2.67, -4.67), Vector2(2.67, -4.67), Vector2(0, 0.67)])
	marker.color = Color(0.3, 0.6, 1.0)
	layer.add_child(marker)
	_controlled_marker = marker



func _sync_ai_controllers() -> void:
	# Все team_1 с полем controlled_player (включая фабричных home/teammate и заспавненных
	# штрафным) синхронизируются, чтобы управляемое тело пропускало свой ИИ (гейт self==controlled).
	for n in get_tree().get_nodes_in_group("team_1"):
		var ai := _ai_of(n)
		if &"controlled_player" in ai:
			ai.controlled_player = controlled_player


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
		# Владение НЕ теряется от собственного толчка/резкого поворота — только по внешнему
		# фактору (подкат/перехват, они зовут release_dribble отдельно). Дистанционный сброс —
		# лишь страховка для реально улетевшего мяча (порог выше макс. ролл-дистанции толчка).
		if dist > FootballConstants.DRIBBLE_KEEP_DIST:
			ball.release_dribble()
		return
	# Адресат паса ловит мяч НЕЗАВИСИМО от скорости (это пас НА него) — иначе быстрый пас в
	# ноги проносит мимо и приходится разворачиваться. Гейт скорости ниже к нему не применяем.
	# Приём в широком радиусе; трап тут же выключит коллизию мяча, не дав ему отскочить от капсулы.
	if _receive_active and is_instance_valid(_receiver):
		var recv_dist: float = _receiver.global_position.distance_to(ball.global_position)
		if recv_dist < FootballConstants.PASS_RECEIVE_CATCH_RADIUS:
			ball.set_dribbler(_receiver, true)  # force: минуем кулдаун релиза (короткий пас доходит <500мс)
			if _ai_of(_receiver).has_method(&"end_receiving"):
				_ai_of(_receiver).end_receiving()
			return
	# Прочий подбор (бесхозный/остановившийся мяч) — только медленный: быстрый мяч «в полёте».
	if ball.linear_velocity.length() > FootballConstants.BALL_TRAP_MAX_SPEED:
		return
	# Перебираем ВСЕХ полевых (team_1+team_2, кроме вратаря — у него свой захват в руки), а не
	# жёсткий список именованных игроков: иначе заспавненные штрафным тела
	# (получатель паса/навеса после истечения окна приёма) добегают к мячу, но подобрать некому.
	var pickers := get_tree().get_nodes_in_group("team_1")
	pickers += get_tree().get_nodes_in_group("team_2")
	for p in pickers:
		if not is_instance_valid(p) or p == _keeper:
			continue
		var dist: float = p.global_position.distance_to(ball.global_position)
		if dist < 1.0:
			ball.set_dribbler(p)
			if _ai_of(p).has_method(&"end_receiving"):
				_ai_of(p).end_receiving()
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
	if _action_executor.action_player() == controlled_player and not _action_executor.is_kick_action_active():
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
		var rp := PassSystem.receive_point(controlled_player.global_position, ball.global_position,
			ball.linear_velocity, FootballConstants.PASS_RECEIVE_LEAD_TIME, FootballConstants.PASS_RECEIVE_ONLINE_DOT)
		var db := rp - controlled_player.global_position
		db.y = 0.0
		if db.length() > 0.01:
			dir = db.normalized()
	# Очередь «в одно касание» на СПОРНЫЙ/ничейный мяч: пока ждём касания, автоматически бежим к
	# мячу (прогноз позиции), даже если стик отпущен. Пас на нас уже ведёт receive-assist выше;
	# свой спринт-отрыв уже ведёт chasing-блок ниже (мяч ещё наш, дриблер = controlled_player) —
	# там же живёт DRIBBLE_CHASE_STEER-блендинг стика, который эта ветка НЕ должна перебивать
	# (иначе `stick := dir` в дриблинг-блоке подменит настоящий ввод игрока нашим авто-курсом).
	if _is_queued() and _queue_player == controlled_player and is_instance_valid(ball) \
			and not (_receive_active and _receiver == controlled_player) \
			and ball.player() != controlled_player:
		var qb := (ball.global_position + ball.linear_velocity * FootballConstants.PASS_RECEIVE_PREDICT_WINDOW) - controlled_player.global_position
		qb.y = 0.0
		if qb.length() > 0.01:
			dir = qb.normalized()
	# Дриблинг: стик задаёт направление ТОЛЧКА мяча, а бег авто-направляется К МЯЧУ —
	# игрок толкает мяч в сторону стика и сам бежит его догонять (аркадная петля). Толчок
	# по intent'у делает ball_controller в момент «догнал».
	if is_instance_valid(ball) and ball.has_method(&"set_dribble_intent") and ball.player() == controlled_player:
		var stick := dir
		var active := stick.length() > 0.2  # человек активно ведёт (стик нажат)
		var chasing: bool = ball.has_method(&"should_chase") and ball.should_chase()
		# Толкать мяч — только пока человек активно ведёт (плюс подавление на зарядке/commit
		# паса-удара). Отпустил стик → толчок подавлен: игрок добегает к мячу и ОСТАНАВЛИВАЕТСЯ,
		# а не продолжает дриблить по остаточной скорости.
		if ball.has_method(&"set_dribble_suppressed"):
			ball.set_dribble_suppressed(_is_charging() or _action_executor.is_kick_action_active() or not active)
		# Стик задаёт направление следующего толчка (intent) + доп. силу спринта.
		if active:
			var sprint_now := Input.get_action_strength(&"sprint")
			ball.set_dribble_intent(stick, FootballConstants.DRIBBLE_SPRINT_PUSH_EXTRA * sprint_now)
		if chasing:
			# ДОГОН (мяч вырвался): ведём к мячу, но стик может ПОДРУЛИТЬ (обойти соперника на
			# пути), не теряя мяч — блёнд DRIBBLE_CHASE_STEER. Стик отпущен → строго к мячу.
			var to_ball := ball.global_position - controlled_player.global_position
			to_ball.y = 0.0
			if to_ball.length() > 0.01:
				var chase_dir := to_ball.normalized()
				if active:
					var w := FootballConstants.DRIBBLE_CHASE_STEER
					var mixed := chase_dir * (1.0 - w) + stick.normalized() * w
					if mixed.length() > 0.01:
						chase_dir = mixed.normalized()
				dir = chase_dir
		elif active:
			# Мяч у ног: ведём в направлении СТИКА (толкаем сквозь).
			dir = stick.normalized()
		else:
			dir = Vector3.ZERO  # мяч у ног, стик отпущен → стоп

	# Притягивание к НИЧЕЙНОМУ мячу (вне владения): если игрок движется примерно к
	# подбираемому (медленному, бесхозному) мячу поблизости — подруливаем к нему, чтобы не
	# целиться точно и проще подбирать. Сам подбор (трап на <1 м) — как есть, ниже по кадру.
	elif is_instance_valid(ball) and ball.has_method(&"set_dribble_intent") and ball.player() == null \
			and not _receive_active and ball.linear_velocity.length() <= FootballConstants.BALL_TRAP_MAX_SPEED \
			and dir.length() > 0.2:
		var to_ball := ball.global_position - controlled_player.global_position
		to_ball.y = 0.0
		var d := to_ball.length()
		if d > 0.01 and d < FootballConstants.PICKUP_ASSIST_RADIUS:
			var stick_dir := dir.normalized()
			var ball_dir := to_ball.normalized()
			if stick_dir.dot(ball_dir) > 0.0:  # движемся примерно к мячу (в пределах ~90°)
				var strength := clampf(1.0 - d / FootballConstants.PICKUP_ASSIST_RADIUS, 0.0, 1.0) \
					* FootballConstants.PICKUP_ASSIST_STRENGTH
				dir = stick_dir.slerp(ball_dir, strength) * dir.length()

	# Аналоговый спринт: сила триггера (или 1.0 с клавиши Shift) лерпит speed_scale.
	var sprint_strength := Input.get_action_strength(&"sprint")
	var sprint_scale := lerpf(1.0, FootballConstants.LOCO_SPRINT_SPEED / FootballConstants.LOCO_TOP_SPEED, sprint_strength)
	var motor := _player_motor(controlled_player)
	if motor != null:
		motor.set_move_intent(dir, sprint_scale)

	# Kick charge system (OpenSoccer-style)
	if Input.is_action_just_pressed(&"kick"):
		if _is_charging() or _is_queued():
			pass  # уже заряжаем/в очереди, игнор
		elif _is_near_ball(controlled_player) and _is_our_dribbler(controlled_player):
			# E+D → кручёный, Q+D → черпачок, иначе прямой удар (контекст удар/вынос решается в _fire_shot).
			var shot_action := ChargeAction.SHOT
			if Input.is_action_pressed(&"combo_curl"):
				shot_action = ChargeAction.SHOT_CURL
			elif Input.is_action_pressed(&"combo_modifier"):
				shot_action = ChargeAction.SHOT_CHIP
			_start_charge(shot_action, controlled_player)
		elif _can_queue(controlled_player):
			# Мяч не у ног (летит пасом / убежал в спринте / спорный ничейный) — заряжаем в очередь,
			# выстрелит в одно касание, когда игрок дотянется (см. _try_fire_queue).
			var q_action := ChargeAction.SHOT
			if Input.is_action_pressed(&"combo_curl"):
				q_action = ChargeAction.SHOT_CURL
			elif Input.is_action_pressed(&"combo_modifier"):
				q_action = ChargeAction.SHOT_CHIP
			_start_queue_charge(q_action, controlled_player)
		else:
			_try_tackle(controlled_player)

	if Input.is_action_just_released(&"kick") and _charge_player == controlled_player \
			and _charge_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]:
		if _is_queued():
			_stop_queue_fix_ratio()  # мяч ещё не у ног — фиксируем силу, ждём касания
		else:
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
	elif not _is_charging() and not _is_queued() and _can_queue(controlled_player):
		if Input.is_action_just_pressed(&"pass_short"):
			_start_queue_charge(ChargeAction.PASS_WALL if combo else ChargeAction.PASS_SHORT, controlled_player)
		elif Input.is_action_just_pressed(&"pass_through"):
			_start_queue_charge(ChargeAction.PASS_THROUGH_AIR if combo else ChargeAction.PASS_THROUGH, controlled_player)
		elif Input.is_action_just_pressed(&"pass_lob"):
			_start_queue_charge(ChargeAction.PASS_LOB, controlled_player)
	for act in [&"pass_short", &"pass_through", &"pass_lob"]:
		if Input.is_action_just_released(act) and _charge_player == controlled_player \
				and _charge_action != ChargeAction.SHOT and _is_charging():
			if _is_queued():
				_stop_queue_fix_ratio()
			else:
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
	# По группе team_1, а не по именованным игрокам — иначе владение мячом
	# заспавненным штрафным тиммейтом (team_1) не распознавалось, и combo_modifier ошибочно
	# работал как свап игрока вместо модификатора паса.
	return ball.dribbler.is_in_group("team_1")

## Можно ли поставить действие в очередь: мяч НЕ у ног (иначе обычный немедленный заряд) и им
## не владеет кто-то ДРУГОЙ (тогда это территория подката/смены). Источники очереди:
##  - incoming: летит к нам пасом нашей команды (receive-assist),
##  - breakaway: мы дриблер, но мяч убежал вперёд (спринт-отрыв, владение не потеряно),
##  - loose: мяч бесхозный/летящий (dribbler == null) и в разумной близости — СПОРНЫЙ мяч
##    (борьба с соперником). Заряжать можно; удар выполнится, только если добежим первыми
##    (см. отмену taken_by_other и «ближе всех» в _try_fire_queue).
## Есть ли соперник (team_2) СТРОГО ближе к мячу, чем наш игрок. Спорный мяч тогда скорее его —
## на нажатие кнопки логичнее подкат (отобрать), а не заряд удара в очередь.
func _opponent_closer_to_ball(player_node: Node3D) -> bool:
	if player_node == null or not is_instance_valid(player_node):
		return false
	var my_d: float = player_node.global_position.distance_to(ball.global_position)
	for opp in get_tree().get_nodes_in_group("team_2"):
		if opp is Node3D and is_instance_valid(opp) \
				and (opp as Node3D).global_position.distance_to(ball.global_position) < my_d:
			return true
	return false


func _can_queue(player_node: CharacterBody3D) -> bool:
	if player_node == null or not is_instance_valid(player_node):
		return false
	# У ног И мы дриблер → обычный путь (немедленный удар/пас), не очередь. НО «близко к мячу, но
	# ещё НЕ владеем» (принимающий добежал до летящего/ничейного мяча) — это как раз очередь одного
	# касания, не подкат; поэтому near-гейт срабатывает только вместе с владением.
	if _is_near_ball(player_node) and _is_our_dribbler(player_node):
		return false
	if ball.has_method(&"set_dribbler") and ball.dribbler != null and ball.dribbler != player_node:
		return false  # мячом владеет кто-то другой (соперник/партнёр) → подкат/смена, не очередь
	var incoming: bool = _receive_active and _receiver == player_node
	var breakaway: bool = _is_our_dribbler(player_node)
	# Ничейный мяч рядом → очередь одного касания, НО только если соперник не ближе к мячу: если
	# он ближе, спорный мяч скорее его — логичнее подкат (отобрать), а не заряд удара, который всё
	# равно не выстрелит (гейт «добрался первым» в _try_fire_queue) и лишь съест нажатие.
	var loose: bool = (not ball.has_method(&"set_dribbler") or ball.dribbler == null) \
		and player_node.global_position.distance_to(ball.global_position) <= FootballConstants.QUEUE_CONSIDER_RADIUS \
		and not _opponent_closer_to_ball(player_node)
	# Наш мяч в полёте (пас нашей команды, летит) — на ЛЮБОЙ дистанции: принимающий бежит на длинный
	# пас на ход, receive-assist истёк по таймауту, а мяч дальше QUEUE_CONSIDER_RADIUS. Не соперника
	# (last_kicker из team_1) и не свой же удар (last_kicker != этот игрок) → удар в очередь, не подкат.
	var friendly_flight: bool = ball.has_method(&"is_flight") and ball.is_flight() \
		and ball.last_kicker != null and is_instance_valid(ball.last_kicker) \
		and ball.last_kicker.is_in_group("team_1") and ball.last_kicker != player_node
	return incoming or breakaway or loose or friendly_flight

func _start_charge(action: ChargeAction, player_node: CharacterBody3D) -> void:
	_charge_action = action
	_charge_time = 0.0
	_charge_player = player_node
	var dir: Vector3 = ball.get_dribble_direction()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		player_node.rotation.y = atan2(-flat.x, -flat.z)

## Начать заряд «в очередь» (мяч ещё не у ног). Копим силу как обычно (power_bar виден),
## но по касанию будем бить в одно касание, а не сразу. Тело НЕ доворачиваем к мячу
## (get_dribble_direction для не-дриблера бессмыслен — прицел возьмём по facing на касании).
func _start_queue_charge(action: ChargeAction, player_node: CharacterBody3D) -> void:
	_charge_action = action
	_charge_time = 0.0
	_charge_player = player_node
	_queued_action = action
	_queue_player = player_node
	_queue_ratio = 0.0
	_queue_timer = FootballConstants.QUEUE_MAX_TIME

## Отпустили кнопку (или дошли до макс.) ДО касания: фиксируем текущий ratio в очереди и
## гасим активный заряд (шкалу), но очередь остаётся ждать касания.
func _stop_queue_fix_ratio() -> void:
	var is_shot: bool = _queued_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]
	var max_time := KICK_CHARGE_MAX_TIME if is_shot else FootballConstants.PASS_CHARGE_MAX_TIME
	_queue_ratio = clampf(_charge_time / max_time, 0.0, 1.0)
	_cancel_charge()

func _fire_charge() -> void:
	if not _is_charging() or not _charge_player or not is_instance_valid(_charge_player):
		_cancel_charge()
		return
	var action := _charge_action
	var player := _charge_player
	if action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]:
		var ratio := clampf(_charge_time / KICK_CHARGE_MAX_TIME, 0.0, 1.0)
		_cancel_charge()
		_action_executor.fire_shot(action, player, ratio)
	else:
		var charge_ratio := clampf(_charge_time / FootballConstants.PASS_CHARGE_MAX_TIME, 0.0, 1.0)
		_cancel_charge()
		_action_executor.fire_pass(action, player, charge_ratio)


## Удар: контекст решает удар в ворота vs вынос; тип (прямой/кручёный/черпачок) — по action.
## Импульс — через commit-action (ball.launch / launch_curl по action_contact), как у паса.
## Плоская скорость удара НИЗОМ: горизонталь к цели, без вертикали (vy=0) — мяч идёт по газону,
## а не по баллистической дуге. from/aim берём только по X/Z.
func _cancel_charge() -> void:
	_charge_action = ChargeAction.NONE
	_charge_time = 0.0
	_charge_player = null
	power_bar.visible = false

## Сбросить очередь «в одно касание» (перехват/аут/таймаут/смена игрока/падение).
func _clear_queue() -> void:
	_queued_action = ChargeAction.NONE
	_queue_player = null
	_queue_ratio = 0.0
	_queue_timer = 0.0

## Если отложенное действие в очереди и игрок дотянулся до мяча — бьём в одно касание.
## Прицел по facing тела игрока СЕЙЧАС (он ещё не дриблер), сила = заряд + скорость влёта мяча.
## Возвращает true, если в этом кадре выстрелили (тогда обычный трап/дриблинг пропускаем).
func _try_fire_queue() -> bool:
	if not _is_queued():
		return false
	if _queue_player == null or not is_instance_valid(_queue_player):
		_clear_queue()
		return false
	var d: float = _queue_player.global_position.distance_to(ball.global_position)
	if d > FootballConstants.QUEUE_REACH_RADIUS:
		return false  # ещё не дотянулся — ждём (авто-подбегание ведёт игрока к мячу)
	# «Добрался ПЕРВЫМ»: не бьём, если соперник СТРОГО ближе к мячу (спорный мяч он выиграл или
	# вот-вот затрапит → тогда сработает отмена taken_by_other). Так одно касание проходит только
	# при честной победе в борьбе; иначе ждём/сбрасываемся. Соперники — группа "team_2".
	for opp in get_tree().get_nodes_in_group("team_2"):
		if opp is Node3D and is_instance_valid(opp) \
				and (opp as Node3D).global_position.distance_to(ball.global_position) < d:
			return false
	# Дотянулся первым: диспатчим в одно касание.
	var action := _queued_action
	var player := _queue_player
	var base_ratio := _queue_ratio
	# Всё ещё держим кнопку в момент касания → бьём на ТЕКУЩЕМ заряде (не на зафиксированном).
	if _is_charging() and _charge_player == player and _charge_action == action:
		var is_shot: bool = action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]
		var max_time := KICK_CHARGE_MAX_TIME if is_shot else FootballConstants.PASS_CHARGE_MAX_TIME
		base_ratio = clampf(_charge_time / max_time, 0.0, 1.0)
		_cancel_charge()
	var incoming_speed: float = ball.linear_velocity.length()
	var eff_ratio := ShotSystem.one_touch_ratio(base_ratio, incoming_speed, FootballConstants.QUEUE_BALL_SPEED_GAIN)
	var facing: Vector3 = _aim_dir(player)
	_clear_queue()
	if action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]:
		_action_executor.fire_shot(action, player, eff_ratio, facing.normalized())
	else:
		_action_executor.fire_pass(action, player, eff_ratio, facing.normalized())
	return true

## Направление прицела удара/паса: СТИК (камеро-относительный), если реально наклонён — человек
## явно указывает, куда бить/пасовать, даже если тело движется/повёрнуто иначе. Facing тела для
## этого не годится: PlayerMotor разворачивает тело по направлению ДВИЖЕНИЯ, так что facing может
## не совпадать с намерением (напр. бежит вперёд, а пас хочет вбок; или авто-бег к мячу в очереди
## крутит facing). Стик отпущен → фолбэк на facing тела. Общий для пасов (_fire_pass) и очереди
## «в одно касание» (_try_fire_queue).
func _aim_dir(player_node: CharacterBody3D) -> Vector3:
	var input_vec := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if input_vec.length() > 0.2:
		var cam_basis := camera_pivot.global_transform.basis
		var cam_forward := -cam_basis.z
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()
		var cam_right := cam_basis.x
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		var d := (cam_forward * -input_vec.y + cam_right * input_vec.x)
		if d.length() > 0.01:
			return d.normalized()
	var facing := -player_node.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		return facing.normalized()
	return Vector3.FORWARD


## Момент касания ногой (сигнал PlayerVisual, проводится фабрикой) → в ActionExecutor.
func _on_action_contact(action: String, player: Node) -> void:
	_action_executor.on_action_contact(action, player)


## Действие завершилось (сигнал PlayerVisual) → в ActionExecutor.
func _on_action_finished(action: String, player: Node) -> void:
	_action_executor.on_action_finished(action, player)


## Отменить действие игрока (сбили подкатом на замахе) → в ActionExecutor.
func _cancel_ball_action(player: Node) -> void:
	_action_executor.cancel_action(player)


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


## «ИИ-объект этого тела»: дочерний Brain-компонент, либо само тело (легаси set_script / без ИИ).
## Единственная точка, где менеджер дотягивается до полей/методов ИИ — работает одинаково для
## компонентных и легаси-тел, поэтому конверсию ИИ можно делать по одному, не ломая менеджер.
func _ai_of(body: Node) -> Node:
	if body != null and body.has_method(&"brain"):
		var b: Node = body.brain()
		if b != null:
			return b
	return body


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
	# Уровень газона жертвы: пиним Y на всё падение (мотор в fallen гравитацию НЕ применяет,
	# а _process_fall двигает только горизонталь — без пина приподнятое при контакте тело
	# зависает в воздухе на всю анимацию). Газон плоский, высота стойки = spawn-y (home_pos).
	var _fall_home: Vector3 = body.get_meta(&"home_pos", body.global_position)
	_fall_ground_y = _fall_home.y
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
	# Держим тело на газоне: перекаты/отброс — только горизонталь; вертикаль (лежит/встаёт)
	# делает клип, а физика в fallen Y не трогает. Без пина приподнятое при контакте тело зависло бы.
	_fall_player.global_position.y = _fall_ground_y

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
	if _queue_player == _fall_player:
		_clear_queue()
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
	# Любой контакт мяча с игроком (стенка/защитник/вратарь) нарушает траекторию — сбрасываем
	# кручение сразу и безусловно (не только в FLIGHT-ветке block_in_flight ниже), иначе Magnus
	# продолжает крутить уже отскочивший мяч (виден как «кружение на месте»).
	if body is CharacterBody3D and (body.is_in_group("team_1") or body.is_in_group("team_2")) \
			and ball.has_method(&"clear_curl"):
		ball.clear_curl()
	# Мяч коснулся вратаря → ловля/отбой (а не блок): иначе block_in_flight гасит мяч, и он
	# закатывается в ворота. Физический контакт — надёжный триггер сейва.
	if body == _keeper and _keeper_brain != null and _keeper_brain.has_method(&"on_ball_contact"):
		print("[MATCH] ball hit KEEPER capsule")
		_keeper_brain.on_ball_contact()
		return
	# Блок: летящий мяч коснулся игрока (защитник на пути / попал в своего). Гасим и роняем
	# мяч в OPEN (без мгновенной передачи владения — дальше обычная борьба за подбор).
	if body is CharacterBody3D and (body.is_in_group("team_1") or body.is_in_group("team_2")) \
			and ball.has_method(&"is_flight") and ball.is_flight() and ball.has_method(&"block_in_flight"):
		print("[MATCH] block_in_flight by ", body.name, " kicker=", ball.last_kicker)
		ball.block_in_flight()


func _reset_ball() -> void:
	if ball.has_method(&"release_dribble"):
		ball.release_dribble()
	if ball.has_method(&"clear_last_kicker"):
		ball.clear_last_kicker()
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = Vector3(0, 0.5, -0.6)

	# Возврат игроков на стартовые позиции — по ростеру обеих команд (home_pos из фабрики).
	# Вратарь НЕ сбрасывается (как и раньше) — он держит свою позицию через keeper_ai.
	for body in _team_home.players() + _team_away.outfield():
		if is_instance_valid(body):
			body.global_position = body.get_meta(&"home_pos", body.global_position)

	controlled_player = _human_player
	_sync_ai_controllers()


## Пауза празднования: мяч гаснет в сетке (колыхание идёт), через
## NET_CELEBRATION_TIME сброс мяча и остановка симуляции. Не await-им игроков —
## по решению ничего не замораживаем. Не await-ит вызывающий (fire-and-forget).
func _celebrate_then_reset(net) -> void:
	await get_tree().create_timer(FootballConstants.NET_CELEBRATION_TIME).timeout
	_reset_ball()
	if net and is_instance_valid(net):
		net.stop_sim()
	_celebrating = false
	_set_ai_frozen(false, _keeper)   # возвращаем ИИ в игру (вратаря не трогали — он сам собой управлял)


func _poll_ai_tackles() -> void:
	# Во время празднования гола новые подкаты НЕ стартуют. Иначе соперник-ИИ добивает забившего
	# слайдом посреди празднования (падение + анимация вставания) — заметнее всего на голе со
	# штрафного/пенальти, где мяч и забивший остаются в штрафной. Подкат стартует МЕНЕДЖЕР (не мозг
	# ИИ), поэтому одной заморозки ИИ мало — нужен явный гейт здесь. Снимется на _reset_ball.
	if _celebrating:
		return
	for node in get_tree().get_nodes_in_group("team_2"):
		if not is_instance_valid(node):
			continue
		var ai := _ai_of(node)
		if "wants_to_tackle" in ai and ai.wants_to_tackle:
			_start_tackle(node)          # подкат берёт ТЕЛО (node), не мозг
			ai.wants_to_tackle = false

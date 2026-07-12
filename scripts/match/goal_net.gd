extends MeshInstance3D
## Объёмная сетка ворот: процедурная решётка узлов-масс (NetSim), Verlet-колыхание
## при голе, рендер линиями через ImmediateMesh. Строится в локальном пространстве
## (устье при z=0, глубина уходит в локальный +z); ориентацию под сторону поля
## задаёт rotation.y снаружи (PI для Home, 0 для Away).

const NetSim = preload("res://scripts/match/net_sim.gd")

var ball: RigidBody3D
var _net: Dictionary
var _params: Dictionary
var _sim := false
var _im: ImmediateMesh
var _mat: StandardMaterial3D

func initialize(ball_ref: RigidBody3D) -> void:
	ball = ball_ref
	var C := FootballConstants
	_net = NetSim.build_box_net(C.GOAL_WIDTH, C.GOAL_HEIGHT, C.NET_DEPTH,
		C.NET_WIDTH_DIV, C.NET_HEIGHT_DIV, C.NET_DEPTH_DIV)
	_params = {
		"gravity": C.NET_GRAVITY,
		"damping": C.NET_DAMPING,
		"stiffness": C.NET_SPRING_STIFFNESS,
		"shape_return": C.NET_SHAPE_RETURN,
		"ball_radius": C.NET_BALL_RADIUS,
		"ball_vel_scale": C.NET_BALL_VEL_SCALE,
		"ball_force": C.NET_BALL_FORCE,
		"ball_min_speed": C.NET_BALL_MIN_SPEED,
		"constraint_iterations": C.NET_CONSTRAINT_ITERATIONS,
	}
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1, 1, 1, 0.55)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_im = ImmediateMesh.new()
	mesh = _im
	material_override = _mat
	set_physics_process(false)
	_redraw()

func start_sim() -> void:
	_sim = true
	set_physics_process(true)

func stop_sim() -> void:
	_sim = false
	set_physics_process(false)
	var rest: PackedVector3Array = _net["rest"]
	_net["pos"] = rest.duplicate()
	_net["prev"] = rest.duplicate()
	_redraw()

func _physics_process(_delta: float) -> void:
	if not _sim or ball == null or not is_instance_valid(ball):
		return
	var ball_local := to_local(ball.global_position)
	var ball_speed := ball.linear_velocity.length()
	NetSim.integrate(_net, ball_local, ball_speed, _params, FootballConstants.NET_SIM_STEP)
	_redraw()

func _redraw() -> void:
	var pos: PackedVector3Array = _net["pos"]
	var edges: PackedInt32Array = _net["edges"]
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	var e := edges.size() / 2
	for k in range(e):
		_im.surface_add_vertex(pos[edges[k * 2]])
		_im.surface_add_vertex(pos[edges[k * 2 + 1]])
	_im.surface_end()

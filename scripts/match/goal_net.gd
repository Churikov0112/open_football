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
	# Прямой FootballConstants.X (статический резолв константы), НЕ `var C := FootballConstants`:
	# алиас автозагрузки-как-ЗНАЧЕНИЯ не резолвится при -s-компиляции по цепочке зависимостей
	# (класс грузится раньше регистрации автозагрузки) — ломал любой -s-тест с компайл-тайм
	# ссылкой на MatchManager (напр. check_action_executor). Статический доступ к const этого не имеет.
	_net = NetSim.build_box_net(FootballConstants.GOAL_WIDTH, FootballConstants.GOAL_HEIGHT, FootballConstants.NET_DEPTH,
		FootballConstants.NET_WIDTH_DIV, FootballConstants.NET_HEIGHT_DIV, FootballConstants.NET_DEPTH_DIV, FootballConstants.NET_SLACK)
	_params = {
		"gravity": FootballConstants.NET_GRAVITY,
		"damping": FootballConstants.NET_DAMPING,
		"stiffness": FootballConstants.NET_SPRING_STIFFNESS,
		"shape_return": FootballConstants.NET_SHAPE_RETURN,
		"ball_radius": FootballConstants.NET_BALL_RADIUS,
		"ball_vel_scale": FootballConstants.NET_BALL_VEL_SCALE,
		"ball_force": FootballConstants.NET_BALL_FORCE,
		"ball_min_speed": FootballConstants.NET_BALL_MIN_SPEED,
		"constraint_iterations": FootballConstants.NET_CONSTRAINT_ITERATIONS,
		"constraint_stiffness": FootballConstants.NET_STIFFNESS,
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

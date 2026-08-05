extends SceneTree

# Сцена `stadium_lab` целиком: стадион из `.glb` под `GpfSpace` в осях оригинала, материалы
# из `.ase` назначены НА САМОЙ СЦЕНЕ (а не только в юнит-проверке загрузчика), игрок и мяч
# ядра порта живут в сцене и двигаются от шага оркестратора.
#
# Это smoke-тест сборки сцены, а не приёмка картинки: как выглядит стадион, headless не видит —
# это глазной чек-лист тикета 10.

const LAB := "res://scenes/lab/stadium_lab.tscn"

# Габарит стадиона, снятый с `*MESH_VERTEX` test.ase (тот же, что проверяет check_gpf_stadium).
const HALF_X := 104.015
const HALF_Y := 84.015
const TOP_Z := 39.0
const EPS := 0.01

# 31 материал стадиона + 4 квадранта поля + 2 материала ворот + 1 мяч.
const EXPECTED_MESHES := 38

var _fails := 0


func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("  FAIL: ", msg)


func feq(a: float, b: float, eps := EPS) -> bool:
	return absf(a - b) < eps


func _find(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for child in node.get_children():
		var found := _find(child, name)
		if found != null:
			return found
	return null


# Трансформ узла относительно `GpfSpace`: геометрия обязана лежать в координатах оригинала
# именно ПОД обёрткой, конверсию осей делает её базис, а не сами меши.
func _xform_under(node: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _collect_models(node: Node, space: Node, out: Array) -> void:
	if node is MeshInstance3D and node.name.begins_with("mat"):
		out.append({"node": node, "xform": _xform_under(node as Node3D, space)})
	for child in node.get_children():
		_collect_models(child, space, out)


# Сколько физических тиков дать оркестратору отработать САМОМУ, прежде чем спрашивать
# состояние. Ядро гонит его собственный _PhysicsProcess, а не этот скрипт: тик гуманоида
# аллоцирует RefCounted (CrudeSelectionQuery), и массовый вызов StepOneFrame из GDScript
# роняет маршалинг Godot.NET примерно на каждом третьем прогоне.
const RUN_TICKS := 300

var _lab: Node = null
var _phase := 0
var _until_frame := 0
var _start_player := Vector3.ZERO
var _start_ball := Vector3.ZERO


# Сцену добавляем в дерево здесь, а проверяем на первом кадре: `_Ready` оркестратора корень
# откладывает до начала кадра, и в `_initialize` сцена ещё пуста.
func _initialize() -> void:
	print("== check_gpf_stadium_lab ==")

	if not ResourceLoader.exists(LAB):
		_fail("нет сцены %s" % LAB)
		_done()
		return

	_lab = (load(LAB) as PackedScene).instantiate()
	get_root().add_child(_lab)


# Возвращаем false: выход делает quit() в _done(). Вернуть ещё и true — значит попросить
# движок завершиться дважды.
func _process(_delta: float) -> bool:
	if _phase == 0:
		_phase = 1
		_run(_lab)
	elif _phase == 1 and Engine.get_physics_frames() >= _until_frame:
		_phase = 2
		_check_core_moved(_lab)
		_done()
	return false


func _run(lab: Node) -> void:
	var space := _find(lab, "GpfSpace")
	if space == null or not (space is Node3D):
		_fail("в сцене нет узла GpfSpace — геометрия не под обёрткой осей")
		_done()
		return

	# Базис обёртки — единственный источник конверсии осей (SkeletonBuilder).
	var builder = load("res://src/gpf/SkeletonBuilder.cs").new()
	var expected_basis: Basis = builder.AxisConversionBasis()
	if not (space as Node3D).basis.is_equal_approx(expected_basis):
		_fail("базис GpfSpace %s не совпадает с SkeletonBuilder" % (space as Node3D).basis)

	var models := []
	_collect_models(space, space, models)
	if models.size() != EXPECTED_MESHES:
		_fail("мешей стадиона %d, ожидалось %d — модель не загрузилась или потерялись слоты"
				% [models.size(), EXPECTED_MESHES])
	else:
		print("модели: %d мешей под GpfSpace" % models.size())

	# Оси: габарит в координатах ПОД обёрткой обязан совпадать с оригиналом (X — длина поля,
	# Z — вверх). Любой доворот меша или автоконверсия glTF валят это немедленно.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var without_texture: Array[String] = []
	for entry in models:
		var mi: MeshInstance3D = entry["node"]
		var xform: Transform3D = entry["xform"]
		var aabb: AABB = mi.mesh.get_aabb()
		for corner in 8:
			var p: Vector3 = xform * (aabb.position + Vector3(
					aabb.size.x if (corner & 1) else 0.0,
					aabb.size.y if (corner & 2) else 0.0,
					aabb.size.z if (corner & 4) else 0.0))
			lo = lo.min(p)
			hi = hi.max(p)
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(s)
			if not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).albedo_texture == null:
				without_texture.append("%s#%d" % [mi.name, s])

	if not (feq(lo.x, -HALF_X) and feq(hi.x, HALF_X) and feq(lo.y, -HALF_Y) and feq(hi.y, HALF_Y)
			and feq(lo.z, 0.0) and feq(hi.z, TOP_Z)):
		_fail("габарит под GpfSpace X %.3f..%.3f Y %.3f..%.3f Z %.3f..%.3f, ожидался ±%.3f / ±%.3f / 0..%.0f"
				% [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, HALF_X, HALF_Y, TOP_Z])
	else:
		print("оси: габарит под GpfSpace ±%.3f × ±%.3f × %.0f — координаты оригинала"
				% [HALF_X, HALF_Y, TOP_Z])

	# Материалы назначены на самой сцене, а не только в юнит-проверке загрузчика.
	if without_texture.is_empty():
		print("материалы: все поверхности несут диффуз из .ase")
	else:
		_fail("поверхности без диффуза в сцене: %s" % ", ".join(without_texture.slice(0, 5)))

	# Дальше — ждём, пока оркестратор сам отработает RUN_TICKS физических тиков.
	_start_player = lab.GetStatePosition()
	_start_ball = lab.GetBallPosition()
	lab.SetCommand(Vector3(0, -1, 0), 3)   # вперёд спринтом — к мячу
	_until_frame = Engine.get_physics_frames() + RUN_TICKS


# Игрок и мяч ядра управляются ОРКЕСТРАТОРОМ: его собственные тики двигают и того, и другого.
func _check_core_moved(lab: Node) -> void:
	var player: Vector3 = lab.GetStatePosition()
	var ball: Vector3 = lab.GetBallPosition()

	if player.distance_to(_start_player) < 0.5:
		_fail("игрок не сдвинулся за %d тиков (%.3f м) — оркестратор не гонит ядро"
				% [RUN_TICKS, player.distance_to(_start_player)])
	elif ball.distance_to(_start_ball) < 0.01:
		_fail("мяч не тронут за %d тиков — игрок до него не дошёл или Ball.Process не зовётся"
				% RUN_TICKS)
	else:
		print("ядро: игрок прошёл %.2f м, мяч сдвинулся на %.2f м, коллизий тело-мяч %d"
				% [player.distance_to(_start_player), ball.distance_to(_start_ball),
						lab.GetTouchCount()])


func _done() -> void:
	if _fails == 0:
		print("OK: сцена stadium_lab собирается, оси и материалы на месте, ядро гоняется")
	else:
		print("ПРОВАЛЕНО: %d расхождений" % _fails)
	quit(1 if _fails > 0 else 0)

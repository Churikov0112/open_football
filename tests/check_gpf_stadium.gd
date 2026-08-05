extends SceneTree

# Геометрия стадиона, поля, ворот и мяча приезжает из `.ase` оригинала через
# `tools/build_gpf_stadium.py`. Скрипт ловит ошибку КОНВЕЙЕРА цифрами: перепутанные оси,
# масштаб, потерянные объекты, разъехавшиеся материалы. Прообраз — `check_gpf_blockout.gd`
# (там тот же приём для скелета).
#
# Инвариант осей порта: сцена живёт в «их» пространстве (X — длина поля, Y — ширина,
# Z — вверх). Конвейер экспортирует с `export_yup=False`, поэтому координаты в `.glb`
# совпадают с `*MESH_VERTEX` оригинала один в один. Любая автоконверсия осей
# немедленно валит габариты ниже.
#
# Имена слотов материалов — `mat<NN>`, где NN = `*MATERIAL_REF` объекта, то есть индекс
# в `*MATERIAL_LIST` того же `.ase`. Это шов с тикетом 03: рантайм-загрузчик лабы читает
# `MATERIAL_LIST` из версионированного `.ase` и назначает карты мешам по этим именам.
# Единственный источник правды — сам `.ase`, поэтому набор материалов сверяется с ним.

const MEDIA := "res://assets/gpf/media"
const MODELS := "res://assets/models"

# Допуск координат: значения приходят из float32 glTF, а сама модель слеплена с точностью
# до миллиметра (крайние X оригинала -57.554/+57.548 — не идеально симметричны).
const EPS := 0.01

# Габариты, СНЯТЫЕ с `*MESH_VERTEX` исходных `.ase` (не подобранные): ими ловятся
# перепутанные оси и масштаб.
const STADIUM_HALF_X := 104.015
const STADIUM_HALF_Y := 84.015
const STADIUM_TOP_Z := 39.0
const BALL_RADIUS := 0.11  # хардкод оригинала по всему ball.cpp

# Сетка ворот: `PrepareGoalNetting` (match.cpp:2147-2156) собирает вершины с
# |x| > pitchHalfW + 0.06 — порог отсекает штанги («don't catch woodwork.. DIRTY HAXX»).
# 1138 на сторону — сумма `*MESH_VERTEX` объектов сетки, прошедших этот фильтр
# (4 боковые панели по 72 + 2 верхние по 200 + 2 задние по 225). Число пересчитано
# по `goals.ase`, а не взято на веру: им ловится потеря панели конвейером.
const NETTING_THRESHOLD := 55.06
const NETTING_VERTS_PER_SIDE := 1138

var _fails := 0


func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("  FAIL: ", msg)


func feq(a: float, b: float, eps := EPS) -> bool:
	return absf(a - b) < eps


# --- чтение .ase: только `*MATERIAL_LIST`, он лежит в шапке файла ---------------------

func _ase_material_names(rel: String) -> Array[String]:
	var names: Array[String] = []
	var f := FileAccess.open("%s/%s" % [MEDIA, rel], FileAccess.READ)
	if f == null:
		_fail("нет исходника %s — сначала тикет 01" % rel)
		return names
	var expected := -1
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("*MATERIAL_COUNT"):
			expected = int(line.split(" ")[1])
		elif line.begins_with("*MATERIAL_NAME"):
			names.append(line.split('"')[1])
			if expected >= 0 and names.size() >= expected:
				break
	f.close()
	if expected >= 0 and names.size() != expected:
		_fail("%s: *MATERIAL_COUNT %d, а имён %d" % [rel, expected, names.size()])
	return names


# --- чтение .glb ----------------------------------------------------------------------

# Трансформ узла относительно корня сцены. Считаем вручную: сцена не в дереве,
# `global_transform` вернул бы Transform3D() с ошибкой `!is_inside_tree()`.
func _xform_to_root(node: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _collect(node: Node, root: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append({"node": mi, "xform": _xform_to_root(mi, root)})
	for child in node.get_children():
		_collect(child, root, out)


# [{name, verts: PackedVector3Array}] — по одной записи на поверхность, вершины в
# координатах корня сцены.
func _surfaces(rel: String) -> Array:
	var path := "%s/%s" % [MODELS, rel]
	var surfaces := []
	if not ResourceLoader.exists(path):
		_fail("нет %s — собери tools/build_gpf_stadium.py" % path)
		return surfaces

	var root: Node = (load(path) as PackedScene).instantiate()
	var found := []
	_collect(root, root, found)

	for entry in found:
		var mi: MeshInstance3D = entry["node"]
		var xform: Transform3D = entry["xform"]
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(s)
			var name := "" if mat == null else mat.resource_name
			var albedo: Texture2D = null
			if mat is BaseMaterial3D:
				albedo = (mat as BaseMaterial3D).albedo_texture
			var raw: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var verts := PackedVector3Array()
			for v in raw:
				verts.append(xform * v)
			surfaces.append({"name": name, "verts": verts, "albedo": albedo})

	root.free()
	return surfaces


func _bounds(surfaces: Array) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var count := 0
	for s in surfaces:
		for v in s["verts"]:
			lo = lo.min(v)
			hi = hi.max(v)
			count += 1
	return {"lo": lo, "hi": hi, "count": count}


# Набор материалов `.glb` обязан быть ровно `mat00..mat<N-1>` по `*MATERIAL_LIST` того же
# `.ase`, и мешей столько же: один меш на материал (решение 5 спеки).
func _check_materials(label: String, surfaces: Array, ase_rel: String) -> void:
	var names := _ase_material_names(ase_rel)
	if names.is_empty():
		return

	var got: Array[String] = []
	var baked: Array[String] = []
	for s in surfaces:
		got.append(s["name"])
		# Текстуры в .glb не запекаются: карты назначает рантайм-загрузчик лабы, иначе
		# генератору газона некуда писать (решение 6 спеки). Запечённый диффуз — ошибка
		# конвейера, а не мелочь: он молча переживёт подмену материала.
		if s["albedo"] != null:
			baked.append(s["name"])
	if not baked.is_empty():
		_fail("%s: в .glb запечены текстуры (%s) — конвейер обязан отдавать только геометрию"
				% [label, ", ".join(baked.slice(0, 5))])

	var missing: Array[String] = []
	for i in names.size():
		if not ("mat%02d" % i) in got:
			missing.append("mat%02d (%s)" % [i, names[i]])
	if not missing.is_empty():
		_fail("%s: нет слотов %s" % [label, ", ".join(missing.slice(0, 5))])

	if got.size() != names.size():
		_fail("%s: поверхностей %d при %d материалах — «один меш на материал» нарушено (%s)"
				% [label, got.size(), names.size(), ", ".join(got.slice(0, 8))])
	else:
		print("%s: материалов %d, поверхностей %d" % [label, names.size(), got.size()])


# --- проверки по файлам ---------------------------------------------------------------

func _check_pitch(P: Object) -> void:
	var surfaces := _surfaces("gpf_pitch.glb")
	if surfaces.is_empty():
		return
	_check_materials("поле", surfaces, "objects/stadiums/test/pitch.ase")

	# Рамка поля: pitch.ase раскатан ровно по pitchFullHalfW/H (gamedefines.hpp:273-274).
	var b := _bounds(surfaces)
	var full_w: float = P.GetPitchFullHalfW()
	var full_h: float = P.GetPitchFullHalfH()
	if not (feq(b["lo"].x, -full_w) and feq(b["hi"].x, full_w)
			and feq(b["lo"].y, -full_h) and feq(b["hi"].y, full_h)):
		_fail("поле: рамка X %.3f..%.3f Y %.3f..%.3f, ожидалось ±%.0f/±%.0f по GpfPitch"
				% [b["lo"].x, b["hi"].x, b["lo"].y, b["hi"].y, full_w, full_h])
	elif not feq(b["lo"].z, 0.0) or not feq(b["hi"].z, 0.0):
		_fail("поле: не плоское, Z %.3f..%.3f" % [b["lo"].z, b["hi"].z])
	else:
		print("поле: рамка ±%.0f × ±%.0f, плоская — совпадает с GpfPitch" % [full_w, full_h])


func _check_goals(P: Object) -> void:
	var surfaces := _surfaces("gpf_goals.glb")
	if surfaces.is_empty():
		return
	_check_materials("ворота", surfaces, "objects/stadiums/goals.ase")

	var half_w: float = P.GetPitchHalfW()
	var depth: float = P.GetGoalDepth()
	var goal_half: float = P.GetGoalHalfWidth()
	var height: float = P.GetGoalHeight()

	# Крайние X — задняя плоскость сетки: линия ворот ± глубина ворот.
	var b := _bounds(surfaces)
	var expect_x := half_w + depth
	if not feq(absf(b["lo"].x), expect_x) or not feq(absf(b["hi"].x), expect_x):
		_fail("ворота: крайние X %.3f..%.3f, ожидалось ±%.2f (pitchHalfW + goalDepth)"
				% [b["lo"].x, b["hi"].x, expect_x])
	else:
		print("ворота: крайние X ±%.2f = pitchHalfW %.0f + goalDepth %.2f"
				% [expect_x, half_w, depth])

	# Створ: сетка натянута ровно по goalHalfWidth и goalHeight. Штанги толще — поэтому
	# створ меряется по сетке, а не по общему габариту файла.
	var net_lo := Vector3(INF, INF, INF)
	var net_hi := Vector3(-INF, -INF, -INF)
	var per_side := {"-": 0, "+": 0}
	for s in surfaces:
		for v in s["verts"]:
			if absf(v.x) <= NETTING_THRESHOLD:
				continue
			net_lo = net_lo.min(v)
			net_hi = net_hi.max(v)
			per_side["-" if v.x < 0.0 else "+"] += 1

	if not (feq(net_lo.y, -goal_half) and feq(net_hi.y, goal_half) and feq(net_hi.z, height)):
		_fail("ворота: створ по сетке Y %.3f..%.3f Z ..%.3f, ожидалось ±%.2f / %.2f"
				% [net_lo.y, net_hi.y, net_hi.z, goal_half, height])
	else:
		print("ворота: створ ±%.2f × %.2f — совпадает с GpfPitch" % [goal_half, height])

	if per_side["-"] != NETTING_VERTS_PER_SIDE or per_side["+"] != NETTING_VERTS_PER_SIDE:
		_fail("ворота: вершин сетки %d слева / %d справа, ожидалось %d на сторону — конвейер потерял или склеил панели"
				% [per_side["-"], per_side["+"], NETTING_VERTS_PER_SIDE])
	else:
		print("ворота: сетка %d вершин на сторону (фильтр |x| > %.2f)"
				% [NETTING_VERTS_PER_SIDE, NETTING_THRESHOLD])


func _check_stadium() -> void:
	var surfaces := _surfaces("gpf_stadium.glb")
	if surfaces.is_empty():
		return
	_check_materials("стадион", surfaces, "objects/stadiums/test/test.ase")

	var b := _bounds(surfaces)
	if not (feq(b["lo"].x, -STADIUM_HALF_X) and feq(b["hi"].x, STADIUM_HALF_X)
			and feq(b["lo"].y, -STADIUM_HALF_Y) and feq(b["hi"].y, STADIUM_HALF_Y)
			and feq(b["lo"].z, 0.0) and feq(b["hi"].z, STADIUM_TOP_Z)):
		_fail("стадион: габарит X %.3f..%.3f Y %.3f..%.3f Z %.3f..%.3f, ожидался ±%.3f / ±%.3f / 0..%.0f"
				% [b["lo"].x, b["hi"].x, b["lo"].y, b["hi"].y, b["lo"].z, b["hi"].z,
						STADIUM_HALF_X, STADIUM_HALF_Y, STADIUM_TOP_Z])
	else:
		print("стадион: габарит ±%.3f × ±%.3f × %.0f, вершин %d"
				% [STADIUM_HALF_X, STADIUM_HALF_Y, STADIUM_TOP_Z, b["count"]])


func _check_ball() -> void:
	var surfaces := _surfaces("gpf_ball.glb")
	if surfaces.is_empty():
		return
	_check_materials("мяч", surfaces, "objects/balls/generic.ase")

	var b := _bounds(surfaces)
	for axis in 3:
		if not feq(b["lo"][axis], -BALL_RADIUS) or not feq(b["hi"][axis], BALL_RADIUS):
			_fail("мяч: габарит по оси %d %.4f..%.4f, ожидался ±%.2f"
					% [axis, b["lo"][axis], b["hi"][axis], BALL_RADIUS])
			return
	print("мяч: радиус %.2f по всем осям" % BALL_RADIUS)


func _initialize() -> void:
	print("== check_gpf_stadium ==")

	var P = load("res://src/gpf/GpfPitch.cs")
	if P == null:
		_fail("нет GpfPitch.cs — сначала dotnet build")
		_done()
		return

	_check_pitch(P)
	_check_goals(P)
	_check_stadium()
	_check_ball()
	_done()


func _done() -> void:
	if _fails == 0:
		print("OK: геометрия оригинала доехала через конвейер без потерь")
	else:
		print("ПРОВАЛЕНО: %d расхождений" % _fails)
	quit(1 if _fails > 0 else 0)

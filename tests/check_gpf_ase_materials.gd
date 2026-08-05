extends SceneTree

# Знание «материал → карты и скаляры» приходит в рантайм так же, как в оригинале: загрузчик
# лабы парсит `*MATERIAL_LIST` из версионированного `.ase` и назначает материалы мешам `.glb`
# по именам слотов `mat<NN>`. Зеркало `aseloader.cpp:39-98`.
#
# Скрипт проверяет ВНЕШНЕЕ поведение загрузчика: какие файлы карт он выдаёт по реальному `.ase`
# оригинала (и существуют ли они), какие скаляры, что при отсутствующем `MAP_DIFFUSE`
# подставляется `orange.jpg` (ветка мёртвая на наших четырёх файлах — иначе её нечем проверить),
# и что назначение по слотам покрывает все поверхности собранного `.glb`.

const MEDIA := "res://assets/gpf/media"
const TEST_ASE := "res://assets/gpf/media/objects/stadiums/test/test.ase"
const STADIUM_GLB := "res://assets/models/gpf_stadium.glb"

# Фолбэк диффуза оригинала (aseloader.cpp:78). У нас файл лежит в textures/.
const FALLBACK := "res://assets/gpf/media/textures/orange.jpg"

var _fails := 0


func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("  FAIL: ", msg)


func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps


# Ожидания сняты с `*MATERIAL_LIST` самого test.ase — они и есть внешнее поведение загрузчика.
func _check_known(mats: Array) -> void:
	var by_name := {}
	for m in mats:
		by_name[m["name"]] = m

	# Материал только с диффузом.
	var floor_mat = by_name.get("greenish_floor")
	if floor_mat == null:
		_fail("нет материала greenish_floor")
	else:
		if floor_mat["diffuse"] != "%s/textures/stadium/greenish_floor.png" % MEDIA:
			_fail("greenish_floor: диффуз %s" % floor_mat["diffuse"])
		if floor_mat["bump"] != "" or floor_mat["shine"] != "" or floor_mat["selfillum"] != "":
			_fail("greenish_floor: лишние карты")
		if not feq(floor_mat["shininess"], 0.2) or not feq(floor_mat["specular"], 0.15):
			_fail("greenish_floor: скаляры shine %f / shinestrength %f"
					% [floor_mat["shininess"], floor_mat["specular"]])

	# Материал со всеми тремя «не-диффузными» слотами разного вида: bump + shine.
	var concrete = by_name.get("concrete")
	if concrete == null:
		_fail("нет материала concrete")
	else:
		if concrete["bump"] != "%s/textures/concrete/concrete.wall01_normal.jpg" % MEDIA:
			_fail("concrete: bump %s" % concrete["bump"])
		if concrete["shine"] != "%s/textures/concrete/concrete.wall01_specular.jpg" % MEDIA:
			_fail("concrete: shine %s" % concrete["shine"])

	# Единственный материал с картой самосвечения.
	var wall = by_name.get("floor01wall")
	if wall == null:
		_fail("нет материала floor01wall")
	elif wall["selfillum"] != "%s/objects/stadiums/test/floor01wall_selfillum.png" % MEDIA:
		_fail("floor01wall: selfillum %s" % wall["selfillum"])

	# Щиты: 23 материала на одной подменяемой заглушке (это вход RandomizeAdboards, тикет 09).
	var placeholders := 0
	for m in mats:
		if m["diffuse"] == "%s/textures/stadium/ad_placeholder.jpg" % MEDIA:
			placeholders += 1
	if placeholders != 23:
		_fail("материалов с ad_placeholder.jpg: %d, ожидалось 23" % placeholders)
	else:
		print("щиты: 23 материала на ad_placeholder.jpg")


# Загрузчик обязан выдавать пути к файлам, которые ЕСТЬ: опечатка в резолвере иначе всплывёт
# только серым стадионом на глазной приёмке.
func _check_files_exist(mats: Array) -> void:
	var missing: Array[String] = []
	for m in mats:
		for key in ["diffuse", "bump", "shine", "selfillum"]:
			var path: String = m[key]
			if path != "" and not FileAccess.file_exists(path):
				missing.append("%s.%s=%s" % [m["name"], key, path])
	if missing.is_empty():
		print("карты: все пути существуют")
	else:
		_fail("несуществующие карты: %s" % ", ".join(missing.slice(0, 5)))


# Ветка `aseloader.cpp:78`: нет MAP_DIFFUSE → "orange.jpg", остальные слоты пустые. На четырёх
# .ase фазы она мертва, поэтому проверяется на синтетическом файле.
func _check_fallback(M: Object) -> void:
	var path := "user://gpf_no_diffuse_test.ase"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("*MATERIAL_LIST {\n\t*MATERIAL_COUNT 1\n\t*MATERIAL 0 {\n"
			+ "\t\t*MATERIAL_NAME \"no_diffuse\"\n\t\t*MATERIAL_SHINE 0.300\n"
			+ "\t\t*MATERIAL_SHINESTRENGTH 0.400\n\t\t*MATERIAL_SELFILLUM 0.500\n\t}\n}\n")
	f.close()

	var mats: Array = M.Describe(path)
	if mats.size() != 1:
		_fail("синтетический .ase: материалов %d, ожидался 1" % mats.size())
		return
	var m = mats[0]
	if m["diffuse"] != FALLBACK:
		_fail("фолбэк диффуза: %s, ожидался %s" % [m["diffuse"], FALLBACK])
	elif m["bump"] != "" or m["shine"] != "" or m["selfillum"] != "":
		_fail("фолбэк: непустые прочие карты")
	elif not feq(m["shininess"], 0.3) or not feq(m["specular"], 0.4) \
			or not feq(m["illumination"], 0.5):
		_fail("фолбэк: скаляры %f/%f/%f" % [m["shininess"], m["specular"], m["illumination"]])
	else:
		print("фолбэк диффуза: orange.jpg при отсутствующем MAP_DIFFUSE")


# Назначение по именам слотов: после Apply каждая поверхность .glb несёт материал с диффузом.
func _check_apply(M: Object, expected: int) -> void:
	if not ResourceLoader.exists(STADIUM_GLB):
		_fail("нет %s — сначала тикет 02" % STADIUM_GLB)
		return

	var root: Node = (load(STADIUM_GLB) as PackedScene).instantiate()
	var applied: int = M.Apply(root, TEST_ASE)
	if applied != expected:
		_fail("назначено материалов %d из %d поверхностей" % [applied, expected])

	var without: Array[String] = []
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(s)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
				continue
			without.append("%s#%d" % [mi.name, s])
	if without.is_empty():
		print("назначение: %d поверхностей получили материал с диффузом" % applied)
	else:
		_fail("без диффуза после Apply: %s" % ", ".join(without.slice(0, 5)))
	root.free()


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, out)


func _initialize() -> void:
	print("== check_gpf_ase_materials ==")

	var M = load("res://src/lab/AseMaterials.cs")
	if M == null:
		_fail("нет AseMaterials.cs — сначала dotnet build")
		_done()
		return

	var mats: Array = M.Describe(TEST_ASE)
	if mats.size() != 31:
		_fail("test.ase: материалов %d, ожидался 31" % mats.size())
		_done()
		return
	print("test.ase: материалов %d" % mats.size())

	_check_known(mats)
	_check_files_exist(mats)
	_check_fallback(M)
	_check_apply(M, mats.size())
	_done()


func _done() -> void:
	if _fails == 0:
		print("OK: материалы оригинала доезжают до мешей .glb")
	else:
		print("ПРОВАЛЕНО: %d расхождений" % _fails)
	quit(1 if _fails > 0 else 0)

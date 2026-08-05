extends SceneTree

# Две живые ветки презентации оригинала: подмена рекламных щитов (`RandomizeAdboards`,
# match.cpp:526-585) и случайное солнце (`SetRandomSunParams`, match.cpp:493-524).
#
# Ожидания ниже ПЕРЕВЫЧИСЛЕНЫ здесь по формулам C++, а не выписаны литералами: тот же приём,
# что в check_gpf_ball_foundation. Порядок обращений к ГСЧ — часть контракта, поэтому эталон
# считается на своём экземпляре GpfRng с тем же сидом.

const TEST_ASE := "res://assets/gpf/media/objects/stadiums/test/test.ase"
const ADBOARD_DIR := "res://assets/gpf/media/textures/adboards"
const PLACEHOLDER := "res://assets/gpf/media/textures/stadium/ad_placeholder.jpg"

# 23 материала стадиона сидят на плейсхолдере (match.cpp:571 меняет каждый).
const AD_MATERIALS := 23

var _fails := 0


func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("  FAIL: ", msg)


func feq(a: float, b: float, eps := 1.0e-5) -> bool:
	return absf(a - b) < eps


# --- щиты ------------------------------------------------------------------------------

func _adboard_files() -> Array[String]:
	var files: Array[String] = []
	for name in DirAccess.get_files_at(ADBOARD_DIR):
		if name.ends_with(".png"):
			files.append(name)
	files.sort()
	return files


func _check_adboards(MP: Object, AM: Object) -> void:
	var files := _adboard_files()
	if files.size() != 16:
		_fail("адбордов в каталоге %d, ожидалось 16" % files.size())
		return

	var plain: Array = AM.Describe(TEST_ASE)
	var randomized: Array = MP.DescribeAdboards(TEST_ASE, 1)
	if plain.size() != randomized.size():
		_fail("подмена изменила число материалов: %d → %d" % [plain.size(), randomized.size()])
		return

	var changed := 0
	for i in plain.size():
		var was: Dictionary = plain[i]
		var now: Dictionary = randomized[i]
		if was["diffuse"] == PLACEHOLDER:
			changed += 1
			if not now["diffuse"].begins_with(ADBOARD_DIR):
				_fail("%s: диффуз не из набора адбордов (%s)" % [now["name"], now["diffuse"]])
			# match.cpp:572-573 — подменённым материалам выставляются оба скаляра.
			if not feq(now["specular"], 0.2) or not feq(now["shininess"], 0.1):
				_fail("%s: скаляры %f/%f, ожидались 0.2/0.1"
						% [now["name"], now["specular"], now["shininess"]])
		else:
			# Не-плейсхолдерные материалы обязаны остаться нетронутыми: условие оригинала —
			# идент диффуза НАЧИНАЕТСЯ с "ad_placeholder" (:569).
			if now["diffuse"] != was["diffuse"] or not feq(now["specular"], was["specular"]) \
					or not feq(now["shininess"], was["shininess"]):
				_fail("%s: материал без плейсхолдера изменён" % now["name"])

	if changed != AD_MATERIALS:
		_fail("подменено %d материалов, ожидалось %d" % [changed, AD_MATERIALS])
	else:
		print("щиты: подменено %d материалов, скаляры 0.2/0.1" % changed)


# Индекс берётся как floor(random(0, size − 1.001)) (:571) — при 16 файлах ПОСЛЕДНИЙ по
# алфавиту не выбирается никогда. Это ошибка оригинала, и порт обязан её повторить:
# 40 сидов × 23 подмены = 920 бросков, при честном диапазоне промах невозможен.
func _check_last_never_used(MP: Object) -> void:
	var files := _adboard_files()
	var last := "%s/%s" % [ADBOARD_DIR, files[files.size() - 1]]
	var seen := {}
	for seed in range(1, 41):
		for entry in MP.DescribeAdboards(TEST_ASE, seed):
			if entry["diffuse"].begins_with(ADBOARD_DIR):
				seen[entry["diffuse"]] = true
	if seen.has(last):
		_fail("выбран последний адборд %s — off-by-one оригинала (:571) не воспроизведён"
				% last.get_file())
	elif seen.size() != files.size() - 1:
		_fail("за 40 сидов встретилось %d разных адбордов из %d ожидаемых"
				% [seen.size(), files.size() - 1])
	else:
		print("щиты: использованы %d из %d файлов, последний (%s) не выбирается — как в оригинале"
				% [seen.size(), files.size(), last.get_file()])


func _check_adboards_vary(MP: Object) -> void:
	var a: Array = MP.DescribeAdboards(TEST_ASE, 11)
	var b: Array = MP.DescribeAdboards(TEST_ASE, 22)
	var diff := 0
	for i in a.size():
		if a[i]["diffuse"] != b[i]["diffuse"]:
			diff += 1
	if diff == 0:
		_fail("набор щитов не меняется между сидами — от загрузки к загрузке будет одинаковым")
	else:
		print("щиты: разные сиды дают разный набор (%d материалов из %d отличаются)"
				% [diff, AD_MATERIALS])


# --- солнце ----------------------------------------------------------------------------

# Эталон формулы match.cpp:495-523, перевычисленный здесь. Порядок бросков: X, Y, флип, ×3 цвет.
func _expected_sun(RNG: Object, seed: int) -> Dictionary:
	var rng = RNG.new()
	rng.Reseed(seed)

	var average_height_multiplier := 1.3
	var sun_pos := Vector3(
			clampf(rng.Uniform(-1.7, 1.7), -1.0, 1.0),
			clampf(rng.Uniform(-1.7, 1.7), -1.0, 1.0),
			average_height_multiplier).normalized()
	# `&&` в C++ ленив по ПРАВОМУ операнду: бросок слева делается всегда.
	var roll: float = rng.Uniform(0.0, 1.0)
	if roll > 0.5 and sun_pos.y > 0.25:
		sun_pos.y = -sun_pos.y

	var noon := Vector3(0.9, 0.8, 1.0) * 1.4
	var dusk := Vector3(1.4, 0.9, 0.7) * 1.2
	var noon_bias: float = pow(clampf((sun_pos.z - 0.5) / 0.5, 0.0, 1.0), 1.2)
	var color: Vector3 = noon * noon_bias + dusk * (1.0 - noon_bias)
	color += Vector3(rng.Uniform(-0.1, 0.1), rng.Uniform(-0.1, 0.1), rng.Uniform(-0.1, 0.1)) * 1.2
	return {"pos": sun_pos, "color": color}


func _check_sun(MP: Object, RNG: Object) -> void:
	for seed in [7, 12345]:
		var expected := _expected_sun(RNG, seed)
		var rng = RNG.new()
		rng.Reseed(seed)
		var light := DirectionalLight3D.new()
		MP.SetRandomSunParams(light, rng)

		# Свет идёт ОТ позиции солнца к центру поля: локальная +Z узла смотрит на солнце.
		var got_dir: Vector3 = light.transform.basis.z
		if got_dir.distance_to(expected["pos"]) > 1.0e-4:
			_fail("солнце сид %d: направление %v, ожидалось %v"
					% [seed, got_dir, expected["pos"]])
		# Цвет оригинала выходит за 1.0 по компонентам, поэтому в Godot он разложен на
		# light_color × light_energy — произведение обязано совпасть с формулой.
		var got_color := Vector3(light.light_color.r, light.light_color.g, light.light_color.b) \
				* light.light_energy
		if got_color.distance_to(expected["color"]) > 1.0e-4:
			_fail("солнце сид %d: цвет %v, ожидался %v" % [seed, got_color, expected["color"]])
		light.free()

	# Солнце обязано быть НАД полем: averageHeightMultiplier 1.3 больше любого из clamp(±1).
	var rng2 = RNG.new()
	rng2.Reseed(999)
	var probe := DirectionalLight3D.new()
	MP.SetRandomSunParams(probe, rng2)
	if probe.transform.basis.z.z <= 0.0:
		_fail("солнце ушло под поле: Z направления %f" % probe.transform.basis.z.z)
	probe.free()

	var a := _expected_sun(RNG, 3)
	var b := _expected_sun(RNG, 4)
	if a["pos"].distance_to(b["pos"]) < 1.0e-6 or a["color"].distance_to(b["color"]) < 1.0e-6:
		_fail("солнце не варьируется между сидами")
	else:
		print("солнце: направление и цвет совпадают с формулой оригинала и меняются с сидом")


func _initialize() -> void:
	print("== check_gpf_adboards_sun ==")

	var MP = load("res://src/lab/MatchPresentation.cs")
	var AM = load("res://src/lab/AseMaterials.cs")
	var RNG = load("res://src/gpf/GpfRng.cs")
	if MP == null or AM == null or RNG == null:
		_fail("нет C#-скриптов — сначала dotnet build")
		_done()
		return

	_check_adboards(MP, AM)
	_check_last_never_used(MP)
	_check_adboards_vary(MP)
	_check_sun(MP, RNG)
	_done()


func _done() -> void:
	if _fails == 0:
		print("OK: щиты и солнце по формулам оригинала, из презентационного ГСЧ")
	else:
		print("ПРОВАЛЕНО: %d расхождений" % _fails)
	quit(1 if _fails > 0 else 0)

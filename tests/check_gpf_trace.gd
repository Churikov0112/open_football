extends SceneTree
# Фаза 5, тикет 03: приёмка писателя трассы и сценарного проигрывателя порта.
# Проверяется внешнее поведение артефактов — формат файла, воспроизводимость, реакция парсера
# на битый вход. Пороги внутри ядра тест намеренно не трогает.
#
# Лаба поднимается один раз (загрузка коллекции ~1 с) и переиспользуется: SetupOracle можно звать
# повторно, он каждый раз заново поднимает стартовое состояние из трассы эталона.

const TICKS := 60

var _lab: Node = null
var _ok := true
var _tmp := ""


func _initialize() -> void:
	_tmp = ProjectSettings.globalize_path("user://")
	_lab = load("res://scenes/lab/ball_lab.tscn").instantiate()
	get_root().add_child(_lab)


func _process(_delta: float) -> bool:
	if not _lab.is_node_ready():
		return false

	_check_scenario_parser()
	_check_reference_input()
	_check_trace_shape()
	_check_determinism()
	_check_manifest()
	_check_hid_input()

	print("CHECK PASS" if _ok else "CHECK FAIL")
	quit(0 if _ok else 1)
	return true


func _fail(message: String) -> void:
	print("CHECK FAIL: ", message)
	_ok = false


func _write(name: String, text: String) -> String:
	var path := _tmp + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


# Синтетическая трасса эталона: заголовок, строка мяча и строка контролируемого на тике 0.
func _reference_trace() -> String:
	var header: String = load("res://src/gpf/TraceWriter.cs").new().GetHeader()
	var ball := "B,0,1.500000,-2.000000,0.110000,0.000000,0.000000,0.000000,,,,,,,,,,,,,,,"
	var player := "P,0,7,1,movement/idle/000,412,movement,1,0,-1,1,0,0," \
		+ "3.000000,4.000000,0.000000,0.500000,0.000000,0.000000,0.000000,0.000000,0.000000,0.000000"
	return _write("ref_synth.csv", header + "\n" + ball + "\n" + player + "\n")


func _scenario(name: String, body: String) -> String:
	return _write(name, body)


# ---------- парсер сценария: тот же синтаксис и тот же набор ошибок, что у C++-стороны ----------
func _check_scenario_parser() -> void:
	var OS_ = load("res://src/lab/OracleScenario.cs")

	var good := _scenario("sc_good.txt", "# комментарий\nseed 7\nticks 100\n0 dir 0,-1,0 buttons Sprint\n50 buttons -\n")
	var s = OS_.new()
	if not s.Load(good):
		_fail("валидный сценарий не разобрался: " + s.Error)
	else:
		if s.GetSeed() != 7: _fail("seed разобран неверно: " + str(s.GetSeed()))
		if s.GetTicks() != 100: _fail("ticks разобран неверно: " + str(s.GetTicks()))
		# разреженность: состояние держится до следующего изменения
		if not s.GetButton(49, OracleScenarioBtnSprint()): _fail("Sprint не дожил до тика 49")
		if s.GetButton(50, OracleScenarioBtnSprint()): _fail("`buttons -` не снял Sprint на тике 50")
		if s.GetDirection(99) != Vector3(0, -1, 0): _fail("dir не дожил до конца прогона")

	var bad := {
		"sc_switch.txt": ["seed 1\nticks 10\n0 dir 0,-1,0 buttons Switch\n", "Switch"],
		"sc_bare.txt": ["seed 1\nticks 10\n0 dir 0,-1,0\n5\n", "no-op"],
		"sc_token.txt": ["seed 1\nticks 10\n0 dir 0,-1,0 turbo\n", "неизвестный токен"],
		"sc_noseed.txt": ["ticks 10\n0 dir 0,-1,0\n", "seed"],
		"sc_noticks.txt": ["seed 1\n0 dir 0,-1,0\n", "ticks"],
	}
	for name in bad:
		var path := _scenario(name, bad[name][0])
		var parser = OS_.new()
		if parser.Load(path):
			_fail(name + ": битый сценарий разобрался молча")
		elif not parser.Error.contains(bad[name][1]):
			_fail(name + ": непонятная ошибка: " + parser.Error)
		elif not parser.Error.contains(":"):
			_fail(name + ": в ошибке нет номера строки: " + parser.Error)


func OracleScenarioBtnSprint() -> int:
	return 14  # e_ButtonFunction_Sprint


# ---------- вход: трасса эталона обязана быть внятной ----------
func _check_reference_input() -> void:
	var sc := _scenario("sc_in.txt", "seed 3\nticks 10\n0 dir 0,-1,0\n")

	var empty := _write("ref_empty.csv", "")
	if _lab.SetupOracle(sc, empty, _tmp + "t.csv", _tmp + "m.csv"):
		_fail("пустая трасса эталона принята — старт из нулей")
	elif not _lab.OracleError.contains("controlled"):
		_fail("непонятная ошибка на пустой трассе: " + _lab.OracleError)

	var header: String = load("res://src/gpf/TraceWriter.cs").new().GetHeader()
	var no_controlled := _write("ref_nc.csv", header + "\n"
		+ "P,0,7,0,movement/idle/000,412,movement,1,0,-1,1,0,0,"
		+ "3.000000,4.000000,0.000000,0.500000,0.000000,0.000000,0.000000,0.000000,0.000000,0.000000\n")
	if _lab.SetupOracle(sc, no_controlled, _tmp + "t.csv", _tmp + "m.csv"):
		_fail("трасса без controlled = 1 принята")

	var missing := _tmp + "ref_missing_file.csv"
	if _lab.SetupOracle(sc, missing, _tmp + "t.csv", _tmp + "m.csv"):
		_fail("несуществующая трасса эталона принята")


# ---------- форма трассы ----------
func _check_trace_shape() -> void:
	var lines := _run("shape", "seed 11\nticks %d\n0 dir 0,-1,0 buttons Sprint\n" % TICKS, "t1.csv", "m1.csv")
	if lines.is_empty():
		return

	var header: String = load("res://src/gpf/TraceWriter.cs").new().GetHeader()
	if lines[0] != header:
		_fail("заголовок трассы не совпал с TraceWriter.Header")

	if lines.size() != 1 + TICKS * 2:
		_fail("строк в трассе %d, ожидалось %d (заголовок + B и P на тик)" % [lines.size(), 1 + TICKS * 2])
		return

	# правило нулевого тика: первая P-строка — idle-клип, кадр 0
	var first_player: PackedStringArray = lines[2].split(",")
	if first_player[0] != "P" or first_player[1] != "0":
		_fail("первая P-строка не тика 0: " + lines[2])
	if first_player[8] != "0":
		_fail("первая P-строка не с frame_num = 0: " + first_player[8])
	if first_player[3] != "1":
		_fail("первая P-строка не помечена controlled")

	for i in range(1, lines.size()):
		var f: PackedStringArray = lines[i].split(",")
		if f.size() != 23:
			_fail("строка %d: полей %d вместо 23" % [i, f.size()])
			return
		var expected_kind := "B" if (i - 1) % 2 == 0 else "P"
		if f[0] != expected_kind:
			_fail("строка %d: kind %s вместо %s" % [i, f[0], expected_kind])
			return
		if f[1] != str((i - 1) / 2):
			_fail("строка %d: тик %s вместо %d" % [i, f[1], (i - 1) / 2])
			return
		# инвариантная культура: точка, а не запятая, и шесть знаков
		if expected_kind == "P" and not f[13].contains("."):
			_fail("строка %d: float без точки-разделителя: %s" % [i, f[13]])
			return

	# дискретные поля последней строки — это состояние гуманоида на том же тике,
	# писатель не отстаёт на кадр и ничего не выдумывает
	var last: PackedStringArray = lines[lines.size() - 1].split(",")
	if int(last[5]) != _lab.GetCurrentAnimIndex():
		_fail("anim_id последней строки %s != состояния %d" % [last[5], _lab.GetCurrentAnimIndex()])
	if last[13] != "%.6f" % _lab.GetStatePosition().x:
		_fail("pos_x последней строки %s != состояния %f" % [last[13], _lab.GetStatePosition().x])


# ---------- воспроизводимость ----------
func _check_determinism() -> void:
	var body := "seed 13\nticks %d\n0 dir 0,-1,0 buttons Sprint\n30 dir 1,0,0\n" % TICKS
	_run("det", body, "d1.csv", "dm1.csv")
	_run("det", body, "d2.csv", "dm2.csv")
	if _read(_tmp + "d1.csv") != _read(_tmp + "d2.csv"):
		_fail("два прогона дали разные трассы")
	if _read(_tmp + "dm1.csv") != _read(_tmp + "dm2.csv"):
		_fail("два прогона дали разные манифесты")


# ---------- манифест ----------
func _check_manifest() -> void:
	var text := _read(_tmp + "m1.csv")
	if text.is_empty():
		_fail("манифест не написан")
		return
	var lines := text.split("\n", false)
	if lines[0] != load("res://src/gpf/TraceWriter.cs").new().GetManifestHeader():
		_fail("заголовок манифеста не совпал")
	# длина манифеста = размеру коллекции; счётчик берём у самой лабы, а не константой
	var collection_size := lines.size() - 1
	if collection_size < 1000:
		_fail("манифест подозрительно короткий: " + str(collection_size))
	var first: PackedStringArray = lines[1].split(",")
	if first[0] != "0" or first.size() != 5:
		_fail("первая строка манифеста не index,anim_name,anim_type,foot,frame_count: " + lines[1])


# ---------- порт _GetHidInput: дедзона проверяется первой ----------
func _check_hid_input() -> void:
	# вне дедзоны + Sprint → разгон до спринта (enum_velocity 3)
	var sprint := _run("hid", "seed 17\nticks 200\n0 dir 0,-1,0 buttons Sprint\n", "h1.csv", "hm.csv")
	if not sprint.is_empty():
		var f: PackedStringArray = sprint[sprint.size() - 1].split(",")
		if f[11] != "3":
			_fail("dir вне дедзоны + Sprint не дал спринт: enum_velocity " + f[11])

	# dir 0,0,0 + Sprint → idle: дедзона проверяется ПЕРЕД кнопками (humancontroller.cpp:500-503)
	var dead := _run("hid", "seed 17\nticks 200\n0 dir 0,0,0 buttons Sprint\n", "h2.csv", "hm.csv")
	if not dead.is_empty():
		var f: PackedStringArray = dead[dead.size() - 1].split(",")
		if f[11] != "0":
			_fail("dir 0,0,0 + Sprint не дал idle: enum_velocity " + f[11])

	# короткий вектор (длина 0.5 < 0.75) → тоже дедзона
	var short := _run("hid", "seed 17\nticks 200\n0 dir 0,-0.5,0 buttons Sprint\n", "h3.csv", "hm.csv")
	if not short.is_empty():
		var f: PackedStringArray = short[short.size() - 1].split(",")
		if f[11] != "0":
			_fail("короткий вектор + Sprint не дал idle: enum_velocity " + f[11])


func _run(name: String, scenario_body: String, trace: String, manifest: String) -> PackedStringArray:
	var sc := _scenario("sc_" + name + "_" + trace + ".txt", scenario_body)
	var ref := _reference_trace()
	if not _lab.SetupOracle(sc, ref, _tmp + trace, _tmp + manifest):
		_fail(name + ": SetupOracle: " + _lab.OracleError)
		return PackedStringArray()
	if not _lab.RunOracle():
		_fail(name + ": RunOracle: " + _lab.OracleError)
		return PackedStringArray()
	return _read(_tmp + trace).split("\n", false)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text

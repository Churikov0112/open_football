extends SceneTree
# Фаза 5, тикет 04: приёмка диффа манифестов коллекции.
# Ожидаемые вердикты строятся из синтетических манифестов, собранных прямо в тесте, а не
# списываются с прогона — то же искусство, что в check_gpf_ball.gd.
#
# Тикеты 05-06 дописывают сюда проверки диффа трасс.

const Manifest := preload("res://tools/oracle_manifest.gd")

var _ok := true
var _tmp := ""


func _initialize() -> void:
	_tmp = ProjectSettings.globalize_path("user://")

	_check_match()
	_check_extra_clip()
	_check_missing_clip()
	_check_reordered()
	_check_duplicates()
	_check_broken_input()
	_check_report_fits_screen()

	print("CHECK PASS" if _ok else "CHECK FAIL")
	quit(0 if _ok else 1)


func _fail(message: String) -> void:
	print("CHECK FAIL: ", message)
	_ok = false


# clips — массив «имя|тип|нога|кадров»; индексы проставляются здесь, как это делает писатель.
func _write_manifest(name: String, clips: Array) -> String:
	var lines: Array[String] = [Manifest.HEADER]
	for i in clips.size():
		lines.append(str(i) + "," + str(clips[i]).replace("|", ","))
	var path := _tmp + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return path


func _sample() -> Array:
	return [
		"movement/idle/000|movement|0|25",
		"movement/idle/000_mirror|movement|1|25",
		"movement/walk/000|movement|1|30",
		"ballcontrol/walk/000|ballcontrol|0|18",
	]


func _check_match() -> void:
	var a := _write_manifest("m_a.csv", _sample())
	var b := _write_manifest("m_b.csv", _sample())
	var r := Manifest.compare(a, b)
	if r.verdict != "match":
		_fail("идентичные манифесты дали вердикт '%s'" % r.verdict)
	if r.size_ref != 4 or r.size_port != 4:
		_fail("размер коллекции посчитан неверно: %d / %d" % [r.size_ref, r.size_port])
	if r.dup_ref != 0 or r.dup_port != 0:
		_fail("дубли найдены там, где их нет: %d / %d" % [r.dup_ref, r.dup_port])
	if not Manifest.report(r).contains("anim_id пригоден"):
		_fail("при совпадении отчёт не говорит, что anim_id стал точным ключом")


func _check_extra_clip() -> void:
	var extra := _sample()
	extra.append("special/celebration/000|special|0|40")
	var a := _write_manifest("m_c.csv", _sample())
	var b := _write_manifest("m_d.csv", extra)
	var r := Manifest.compare(a, b)
	if r.verdict != "composition":
		_fail("лишний клип у порта дал вердикт '%s'" % r.verdict)
		return
	if r.only_port.size() != 1 or not str(r.only_port[0]).begins_with("special/celebration/000"):
		_fail("лишний клип не назван: " + str(r.only_port))
	if not r.only_ref.is_empty():
		_fail("у эталона нашлось лишнее там, где его нет: " + str(r.only_ref))
	if not Manifest.report(r).contains("special/celebration/000"):
		_fail("отчёт не называет лишний клип")


func _check_missing_clip() -> void:
	var short := _sample()
	short.remove_at(2)
	var a := _write_manifest("m_e.csv", _sample())
	var b := _write_manifest("m_f.csv", short)
	var r := Manifest.compare(a, b)
	if r.verdict != "composition":
		_fail("недостающий клип дал вердикт '%s'" % r.verdict)
		return
	if r.only_ref.size() != 1 or not str(r.only_ref[0]).begins_with("movement/walk/000"):
		_fail("недостающий клип не назван: " + str(r.only_ref))


# Тот же набор в другом порядке — расхождение, а не совпадение: стабильная сортировка отбора
# разрешает равные ключи порядком исходного списка.
func _check_reordered() -> void:
	var reordered := _sample()
	var third: String = reordered[2]
	reordered[2] = reordered[3]
	reordered[3] = third
	var a := _write_manifest("m_g.csv", _sample())
	var b := _write_manifest("m_h.csv", reordered)
	var r := Manifest.compare(a, b)
	if r.verdict != "order":
		_fail("перестановка дала вердикт '%s' вместо 'order'" % r.verdict)
		return
	if r.first_index != 2:
		_fail("первый разошедшийся индекс %d вместо 2" % r.first_index)
	if not Manifest.report(r).contains("первый разошедшийся индекс: 2"):
		_fail("отчёт не называет первый разошедшийся индекс")


func _check_duplicates() -> void:
	# Одно и то же имя с одной и той же ногой, но разной длиной — неразрешённая коллизия:
	# по паре anim_name+foot такие строки неразличимы.
	var dup := _sample()
	dup.append("autogen [v1 b0] => [v1 b0 a0]|movement|0|25")
	dup.append("autogen [v1 b0] => [v1 b0 a0]|movement|0|27")
	var a := _write_manifest("m_i.csv", dup)
	var r := Manifest.compare(a, a)
	if r.verdict != "match":
		_fail("манифест, сравнённый сам с собой, дал '%s'" % r.verdict)
	if r.dup_ref != 1 or r.dup_port != 1:
		_fail("дубли anim_name+foot посчитаны неверно: %d / %d" % [r.dup_ref, r.dup_port])
	if not Manifest.report(r).contains("сравнивает по anim_id"):
		_fail("при дублях отчёт не предупреждает, как их разрешает дифф трасс")


func _check_broken_input() -> void:
	var good := _write_manifest("m_j.csv", _sample())

	var missing := _tmp + "m_nope.csv"
	if Manifest.compare(good, missing).verdict != "error":
		_fail("несуществующий манифест не дал ошибку")

	var bad_header := _tmp + "m_bad_header.csv"
	var f := FileAccess.open(bad_header, FileAccess.WRITE)
	f.store_string("index,name\n0,x\n")
	f.close()
	var r := Manifest.compare(good, bad_header)
	if r.verdict != "error":
		_fail("чужой заголовок не дал ошибку")
	elif not str(r.error).contains("заголовок"):
		_fail("непонятная ошибка на чужом заголовке: " + str(r.error))

	var bad_index := _tmp + "m_bad_index.csv"
	f = FileAccess.open(bad_index, FileAccess.WRITE)
	f.store_string(Manifest.HEADER + "\n0,a,movement,0,10\n5,b,movement,0,10\n")
	f.close()
	r = Manifest.compare(good, bad_index)
	if r.verdict != "error":
		_fail("сбитая нумерация манифеста не дала ошибку")


# Отчёт, который не читают, не отличается от отсутствующего.
func _check_report_fits_screen() -> void:
	var many: Array = []
	for i in 500:
		many.append("movement/gen/%03d|movement|%d|25" % [i, i % 2])
	var a := _write_manifest("m_k.csv", many)
	var b := _write_manifest("m_l.csv", _sample())
	var text := Manifest.report(Manifest.compare(a, b))
	var line_count := text.split("\n").size()
	if line_count > 12:
		_fail("отчёт на 500 расхождений занял %d строк — на экран не помещается" % line_count)
	if not text.contains("и ещё"):
		_fail("длинный список расхождений не свёрнут")

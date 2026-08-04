extends SceneTree
# Фаза 5, тикеты 04 и 05: приёмка диффа манифестов коллекции и диффа трасс по дискретным полям.
# Ожидаемые вердикты строятся из синтетических манифестов и трасс, собранных прямо в тесте, а не
# списываются с прогона и не читаются золотыми файлами с диска — то же искусство, что в
# check_gpf_ball.gd.
#
# Тикет 06 дописывает сюда проверки непрерывного слоя.

const Manifest := preload("res://tools/oracle_manifest.gd")
const Trace := preload("res://tools/oracle_trace.gd")

var _ok := true
var _tmp := ""
# Пара совпадающих манифестов: дифф трасс без совпавшего манифеста до строк не доходит вовсе.
var _mref := ""
var _mport := ""


func _initialize() -> void:
	_tmp = ProjectSettings.globalize_path("user://")

	_check_match()
	_check_extra_clip()
	_check_missing_clip()
	_check_reordered()
	_check_duplicates()
	_check_broken_input()
	_check_report_fits_screen()

	_mref = _write_manifest("t_m_ref.csv", _sample())
	_mport = _write_manifest("t_m_port.csv", _sample())

	_check_trace_match()
	_check_trace_first_divergence()
	_check_trace_stops_on_manifest()
	_check_trace_whitelist()
	_check_trace_whitelist_broken()
	_check_trace_control_moved()
	_check_trace_length_mismatch()
	_check_trace_missing_tick()
	_check_trace_tick_without_controlled()
	_check_trace_ambiguous_names()
	_check_trace_safe_area()
	_check_trace_report_fits_screen()

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


# --- дифф трасс (тикет 05) ------------------------------------------------------------------------

func _join(fields: Array) -> String:
	var out := PackedStringArray()
	for f in fields:
		out.append(str(f))
	return ",".join(out)


# Мяч в 12 м от игрока в нуле координат — снаружи безопасной области предупреждать не о чем.
func _b_row() -> Array:
	var row := ["B", "0", "0.000000", "-12.000000", "0.110000", "0.000000", "0.000000", "0.000000"]
	for i in Trace.FIELD_COUNT - row.size():
		row.append("")
	return row


func _p_row() -> Array:
	return ["P", "0", "7", "1", "movement/idle/000", "412", "movement", "0", "0", "-1", "1", "0", "0",
		"0.000000", "0.000000", "0.000000", "0.000000", "0.000000",
		"0.000000", "0.000000", "0.000000", "0.000000", "0.000000"]


# rows — по тику список P-строк; номер тика проставляется здесь, как это делает писатель.
func _write_trace(name: String, rows: Array) -> String:
	var lines: Array[String] = [Trace.HEADER]
	for t in rows.size():
		var b := _b_row()
		b[Trace.COL_TICK] = str(t)
		lines.append(_join(b))
		for row in rows[t]:
			var p: Array = (row as Array).duplicate()
			p[Trace.COL_TICK] = str(t)
			lines.append(_join(p))
	var path := _tmp + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return path


# Ровный прогон: один контролируемый игрок на каждом тике.
func _plain(tick_count: int) -> Array:
	var rows: Array = []
	for t in tick_count:
		rows.append([_p_row()])
	return rows


func _write_whitelist(name: String, body: String) -> String:
	var path := _tmp + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(body)
	f.close()
	return path


func _check_trace_match() -> void:
	var a := _write_trace("t_a.csv", _plain(20))
	var b := _write_trace("t_b.csv", _plain(20))
	var r := Trace.compare(a, b, _mref, _mport, "")
	if r.verdict != "match":
		_fail("идентичные трассы дали вердикт '%s' (%s)" % [r.verdict, r.get("error", "")])
		return
	if r.paired != 20:
		_fail("спарено %d тиков вместо 20" % r.paired)
	if not Trace.report(r).contains("ДИСКРЕТНЫЕ ПОЛЯ СОВПАЛИ на 20"):
		_fail("при совпадении отчёт не говорит, на скольких тиках совпало")


func _check_trace_first_divergence() -> void:
	var port := _plain(20)
	# frame_num расходится с тика 7, anim_type — позже: назван должен быть первый.
	for t in range(7, 20):
		port[t][0][Trace.DISCRETE[4].col] = "9"
	for t in range(12, 20):
		port[t][0][Trace.DISCRETE[2].col] = "ballcontrol"
	var a := _write_trace("t_c.csv", _plain(20))
	var b := _write_trace("t_d.csv", port)
	var r := Trace.compare(a, b, _mref, _mport, "")
	if r.verdict != "mismatch":
		_fail("расхождение дискретного поля дало вердикт '%s'" % r.verdict)
		return
	if r.first_tick != 7 or r.first_field != "frame_num":
		_fail("первое расхождение названо как тик %d поле %s вместо тика 7 поля frame_num"
			% [r.first_tick, r.first_field])
	var text := Trace.report(r)
	if not text.contains("тик 7, поле frame_num"):
		_fail("отчёт не называет тик и поле первого расхождения")
	if not text.contains("эталон: 0") or not text.contains("порт:   9"):
		_fail("отчёт не печатает оба значения")
	# Контекст ±5: тики 2..12, из них 11 строк.
	if r.context.size() != 11:
		_fail("контекст занял %d тиков вместо 11" % r.context.size())
	if int(r.context[0].tick) != 2 or int(r.context[10].tick) != 12:
		_fail("контекст не центрирован на первом расхождении: %d..%d"
			% [r.context[0].tick, r.context[10].tick])
	# Разбор продолжился до конца: остальные поля знают СВОЙ первый тик.
	if not r.field_first.has("anim_type") or int(r.field_first.anim_type.tick) != 12:
		_fail("хвостовая сводка не нашла первый тик anim_type: " + str(r.field_first))
	if not text.contains("anim_type (тик 12)"):
		_fail("отчёт не печатает тик первого расхождения остальных полей")
	if not text.contains("совпали на всей длине"):
		_fail("отчёт не перечисляет поля без расхождений")


# Манифесты — первая стадия: разошлись, и построчный дифф не запускается.
func _check_trace_stops_on_manifest() -> void:
	var other := _sample()
	other.append("special/celebration/000|special|0|40")
	var m := _write_manifest("t_m_other.csv", other)
	var a := _write_trace("t_e.csv", _plain(5))
	var r := Trace.compare(a, a, _mref, m, "")
	if r.verdict != "manifest":
		_fail("разошедшийся манифест дал вердикт '%s' вместо 'manifest'" % r.verdict)
		return
	if not Trace.report(r).contains("Построчный дифф трасс не запускается"):
		_fail("отчёт не говорит, что построчный дифф не запускался")


func _check_trace_whitelist() -> void:
	var port := _plain(20)
	for t in range(3, 20):
		port[t][0][Trace.DISCRETE[0].col] = "movement/walk/000"
	for t in range(9, 20):
		port[t][0][Trace.DISCRETE[4].col] = "9"
	var a := _write_trace("t_f.csv", _plain(20))
	var b := _write_trace("t_g.csv", port)

	var always := _write_whitelist("wl_always.txt",
		"# комментарий\nanim_name|always|расхождения-с-оригиналом.md, строка про отбор клипа\n")
	var r := Trace.compare(a, b, _mref, _mport, always)
	if r.verdict != "mismatch" or r.first_field != "frame_num" or r.first_tick != 9:
		_fail("поле из белого списка не исключено: вердикт '%s', %s на тике %d"
			% [r.verdict, r.first_field, r.first_tick])
	if int(r.suppressed.get("anim_name", 0)) != 17:
		_fail("погашенные расхождения не посчитаны: " + str(r.suppressed))
	if not Trace.report(r).contains("белый список: правил 1"):
		_fail("отчёт не сообщает, что белый список действовал")

	# Условие с границей: до тика 6 гасим, дальше сравниваем как обычно.
	var bounded := _write_whitelist("wl_tick.txt", "anim_name|tick<6|строка страницы\n")
	r = Trace.compare(a, b, _mref, _mport, bounded)
	if r.first_field != "anim_name" or r.first_tick != 6:
		_fail("условие tick<6 сработало неверно: %s на тике %d" % [r.first_field, r.first_tick])


func _check_trace_whitelist_broken() -> void:
	var a := _write_trace("t_h.csv", _plain(5))
	var bad_column := _write_whitelist("wl_bad_col.txt", "anim_nmae|always|опечатка\n")
	var r := Trace.compare(a, a, _mref, _mport, bad_column)
	if r.verdict != "error" or not str(r.error).contains("нет колонки"):
		_fail("опечатка в имени колонки белого списка не дала ошибку: " + str(r.get("error", r.verdict)))

	var bad_condition := _write_whitelist("wl_bad_cond.txt", "anim_name|tick~5|условие\n")
	r = Trace.compare(a, a, _mref, _mport, bad_condition)
	if r.verdict != "error" or not str(r.error).contains("условие"):
		_fail("неизвестное условие белого списка не дало ошибку: " + str(r.get("error", r.verdict)))


func _check_trace_control_moved() -> void:
	var ref: Array = []
	for t in 10:
		var row := _p_row()
		row[Trace.COL_PLAYER_ID] = "26" if t < 5 else "20"
		ref.append([row])
	var a := _write_trace("t_i.csv", ref)
	var b := _write_trace("t_j.csv", _plain(10))
	var r := Trace.compare(a, b, _mref, _mport, "")
	if r.verdict != "control_moved":
		_fail("переезд контроля дал вердикт '%s'" % r.verdict)
		return
	var text := Trace.report(r)
	if not text.contains("26 (тик 0)") or not text.contains("20 (тик 5)"):
		_fail("отчёт не называет обоих игроков и тики: " + text)
	if not text.contains("Построчный дифф не запускается"):
		_fail("отчёт не говорит, что построчный дифф не запускался")


func _check_trace_length_mismatch() -> void:
	var a := _write_trace("t_k.csv", _plain(20))
	var b := _write_trace("t_l.csv", _plain(15))
	var r := Trace.compare(a, b, _mref, _mport, "")
	if r.verdict != "error" or not str(r.error).contains("разной длины"):
		_fail("трассы разной длины не дали внятную ошибку: " + str(r.get("error", r.verdict)))


# Пропущенный тик — дырка в нумерации B-строк, то есть сломанная трасса.
func _check_trace_missing_tick() -> void:
	var lines: Array[String] = [Trace.HEADER]
	for t in [0, 1, 3]:
		var b := _b_row()
		b[Trace.COL_TICK] = str(t)
		lines.append(_join(b))
		var p := _p_row()
		p[Trace.COL_TICK] = str(t)
		lines.append(_join(p))
	var path := _tmp + "t_gap.csv"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()

	var good := _write_trace("t_m.csv", _plain(3))
	var r := Trace.compare(good, path, _mref, _mport, "")
	if r.verdict != "error" or not str(r.error).contains("пропущен тик"):
		_fail("пропущенный тик не дал внятную ошибку: " + str(r.get("error", r.verdict)))


# Тик, у которого B есть, а контролируемого нет, — законное состояние: Team::Process снимает выбор
# игрока, пока мяч не в игре. Это не пропущенный тик и не усечение, он просто не спаривается.
func _check_trace_tick_without_controlled() -> void:
	var ref := _plain(20)
	for t in range(12, 20):
		ref[t] = []
	var a := _write_trace("t_n.csv", ref)
	var b := _write_trace("t_o.csv", _plain(20))
	var r := Trace.compare(a, b, _mref, _mport, "")
	if r.verdict != "match":
		_fail("тик без контролируемого дал вердикт '%s' (%s)" % [r.verdict, r.get("error", "")])
		return
	if r.paired != 12 or r.ref_no_controlled != 8:
		_fail("спарено %d тиков, без контролируемого %d — ожидалось 12 и 8"
			% [r.paired, r.ref_no_controlled])
	if not Trace.report(r).contains("тиков без контролируемого: эталон 8"):
		_fail("отчёт не печатает число тиков без контролируемого")


# Неразрешённая коллизия имён автогенов: по паре anim_name+foot клипы неразличимы, поэтому имя у таких
# строк не сравнивается — сравнивается anim_id. На живой библиотеке дублей ноль, ветка проверяется
# синтетикой.
func _check_trace_ambiguous_names() -> void:
	var dup := _sample()
	dup.append("autogen [v1 b0] => [v1 b0 a0]|movement|0|25")
	dup.append("autogen [v1 b0] => [v1 b0 a0]|movement|0|27")
	var m := _write_manifest("t_m_dup.csv", dup)

	var ref := _plain(10)
	var port := _plain(10)
	for t in 10:
		ref[t][0][Trace.DISCRETE[0].col] = "autogen [v1 b0] => [v1 b0 a0]"
		port[t][0][Trace.DISCRETE[0].col] = "movement/walk/000"
	var a := _write_trace("t_p.csv", ref)
	var b := _write_trace("t_q.csv", port)
	var r := Trace.compare(a, b, m, m, "")
	if r.verdict != "match":
		_fail("строки с неразрешённым именем сравнены по имени: %s / %s" % [r.verdict, r.first_field])
	if r.ambiguous_names != 1 or r.ambiguous_rows != 10:
		_fail("ограничение прогона посчитано неверно: имён %d, строк %d"
			% [r.ambiguous_names, r.ambiguous_rows])
	if not Trace.report(r).contains("ОГРАНИЧЕНИЕ ПРОГОНА"):
		_fail("отчёт не отмечает неразрешённую коллизию как ограничение прогона")

	# Тот же случай, но разошёлся anim_id — вот он обязан быть виден.
	for t in range(4, 10):
		port[t][0][Trace.DISCRETE[1].col] = "999"
	var c := _write_trace("t_r.csv", port)
	r = Trace.compare(a, c, m, m, "")
	if r.verdict != "mismatch" or r.first_field != "anim_id" or r.first_tick != 4:
		_fail("расхождение anim_id на неразрешённых именах не поймано: %s, %s, тик %d"
			% [r.verdict, r.first_field, r.first_tick])


func _check_trace_safe_area() -> void:
	var port := _plain(10)
	for t in range(2, 5):
		port[t][0][Trace.COL_TOUCH_FRAME] = "0"
	var ref := _plain(10)
	for t in range(6, 8):
		ref[t][0][Trace.COL_POS_X + 1] = "-5.000000"  # мяч стоит на y = -12, дистанция 7 м
	var a := _write_trace("t_s.csv", ref)
	var b := _write_trace("t_t.csv", port)
	var r := Trace.compare(a, b, _mref, _mport, "")
	if r.touch_ticks != 3 or r.near_ticks != 2:
		_fail("выход за безопасную область посчитан неверно: касаний %d, близко к мячу %d"
			% [r.touch_ticks, r.near_ticks])
	if not Trace.report(r).contains("вышел за безопасную область"):
		_fail("отчёт не предупреждает о выходе за безопасную область фазы 5")


func _check_trace_report_fits_screen() -> void:
	var long_name := "autogen [v2 b45] => [v0 b0 a90] очень длинное синтезированное имя_mirror"
	var ref := _plain(300)
	var port := _plain(300)
	for t in 300:
		ref[t][0][Trace.DISCRETE[0].col] = long_name
		for d in Trace.DISCRETE:
			if t >= 100:
				port[t][0][d.col] = "X"
	var a := _write_trace("t_u.csv", ref)
	var b := _write_trace("t_v.csv", port)
	var text := Trace.report(Trace.compare(a, b, _mref, _mport, ""))
	var line_count := text.split("\n").size()
	if line_count > 40:
		_fail("отчёт занял %d строк — на экран не помещается" % line_count)
	for line in text.split("\n"):
		if str(line).length() > 120:
			_fail("строка отчёта длиной %d символов не помещается по ширине" % str(line).length())
			break

extends RefCounted
# Дифф трасс по дискретным полям — главный инструмент вехи. Печатает ПЕРВЫЙ разошедшийся тик: номер,
# имя поля, оба значения и контекст вокруг. Первый разошедшийся тик по определению есть место первого
# отступления, всё дальнейшее — его следствие; полная таблица расхождений не печатается никогда,
# потому что отчёт, который не читают, не отличается от отсутствующего.
#
# Порядок стадий жёсткий:
#   1. манифесты коллекции (tools/oracle_manifest.gd — та же логика, что у tools/manifest_diff.gd);
#      разошлись — построчный дифф не запускается, сравнивать нечего;
#   2. постоянство контролируемого игрока в трассе; переезжал — дифф не запускается, строки
#      принадлежали бы разным людям;
#   3. дискретные поля спаренных строк.
#
# Библиотека, не инструмент: CLI-обёртка — tools/trace_diff.gd, приёмка — tests/check_trace_diff.gd.
# Непрерывный слой (позиции, углы, смаггл, начало роста) — тикет 06, дописывается сюда же.

const Manifest := preload("res://tools/oracle_manifest.gd")

const HEADER := "kind,tick,player_id,controlled,anim_name,anim_id,anim_type,function_type,frame_num,touch_frame,foot,enum_velocity,quadrant_id,pos_x,pos_y,pos_z,angle,rel_body_angle,move_x,move_y,move_z,action_smuggle,movement_smuggle"

# Файл прямоугольный: 23 поля в каждой строке, включая B — у неё заняты первые восемь, хвост пустой.
const FIELD_COUNT := 23

const COL_KIND := 0
const COL_TICK := 1
const COL_PLAYER_ID := 2
const COL_CONTROLLED := 3
const COL_ANIM_NAME := 4
const COL_TOUCH_FRAME := 9
const COL_POS_X := 13
# B-строка: свои шесть значений в позициях 3-8, то есть позиция мяча начинается с индекса 2.
const COL_BALL_X := 2

# Дискретные поля. Порядок значим: им отчёт выбирает, какое поле назвать, если на первом разошедшемся
# тике разошлось сразу несколько. anim_name идёт первым, потому что он читаемый; anim_id законен как
# точный ключ только после совпадения манифеста, а до него дифф и не доходит.
const DISCRETE := [
	{"name": "anim_name", "col": 4},
	{"name": "anim_id", "col": 5},
	{"name": "anim_type", "col": 6},
	{"name": "function_type", "col": 7},
	{"name": "frame_num", "col": 8},
	{"name": "touch_frame", "col": 9},
	{"name": "foot", "col": 10},
	{"name": "enum_velocity", "col": 11},
	{"name": "quadrant_id", "col": 12},
]

# Контекст вокруг первого расхождения: одиночный всплеск отличается от начала лавины только так.
const CONTEXT := 5

# До фазы 8 участки рядом с мячом отравлены незакрытыми швами (MentalImage, суррогатный
# HasPossession, AI_GetPass), и расхождение на них не приговор порту.
const SAFE_BALL_DISTANCE := 10.0

# Отчёт обязан помещаться на экран — длинные имена автогенов режутся, длинные перечисления
# переносятся.
const MAX_VALUE_CHARS := 46
const MAX_LINE_CHARS := 96


# --- чтение трассы -----------------------------------------------------------------------------

# -> { ok, error, ticks: Array[int], ball: {tick -> Vector3}, controlled: {tick -> PackedStringArray},
#      controlled_ids: {player_id -> первый тик}, zero_rows: int, touch_ticks: int, near_ticks: int }
#
# Тики нумеруются от нуля подряд и держатся на B-строках: B пишется раз в тик безусловно, значит она и
# есть костяк файла. Дырка в этой нумерации — пропущенный тик, то есть сломанная трасса. Тик, у
# которого B есть, а строки с controlled = 1 нет, — законное состояние: Team::Process снимает выбор
# игрока, пока мяч не в игре. Здесь и проходит граница между «трасса битая» и «сравнивать нечего».
static func load_trace(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("%s: не открывается (%d)" % [path, FileAccess.get_open_error()])

	var text := file.get_as_text()
	file.close()
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n", false)
	if lines.is_empty():
		return _error("%s: пустой файл" % path)
	if lines[0] != HEADER:
		return _error("%s: заголовок не совпадает с объявленным в спеке" % path)

	var ticks: Array[int] = []
	var ball := {}
	var controlled := {}
	var controlled_ids := {}
	var zero_rows := 0
	var touch_ticks := 0
	var near_ticks := 0

	for i in range(1, lines.size()):
		var f := lines[i].split(",")
		if f.size() != FIELD_COUNT:
			return _error("%s:%d: полей %d вместо %d" % [path, i + 1, f.size(), FIELD_COUNT])
		var tick := int(f[COL_TICK])

		if f[COL_KIND] == "B":
			if tick != ticks.size():
				return _error("%s:%d: тик %d вместо %d — в трассе пропущен тик"
					% [path, i + 1, tick, ticks.size()])
			ticks.append(tick)
			ball[tick] = Vector3(float(f[COL_BALL_X]), float(f[COL_BALL_X + 1]), float(f[COL_BALL_X + 2]))
		elif f[COL_KIND] == "P":
			if ticks.is_empty() or tick != ticks[-1]:
				return _error("%s:%d: строка игрока в тике %d, а открыт тик %d"
					% [path, i + 1, tick, -1 if ticks.is_empty() else ticks[-1]])
			if f[COL_CONTROLLED] != "1":
				zero_rows += 1
				continue
			if controlled.has(tick):
				return _error("%s:%d: в тике %d контролируемых строк больше одной" % [path, i + 1, tick])
			controlled[tick] = f
			if not controlled_ids.has(f[COL_PLAYER_ID]):
				controlled_ids[f[COL_PLAYER_ID]] = tick
			if int(f[COL_TOUCH_FRAME]) >= 0:
				touch_ticks += 1
			var pos := Vector3(float(f[COL_POS_X]), float(f[COL_POS_X + 1]), float(f[COL_POS_X + 2]))
			if pos.distance_to(ball[tick]) < SAFE_BALL_DISTANCE:
				near_ticks += 1
		else:
			return _error("%s:%d: kind '%s' — ни B, ни P" % [path, i + 1, f[COL_KIND]])

	if ticks.is_empty():
		return _error("%s: ни одной строки B — трасса пуста" % path)

	return {
		"ok": true, "error": "", "ticks": ticks, "ball": ball, "controlled": controlled,
		"controlled_ids": controlled_ids, "zero_rows": zero_rows,
		"touch_ticks": touch_ticks, "near_ticks": near_ticks,
	}


# --- белый список ------------------------------------------------------------------------------

# Машиночитаемая выжимка из docs/wiki/расхождения-с-оригиналом.md: `<колонка>|<условие>|<ссылка>`,
# условие — always | tick<N | tick>N | kind=B, `#` — комментарий. Ведётся руками, и расхождение без
# строки на той странице сюда не попадает.
# -> { ok, error, rules: Array[Dictionary] }
static func load_whitelist(path: String) -> Dictionary:
	if path == "":
		return {"ok": true, "error": "", "rules": []}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "rules": [],
			"error": "%s: не открывается (%d)" % [path, FileAccess.get_open_error()]}

	var text := file.get_as_text()
	file.close()
	var columns := HEADER.split(",")
	var rules: Array[Dictionary] = []
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")

	for i in lines.size():
		var line := lines[i]
		var comment := line.find("#")
		if comment >= 0:
			line = line.substr(0, comment)
		line = line.strip_edges()
		if line.is_empty():
			continue

		var f := line.split("|")
		if f.size() != 3:
			return {"ok": false, "rules": [],
				"error": "%s:%d: частей %d вместо 3 (<колонка>|<условие>|<ссылка>)" % [path, i + 1, f.size()]}

		var column := f[0].strip_edges()
		if not columns.has(column):
			return {"ok": false, "rules": [], "error": "%s:%d: нет колонки '%s'" % [path, i + 1, column]}

		var condition := f[1].strip_edges()
		var rule := {"column": column, "kind": "", "n": 0, "source": f[2].strip_edges()}
		if condition == "always":
			rule.kind = "always"
		elif condition == "kind=B":
			rule.kind = "kind_b"
		elif condition.begins_with("tick<") or condition.begins_with("tick>"):
			var tail := condition.substr(5)
			if not tail.is_valid_int():
				return {"ok": false, "rules": [],
					"error": "%s:%d: условие '%s': '%s' — не число" % [path, i + 1, condition, tail]}
			rule.kind = "lt" if condition.begins_with("tick<") else "gt"
			rule.n = int(tail)
		else:
			return {"ok": false, "rules": [],
				"error": "%s:%d: условие '%s' — не always, tick<N, tick>N или kind=B" % [path, i + 1, condition]}
		rules.append(rule)

	return {"ok": true, "error": "", "rules": rules}


static func is_suppressed(rules: Array, column: String, tick: int) -> bool:
	for rule in rules:
		if rule.column != column:
			continue
		match rule.kind:
			"always":
				return true
			"lt":
				if tick < rule.n:
					return true
			"gt":
				if tick > rule.n:
					return true
			"kind_b":
				# B-строки в вердикт фазы 5 не входят вовсе, гасить в P-строках нечего.
				pass
	return false


# --- дифф --------------------------------------------------------------------------------------

# verdict: "match" | "mismatch" | "manifest" | "control_moved" | "error"
static func compare(ref_path: String, port_path: String, ref_manifest_path: String,
		port_manifest_path: String, whitelist_path: String) -> Dictionary:
	var manifest := Manifest.compare(ref_manifest_path, port_manifest_path)
	if manifest.verdict == "error":
		return _error(str(manifest.error))
	if manifest.verdict != "match":
		return {"verdict": "manifest", "ok": true, "error": "", "manifest": manifest}

	var whitelist := load_whitelist(whitelist_path)
	if not whitelist.ok:
		return _error(str(whitelist.error))

	var ref := load_trace(ref_path)
	if not ref.ok:
		return _error(str(ref.error))
	var port := load_trace(port_path)
	if not port.ok:
		return _error(str(port.error))

	if ref.ticks.size() != port.ticks.size():
		return _error("трассы разной длины: эталон %d тиков, порт %d" % [ref.ticks.size(), port.ticks.size()])

	var result := {
		"ok": true, "error": "", "verdict": "match", "manifest": manifest,
		"rules": whitelist.rules.size(),
		"tick_count": ref.ticks.size(),
		"zero_rows": ref.zero_rows,
		"ref_no_controlled": ref.ticks.size() - ref.controlled.size(),
		"port_no_controlled": port.ticks.size() - port.controlled.size(),
		"touch_ticks": ref.touch_ticks + port.touch_ticks,
		"near_ticks": ref.near_ticks + port.near_ticks,
		"paired": 0,
		"ambiguous_names": manifest.dup_names.size(),
		"ambiguous_rows": 0,
		"suppressed": {},
		"field_first": {},
		"first_tick": -1,
		"first_field": "",
		"context": [],
		"moved_ids": [],
	}

	# Контроль переезжал — строки принадлежали бы разным людям, сравнивать их бессмысленно.
	for trace in [ref, port]:
		if trace.controlled_ids.size() > 1:
			var moved: Array = []
			for id in trace.controlled_ids:
				moved.append("%s (тик %d)" % [id, trace.controlled_ids[id]])
			result.moved_ids = moved
			result.verdict = "control_moved"
			return result

	var dup_names := {}
	for name in manifest.dup_names:
		dup_names[name] = true

	var paired: Array[int] = []
	for tick in ref.ticks:
		# Спаривание по (tick, controlled = 1): player_id в нём не участвует, нумерация сторон
		# независима. Тик без контролируемого просто не спаривается.
		if not ref.controlled.has(tick) or not port.controlled.has(tick):
			continue
		paired.append(tick)
		var a: PackedStringArray = ref.controlled[tick]
		var b: PackedStringArray = port.controlled[tick]

		# Неразрешённая коллизия имён автогенов: по паре anim_name+foot клипы неразличимы, поэтому
		# имя у таких строк не сравнивается — сравнивается anim_id, законный после совпадения манифеста.
		var ambiguous: bool = dup_names.has(a[COL_ANIM_NAME]) or dup_names.has(b[COL_ANIM_NAME])
		if ambiguous:
			result.ambiguous_rows += 1

		for d in DISCRETE:
			if ambiguous and d.name == "anim_name":
				continue
			if a[d.col] == b[d.col]:
				continue
			if is_suppressed(whitelist.rules, d.name, tick):
				result.suppressed[d.name] = int(result.suppressed.get(d.name, 0)) + 1
				continue
			# Разбор идёт до конца трасс, но каждое поле запоминает только ПЕРВЫЙ свой тик: дальше по
			# нему печатать нечего, а хвостовая сводка требует тик первого расхождения по каждому полю.
			if not result.field_first.has(d.name):
				result.field_first[d.name] = {"tick": tick, "ref": a[d.col], "port": b[d.col]}

	result.paired = paired.size()
	if paired.is_empty():
		return _error("спарено 0 тиков: строк с controlled = 1 нет ни в одной паре тиков")

	if result.field_first.is_empty():
		return result

	result.verdict = "mismatch"
	var first_tick: int = result.tick_count
	for name in result.field_first:
		first_tick = min(first_tick, int(result.field_first[name].tick))
	result.first_tick = first_tick
	for d in DISCRETE:
		if result.field_first.has(d.name) and int(result.field_first[d.name].tick) == first_tick:
			result.first_field = d.name
			break

	var col: int = 0
	for d in DISCRETE:
		if d.name == result.first_field:
			col = d.col
	for tick in paired:
		if absi(tick - first_tick) <= CONTEXT:
			result.context.append({
				"tick": tick,
				"ref": ref.controlled[tick][col],
				"port": port.controlled[tick][col],
			})

	return result


static func _error(message: String) -> Dictionary:
	return {"ok": false, "verdict": "error", "error": message}


# --- отчёт -------------------------------------------------------------------------------------

static func report(r: Dictionary) -> String:
	if r.verdict == "error":
		return "ТРАССЫ: ошибка\n  " + str(r.error)

	var lines: Array[String] = [Manifest.report(r.manifest)]
	if r.verdict == "manifest":
		return "\n".join(lines)

	# При переезде контроля спаривание не запускалось вовсе — «спарено 0» читалось бы как результат.
	if r.verdict == "control_moved":
		lines.append("ТРАССЫ: %d тиков с обеих сторон." % r.tick_count)
	else:
		lines.append("ТРАССЫ: %d тиков с обеих сторон, спарено %d." % [r.tick_count, r.paired])
	lines.append("  строк controlled = 0 у эталона: %d (игнорируются)" % r.zero_rows)
	lines.append("  тиков без контролируемого: эталон %d, порт %d (стандарт снимает выбор игрока)"
		% [r.ref_no_controlled, r.port_no_controlled])
	if r.ambiguous_names > 0:
		lines.append("  ОГРАНИЧЕНИЕ ПРОГОНА: неразрешённых имён автогенов %d, строк с ними %d — "
			% [r.ambiguous_names, r.ambiguous_rows] + "сравнены по anim_id, не по имени")
	if r.touch_ticks > 0 or r.near_ticks > 0:
		lines.append("  ПРЕДУПРЕЖДЕНИЕ: сценарий вышел за безопасную область фазы 5 — "
			+ "тиков с касанием %d, тиков ближе %.0f м к мячу %d." % [r.touch_ticks, SAFE_BALL_DISTANCE, r.near_ticks])
		lines.append("  Там расхождение не приговор порту: швы MentalImage, HasPossession и AI_GetPass ещё не закрыты.")
	if r.rules > 0:
		lines.append("  белый список: правил %d, погашено расхождений %s"
			% [r.rules, _brief_counts(r.suppressed)])

	if r.verdict == "control_moved":
		lines.append("КОНТРОЛЬ ПЕРЕЕЗЖАЛ: controlled = 1 стоит у разных player_id — " + ", ".join(r.moved_ids))
		lines.append("  Построчный дифф не запускается: строки принадлежали бы разным людям.")
		return "\n".join(lines)

	if r.verdict == "match":
		lines.append("ДИСКРЕТНЫЕ ПОЛЯ СОВПАЛИ на %d спаренных тиках." % r.paired)
		return "\n".join(lines)

	var first: Dictionary = r.field_first[r.first_field]
	lines.append("ПЕРВОЕ РАСХОЖДЕНИЕ: тик %d, поле %s" % [r.first_tick, r.first_field])
	lines.append("  эталон: " + _clip(str(first.ref)))
	lines.append("  порт:   " + _clip(str(first.port)))
	lines.append("  контекст ±%d тиков (эталон | порт):" % CONTEXT)
	for row in r.context:
		lines.append("    %5d  %s | %s" % [row.tick, _clip(str(row.ref)), _clip(str(row.port))])

	var tail: Array[String] = []
	var same: Array[String] = []
	for d in DISCRETE:
		if d.name == r.first_field:
			continue
		if r.field_first.has(d.name):
			tail.append("%s (тик %d)" % [d.name, r.field_first[d.name].tick])
		else:
			same.append(d.name)
	lines.append("  остальные дискретные поля — тик первого расхождения:")
	lines.append_array(_wrap(["нет расхождений"] if tail.is_empty() else tail))
	if not same.is_empty():
		lines.append("  совпали на всей длине:")
		lines.append_array(_wrap(same))
	return "\n".join(lines)


# Отчёт помещается на экран не только по числу строк, но и по ширине: девять дискретных полей в
# одну строку не влезают.
static func _wrap(parts: Array) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for part in parts:
		var candidate: String = str(part) if line.is_empty() else line + ", " + str(part)
		if candidate.length() > MAX_LINE_CHARS:
			out.append("    " + line)
			line = part
		else:
			line = candidate
	if not line.is_empty():
		out.append("    " + line)
	return out


static func _clip(value: String) -> String:
	if value.length() <= MAX_VALUE_CHARS:
		return value
	return value.substr(0, MAX_VALUE_CHARS - 1) + "…"


static func _brief_counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "нет"
	var parts: Array[String] = []
	for name in counts:
		parts.append("%s %d" % [name, counts[name]])
	parts.sort()
	return ", ".join(parts)

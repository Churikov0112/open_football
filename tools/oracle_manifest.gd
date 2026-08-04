extends RefCounted
# Сравнение манифестов коллекции клипов — первый вопрос оракула: а одинаковые ли у сторон коллекции
# вообще? Пока манифесты не сошлись, построчный дифф трасс не имеет смысла — он будет показывать
# расхождения, которых в портированном коде нет.
#
# Почему сравнение построчное, включая `index`: сорт-цепочка отбора клипа идёт через стабильную
# сортировку, а та разрешает равные ключи порядком исходного списка. Одинаковый набор имён в другом
# порядке — расхождение, а не совпадение.
#
# Библиотека, не инструмент: CLI-обёртка — tools/manifest_diff.gd, а дифф трасс (tools/trace_diff.gd)
# зовёт то же самое своей первой стадией.

const HEADER := "index,anim_name,anim_type,foot,frame_count"

# Сколько имён печатать в отчёте, прежде чем свернуть в «и ещё N» — отчёт обязан помещаться на экран.
const MAX_LISTED := 8


# -> { ok: bool, error: String, clips: Array[String] }
# clip — «имя|тип|нога|кадров», то есть строка манифеста без индекса: индекс проверяется отдельно,
# позицией в массиве.
static func load_manifest(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "%s: не открывается (%d)" % [path, FileAccess.get_open_error()], "clips": []}

	var text := file.get_as_text()
	file.close()
	# Оба писателя кладут одиночный LF, но манифест могли перегнать чужим инструментом: невидимый
	# хвостовой \r иначе даёт отчёт «заголовок X вместо X».
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n", false)
	if lines.is_empty():
		return {"ok": false, "error": "%s: пустой файл" % path, "clips": []}
	if lines[0] != HEADER:
		return {"ok": false, "error": "%s: заголовок '%s' вместо '%s'" % [path, lines[0], HEADER], "clips": []}

	var clips: Array[String] = []
	for i in range(1, lines.size()):
		var f := lines[i].split(",")
		if f.size() != 5:
			return {"ok": false, "error": "%s:%d: полей %d вместо 5" % [path, i + 1, f.size()], "clips": []}
		if f[0] != str(i - 1):
			return {"ok": false, "error": "%s:%d: index '%s' вместо %d — манифест не по порядку"
				% [path, i + 1, f[0], i - 1], "clips": []}
		clips.append("%s|%s|%s|%s" % [f[1], f[2], f[3], f[4]])

	return {"ok": true, "error": "", "clips": clips}


# Имена, у которых пара anim_name + foot встречается больше одного раза: по этой паре такие клипы
# неразличимы. Дифф трасс сравнивает строки с такими именами по anim_id, а не по имени.
static func duplicate_names(clips: Array[String]) -> Array[String]:
	var seen := {}
	var dups := {}
	for clip in clips:
		var f := clip.split("|")
		var key: String = f[0] + "|" + f[2]
		if seen.has(key):
			dups[f[0]] = true
		else:
			seen[key] = true
	var out: Array[String] = []
	for name in dups:
		out.append(name)
	out.sort()
	return out


# Дубли пары anim_name + foot. Имена автогенов не уникальны (формула грубо квантована), и пара с
# ногой — то, чем коллизия разрешается; неразрешённые дифф трасс потом обрабатывает особо.
static func count_name_foot_duplicates(clips: Array[String]) -> int:
	var seen := {}
	var duplicates := 0
	for clip in clips:
		var f := clip.split("|")
		var key: String = f[0] + "|" + f[2]
		if seen.has(key):
			duplicates += 1
		else:
			seen[key] = true
	return duplicates


# -> { ok, error, verdict, size_ref, size_port, dup_ref, dup_port,
#      only_ref: Array[String], only_port: Array[String], first_index: int }
# verdict: "match" | "composition" | "order" | "error"
static func compare(reference_path: String, port_path: String) -> Dictionary:
	var a := load_manifest(reference_path)
	if not a.ok:
		return {"verdict": "error", "ok": false, "error": a.error}
	var b := load_manifest(port_path)
	if not b.ok:
		return {"verdict": "error", "ok": false, "error": b.error}

	var ref_clips: Array[String] = a.clips
	var port_clips: Array[String] = b.clips

	var result := {
		"ok": true,
		"error": "",
		"verdict": "match",
		"size_ref": ref_clips.size(),
		"size_port": port_clips.size(),
		"dup_ref": count_name_foot_duplicates(ref_clips),
		"dup_port": count_name_foot_duplicates(port_clips),
		# Имена неразрешённых коллизий берёт дифф трасс: строки с ними он сравнивает по anim_id.
		"dup_names": duplicate_names(ref_clips),
		"only_ref": [],
		"only_port": [],
		"first_index": -1,
	}

	# Состав: мультимножества, а не множества — один и тот же клип может законно повторяться.
	var ref_counts := _counts(ref_clips)
	var port_counts := _counts(port_clips)
	result.only_ref = _excess(ref_counts, port_counts)
	result.only_port = _excess(port_counts, ref_counts)

	if not result.only_ref.is_empty() or not result.only_port.is_empty():
		result.verdict = "composition"
		return result

	# Состав тот же — остаётся порядок.
	for i in ref_clips.size():
		if ref_clips[i] != port_clips[i]:
			result.verdict = "order"
			result.first_index = i
			return result

	return result


static func _counts(clips: Array[String]) -> Dictionary:
	var counts := {}
	for clip in clips:
		counts[clip] = counts.get(clip, 0) + 1
	return counts


# Клипы, которых у второй стороны меньше, чем у первой (с учётом кратности).
static func _excess(a: Dictionary, b: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for clip in a:
		var extra: int = a[clip] - b.get(clip, 0)
		for i in extra:
			out.append(clip)
	out.sort()
	return out


static func report(result: Dictionary) -> String:
	if result.verdict == "error":
		return "МАНИФЕСТЫ: ошибка чтения\n  " + str(result.error)

	var lines: Array[String] = []

	if result.verdict == "match":
		lines.append("МАНИФЕСТЫ СОВПАЛИ: %d клипов, тот же порядок." % result.size_ref)
		lines.append("  anim_id пригоден как точный ключ — индексы сторон указывают на один клип.")
	elif result.verdict == "composition":
		lines.append("МАНИФЕСТЫ РАЗОШЛИСЬ ПО СОСТАВУ: у эталона %d клипов, у порта %d."
			% [result.size_ref, result.size_port])
		lines.append(_list("  только у эталона", result.only_ref))
		lines.append(_list("  только у порта", result.only_port))
		lines.append("  Построчный дифф трасс не запускается: сравнивать нечего.")
	else:
		lines.append("МАНИФЕСТЫ РАЗОШЛИСЬ ПО ПОРЯДКУ: набор клипов одинаков (%d), порядок — нет."
			% result.size_ref)
		lines.append("  первый разошедшийся индекс: %d" % result.first_index)
		lines.append("  Выбор клипа расходится БЕЗ ошибки в логике: стабильная сортировка отбора")
		lines.append("  разрешает равные ключи порядком исходного списка.")
		lines.append("  Построчный дифф трасс не запускается: сравнивать нечего.")

	lines.append("  дубли пары anim_name+foot: эталон %d, порт %d%s"
		% [result.dup_ref, result.dup_port,
			"" if result.dup_ref == 0 and result.dup_port == 0
			else " — строки с такими именами дифф трасс сравнивает по anim_id"])
	return "\n".join(lines)


static func _list(caption: String, clips: Array) -> String:
	if clips.is_empty():
		return caption + ": нет"
	var shown: Array[String] = []
	for i in min(clips.size(), MAX_LISTED):
		shown.append(str(clips[i]).split("|")[0])
	var tail := "" if clips.size() <= MAX_LISTED else ", и ещё %d" % (clips.size() - MAX_LISTED)
	return "%s (%d): %s%s" % [caption, clips.size(), ", ".join(shown), tail]

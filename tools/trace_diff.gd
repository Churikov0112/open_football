extends SceneTree
# Дифф трасс: первый тик, на котором порт разошёлся с эталоном по дискретным полям.
#
#   godot --path <repo> --headless -s res://tools/trace_diff.gd -- \
#       out/ref.csv out/port.csv out/ref_manifest.csv out/port_manifest.csv tools/trace_whitelist.txt
#
# Коды возврата: 0 — дискретные поля совпали; 1 — расхождение, расхождение манифестов либо переезд
# контроля; 2 — не хватает аргументов, файл не читается или трасса сломана.
# Логика — в tools/oracle_trace.gd; манифесты сравниваются той же библиотекой, что у
# tools/manifest_diff.gd, первой стадией.

const Trace := preload("res://tools/oracle_trace.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		printerr("TRACE DIFF: нужны 5 аргументов после --: ",
			"<трасса эталона> <трасса порта> <манифест эталона> <манифест порта> <белый список>")
		quit(2)
		return

	var result := Trace.compare(_to_absolute(args[0]), _to_absolute(args[1]),
		_to_absolute(args[2]), _to_absolute(args[3]), _to_absolute(args[4]))
	print(Trace.report(result))

	if result.verdict == "error":
		quit(2)
	else:
		quit(0 if result.verdict == "match" else 1)


func _to_absolute(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)

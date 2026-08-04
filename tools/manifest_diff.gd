extends SceneTree
# Дифф манифестов коллекции клипов: сошлись ли у сторон коллекции вообще.
#
#   godot --path <repo> --headless -s res://tools/manifest_diff.gd -- \
#       out/ref_manifest.csv out/port_manifest.csv
#
# Коды возврата: 0 — совпали; 1 — разошлись; 2 — не хватает аргументов или файл не читается.
# Ту же проверку дифф трасс (tools/trace_diff.gd) делает своей первой стадией — логика одна на двоих
# и живёт в tools/oracle_manifest.gd.

const Manifest := preload("res://tools/oracle_manifest.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("MANIFEST DIFF: нужны 2 аргумента после --: <манифест эталона> <манифест порта>")
		quit(2)
		return

	var result := Manifest.compare(_to_absolute(args[0]), _to_absolute(args[1]))
	print(Manifest.report(result))

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

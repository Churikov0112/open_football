extends SceneTree
# Прогон порта по сценарию оракула: поднимает ball_lab в headless, включает сценарный
# проигрыватель и писатель трассы, кладёт трассу и манифест.
#
# Трасса эталона здесь ВХОД, а не только объект сравнения: из её первой строки берутся стартовые
# позиция и угол игрока и позиция мяча. Значит порядок цикла жёсткий — сначала прогон эталона,
# потом прогон порта, потом дифф.
#
#   godot --path <repo> --headless -s res://tools/run_scenario.gd -- \
#       tests/scenarios/walk_line.txt out/ref.csv out/port.csv out/port_manifest.csv
#
# Пути — либо абсолютные, либо относительно корня репозитория. Обычный запуск лабы этим скриптом
# не затрагивается: без SetupOracle сцена ведёт себя ровно как прежде.

var _lab: Node = null
var _scenario_path := ""
var _reference_path := ""
var _trace_path := ""
var _manifest_path := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		printerr("ORACLE FAIL: нужны 4 аргумента после --: ",
			"<сценарий> <трасса эталона> <выходная трасса> <выходной манифест>")
		quit(2)
		return

	_scenario_path = _to_absolute(args[0])
	_reference_path = _to_absolute(args[1])
	_trace_path = _to_absolute(args[2])
	_manifest_path = _to_absolute(args[3])

	_lab = load("res://scenes/lab/ball_lab.tscn").instantiate()
	get_root().add_child(_lab)


# Работа идёт здесь, а не в _initialize: _Ready лабы (загрузка коллекции клипов) отрабатывает
# только на первом кадре дерева, и до него у гуманоида ещё нет коллекции.
func _process(_delta: float) -> bool:
	if _lab == null:
		return true
	if not _lab.is_node_ready():
		return false

	if not _lab.SetupOracle(_scenario_path, _reference_path, _trace_path, _manifest_path):
		printerr("ORACLE FAIL: ", _lab.OracleError)
		quit(1)
		return true

	if not _lab.RunOracle():
		printerr("ORACLE FAIL: ", _lab.OracleError)
		quit(1)
		return true

	print("ORACLE OK: трасса ", _trace_path, ", манифест ", _manifest_path)
	quit(0)
	return true


func _to_absolute(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)

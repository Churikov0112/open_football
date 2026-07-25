extends SceneTree
## Headless-смоук MatchReferee: узел на stub-мяче/менеджере. Мяч за боковой при last_touch=team_1
## → эмитит restart_awarded(THROW_IN, team=2, spot на линии) И интерим-заглушка ставит мяч на
## точку + отдаёт владение ближайшему team_2. Проверяем сигнал и репозицию мяча.
##
## Судья теперь два метода (см. match_referee.gd): track_ball_bounds() — непрерывный трекинг
## перехода внутри→снаружи (зовётся match_manager БЕЗУСЛОВНО каждый кадр), tick() — решение о
## награде по уже взведённой защёлке (гейтится сет-писами/празднованием). Здесь мяч ставится
## сразу "снаружи" (позиция никогда не была "внутри" за время теста) — track_ball_bounds() ловит
## это как переход NONE→TOUCHLINE (т.к. внутреннее состояние _prev_exit стартует с NONE), так что
## оба метода нужно звать по порядку, как это делает match_manager. Регресс на "не уровень, а
## переход" — check_referee_edge_not_level.gd.
##
## Узлы создаются в _initialize (add_child), но реальные действия/проверки — в первом _process:
## только к этому моменту узлы «внутри дерева» и global_position считается корректно (в
## _initialize он возвращает identity). Все узлы — прямые дети root (identity), поэтому
## position(локальный) == global_position.

var _got := {}
var _ball: RigidBody3D
var _p1: CharacterBody3D
var _p2: CharacterBody3D
var _ref: MatchReferee
var _done := false

func _initialize() -> void:
	_ball = RigidBody3D.new()
	_ball.set_script(load("res://scripts/ball/ball_controller.gd"))
	root.add_child(_ball)
	_ball._last_release_time = -100000

	_p1 = CharacterBody3D.new()
	_p1.add_to_group("team_1")
	root.add_child(_p1)
	_p1.position = Vector3(0, 0.5, 10)

	_p2 = CharacterBody3D.new()
	_p2.add_to_group("team_2")
	root.add_child(_p2)
	_p2.position = Vector3(20, 0.5, 12)

	var mgr := _StubManager.new()
	mgr.field_length = 52.5
	mgr.field_width = 34.0
	root.add_child(mgr)

	_ref = load("res://scripts/match/match_referee.gd").new()
	root.add_child(_ref)
	_ref.setup(mgr, _ball, 2)
	_ref.restart_awarded.connect(func(t, tm, sp): _got = {"t": t, "tm": tm, "sp": sp})

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var ok := true

	# Мяч касался team_1, ушёл за боковую (+X). Узлы теперь в дереве — global_position корректен.
	_ball.set_dribbler(_p1)   # last_touch = p1 (team_1)
	_ball.release_dribble()
	_ball.position = Vector3(35.0, 0.11, 12.0)

	ok = _expect(_ref.state() == MatchReferee.State.LIVE, "старт LIVE") and ok
	_ref.track_ball_bounds()
	_ref.tick()

	ok = _expect(_got.has("t"), "restart_awarded эмитнут") and ok
	if _got.has("t"):
		ok = _expect(_got["t"] == RefereeLogic.Restart.THROW_IN, "тип = THROW_IN") and ok
		ok = _expect(_got["tm"] == 2, "исполняет team_2") and ok
		ok = _expect(is_equal_approx((_got["sp"] as Vector3).x, 34.0), "точка на боковой x=34") and ok
	# Интерим-заглушка: мяч поставлен на точку, владение у ближайшего team_2 (p2).
	ok = _expect(_ball.dribbler == _p2, "владение отдано team_2") and ok
	ok = _expect(_ref.state() == MatchReferee.State.LIVE, "после award снова LIVE") and ok

	if ok:
		print("CHECK PASS: referee_flow")
		quit(0)
	else:
		print("CHECK FAIL: referee_flow")
		quit(1)
	return true

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

# Stub-менеджер: судья читает только эти члены/методы.
class _StubManager extends Node:
	var field_length: float
	var field_width: float
	func is_celebrating() -> bool: return false
	func is_penalty_active() -> bool: return false
	func is_free_kick_active() -> bool: return false
	func is_corner_active() -> bool: return false
	func is_goal_kick_active() -> bool: return false
	func is_throw_in_active() -> bool: return false

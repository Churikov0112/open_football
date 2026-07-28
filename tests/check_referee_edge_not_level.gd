extends SceneTree
## Юнит-тест MatchReferee.track_ball_bounds()/tick(): судья реагирует на РЕАЛЬНЫЙ переход
## внутри→снаружи, а не на текущий уровень позиции. Регресс-тест на баг: мяч, который
## сет-пис-контроллер держит (CAUGHT) за пределами поля как часть расстановки (вброс — точка
## розыгрыша ЛЕЖИТ на боковой линии), не должен триггерить награду сразу после отпускания —
## сама позиция "снаружи" не изменилась между кадром CAUGHT и первым кадром после него, значит
## перехода не было. Но реальный ВТОРОЙ выход (после того как мяч честно вернулся в поле) обязан
## отработать как обычно — фикс не должен блокировать судью навсегда.
##
## Тестируем MatchReferee напрямую (как check_referee_flow.gd) — без загрузки match.tscn.

var _ball: RigidBody3D
var _p1: CharacterBody3D
var _p2: CharacterBody3D
var _ref: MatchReferee
var _got: Array = []
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
	_ref.restart_awarded.connect(func(t, tm, sp): _got.append({"t": t, "tm": tm, "sp": sp}))

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var ok := true

	# --- Часть 1: мяч ДЕРЖАТ (CAUGHT) за боковой — имитация вброса. Позиция "снаружи" всю
	# ---           расстановку, затем отпускают, всё ещё "снаружи" — награды быть НЕ должно.
	_ball.catch(_p1, _p1)                       # CAUGHT, last_touch=p1 (вбрасывающий team_1)
	_ball.position = Vector3(35.0, 0.11, 12.0)  # за боковой (half_width=34 + ball_radius~0.11)
	for i in range(3):                          # несколько кадров расстановки/прицела — держим
		_ref.track_ball_bounds()
	ok = _expect(_got.is_empty(), "нет награды, пока мяч CAUGHT снаружи") and ok

	_ball.release_dribble()                     # "бросок": мяч больше не CAUGHT...
	# ...но физически ещё НЕ отъехал за порог в этом же кадре (та самая гонка бага).
	_ref.track_ball_bounds()
	ok = _expect(_got.is_empty(), "нет спурной награды в первый кадр после release") and ok
	_ref.tick()
	ok = _expect(_got.is_empty(), "нет спурной награды после tick() сразу после release") and ok

	# --- Часть 2: мяч честно возвращается в поле, а ЗАТЕМ реально выходит второй раз —
	# ---           это должно отработать как обычный, настоящий выход (фикс не должен глушить
	# ---           судью навсегда после первого CAUGHT-эпизода).
	_ball.position = Vector3(0.0, 0.11, 12.0)   # вернулся в игру
	_ref.track_ball_bounds()
	_ball.position = Vector3(35.0, 0.11, 12.0)  # реальный повторный выход (не CAUGHT, живая физика)
	_ref.track_ball_bounds()
	_ref.tick()
	ok = _expect(_got.size() == 1, "реальный повторный выход награждён (получено " + str(_got.size()) + ")") and ok
	if not _got.is_empty():
		ok = _expect(_got[0]["t"] == RefereeLogic.Restart.THROW_IN, "тип = THROW_IN") and ok
		ok = _expect(_got[0]["tm"] == 2, "исполняет team_2 (противоположная last_touch=p1/team_1)") and ok

	if ok:
		print("CHECK PASS: referee edge-detect (не уровень) — CAUGHT-выход не награждается, настоящий выход награждается")
		quit(0)
	else:
		print("CHECK FAIL: referee_edge_not_level")
		quit(1)
	return true

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

# Stub-менеджер: судья читает только эти члены.
class _StubManager extends Node:
	var field_length: float
	var field_width: float
	func is_celebrating() -> bool: return false
	func is_penalty_active() -> bool: return false
	func is_free_kick_active() -> bool: return false
	func is_corner_active() -> bool: return false
	func is_goal_kick_active() -> bool: return false
	func is_throw_in_active() -> bool: return false

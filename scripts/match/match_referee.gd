class_name MatchReferee
extends Node
## Судья v1 (Этап 0). Автомат LIVE/DEAD. Детектит выход мяча за линии (BoundaryLogic),
## разрешает рестарт (RefereeLogic), эмитит сигналы. Интерим-режим detect+award: пока настоящих
## ИИ-стандартов нет, рестарт разрешается заглушкой — мяч на точку, владение исполняющей команде,
## снова LIVE, без церемонии. Гол/фол пробрасываются извне (менеджером).

signal restart_awarded(restart_type: int, team: int, spot: Vector3)
signal foul_called(spot: Vector3, team: int)

enum State { LIVE = 0, DEAD = 1 }

var _manager: Node
var _ball: Node
var _team_defending_neg: int = 2
var _state: int = State.LIVE

# --- Непрерывный трекинг границ (см. track_ball_bounds) ---
var _prev_exit: int = BoundaryLogic.Exit.NONE   # классификация с прошлого кадра — для детекта РЕАЛЬНОГО перехода
var _suppress_next_edge: bool = false           # взведено, пока мяч CAUGHT; следующий кадр после снятия — не переход, а перебазировка
var _pending_award_exit: int = BoundaryLogic.Exit.NONE  # "защёлка": реальный переход зафиксирован, награда ещё не выдана

func setup(manager: Node, ball: Node, team_defending_neg: int) -> void:
	_manager = manager
	_ball = ball
	_team_defending_neg = team_defending_neg

func state() -> int:
	return _state

## Непрерывный трекинг позиции мяча относительно границ — зовётся из match_manager
## БЕЗУСЛОВНО каждый физ-кадр, до всех ранних return сет-писов (в отличие от tick() ниже,
## который гейтится ими). Ловит РЕАЛЬНЫЙ переход внутри→снаружи (не "сейчас снаружи", а именно
## момент пересечения) — иначе мяч, который сет-пис-контроллер держит/кладёт снаружи поля как
## часть расстановки (вброс — единственный стандарт, где точка розыгрыша лежит НА границе),
## триггерил бы ложную награду сразу после отпускания: позиция "снаружи" сохраняется с прошлого
## кадра → перехода нет → защёлка не взводится. Реальный выход, случившийся ПОКА другой
## контроллер ещё владеет мячом (например, штрафной ещё не разрешил WATCH, а сам удар улетел
## за боковую), не теряется — защёлка взводится независимо от того, гейтится ли tick() в этот
## момент; award() лишь читает уже взведённый факт, когда контроллер наконец отпустит мяч.
##
## CAUGHT (мяч в руках — не живая физика, кто-то его туда СТАВИТ) обрабатывается отдельно: пока
## CAUGHT, мы держим _prev_exit в курсе актуальной позиции, но защёлку не взводим (позиция снаружи
## тут не результат пересечения линии физикой). Первый кадр ПОСЛЕ снятия CAUGHT — перебазировка:
## берём текущую позицию за новую точку отсчёта, не считая её переходом. С этого момента снова
## работает обычное отслеживание — поэтому мяч, пойманный УЖЕ за пределами (напр. вратарь ловит
## мяч, который улетел мимо ворот — гипотетический будущий кейс), тоже отработает верно: сам факт
## пересечения линии фиксируется независимо от поимки, ДО неё, а не в момент отпускания.
func track_ball_bounds() -> void:
	if _ball == null or not is_instance_valid(_ball):
		return
	var caught: bool = _ball.has_method(&"is_caught") and _ball.is_caught()
	var exit := BoundaryLogic.classify(_ball.global_position,
		_manager.field_length, _manager.field_width,
		FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.BALL_RADIUS)
	if caught:
		_prev_exit = exit
		_suppress_next_edge = true
		return
	if _suppress_next_edge:
		_suppress_next_edge = false
		_prev_exit = exit
		return
	if _prev_exit == BoundaryLogic.Exit.NONE and exit != BoundaryLogic.Exit.NONE:
		_pending_award_exit = exit
	elif exit == BoundaryLogic.Exit.NONE:
		_pending_award_exit = BoundaryLogic.Exit.NONE
	_prev_exit = exit

## Решение о награде (зовётся из match_manager._physics_process, гейтится "нет активного
## сет-писа/не празднование" — та же причина, что раньше: пока стандарт владеет мячом, только
## он вправе его переставлять). Сам позицию НЕ проверяет — читает защёлку из track_ball_bounds(),
## взведённую независимо от гейта.
func tick() -> void:
	if _state != State.LIVE:
		return
	if _pending_award_exit == BoundaryLogic.Exit.NONE:
		return
	if _ball == null or not is_instance_valid(_ball):
		return
	var lt: Node = _ball.last_touch
	if lt == null or not is_instance_valid(lt):
		return   # некому атрибутировать — не судим (напр. до первого касания)
	var exit := _pending_award_exit
	_pending_award_exit = BoundaryLogic.Exit.NONE
	_award_ball_out(exit, lt)

func _award_ball_out(exit: int, last_touch: Node) -> void:
	var lt_team := 1 if last_touch.is_in_group("team_1") else 2
	var res := RefereeLogic.ball_out_restart(exit, lt_team, _team_defending_neg)
	var spot := _spot_for(res["restart"], exit)
	_state = State.DEAD
	# Сигнал синхронен: подписчик-диспетчер (match_manager) поднимает реальный контроллер ПРЯМО
	# здесь, до возврата. Для GOAL_KICK интерим не нужен — контроллер уже владеет мячом.
	restart_awarded.emit(res["restart"], res["team"], spot)
	if res["restart"] != RefereeLogic.Restart.GOAL_KICK:
		_interim_award(res["team"], spot)
	_state = State.LIVE

## Точка рестарта по типу и стороне выхода.
func _spot_for(restart: int, exit: int) -> Vector3:
	var hl: float = _manager.field_length
	var hw: float = _manager.field_width
	var r := FootballConstants.BALL_RADIUS
	match restart:
		RefereeLogic.Restart.THROW_IN:
			return BoundaryLogic.throw_in_spot(_ball.global_position, hw, r)
		RefereeLogic.Restart.CORNER:
			return BoundaryLogic.corner_spot(_ball.global_position, hl, hw, exit, FootballConstants.CORNER_INSET, r)
		RefereeLogic.Restart.GOAL_KICK:
			return BoundaryLogic.goal_kick_spot(exit, hl, FootballConstants.GOAL_AREA_DEPTH, r)
		_:
			return Vector3(0.0, r, 0.0)

## Интерим-заглушка: мяч на точку, владение ближайшему полевому исполняющей команды. БЕЗ
## церемонии/камеры. Заменяется настоящими контроллерами в Этапах 1–2.
func _interim_award(team: int, spot: Vector3) -> void:
	if _ball.has_method(&"release_dribble"):
		_ball.release_dribble()
	if _ball.has_method(&"clear_last_kicker"):
		_ball.clear_last_kicker()
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = spot + Vector3(0, FootballConstants.RESET_BALL_Y, 0)
	var group := "team_1" if team == 1 else "team_2"
	var nodes := get_tree().get_nodes_in_group(group)
	var positions: Array = []
	for n in nodes:
		positions.append((n as Node3D).global_position)
	var idx := RefereeLogic.select_taker(spot, positions)
	if idx >= 0 and _ball.has_method(&"set_dribbler"):
		_ball.set_dribbler(nodes[idx], true)

## Гол (зовёт менеджер из goal-area с уже вычисленной пропустившей командой — атрибуция по тому,
## в какие ворота влетел мяч, не по last_touch). Эмитит сигнал (для будущих слушателей — напр.
## RefereeAvatar); фактический запуск кикоффа менеджер делает напрямую через _dispatch_kickoff
## после окончания празднования (см. _celebrate_then_reset) — не через подписку на этот сигнал,
## т.к. кикофф не должен стартовать, пока идёт 5-секундная церемония гола.
func report_goal(conceding_team: int) -> void:
	restart_awarded.emit(RefereeLogic.Restart.KICKOFF, conceding_team, Vector3.ZERO)

## Фол подката (зовёт менеджер). Интерим: сигнал foul_called + restart_awarded, без запуска
## контроллера штрафного/пенальти (Этап 2). Заглушку владения НЕ делаем — фол-геометрия и
## расстановка сложнее аута, оставляем настоящему контроллеру.
func report_tackle_foul(foul_pos: Vector3, fouler: Node, fouled: Node) -> void:
	var fouler_team := 1 if fouler.is_in_group("team_1") else 2
	var fouled_team := 1 if fouled.is_in_group("team_1") else 2
	foul_called.emit(foul_pos, fouler_team)
	var res := RefereeLogic.foul_restart(foul_pos, fouler_team, fouled_team,
		_manager.field_length, _team_defending_neg,
		FootballConstants.PENALTY_AREA_DEPTH, FootballConstants.PENALTY_AREA_WIDTH * 0.5)
	restart_awarded.emit(res["restart"], res["team"], foul_pos)

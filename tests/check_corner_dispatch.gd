extends SceneTree
## Диспетчеризация углового судьёй. Грузит match.tscn. Проверяет: (1) прогон через _award_ball_out
## для CORNER поднимает контроллер и НЕ делает интерим (мяч без дриблера); (2) restart_awarded(CORNER,
## team=2) → AICornerIntent + Role.NONE, атакующая группа team_2; (3) team=1 → HumanKickerIntent +
## Role.KICKER, атакующая группа team_1.

var _mm: Node
var _elapsed: float = 0.0
var _state: int = 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.3:
				# (1) Мяч ушёл за -Z лицевую от ЗАЩИТНИКА -Z (team_2) → угловой team_1. Интерим для
				# CORNER не должен сработать; контроллер владеет мячом (dribbler освобождён).
				if _mm._kickoff != null and _mm._kickoff.is_active():
					_mm._kickoff._release()
				_mm._celebrating = false
				var defender = _mm._team_away.outfield()[0]   # team_2 защищает -Z
				_mm._referee._award_ball_out(BoundaryLogic.Exit.GOAL_LINE_NEG, defender)
				if not _mm.is_corner_active():
					print("CHECK FAIL: _award_ball_out(CORNER) не поднял контроллер"); return true
				if _mm.ball.dribbler != null:
					print("CHECK FAIL: интерим сработал для CORNER (мяч у дриблера)"); return true
				_mm._corner._release()
				_state = 1
		1:
			if _elapsed > 0.6:
				# (2) team_2 подаёт (ИИ).
				_mm._referee.restart_awarded.emit(RefereeLogic.Restart.CORNER, 2, Vector3(30.0, 0.11, _mm.field_length))
				if not _mm.is_corner_active():
					print("CHECK FAIL: диспетч team_2 не поднял контроллер"); return true
				var cn = _mm._corner
				var is_ai: bool = cn._intent is AICornerIntent
				var role_none: bool = cn._presentation.owns_camera() == false
				var att2: bool = cn._att_group == &"team_2"
				print("DISPATCH team_2: is_ai=", is_ai, " role_none=", role_none, " att_t2=", att2, " side=", cn._side)
				if not (is_ai and role_none and att2):
					print("CHECK FAIL: team_2 — is_ai=", is_ai, " role_none=", role_none, " att_t2=", att2); return true
				cn._release()
				_state = 2
		2:
			if not _mm.is_corner_active() and _elapsed > 0.9:
				# (3) team_1 подаёт (человек).
				_mm._referee.restart_awarded.emit(RefereeLogic.Restart.CORNER, 1, Vector3(-30.0, 0.11, -_mm.field_length))
				if not _mm.is_corner_active():
					print("CHECK FAIL: диспетч team_1 не поднял контроллер"); return true
				var cn = _mm._corner
				var is_human: bool = cn._intent is HumanKickerIntent
				var role_kicker: bool = cn._presentation.owns_hud() == true
				var att1: bool = cn._att_group == &"team_1"
				print("DISPATCH team_1: is_human=", is_human, " role_kicker=", role_kicker, " att_t1=", att1, " side=", cn._side)
				if is_human and role_kicker and att1:
					print("CHECK PASS: corner_dispatch")
					quit(0)
				else:
					print("CHECK FAIL: team_1 — is_human=", is_human, " role_kicker=", role_kicker, " att_t1=", att1)
					quit(1)
				return true
	if _elapsed > 8.0:
		print("CHECK FAIL: таймаут"); return true
	return false

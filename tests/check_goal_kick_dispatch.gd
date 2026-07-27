extends SceneTree
## Диспетчеризация удара от ворот судьёй. Грузит match.tscn. Проверяет: (1) прогон через
## _award_ball_out для GOAL_KICK поднимает контроллер и НЕ делает интерим (мяч без дриблера);
## (2) restart_awarded(GOAL_KICK, team=2) → AIGoalKickIntent + Role.NONE, вратарь team_2;
## (3) team=1 → HumanKickerIntent + Role.KICKER, вратарь team_1.

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
				# (1) Мяч ушёл за -Z лицевую от атакующего team_1 → удар от ворот team_2.
				# Прогон через сам судейский путь: интерим НЕ должен сработать для GOAL_KICK.
				if _mm._kickoff != null and _mm._kickoff.is_active():
					_mm._kickoff._release()
				_mm._celebrating = false
				var attacker = _mm._team_home.outfield()[0]   # team_1 атакует -Z
				_mm._referee._award_ball_out(BoundaryLogic.Exit.GOAL_LINE_NEG, attacker)
				if not _mm.is_goal_kick_active():
					print("CHECK FAIL: _award_ball_out(GOAL_KICK) не поднял контроллер"); return true
				# `dribbler` — публичное поле ball_controller (не метод). Интерим (set_dribbler)
				# для GOAL_KICK не должен сработать; контроллер владеет мячом (dribbler освобождён).
				if _mm.ball.dribbler != null:
					print("CHECK FAIL: интерим сработал для GOAL_KICK (мяч у дриблера)"); return true
				_mm._goal_kick._release()
				_state = 1
		1:
			if _elapsed > 0.6:
				# (2) team_2 бьёт (ИИ).
				_mm._referee.restart_awarded.emit(RefereeLogic.Restart.GOAL_KICK, 2, Vector3(0, 0.11, -40.0))
				if not _mm.is_goal_kick_active():
					print("CHECK FAIL: диспетч team_2 не поднял контроллер"); return true
				var gk = _mm._goal_kick
				var is_ai: bool = gk._intent is AIGoalKickIntent
				var role_none: bool = gk._presentation.owns_camera() == false
				var kt2: bool = gk._keeper.is_in_group(&"team_2")
				print("DISPATCH team_2: is_ai=", is_ai, " role_none=", role_none, " keeper_t2=", kt2)
				if not (is_ai and role_none and kt2):
					print("CHECK FAIL: team_2 — is_ai=", is_ai, " role_none=", role_none, " keeper_t2=", kt2); return true
				gk._release()
				_state = 2
		2:
			if not _mm.is_goal_kick_active() and _elapsed > 0.9:
				# (3) team_1 бьёт (человек).
				_mm._referee.restart_awarded.emit(RefereeLogic.Restart.GOAL_KICK, 1, Vector3(0, 0.11, 40.0))
				if not _mm.is_goal_kick_active():
					print("CHECK FAIL: диспетч team_1 не поднял контроллер"); return true
				var gk = _mm._goal_kick
				var is_human: bool = gk._intent is HumanKickerIntent
				var role_kicker: bool = gk._presentation.owns_hud() == true
				var kt1: bool = gk._keeper.is_in_group(&"team_1")
				print("DISPATCH team_1: is_human=", is_human, " role_kicker=", role_kicker, " keeper_t1=", kt1)
				if is_human and role_kicker and kt1:
					print("CHECK PASS: goal_kick_dispatch")
					quit(0)
				else:
					print("CHECK FAIL: team_1 — is_human=", is_human, " role_kicker=", role_kicker, " keeper_t1=", kt1)
					quit(1)
				return true
	if _elapsed > 8.0:
		print("CHECK FAIL: таймаут"); return true
	return false

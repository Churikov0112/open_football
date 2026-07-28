extends SceneTree
## Диспетч вброса судьёй. (1) _award_ball_out(TOUCHLINE) поднимает контроллер и НЕ делает интерим;
## (2) restart_awarded(THROW_IN, 2) → AIThrowInIntent + Role.NONE, вбрасывает team_2; (3) team=1 →
## Human + Role.KICKER. Грузит match.tscn.

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
				if _mm._kickoff.is_active():
					_mm._kickoff._release()
				_mm._celebrating = false
				# Мяч за правой боковой, последним касался team_1 → вброс team_2.
				_mm.ball.global_position = Vector3(30.0, 0.11, 8.0)
				var last_touch = _mm._team_home.outfield()[0]
				_mm._referee._award_ball_out(BoundaryLogic.Exit.TOUCHLINE, last_touch)
				if not _mm.is_throw_in_active():
					print("CHECK FAIL: _award_ball_out(THROW_IN) не поднял контроллер (интерим?)"); return true
				var ti = _mm._throw_in
				var is_ai: bool = ti._intent is AIThrowInIntent
				var role_none: bool = ti._presentation.owns_camera() == false
				var t2: bool = ti._thrower.is_in_group(&"team_2")
				print("DISPATCH team_2: is_ai=", is_ai, " role_none=", role_none, " thrower_t2=", t2)
				if not (is_ai and role_none and t2):
					print("CHECK FAIL: team_2 — is_ai=", is_ai, " role_none=", role_none, " thrower_t2=", t2); return true
				ti._release()
				_state = 1
		1:
			if not _mm.is_throw_in_active() and _elapsed > 0.6:
				_mm.ball.global_position = Vector3(30.0, 0.11, 8.0)
				_mm._referee.restart_awarded.emit(RefereeLogic.Restart.THROW_IN, 1, Vector3(34, 0.11, 8))
				if not _mm.is_throw_in_active():
					print("CHECK FAIL: диспетч team_1 не поднял контроллер"); return true
				var ti = _mm._throw_in
				var is_human: bool = ti._intent is HumanKickerIntent
				var role_kicker: bool = ti._presentation.owns_hud() == true
				var t1: bool = ti._thrower.is_in_group(&"team_1")
				print("DISPATCH team_1: is_human=", is_human, " role_kicker=", role_kicker, " thrower_t1=", t1)
				if is_human and role_kicker and t1:
					print("CHECK PASS: throw_in_dispatch")
					quit(0)
				else:
					print("CHECK FAIL: team_1 — is_human=", is_human, " role_kicker=", role_kicker, " thrower_t1=", t1)
					quit(1)
				return true
	if _elapsed > 8.0:
		print("CHECK FAIL: таймаут"); return true
	return false

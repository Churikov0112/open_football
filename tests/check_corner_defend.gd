extends SceneTree
## ИИ-угловой (team_2, Role.NONE) → человек защищается: его команда ЖИВАЯ (моторы не залочены),
## подающая заморожена, подкат запрещён, стена 9.15 м держит защитника (он её слушает), управление
## не ушло на team_2. Грузит match.tscn.

var _mm: Node
var _elapsed: float = 0.0
var _state: int = 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _locked(body) -> bool:
	var m = PlayerMotor.find_on(body)
	return m != null and m._locked

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.3:
				if _mm._kickoff.is_active():
					_mm._kickoff._release()
				_mm._celebrating = false
				_mm._dispatch_corner(2, Vector3(30.0, 0.11, _mm.field_length))
				if not _mm.is_corner_active() or _mm._corner.camera_is_owned():
					print("CHECK FAIL: ожидался активный ИИ-угловой (Role.NONE)"); return true

				var defender = _mm._team_home.outfield()[0]
				if _locked(defender):
					print("CHECK FAIL: защитник team_1 залочен (должен играть)"); return true

				var kicker = _mm._corner._kicker
				if not _locked(kicker):
					print("CHECK FAIL: бьющий team_2 не заморожен"); return true

				if _mm._try_tackle(_mm.controlled_player) != false:
					print("CHECK FAIL: подкат разрешён во время углового"); return true

				if _mm.controlled_player != null and _mm.controlled_player.is_in_group(&"team_2"):
					print("CHECK FAIL: управление ушло на team_2"); return true

				if _mm._corner._block_wall == null or not is_instance_valid(_mm._corner._block_wall):
					print("CHECK FAIL: стена 9.15 м не построена"); return true
				if (defender.collision_mask & FootballConstants.SETPIECE_BLOCK_LAYER) == 0:
					print("CHECK FAIL: защитник не слушает стену (нет бита)"); return true

				_mm._corner._release()
				if _mm._corner._block_wall != null:
					print("CHECK FAIL: стена не снята после розыгрыша"); return true
				if (defender.collision_mask & FootballConstants.SETPIECE_BLOCK_LAYER) != 0:
					print("CHECK FAIL: бит стены не убран из mask"); return true

				print("CHECK PASS: corner_defend")
				quit(0)
				return true
	if _elapsed > 8.0:
		print("CHECK FAIL: таймаут"); return true
	return false

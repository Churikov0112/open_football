extends SceneTree
## start(2) поднимает вброс СТОРОНЫ team_2 (вбрасывающий — team_2), и при Role.NONE управление не
## уходит на team_2. start(1) → вбрасывающий team_1 + управление ему (Role.KICKER). Грузит match.tscn.

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
				# Мяч у правой боковой — точка аута валидна.
				_mm.ball.global_position = Vector3(30.0, 0.11, 8.0)
				# team_2 (ИИ) вбрасывает, Role.NONE.
				_mm._throw_in.start(2, null, SetPiecePresentation.new(SetPiecePresentation.Role.NONE))
				if not _mm.is_throw_in_active():
					print("CHECK FAIL: вброс team_2 не активен"); return true
				if not _mm._throw_in._thrower.is_in_group(&"team_2"):
					print("CHECK FAIL: вбрасывающий не team_2"); return true
				if _mm._throw_in.camera_is_owned():
					print("CHECK FAIL: Role.NONE не должен владеть камерой"); return true
				if _mm.controlled_player != null and _mm.controlled_player.is_in_group(&"team_2"):
					print("CHECK FAIL: ИИ-вброс отдал управление team_2"); return true
				_mm._throw_in._release()
				_state = 1
		1:
			if not _mm.is_throw_in_active() and _elapsed > 0.6:
				_mm.ball.global_position = Vector3(30.0, 0.11, 8.0)
				# team_1 (человек) вбрасывает, Role.KICKER.
				_mm._throw_in.start(1, null, SetPiecePresentation.new(SetPiecePresentation.Role.KICKER))
				if not _mm.is_throw_in_active():
					print("CHECK FAIL: вброс team_1 не активен"); return true
				if not _mm._throw_in._thrower.is_in_group(&"team_1"):
					print("CHECK FAIL: вбрасывающий не team_1"); return true
				if _mm.controlled_player != _mm._throw_in._thrower:
					print("CHECK FAIL: управление не передано вбрасывающему team_1"); return true
				print("CHECK PASS: throw_in_start_side")
				quit(0)
				return true
	if _elapsed > 8.0:
		print("CHECK FAIL: таймаут"); return true
	return false

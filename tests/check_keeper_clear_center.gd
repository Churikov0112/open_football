extends SceneTree
## Вынос вратаря к центру (X/CLEAR_CENTER): мяч улетает от ворот вглубь поля.
## Кикофф гасим (иначе он держит мяч в центре и сбрасывает инъекцию); мяч кладём К ВРАТАРЮ
## перед ловлей (иначе _handle_dribbling видит пойманный мяч далеко и отпускает по DRIBBLE_KEEP_DIST).
class FakeHandsIntent extends KeeperHandsIntent:
	func held_action() -> int: return KeeperHandsIntent.Action.CLEAR_CENTER
var _mm; var _k; var _b; var _f := 0; var _fired := false; var _z0 := 0.0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 5:
		_mm.set_kickoff_active(false)   # живая игра: кикофф больше не держит мяч в центре
		_k = _mm._team_home.keeper(); _b = _k.brain()
		_b._hands_intent_override = FakeHandsIntent.new()
		_mm.ball.global_position = _k.global_position + Vector3(0, 1.0, 0)
		_mm.ball.catch(_k, _b.hold_point); _b._enter_hands()
		return
	if _f == 8:
		_z0 = _mm.ball.global_position.z; _fired = true
		return
	if _f == 60 and _fired:
		var into: float = signf(-_b.goal_line_z)   # от ворот в поле
		var progressed: float = (_mm.ball.global_position.z - _z0) * into
		if _mm.ball.dribbler == _k or _mm.ball.is_caught():
			print("CHECK FAIL: мяч не вынесен (в руках)"); quit(1); return
		if progressed < 3.0:
			print("CHECK FAIL: мяч не улетел от ворот к центру (progressed=", progressed, ")"); quit(1); return
		print("CHECK PASS: keeper center clear (X)"); quit(0); return

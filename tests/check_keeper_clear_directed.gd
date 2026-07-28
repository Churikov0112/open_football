extends SceneTree
## Направленный вынос вратаря (B/CLEAR_DIRECTED) по стику: мяч уходит в сторону прицела (+x).
## Кикофф гасим, мяч кладём к вратарю (см. check_keeper_clear_center про причины).
class FakeHandsIntent extends KeeperHandsIntent:
	var a := Vector2(1.0, 0.5)   # прицел: вбок(+x) и вглубь(+y)
	var act := KeeperHandsIntent.Action.CLEAR_DIRECTED
	func aim_axis() -> Vector2: return a
	func held_action() -> int: return act
var _mm; var _k; var _b; var _fake; var _f := 0; var _fired := false; var _x0 := 0.0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 5:
		_mm.set_kickoff_active(false)
		_k = _mm._team_home.keeper(); _b = _k.brain()
		_fake = FakeHandsIntent.new()
		_b._hands_intent_override = _fake
		_mm.ball.global_position = _k.global_position + Vector3(0, 1.0, 0)
		_mm.ball.catch(_k, _b.hold_point); _b._enter_hands()
		return
	if _f == 10:
		# держим B — зарядка; затем отпустим, чтобы пошёл выпуск (charge-as-timer, Задача 4).
		_x0 = _mm.ball.global_position.x; _fired = true
		return
	if _f == 14:
		_fake.act = KeeperHandsIntent.Action.NONE   # отпустить заряд → выпуск
		return
	if _f == 70 and _fired:
		if _mm.ball.dribbler == _k or _mm.ball.is_caught():
			print("CHECK FAIL: мяч не вынесен направленно (в руках)"); quit(1); return
		var dx: float = _mm.ball.global_position.x - _x0
		if dx < 1.0:
			print("CHECK FAIL: мяч не ушёл вбок по прицелу (dx=", dx, ")"); quit(1); return
		print("CHECK PASS: keeper directed clear (B)"); quit(0); return

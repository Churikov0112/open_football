extends SceneTree
## Правило 6 секунд: вратарь с «пустым» интентом (ничего не жмёт) через KEEPER_SIX_SECOND_TIME
## сам выносит мяч (к центру) и управление уходит. Кикофф гасим, мяч кладём к вратарю.
class Idle extends KeeperHandsIntent:
	func move_axis() -> Vector2: return Vector2.ZERO
	func held_action() -> int: return KeeperHandsIntent.Action.NONE
var _mm; var _k; var _b; var _f := 0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 5:
		_mm.set_kickoff_active(false)
		_k = _mm._team_home.keeper(); _b = _k.brain()
		_b._hands_intent_override = Idle.new()
		_mm.ball.global_position = _k.global_position + Vector3(0, 1.0, 0)
		_mm.ball.catch(_k, _b.hold_point); _b._enter_hands()
		return
	# 6 сек * 60 фпс = 360 физкадров; ждём с запасом.
	if _f == 5 + 360 + 40:
		if _b.is_hands_active():
			print("CHECK FAIL: через 6с всё ещё HANDS"); quit(1); return
		if _mm.ball.dribbler == _k or _mm.ball.is_caught():
			print("CHECK FAIL: через 6с мяч всё ещё в руках"); quit(1); return
		print("CHECK PASS: keeper six-second rule"); quit(0); return

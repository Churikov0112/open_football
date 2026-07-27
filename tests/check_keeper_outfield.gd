extends SceneTree
## OUTFIELD: дроп Y → мяч у ног вратаря (dribbler==keeper), keeper_ai заглушён; отобрать мяч →
## возврат в POSITION (AI-режим). Кикофф гасим, мяч кладём к вратарю.
class DropOnce extends KeeperHandsIntent:
	var fired := false
	func held_action() -> int:
		if fired: return KeeperHandsIntent.Action.NONE
		fired = true
		return KeeperHandsIntent.Action.DROP
var _mm; var _k; var _b; var _f := 0; var _dropped := false
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 5:
		_mm.set_kickoff_active(false)
		_k = _mm._team_home.keeper(); _b = _k.brain()
		_b._hands_intent_override = DropOnce.new()
		_mm.ball.global_position = _k.global_position + Vector3(0, 1.0, 0)
		_mm.ball.catch(_k, _b.hold_point); _b._enter_hands()
		return
	if _f == 20:
		# После дропа: мяч у ног вратаря, состояние OUTFIELD.
		if _mm.ball.dribbler != _k:
			print("CHECK FAIL: после Y мяч не у ног вратаря"); quit(1); return
		if _b._state != _b.State.OUTFIELD:
			print("CHECK FAIL: не в OUTFIELD после Y (state=", _b._state, ")"); quit(1); return
		_dropped = true
		# Отбираем мяч (эмулируем потерю): release_dribble.
		_mm.ball.release_dribble()
		return
	if _f == 50 and _dropped:
		if _b._state != _b.State.POSITION:
			print("CHECK FAIL: не вернулся в POSITION после потери мяча (state=", _b._state, ")"); quit(1); return
		print("CHECK PASS: keeper outfield drop + return to AI"); quit(0); return

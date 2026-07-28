extends SceneTree
## OUTFIELD: дроп Y → мяч у ног вратаря (dribbler==keeper), keeper_ai заглушён.
## Потеря мяча ВНЕ штрафной → RETURNING: рывок ДОМОЙ (без телепорта в штрафную, без ловли руками),
## по прибытии → POSITION. Кикофф гасим, мяч кладём к вратарю.
class DropOnce extends KeeperHandsIntent:
	var fired := false
	func held_action() -> int:
		if fired: return KeeperHandsIntent.Action.NONE
		fired = true
		return KeeperHandsIntent.Action.DROP
var _mm; var _k; var _b; var _f := 0; var _dropped := false; var _out_z := 0.0
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
		if _mm.ball.dribbler != _k:
			print("CHECK FAIL: после Y мяч не у ног вратаря"); quit(1); return
		if _b._state != _b.State.OUTFIELD:
			print("CHECK FAIL: не в OUTFIELD после Y (state=", _b._state, ")"); quit(1); return
		_dropped = true
		# Выводим вратаря ВНЕ штрафной (мидфилд) и отбираем мяч — эмуляция потери в поле.
		var into = signf(-_b.goal_line_z)
		_out_z = _b.goal_line_z + into * 20.0   # ~20 м от линии ворот, вне штрафной
		_k.global_position = Vector3(0, _k.global_position.y, _out_z)
		_mm.ball.release_dribble()
		return
	if _f == 26 and _dropped:
		# Сразу после потери: рывок домой (RETURNING), НЕ схватил руками, НЕ телепортировался в штрафную.
		if _mm.ball.is_caught():
			print("CHECK FAIL: вратарь схватил мяч руками при потере"); quit(1); return
		if _b._state != _b.State.RETURNING:
			print("CHECK FAIL: не RETURNING после потери мяча вне штрафной (state=", _b._state, ")"); quit(1); return
		# Ещё не дома (не телепортировался): |z - out_z| мал.
		if absf(_k.global_position.z - _out_z) > 4.0:
			print("CHECK FAIL: вратарь телепортировался (z=", _k.global_position.z, " out_z=", _out_z, ")"); quit(1); return
		return
	if _f == 220 and _dropped:
		if _mm.ball.is_caught():
			print("CHECK FAIL: вратарь схватил мяч руками в возврате"); quit(1); return
		if _b._state != _b.State.POSITION:
			print("CHECK FAIL: не вернулся в POSITION домой (state=", _b._state, ")"); quit(1); return
		# Дома: в пределах вратарской площади (базовая стойка — её центр, ~2.75м + допуск прибытия).
		if absf(_k.global_position.z - _b.goal_line_z) > FootballConstants.GOAL_AREA_DEPTH:
			print("CHECK FAIL: вратарь не добежал домой (z=", _k.global_position.z, ")"); quit(1); return
		print("CHECK PASS: keeper outfield loss → sprint home → POSITION (no hands, no teleport)"); quit(0); return

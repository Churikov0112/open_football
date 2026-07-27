extends SceneTree
## Управляемый вратарь HANDS: ловля → HANDS (фейк-интент), движение в штрафной по move_axis.
## Фейк-интент скриптует KeeperHandsIntent без реального Input (как intent-seam тесты сет-писов).

class FakeHandsIntent extends KeeperHandsIntent:
	var mv := Vector2.ZERO
	var act := KeeperHandsIntent.Action.NONE
	func move_axis() -> Vector2: return mv
	func aim_axis() -> Vector2: return mv
	func held_action() -> int: return act

var _mm: Node
var _keeper: Node
var _brain: Node
var _fake: FakeHandsIntent
var _frames := 0
var _entered := false
var _start_pos := Vector3.ZERO

func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate()
	root.add_child(_mm)
	_fake = FakeHandsIntent.new()
	physics_frame.connect(_tick)

func _tick() -> void:
	_frames += 1
	if _frames == 5:
		_keeper = _mm._team_home.keeper()
		_brain = _keeper.brain()
		# Инжектируем фейк-интент: keeper_ai возьмёт его вместо диспетча (см. _enter_hands override-хук).
		_brain._hands_intent_override = _fake
		# Ставим мяч в руки вратаря и запускаем HANDS напрямую (минуя всю сейв-цепочку).
		_mm.ball.catch(_keeper, _brain.hold_point)
		_brain._enter_hands()
		return
	if _frames == 8:
		if not _brain.is_hands_active():
			print("CHECK FAIL: не вошёл в HANDS"); quit(1); return
		_entered = true
		_start_pos = _keeper.global_position
		_fake.mv = Vector2(1.0, 0.0)   # движение вбок (в штрафной)
		return
	if _frames == 40:
		var moved: float = _keeper.global_position.distance_to(_start_pos)
		if not _entered:
			print("CHECK FAIL: HANDS не активировался"); quit(1); return
		if moved < 0.3:
			print("CHECK FAIL: вратарь не двигался в HANDS по move_axis (moved=", moved, ")"); quit(1); return
		# Кламп: остался в штрафной по X (|x| <= полуширина).
		if absf(_keeper.global_position.x) > FootballConstants.PENALTY_AREA_WIDTH * 0.5 + 0.5:
			print("CHECK FAIL: вратарь вышел за штрафную по X: ", _keeper.global_position); quit(1); return
		return
	if _frames == 45:
		_fake.mv = Vector2.ZERO
		_fake.act = KeeperHandsIntent.Action.HAND   # зажали «рука» — заряжается
		return
	if _frames == 55:
		if _brain.hands_charge_ratio() <= 0.0:
			print("CHECK FAIL: заряд A не копится (ratio=", _brain.hands_charge_ratio(), ")"); quit(1); return
		_fake.act = KeeperHandsIntent.Action.NONE   # отпустили (выпуск — Задача 5; тут не проверяем гол)
		return
	if _frames == 60:
		print("CHECK PASS: keeper enters HANDS + moves in box")
		quit(0)

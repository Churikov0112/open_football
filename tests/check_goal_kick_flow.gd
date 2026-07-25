extends SceneTree
## Headless smoke-тест флоу удара от ворот: грузим match.tscn, стартуем розыгрыш и бьём
## (в обход Input), крутим кадры и проверяем — мяч получил импульс, режим снялся, без крашей.

var _mm: Node
var _gk: Node
var _elapsed: float = 0.0
var _started: bool = false
var _fired: bool = false
var _max_ball_speed: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 0.15 and not _started:
		_gk = _mm.get_node_or_null("GoalKickController")
		if _gk == null:
			print("CHECK FAIL: нет узла GoalKickController")
			return true
		_gk.start(_mm._keeper_at(-_mm.field_length), -_mm.field_length)
		_started = true
		if not _mm.is_goal_kick_active():
			print("CHECK FAIL: goal_kick-режим не включился после start")
			return true
		return false
	# Имитируем наземный пас на 70% заряда (минуем Input-заряд).
	if _elapsed > 0.3 and _started and not _fired:
		_gk._charge_kind = "ground"
		_gk._fire_charge(0.7)
		_fired = true
		return false
	if _fired:
		_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
	# Ждём завершения страйка (контакт ~1.35с) + запас.
	if _elapsed > 4.0:
		var released: bool = not _mm.is_goal_kick_active()
		var launched: bool = _max_ball_speed > 1.0
		print("SMOKE: max_ball_speed=", _max_ball_speed, " goal_kick_active=", _mm.is_goal_kick_active())
		if released and launched:
			print("CHECK PASS: goal_kick flow (launched + released)")
			quit(0)
		else:
			print("CHECK FAIL: released=", released, " launched=", launched)
			quit(1)
		return true
	return false

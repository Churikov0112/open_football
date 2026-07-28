extends SceneTree
## Headless-смоук флоу кикоффа: грузим match.tscn, стартуем розыгрыш team_1 и бьём (в обход
## Input), крутим кадры — мяч получил импульс, режим снялся, управление у партнёра.

var _mm: Node
var _kickoff: Node
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
		_kickoff = _mm.get_node_or_null("KickoffController")
		if _kickoff == null:
			print("CHECK FAIL: нет узла KickoffController")
			return true
		_kickoff.start(1)
		_started = true
		if not _mm.is_kickoff_active():
			print("CHECK FAIL: kickoff-режим не включился после start")
			return true
		return false
	if _elapsed > 0.3 and _started and not _fired:
		_kickoff._fire_charge(0.7)
		_fired = true
		return false
	if _fired:
		_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
	if _elapsed > 4.0:
		var released: bool = not _mm.is_kickoff_active()
		var launched: bool = _max_ball_speed > 1.0
		print("SMOKE: max_ball_speed=", _max_ball_speed, " kickoff_active=", _mm.is_kickoff_active())
		if released and launched:
			print("CHECK PASS: kickoff flow (launched + released)")
			quit(0)
		else:
			print("CHECK FAIL: released=", released, " launched=", launched)
			quit(1)
		return true
	return false

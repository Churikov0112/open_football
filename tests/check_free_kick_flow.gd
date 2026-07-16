extends SceneTree
## Headless-смоук флоу штрафного: грузим match.tscn, стартуем розыгрыш и бьём (в обход Input),
## крутим кадры и проверяем — мяч получил импульс, режим штрафного снялся, без крашей.

var _mm: Node
var _fk: Node
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
		_fk = _mm.get_node_or_null("FreeKickController")
		if _fk == null:
			print("CHECK FAIL: нет узла FreeKickController")
			return true
		_fk.start(_mm.controlled_player, _mm._keeper.goal_line_z)
		_started = true
		if not _mm.is_free_kick_active():
			print("CHECK FAIL: режим штрафного не включился после start")
			return true
		return false
	if _elapsed > 0.3 and _started and not _fired:
		_fk._fire_shot(0.7)
		_fired = true
		return false
	if _fired:
		_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
	if _elapsed > 4.0:
		var released: bool = not _mm.is_free_kick_active()
		var launched: bool = _max_ball_speed > 1.0
		print("SMOKE: max_ball_speed=", _max_ball_speed, " free_kick_active=", _mm.is_free_kick_active())
		if released and launched:
			print("CHECK PASS: free_kick flow (launched + released)")
			quit(0)
		else:
			print("CHECK FAIL: released=", released, " launched=", launched)
			quit(1)
		return true
	return false

extends SceneTree
## Headless smoke-тест флоу углового: грузим match.tscn, стартуем розыгрыш и навешиваем (в обход
## Input), крутим кадры — мяч получил импульс, режим углового снялся, без крашей. Интерактив
## (прицел/камера/анимация) headless не покрывает.

var _mm: Node
var _corner: Node
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
		_corner = _mm.get_node_or_null("CornerController")
		if _corner == null:
			print("CHECK FAIL: нет узла CornerController")
			return true
		_corner.start(_mm.controlled_player, -_mm.field_length)
		_started = true
		if not _mm.is_corner_active():
			print("CHECK FAIL: режим углового не включился после start")
			return true
		return false
	# Имитируем навес B на 70% заряда (минуем Input).
	if _elapsed > 0.3 and _started and not _fired:
		_corner._start_charge("lob")
		_corner._fire_charge(0.7)
		_fired = true
		return false
	if _fired:
		_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
	if _elapsed > 4.0:
		var released: bool = not _mm.is_corner_active()
		var launched: bool = _max_ball_speed > 1.0
		print("SMOKE: max_ball_speed=", _max_ball_speed, " corner_active=", _mm.is_corner_active())
		if released and launched:
			print("CHECK PASS: corner flow (launched + released)")
			quit(0)
		else:
			print("CHECK FAIL: released=", released, " launched=", launched)
			quit(1)
		return true
	return false

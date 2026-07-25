extends SceneTree
## Seam-тест углового: контроллер потребляет инжектированный KickerIntent — вторичное действие
## (corner_call) зовёт короткого партнёра, lob-заряд + коммит бьют через шов. Драйв — match_manager.

class FakeKickerIntent extends KickerIntent:
	var start_variant: int = -1
	var committed: bool = false
	var secondary_now: bool = false
	func aim_axis() -> Vector2:
		return Vector2.ZERO
	func charge_start_variant() -> int:
		var v := start_variant
		start_variant = -1
		return v
	func charge_committed() -> bool:
		return committed
	func secondary() -> bool:
		var s := secondary_now
		secondary_now = false
		return s

var _mm: Node
var _corner: Node
var _fake: FakeKickerIntent
var _elapsed: float = 0.0
var _state: int = 0
var _max_ball_speed: float = 0.0
var _secondary_ok: bool = false

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.15:
				_corner = _mm.get_node_or_null("CornerController")
				if _corner == null:
					print("CHECK FAIL: нет узла CornerController"); return true
				_fake = FakeKickerIntent.new()
				_corner.start(_mm.controlled_player, _mm._keeper_brain.goal_line_z, _fake)
				if not _mm.is_corner_active():
					print("CHECK FAIL: режим углового не включился"); return true
				_state = 1
		1:
			# Вторичное действие: «нажали» corner_call — короткий партнёр должен быть вызван.
			if _elapsed > 0.4:
				_fake.secondary_now = true
				_state = 2
		2:
			if _elapsed > 0.55:
				_secondary_ok = bool(_corner._short_called)
				_fake.start_variant = 1    # 1 = lob (навес)
				_state = 3
		3:
			if _elapsed > 0.75:
				_fake.committed = true
				_state = 4
		4:
			_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
			if _elapsed > 4.0:
				var released: bool = not _mm.is_corner_active()
				var launched: bool = _max_ball_speed > 1.0
				print("SEAM: max_ball_speed=", _max_ball_speed, " secondary_ok=", str(_secondary_ok))
				if released and launched and _secondary_ok:
					print("CHECK PASS: corner intent seam (secondary + charge+commit через KickerIntent)")
					quit(0)
				else:
					print("CHECK FAIL: released=", str(released), " launched=", str(launched), " secondary_ok=", str(_secondary_ok))
					quit(1)
				return true
	if _elapsed > 6.0:
		print("CHECK FAIL: таймаут"); return true
	return false

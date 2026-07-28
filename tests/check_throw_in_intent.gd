extends SceneTree
## Seam-тест вброса: контроллер потребляет инжектированный KickerIntent (заряд+коммит через шов),
## а не Input. Драйв — match_manager делегирует update(); фейк-интент скриптует «нажатия».

class FakeKickerIntent extends KickerIntent:
	var start_variant: int = -1     # тест выставит один раз → «кнопка заряда нажата»
	var committed: bool = false     # тест выставит → «кнопка отпущена, выстрел»
	func aim_axis() -> Vector2:
		return Vector2.ZERO
	func charge_start_variant() -> int:
		var v := start_variant
		start_variant = -1          # one-shot, как just_pressed
		return v
	func charge_committed() -> bool:
		return committed

var _mm: Node
var _ti: Node
var _fake: FakeKickerIntent
var _elapsed: float = 0.0
var _state: int = 0
var _max_ball_speed: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.15:
				_ti = _mm.get_node_or_null("ThrowInController")
				if _ti == null:
					print("CHECK FAIL: нет узла ThrowInController"); return true
				_fake = FakeKickerIntent.new()
				_ti.start(1, _fake)   # сторона-агностичная сигнатура: team, intent, presentation
				if not _mm.is_throw_in_active():
					print("CHECK FAIL: throw-in-режим не включился"); return true
				_state = 1
		1:
			if _elapsed > 0.4:
				_fake.start_variant = 0    # «нажали» кнопку заряда через шов
				_state = 2
		2:
			if _elapsed > 0.6:
				_fake.committed = true     # «отпустили» через шов → выстрел
				_state = 3
		3:
			_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
			if _elapsed > 4.0:
				var released: bool = not _mm.is_throw_in_active()
				var launched: bool = _max_ball_speed > 1.0
				print("SEAM: max_ball_speed=", _max_ball_speed)
				if released and launched:
					print("CHECK PASS: throw_in intent seam (charge+commit через KickerIntent)")
					quit(0)
				else:
					print("CHECK FAIL: released=", str(released), " launched=", str(launched))
					quit(1)
				return true
	if _elapsed > 6.0:
		print("CHECK FAIL: таймаут"); return true
	return false

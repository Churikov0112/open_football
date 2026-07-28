extends SceneTree
## Headless smoke-тест флоу пенальти: грузим match.tscn, программно стартуем розыгрыш и бьём
## (в обход Input), крутим кадры и проверяем — мяч получил импульс, пенальти-режим снялся
## (release_after_strike), без крашей. Интерактивную «фил»-часть (прицел/камера/анимация)
## headless не покрывает — только логику страйка/запуска/возврата.

var _mm: Node
var _pen: Node
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
	# Даём сцене отработать _ready (~0.15с реального времени).
	if _elapsed > 0.15 and not _started:
		_pen = _mm.get_node_or_null("PenaltyController")
		if _pen == null:
			print("CHECK FAIL: нет узла PenaltyController")
			return true
		_pen.start_single(_mm.controlled_player, -_mm.field_length)
		_started = true
		if not _mm.is_penalty_active():
			print("CHECK FAIL: пенальти-режим не включился после start_single")
			return true
		return false
	# Имитируем удар на 70% заряда (минуем Input-заряд).
	if _elapsed > 0.3 and _started and not _fired:
		_pen._fire(0.7)
		_fired = true
		return false
	if _fired:
		_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
	# Ждём завершения страйка (контакт ~1.35с) + запас.
	if _elapsed > 4.0:
		var released: bool = not _mm.is_penalty_active()
		var launched: bool = _max_ball_speed > 1.0
		print("SMOKE: max_ball_speed=", _max_ball_speed, " penalty_active=", _mm.is_penalty_active())
		if released and launched:
			print("CHECK PASS: penalty flow (launched + released)")
			quit(0)
		else:
			print("CHECK FAIL: released=", released, " launched=", launched)
			quit(1)
		return true
	return false

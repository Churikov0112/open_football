class_name AIKeeperHandsIntent
extends KeeperHandsIntent
## ИИ-реализация v1 (заглушка): пауза «обдумывания», затем всегда вынос к центру (CLEAR_CENTER).
## move/aim = ZERO (не бегает). Апгрейд до полноценного решателя — позже, без правок keeper_ai.
## Время через переопределяемый _now_msec() (headless-тест без sleep).

var _start_msec: int
var _think_time: float

func _init(think_time: float) -> void:
	_think_time = think_time
	_start_msec = _now_msec()

func _now_msec() -> int:
	return Time.get_ticks_msec()

func held_action() -> int:
	if _now_msec() - _start_msec >= int(_think_time * 1000.0):
		return Action.CLEAR_CENTER
	return Action.NONE

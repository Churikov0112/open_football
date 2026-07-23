class_name AIKickerIntent
extends KickerIntent
## Простой ИИ-бьющий пенальти (стаб): пауза обдумывания → фиксированный прицел (случайная точка
## в створе) → фиксированный заряд → удар. ИИ-скрипт (не чистая логика) — читает FootballConstants.
## Время через переопределяемый _now_msec() (для headless-теста без sleep).

var _start_msec: int
var _charge_start_msec: int = -1
var _aim_target_v: Vector2

func _init(rng: RandomNumberGenerator) -> void:
	_start_msec = _now_msec()
	var hw := FootballConstants.GOAL_WIDTH * 0.5 * FootballConstants.AI_PENALTY_AIM_SPREAD
	var tx := rng.randf_range(-hw, hw)
	var ty := rng.randf_range(0.3, FootballConstants.GOAL_HEIGHT * 0.7)
	_aim_target_v = Vector2(tx, ty)

func _now_msec() -> int:
	return Time.get_ticks_msec()

func has_fixed_aim() -> bool:
	return true

func aim_target() -> Vector2:
	return _aim_target_v

func charge_start_variant() -> int:
	if _charge_start_msec >= 0:
		return -1
	if _now_msec() - _start_msec >= int(FootballConstants.AI_PENALTY_THINK_TIME * 1000.0):
		_charge_start_msec = _now_msec()
		return 0
	return -1

func charge_committed() -> bool:
	if _charge_start_msec < 0:
		return false
	return _now_msec() - _charge_start_msec >= int(FootballConstants.AI_PENALTY_CHARGE_RATIO * FootballConstants.PEN_CHARGE_MAX_TIME * 1000.0)

func foot_switch() -> int:
	return 0

func modifier_held() -> bool:
	return false

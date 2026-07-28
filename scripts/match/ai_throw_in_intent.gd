class_name AIThrowInIntent
extends KickerIntent
## ИИ-вбрасывающий: думает → доворачивает стиком на цель (aim_dir) → заряжает под power_ratio →
## бросает. Directional-playback (как AIGoalKickIntent). Читает FootballConstants. Время — _now_msec().
## Решение (кому/какой силой) принято ThrowInPlan в диспетчере — intent лишь проигрывает.

var _start_msec: int
var _turn_stick_x: float
var _turn_duration_msec: int
var _power_ratio: float
var _charge_start_msec: int = -1

func _init(into: Vector3, aim_dir: Vector3, power_ratio: float) -> void:
	_start_msec = _now_msec()
	_power_ratio = clampf(power_ratio, 0.0, 1.0)
	var angle := KickoffLogic.signed_angle_xz(into, aim_dir)
	_turn_stick_x = -signf(angle)
	_turn_duration_msec = int((absf(angle) / FootballConstants.THROW_AIM_SPEED) * 1000.0)

func _now_msec() -> int:
	return Time.get_ticks_msec()

func _think_end_msec() -> int:
	return _start_msec + int(FootballConstants.AI_THROWIN_THINK_TIME * 1000.0)

func aim_axis() -> Vector2:
	var elapsed := _now_msec() - _think_end_msec()
	if elapsed >= 0 and elapsed < _turn_duration_msec:
		return Vector2(_turn_stick_x, 0.0)
	return Vector2.ZERO

func charge_start_variant() -> int:
	if _charge_start_msec >= 0:
		return -1
	if _now_msec() < _think_end_msec() + _turn_duration_msec:
		return -1
	_charge_start_msec = _now_msec()
	return 0

func charge_committed() -> bool:
	if _charge_start_msec < 0:
		return false
	return _now_msec() - _charge_start_msec >= int(_power_ratio * FootballConstants.THROW_CHARGE_MAX_TIME * 1000.0)

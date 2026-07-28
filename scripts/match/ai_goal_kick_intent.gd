class_name AIGoalKickIntent
extends KickerIntent
## ИИ-бьющий удар от ворот: думает → доворачивает стиком на цель (aim_dir) → заряжает под
## power_ratio → выбирает ground/lob (variant) → бьёт. Directional-playback (как AIKickoffIntent).
## Читает FootballConstants (ИИ-скрипт, не чистая логика). Время — через _now_msec() (headless).
##
## Решение (кому/чем/какой силой) уже принято GoalKickPlan в диспетчере — intent лишь проигрывает
## его как «нажатия». spot/rng конструктору не нужны в v1: aim_dir уже дан, разброса нет (задел).

var _start_msec: int
var _turn_stick_x: float
var _turn_duration_msec: int
var _variant: int
var _power_ratio: float
var _charge_start_msec: int = -1

func _init(attack_dir: Vector3, aim_dir: Vector3, variant: int, power_ratio: float) -> void:
	_start_msec = _now_msec()
	_variant = variant
	_power_ratio = clampf(power_ratio, 0.0, 1.0)
	var angle := KickoffLogic.signed_angle_xz(attack_dir, aim_dir)
	_turn_stick_x = -signf(angle)
	_turn_duration_msec = int((absf(angle) / FootballConstants.GK_AIM_SPEED) * 1000.0)

func _now_msec() -> int:
	return Time.get_ticks_msec()

func _think_end_msec() -> int:
	return _start_msec + int(FootballConstants.AI_GOALKICK_THINK_TIME * 1000.0)

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
	return _variant

func charge_committed() -> bool:
	if _charge_start_msec < 0:
		return false
	return _now_msec() - _charge_start_msec >= int(_power_ratio * FootballConstants.GK_CHARGE_MAX_TIME * 1000.0)

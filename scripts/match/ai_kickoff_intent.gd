class_name AIKickoffIntent
extends KickerIntent
## ИИ-бьющий кикоффа: думает → доворачивает стиком точно на партнёра → заряжает → бьёт.
## Кикофф — направленческий стандарт (как вброс/штрафной/угловой/удар от ворот): контроллер
## каждый кадр читает aim_axis() и скармливает в FreeKickLogic.rotate_heading, как живой стик —
## has_fixed_aim()/aim_target() (механизм пенальти, точка В ПЛОСКОСТИ ВОРОТ) тут неприменимы.
##
## Геометрия (позиция кикера, base_heading, позиция партнёра) известна целиком на старте — угол
## доворота и его длительность (при известной скорости KICKOFF_AIM_SPEED) вычисляются один раз
## в _init, дальше aim_axis() лишь "проигрывает" готовый план (тот же принцип playback, что уже
## проверен у заряда AIKickerIntent). Без ошибки/характера — пас всегда точно на партнёра.

var _start_msec: int
var _turn_stick_x: float
var _turn_duration_msec: int
var _charge_start_msec: int = -1

func _init(kicker_pos: Vector3, base_heading: Vector3, partner_pos: Vector3) -> void:
	_start_msec = _now_msec()
	var to_partner := Vector3(partner_pos.x - kicker_pos.x, 0.0, partner_pos.z - kicker_pos.z)
	var target_dir := to_partner.normalized() if to_partner.length() > 0.001 else base_heading
	var angle := KickoffLogic.signed_angle_xz(base_heading, target_dir)
	_turn_stick_x = -signf(angle)
	_turn_duration_msec = int((absf(angle) / FootballConstants.KICKOFF_AIM_SPEED) * 1000.0)

func _now_msec() -> int:
	return Time.get_ticks_msec()

func _think_end_msec() -> int:
	return _start_msec + int(FootballConstants.AI_KICKOFF_THINK_TIME * 1000.0)

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
	return _now_msec() - _charge_start_msec >= int(FootballConstants.AI_KICKOFF_CHARGE_RATIO * FootballConstants.KICKOFF_CHARGE_MAX_TIME * 1000.0)

class_name HumanKeeperIntent
extends KeeperIntent
## Human-вратарь: зона нырка из квадранта стика (крутится вплоть до удара). Конфиг осей;
## ввод через переопределяемый _axis (для headless-теста). Дедзона 0.15 (как порог прицела бьющего).

var _cfg: Dictionary

func _init(cfg: Dictionary) -> void:
	_cfg = cfg

func _axis(neg: StringName, pos: StringName) -> float:
	return Input.get_axis(neg, pos)

func dive_zone() -> int:
	var lat: Array = _cfg.get("aim_lat", [])
	var vert: Array = _cfg.get("aim_vert", [])
	var x := _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0
	var y := -_axis(vert[0], vert[1]) if vert.size() == 2 else 0.0
	return PenaltyLogic.stick_to_zone(Vector2(x, y), 0.15)

func step_lateral() -> float:
	var lat: Array = _cfg.get("aim_lat", [])
	return _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0

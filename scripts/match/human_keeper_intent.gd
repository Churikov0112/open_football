class_name HumanKeeperIntent
extends KeeperIntent
## Human-вратарь: зона нырка из квадранта стика (крутится вплоть до удара). Конфиг осей;
## ввод через переопределяемый _axis (для headless-теста). Дедзона 0.15 (как порог прицела бьющего).
## `lat_sign` (по умолч. 1.0) — знак латеральной оси относительно МИРОВОГО +X: камера пенальти
## всегда за точкой и смотрит на ворота, поэтому «право на экране» = мировой X со знаком `_into`
## (для ворот на -Z это +X, для наших ворот на +Z это -X). Контроллер передаёт lat_sign = _into,
## чтобы «право стика» = «право на экране» для любых ворот (иначе вратарь зеркалит сторону нырка).

var _cfg: Dictionary

func _init(cfg: Dictionary) -> void:
	_cfg = cfg

func _axis(neg: StringName, pos: StringName) -> float:
	return Input.get_axis(neg, pos)

func _lat_axis() -> float:
	var lat: Array = _cfg.get("aim_lat", [])
	var raw := _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0
	return raw * float(_cfg.get("lat_sign", 1.0))

func dive_zone() -> int:
	var vert: Array = _cfg.get("aim_vert", [])
	var x := _lat_axis()
	var y := -_axis(vert[0], vert[1]) if vert.size() == 2 else 0.0
	return PenaltyLogic.stick_to_zone(Vector2(x, y), 0.15)

func step_lateral() -> float:
	return _lat_axis()

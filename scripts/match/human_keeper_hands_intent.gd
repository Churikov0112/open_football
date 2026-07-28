class_name HumanKeeperHandsIntent
extends KeeperHandsIntent
## Human-реализация: тонкая обёртка над Input, config-driven (как HumanKickerIntent).
## Ввод через переопределяемые _pressed/_axis — headless-тест подменяет.

var _cfg: Dictionary

func _init(cfg: Dictionary) -> void:
	_cfg = cfg

func _pressed(a: StringName) -> bool:
	return Input.is_action_pressed(a)

func _axis(neg: StringName, pos: StringName) -> float:
	return Input.get_axis(neg, pos)

func move_axis() -> Vector2:
	var lat: Array = _cfg.get("move_lat", [])
	var vert: Array = _cfg.get("move_vert", [])
	var x := _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0
	var y := -_axis(vert[0], vert[1]) if vert.size() == 2 else 0.0
	return Vector2(x, y)

func aim_axis() -> Vector2:
	var lat: Array = _cfg.get("aim_lat", [])
	var vert: Array = _cfg.get("aim_vert", [])
	var x := _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0
	var y := -_axis(vert[0], vert[1]) if vert.size() == 2 else 0.0
	return Vector2(x, y)

## Приоритет при одновременном зажатии: HAND → CLEAR_CENTER → CLEAR_DIRECTED → DROP.
func held_action() -> int:
	if _pressed(_cfg.get("hand", &"")):
		return Action.HAND
	if _pressed(_cfg.get("clear_center", &"")):
		return Action.CLEAR_CENTER
	if _pressed(_cfg.get("clear_directed", &"")):
		return Action.CLEAR_DIRECTED
	if _pressed(_cfg.get("drop", &"")):
		return Action.DROP
	return Action.NONE

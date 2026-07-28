class_name HumanKickerIntent
extends KickerIntent
## Human-реализация шва бьющего: тонкая обёртка над Input, конфиг-driven (какие оси/кнопки).
## Ввод читается через переопределяемые _pressed/_just_pressed/_axis — для headless-теста
## (фейковый сабкласс скриптует ввод). Поведение = ровно прежние прямые Input.* контроллера.

var _cfg: Dictionary
var _active: StringName = &""   # латченная стартовая кнопка активного заряда

func _init(cfg: Dictionary) -> void:
	_cfg = cfg

# --- переопределяемый источник ввода (тест подменяет) ---
func _pressed(a: StringName) -> bool:
	return Input.is_action_pressed(a)

func _just_pressed(a: StringName) -> bool:
	return Input.is_action_just_pressed(a)

func _axis(neg: StringName, pos: StringName) -> float:
	return Input.get_axis(neg, pos)

# --- KickerIntent ---
func aim_axis() -> Vector2:
	var lat: Array = _cfg.get("aim_lat", [])
	var vert: Array = _cfg.get("aim_vert", [])
	var x := _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0
	var y := -_axis(vert[0], vert[1]) if vert.size() == 2 else 0.0
	return Vector2(x, y)

func foot_switch() -> int:
	var f: Array = _cfg.get("foot", [])
	if f.size() == 2:
		if _just_pressed(f[0]):
			return -1
		if _just_pressed(f[1]):
			return 1
	return 0

func charge_start_variant() -> int:
	var charges: Array = _cfg.get("charges", [])
	for entry in charges:
		var action: StringName = entry[0]
		if _just_pressed(action):
			_active = action
			return int(entry[1])
	return -1

func charge_committed() -> bool:
	if _active == &"":
		return false
	if not _pressed(_active):
		_active = &""
		return true
	return false

func modifier_held() -> bool:
	var m: StringName = _cfg.get("modifier", &"")
	return _pressed(m) if m != &"" else false

func secondary() -> bool:
	var s: StringName = _cfg.get("secondary", &"")
	return _just_pressed(s) if s != &"" else false

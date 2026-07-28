extends SceneTree
## Headless-проверка латч/вариант/нога-логики HumanKickerIntent через фейковый сабкласс,
## который скриптует ввод (переопределяет _pressed/_just_pressed/_axis). Чистый RefCounted —
## синхронно в _init, узлы не нужны.

class _FakeIntent extends HumanKickerIntent:
	var pressed := {}
	var just := {}
	func _pressed(a: StringName) -> bool: return pressed.get(a, false)
	func _just_pressed(a: StringName) -> bool: return just.get(a, false)
	func _axis(neg: StringName, pos: StringName) -> float:
		return (1.0 if pressed.get(pos, false) else 0.0) - (1.0 if pressed.get(neg, false) else 0.0)

func _init() -> void:
	var ok := true
	var cfg := {
		"aim_lat": [&"move_left", &"move_right"],
		"aim_vert": [&"move_forward", &"move_back"],
		"foot": [&"foot_left", &"foot_right"],
		"charges": [[&"kick", 0], [&"pass_lob", 2]],
		"modifier": &"combo_modifier",
	}
	var f := _FakeIntent.new(cfg)

	# Прицел: право+назад зажаты → x=+1, y=-(back)= -1 (инверсия вертикали).
	f.pressed = {&"move_right": true, &"move_back": true}
	var aim := f.aim_axis()
	ok = _expect(is_equal_approx(aim.x, 1.0) and is_equal_approx(aim.y, -1.0), "aim_axis право+назад") and ok

	# Нога: just_pressed(foot_left) → -1; foot_right → +1; иначе 0.
	f.just = {&"foot_left": true}
	ok = _expect(f.foot_switch() == -1, "foot_switch left = -1") and ok
	f.just = {&"foot_right": true}
	ok = _expect(f.foot_switch() == 1, "foot_switch right = +1") and ok
	f.just = {}
	ok = _expect(f.foot_switch() == 0, "foot_switch none = 0") and ok

	# Старт заряда: just_pressed(kick) → вариант 0, латчит kick.
	f.just = {&"kick": true}
	f.pressed = {&"kick": true}
	ok = _expect(f.charge_start_variant() == 0, "charge_start вариант kick=0") and ok
	# Пока kick зажат — коммита нет.
	f.just = {}
	ok = _expect(f.charge_committed() == false, "нет коммита пока kick зажат") and ok
	# kick отпущен → коммит true (один раз), латч сброшен.
	f.pressed = {}
	ok = _expect(f.charge_committed() == true, "коммит при отпускании kick") and ok
	ok = _expect(f.charge_committed() == false, "коммит только раз (латч сброшен)") and ok

	# Другой вариант: just_pressed(pass_lob) → вариант 2.
	f.just = {&"pass_lob": true}
	f.pressed = {&"pass_lob": true}
	ok = _expect(f.charge_start_variant() == 2, "charge_start вариант pass_lob=2") and ok

	# modifier_held.
	f.pressed = {&"combo_modifier": true}
	ok = _expect(f.modifier_held() == true, "modifier_held true") and ok
	f.pressed = {}
	ok = _expect(f.modifier_held() == false, "modifier_held false") and ok

	# База KickerIntent — no-op дефолты.
	var base := KickerIntent.new()
	ok = _expect(base.charge_start_variant() == -1 and base.charge_committed() == false \
		and base.foot_switch() == 0 and base.aim_axis() == Vector2.ZERO, "база no-op") and ok

	# Презентация по роли: KICKER → камера+HUD, без keeper-маркера; KEEPER → камера+маркер, без HUD; NONE → ничего.
	var pk := SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
	var pkeep := SetPiecePresentation.new(SetPiecePresentation.Role.KEEPER)
	var pn := SetPiecePresentation.new(SetPiecePresentation.Role.NONE)
	ok = _expect(pk.owns_camera() and pk.owns_hud() and not pk.owns_keeper_marker(), "KICKER: камера+HUD") and ok
	ok = _expect(pkeep.owns_camera() and not pkeep.owns_hud() and pkeep.owns_keeper_marker(), "KEEPER: камера+маркер") and ok
	ok = _expect(not pn.owns_camera() and not pn.owns_hud() and not pn.owns_keeper_marker(), "NONE: ничего") and ok

	if ok:
		print("CHECK PASS: human_kicker_intent")
		quit(0)
	else:
		print("CHECK FAIL: human_kicker_intent")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

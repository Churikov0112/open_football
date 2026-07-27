extends SceneTree
## KeeperHandsIntent: HumanKeeperHandsIntent (фейк-ввод через сабкласс), AIKeeperHandsIntent (тайминг).

# Фейк Human: скриптуем "зажатые" действия и оси без реального Input.
class FakeHuman extends HumanKeeperHandsIntent:
	var held := {}
	var axes := {}
	func _pressed(a: StringName) -> bool:
		return held.get(a, false)
	func _axis(neg: StringName, pos: StringName) -> float:
		return float(axes.get(pos, 0.0)) - float(axes.get(neg, 0.0))

# Фейк AI: подменяем время.
class FakeAI extends AIKeeperHandsIntent:
	var t := 0
	func _now_msec() -> int:
		return t

func _initialize() -> void:
	var ok := true
	var cfg := {
		"move_lat": [&"ml", &"mr"], "move_vert": [&"mu", &"md"],
		"aim_lat": [&"ml", &"mr"], "aim_vert": [&"mu", &"md"],
		"hand": &"k_hand", "clear_center": &"k_cc", "clear_directed": &"k_cd", "drop": &"k_drop",
	}
	var h := FakeHuman.new(cfg)
	if h.held_action() != KeeperHandsIntent.Action.NONE:
		print("CHECK FAIL: пустой held_action не NONE"); ok = false
	h.held = {&"k_hand": true}
	if h.held_action() != KeeperHandsIntent.Action.HAND:
		print("CHECK FAIL: HAND не считался"); ok = false
	h.held = {&"k_drop": true}
	if h.held_action() != KeeperHandsIntent.Action.DROP:
		print("CHECK FAIL: DROP не считался"); ok = false
	h.held = {}
	h.axes = {&"mr": 1.0}
	if absf(h.move_axis().x - 1.0) > 0.01:
		print("CHECK FAIL: move_axis.x != 1: ", h.move_axis()); ok = false

	var a := FakeAI.new(0.5)   # think 0.5с
	a.t = 0
	if a.held_action() != KeeperHandsIntent.Action.NONE:
		print("CHECK FAIL: AI до паузы не NONE"); ok = false
	a.t = 600   # >0.5с
	if a.held_action() != KeeperHandsIntent.Action.CLEAR_CENTER:
		print("CHECK FAIL: AI после паузы не CLEAR_CENTER"); ok = false

	if ok:
		print("CHECK PASS: KeeperHandsIntent (human fake + ai timing)")
		quit(0)
	else:
		quit(1)

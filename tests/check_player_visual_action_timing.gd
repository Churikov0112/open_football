extends SceneTree

# Проверяем: (A) нормальный путь — trigger('pass') → сигнал contact, затем finished;
# (B) отмена — trigger + cancel_action → contact НЕ приходит, finished не обязателен.
var _inst: Node
var _log: Array = []
var _phase := 0
var _pt := 0.0  # накопленное реальное время текущей фазы (не зависит от fps)

func _initialize() -> void:
	var scene := load("res://scenes/player_visual.tscn") as PackedScene
	_inst = scene.instantiate()
	root.add_child(_inst)

func _process(delta: float) -> bool:
	if _inst == null or not _inst.is_node_ready():
		return false
	_pt += delta
	if _phase == 0:
		_inst.action_contact.connect(func(a: String) -> void: _log.append("contact:" + a))
		_inst.action_finished.connect(func(a: String) -> void: _log.append("finished:" + a))
		var started: bool = _inst.trigger("pass")
		if not started:
			print("CHECK FAIL: trigger('pass') вернул false")
			quit(1); return true
		_phase = 1; _pt = 0.0
		return false
	if _phase == 1:
		if "finished:pass" in _log:
			var ok := true
			if not ("contact:pass" in _log):
				print("CHECK FAIL: не пришёл contact"); ok = false
			elif _log.find("contact:pass") > _log.find("finished:pass"):
				print("CHECK FAIL: finished раньше contact, log=", _log); ok = false
			if not ok:
				print("CHECK FAIL"); quit(1); return true
			print("CHECK: нормальный путь ", _log)
			_log.clear(); _phase = 2; _pt = 0.0
			_inst.trigger("pass")
			_inst.cancel_action()
			return false
		if _pt > 2.0:
			print("CHECK FAIL: finished не пришёл за 2с, log=", _log)
			quit(1); return true
		return false
	if _phase == 2:
		if _pt > 1.0:
			if "contact:pass" in _log:
				print("CHECK FAIL: после cancel пришёл contact, log=", _log)
				quit(1); return true
			print("CHECK: отмена подавила contact ", _log)
			print("CHECK PASS")
			quit(0); return true
		return false
	return false

extends SceneTree
## Регресс: несколько угловых подряд НЕ должны наращивать состав. Временные тела углового
## (толпа/защитники) деспавнятся на резолве; получателем становится РЕАЛЬНЫЙ тиммейт из ростера,
## а не новое постоянное тело. После каждого резолва счётчики team_1/team_2 = базовым.

var _mm: Node
var _corner: Node
var _elapsed: float = 0.0
var _stage: int = 0
var _st: float = 0.0
var _base_t1: int = 0
var _base_t2: int = 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _c(g: String) -> int:
	return _mm.get_tree().get_nodes_in_group(g).size()

func _fail(msg: String) -> bool:
	print("CHECK FAIL: ", msg)
	quit(1)
	return true

func _process(delta: float) -> bool:
	_elapsed += delta
	_st += delta
	match _stage:
		0:  # baseline + старт углового 1
			if _elapsed > 0.2:
				_corner = _mm.get_node_or_null("CornerController")
				if _corner == null:
					return _fail("нет узла CornerController")
				_base_t1 = _c("team_1")
				_base_t2 = _c("team_2")
				print("baseline: team_1=%d team_2=%d" % [_base_t1, _base_t2])
				_corner.start(_mm.controlled_player, -_mm.field_length)
				_stage = 1
				_st = 0.0
		1:  # навес 1
			if _st > 0.2:
				_corner._start_charge("lob")
				_corner._fire_charge(0.7)
				_stage = 2
				_st = 0.0
		2:  # ждём резолва, проверяем счётчики, старт углового 2
			if _st > 3.0:
				if _mm.is_corner_active():
					return _fail("угловой 1 не завершился за 3с")
				var t1 := _c("team_1")
				var t2 := _c("team_2")
				print("after corner 1: team_1=%d team_2=%d" % [t1, t2])
				if t1 != _base_t1 or t2 != _base_t2:
					return _fail("состав вырос после углового 1 (t1=%d/%d t2=%d/%d)" % [t1, _base_t1, t2, _base_t2])
				_corner.start(_mm.controlled_player, -_mm.field_length)
				_stage = 3
				_st = 0.0
		3:  # навес 2
			if _st > 0.2:
				_corner._start_charge("lob")
				_corner._fire_charge(0.7)
				_stage = 4
				_st = 0.0
		4:  # финальная проверка
			if _st > 3.0:
				if _mm.is_corner_active():
					return _fail("угловой 2 не завершился за 3с")
				var t1 := _c("team_1")
				var t2 := _c("team_2")
				print("after corner 2: team_1=%d team_2=%d" % [t1, t2])
				if t1 != _base_t1 or t2 != _base_t2:
					return _fail("состав вырос после углового 2 (t1=%d/%d t2=%d/%d)" % [t1, _base_t1, t2, _base_t2])
				print("CHECK PASS: corner no-growth (team counts stable over 2 corners)")
				quit(0)
				return true
	return false

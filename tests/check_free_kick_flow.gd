extends SceneTree
## Headless-смоук флоу штрафного: грузим match.tscn, стартуем розыгрыш и бьём (в обход Input),
## крутим кадры. Проверяем: мяч получил импульс, режим снялся, стенка сконвертирована в team_2-ИИ,
## тиммейты/цели заспавнены, и — при ДВУХ штрафных подряд — тела НЕ накапливаются (нет дублей).

var _mm: Node
var _fk: Node
var _elapsed: float = 0.0
var _state: int = 0            # 0 ждём ready, 1 FK#1, 2 между, 3 FK#2, 4 вердикт
var _fired: bool = false
var _max_ball_speed: float = 0.0
var _count1: int = 0
var _count2: int = 0
var _wall_ok: bool = true
var _t2: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _count_fk_bodies() -> int:
	return get_nodes_in_group("fk_spawned").size()

func _start_kick() -> void:
	_mm.controlled_player.global_position = Vector3(5.0, 0.5, -35.0)
	_fk.start(_mm.controlled_player, -_mm.field_length)

func _fail(msg: String) -> void:
	print("CHECK FAIL: ", msg)
	quit(1)

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.15:
				_fk = _mm.get_node_or_null("FreeKickController")
				if _fk == null:
					_fail("нет узла FreeKickController"); return true
				_start_kick()
				if not _mm.is_free_kick_active():
					_fail("режим штрафного не включился"); return true
				if _fk._mates.size() < 1:
					_fail("не заспавнены тиммейт/цели"); return true
				_state = 1
		1:
			if not _fired and _elapsed > 0.3:
				_fk._fire_shot(0.7)
				_fired = true
			if _fired:
				_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
			# Ждём снятия режима (release), затем считаем тела и запускаем второй штрафной.
			if _fired and not _mm.is_free_kick_active():
				for entry in _fk._wall_bodies:
					var b = entry["body"]
					if not is_instance_valid(b) or not b.is_in_group("team_2") or b.get_script() == null:
						_wall_ok = false
				_count1 = _count_fk_bodies()
				_start_kick()          # второй штрафной — _cleanup_spawned должен деспавнить тела первого
				_t2 = _elapsed
				_state = 3
			elif _elapsed > 5.0:
				_fail("первый штрафной не завершился (release)"); return true
		3:
			# Даём кадр на отложенный queue_free тел первого штрафного, затем считаем.
			if _elapsed - _t2 > 0.2:
				_count2 = _count_fk_bodies()
				_state = 4
		4:
			var launched: bool = _max_ball_speed > 1.0
			# После 2-го штрафного тел не больше, чем после 1-го (тела первого деспавнены).
			var no_dup: bool = _count2 <= _count1
			print("SMOKE: max_speed=", _max_ball_speed, " count1=", _count1, " count2=", _count2, " wall_ok=", _wall_ok)
			if launched and _wall_ok and no_dup:
				print("CHECK PASS: free_kick flow (launch + convert + no accumulation)")
				quit(0)
			else:
				_fail("launched=" + str(launched) + " wall_ok=" + str(_wall_ok) + " no_dup=" + str(no_dup))
			return true
	if _elapsed > 9.0:
		_fail("таймаут"); return true
	return false

extends SceneTree
## Регресс: если гол засчитан РАНЬШЕ, чем прыжок стенки естественно доиграл (tt<1.0), тело
## обязано СРАЗУ приземлиться (Y=base_y, снят с "fallen", визуал recover()), а не висеть в
## воздухе до тех пор, пока FreeKickController._release() не сработает (это может занять ещё
## секунду-две WATCH-фазы). Фикс: _update_wall_jumps проверяет is_celebrating() каждый кадр,
## не только на релизе.

var _mm: Node
var _fk: Node
var _frames := 0
var _started := false
var _jump_body: CharacterBody3D = null

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn") as PackedScene
	_mm = scene.instantiate()
	root.add_child(_mm)
	physics_frame.connect(_tick)

func _fail(msg: String) -> void:
	print("CHECK FAIL: ", msg)
	quit(1)

func _tick() -> void:
	_frames += 1
	if _frames < 15 or _started:
		return
	_started = true
	_fk = _mm.get_node_or_null("FreeKickController")
	if _fk == null:
		_fail("нет FreeKickController"); return
	var kicker: Node3D = _mm.get(&"controlled_player")
	kicker.global_position = Vector3(5.0, 0.5, -35.0)
	_fk.start(kicker, _mm._keeper_brain.goal_line_z)
	# _setup() уже отработал синхронно — стенка заспавнена.
	var wall_bodies: Array = _fk.get(&"_wall_bodies")
	if wall_bodies.is_empty():
		_fail("стенка не заспавнена"); return
	_jump_body = wall_bodies[0]["body"]
	# Имитируем «тело в прыжке, на середине дуги» (как будто wall_should_jump уже сработал).
	wall_bodies[0]["jumping"] = true
	wall_bodies[0]["jump_t"] = FootballConstants.FK_WALL_JUMP_TIME * 0.5   # tt=0.5, ЕЩЁ не доиграл
	_jump_body.add_to_group("fallen")
	var base_y: float = wall_bodies[0]["base_y"]
	_jump_body.global_position.y = base_y + FootballConstants.FK_WALL_JUMP_HEIGHT   # на пике дуги
	_fk.set(&"_ball_in_flight_watch", true)
	print("[DIAG] jump body at peak, y=", _jump_body.global_position.y, " base_y=", base_y)
	# ГОЛ уже засчитан (мяч влетел в сетку) — раньше, чем прыжок доиграл естественно.
	_mm.set(&"_celebrating", true)
	# Вызываем _update_wall_jumps НАПРЯМУЮ (как check_free_kick_flow.gd зовёт _fire_shot) — не
	# полагаемся на _phase (STRIKE/WATCH), это тест конкретно этой функции.
	_fk.call(&"_update_wall_jumps", 1.0 / 60.0)
	var jumping: bool = wall_bodies[0]["jumping"]
	var y := _jump_body.global_position.y
	var in_fallen := _jump_body.is_in_group("fallen")
	print("SMOKE: jumping=", jumping, " y=", y, " base_y=", base_y, " in_fallen=", in_fallen)
	if jumping or absf(y - base_y) > 0.05 or in_fallen:
		_fail("тело всё ещё висит: jumping=" + str(jumping) + " y=" + str(y) + " base_y=" + str(base_y) + " fallen=" + str(in_fallen))
		return
	print("CHECK PASS: wall body lands immediately when celebrating starts mid-jump")
	quit(0)

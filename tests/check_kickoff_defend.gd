extends SceneTree
## ИИ-соперник разводит (team_2 kickoff, Role.NONE) → человек защищается: его команда ЖИВАЯ (моторы
## не залочены), бьющая заморожена, подкат запрещён, а заход на чужую половину/в центр держат две
## физические стены (защитники получают их бит в collision_mask). Грузит match.tscn.

var _mm: Node
var _elapsed: float = 0.0
var _state: int = 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _locked(body) -> bool:
	var m = PlayerMotor.find_on(body)
	return m != null and m._locked

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.3:
				# Сбрасываем возможный стартовый кикофф жеребьёвки, разводим team_2 (ИИ).
				if _mm._kickoff.is_active():
					_mm._kickoff._release()
				_mm._celebrating = false
				_mm._dispatch_kickoff(2)
				if not _mm.is_kickoff_active() or _mm._kickoff.camera_is_owned():
					print("CHECK FAIL: ожидался активный ИИ-развод (Role.NONE)"); return true

				# Защищающаяся команда (team_1) — ЖИВАЯ: моторы не залочены.
				var defender = _mm._team_home.outfield()[0]
				if _locked(defender):
					print("CHECK FAIL: защитник team_1 залочен (должен играть)"); return true

				# Бьющая команда (team_2, полевой) — заморожена.
				var kicker_mate = _mm._team_away.outfield()[1]
				if not _locked(kicker_mate):
					print("CHECK FAIL: полевой бьющей team_2 не заморожен"); return true

				# Подкат запрещён во время кикоффа.
				if _mm._try_tackle(_mm.controlled_player) != false:
					print("CHECK FAIL: подкат разрешён во время кикоффа"); return true

				# Две стены построены; защитник их слушает.
				if _mm._kickoff._block_walls.size() != 2:
					print("CHECK FAIL: ожидались 2 стены (чужая половина + круг), есть ", _mm._kickoff._block_walls.size()); return true
				if (defender.collision_mask & FootballConstants.SETPIECE_BLOCK_LAYER) == 0:
					print("CHECK FAIL: защитник не слушает стены (нет бита в mask)"); return true

				# После розыгрыша стены сняты и бит возвращён.
				_mm._kickoff._release()
				if _mm._kickoff._block_walls.size() != 0:
					print("CHECK FAIL: стены не сняты после розыгрыша"); return true
				if (defender.collision_mask & FootballConstants.SETPIECE_BLOCK_LAYER) != 0:
					print("CHECK FAIL: бит стены не убран из mask защитника"); return true

				print("CHECK PASS: kickoff_defend")
				quit(0)
				return true
	if _elapsed > 8.0:
		print("CHECK FAIL: таймаут"); return true
	return false

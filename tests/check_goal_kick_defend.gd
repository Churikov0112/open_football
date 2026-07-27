extends SceneTree
## ИИ-соперник бьёт удар от ворот (Role.NONE) → человек защищается: его команда ЖИВАЯ (моторы не
## залочены), бьющая команда заморожена, подкат запрещён, а заход в штрафную блокируется push'ем
## БЕЗ лока (игрок в штрафной вытолкнут, но мотор остаётся свободным). Грузит match.tscn.

var _mm: Node
var _elapsed: float = 0.0
var _state: int = 0
var _gl: float

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _locked(body) -> bool:
	var m = PlayerMotor.find_on(body)
	return m != null and m._locked

func _in_box(n: Node3D) -> bool:
	var into := -signf(_gl)
	return absf(n.global_position.x) <= FootballConstants.PENALTY_AREA_WIDTH * 0.5 \
		and (n.global_position.z - _gl) * into >= 0.0 \
		and (n.global_position.z - _gl) * into <= FootballConstants.PENALTY_AREA_DEPTH

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.3:
				if _mm._kickoff != null and _mm._kickoff.is_active():
					_mm._kickoff._release()
				_mm._celebrating = false
				_gl = -_mm.field_length
				_mm._dispatch_goal_kick(2, Vector3(0, 0.11, _gl))   # team_2 (ИИ) бьёт у -Z
				if not _mm.is_goal_kick_active() or _mm._goal_kick.camera_is_owned():
					print("CHECK FAIL: ожидался активный ИИ-удар (Role.NONE)"); return true

				# Защищающаяся команда (team_1) — ЖИВАЯ: моторы не залочены.
				var defender = _mm._team_home.outfield()[0]
				if _locked(defender):
					print("CHECK FAIL: защитник team_1 залочен (должен играть)"); return true

				# Бьющая команда (team_2, полевой) — заморожена.
				var kicker_mate = _mm._team_away.outfield()[0]
				if not _locked(kicker_mate):
					print("CHECK FAIL: полевой бьющей team_2 не заморожен"); return true

				# Подкат запрещён во время удара от ворот.
				if _mm._try_tackle(_mm.controlled_player) != false:
					print("CHECK FAIL: подкат разрешён во время удара от ворот"); return true

				# Заход в штрафную блокируется push'ем БЕЗ лока: телепорт защитника в штрафную →
				# update() выталкивает его, но мотор остаётся свободным.
				var into := -signf(_gl)
				defender.global_position = Vector3(0.0, 0.5, _gl + into * 5.0)
				_mm._goal_kick.update(1.0 / 60.0)
				if _in_box(defender):
					print("CHECK FAIL: защитник не вытолкнут из штрафной"); return true
				if _locked(defender):
					print("CHECK FAIL: защитник залочен после выталкивания (должен остаться свободным)"); return true

				print("CHECK PASS: goal_kick_defend")
				quit(0)
				return true
	if _elapsed > 8.0:
		print("CHECK FAIL: таймаут"); return true
	return false

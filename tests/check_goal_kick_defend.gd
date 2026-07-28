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
				var into := -signf(_gl)
				# Защитник ДО дспетча стоит В штрафной — SETUP-расстановка обязана вытолкнуть его один раз.
				var defender = _mm._team_home.outfield()[0]
				defender.global_position = Vector3(0.0, 0.5, _gl + into * 5.0)
				_mm._dispatch_goal_kick(2, Vector3(0, 0.11, _gl))   # team_2 (ИИ) бьёт у -Z
				if not _mm.is_goal_kick_active() or _mm._goal_kick.camera_is_owned():
					print("CHECK FAIL: ожидался активный ИИ-удар (Role.NONE)"); return true

				# SETUP выставил защитника вне штрафной (одноразовая начальная расстановка).
				if _in_box(defender):
					print("CHECK FAIL: SETUP не вытолкнул защитника из штрафной"); return true

				# Защищающаяся команда (team_1) — ЖИВАЯ: моторы не залочены.
				if _locked(defender):
					print("CHECK FAIL: защитник team_1 залочен (должен играть)"); return true

				# Бьющая команда (team_2, полевой) — заморожена.
				var kicker_mate = _mm._team_away.outfield()[0]
				if not _locked(kicker_mate):
					print("CHECK FAIL: полевой бьющей team_2 не заморожен"); return true

				# Подкат запрещён во время удара от ворот.
				if _mm._try_tackle(_mm.controlled_player) != false:
					print("CHECK FAIL: подкат разрешён во время удара от ворот"); return true

				# Заход в штрафную держит физическая стена, а не пер-кадровый телепорт: коллайдер
				# построен и защитник получил его бит в collision_mask (упрётся через move_and_slide).
				if _mm._goal_kick._block_wall == null or not is_instance_valid(_mm._goal_kick._block_wall):
					print("CHECK FAIL: стена штрафной не построена"); return true
				if (defender.collision_mask & FootballConstants.SETPIECE_BLOCK_LAYER) == 0:
					print("CHECK FAIL: защитник не слушает стену (нет бита в mask)"); return true

				# После удара стена снимается и бит возвращается.
				_mm._goal_kick._release()
				if _mm._goal_kick._block_wall != null:
					print("CHECK FAIL: стена не снята после розыгрыша"); return true
				if (defender.collision_mask & FootballConstants.SETPIECE_BLOCK_LAYER) != 0:
					print("CHECK FAIL: бит стены не убран из mask защитника"); return true

				print("CHECK PASS: goal_kick_defend")
				quit(0)
				return true
	if _elapsed > 8.0:
		print("CHECK FAIL: таймаут"); return true
	return false

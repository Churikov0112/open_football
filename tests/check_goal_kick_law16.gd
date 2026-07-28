extends SceneTree
## Соперник вне штрафной ДЕРЖИТСЯ непрерывно до удара, а не одноразово на SETUP. Грузит match.tscn
## (нужны реальные тела в группах). Проверяет: (1) в AIM соперник, телепортнутый в штрафную, вытолкнут
## на update(); (2) то же в STRIKE; (3) в IDLE (после удара) — НЕ вытолкнут (окно закрылось).

var _mm: Node
var _elapsed: float = 0.0
var _state: int = 0
var _opp: Node3D
var _gl: float

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _in_box(n: Node3D) -> bool:
	var into := -signf(_gl)
	return absf(n.global_position.x) <= FootballConstants.PENALTY_AREA_WIDTH * 0.5 \
		and (n.global_position.z - _gl) * into >= 0.0 \
		and (n.global_position.z - _gl) * into <= FootballConstants.PENALTY_AREA_DEPTH

func _put_in_box() -> void:
	var into := -signf(_gl)
	_opp.global_position = Vector3(0.0, 0.5, _gl + into * 5.0)  # 5 м в поле от линии — внутри 16.5

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.3:
				_gl = -_mm.field_length
				var keeper = _mm._keeper_at(_gl)
				_mm._goal_kick.start(keeper, _gl)   # human-дефолт, бьёт team_2-вратарь; соперники = team_1
				_opp = _mm._team_home.outfield()[0]  # полевой team_1
				if not _mm.is_goal_kick_active():
					print("CHECK FAIL: удар от ворот не активен"); return true
				_state = 1
		1:
			# AIM: соперник в штрафной → update() выталкивает.
			_put_in_box()
			_mm._goal_kick.update(1.0 / 60.0)
			if _in_box(_opp):
				print("CHECK FAIL: AIM — соперник остался в штрафной"); return true
			_state = 2
		2:
			# STRIKE: то же.
			_mm._goal_kick._phase = 3   # Phase.STRIKE
			_put_in_box()
			_mm._goal_kick.update(1.0 / 60.0)
			if _in_box(_opp):
				print("CHECK FAIL: STRIKE — соперник остался в штрафной"); return true
			_state = 3
		3:
			# После удара (IDLE): окно закрыто — соперник НЕ выталкивается.
			_mm._goal_kick._release()
			_put_in_box()
			_mm._goal_kick.update(1.0 / 60.0)
			if not _in_box(_opp):
				print("CHECK FAIL: IDLE — enforcement не должен действовать после удара"); return true
			print("CHECK PASS: goal_kick_law16")
			quit(0)
			return true
	if _elapsed > 8.0:
		print("CHECK FAIL: таймаут"); return true
	return false

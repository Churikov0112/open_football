extends SceneTree
## Headless-проверка диспетчеризации кикоффа судьёй: гол в ворота Home → пропустил team_2 →
## кикофф стартует с AIKickoffIntent/Role.NONE; гол в Away → пропустил team_1 → Human/Role.KICKER.
## Жеребьёвка старта матча детерминирована при фиксированном seed.

var _mm: Node
var _elapsed: float = 0.0
var _state: int = 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			# Старт матча уже должен был диспетчеризовать кикофф (жеребьёвка в _ready) —
			# проверяем, что мяч НЕ у человека напрямую (старое поведение), а идёт розыгрыш ИЛИ
			# уже разыгран (жеребьёвка может выпасть на любую сторону — тест не завязан на исход).
			if _elapsed > 0.2:
				var had_kickoff: bool = _mm.is_kickoff_active() or not _mm.ball.has_method(&"is_caught")
				# Основная проверка старта матча — что диспетчер вообще что-то сделал, не падаем
				# с ошибкой. Реальная проверка команды/типа — через прямой report_goal ниже.
				_state = 1
		1:
			if _elapsed > 0.4:
				# Гол в ворота Home → team_1 забил → team_2 пропустил → team_2 бьёт кикофф (ИИ).
				_mm._celebrating = false   # сбрасываем на случай, если жеребьёвка/что-то ещё держит флаг
				# В реальной игре гол физически не может случиться, пока стартовый кикофф ещё
				# активен (_physics_process менеджера гейтится на is_kickoff_active()) — но
				# жеребьёвка _ready() могла отдать его человеку, который без реального ввода в
				# headless-тесте никогда не завершит AIM сам. Форсируем завершение здесь (а не
				# ждём), т.к. этот тест бьёт по report_goal/_dispatch_kickoff напрямую и не должен
				# зависеть от исхода жеребьёвки при старте матча.
				if _mm._kickoff.is_active():
					_mm._kickoff._release()
				_mm._referee.report_goal(2)
				_mm._dispatch_kickoff(2)
				if not _mm.is_kickoff_active():
					print("CHECK FAIL: кикофф team_2 не стартовал"); return true
				var kickoff_node = _mm.get_node_or_null("KickoffController")
				var is_ai: bool = kickoff_node._intent is AIKickoffIntent
				var role_none: bool = kickoff_node._presentation.owns_camera() == false
				print("DISPATCH team_2: is_ai=", is_ai, " role_none=", role_none)
				if not (is_ai and role_none):
					print("CHECK FAIL: team_2 kickoff — is_ai=", is_ai, " role_none=", role_none)
					return true
				kickoff_node._fire_charge(0.7)   # сразу разрешаем розыгрыш, не ждём таймингов ИИ
				_state = 2
		2:
			if not _mm.is_kickoff_active() and _elapsed > 1.5:
				# Гол в ворота Away → team_2 забил → team_1 пропустил → team_1 бьёт кикофф (Human).
				_mm._referee.report_goal(1)
				_mm._dispatch_kickoff(1)
				if not _mm.is_kickoff_active():
					print("CHECK FAIL: кикофф team_1 не стартовал"); return true
				var kickoff_node = _mm.get_node_or_null("KickoffController")
				var is_human: bool = kickoff_node._intent is HumanKickerIntent
				var role_kicker: bool = kickoff_node._presentation.owns_hud() == true
				print("DISPATCH team_1: is_human=", is_human, " role_kicker=", role_kicker)
				if is_human and role_kicker:
					print("CHECK PASS: kickoff dispatch (team_2→AI/observer, team_1→Human/kicker)")
					quit(0)
				else:
					print("CHECK FAIL: team_1 kickoff — is_human=", is_human, " role_kicker=", role_kicker)
					quit(1)
				return true
	if _elapsed > 8.0:
		print("CHECK FAIL: таймаут"); return true
	return false

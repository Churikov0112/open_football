extends SceneTree
## Регрессия: судья НЕ должен переучреждать вброс сразу после того, как только что брошенный мяч
## его же контроллером покинул точку розыгрыша. Баг: вброс — единственный стандарт, где точка
## розыгрыша лежит НА самой боковой линии (мяч физически стоит за линией в руках вбрасывающего);
## без грейса (FootballConstants.REFEREE_SETPIECE_GRACE) судья видел мяч ещё не отъехавшим за
## порог |x| > half_width+ball_radius в тот же/следующий кадр, что и снятие _throw_in_active, и
## тут же ставил НОВЫЙ вброс с нулевой скоростью — мяч выглядел так, будто врезался в невидимую
## стену на боковой и доставался вбрасывающему обратно (найдено при живом плейтесте).

var _mm: Node
var _ti: Node
var _elapsed: float = 0.0
var _state: int = 0
var _fired_at: float = -1.0
var _restart_events: Array = []
var _max_ball_speed_after_fire: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.15:
				_ti = _mm.get_node_or_null("ThrowInController")
				if _ti == null:
					print("CHECK FAIL: нет узла ThrowInController"); return true
				var ref := _mm.get_node_or_null("MatchReferee")
				if ref != null:
					ref.restart_awarded.connect(func(t, tm, sp):
						_restart_events.append({"t": t, "team": tm, "at": _elapsed}))
				_ti.start()
				if not _mm.is_throw_in_active():
					print("CHECK FAIL: throw-in-режим не включился"); return true
				_state = 1
		1:
			if _elapsed > 0.4:
				_ti._fire_charge(0.7)
				_fired_at = _elapsed
				_state = 2
		2:
			if _fired_at > 0 and not _mm.is_throw_in_active():
				_max_ball_speed_after_fire = maxf(_max_ball_speed_after_fire, _mm.ball.linear_velocity.length())
				if _elapsed - _fired_at > 1.5:
					var spurious := false
					for e in _restart_events:
						if e["at"] - _fired_at > 0.0 and e["at"] - _fired_at < 1.0:
							spurious = true
					var launched: bool = _max_ball_speed_after_fire > 1.0
					print("SPURIOUS_CHECK: events=", _restart_events, " launched=", launched)
					if not spurious and launched:
						print("CHECK PASS: throw_in referee grace (нет спурного переучреждения)")
						quit(0)
					else:
						print("CHECK FAIL: spurious=", str(spurious), " launched=", str(launched))
						quit(1)
					return true
	if _elapsed > 6.0:
		print("CHECK FAIL: таймаут"); return true
	return false

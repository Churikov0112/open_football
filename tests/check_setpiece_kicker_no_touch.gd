extends SceneTree
## Регресс: на сет-писе мяч лежит на точке (dribbler=null), поэтому launch() раньше писал
## last_kicker=null → грейс/кулдаун не защищали бьющего, и мяч, рождённый прямо в его капсуле,
## тут же блокировался о него (block_in_flight) — «перехватывался тем, кто давал пас». note_kicker()
## помечает бьющего явно и ставит грейс. Проверяем: слабый пас (A) на угловом УЛЕТАЕТ от точки
## (не гасится о ногу бьющего) и last_kicker == бьющий.

var _mm: Node
var _corner: Node
var _kicker: Node
var _spot: Vector3
var _max_dist: float = 0.0
var _lk_at_launch: int = -1   # -1 не захвачен, 1 == kicker, 0 != kicker
var _elapsed: float = 0.0
var _stage: int = 0
var _st: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	_st += delta
	match _stage:
		0:
			if _elapsed > 0.2:
				_corner = _mm.get_node_or_null("CornerController")
				if _corner == null:
					print("CHECK FAIL: нет узла CornerController")
					return true
				_corner.start(_mm.controlled_player, -_mm.field_length)
				_kicker = _corner._kicker
				_spot = _corner._spot
				_stage = 1
				_st = 0.0
		1:
			if _st > 0.2:
				# Слабый наземный пас (A).
				_corner._start_charge("ground")
				_corner._fire_charge(0.1)
				_stage = 2
				_st = 0.0
		2:
			# После контакта копим макс. удаление мяча от точки и ловим last_kicker В МОМЕНТ запуска
			# (позже быстрый пас долетает до ворот/вратаря и last_kicker сбрасывается ресетом).
			var p: Vector3 = _mm.ball.global_position
			_max_dist = maxf(_max_dist, Vector2(p.x - _spot.x, p.z - _spot.z).length())
			if _lk_at_launch == -1 and _mm.ball.last_kicker != null:
				_lk_at_launch = 1 if _mm.ball.last_kicker == _kicker else 0
			if _st > 2.5:
				var lk_ok: bool = _lk_at_launch == 1
				# Без грейса мяч блокировался о бьющего и оставался у точки (~1-2 м). С фиксом улетает.
				var flew: bool = _max_dist > 4.0
				print("SMOKE: last_kicker==kicker@launch=%s  max_dist=%.1f m" % [lk_ok, _max_dist])
				if lk_ok and flew:
					print("CHECK PASS: setpiece pass leaves the kicker (no self-block), kicker tagged")
					quit(0)
				else:
					print("CHECK FAIL: lk_ok=%s flew(>4m)=%s max_dist=%.1f" % [lk_ok, flew, _max_dist])
					quit(1)
				return true
	return false

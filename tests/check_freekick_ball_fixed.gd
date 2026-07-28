extends SceneTree
## Регресс: мяч на штрафном должен быть ЗАФИКСИРОВАН на точке в фазе AIM (как на пенальти).
## Имитируем остаточную скорость (штрафной берут «с ноги», ведя мяч) — пин обязан её погасить.
## Без пина мяч укатился бы драгом на ~6-7 м за секунду.

var _mm: Node
var _fk: Node
var _elapsed: float = 0.0
var _started: bool = false
var _spot: Vector3

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 0.2 and not _started:
		_fk = _mm.get_node_or_null("FreeKickController")
		if _fk == null:
			print("CHECK FAIL: нет узла FreeKickController")
			return true
		_fk.start(_mm.controlled_player, -_mm.field_length)
		if not _mm.is_free_kick_active():
			print("CHECK FAIL: штрафной не активировался")
			return true
		_spot = _fk._spot
		# Имитируем остаточную скорость дриблинга.
		_mm.ball.linear_velocity = Vector3(10.0, 0.0, 6.0)
		_started = true
		return false
	# Через ~1с в AIM мяч должен оставаться на точке (пин погасил скорость).
	if _elapsed > 1.2 and _started:
		var d: float = _mm.ball.global_position.distance_to(_spot)
		print("SMOKE: ball drift=%.3f m (spot=%s ball=%s) fk_active=%s" % [d, _spot, _mm.ball.global_position, _mm.is_free_kick_active()])
		if d < 0.5:
			print("CHECK PASS: free kick ball fixed on spot during AIM")
			quit(0)
		else:
			print("CHECK FAIL: мяч укатился на ", d, " м (ожидалось <0.5)")
			quit(1)
		return true
	return false

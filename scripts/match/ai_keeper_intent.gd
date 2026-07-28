class_name AIKeeperIntent
extends KeeperIntent
## AI-вратарь: слепой выбор зоны ОДИН раз при создании (кэш) — ровно текущее поведение под P,
## но через шов. dive_zone() всегда возвращает кэш (не переигрывается каждый кадр).

var _zone: int

func _init(rng: RandomNumberGenerator) -> void:
	_zone = PenaltyLogic.random_dive_zone(rng)

func dive_zone() -> int:
	return _zone

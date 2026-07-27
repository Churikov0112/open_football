class_name KeeperHandsIntent
extends RefCounted
## Интерфейс «вратарь с мячом в руках»: движение в штрафной + выбор действия раздачи.
## Charge-as-timer владеет consumer (keeper_ai) — интент лишь сообщает зажатую кнопку.

enum Action { NONE, HAND, CLEAR_CENTER, CLEAR_DIRECTED, DROP }

func move_axis() -> Vector2:
	return Vector2.ZERO

func aim_axis() -> Vector2:
	return Vector2.ZERO

func held_action() -> int:
	return Action.NONE

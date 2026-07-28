class_name SetPiecePresentation
extends RefCounted
## Профиль презентации стандарта по РОЛИ локального человека (один факт → вся презентация).
## Камера включается, если человек участвует в любой роли; состав HUD — по роли.
## WALL — задел под штрафной (Этап 2), сейчас не используется.

enum Role { NONE, KICKER, KEEPER, WALL }

var _local_role: int

func _init(local_role: int) -> void:
	_local_role = local_role

func owns_camera() -> bool:
	return _local_role != Role.NONE

func owns_hud() -> bool:
	return _local_role == Role.KICKER   # ретикл/power_bar бьющего

func owns_keeper_marker() -> bool:
	return _local_role == Role.KEEPER

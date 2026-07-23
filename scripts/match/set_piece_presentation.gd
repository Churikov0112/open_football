class_name SetPiecePresentation
extends RefCounted
## Двухуровневый профиль презентации стандарта. Уровень 1: участвует ли локальный человек-актёр
## (owns camera + тайминги стандарта). Уровень 2 (состав HUD по роли) добавят фичи, которым он
## нужен. Пилот: только owns_camera/owns_hud. is_local_human=true (дефолт human) → владеет всем;
## observer (ИИ/чужой стандарт) → ничем (камера-броадкаст не трогается, HUD скрыт).

var _local_human: bool

func _init(is_local_human: bool) -> void:
	_local_human = is_local_human

func owns_camera() -> bool:
	return _local_human

func owns_hud() -> bool:
	return _local_human

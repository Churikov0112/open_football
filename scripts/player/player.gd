class_name Player
extends CharacterBody3D
## Стабильный корень тела игрока (Фаза 2). Заменяет прежнюю схему «set_script(ai) на корень».
## Мозг — дочерний Brain-узел (вешает фабрика). Группы team_x/role_x остаются физическим индексом;
## эти поля — удобный геймплей-дубликат (пока необязательны, seam на будущее).

var team_group: StringName = &"team_1"
var role: int = 0   # PlayerConfig.Role.*

## Первый дочерний Brain, либо null (нет ИИ / человек в конечной Фазе 3 / легаси set_script).
func brain() -> Node:
	for c in get_children():
		if c is Brain:
			return c
	return null

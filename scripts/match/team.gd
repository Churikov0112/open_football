class_name Team
extends Node3D
## Узел-ростер: игроки — дети этого узла. Авторитетный игровой источник состава/роли/кита/
## стороны. Группы Godot (team_x + role_x) фабрика ставит параллельно как физический индекс.
## ВАЖНО: extends Node3D (не Node) — дети CharacterBody3D должны иметь Node3D-родителя, иначе
## трансформ физ-тела не пропагируется в физсервер и move_and_slide() выталкивает тело в мусорную
## позицию (депенетрация из «нулевого» трансформа) → игрок телепортируется/висит на другом теле.

var team_group: StringName = &"team_1"
var attack_z_sign: float = -1.0            # -1: атакуем −Z (наша); +1: соперник
var kit_color: Color = Color.WHITE
var id: StringName = &"home"
var manager: Node = null
var ball: Node = null

var _players: Array[CharacterBody3D] = []

func add_player(body: CharacterBody3D, role: int) -> void:
	if body.get_parent() != self:
		if body.get_parent() != null:
			body.get_parent().remove_child(body)
		add_child(body)
	body.add_to_group(team_group)
	body.add_to_group(PlayerConfig.role_group(role))
	body.set_meta(&"role", role)
	if not _players.has(body):
		_players.append(body)

func remove_player(body: CharacterBody3D) -> void:
	_players.erase(body)
	if is_instance_valid(body):
		body.remove_from_group(team_group)
		body.remove_from_group(PlayerConfig.role_group(int(body.get_meta(&"role", PlayerConfig.Role.MID))))

func players() -> Array:
	_players = _players.filter(func(b): return is_instance_valid(b))
	return _players

func by_role(role: int) -> Array:
	return players().filter(func(b): return int(b.get_meta(&"role", -1)) == role)

func keeper() -> CharacterBody3D:
	var gks := by_role(PlayerConfig.Role.GK)
	return gks[0] if gks.size() > 0 else null

func outfield() -> Array:
	return players().filter(func(b): return int(b.get_meta(&"role", -1)) != PlayerConfig.Role.GK)

class_name ActionExecutor
extends Node
## Резолюция «действия с мячом» → физический импульс. Общий commit-путь удара/паса, вынесенный
## из match_manager (Фаза 3a). Узел-компаньон менеджера (как PenaltyController/FreeKickController):
## владеет состоянием коммита (_action_*/_pending_*/_pass_rng) и звонит назад в _manager за общими
## хелперами (_aim_dir/_ai_of/_player_visual/... — вход человека и заряд остаются в менеджере до 3b).

var _manager: Node
var _ball: RigidBody3D

func setup(manager: Node, ball: RigidBody3D) -> void:
	_manager = manager
	_ball = ball

## Тело, выполняющее действие (управление заблокировано), либо null. Читает менеджер в
## _handle_player_input/_handle_dribbling — раньше это было поле _action_player.
func action_player() -> CharacterBody3D:
	return null

## Идёт ли клип удара (импульс отложен до action_contact, мотор НЕ залочен). Раньше — поле
## _kick_action_active.
func is_kick_action_active() -> bool:
	return false

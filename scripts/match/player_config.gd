class_name PlayerConfig
extends RefCounted
## Вход PlayerFactory.spawn(). Тонкий дата-холдер (эмбрион будущего SquadMember);
## FootballConstants НЕ читает — значения кладёт вызывающий.

enum Role { GK, DEF, MID, FWD }
# ControlMode, не Control — имя "Control" конфликтует со встроенным классом Godot Control
# (базовый UI-узел) и внешние скрипты не резолвят члены класса при коллизии имён.
enum ControlMode { AI, HUMAN, REMOTE }   # REMOTE — заглушка на будущее

var team_group: StringName = &"team_1"
var role: int = Role.MID
var kit_color: Color = Color.WHITE
var spawn_pos: Vector3 = Vector3.ZERO
var control_mode: int = ControlMode.AI
var ai_script: Script = null                 # мозг, когда control_mode == AI (Фаза 1: set_script)
var display_name: String = "Player"
var connect_action_signals: bool = true      # keeper self-connects → false
var locomotion_style: int = -1               # PlayerVisual.LOCO_STYLE_*; -1 = не трогать
var extra_fields: Dictionary = {}            # применяются к телу через set() после set_script

static func role_group(role_id: int) -> StringName:
	match role_id:
		Role.GK: return &"role_gk"
		Role.DEF: return &"role_def"
		Role.MID: return &"role_mid"
		Role.FWD: return &"role_fwd"
	return &"role_mid"

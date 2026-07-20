class_name PlayerFactory
extends Object
## Единственный шов создания игрока. Инстанцирует player.tscn, красит, вешает слои/группы/роль,
## регистрирует в Team, навешивает ИИ-скрипт (Фаза 1: set_script). Повторяет 1:1 порядок операций
## прежних 7 копипаст-сайтов: kit до входа в дерево, set_script ПОСЛЕ add_child, поля после set_script.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

static func spawn(config: PlayerConfig, team: Team) -> CharacterBody3D:
	var body: CharacterBody3D = PLAYER_SCENE.instantiate()
	body.name = config.display_name
	# Позу задаём ДО входа в дерево: тогда физ-тело регистрируется в физсервере сразу на споте.
	# Если ставить global_position ПОСЛЕ add_child, все тела на кадр остаются в origin (0,0,0),
	# где их инстанцировали, и игрок, чей спот и есть origin, оверлапит эти «застрявшие» физ-тела —
	# move_and_slide() депенетрирует его прочь (телепорт на другое тело, зависание в воздухе).
	body.position = config.spawn_pos
	body.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	body.collision_mask = FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
	var visual := find_visual(body)
	if visual != null:
		visual.apply_appearance({"kit_color": config.kit_color})
	# регистрация в ростер + группы (вход в дерево → _ready детей: motor находит visual-сиблинга)
	team.add_player(body, config.role)
	body.set_meta(&"home_pos", config.spawn_pos)
	if config.locomotion_style >= 0 and visual != null:
		visual.set_locomotion_style(config.locomotion_style)
	# сигналы удара/паса на менеджер (вратарь self-connect'ит → connect_action_signals=false)
	if config.connect_action_signals and team.manager != null and visual != null:
		visual.action_contact.connect(team.manager._on_action_contact.bind(body))
		visual.action_finished.connect(team.manager._on_action_finished.bind(body))
	# мозг (Фаза 1: set_script; Фаза 2 заменит компонентом)
	if config.control_mode == PlayerConfig.ControlMode.AI and config.ai_script != null:
		body.set_script(config.ai_script)
		body.set_physics_process(true)
	# общая ссылка на мяч + пер-ролевые поля
	if team.ball != null:
		body.set(&"ball", team.ball)
	for k in config.extra_fields:
		body.set(k, config.extra_fields[k])
	return body

static func find_visual(body: Node) -> PlayerVisual:
	for c in body.get_children():
		if c is PlayerVisual:
			return c
	return null

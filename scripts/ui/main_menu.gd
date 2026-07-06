extends Control


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.1, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "OpenFootball"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_position(Vector2(190, 150))
	title.set_size(Vector2(900, 110))
	add_child(title)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

	var btn := Button.new()
	btn.name = "StartBtn"
	btn.text = "Start Match"
	btn.set_position(Vector2(490, 400))
	btn.set_size(Vector2(300, 80))
	btn.add_theme_font_size_override("font_size", 28)
	add_child(btn)

	if not btn.pressed.is_connected(_on_start):
		btn.pressed.connect(_on_start)

	print("Main menu ready")


func _on_start() -> void:
	print("Start Match clicked")
	var packed := load("res://scenes/match.tscn")
	if not packed:
		push_error("Failed to load match.tscn")
		return
	var err := get_tree().change_scene_to_packed(packed)
	if err != OK:
		push_error("change_scene_to_packed failed: " + str(err))

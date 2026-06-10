extends Control
## Menu principal : choix du mode de jeu.

const GAME_MODES := [
	{
		"label": "Flappy Bird 3D",
		"hint": "Le classique vu de côté, en 3D.",
		"scene": "res://scenes/main_3d.tscn",
	},
	{
		"label": "Arène solo",
		"hint": "Vagues d'ennemis et améliorations roguelite.",
		"scene": "res://scenes/arena.tscn",
	},
	{
		"label": "PvP LAN",
		"hint": "1 à 4 joueurs sur le même réseau.",
		"scene": "res://scenes/pvp_arena.tscn",
	},
	{
		"label": "Prop Hunt LAN",
		"hint": "Un chercheur, les autres se déguisent en objets du décor.",
		"scene": "res://scenes/prop_hunt.tscn",
	},
]

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.13, 0.17, 0.25)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Flapypy"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choisis ton mode de jeu"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	root.add_child(subtitle)

	var first_button: Button = null
	for mode in GAME_MODES:
		var button := Button.new()
		button.text = mode["label"]
		button.custom_minimum_size = Vector2(300, 46)
		button.add_theme_font_size_override("font_size", 22)
		button.pressed.connect(_start_mode.bind(mode["scene"]))
		root.add_child(button)
		if first_button == null:
			first_button = button

		var hint := Label.new()
		hint.text = mode["hint"]
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 14)
		hint.modulate = Color(1, 1, 1, 0.65)
		root.add_child(hint)

	var quit_button := Button.new()
	quit_button.text = "Quitter"
	quit_button.custom_minimum_size = Vector2(300, 40)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	root.add_child(quit_button)

	if first_button:
		first_button.grab_focus()

func _start_mode(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

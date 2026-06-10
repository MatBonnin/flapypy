extends Node3D
## Arène en vagues : chaque vague annonce ses ennemis, et une fois nettoyée
## le joueur choisit une amélioration avant la suivante. Boss toutes les 5 vagues.

const PipemanScene := preload("res://scenes/pipeman.tscn")
const PickupScene := preload("res://scenes/pickup.tscn")
const SAVE_PATH := "user://highscore.cfg"
const SETTINGS_PATH := "user://settings.cfg"
const ACTION_MOVE_UP := "arena_move_up"
const ACTION_MOVE_DOWN := "arena_move_down"
const ACTION_MOVE_LEFT := "arena_move_left"
const ACTION_MOVE_RIGHT := "arena_move_right"
const ACTION_ATTACK := "arena_attack"
const ACTION_THROW_BEAK := "arena_throw_beak"
const ACTION_JUMP := "arena_jump"
const ACTION_PAUSE := "arena_pause"
const CONTROL_BINDINGS := [
	{"action": ACTION_MOVE_UP, "label": "Avancer", "default": KEY_Z},
	{"action": ACTION_MOVE_DOWN, "label": "Reculer", "default": KEY_S},
	{"action": ACTION_MOVE_LEFT, "label": "Gauche", "default": KEY_Q},
	{"action": ACTION_MOVE_RIGHT, "label": "Droite", "default": KEY_D},
	{"action": ACTION_ATTACK, "label": "Massue", "default": KEY_E},
	{"action": ACTION_THROW_BEAK, "label": "Lancer le bec", "default": KEY_F},
	{"action": ACTION_JUMP, "label": "Sauter", "default": KEY_SPACE},
	{"action": ACTION_PAUSE, "label": "Pause", "default": KEY_ESCAPE},
]
const EXTRA_BINDINGS := {
	ACTION_MOVE_UP: [KEY_UP],
	ACTION_MOVE_DOWN: [KEY_DOWN],
	ACTION_MOVE_LEFT: [KEY_LEFT],
	ACTION_MOVE_RIGHT: [KEY_RIGHT],
}

const DROP_CHANCE := 0.35
## Doit suivre l'ordre de l'enum Pickup de player.gd.
const PICKUP_TEXTS: Array[String] = [
	"+2 PV ! Miam !",
	"BAGUETTE MAGIQUE !! Portée énorme !",
	"BEC D'OR : TRIPLE TIR !",
	"CAFÉ !!! VITESSE MAXIMALE !",
	"CHAMPIGNON SUSPECT : MODE GÉANT !",
]
## Doit suivre l'ordre de l'enum Upgrade de player.gd.
const UPGRADE_TEXTS: Array[String] = [
	"+2 PV max et soin complet",
	"Massue brutale : +1 dégât",
	"Bec aiguisé : +1 dégât de projectile",
	"Recharge éclair : bec 30% plus rapide",
	"DOUBLE SAUT !",
	"Bottes véloces : +15% de vitesse",
]

const MAP_HALF := 10.0
const SPAWN_EDGE := 9.5
const MAX_ALIVE := 10
const CAMERA_OFFSET := Vector3(0, 9, 6.5)

const TREE_POSITIONS: Array[Vector3] = [
	Vector3(4.5, 0, -4.5),
	Vector3(5.2, 0, 2.5),
	Vector3(-5.0, 0, 3.5),
	Vector3(-1.5, 0, 5.2),
	Vector3(2.2, 0, -5.2),
	Vector3(-5.4, 0, -0.5),
	Vector3(0.5, 0, 3.8),
	Vector3(7.5, 0, 6.0),
	Vector3(-7.0, 0, -6.5),
	Vector3(8.0, 0, -3.0),
	Vector3(-8.0, 0, 5.5),
	Vector3(6.5, 0, -7.5),
	Vector3(-3.0, 0, 8.0),
	Vector3(3.0, 0, 7.5),
	Vector3(-7.5, 0, 1.5),
]
const ROCK_POSITIONS: Array[Vector3] = [
	Vector3(1.8, 0, 1.2),
	Vector3(-3.0, 0, 1.5),
	Vector3(4.0, 0, -1.0),
	Vector3(-2.2, 0, -2.8),
	Vector3(6.0, 0, 4.5),
	Vector3(-6.0, 0, -3.5),
	Vector3(0.5, 0, -7.0),
	Vector3(-1.0, 0, -4.8),
]
const HOUSE_POSITION := Vector3(-4.0, 0, -4.5)

enum WaveState { INTRO, ACTIVE, CHOICE }

var kills := 0
var best := 0
var wave := 0
var wave_state := WaveState.INTRO
var spawn_queue: Array[int] = []
var upgrade_options: Array[int] = []
var game_over := false
var shake := 0.0
var prev_hp := 0
var boss: Pipeman = null
var boss_bar: Control = null
var boss_fill: ColorRect = null
var pause_overlay: Control = null
var pause_page: Control = null
var settings_page: Control = null
var settings_status: Label = null
var control_buttons: Dictionary = {}
var control_keys: Dictionary = {}
var pending_rebind_action := ""

@onready var player: CharacterBody3D = $Player
@onready var units: Node3D = $Units
@onready var floor_root: Node3D = $Floor
@onready var camera: Camera3D = $Camera3D
@onready var spawn_timer: Timer = $SpawnTimer
@onready var hp_label: Label = $UI/HpLabel
@onready var score_label: Label = $UI/ScoreLabel
@onready var message_label: Label = $UI/MessageLabel
@onready var sfx: Node = $Sfx

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_controls()
	best = _load_best()
	_build_map()
	_build_boss_bar()
	_build_pause_menu()
	prev_hp = player.hp
	player.sfx = sfx
	player.hp_changed.connect(_on_player_hp_changed)
	player.hit_landed.connect(func() -> void: add_shake(0.07))
	player.died.connect(_on_player_died)
	spawn_timer.timeout.connect(_on_spawn_tick)
	camera.position = player.position + CAMERA_OFFSET
	_update_ui()
	message_label.text = _controls_hint()
	await get_tree().create_timer(3.0, false).timeout
	if not game_over:
		_start_wave(1)

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	shake = lerpf(shake, 0.0, 8.0 * delta)
	var target := player.position + CAMERA_OFFSET
	camera.position = camera.position.lerp(target, 6.0 * delta) \
		+ Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake
	if not game_over and wave_state == WaveState.ACTIVE and spawn_queue.is_empty() \
			and get_tree().get_nodes_in_group("enemies").is_empty():
		_begin_choice()
	if boss != null and not is_instance_valid(boss):
		boss = null
		boss_bar.visible = false
	if boss != null:
		boss_fill.size.x = 436.0 * float(maxi(boss.hp, 0)) / float(boss.max_hp_value)

func _unhandled_input(event: InputEvent) -> void:
	if _handle_rebind_input(event):
		return
	if event.is_action_pressed(ACTION_PAUSE):
		if game_over:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
		else:
			_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if game_over:
		if event.is_action_pressed("ui_accept"):
			get_tree().reload_current_scene()
		return
	if wave_state == WaveState.CHOICE and event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		match event.physical_keycode:
			KEY_1, KEY_KP_1:
				idx = 0
			KEY_2, KEY_KP_2:
				idx = 1
			KEY_3, KEY_KP_3:
				idx = 2
		if idx >= 0 and idx < upgrade_options.size():
			player.apply_upgrade(upgrade_options[idx])
			sfx.play_score()
			_update_ui()
			_start_wave(wave + 1)

func _build_pause_menu() -> void:
	pause_overlay = Control.new()
	pause_overlay.name = "PauseMenu"
	pause_overlay.visible = false
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	$UI.add_child(pause_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Pause"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)

	pause_page = VBoxContainer.new()
	pause_page.add_theme_constant_override("separation", 10)
	root.add_child(pause_page)

	var resume_button := _make_menu_button("Reprendre")
	resume_button.pressed.connect(func() -> void: _set_paused(false))
	pause_page.add_child(resume_button)

	var settings_button := _make_menu_button("Parametres")
	settings_button.pressed.connect(_show_settings_page)
	pause_page.add_child(settings_button)

	var quit_button := _make_menu_button("Recommencer")
	quit_button.pressed.connect(func() -> void:
		_set_paused(false)
		get_tree().reload_current_scene()
	)
	pause_page.add_child(quit_button)

	var main_menu_button := _make_menu_button("Menu principal")
	main_menu_button.pressed.connect(func() -> void:
		_set_paused(false)
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	)
	pause_page.add_child(main_menu_button)

	settings_page = VBoxContainer.new()
	settings_page.visible = false
	settings_page.add_theme_constant_override("separation", 9)
	root.add_child(settings_page)

	settings_status = Label.new()
	settings_status.text = "Clique une action, puis appuie sur une touche."
	settings_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_status.add_theme_font_size_override("font_size", 16)
	settings_page.add_child(settings_status)

	for binding in CONTROL_BINDINGS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		settings_page.add_child(row)

		var label := Label.new()
		label.text = binding["label"]
		label.custom_minimum_size = Vector2(220, 32)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)

		var button := Button.new()
		button.text = _key_name(int(control_keys[binding["action"]]))
		button.custom_minimum_size = Vector2(180, 32)
		button.pressed.connect(_begin_rebind.bind(binding["action"]))
		row.add_child(button)
		control_buttons[binding["action"]] = button

	var reset_button := _make_menu_button("Touches par defaut")
	reset_button.pressed.connect(_reset_controls)
	settings_page.add_child(reset_button)

	var back_button := _make_menu_button("Retour")
	back_button.pressed.connect(_show_pause_page)
	settings_page.add_child(back_button)

func _make_menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260, 42)
	button.add_theme_font_size_override("font_size", 20)
	return button

func _show_pause_page() -> void:
	pending_rebind_action = ""
	if pause_page:
		pause_page.visible = true
	if settings_page:
		settings_page.visible = false
	if settings_status:
		settings_status.text = "Clique une action, puis appuie sur une touche."
	_update_control_buttons()

func _show_settings_page() -> void:
	pending_rebind_action = ""
	pause_page.visible = false
	settings_page.visible = true
	settings_status.text = "Clique une action, puis appuie sur une touche."
	_update_control_buttons()

func _set_paused(value: bool) -> void:
	if game_over and value:
		return
	pending_rebind_action = ""
	get_tree().paused = value
	pause_overlay.visible = value
	if value:
		_show_pause_page()

func _begin_rebind(action: String) -> void:
	pending_rebind_action = action
	settings_status.text = "Appuie sur la nouvelle touche pour %s." % _action_label(action)
	_update_control_buttons()
	if control_buttons.has(action):
		control_buttons[action].text = "..."

func _handle_rebind_input(event: InputEvent) -> bool:
	if pending_rebind_action == "":
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		var keycode: int = event.physical_keycode
		if keycode == KEY_NONE:
			keycode = event.keycode
		_apply_rebind(pending_rebind_action, keycode)
		pending_rebind_action = ""
		settings_status.text = "Touches enregistrees."
		get_viewport().set_input_as_handled()
		return true
	return false

func _apply_rebind(action: String, keycode: int) -> void:
	if keycode == KEY_NONE:
		return
	var swapped_action := _action_for_key(keycode)
	var old_key := int(control_keys[action])
	if swapped_action != "" and swapped_action != action:
		control_keys[swapped_action] = old_key
		_apply_action_key(swapped_action, old_key)
	control_keys[action] = keycode
	_apply_action_key(action, keycode)
	_save_controls()
	_update_control_buttons()
	message_label.text = _controls_hint()

func _reset_controls() -> void:
	for binding in CONTROL_BINDINGS:
		var action: String = binding["action"]
		var keycode := int(binding["default"])
		control_keys[action] = keycode
		_apply_action_key(action, keycode)
	_save_controls()
	pending_rebind_action = ""
	settings_status.text = "Touches par defaut restaurees."
	_update_control_buttons()
	message_label.text = _controls_hint()

func _load_controls() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SETTINGS_PATH) == OK
	for binding in CONTROL_BINDINGS:
		var action: String = binding["action"]
		var keycode := int(binding["default"])
		if loaded:
			keycode = int(cfg.get_value("controls", action, keycode))
		control_keys[action] = keycode
		_apply_action_key(action, keycode)

func _save_controls() -> void:
	var cfg := ConfigFile.new()
	for binding in CONTROL_BINDINGS:
		var action: String = binding["action"]
		cfg.set_value("controls", action, int(control_keys[action]))
	cfg.save(SETTINGS_PATH)

func _apply_action_key(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)
	for extra_key in EXTRA_BINDINGS.get(action, []):
		if int(extra_key) != keycode:
			var extra_event := InputEventKey.new()
			extra_event.physical_keycode = int(extra_key)
			InputMap.action_add_event(action, extra_event)

func _update_control_buttons() -> void:
	for binding in CONTROL_BINDINGS:
		var action: String = binding["action"]
		if control_buttons.has(action):
			control_buttons[action].text = _key_name(int(control_keys[action]))

func _action_label(action: String) -> String:
	for binding in CONTROL_BINDINGS:
		if binding["action"] == action:
			return binding["label"]
	return action

func _action_for_key(keycode: int) -> String:
	for binding in CONTROL_BINDINGS:
		var action: String = binding["action"]
		if int(control_keys.get(action, KEY_NONE)) == keycode:
			return action
	return ""

func _key_name(keycode: int) -> String:
	var text := OS.get_keycode_string(keycode)
	if text == "":
		return str(keycode)
	return text

func _controls_hint() -> String:
	return "%s / Fleches : se deplacer\n%s : massue   %s : lancer le bec\n%s : sauter   %s : pause / parametres" % [
		_key_name(int(control_keys[ACTION_MOVE_UP])),
		_key_name(int(control_keys[ACTION_ATTACK])),
		_key_name(int(control_keys[ACTION_THROW_BEAK])),
		_key_name(int(control_keys[ACTION_JUMP])),
		_key_name(int(control_keys[ACTION_PAUSE])),
	]

func add_shake(amount: float) -> void:
	shake = minf(shake + amount, 0.5)

func hit_stop(duration := 0.06, time_scale := 0.05) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = time_scale
	get_tree().create_timer(duration, true, false, true).timeout.connect(
		func() -> void: Engine.time_scale = 1.0)

# --- Vagues ---

func _start_wave(n: int) -> void:
	wave = n
	wave_state = WaveState.INTRO
	spawn_queue = _wave_composition(n)
	if n % 5 == 0:
		message_label.text = "VAGUE %d\nLE TUYAU SUPRÊME ARRIVE !!" % n
		add_shake(0.3)
	else:
		message_label.text = "VAGUE %d" % n
	_update_ui()
	await get_tree().create_timer(2.0, false).timeout
	if game_over:
		return
	message_label.text = ""
	wave_state = WaveState.ACTIVE
	spawn_timer.wait_time = 0.5
	spawn_timer.start()

func _wave_composition(n: int) -> Array[int]:
	var q: Array[int] = []
	if n % 5 == 0:
		q.append(Pipeman.Kind.BOSS)
		for i in 2:
			q.append(Pipeman.Kind.NORMAL)
		for i in mini(n / 2, 5):
			q.append(Pipeman.Kind.RUNNER)
		return q
	var count := mini(4 + n * 2, 14)
	for i in count:
		var roll := randf()
		if n >= 4 and roll < 0.18:
			q.append(Pipeman.Kind.SHOOTER)
		elif n >= 3 and roll < 0.38:
			q.append(Pipeman.Kind.TANK)
		elif n >= 2 and roll < 0.65:
			q.append(Pipeman.Kind.RUNNER)
		else:
			q.append(Pipeman.Kind.NORMAL)
	return q

func _on_spawn_tick() -> void:
	if game_over or wave_state != WaveState.ACTIVE or spawn_queue.is_empty():
		spawn_timer.stop()
		return
	if get_tree().get_nodes_in_group("enemies").size() >= MAX_ALIVE:
		return
	var kind: int = spawn_queue.pop_front()
	var enemy: Pipeman = PipemanScene.instantiate()
	enemy.position = _random_edge_position()
	enemy.player = player
	enemy.sfx = sfx
	enemy.killed.connect(_on_enemy_killed)
	units.add_child(enemy)
	enemy.setup(kind)
	if kind == Pipeman.Kind.BOSS:
		boss = enemy
		boss_bar.visible = true
	spawn_timer.wait_time = randf_range(0.7, 1.4)

func _begin_choice() -> void:
	wave_state = WaveState.CHOICE
	upgrade_options.clear()
	var pool: Array[int] = []
	for id in UPGRADE_TEXTS.size():
		if id == player.Upgrade.DOUBLE_JUMP and player.max_jumps >= 2:
			continue
		pool.append(id)
	pool.shuffle()
	for i in 3:
		upgrade_options.append(pool[i])
	sfx.play_score()
	message_label.text = "VAGUE %d NETTOYÉE !\nChoisis ton amélioration (touches 1, 2, 3) :\n1 — %s\n2 — %s\n3 — %s" % [
		wave,
		UPGRADE_TEXTS[upgrade_options[0]],
		UPGRADE_TEXTS[upgrade_options[1]],
		UPGRADE_TEXTS[upgrade_options[2]],
	]

func _random_edge_position() -> Vector3:
	var t := randf_range(-SPAWN_EDGE, SPAWN_EDGE)
	var side := randi() % 4
	if side == 0:
		return Vector3(t, 0.0, -SPAWN_EDGE)
	if side == 1:
		return Vector3(t, 0.0, SPAWN_EDGE)
	if side == 2:
		return Vector3(-SPAWN_EDGE, 0.0, t)
	return Vector3(SPAWN_EDGE, 0.0, t)

# --- Réactions ---

func _on_enemy_killed(pos: Vector3, kind: int) -> void:
	kills += 1
	sfx.play_score()
	_update_ui()
	if kind == Pipeman.Kind.BOSS:
		add_shake(0.45)
		hit_stop(0.18, 0.05)
		_spawn_burst(pos, Color(0.75, 0.2, 0.15), 40, 2.0)
		for i in 3:
			_spawn_pickup(pos + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
	else:
		add_shake(0.16)
		hit_stop()
		_spawn_burst(pos, Color(0.3, 0.69, 0.31))
		if randf() < DROP_CHANCE:
			_spawn_pickup(pos)

func _on_player_hp_changed(new_hp: int) -> void:
	if new_hp < prev_hp:
		add_shake(0.3)
	prev_hp = new_hp
	_update_ui()

func _on_player_died() -> void:
	game_over = true
	spawn_timer.stop()
	boss_bar.visible = false
	if kills > best:
		best = kills
		_save_best()
	message_label.text = "Game Over à la vague %d\nTués : %d   Record : %d\nEntrée pour rejouer — Échap pour le menu" % [wave, kills, best]

func _spawn_pickup(pos: Vector3) -> void:
	var pickup: Area3D = PickupScene.instantiate()
	# pondération : le coeur est le plus fréquent
	var roll := randf()
	if roll < 0.34:
		pickup.type = player.Pickup.HEART
	elif roll < 0.52:
		pickup.type = player.Pickup.BAGUETTE
	elif roll < 0.70:
		pickup.type = player.Pickup.GOLD_BEAK
	elif roll < 0.86:
		pickup.type = player.Pickup.COFFEE
	else:
		pickup.type = player.Pickup.MUSHROOM
	pickup.position = Vector3(pos.x, 0.45, pos.z)
	pickup.collected.connect(_on_pickup_collected)
	add_child(pickup)

func _on_pickup_collected(type: int) -> void:
	player.apply_pickup(type)
	sfx.play_score()
	_update_ui()
	if wave_state != WaveState.CHOICE:
		_show_popup(PICKUP_TEXTS[type])

func _show_popup(text: String) -> void:
	message_label.text = text
	get_tree().create_timer(2.2, false).timeout.connect(func() -> void:
		if not game_over and message_label.text == text:
			message_label.text = "")

# --- Effets ---

func _spawn_burst(pos: Vector3, color: Color, amount := 16, scale_f := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 3.0 * scale_f
	p.initial_velocity_max = 6.0 * scale_f
	p.gravity = Vector3(0, -14, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 0.12) * scale_f
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	p.mesh = mesh
	p.position = pos + Vector3(0, 0.6, 0)
	add_child(p)
	get_tree().create_timer(1.5, false).timeout.connect(p.queue_free)

# --- Construction de la map ---

func _build_map() -> void:
	_build_floor()
	_add_walls()
	for pos in TREE_POSITIONS:
		_add_tree(pos)
	for pos in ROCK_POSITIONS:
		_add_rock(pos)
	_add_house(HOUSE_POSITION)

func _build_boss_bar() -> void:
	boss_bar = Control.new()
	boss_bar.visible = false
	boss_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	$UI.add_child(boss_bar)
	var label := Label.new()
	label.text = "LE TUYAU SUPRÊME"
	label.position = Vector2(-220, 54)
	label.size = Vector2(440, 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	boss_bar.add_child(label)
	var bg := ColorRect.new()
	bg.position = Vector2(-220, 84)
	bg.size = Vector2(440, 20)
	bg.color = Color(0, 0, 0, 0.6)
	boss_bar.add_child(bg)
	boss_fill = ColorRect.new()
	boss_fill.position = Vector2(-218, 86)
	boss_fill.size = Vector2(436, 16)
	boss_fill.color = Color(0.85, 0.2, 0.15)
	boss_bar.add_child(boss_fill)

func _make_obstacle(shape: Shape3D, shape_offset: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = shape_offset
	body.add_child(col)
	return body

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, mesh_scale := Vector3.ONE) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = mesh_scale
	parent.add_child(mi)
	return mi

func _add_walls() -> void:
	var stone := Color(0.55, 0.53, 0.5)
	var sides := [
		[Vector3(0, 0.4, -10.2), Vector3(20.8, 0.8, 0.4)],
		[Vector3(0, 0.4, 10.2), Vector3(20.8, 0.8, 0.4)],
		[Vector3(-10.2, 0.4, 0), Vector3(0.4, 0.8, 20.8)],
		[Vector3(10.2, 0.4, 0), Vector3(0.4, 0.8, 20.8)],
	]
	for side in sides:
		var shape := BoxShape3D.new()
		shape.size = side[1]
		var body := _make_obstacle(shape, Vector3.ZERO)
		var mesh := BoxMesh.new()
		mesh.size = side[1]
		_add_mesh(body, mesh, Vector3.ZERO, stone)
		body.position = side[0]
		floor_root.add_child(body)

func _add_tree(pos: Vector3) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 2.0
	var body := _make_obstacle(shape, Vector3(0, 1, 0))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.18
	trunk.height = 0.9
	_add_mesh(body, trunk, Vector3(0, 0.45, 0), Color(0.45, 0.3, 0.17))
	var leaves := SphereMesh.new()
	leaves.radius = 0.75
	leaves.height = 1.5
	_add_mesh(body, leaves, Vector3(0, 1.45, 0), Color(0.2, 0.5, 0.22))
	var top := SphereMesh.new()
	top.radius = 0.5
	top.height = 1.0
	_add_mesh(body, top, Vector3(0, 2.05, 0), Color(0.25, 0.58, 0.26))
	body.position = pos
	floor_root.add_child(body)

func _add_rock(pos: Vector3) -> void:
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var body := _make_obstacle(shape, Vector3(0, 0.12, 0))
	var mesh := SphereMesh.new()
	mesh.radius = 0.38
	mesh.height = 0.76
	_add_mesh(body, mesh, Vector3(0, 0.1, 0), Color(0.6, 0.6, 0.62), Vector3(1, 0.55, 0.85))
	body.position = pos
	body.rotation.y = randf_range(0.0, TAU)
	floor_root.add_child(body)

func _add_house(pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.8, 2.5)
	var body := _make_obstacle(shape, Vector3(0, 0.9, 0))
	var walls := BoxMesh.new()
	walls.size = Vector3(3.0, 1.8, 2.5)
	_add_mesh(body, walls, Vector3(0, 0.9, 0), Color(0.87, 0.78, 0.62))
	var roof := PrismMesh.new()
	roof.size = Vector3(3.4, 1.1, 2.9)
	_add_mesh(body, roof, Vector3(0, 2.35, 0), Color(0.65, 0.28, 0.2))
	var door := BoxMesh.new()
	door.size = Vector3(0.6, 1.1, 0.1)
	_add_mesh(body, door, Vector3(0.6, 0.55, 1.28), Color(0.35, 0.23, 0.13))
	var window := BoxMesh.new()
	window.size = Vector3(0.55, 0.55, 0.1)
	_add_mesh(body, window, Vector3(-0.7, 1.0, 1.28), Color(0.75, 0.88, 0.95))
	body.position = pos
	floor_root.add_child(body)

func _build_floor() -> void:
	# prairie : texture d'herbe générée par bruit procédural
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.06
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.33, 0.52, 0.24))
	ramp.set_color(1, Color(0.55, 0.73, 0.38))
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(4, 4, 4)
	var plane := PlaneMesh.new()
	plane.size = Vector2(MAP_HALF * 2.08, MAP_HALF * 2.08)
	plane.material = mat
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	floor_root.add_child(ground)
	# touffes d'herbe et fleurs décoratives
	for i in 80:
		var tuft := CylinderMesh.new()
		tuft.top_radius = 0.0
		tuft.bottom_radius = 0.06
		tuft.height = 0.22
		var pos := Vector3(randf_range(-SPAWN_EDGE, SPAWN_EDGE), 0.11, randf_range(-SPAWN_EDGE, SPAWN_EDGE))
		_add_mesh(floor_root, tuft, pos, Color(0.3, 0.55, 0.25))
	var flower_colors: Array[Color] = [
		Color(1, 1, 1), Color(0.95, 0.85, 0.3), Color(0.9, 0.5, 0.6),
	]
	for i in 35:
		var flower := SphereMesh.new()
		flower.radius = 0.06
		flower.height = 0.12
		var pos := Vector3(randf_range(-SPAWN_EDGE, SPAWN_EDGE), 0.08, randf_range(-SPAWN_EDGE, SPAWN_EDGE))
		_add_mesh(floor_root, flower, pos, flower_colors[randi() % flower_colors.size()])

# --- UI et sauvegarde ---

func _update_ui() -> void:
	hp_label.text = "PV : %d" % maxi(player.hp, 0)
	score_label.text = "Vague %d   Tués : %d" % [maxi(wave, 1), kills]

func _load_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return int(cfg.get_value("game", "best_arena", 0))
	return 0

func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("game", "best_arena", best)
	cfg.save(SAVE_PATH)

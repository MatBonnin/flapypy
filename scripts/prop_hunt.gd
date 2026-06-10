extends Node3D
## Prop Hunt LAN : un chercheur, les autres se deguisent en objets de la map.
## Manche en deux phases : les props se cachent, puis le chercheur les traque.
## L'hote reste autoritaire pour les roles, les degats et la fin de manche.

const BirdmanScene := preload("res://scenes/birdman.tscn")
const SETTINGS_PATH := "user://settings.cfg"
const PORT := 42425
const MAX_PLAYERS := 4
const HIDE_SECONDS := 12.0
const HUNT_SECONDS := 120.0
const OVER_SECONDS := 6.0
const STATE_SEND_INTERVAL := 0.05
const MORPH_RANGE := 3.0
const SEEKER_HP := 10
const HIDER_HP := 2
const SEEKER_SPEED_MULT := 1.15
const MORPH_SPEED_MULT := 0.8
const MAP_HALF := 10.0
const CAMERA_OFFSET := Vector3(0, 9, 6.5)
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
	{"action": ACTION_ATTACK, "label": "Massue / Deguisement", "default": KEY_E},
	{"action": ACTION_THROW_BEAK, "label": "Lancer le bec", "default": KEY_F},
	{"action": ACTION_JUMP, "label": "Sauter", "default": KEY_SPACE},
	{"action": ACTION_PAUSE, "label": "Parametres", "default": KEY_ESCAPE},
]
const EXTRA_BINDINGS := {
	ACTION_MOVE_UP: [KEY_UP],
	ACTION_MOVE_DOWN: [KEY_DOWN],
	ACTION_MOVE_LEFT: [KEY_LEFT],
	ACTION_MOVE_RIGHT: [KEY_RIGHT],
}
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-6.5, 0, -6.5),
	Vector3(6.5, 0, 6.5),
	Vector3(-6.5, 0, 6.5),
	Vector3(6.5, 0, -6.5),
]
const SEEKER_SPAWN := Vector3(0, 0, 0)
const PLAYER_COLORS: Array[Color] = [
	Color(0.97, 0.82, 0.27),
	Color(0.25, 0.55, 1.0),
	Color(0.35, 0.85, 0.35),
	Color(0.8, 0.45, 0.9),
]
const SEEKER_COLOR := Color(0.95, 0.2, 0.2)
const HOUSE_POSITION := Vector3(-4.0, 0, -4.5)

enum Phase { LOBBY, HIDE, HUNT, OVER }
enum Prop { TREE, ROCK, BARREL, CRATE, HAY, STUMP, BUSH, PUMPKIN }
## Doit suivre l'ordre de l'enum Prop.
const PROP_COUNTS: Array[int] = [10, 8, 7, 7, 6, 6, 8, 7]

## Surchargeable (les tests utilisent un port dedie pour ne pas entrer en
## collision avec une partie en cours sur la machine).
var listen_port := PORT
var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}
var player_names: Dictionary = {}
var player_order: Array[int] = []
var kills: Dictionary = {}
var morphs: Dictionary = {}
var props: Array = []  # [{ "type": int, "pos": Vector3 }]
var seeker_id := 0
var phase: int = Phase.LOBBY
var phase_time_left := 0.0
var round_index := -1
var state_send_timer := 0.0

var ui_layer: CanvasLayer
var menu_panel: PanelContainer
var name_edit: LineEdit
var ip_edit: LineEdit
var status_label: Label
var timer_label: Label
var board_label: Label
var message_label: Label
var host_button: Button
var join_button: Button
var start_button: Button
var seeker_overlay: Control
var seeker_overlay_label: Label
var controls_panel: Control
var controls_status: Label
var control_buttons: Dictionary = {}
var control_keys: Dictionary = {}
var pending_rebind_action := ""
var controls_return_to_menu := false

@onready var units: Node3D = $Units
@onready var floor_root: Node3D = $Floor
@onready var camera: Camera3D = $Camera3D
@onready var sfx: Node = $Sfx

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_controls()
	_build_map()
	_build_ui()
	_connect_multiplayer_signals()
	camera.position = CAMERA_OFFSET

func _input(event: InputEvent) -> void:
	if _handle_rebind_input(event):
		return
	if controls_panel != null and controls_panel.visible:
		if event.is_action_pressed(ACTION_PAUSE):
			_hide_controls_panel()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_PAUSE):
		_show_controls_panel(false)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		match phase:
			Phase.HIDE:
				phase_time_left = maxf(phase_time_left - delta, 0.0)
				rpc("_client_phase_time", phase_time_left)
				if phase_time_left <= 0.0:
					_server_set_phase(Phase.HUNT, HUNT_SECONDS)
			Phase.HUNT:
				phase_time_left = maxf(phase_time_left - delta, 0.0)
				rpc("_client_phase_time", phase_time_left)
				if phase_time_left <= 0.0:
					_server_end_round("Temps ecoule — victoire des PROPS !")
			Phase.OVER:
				phase_time_left = maxf(phase_time_left - delta, 0.0)
				if phase_time_left <= 0.0:
					_server_back_to_lobby()
	_update_camera(delta)
	_update_hud()

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	state_send_timer += delta
	if state_send_timer < STATE_SEND_INTERVAL:
		return
	state_send_timer = 0.0
	var local_id := multiplayer.get_unique_id()
	var player: CharacterBody3D = players.get(local_id)
	if player == null:
		return
	if multiplayer.is_server():
		rpc("_client_player_state", local_id, player.global_position, player.rotation.y, player.hp, player.dead)
	else:
		rpc_id(1, "_server_player_state", player.global_position, player.rotation.y)

func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _load_controls() -> void:
	var cfg := ConfigFile.new()
	var loaded: bool = cfg.load(SETTINGS_PATH) == OK
	for binding in CONTROL_BINDINGS:
		var action: String = binding["action"]
		var keycode: int = int(binding["default"])
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
	if keycode == KEY_NONE:
		return
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

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	timer_label = _make_label(Vector2(20, 18), Vector2(320, 42), 30, HORIZONTAL_ALIGNMENT_LEFT)
	ui_layer.add_child(timer_label)

	board_label = _make_label(Vector2(-360, 18), Vector2(340, 180), 20, HORIZONTAL_ALIGNMENT_RIGHT)
	board_label.anchor_left = 1.0
	board_label.anchor_right = 1.0
	ui_layer.add_child(board_label)

	message_label = _make_label(Vector2(0, -160), Vector2(0, 130), 26, HORIZONTAL_ALIGNMENT_CENTER)
	message_label.anchor_top = 1.0
	message_label.anchor_right = 1.0
	message_label.anchor_bottom = 1.0
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui_layer.add_child(message_label)

	start_button = Button.new()
	start_button.text = "Lancer la manche"
	start_button.visible = false
	start_button.anchor_left = 0.5
	start_button.anchor_right = 0.5
	start_button.offset_left = -130
	start_button.offset_right = 130
	start_button.offset_top = 70
	start_button.offset_bottom = 116
	start_button.add_theme_font_size_override("font_size", 20)
	start_button.pressed.connect(_on_start_pressed)
	ui_layer.add_child(start_button)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(center)

	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(menu_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	menu_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Prop Hunt LAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nom du joueur"
	name_edit.text = "Joueur"
	root.add_child(name_edit)

	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP de l'hote"
	ip_edit.text = "127.0.0.1"
	root.add_child(ip_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)

	host_button = Button.new()
	host_button.text = "Heberger"
	host_button.custom_minimum_size = Vector2(0, 42)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.pressed.connect(_host_game)
	row.add_child(host_button)

	join_button = Button.new()
	join_button.text = "Rejoindre"
	join_button.custom_minimum_size = Vector2(0, 42)
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(_join_game)
	row.add_child(join_button)

	var settings_button := Button.new()
	settings_button.text = "Parametres des touches"
	settings_button.custom_minimum_size = Vector2(0, 38)
	settings_button.pressed.connect(_show_controls_panel.bind(true))
	root.add_child(settings_button)

	var main_menu_button := Button.new()
	main_menu_button.text = "Menu principal"
	main_menu_button.custom_minimum_size = Vector2(0, 38)
	main_menu_button.pressed.connect(_back_to_main_menu)
	root.add_child(main_menu_button)

	status_label = Label.new()
	status_label.text = "Un chercheur, les autres se transforment en objets. 2 a 4 joueurs sur le meme reseau.\n%s" % _local_network_hint()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_label)

	_build_seeker_overlay()
	_build_controls_panel()

func _build_seeker_overlay() -> void:
	seeker_overlay = Control.new()
	seeker_overlay.name = "SeekerOverlay"
	seeker_overlay.visible = false
	seeker_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(seeker_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	seeker_overlay.add_child(dim)

	seeker_overlay_label = Label.new()
	seeker_overlay_label.text = ""
	seeker_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seeker_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seeker_overlay_label.add_theme_font_size_override("font_size", 34)
	seeker_overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	seeker_overlay.add_child(seeker_overlay_label)

func _make_label(pos: Vector2, size: Vector2, font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = size
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 8)
	return label

func _build_controls_panel() -> void:
	controls_panel = Control.new()
	controls_panel.name = "ControlsPanel"
	controls_panel.visible = false
	controls_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(controls_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls_panel.add_child(center)

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
	root.add_theme_constant_override("separation", 9)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Parametres"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)

	controls_status = Label.new()
	controls_status.text = "Clique une action, puis appuie sur une touche."
	controls_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_status.add_theme_font_size_override("font_size", 16)
	root.add_child(controls_status)

	for binding in CONTROL_BINDINGS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		root.add_child(row)

		var label := Label.new()
		label.text = binding["label"]
		label.custom_minimum_size = Vector2(220, 32)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)

		var button := Button.new()
		var action: String = binding["action"]
		button.text = _key_name(int(control_keys[action]))
		button.custom_minimum_size = Vector2(180, 32)
		button.pressed.connect(_begin_rebind.bind(action))
		row.add_child(button)
		control_buttons[action] = button

	var reset_button := Button.new()
	reset_button.text = "Touches par defaut"
	reset_button.custom_minimum_size = Vector2(260, 38)
	reset_button.pressed.connect(_reset_controls)
	root.add_child(reset_button)

	var back_button := Button.new()
	back_button.text = "Retour"
	back_button.custom_minimum_size = Vector2(260, 38)
	back_button.pressed.connect(_hide_controls_panel)
	root.add_child(back_button)

	var leave_button := Button.new()
	leave_button.text = "Quitter vers le menu"
	leave_button.custom_minimum_size = Vector2(260, 38)
	leave_button.pressed.connect(_back_to_main_menu)
	root.add_child(leave_button)

func _show_controls_panel(return_to_menu: bool) -> void:
	controls_return_to_menu = return_to_menu
	pending_rebind_action = ""
	if return_to_menu:
		menu_panel.visible = false
	controls_panel.visible = true
	controls_status.text = "Clique une action, puis appuie sur une touche."
	_update_control_buttons()

func _hide_controls_panel() -> void:
	pending_rebind_action = ""
	controls_panel.visible = false
	if controls_return_to_menu and multiplayer.multiplayer_peer == null:
		menu_panel.visible = true
	controls_return_to_menu = false
	_update_control_buttons()

func _begin_rebind(action: String) -> void:
	pending_rebind_action = action
	controls_status.text = "Appuie sur la nouvelle touche pour %s." % _action_label(action)
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
		controls_status.text = "Touches enregistrees."
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

func _reset_controls() -> void:
	for binding in CONTROL_BINDINGS:
		var action: String = binding["action"]
		var keycode := int(binding["default"])
		control_keys[action] = keycode
		_apply_action_key(action, keycode)
	_save_controls()
	_update_control_buttons()
	controls_status.text = "Touches remises par defaut."

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

func _local_network_hint() -> String:
	var addresses := _get_lan_addresses()
	if addresses.is_empty():
		return "Aucune IPv4 LAN detectee. Verifie le Wi-Fi/Ethernet et evite 127.0.0.1."
	return "IP a donner : %s | Port UDP : %d" % [", ".join(addresses), PORT]

func _get_lan_addresses() -> PackedStringArray:
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		var text := str(address)
		if _is_private_ipv4(text) and not addresses.has(text):
			addresses.append(text)
	return addresses

func _is_private_ipv4(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4:
		return false
	if address.begins_with("10.") or address.begins_with("192.168."):
		return true
	if address.begins_with("172."):
		var second := int(parts[1])
		return second >= 16 and second <= 31
	return false

func _back_to_main_menu() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	peer = null
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _host_game() -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(listen_port, MAX_PLAYERS - 1)
	if err != OK:
		status_label.text = "Impossible d'heberger sur le port %d." % listen_port
		return
	multiplayer.multiplayer_peer = peer
	var host_id := multiplayer.get_unique_id()
	player_names[host_id] = _clean_name(name_edit.text, "Hote")
	player_order.append(host_id)
	kills[host_id] = 0
	_client_spawn_player(host_id, player_names[host_id], SPAWN_POINTS[0], 8, false)
	phase = Phase.LOBBY
	menu_panel.visible = false
	message_label.text = "Lobby ouvert : en attente de joueurs (2 minimum)."

func _join_game() -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip_edit.text.strip_edges(), listen_port)
	if err != OK:
		status_label.text = "Connexion impossible."
		return
	multiplayer.multiplayer_peer = peer
	host_button.disabled = true
	join_button.disabled = true
	status_label.text = "Connexion a %s..." % ip_edit.text.strip_edges()

func _on_connected_to_server() -> void:
	menu_panel.visible = false
	message_label.text = "Connexion OK"
	rpc_id(1, "_server_register_player", _clean_name(name_edit.text, "Joueur"))

func _on_connection_failed() -> void:
	host_button.disabled = false
	join_button.disabled = false
	status_label.text = "Connexion echouee."

func _on_server_disconnected() -> void:
	message_label.text = "Hote deconnecte. Echap pour quitter vers le menu."
	phase = Phase.OVER
	seeker_overlay.visible = false
	_set_local_frozen(false)

func _on_peer_connected(_id: int) -> void:
	pass

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var was_seeker: bool = id == seeker_id
	_remove_player(id)
	rpc("_client_remove_player", id)
	if phase == Phase.HIDE or phase == Phase.HUNT:
		if was_seeker:
			_server_end_round("Le chercheur est parti — victoire des PROPS !")
		else:
			_check_round_end()

@rpc("any_peer", "reliable")
func _server_register_player(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if player_order.size() >= MAX_PLAYERS:
		rpc_id(id, "_client_rejected", "Partie pleine.")
		return
	if phase != Phase.LOBBY:
		rpc_id(id, "_client_rejected", "Manche en cours, reessaie dans un instant.")
		return
	player_names[id] = _clean_name(display_name, "Joueur %d" % id)
	player_order.append(id)
	kills[id] = 0
	var spawn_pos := SPAWN_POINTS[(player_order.size() - 1) % SPAWN_POINTS.size()]
	for existing_id in player_order:
		var existing_player: CharacterBody3D = players.get(existing_id)
		var existing_hp := 8
		var existing_dead := false
		var existing_pos := SPAWN_POINTS[player_order.find(existing_id) % SPAWN_POINTS.size()]
		if existing_player != null:
			existing_hp = existing_player.hp
			existing_dead = existing_player.dead
			existing_pos = existing_player.global_position
		rpc_id(id, "_client_spawn_player", existing_id, player_names[existing_id], existing_pos, existing_hp, existing_dead)
	rpc("_client_spawn_player", id, player_names[id], spawn_pos, 8, false)
	# le nouveau venu doit voir les deguisements deja en cours dans le lobby
	for morph_id in morphs:
		if int(morphs[morph_id]) >= 0:
			rpc_id(id, "_client_set_morph", morph_id, int(morphs[morph_id]))
	_broadcast_scoreboard()

@rpc("authority", "reliable")
func _client_rejected(reason: String) -> void:
	message_label.text = reason
	menu_panel.visible = true
	host_button.disabled = false
	join_button.disabled = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	peer = null

@rpc("authority", "call_local", "reliable")
func _client_spawn_player(peer_id: int, display_name: String, spawn_pos: Vector3, hp_value: int, is_dead: bool) -> void:
	player_names[peer_id] = display_name
	if not player_order.has(peer_id):
		player_order.append(peer_id)
	if not kills.has(peer_id):
		kills[peer_id] = 0
	if players.has(peer_id):
		var existing: CharacterBody3D = players[peer_id]
		existing.set_pvp_remote_state(spawn_pos, existing.rotation.y, hp_value, is_dead)
		return
	var player: CharacterBody3D = BirdmanScene.instantiate()
	player.name = "Player_%d" % peer_id
	player.position = spawn_pos
	player.pvp_enabled = true
	player.pvp_peer_id = peer_id
	player.pvp_arena = self
	player.sfx = sfx
	player.set_multiplayer_authority(peer_id)
	player.add_to_group("prop_hunt_players")
	units.add_child(player)
	player.set_pvp_color(_base_color(peer_id))
	player.set_pvp_health(hp_value, is_dead)
	players[peer_id] = player

@rpc("authority", "call_local", "reliable")
func _client_remove_player(peer_id: int) -> void:
	_remove_player(peer_id)

func _remove_player(peer_id: int) -> void:
	if players.has(peer_id):
		var player: Node = players[peer_id]
		if is_instance_valid(player):
			player.queue_free()
		players.erase(peer_id)
	player_names.erase(peer_id)
	kills.erase(peer_id)
	morphs.erase(peer_id)
	player_order.erase(peer_id)

@rpc("any_peer", "unreliable")
func _server_player_state(pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	# le chercheur reste fige pendant que les props se cachent
	if phase == Phase.HIDE and id == seeker_id:
		return
	var player: CharacterBody3D = players.get(id)
	if player == null or player.dead:
		return
	# pvp_target_* d'abord : teleporter global_position ferait clignoter le
	# joueur cote hote (le lerp le ramenerait vers une cible jamais mise a jour)
	var clamped_pos := _clamp_to_arena(pos)
	player.set_pvp_remote_state(clamped_pos, rot_y, player.hp, player.dead)
	rpc("_client_player_state", id, clamped_pos, rot_y, player.hp, player.dead)

@rpc("authority", "unreliable")
func _client_player_state(peer_id: int, pos: Vector3, rot_y: float, hp_value: int, is_dead: bool) -> void:
	var local_id := multiplayer.get_unique_id()
	var player: CharacterBody3D = players.get(peer_id)
	if player == null:
		return
	if peer_id == local_id:
		player.set_pvp_health(hp_value, is_dead)
	else:
		player.set_pvp_remote_state(pos, rot_y, hp_value, is_dead)

## Appelee par player.gd quand le joueur local frappe (touche Massue).
## Chercheur : coup de massue. Prop : prend l'apparence de l'objet le plus proche.
func request_pvp_strike(attacker_id: int) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_server_handle_action(attacker_id)
	else:
		rpc_id(1, "_server_request_action")

## Pas de projectile dans ce mode : la massue suffit au chercheur.
func request_pvp_beak(_owner_id: int, _start_pos: Vector3, _direction: Vector3, _rot_y: float, _damage: int) -> void:
	pass

@rpc("any_peer", "reliable")
func _server_request_action() -> void:
	if not multiplayer.is_server():
		return
	_server_handle_action(multiplayer.get_remote_sender_id())

func _server_handle_action(id: int) -> void:
	if id != seeker_id or phase == Phase.LOBBY or phase == Phase.OVER:
		_server_do_morph(id)
	elif phase == Phase.HUNT:
		_server_apply_strike(id)
		rpc("_client_play_attack", id)
	# chercheur pendant la phase de cachette : rien

func _server_do_morph(id: int) -> void:
	var player: CharacterBody3D = players.get(id)
	if player == null or player.dead:
		return
	var nearest_type := -1
	var nearest_dist := MORPH_RANGE
	for prop in props:
		var d: float = (prop["pos"] - player.global_position).length()
		if d <= nearest_dist:
			nearest_dist = d
			nearest_type = int(prop["type"])
	if nearest_type < 0:
		return
	rpc("_client_set_morph", id, nearest_type)

@rpc("authority", "call_local", "reliable")
func _client_set_morph(peer_id: int, prop_type: int) -> void:
	var player: CharacterBody3D = players.get(peer_id)
	if player == null:
		return
	morphs[peer_id] = prop_type
	var old: Node = player.get_node_or_null("MorphVisual")
	if old != null:
		old.queue_free()
	if prop_type >= 0:
		var visual := _make_prop_visual(prop_type)
		visual.name = "MorphVisual"
		player.add_child(visual)
		player.model.visible = false
		if peer_id != seeker_id:
			player.speed_mult = MORPH_SPEED_MULT
		# son uniquement local : le chercheur ne doit pas entendre les
		# re-deguisements des props
		if sfx and peer_id == multiplayer.get_unique_id():
			sfx.play_flap()
	else:
		player.model.visible = true
		player.speed_mult = SEEKER_SPEED_MULT if peer_id == seeker_id else 1.0

@rpc("authority", "call_local", "reliable")
func _client_play_attack(attacker_id: int) -> void:
	if attacker_id == multiplayer.get_unique_id():
		return
	var player: CharacterBody3D = players.get(attacker_id)
	if player != null:
		player.play_pvp_attack_visual()

func _server_apply_strike(attacker_id: int) -> void:
	var attacker: CharacterBody3D = players.get(attacker_id)
	if attacker == null or attacker.dead:
		return
	var fwd := Vector3(sin(attacker.rotation.y), 0.0, cos(attacker.rotation.y))
	var hit_any := false
	for victim_id in player_order:
		if victim_id == attacker_id:
			continue
		var victim: CharacterBody3D = players.get(victim_id)
		if victim == null or victim.dead:
			continue
		if victim.position.y > 0.6:
			continue
		var to: Vector3 = victim.global_position - attacker.global_position
		to.y = 0.0
		var dist := to.length()
		if dist <= attacker._melee_range() and (dist <= 0.01 or fwd.angle_to(to.normalized()) <= attacker.ATTACK_ARC):
			var hp_before: int = victim.hp
			victim.take_damage(1)
			if victim.hp < hp_before:
				hit_any = true
			rpc("_client_player_health", victim_id, victim.hp, victim.dead)
			if hp_before > 0 and victim.dead:
				kills[attacker_id] = int(kills.get(attacker_id, 0)) + 1
				rpc("_client_set_morph", victim_id, -1)
				_broadcast_scoreboard()
	if hit_any:
		_check_round_end()
	else:
		_server_punish_miss(attacker)

## Chaque coup de massue dans le vide (ou dans un vrai decor) coute 1 PV au chercheur.
func _server_punish_miss(attacker: CharacterBody3D) -> void:
	var new_hp: int = attacker.hp - 1
	var now_dead: bool = new_hp <= 0
	rpc("_client_player_health", seeker_id, new_hp, now_dead)
	if now_dead:
		_server_end_round("Le chercheur est K.O. — victoire des PROPS !")

@rpc("authority", "call_local", "reliable")
func _client_player_health(peer_id: int, hp_value: int, is_dead: bool) -> void:
	var player: CharacterBody3D = players.get(peer_id)
	if player == null:
		return
	var old_hp: int = player.hp
	player.set_pvp_health(hp_value, is_dead)
	if hp_value >= old_hp:
		return
	# le flash rouge de set_pvp_health touche le modele d'oiseau, invisible
	# sous un deguisement : on ecrase le prop et on joue le son partout
	if sfx:
		sfx.play_hit()
	var morph: Node3D = player.get_node_or_null("MorphVisual")
	if morph != null:
		var tw := morph.create_tween()
		tw.tween_property(morph, "scale", Vector3.ONE * 0.78, 0.06)
		tw.tween_property(morph, "scale", Vector3.ONE, 0.1)

func _broadcast_scoreboard() -> void:
	var data: Array = []
	for id in player_order:
		var player: CharacterBody3D = players.get(id)
		var hp_value := 0
		var is_dead := true
		if player != null:
			hp_value = player.hp
			is_dead = player.dead
		data.append([id, player_names.get(id, "Joueur"), int(kills.get(id, 0)), hp_value, is_dead])
	rpc("_client_scoreboard", data)

@rpc("authority", "call_local", "reliable")
func _client_scoreboard(data: Array) -> void:
	for row in data:
		var id := int(row[0])
		player_names[id] = str(row[1])
		kills[id] = int(row[2])
		var player: CharacterBody3D = players.get(id)
		if player != null:
			player.set_pvp_health(int(row[3]), bool(row[4]))

func _on_start_pressed() -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_server_start_round()

func _server_start_round() -> void:
	if phase != Phase.LOBBY or player_order.size() < 2:
		return
	round_index += 1
	var new_seeker: int = player_order[round_index % player_order.size()]
	var ids: Array = []
	var positions: Array = []
	var hps: Array = []
	var hider_slot := 0
	for id in player_order:
		ids.append(id)
		if id == new_seeker:
			positions.append(SEEKER_SPAWN)
			hps.append(SEEKER_HP)
		else:
			positions.append(SPAWN_POINTS[hider_slot % SPAWN_POINTS.size()])
			hps.append(HIDER_HP)
			hider_slot += 1
	rpc("_client_round_setup", new_seeker, ids, positions, hps)
	_server_set_phase(Phase.HIDE, HIDE_SECONDS)
	_broadcast_scoreboard()

@rpc("authority", "call_local", "reliable")
func _client_round_setup(new_seeker_id: int, ids: Array, positions: Array, hps: Array) -> void:
	seeker_id = new_seeker_id
	for i in ids.size():
		var id := int(ids[i])
		var player: CharacterBody3D = players.get(id)
		if player == null:
			continue
		player.global_position = positions[i]
		player.pvp_target_position = positions[i]
		player.rotation.y = 0.0
		player.pvp_target_rotation = 0.0
		player.set_pvp_health(int(hps[i]), false)
		morphs.erase(id)
		var old: Node = player.get_node_or_null("MorphVisual")
		if old != null:
			old.queue_free()
		player.model.visible = true
		if id == seeker_id:
			player.set_pvp_color(SEEKER_COLOR)
			player.speed_mult = SEEKER_SPEED_MULT
		else:
			player.set_pvp_color(_base_color(id))
			player.speed_mult = 1.0
	if multiplayer.get_unique_id() == seeker_id:
		_set_local_frozen(true)
		seeker_overlay.visible = true
		message_label.text = "Tu es le CHERCHEUR !\nMassue (%s) sur un prop pour l'eliminer. Chaque coup manque : -1 PV." \
			% _key_name(int(control_keys[ACTION_ATTACK]))
	else:
		message_label.text = "Tu es un PROP ! Cache-toi vite.\n%s pres d'un objet : prendre son apparence. %s : sauter." % [
			_key_name(int(control_keys[ACTION_ATTACK])),
			_key_name(int(control_keys[ACTION_JUMP])),
		]

func _server_set_phase(new_phase: int, duration: float) -> void:
	phase_time_left = duration
	rpc("_client_phase_changed", new_phase)

@rpc("authority", "call_local", "reliable")
func _client_phase_changed(new_phase: int) -> void:
	phase = new_phase
	match phase:
		Phase.HUNT:
			seeker_overlay.visible = false
			if multiplayer.get_unique_id() == seeker_id:
				_set_local_frozen(false)
				message_label.text = "TROUVE-LES !\nUn des objets de la plaine n'est pas a sa place..."
			else:
				message_label.text = "Le chercheur arrive ! Reste immobile ou fuis au bon moment."
		Phase.LOBBY:
			seeker_overlay.visible = false
			_set_local_frozen(false)
			# plus de bonus de vitesse du chercheur en dehors d'une manche
			for id in players:
				var player: CharacterBody3D = players[id]
				if player != null:
					player.speed_mult = MORPH_SPEED_MULT if int(morphs.get(id, -1)) >= 0 else 1.0
			if multiplayer.multiplayer_peer != null and multiplayer.is_server():
				message_label.text = "Retour au lobby. Clique « Lancer la manche » quand tout le monde est la."
			else:
				message_label.text = "Retour au lobby. L'hote peut relancer une manche."

@rpc("authority", "unreliable")
func _client_phase_time(time_left: float) -> void:
	phase_time_left = time_left

func _check_round_end() -> void:
	if phase != Phase.HIDE and phase != Phase.HUNT:
		return
	var hiders_alive := 0
	for id in player_order:
		if id == seeker_id:
			continue
		var player: CharacterBody3D = players.get(id)
		if player != null and not player.dead:
			hiders_alive += 1
	if hiders_alive == 0:
		_server_end_round("Le CHERCHEUR a trouve tous les props !")

func _server_end_round(text: String) -> void:
	if phase != Phase.HIDE and phase != Phase.HUNT:
		return
	# on revele tout le monde
	for id in player_order:
		if int(morphs.get(id, -1)) >= 0:
			rpc("_client_set_morph", id, -1)
	rpc("_client_round_over", text)
	_server_set_phase(Phase.OVER, OVER_SECONDS)
	_broadcast_scoreboard()

@rpc("authority", "call_local", "reliable")
func _client_round_over(text: String) -> void:
	seeker_overlay.visible = false
	_set_local_frozen(false)
	message_label.text = text

func _server_back_to_lobby() -> void:
	for id in player_order:
		rpc("_client_player_health", id, 8, false)
	_server_set_phase(Phase.LOBBY, 0.0)

func _set_local_frozen(frozen: bool) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	var player: CharacterBody3D = players.get(multiplayer.get_unique_id())
	if player == null:
		return
	player.set_physics_process(not frozen)
	if frozen:
		player.velocity = Vector3.ZERO

func _update_camera(delta: float) -> void:
	var local_id := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0
	var player: CharacterBody3D = players.get(local_id)
	if player == null:
		return
	var target := player.position + CAMERA_OFFSET
	camera.position = camera.position.lerp(target, minf(1.0, 6.0 * delta))

func _update_hud() -> void:
	match phase:
		Phase.LOBBY:
			timer_label.text = "Lobby : %d joueur(s)" % player_order.size()
		Phase.HIDE:
			timer_label.text = "Cachette : %d s" % int(ceil(phase_time_left))
		Phase.HUNT:
			timer_label.text = "Chasse : %d s" % int(ceil(phase_time_left))
		Phase.OVER:
			timer_label.text = "Fin de manche"
	if seeker_overlay.visible:
		seeker_overlay_label.text = "Les PROPS se cachent...\n%d s" % int(ceil(phase_time_left))
	if start_button != null:
		start_button.visible = multiplayer.multiplayer_peer != null \
			and multiplayer.is_server() and phase == Phase.LOBBY
		start_button.disabled = player_order.size() < 2
		start_button.text = "Lancer la manche" if player_order.size() >= 2 \
			else "Lancer la manche (2 joueurs min.)"
	var lines: Array[String] = []
	for id in player_order:
		var player: CharacterBody3D = players.get(id)
		var hp_value := 0
		var dead_text := "KO"
		if player != null:
			hp_value = maxi(player.hp, 0)
			dead_text = "KO" if player.dead else "%d PV" % hp_value
		var role := ""
		if phase != Phase.LOBBY:
			role = "  [CHERCHEUR]" if id == seeker_id else "  [PROP]"
		var marker := " *" if multiplayer.multiplayer_peer != null and id == multiplayer.get_unique_id() else ""
		lines.append("%s%s%s  %s  K:%d" % [
			player_names.get(id, "Joueur"),
			marker,
			role,
			dead_text,
			int(kills.get(id, 0)),
		])
	board_label.text = "\n".join(lines)

func _clean_name(value: String, fallback: String) -> String:
	var text := value.strip_edges()
	if text == "":
		text = fallback
	return text.substr(0, 18)

func _clamp_to_arena(pos: Vector3) -> Vector3:
	return Vector3(clampf(pos.x, -9.6, 9.6), clampf(pos.y, 0.0, 4.0), clampf(pos.z, -9.6, 9.6))

func _base_color(peer_id: int) -> Color:
	var idx := player_order.find(peer_id)
	if idx < 0:
		idx = 0
	return PLAYER_COLORS[idx % PLAYER_COLORS.size()]

# --- Construction de la map ---
# La map est generee avec un RNG a graine fixe : tous les pairs construisent
# exactement la meme plaine sans rien echanger sur le reseau.

func _build_map() -> void:
	_build_floor()
	_add_walls()
	_add_house(HOUSE_POSITION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var occupied: Array = [
		{"pos": HOUSE_POSITION, "radius": 3.2},
		{"pos": SEEKER_SPAWN, "radius": 1.6},
	]
	for spawn in SPAWN_POINTS:
		occupied.append({"pos": spawn, "radius": 1.4})
	for type in Prop.size():
		for i in PROP_COUNTS[type]:
			var pos := _find_prop_spot(rng, occupied)
			if pos == Vector3.INF:
				continue
			_add_prop(type, pos, rng.randf_range(0.0, TAU))
			occupied.append({"pos": pos, "radius": 1.3})

func _find_prop_spot(rng: RandomNumberGenerator, occupied: Array) -> Vector3:
	for attempt in 80:
		var pos := Vector3(rng.randf_range(-8.8, 8.8), 0.0, rng.randf_range(-8.8, 8.8))
		var ok := true
		for entry in occupied:
			if (pos - entry["pos"]).length() < float(entry["radius"]):
				ok = false
				break
		if ok:
			return pos
	return Vector3.INF

func _add_prop(type: int, pos: Vector3, rot_y: float) -> void:
	var body := _make_obstacle(_prop_collision_shape(type), _prop_collision_offset(type))
	body.add_child(_make_prop_visual(type))
	body.position = pos
	body.rotation.y = rot_y
	floor_root.add_child(body)
	props.append({"type": type, "pos": pos})

func _prop_collision_shape(type: int) -> Shape3D:
	match type:
		Prop.TREE:
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.35
			cyl.height = 2.0
			return cyl
		Prop.BARREL:
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.34
			cyl.height = 0.85
			return cyl
		Prop.CRATE:
			var box := BoxShape3D.new()
			box.size = Vector3(0.72, 0.72, 0.72)
			return box
		Prop.HAY:
			var box := BoxShape3D.new()
			box.size = Vector3(1.0, 0.7, 0.7)
			return box
		Prop.STUMP:
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.3
			cyl.height = 0.5
			return cyl
		Prop.BUSH:
			var sphere := SphereShape3D.new()
			sphere.radius = 0.42
			return sphere
		_:
			var sphere := SphereShape3D.new()
			sphere.radius = 0.3
			return sphere

func _prop_collision_offset(type: int) -> Vector3:
	match type:
		Prop.TREE:
			return Vector3(0, 1.0, 0)
		Prop.BARREL:
			return Vector3(0, 0.43, 0)
		Prop.CRATE:
			return Vector3(0, 0.36, 0)
		Prop.HAY:
			return Vector3(0, 0.35, 0)
		Prop.STUMP:
			return Vector3(0, 0.25, 0)
		Prop.BUSH:
			return Vector3(0, 0.35, 0)
		_:
			return Vector3(0, 0.15, 0)

## Visuel d'un prop, partage entre la map et les joueurs deguises :
## un joueur transforme est strictement identique aux objets du decor.
func _make_prop_visual(type: int) -> Node3D:
	var root := Node3D.new()
	match type:
		Prop.TREE:
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.14
			trunk.bottom_radius = 0.18
			trunk.height = 0.9
			_add_mesh(root, trunk, Vector3(0, 0.45, 0), Color(0.45, 0.3, 0.17))
			var leaves := SphereMesh.new()
			leaves.radius = 0.75
			leaves.height = 1.5
			_add_mesh(root, leaves, Vector3(0, 1.45, 0), Color(0.2, 0.5, 0.22))
			var top := SphereMesh.new()
			top.radius = 0.5
			top.height = 1.0
			_add_mesh(root, top, Vector3(0, 2.05, 0), Color(0.25, 0.58, 0.26))
		Prop.ROCK:
			var rock := SphereMesh.new()
			rock.radius = 0.38
			rock.height = 0.76
			_add_mesh(root, rock, Vector3(0, 0.1, 0), Color(0.6, 0.6, 0.62), Vector3(1, 0.55, 0.85))
		Prop.BARREL:
			var barrel := CylinderMesh.new()
			barrel.top_radius = 0.32
			barrel.bottom_radius = 0.32
			barrel.height = 0.85
			_add_mesh(root, barrel, Vector3(0, 0.43, 0), Color(0.55, 0.36, 0.2))
			for ring_y in [0.18, 0.68]:
				var ring := CylinderMesh.new()
				ring.top_radius = 0.34
				ring.bottom_radius = 0.34
				ring.height = 0.07
				_add_mesh(root, ring, Vector3(0, ring_y, 0), Color(0.32, 0.22, 0.13))
		Prop.CRATE:
			var crate := BoxMesh.new()
			crate.size = Vector3(0.72, 0.72, 0.72)
			_add_mesh(root, crate, Vector3(0, 0.36, 0), Color(0.72, 0.55, 0.34))
			var band := BoxMesh.new()
			band.size = Vector3(0.76, 0.14, 0.76)
			_add_mesh(root, band, Vector3(0, 0.36, 0), Color(0.5, 0.36, 0.2))
		Prop.HAY:
			var hay := CylinderMesh.new()
			hay.top_radius = 0.35
			hay.bottom_radius = 0.35
			hay.height = 1.0
			var mi := _add_mesh(root, hay, Vector3(0, 0.35, 0), Color(0.87, 0.73, 0.32))
			mi.rotation.z = PI / 2.0
			var core := CylinderMesh.new()
			core.top_radius = 0.36
			core.bottom_radius = 0.36
			core.height = 0.12
			var band := _add_mesh(root, core, Vector3(0, 0.35, 0), Color(0.7, 0.55, 0.22))
			band.rotation.z = PI / 2.0
		Prop.STUMP:
			var stump := CylinderMesh.new()
			stump.top_radius = 0.28
			stump.bottom_radius = 0.32
			stump.height = 0.5
			_add_mesh(root, stump, Vector3(0, 0.25, 0), Color(0.45, 0.3, 0.17))
			var top := CylinderMesh.new()
			top.top_radius = 0.24
			top.bottom_radius = 0.24
			top.height = 0.04
			_add_mesh(root, top, Vector3(0, 0.51, 0), Color(0.72, 0.55, 0.34))
		Prop.BUSH:
			var big := SphereMesh.new()
			big.radius = 0.42
			big.height = 0.84
			_add_mesh(root, big, Vector3(0, 0.3, 0), Color(0.22, 0.48, 0.2))
			var mid := SphereMesh.new()
			mid.radius = 0.3
			mid.height = 0.6
			_add_mesh(root, mid, Vector3(0.25, 0.38, 0.1), Color(0.27, 0.55, 0.24))
			var small := SphereMesh.new()
			small.radius = 0.26
			small.height = 0.52
			_add_mesh(root, small, Vector3(-0.22, 0.34, -0.08), Color(0.2, 0.45, 0.19))
		Prop.PUMPKIN:
			var pumpkin := SphereMesh.new()
			pumpkin.radius = 0.32
			pumpkin.height = 0.64
			_add_mesh(root, pumpkin, Vector3(0, 0.25, 0), Color(0.92, 0.5, 0.12), Vector3(1, 0.8, 1))
			var stem := CylinderMesh.new()
			stem.top_radius = 0.04
			stem.bottom_radius = 0.06
			stem.height = 0.16
			_add_mesh(root, stem, Vector3(0, 0.55, 0), Color(0.3, 0.5, 0.2))
	return root

func _build_floor() -> void:
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
	for i in 80:
		var tuft := CylinderMesh.new()
		tuft.top_radius = 0.0
		tuft.bottom_radius = 0.06
		tuft.height = 0.22
		var pos := Vector3(randf_range(-9.5, 9.5), 0.11, randf_range(-9.5, 9.5))
		_add_mesh(floor_root, tuft, pos, Color(0.3, 0.55, 0.25))
	var flower_colors: Array[Color] = [
		Color(1, 1, 1), Color(0.95, 0.85, 0.3), Color(0.9, 0.5, 0.6),
	]
	for i in 35:
		var flower := SphereMesh.new()
		flower.radius = 0.06
		flower.height = 0.12
		var pos := Vector3(randf_range(-9.5, 9.5), 0.08, randf_range(-9.5, 9.5))
		_add_mesh(floor_root, flower, pos, flower_colors[randi() % flower_colors.size()])

func _add_walls() -> void:
	var stone := Color(0.55, 0.53, 0.5)
	var sides := [
		[Vector3(0, 0.4, -10.2), Vector3(20.8, 0.8, 0.4)],
		[Vector3(0, 0.4, 10.2), Vector3(20.8, 0.8, 0.4)],
		[Vector3(-10.2, 0.4, 0), Vector3(0.4, 0.8, 20.8)],
		[Vector3(10.2, 0.4, 0), Vector3(0.4, 0.8, 20.8)],
	]
	for side in sides:
		var body := StaticBody3D.new()
		body.collision_layer = 4
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = side[1]
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		var mesh := BoxMesh.new()
		mesh.size = side[1]
		_add_mesh(body, mesh, Vector3.ZERO, stone)
		body.position = side[0]
		floor_root.add_child(body)

func _make_obstacle(shape: Shape3D, shape_offset: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = shape_offset
	body.add_child(col)
	return body

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

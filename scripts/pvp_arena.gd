extends Node3D
## MVP PvP LAN : un joueur heberge, jusqu'a 3 autres rejoignent par IP locale.
## L'hote reste autoritaire pour les degats, les morts et la fin de manche.

const BirdmanScene := preload("res://scenes/birdman.tscn")
const PvpBeakScene := preload("res://scenes/pvp_beak_projectile.tscn")
const PvpPickupScene := preload("res://scenes/pvp_pickup.tscn")
const SETTINGS_PATH := "user://settings.cfg"
const PORT := 42424
const MAX_PLAYERS := 4
const MATCH_SECONDS := 120.0
const STATE_SEND_INTERVAL := 0.05
const PVP_BEAK_COOLDOWN := 0.7
const RESPAWN_SECONDS := 3.0
const PICKUP_SPAWN_INTERVAL := 7.0
const MAX_PICKUPS := 5
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
const ACTION_TOGGLE_VIEW := "arena_toggle_view"
const CONTROL_BINDINGS := [
	{"action": ACTION_MOVE_UP, "label": "Avancer", "default": KEY_Z},
	{"action": ACTION_MOVE_DOWN, "label": "Reculer", "default": KEY_S},
	{"action": ACTION_MOVE_LEFT, "label": "Gauche", "default": KEY_Q},
	{"action": ACTION_MOVE_RIGHT, "label": "Droite", "default": KEY_D},
	{"action": ACTION_ATTACK, "label": "Massue", "default": KEY_E},
	{"action": ACTION_THROW_BEAK, "label": "Lancer le bec", "default": KEY_F},
	{"action": ACTION_JUMP, "label": "Sauter", "default": KEY_SPACE},
	{"action": ACTION_TOGGLE_VIEW, "label": "Vue", "default": KEY_V},
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
const PLAYER_COLORS: Array[Color] = [
	Color(0.97, 0.82, 0.27),
	Color(0.25, 0.55, 1.0),
	Color(0.95, 0.25, 0.28),
	Color(0.35, 0.85, 0.35),
]
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
const FIRST_PERSON_HEIGHT := 1.28
const FIRST_PERSON_FORWARD := 0.45
const PICKUP_POSITIONS: Array[Vector3] = [
	Vector3(0.0, 0.45, 0.0),
	Vector3(2.7, 0.45, 2.5),
	Vector3(-2.7, 0.45, -1.2),
	Vector3(6.0, 0.45, -1.8),
	Vector3(-6.3, 0.45, 2.2),
	Vector3(1.2, 0.45, -5.8),
	Vector3(-1.8, 0.45, 6.2),
	Vector3(7.5, 0.45, 6.8),
	Vector3(-7.4, 0.45, -7.2),
	Vector3(4.2, 0.45, 5.8),
]

var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}
var player_names: Dictionary = {}
var player_order: Array[int] = []
var kills: Dictionary = {}
var deaths: Dictionary = {}
var streaks: Dictionary = {}
var respawn_due_at: Dictionary = {}
var projectiles: Dictionary = {}
var pickups: Dictionary = {}
var beak_ready_at: Dictionary = {}
var next_projectile_id := 1
var next_pickup_id := 1
var match_running := false
var match_over := false
var match_time_left := MATCH_SECONDS
var state_send_timer := 0.0
var pickup_spawn_timer := 2.0
var first_person_view := false

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
	if event.is_action_pressed(ACTION_TOGGLE_VIEW):
		_toggle_first_person()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_PAUSE):
		_show_controls_panel(false)
		get_viewport().set_input_as_handled()
	elif match_over and event.is_action_pressed("ui_accept"):
		if multiplayer.is_server():
			_restart_match()
		else:
			message_label.text = "En attente de l'hote pour relancer."
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if match_running and multiplayer.is_server():
		match_time_left = maxf(match_time_left - delta, 0.0)
		_update_server_respawns()
		_update_server_pickups(delta)
		_broadcast_match_state()
		if match_time_left <= 0.0:
			_end_match()
	_update_camera(delta)
	_update_hud()

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not match_running or match_over:
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

	timer_label = _make_label(Vector2(20, 18), Vector2(260, 42), 30, HORIZONTAL_ALIGNMENT_LEFT)
	ui_layer.add_child(timer_label)

	board_label = _make_label(Vector2(-360, 18), Vector2(340, 180), 20, HORIZONTAL_ALIGNMENT_RIGHT)
	board_label.anchor_left = 1.0
	board_label.anchor_right = 1.0
	ui_layer.add_child(board_label)

	message_label = _make_label(Vector2(0, -160), Vector2(0, 130), 30, HORIZONTAL_ALIGNMENT_CENTER)
	message_label.anchor_top = 1.0
	message_label.anchor_right = 1.0
	message_label.anchor_bottom = 1.0
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui_layer.add_child(message_label)

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
	title.text = "PvP LAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nom du joueur"
	name_edit.text = "Joueur"
	root.add_child(name_edit)

	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP de l'hote"
	ip_edit.text = ""
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
	status_label.text = "Meme reseau : l'hote clique Heberger, les autres entrent son IP locale.\n%s" % _local_network_hint()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_label)

	_build_controls_panel()

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
	pending_rebind_action = ""
	controls_status.text = "Touches par defaut restaurees."
	_update_control_buttons()

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
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		status_label.text = "Impossible d'heberger sur le port %d." % PORT
		return
	multiplayer.multiplayer_peer = peer
	_reset_match_data()
	var host_id := multiplayer.get_unique_id()
	player_names[host_id] = _clean_name(name_edit.text, "Hote")
	player_order.append(host_id)
	kills[host_id] = 0
	deaths[host_id] = 0
	streaks[host_id] = 0
	beak_ready_at[host_id] = 0.0
	_client_spawn_player(host_id, player_names[host_id], SPAWN_POINTS[0], 8, false)
	menu_panel.visible = false
	_start_match()
	message_label.text = "Partie hebergee. Donne a ton pote : %s" % _local_network_hint()

func _join_game() -> void:
	var host_ip := ip_edit.text.strip_edges()
	if host_ip == "":
		status_label.text = "Entre l'IPv4 LAN de l'hote. Exemple : 192.168.1.23."
		return
	if host_ip == "127.0.0.1" or host_ip.to_lower() == "localhost":
		status_label.text = "127.0.0.1 ne marche que sur le meme PC. Entre l'IPv4 LAN de l'hote."
		return
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(host_ip, PORT)
	if err != OK:
		status_label.text = "Connexion impossible vers %s:%d." % [host_ip, PORT]
		return
	multiplayer.multiplayer_peer = peer
	host_button.disabled = true
	join_button.disabled = true
	status_label.text = "Connexion a %s:%d..." % [host_ip, PORT]

func _reset_match_data() -> void:
	for player in players.values():
		if is_instance_valid(player):
			player.queue_free()
	players.clear()
	player_names.clear()
	player_order.clear()
	kills.clear()
	deaths.clear()
	streaks.clear()
	respawn_due_at.clear()
	projectiles.clear()
	pickups.clear()
	beak_ready_at.clear()
	next_projectile_id = 1
	next_pickup_id = 1
	match_time_left = MATCH_SECONDS
	pickup_spawn_timer = 2.0
	match_running = false
	match_over = false

func _start_match() -> void:
	match_running = true
	match_over = false
	match_time_left = MATCH_SECONDS
	pickup_spawn_timer = 1.0
	respawn_due_at.clear()
	for id in player_order:
		kills[id] = 0
		deaths[id] = 0
		streaks[id] = 0
		beak_ready_at[id] = 0.0
		var spawn_pos := SPAWN_POINTS[player_order.find(id) % SPAWN_POINTS.size()]
		rpc("_client_respawn_player", id, spawn_pos, 8)
	for pickup_id in pickups.keys():
		rpc("_client_despawn_pvp_pickup", int(pickup_id))
	pickups.clear()
	message_label.text = "Deathmatch lance !"
	rpc("_client_match_state", match_running, match_time_left, match_over)
	rpc("_client_match_message", message_label.text)
	_broadcast_scoreboard()

func _restart_match() -> void:
	if not multiplayer.is_server():
		return
	for projectile_id in projectiles.keys():
		rpc("_client_despawn_pvp_beak", int(projectile_id))
	projectiles.clear()
	_start_match()

func _on_connected_to_server() -> void:
	menu_panel.visible = false
	message_label.text = "Connexion OK"
	rpc_id(1, "_server_register_player", _clean_name(name_edit.text, "Joueur"))

func _on_connection_failed() -> void:
	host_button.disabled = false
	join_button.disabled = false
	status_label.text = "Connexion echouee. Verifie l'IP, le meme reseau, et le pare-feu Windows de l'hote sur UDP %d." % PORT
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func _on_server_disconnected() -> void:
	message_label.text = "Hote deconnecte."
	match_running = false
	match_over = true
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func _on_peer_connected(_id: int) -> void:
	pass

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		_server_remove_player(id)
		rpc("_client_remove_player", id)
		_check_last_player()

@rpc("any_peer", "reliable")
func _server_register_player(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if player_order.size() >= MAX_PLAYERS:
		rpc_id(id, "_client_rejected", "Partie pleine.")
		return
	player_names[id] = _clean_name(display_name, "Joueur %d" % id)
	player_order.append(id)
	kills[id] = 0
	deaths[id] = 0
	streaks[id] = 0
	beak_ready_at[id] = 0.0
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
	for pickup_id in pickups.keys():
		var pickup: Area3D = pickups[pickup_id]
		if is_instance_valid(pickup):
			rpc_id(id, "_client_spawn_pvp_pickup", int(pickup_id), pickup.type, pickup.global_position)
	rpc_id(id, "_client_match_state", match_running, match_time_left, match_over)
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

@rpc("authority", "call_local", "reliable")
func _client_spawn_player(peer_id: int, display_name: String, spawn_pos: Vector3, hp_value: int, is_dead: bool) -> void:
	player_names[peer_id] = display_name
	if not player_order.has(peer_id):
		player_order.append(peer_id)
	if not kills.has(peer_id):
		kills[peer_id] = 0
	if not deaths.has(peer_id):
		deaths[peer_id] = 0
	if not streaks.has(peer_id):
		streaks[peer_id] = 0
	if players.has(peer_id):
		var existing: CharacterBody3D = players[peer_id]
		existing.set_pvp_remote_state(spawn_pos, existing.rotation.y, hp_value, is_dead)
		if peer_id == multiplayer.get_unique_id():
			_update_local_player_visibility()
		return
	var player: CharacterBody3D = BirdmanScene.instantiate()
	player.name = "Player_%d" % peer_id
	player.position = spawn_pos
	player.pvp_enabled = true
	player.pvp_peer_id = peer_id
	player.pvp_arena = self
	player.sfx = sfx
	player.set_multiplayer_authority(peer_id)
	player.add_to_group("pvp_players")
	units.add_child(player)
	player.set_pvp_color(PLAYER_COLORS[player_order.find(peer_id) % PLAYER_COLORS.size()])
	player.set_pvp_health(hp_value, is_dead)
	player.hp_changed.connect(func(_hp: int) -> void: _update_hud())
	player.died.connect(func() -> void:
		if multiplayer.is_server():
			_check_last_player()
	)
	players[peer_id] = player
	if peer_id == multiplayer.get_unique_id():
		_update_local_player_visibility()

@rpc("authority", "call_local", "reliable")
func _client_remove_player(peer_id: int) -> void:
	if players.has(peer_id):
		var player: Node = players[peer_id]
		if is_instance_valid(player):
			player.queue_free()
		players.erase(peer_id)
	player_names.erase(peer_id)
	kills.erase(peer_id)
	deaths.erase(peer_id)
	streaks.erase(peer_id)
	respawn_due_at.erase(peer_id)
	beak_ready_at.erase(peer_id)
	player_order.erase(peer_id)

func _server_remove_player(peer_id: int) -> void:
	if players.has(peer_id):
		var player: Node = players[peer_id]
		if is_instance_valid(player):
			player.queue_free()
		players.erase(peer_id)
	player_names.erase(peer_id)
	kills.erase(peer_id)
	deaths.erase(peer_id)
	streaks.erase(peer_id)
	respawn_due_at.erase(peer_id)
	beak_ready_at.erase(peer_id)
	player_order.erase(peer_id)

@rpc("authority", "call_local", "reliable")
func _client_respawn_player(peer_id: int, spawn_pos: Vector3, hp_value: int) -> void:
	var player: CharacterBody3D = players.get(peer_id)
	if player == null:
		return
	player.pvp_respawn(spawn_pos, hp_value)
	if peer_id == multiplayer.get_unique_id():
		_update_local_player_visibility()

func _update_server_respawns() -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	for id in respawn_due_at.keys():
		if now >= float(respawn_due_at[id]):
			respawn_due_at.erase(id)
			if players.has(id):
				var spawn_pos := _best_respawn_position(int(id))
				rpc("_client_respawn_player", int(id), spawn_pos, 8)
				rpc("_client_match_message", "%s revient dans l'arene" % player_names.get(id, "Joueur"))
				_broadcast_scoreboard()

func _best_respawn_position(peer_id: int) -> Vector3:
	var best_pos := SPAWN_POINTS[0]
	var best_dist := -1.0
	for pos in SPAWN_POINTS:
		var nearest := 999.0
		for other_id in player_order:
			if int(other_id) == peer_id:
				continue
			var other: CharacterBody3D = players.get(other_id)
			if other != null and not other.dead:
				nearest = minf(nearest, (other.global_position - pos).length())
		if nearest > best_dist:
			best_dist = nearest
			best_pos = pos
	return best_pos

@rpc("any_peer", "unreliable")
func _server_player_state(pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server() or match_over:
		return
	var id := multiplayer.get_remote_sender_id()
	var player: CharacterBody3D = players.get(id)
	if player == null or player.dead:
		return
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

func request_pvp_strike(attacker_id: int) -> void:
	if not match_running or match_over:
		return
	if multiplayer.is_server():
		_server_apply_strike(attacker_id)
		rpc("_client_play_attack", attacker_id)
	else:
		rpc_id(1, "_server_request_strike")

func request_pvp_beak(owner_id: int, _start_pos: Vector3, _direction: Vector3, _rot_y: float, _damage: int) -> void:
	if not match_running or match_over:
		return
	if multiplayer.is_server():
		_server_spawn_pvp_beak(owner_id, _start_pos, _direction, _rot_y)
	else:
		rpc_id(1, "_server_request_pvp_beak", _start_pos, _direction, _rot_y)

@rpc("any_peer", "reliable")
func _server_request_pvp_beak(start_pos: Vector3, direction: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server() or not match_running or match_over:
		return
	_server_spawn_pvp_beak(multiplayer.get_remote_sender_id(), start_pos, direction, rot_y)

func _server_spawn_pvp_beak(owner_id: int, start_pos := Vector3.INF, direction := Vector3.ZERO, rot_y := INF) -> void:
	var player: CharacterBody3D = players.get(owner_id)
	if player == null or player.dead:
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now < float(beak_ready_at.get(owner_id, 0.0)):
		return
	beak_ready_at[owner_id] = now + ((0.35 if player.triple_timer > 0.0 else PVP_BEAK_COOLDOWN) * player.beak_cd_mult)
	var base_angle := player.rotation.y
	if rot_y != INF:
		base_angle = rot_y
		player.pvp_target_rotation = rot_y
	var base_dir := Vector3(sin(base_angle), 0.0, cos(base_angle)).normalized()
	if direction.length() > 0.01:
		base_dir = Vector3(direction.x, 0.0, direction.z).normalized()
		base_angle = atan2(base_dir.x, base_dir.z)
	var base_spawn := player.global_position + base_dir * 0.65 + Vector3(0, 0.82, 0)
	if start_pos != Vector3.INF:
		var clamped_start := _clamp_to_arena(start_pos)
		clamped_start.y = clampf(start_pos.y, 0.4, 2.6)
		base_spawn = clamped_start
	var angles: Array[float] = [0.0]
	if player.triple_timer > 0.0:
		angles = [-0.3, 0.0, 0.3]
	for angle_offset in angles:
		var projectile_id := next_projectile_id
		next_projectile_id += 1
		var angle := base_angle + angle_offset
		var dir := Vector3(sin(angle), 0.0, cos(angle)).normalized()
		var spawn_pos := base_spawn
		if angle_offset != 0.0:
			spawn_pos += dir * 0.18
		rpc("_client_spawn_pvp_beak", projectile_id, owner_id, spawn_pos, dir, angle, player.beak_damage)

@rpc("authority", "call_local", "reliable")
func _client_spawn_pvp_beak(projectile_id: int, owner_id: int, spawn_pos: Vector3, dir: Vector3, rot_y: float, damage: int) -> void:
	var projectile: Area3D = PvpBeakScene.instantiate()
	projectile.name = "PvpBeak_%d" % projectile_id
	projectile.projectile_id = projectile_id
	projectile.owner_id = owner_id
	projectile.direction = dir.normalized()
	projectile.damage = damage
	projectile.pvp_arena = self
	projectile.global_position = spawn_pos
	projectile.rotation.y = rot_y
	units.add_child(projectile)
	projectiles[projectile_id] = projectile

func server_pvp_beak_hit(projectile_id: int, owner_id: int, victim_id: int, damage: int) -> void:
	if not multiplayer.is_server() or not projectiles.has(projectile_id):
		return
	var owner: CharacterBody3D = players.get(owner_id)
	var victim: CharacterBody3D = players.get(victim_id)
	if owner == null or victim == null or owner.dead or victim.dead:
		server_pvp_beak_expired(projectile_id)
		return
	_apply_pvp_damage(owner_id, victim_id, damage)
	if sfx:
		sfx.play_hit()
	server_pvp_beak_expired(projectile_id)

func server_pvp_beak_expired(projectile_id: int) -> void:
	if not multiplayer.is_server():
		return
	rpc("_client_despawn_pvp_beak", projectile_id)

@rpc("authority", "call_local", "reliable")
func _client_despawn_pvp_beak(projectile_id: int) -> void:
	var projectile: Node = projectiles.get(projectile_id)
	if projectile != null and is_instance_valid(projectile):
		projectile.queue_free()
	projectiles.erase(projectile_id)

func _update_server_pickups(delta: float) -> void:
	pickup_spawn_timer -= delta
	if pickup_spawn_timer > 0.0:
		return
	pickup_spawn_timer = PICKUP_SPAWN_INTERVAL
	if pickups.size() < MAX_PICKUPS:
		_server_spawn_pvp_pickup()

func _server_spawn_pvp_pickup() -> void:
	var pickup_id := next_pickup_id
	next_pickup_id += 1
	var type := _random_pvp_pickup_type()
	var pos := PICKUP_POSITIONS[randi() % PICKUP_POSITIONS.size()]
	rpc("_client_spawn_pvp_pickup", pickup_id, type, pos)

func _random_pvp_pickup_type() -> int:
	var roll := randf()
	if roll < 0.26:
		return 0
	if roll < 0.46:
		return 1
	if roll < 0.66:
		return 2
	if roll < 0.84:
		return 3
	return 4

@rpc("authority", "call_local", "reliable")
func _client_spawn_pvp_pickup(pickup_id: int, type: int, pos: Vector3) -> void:
	if pickups.has(pickup_id):
		return
	var pickup: Area3D = PvpPickupScene.instantiate()
	pickup.name = "PvpPickup_%d" % pickup_id
	pickup.pickup_id = pickup_id
	pickup.type = type
	pickup.pvp_arena = self
	pickup.global_position = pos
	units.add_child(pickup)
	pickups[pickup_id] = pickup

func server_pvp_pickup_collected(pickup_id: int, peer_id: int, type: int) -> void:
	if not multiplayer.is_server() or not pickups.has(pickup_id):
		return
	server_pvp_pickup_expired(pickup_id)
	rpc("_client_apply_pvp_pickup", peer_id, type)
	var text := "%s ramasse %s" % [player_names.get(peer_id, "Joueur"), _pickup_name(type)]
	rpc("_client_match_message", text)
	_broadcast_scoreboard()

func server_pvp_pickup_expired(pickup_id: int) -> void:
	if not multiplayer.is_server():
		return
	rpc("_client_despawn_pvp_pickup", pickup_id)

@rpc("authority", "call_local", "reliable")
func _client_despawn_pvp_pickup(pickup_id: int) -> void:
	var pickup: Node = pickups.get(pickup_id)
	if pickup != null and is_instance_valid(pickup):
		pickup.queue_free()
	pickups.erase(pickup_id)

@rpc("authority", "call_local", "reliable")
func _client_apply_pvp_pickup(peer_id: int, type: int) -> void:
	var player: CharacterBody3D = players.get(peer_id)
	if player == null or player.dead:
		return
	player.apply_pickup(type)
	if multiplayer.is_server():
		rpc("_client_player_health", peer_id, player.hp, player.dead)

func _pickup_name(type: int) -> String:
	match type:
		0:
			return "un coeur"
		1:
			return "la baguette"
		2:
			return "le bec d'or"
		3:
			return "le cafe"
		4:
			return "le champignon"
	return "un bonus"

@rpc("any_peer", "reliable")
func _server_request_strike() -> void:
	if not multiplayer.is_server() or not match_running or match_over:
		return
	var attacker_id := multiplayer.get_remote_sender_id()
	_server_apply_strike(attacker_id)
	rpc("_client_play_attack", attacker_id)

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
	var attacker_pos := _server_player_position(attacker_id)
	var attacker_rot := _server_player_rotation(attacker_id)
	var fwd := Vector3(sin(attacker_rot), 0.0, cos(attacker_rot))
	var hit_any := false
	for victim_id in player_order:
		if victim_id == attacker_id:
			continue
		var victim: CharacterBody3D = players.get(victim_id)
		if victim == null or victim.dead:
			continue
		var victim_pos := _server_player_position(int(victim_id))
		if victim_pos.y > 0.6:
			continue
		var to: Vector3 = victim_pos - attacker_pos
		to.y = 0.0
		var dist := to.length()
		if dist <= attacker._melee_range() and (dist <= 0.01 or fwd.angle_to(to.normalized()) <= attacker.ATTACK_ARC):
			_apply_pvp_damage(attacker_id, int(victim_id), attacker._melee_damage())
			hit_any = true
	if hit_any and sfx:
		sfx.play_hit()

func _server_player_position(peer_id: int) -> Vector3:
	var player: CharacterBody3D = players.get(peer_id)
	if player == null:
		return Vector3.ZERO
	if multiplayer.is_server() and peer_id != multiplayer.get_unique_id():
		return player.pvp_target_position
	return player.global_position

func _server_player_rotation(peer_id: int) -> float:
	var player: CharacterBody3D = players.get(peer_id)
	if player == null:
		return 0.0
	if multiplayer.is_server() and peer_id != multiplayer.get_unique_id():
		return player.pvp_target_rotation
	return player.rotation.y

func _apply_pvp_damage(attacker_id: int, victim_id: int, damage: int) -> void:
	var attacker: CharacterBody3D = players.get(attacker_id)
	var victim: CharacterBody3D = players.get(victim_id)
	if attacker == null or victim == null or victim.dead:
		return
	var was_alive: bool = not victim.dead
	var victim_pos := _server_player_position(victim_id)
	var knock := victim_pos - _server_player_position(attacker_id)
	knock.y = 0.0
	if knock.length() > 0.01:
		var knocked_pos := _clamp_to_arena(victim_pos + knock.normalized() * 0.55)
		victim.global_position = knocked_pos
		victim.pvp_target_position = knocked_pos
	victim.take_damage(damage)
	rpc("_client_player_health", victim_id, victim.hp, victim.dead)
	if was_alive and victim.dead:
		kills[attacker_id] = int(kills.get(attacker_id, 0)) + 1
		streaks[attacker_id] = int(streaks.get(attacker_id, 0)) + 1
		deaths[victim_id] = int(deaths.get(victim_id, 0)) + 1
		streaks[victim_id] = 0
		respawn_due_at[victim_id] = float(Time.get_ticks_msec()) / 1000.0 + RESPAWN_SECONDS
		var text := "%s elimine %s" % [
			player_names.get(attacker_id, "Joueur"),
			player_names.get(victim_id, "Joueur"),
		]
		if int(streaks.get(attacker_id, 0)) >= 3:
			text += "  Serie x%d !" % int(streaks[attacker_id])
		rpc("_client_match_message", text)
		_broadcast_scoreboard()

@rpc("authority", "call_local", "reliable")
func _client_player_health(peer_id: int, hp_value: int, is_dead: bool) -> void:
	var player: CharacterBody3D = players.get(peer_id)
	if player != null:
		player.set_pvp_health(hp_value, is_dead)

func _broadcast_match_state() -> void:
	rpc("_client_match_state", match_running, match_time_left, match_over)

@rpc("authority", "call_local", "unreliable")
func _client_match_state(is_running: bool, time_left: float, is_over: bool) -> void:
	match_running = is_running
	match_time_left = time_left
	match_over = is_over

func _broadcast_scoreboard() -> void:
	var data: Array = []
	for id in player_order:
		var player: CharacterBody3D = players.get(id)
		var hp_value := 0
		var is_dead := true
		if player != null:
			hp_value = player.hp
			is_dead = player.dead
		var respawn_left := 0.0
		if respawn_due_at.has(id):
			respawn_left = maxf(0.0, float(respawn_due_at[id]) - float(Time.get_ticks_msec()) / 1000.0)
		data.append([
			id,
			player_names.get(id, "Joueur"),
			int(kills.get(id, 0)),
			int(deaths.get(id, 0)),
			int(streaks.get(id, 0)),
			hp_value,
			is_dead,
			respawn_left,
		])
	rpc("_client_scoreboard", data)

@rpc("authority", "call_local", "reliable")
func _client_scoreboard(data: Array) -> void:
	for row in data:
		var id := int(row[0])
		player_names[id] = str(row[1])
		kills[id] = int(row[2])
		deaths[id] = int(row[3])
		streaks[id] = int(row[4])
		var respawn_left := float(row[7])
		if respawn_left > 0.0:
			respawn_due_at[id] = float(Time.get_ticks_msec()) / 1000.0 + respawn_left
		else:
			respawn_due_at.erase(id)
		var player: CharacterBody3D = players.get(id)
		if player != null:
			player.set_pvp_health(int(row[5]), bool(row[6]))

func _check_last_player() -> void:
	pass

func _end_match() -> void:
	if match_over:
		return
	match_running = false
	match_over = true
	var winner_id := _winner_id()
	var winner_name: String = str(player_names.get(winner_id, "Personne"))
	var text := "Victoire : %s  (%d K / %d D)" % [
		winner_name,
		int(kills.get(winner_id, 0)),
		int(deaths.get(winner_id, 0)),
	]
	rpc("_client_match_over", text, winner_id)

@rpc("authority", "call_local", "reliable")
func _client_match_over(text: String, _winner_id: int) -> void:
	match_running = false
	match_over = true
	message_label.text = "%s\nHote : Entree pour relancer" % text

@rpc("authority", "call_local", "reliable")
func _client_match_message(text: String) -> void:
	if match_over:
		return
	message_label.text = text
	get_tree().create_timer(2.0, false).timeout.connect(func() -> void:
		if not match_over and message_label.text == text:
			message_label.text = ""
	)

func _winner_id() -> int:
	var best_id := -1
	var best_kills := -1
	var best_deaths := 999
	for id in player_order:
		var kill_score := int(kills.get(id, 0))
		var death_score := int(deaths.get(id, 0))
		if kill_score > best_kills or (kill_score == best_kills and death_score < best_deaths):
			best_id = id
			best_kills = kill_score
			best_deaths = death_score
	return best_id

func _update_camera(delta: float) -> void:
	var local_id := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0
	var player: CharacterBody3D = players.get(local_id)
	if player == null:
		return
	if first_person_view:
		var forward := Vector3(sin(player.rotation.y), 0.0, cos(player.rotation.y))
		camera.global_position = player.global_position + Vector3(0, FIRST_PERSON_HEIGHT, 0) + forward * FIRST_PERSON_FORWARD
		camera.rotation = Vector3(0.0, player.rotation.y + PI, 0.0)
		camera.fov = 75.0
	else:
		var target := player.position + CAMERA_OFFSET
		camera.position = camera.position.lerp(target, minf(1.0, 6.0 * delta))
		camera.rotation = Vector3(-0.94, 0.0, 0.0)
		camera.fov = 55.0

func _toggle_first_person() -> void:
	first_person_view = not first_person_view
	_update_local_player_visibility()
	_update_camera(1.0)

func _update_local_player_visibility() -> void:
	var local_id := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0
	var player: CharacterBody3D = players.get(local_id)
	if player != null:
		player.model.visible = not first_person_view

func _update_hud() -> void:
	timer_label.text = "Temps : %03d" % int(ceil(match_time_left))
	var lines: Array[String] = []
	for id in player_order:
		var player: CharacterBody3D = players.get(id)
		var hp_value := 0
		var dead_text := "KO"
		if player != null:
			hp_value = maxi(player.hp, 0)
			if player.dead:
				dead_text = "KO"
				if multiplayer.is_server() and respawn_due_at.has(id):
					var left := maxi(0, int(ceil(float(respawn_due_at[id]) - float(Time.get_ticks_msec()) / 1000.0)))
					dead_text = "Retour %ds" % left
			else:
				dead_text = "%d PV" % hp_value
		var marker := " *" if id == multiplayer.get_unique_id() and multiplayer.multiplayer_peer != null else ""
		lines.append("%s%s  %s  K:%d D:%d S:%d" % [
			player_names.get(id, "Joueur"),
			marker,
			dead_text,
			int(kills.get(id, 0)),
			int(deaths.get(id, 0)),
			int(streaks.get(id, 0)),
		])
	board_label.text = "\n".join(lines)

func _clean_name(value: String, fallback: String) -> String:
	var text := value.strip_edges()
	if text == "":
		text = fallback
	return text.substr(0, 18)

func _clamp_to_arena(pos: Vector3) -> Vector3:
	return Vector3(clampf(pos.x, -9.6, 9.6), clampf(pos.y, 0.0, 4.0), clampf(pos.z, -9.6, 9.6))

func _build_map() -> void:
	_build_floor()
	_add_walls()
	for pos in TREE_POSITIONS:
		_add_tree(pos)
	for pos in ROCK_POSITIONS:
		_add_rock(pos)
	_add_house(HOUSE_POSITION)

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

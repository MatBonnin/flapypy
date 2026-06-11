extends Node3D
## Mode labyrinthe solo : exploration FPS, plumes a recuperer et sortie.

const SETTINGS_PATH := "user://settings.cfg"
const ACTION_MOVE_UP := "arena_move_up"
const ACTION_MOVE_DOWN := "arena_move_down"
const ACTION_MOVE_LEFT := "arena_move_left"
const ACTION_MOVE_RIGHT := "arena_move_right"
const ACTION_INTERACT := "arena_attack"
const ACTION_JUMP := "arena_jump"
const ACTION_PAUSE := "arena_pause"
const CONTROL_BINDINGS := [
	{"action": ACTION_MOVE_UP, "default": KEY_Z},
	{"action": ACTION_MOVE_DOWN, "default": KEY_S},
	{"action": ACTION_MOVE_LEFT, "default": KEY_Q},
	{"action": ACTION_MOVE_RIGHT, "default": KEY_D},
	{"action": ACTION_INTERACT, "default": KEY_E},
	{"action": ACTION_JUMP, "default": KEY_SPACE},
	{"action": ACTION_PAUSE, "default": KEY_ESCAPE},
]
const EXTRA_BINDINGS := {
	ACTION_MOVE_UP: [KEY_UP],
	ACTION_MOVE_DOWN: [KEY_DOWN],
	ACTION_MOVE_LEFT: [KEY_LEFT],
	ACTION_MOVE_RIGHT: [KEY_RIGHT],
}

const GRID_W := 17
const GRID_H := 17
const CELL_SIZE := 3.0
const WALL_HEIGHT := 2.65
const WALL_THICKNESS := 0.24
const PLAYER_EYE_HEIGHT := 1.32
const PLAYER_FORWARD := 0.22
const REQUIRED_FEATHERS := 3
const SLOW_SECONDS := 2.3
const SLOW_MULT := 0.55

const N := 1
const E := 2
const S := 4
const W := 8
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const BITS: Array[int] = [N, E, S, W]
const OPPOSITE: Array[int] = [S, W, N, E]

var maze_seed := 0
var rng := RandomNumberGenerator.new()
var walls: Array = []
var distances: Array = []
var parents: Array = []
var start_cell := 0
var exit_cell := 0
var feather_cells: Array = []
var key_cells: Array = []
var door_edges: Array = []
var shortcut_edges := {}
var doors := {}
var shortcuts := {}
var collected_feathers := 0
var keys := 0
var run_time := 0.0
var slow_timer := 0.0
var won := false
var nearby_interactable: Area3D = null
var fp_sens := 1.0

var hud_label: Label
var message_label: Label
var prompt_label: Label
var pause_overlay: Control
var end_panel: Control

@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $Camera3D
@onready var floor_root: Node3D = $Floor
@onready var dynamic_root: Node3D = $Dynamic
@onready var ui: CanvasLayer = $UI
@onready var sfx: Node = $Sfx

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_controls()
	_configure_player()
	_generate_maze()
	_build_world()
	_build_ui()
	_update_camera()
	_show_message("Trouve les 3 plumes dorees, puis la sortie.")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if not won:
		run_time += delta
	if slow_timer > 0.0:
		slow_timer = maxf(slow_timer - delta, 0.0)
		if slow_timer <= 0.0:
			player.speed_mult = 1.0
	_update_camera()
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_PAUSE):
		if won:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
		else:
			_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused or won:
		return
	if event.is_action_pressed(ACTION_INTERACT):
		_try_interact()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _load_controls() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SETTINGS_PATH) == OK
	for binding in CONTROL_BINDINGS:
		var action: String = binding["action"]
		var keycode := int(binding["default"])
		if loaded:
			keycode = int(cfg.get_value("controls", action, keycode))
		_apply_action_key(action, keycode)

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

func _configure_player() -> void:
	player.sfx = sfx
	player.first_person = true
	player.fp_sens_mult = fp_sens
	player.combat_enabled = false
	player.movement_half = 0.0
	player.global_position = _cell_to_world(start_cell)
	player.rotation.y = 0.0
	player.model.visible = false

func _generate_maze(seed_value := 0) -> void:
	if seed_value != 0:
		maze_seed = seed_value
	else:
		rng.randomize()
		maze_seed = rng.randi()
	rng.seed = maze_seed
	walls.clear()
	for i in GRID_W * GRID_H:
		walls.append(N | E | S | W)
	_build_maze_paths()
	_add_extra_loops()
	_pick_layout_points()

func _build_maze_paths() -> void:
	var visited: Array[bool] = []
	for i in GRID_W * GRID_H:
		visited.append(false)
	var stack: Array[int] = [start_cell]
	visited[start_cell] = true
	while not stack.is_empty():
		var current: int = stack[stack.size() - 1]
		var dirs: Array[int] = []
		for dir_i in 4:
			var next := _neighbor_index(current, dir_i)
			if next >= 0 and not visited[next]:
				dirs.append(dir_i)
		if dirs.is_empty():
			stack.pop_back()
			continue
		var picked: int = dirs[rng.randi_range(0, dirs.size() - 1)]
		var next_cell := _neighbor_index(current, picked)
		_carve(current, next_cell, picked)
		visited[next_cell] = true
		stack.append(next_cell)

func _add_extra_loops() -> void:
	for attempt in int(GRID_W * GRID_H * 0.18):
		var cell := rng.randi_range(0, GRID_W * GRID_H - 1)
		var dir_i := rng.randi_range(0, 3)
		var next := _neighbor_index(cell, dir_i)
		if next >= 0 and (int(walls[cell]) & int(BITS[dir_i])) != 0:
			_carve(cell, next, dir_i)

func _pick_layout_points() -> void:
	distances = _compute_distances(start_cell)
	parents = _compute_parents(start_cell)
	exit_cell = start_cell
	for i in distances.size():
		if int(distances[i]) > int(distances[exit_cell]):
			exit_cell = i
	feather_cells = _pick_far_cells(REQUIRED_FEATHERS, [start_cell, exit_cell])
	door_edges.clear()
	key_cells.clear()
	for feather in feather_cells:
		var path := _path_to(int(feather))
		if path.size() > 7:
			var door_index := int(path.size() * 0.55)
			var a: int = path[door_index - 1]
			var b: int = path[door_index]
			var edge := _edge_key(a, b)
			if not _door_edge_exists(edge):
				door_edges.append({"a": a, "b": b, "key": edge})
				key_cells.append(path[maxi(1, door_index - 3)])
	shortcut_edges.clear()
	for i in GRID_W * GRID_H:
		if shortcut_edges.size() >= 3:
			break
		for dir_i in 4:
			var next := _neighbor_index(i, dir_i)
			if next > i and (int(walls[i]) & int(BITS[dir_i])) != 0:
				if abs(int(distances[i]) - int(distances[next])) >= 10:
					shortcut_edges[_edge_key(i, next)] = {"a": i, "b": next}
					break

func _door_edge_exists(edge: String) -> bool:
	for entry in door_edges:
		if String(entry["key"]) == edge:
			return true
	return false

func _pick_far_cells(count: int, blocked: Array) -> Array:
	var picked: Array[int] = []
	while picked.size() < count:
		var best := -1
		var best_score := -1.0
		for i in distances.size():
			if blocked.has(i) or picked.has(i) or int(distances[i]) < 12:
				continue
			var score := float(distances[i])
			for chosen in picked:
				score += minf(14.0, float(_grid_distance(i, int(chosen)))) * 1.5
			if score > best_score:
				best_score = score
				best = i
		if best < 0:
			break
		picked.append(best)
	return picked

func _grid_distance(a: int, b: int) -> int:
	var ax := a % GRID_W
	var ay := int(a / GRID_W)
	var bx := b % GRID_W
	var by := int(b / GRID_W)
	return absi(ax - bx) + absi(ay - by)

func _compute_distances(from_cell: int) -> Array:
	var result: Array[int] = []
	for i in GRID_W * GRID_H:
		result.append(-1)
	var queue: Array[int] = [from_cell]
	var head := 0
	result[from_cell] = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for next in _open_neighbors(current):
			if int(result[next]) < 0:
				result[next] = int(result[current]) + 1
				queue.append(next)
	return result

func _compute_parents(from_cell: int) -> Array:
	var result: Array[int] = []
	for i in GRID_W * GRID_H:
		result.append(-1)
	var queue: Array[int] = [from_cell]
	var head := 0
	result[from_cell] = from_cell
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for next in _open_neighbors(current):
			if int(result[next]) < 0:
				result[next] = current
				queue.append(next)
	return result

func _path_to(target: int) -> Array:
	var path: Array[int] = []
	var current := target
	while current >= 0 and current != start_cell:
		path.push_front(current)
		current = int(parents[current])
	path.push_front(start_cell)
	return path

func _open_neighbors(cell: int) -> Array:
	var result: Array[int] = []
	for dir_i in 4:
		if (int(walls[cell]) & int(BITS[dir_i])) == 0:
			var next := _neighbor_index(cell, dir_i)
			if next >= 0:
				result.append(next)
	return result

func _neighbor_index(cell: int, dir_i: int) -> int:
	var x := cell % GRID_W
	var y := int(cell / GRID_W)
	var npos: Vector2i = Vector2i(x, y) + DIRS[dir_i]
	if npos.x < 0 or npos.x >= GRID_W or npos.y < 0 or npos.y >= GRID_H:
		return -1
	return npos.y * GRID_W + npos.x

func _carve(a: int, b: int, dir_i: int) -> void:
	walls[a] = int(walls[a]) & ~int(BITS[dir_i])
	walls[b] = int(walls[b]) & ~int(OPPOSITE[dir_i])

func _build_world() -> void:
	for child in floor_root.get_children():
		child.queue_free()
	for child in dynamic_root.get_children():
		child.queue_free()
	doors.clear()
	shortcuts.clear()
	_build_floor()
	_build_walls()
	_add_exit()
	for cell in feather_cells:
		_add_feather(int(cell))
	for cell in key_cells:
		_add_key(int(cell))
	for door in door_edges:
		_add_locked_door(int(door["a"]), int(door["b"]), String(door["key"]))
	for edge in shortcut_edges:
		var entry: Dictionary = shortcut_edges[edge]
		_add_shortcut_lever(String(edge), int(entry["a"]))
	_add_traps()
	_add_landmarks()

func _build_floor() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(GRID_W * CELL_SIZE + 2.0, GRID_H * CELL_SIZE + 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.23, 0.28, 0.22)
	mat.roughness = 0.85
	floor_mesh.material = mat
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_root.add_child(floor_instance)

func _build_walls() -> void:
	for cell in GRID_W * GRID_H:
		var x := cell % GRID_W
		var y := int(cell / GRID_W)
		if y == 0 and (int(walls[cell]) & N) != 0:
			_add_wall_at(_wall_pos(cell, N), Vector3(CELL_SIZE + WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS), "")
		if x == 0 and (int(walls[cell]) & W) != 0:
			_add_wall_at(_wall_pos(cell, W), Vector3(WALL_THICKNESS, WALL_HEIGHT, CELL_SIZE + WALL_THICKNESS), "")
		if x == GRID_W - 1 and (int(walls[cell]) & E) != 0:
			_add_wall_at(_wall_pos(cell, E), Vector3(WALL_THICKNESS, WALL_HEIGHT, CELL_SIZE + WALL_THICKNESS), "")
		if y == GRID_H - 1 and (int(walls[cell]) & S) != 0:
			_add_wall_at(_wall_pos(cell, S), Vector3(CELL_SIZE + WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS), "")
		for dir_i in range(1, 3):
			if (int(walls[cell]) & int(BITS[dir_i])) == 0:
				continue
			var next := _neighbor_index(cell, dir_i)
			if next < 0:
				continue
			var edge := _edge_key(cell, next)
			var size := Vector3(WALL_THICKNESS, WALL_HEIGHT, CELL_SIZE + WALL_THICKNESS) if dir_i == 1 else Vector3(CELL_SIZE + WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS)
			if shortcut_edges.has(edge):
				_add_shortcut_gate(edge, _wall_pos(cell, int(BITS[dir_i])), size)
			else:
				_add_wall_at(_wall_pos(cell, int(BITS[dir_i])), size, edge)

func _add_wall_at(pos: Vector3, size: Vector3, edge: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = pos
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.44, 0.39)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	if edge != "":
		body.name = "Wall_%s" % edge.replace(":", "_")
	floor_root.add_child(body)
	return body

func _add_locked_door(a: int, b: int, edge: String) -> void:
	var a_pos := _cell_to_world(a)
	var b_pos := _cell_to_world(b)
	var center := (a_pos + b_pos) * 0.5 + Vector3(0, 1.1, 0)
	var horizontal := absf(a_pos.x - b_pos.x) > absf(a_pos.z - b_pos.z)
	var size := Vector3(WALL_THICKNESS, 2.2, CELL_SIZE * 0.72) if horizontal else Vector3(CELL_SIZE * 0.72, 2.2, WALL_THICKNESS)
	var body := _add_wall_at(center, size, "door_%s" % edge)
	for child in body.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.62, 0.38, 0.16)
			mesh_instance.material_override = mat
	var area := _make_area(center, Vector3(1.5, 1.7, 1.5), "door", edge)
	doors[edge] = {"body": body, "area": area}

func _add_shortcut_gate(edge: String, pos: Vector3, size: Vector3) -> void:
	var body := _add_wall_at(pos, size, "shortcut_%s" % edge)
	for child in body.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.30, 0.48, 0.52)
			mesh_instance.material_override = mat
	shortcuts[edge] = body

func _add_shortcut_lever(edge: String, cell: int) -> void:
	var pos := _cell_to_world(cell) + Vector3(0.8, 0.45, 0.8)
	var root := Node3D.new()
	root.position = pos
	var base := CylinderMesh.new()
	base.top_radius = 0.18
	base.bottom_radius = 0.18
	base.height = 0.9
	_add_mesh(root, base, Vector3.ZERO, Color(0.18, 0.18, 0.18))
	var knob := SphereMesh.new()
	knob.radius = 0.18
	_add_mesh(root, knob, Vector3(0, 0.55, 0), Color(0.9, 0.18, 0.12))
	dynamic_root.add_child(root)
	_make_area(pos + Vector3(0, 0.4, 0), Vector3(1.4, 1.4, 1.4), "lever", edge)

func _add_exit() -> void:
	var pos := _cell_to_world(exit_cell)
	var arch := Node3D.new()
	arch.position = pos
	var frame := BoxMesh.new()
	frame.size = Vector3(1.8, 2.8, 0.22)
	_add_mesh(arch, frame, Vector3(0, 1.4, -0.95), Color(0.18, 0.55, 0.32))
	var glow := SphereMesh.new()
	glow.radius = 0.9
	glow.height = 1.8
	_add_mesh(arch, glow, Vector3(0, 1.15, -0.85), Color(0.25, 0.95, 0.55), Vector3(1, 1.35, 0.12))
	dynamic_root.add_child(arch)
	_make_area(pos + Vector3(0, 0.8, 0), Vector3(1.6, 1.8, 1.6), "exit", "")

func _add_feather(cell: int) -> void:
	var pos := _cell_to_world(cell) + Vector3(0, 0.75, 0)
	var feather := Node3D.new()
	feather.position = pos
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.18
	mesh.height = 0.9
	var mi := _add_mesh(feather, mesh, Vector3.ZERO, Color(1.0, 0.78, 0.12))
	mi.rotation.z = 0.35
	dynamic_root.add_child(feather)
	var area := _make_area(pos, Vector3(1.1, 1.4, 1.1), "feather", str(cell))
	area.set_meta("visual", feather)

func _add_key(cell: int) -> void:
	var pos := _cell_to_world(cell) + Vector3(0, 0.42, 0)
	var key := Node3D.new()
	key.position = pos
	var ring := TorusMesh.new()
	ring.inner_radius = 0.08
	ring.outer_radius = 0.18
	_add_mesh(key, ring, Vector3.ZERO, Color(0.95, 0.78, 0.18))
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.42, 0.08, 0.08)
	_add_mesh(key, shaft, Vector3(0.32, 0, 0), Color(0.95, 0.78, 0.18))
	dynamic_root.add_child(key)
	var area := _make_area(pos, Vector3(1.0, 1.1, 1.0), "key", str(cell))
	area.set_meta("visual", key)

func _add_traps() -> void:
	var placed := 0
	for i in distances.size():
		if placed >= 8:
			break
		if int(distances[i]) > 10 and i % 23 == maze_seed % 23 and not feather_cells.has(i) and i != exit_cell:
			var pos := _cell_to_world(i)
			var plate := BoxMesh.new()
			plate.size = Vector3(1.25, 0.08, 1.25)
			_add_mesh(dynamic_root, plate, pos + Vector3(0, 0.04, 0), Color(0.28, 0.25, 0.22))
			_make_area(pos + Vector3(0, 0.25, 0), Vector3(1.2, 0.8, 1.2), "trap", "")
			placed += 1

func _add_landmarks() -> void:
	for i in 14:
		var cell := rng.randi_range(0, GRID_W * GRID_H - 1)
		if cell == start_cell or cell == exit_cell or feather_cells.has(cell):
			continue
		var torch := CylinderMesh.new()
		torch.top_radius = 0.08
		torch.bottom_radius = 0.08
		torch.height = 0.8
		var pos := _cell_to_world(cell) + Vector3(rng.randf_range(-0.8, 0.8), 0.55, rng.randf_range(-0.8, 0.8))
		_add_mesh(dynamic_root, torch, pos, Color(0.30, 0.18, 0.08))
		var flame := SphereMesh.new()
		flame.radius = 0.18
		_add_mesh(dynamic_root, flame, pos + Vector3(0, 0.48, 0), Color(1.0, 0.45, 0.08))

func _make_area(pos: Vector3, size: Vector3, kind: String, id: String) -> Area3D:
	var area := Area3D.new()
	area.position = pos
	area.set_meta("kind", kind)
	area.set_meta("id", id)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(_on_area_body_entered.bind(area))
	area.body_exited.connect(_on_area_body_exited.bind(area))
	dynamic_root.add_child(area)
	return area

func _on_area_body_entered(body: Node3D, area: Area3D) -> void:
	if body != player or won:
		return
	var kind := String(area.get_meta("kind"))
	match kind:
		"feather":
			_collect_area(area, "Plume trouvee !")
			collected_feathers += 1
			if sfx:
				sfx.play_score()
			if collected_feathers >= REQUIRED_FEATHERS:
				_show_message("Les plumes ouvrent la sortie. Cherche la lueur verte.")
		"key":
			_collect_area(area, "Cle recuperee.")
			keys += 1
			if sfx:
				sfx.play_pickup("pickup_gold")
		"trap":
			if slow_timer <= 0.0:
				player.speed_mult = SLOW_MULT
				slow_timer = SLOW_SECONDS
				_show_message("Dalle collante : tu ralentis.")
				if sfx:
					sfx.play_hurt()
		"exit":
			if collected_feathers >= REQUIRED_FEATHERS:
				_win()
			else:
				_show_message("La sortie reclame encore %d plume(s)." % (REQUIRED_FEATHERS - collected_feathers))
		"door", "lever":
			nearby_interactable = area
			_update_prompt()

func _on_area_body_exited(body: Node3D, area: Area3D) -> void:
	if body == player and nearby_interactable == area:
		nearby_interactable = null
		_update_prompt()

func _collect_area(area: Area3D, text: String) -> void:
	if area.has_meta("visual"):
		var visual: Node = area.get_meta("visual") as Node
		if visual != null and is_instance_valid(visual):
			visual.queue_free()
	area.queue_free()
	_show_message(text)

func _try_interact() -> void:
	if nearby_interactable == null or not is_instance_valid(nearby_interactable):
		return
	var kind := String(nearby_interactable.get_meta("kind"))
	var id := String(nearby_interactable.get_meta("id"))
	if kind == "door":
		if keys <= 0:
			_show_message("Il faut une cle.")
			return
		keys -= 1
		var door: Dictionary = doors[id] if doors.has(id) else {}
		if door.has("body") and is_instance_valid(door["body"]):
			door["body"].queue_free()
		if door.has("area") and is_instance_valid(door["area"]):
			door["area"].queue_free()
		doors.erase(id)
		nearby_interactable = null
		_show_message("Porte ouverte.")
		if sfx:
			sfx.play_morph()
	elif kind == "lever":
		var gate: Node = shortcuts.get(id) as Node
		if gate != null and is_instance_valid(gate):
			gate.queue_free()
		shortcuts.erase(id)
		nearby_interactable.queue_free()
		nearby_interactable = null
		_show_message("Raccourci ouvert.")
		if sfx:
			sfx.play_morph()
	_update_prompt()

func _win() -> void:
	if won:
		return
	won = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_physics_process(false)
	if sfx:
		sfx.play_win()
	_show_message("Sortie trouvee !")
	_show_end_panel()

func _build_ui() -> void:
	hud_label = _make_label(Vector2(20, 16), Vector2(420, 96), 24, HORIZONTAL_ALIGNMENT_LEFT)
	ui.add_child(hud_label)
	message_label = _make_label(Vector2(0, -118), Vector2(0, 80), 24, HORIZONTAL_ALIGNMENT_CENTER)
	message_label.anchor_top = 1.0
	message_label.anchor_right = 1.0
	message_label.anchor_bottom = 1.0
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.add_child(message_label)
	prompt_label = _make_label(Vector2(0, -72), Vector2(0, 40), 22, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_right = 1.0
	prompt_label.anchor_bottom = 1.0
	ui.add_child(prompt_label)
	_build_pause_overlay()
	_update_hud()
	_update_prompt()

func _build_pause_overlay() -> void:
	pause_overlay = Control.new()
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.visible = false
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(pause_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var title := Label.new()
	title.text = "Labyrinthe"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	root.add_child(title)
	var resume := _make_button("Reprendre")
	resume.pressed.connect(func() -> void: _set_paused(false))
	root.add_child(resume)
	var restart := _make_button("Rejouer")
	restart.pressed.connect(func() -> void:
		_set_paused(false)
		get_tree().reload_current_scene()
	)
	root.add_child(restart)
	var menu := _make_button("Menu principal")
	menu.pressed.connect(func() -> void:
		_set_paused(false)
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	)
	root.add_child(menu)

func _show_end_panel() -> void:
	end_panel = Control.new()
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(end_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.58)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var title := Label.new()
	title.text = "Sortie trouvee"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)
	var score := Label.new()
	score.text = "Temps : %s\nGraine : %d" % [_format_time(run_time), maze_seed]
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", 20)
	root.add_child(score)
	var replay := _make_button("Rejouer")
	replay.pressed.connect(func() -> void: get_tree().reload_current_scene())
	root.add_child(replay)
	var menu := _make_button("Menu principal")
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	root.add_child(menu)

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

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 42)
	button.add_theme_font_size_override("font_size", 20)
	return button

func _set_paused(value: bool) -> void:
	get_tree().paused = value
	pause_overlay.visible = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "Plumes : %d / %d\nCles : %d\nTemps : %s\nGraine : %d" % [
		collected_feathers,
		REQUIRED_FEATHERS,
		keys,
		_format_time(run_time),
		maze_seed,
	]

func _update_prompt() -> void:
	if prompt_label == null:
		return
	if nearby_interactable == null or not is_instance_valid(nearby_interactable):
		prompt_label.text = ""
		return
	var kind := String(nearby_interactable.get_meta("kind"))
	prompt_label.text = "E : ouvrir la porte" if kind == "door" else "E : activer le levier"

func _show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text
		var tw := create_tween()
		tw.tween_interval(2.5)
		tw.tween_callback(func() -> void:
			if message_label != null and message_label.text == text:
				message_label.text = ""
		)

func _format_time(value: float) -> String:
	var total := int(value)
	return "%02d:%02d" % [int(total / 60), total % 60]

func _update_camera() -> void:
	var forward := Vector3(sin(player.rotation.y), 0.0, cos(player.rotation.y))
	camera.global_position = player.global_position + Vector3(0, PLAYER_EYE_HEIGHT, 0) + forward * PLAYER_FORWARD
	camera.rotation = Vector3(player.fp_pitch, player.rotation.y + PI, 0.0)
	camera.fov = 74.0

func _wall_pos(cell: int, side: int) -> Vector3:
	var pos := _cell_to_world(cell)
	match side:
		N:
			return pos + Vector3(0, WALL_HEIGHT * 0.5, -CELL_SIZE * 0.5)
		E:
			return pos + Vector3(CELL_SIZE * 0.5, WALL_HEIGHT * 0.5, 0)
		S:
			return pos + Vector3(0, WALL_HEIGHT * 0.5, CELL_SIZE * 0.5)
		_:
			return pos + Vector3(-CELL_SIZE * 0.5, WALL_HEIGHT * 0.5, 0)

func _cell_to_world(cell: int) -> Vector3:
	var x := cell % GRID_W
	var y := int(cell / GRID_W)
	return Vector3(
		(float(x) - float(GRID_W - 1) * 0.5) * CELL_SIZE,
		0.0,
		(float(y) - float(GRID_H - 1) * 0.5) * CELL_SIZE
	)

func _edge_key(a: int, b: int) -> String:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return "%d:%d" % [lo, hi]

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, mesh_scale := Vector3.ONE) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = mesh_scale
	parent.add_child(mi)
	return mi

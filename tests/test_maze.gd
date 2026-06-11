extends Node
## Test automatique du mode labyrinthe : generation, accessibilite et victoire.

func _fail(msg: String) -> void:
	print("TEST ECHEC - %s" % msg)
	get_tree().quit(1)

func _ready() -> void:
	var maze: Node3D = load("res://scenes/maze.tscn").instantiate()
	get_tree().root.add_child.call_deferred(maze)
	await get_tree().process_frame
	await get_tree().process_frame
	if maze.walls.size() != maze.GRID_W * maze.GRID_H:
		_fail("taille de grille invalide")
		return
	if maze.exit_cell == maze.start_cell:
		_fail("la sortie ne doit pas etre sur le depart")
		return
	var distances: Array = maze._compute_distances(maze.start_cell)
	if int(distances[maze.exit_cell]) <= 0:
		_fail("sortie inaccessible depuis le depart")
		return
	if maze.feather_cells.size() != maze.REQUIRED_FEATHERS:
		_fail("nombre de plumes invalide")
		return
	for cell in maze.feather_cells:
		if int(distances[int(cell)]) <= 0:
			_fail("plume inaccessible")
			return
	for door in maze.door_edges:
		var key := String(door["key"])
		if not maze.doors.has(key):
			_fail("porte verrouillee non construite")
			return
		var key_cell := int(door["key_cell"])
		var dist_to_door := mini(
			maze._grid_distance(key_cell, int(door["a"])),
			maze._grid_distance(key_cell, int(door["b"]))
		)
		if dist_to_door < maze.KEY_DOOR_MIN_GRID_DISTANCE:
			_fail("cle trop proche de sa porte (%d cases)" % dist_to_door)
			return
	if maze.key_cells.size() != maze.door_edges.size():
		_fail("chaque porte verrouillee doit avoir une cle")
		return
	for cell in maze.key_cells:
		if int(distances[int(cell)]) <= 0:
			_fail("cle inaccessible")
			return
	if not maze.door_edges.is_empty():
		var first_door: Dictionary = maze.door_edges[0]
		var door_id := String(first_door["key"])
		var door_data: Dictionary = maze.doors[door_id]
		var area: Area3D = door_data["area"]
		maze.keys = 1
		maze.player.global_position = area.global_position
		maze._update_nearby_interactable()
		maze._try_interact()
		if maze.doors.has(door_id) or maze.keys != 0:
			_fail("interaction porte avec cle attendue")
			return
	maze.collected_feathers = maze.REQUIRED_FEATHERS
	maze._win()
	await get_tree().process_frame
	if not maze.won:
		_fail("la victoire ne s'active pas apres les plumes")
		return
	print("TEST OK - labyrinthe genere : sortie, plumes, cles et victoire valides")
	get_tree().quit(0)

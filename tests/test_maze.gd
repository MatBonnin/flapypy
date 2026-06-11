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
	if maze.key_cells.size() != maze.door_edges.size():
		_fail("chaque porte verrouillee doit avoir une cle")
		return
	for cell in maze.key_cells:
		if int(distances[int(cell)]) <= 0:
			_fail("cle inaccessible")
			return
	maze.collected_feathers = maze.REQUIRED_FEATHERS
	maze._win()
	await get_tree().process_frame
	if not maze.won:
		_fail("la victoire ne s'active pas apres les plumes")
		return
	print("TEST OK - labyrinthe genere : sortie, plumes, cles et victoire valides")
	get_tree().quit(0)

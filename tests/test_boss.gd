extends Node
## Test du boss : force la vague 5, vérifie que le Tuyau Suprême apparaît,
## tire en cercle, et que sa mort termine la vague.

func _ready() -> void:
	var arena: Node3D = load("res://scenes/arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: CharacterBody3D = arena.get_node("Player")
	# joueur boosté pour aller droit au but
	player.beak_damage = 5
	player.max_hp = 30
	player.hp = 30
	# attendre que l'intro de la vague 1 soit passée puis forcer la vague boss
	await get_tree().create_timer(3.5).timeout
	arena._start_wave(5)
	var saw_boss := false
	var saw_shot := false
	for i in 3000:
		await get_tree().physics_frame
		if arena.boss != null:
			saw_boss = true
		for child in arena.get_node("Units").get_children():
			if child.name.begins_with("PipeShot"):
				saw_shot = true
		var nearest: Node3D = null
		var nearest_dist := 99.0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var d: float = (enemy.global_position - player.global_position).length()
			if d < nearest_dist:
				nearest_dist = d
				nearest = enemy
		if nearest != null:
			var to: Vector3 = nearest.global_position - player.global_position
			player.rotation.y = atan2(to.x, to.z)
			if nearest_dist < 1.5:
				player.attack()
			elif nearest_dist < 6.0:
				player.throw_beak()
		if arena.wave_state == arena.WaveState.CHOICE or player.dead:
			break
	var ok: bool = saw_boss and saw_shot and arena.wave_state == arena.WaveState.CHOICE
	print("%s - boss vu: %s, tirs du boss: %s, vague nettoyee: %s, tues: %d, PV: %d" % [
		"TEST OK" if ok else "TEST ECHEC",
		str(saw_boss), str(saw_shot),
		str(arena.wave_state == arena.WaveState.CHOICE),
		arena.kills, player.hp,
	])
	get_tree().quit(0 if ok else 1)

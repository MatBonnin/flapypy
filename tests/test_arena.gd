extends Node
## Test automatique : joue la vague 1 (passif jusqu'au premier coup reçu,
## puis combat), choisit une amélioration et vérifie que la vague 2 démarre.

func _ready() -> void:
	var arena: Node3D = load("res://scenes/arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: CharacterBody3D = arena.get_node("Player")
	var hurt := false
	var upgraded := false
	for i in 3000:
		await get_tree().physics_frame
		if player.hp < player.max_hp:
			hurt = true
		if arena.wave_state == arena.WaveState.CHOICE:
			player.apply_upgrade(arena.upgrade_options[0])
			upgraded = true
			arena._start_wave(arena.wave + 1)
		var nearest: Node3D = null
		var nearest_dist := 99.0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var d: float = (enemy.global_position - player.global_position).length()
			if d < nearest_dist:
				nearest_dist = d
				nearest = enemy
		# phase 1 : passif jusqu'à encaisser un coup, pour vérifier l'attaque ennemie
		if nearest != null and hurt:
			var to: Vector3 = nearest.global_position - player.global_position
			player.rotation.y = atan2(to.x, to.z)
			if nearest_dist < 1.5:
				player.attack()
			elif nearest_dist < 5.0:
				player.throw_beak()
		if (arena.wave >= 2 and upgraded and arena.kills >= 5) or player.dead:
			break
	var ok: bool = hurt and upgraded and arena.kills >= 5 and not player.dead
	print("%s - vague: %d, tues: %d, PV: %d, amelioration: %s" % [
		"TEST OK" if ok else "TEST ECHEC",
		arena.wave, arena.kills, player.hp, str(upgraded),
	])
	get_tree().quit(0 if ok else 1)

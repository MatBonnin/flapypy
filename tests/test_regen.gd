extends Node
## Vérifie la régénération : la vie remonte après un délai sans dégât,
## mais reste bloquée tant qu'on prend des coups.

func _ready() -> void:
	_ensure_input_actions()
	var player: CharacterBody3D = load("res://scenes/birdman.tscn").instantiate()
	get_tree().root.add_child.call_deferred(player)
	await get_tree().process_frame
	await get_tree().process_frame

	# blessure initiale
	player.hp = 3
	player.hp_changed.emit(3)
	var low: int = player.hp

	# 1) on prend un coup régulièrement : la vie ne doit PAS remonter
	for i in 180:  # ~3s
		await get_tree().physics_frame
		player.invuln_timer = 0.0
		player.take_damage(0)  # reset le compteur sans baisser les PV
	var blocked_ok: bool = player.hp == low

	# 2) on laisse le joueur tranquille : la vie doit remonter
	player.no_damage_time = 0.0
	player.regen_timer = 0.0
	for i in 480:  # ~8s sans dégât
		await get_tree().physics_frame
	var regen_ok: bool = player.hp > low and player.hp <= player.max_hp

	# 3) ne dépasse jamais max_hp via le régen
	for i in 300:
		await get_tree().physics_frame
	var cap_ok: bool = player.hp <= player.max_hp

	var ok := blocked_ok and regen_ok and cap_ok
	print("%s - bloque sous le feu: %s, regen ok: %s (PV=%d/%d), cap: %s" % [
		"TEST OK" if ok else "TEST ECHEC",
		str(blocked_ok), str(regen_ok), player.hp, player.max_hp, str(cap_ok),
	])
	get_tree().quit(0 if ok else 1)

func _ensure_input_actions() -> void:
	for action in [
		"arena_move_up",
		"arena_move_down",
		"arena_move_left",
		"arena_move_right",
		"arena_attack",
		"arena_throw_beak",
		"arena_jump",
	]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

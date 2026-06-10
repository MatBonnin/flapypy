extends Node
## Test automatique du Prop Hunt : heberge, simule un 2e joueur cote serveur,
## puis joue une manche complete : deguisement pendant la cachette, passage en
## chasse, coup manque (malus chercheur), elimination du prop et retour lobby.

func _fail(msg: String) -> void:
	print("TEST ECHEC - %s" % msg)
	get_tree().quit(1)

func _ready() -> void:
	var arena: Node3D = load("res://scenes/prop_hunt.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.listen_port = 52425  # port dedie : ne pas gener une partie en cours
	arena._host_game()
	await get_tree().process_frame
	# 2e joueur simule directement cote serveur
	arena.player_names[2] = "Bot"
	arena.player_order.append(2)
	arena.kills[2] = 0
	arena._client_spawn_player(2, "Bot", Vector3(6.5, 0, 6.5), 8, false)
	await get_tree().process_frame
	if arena.player_order.size() != 2:
		_fail("2 joueurs attendus")
		return
	arena._server_start_round()
	await get_tree().process_frame
	if arena.phase != arena.Phase.HIDE:
		_fail("phase HIDE attendue apres le lancement")
		return
	if arena.seeker_id != 1:
		_fail("l'hote devait etre le chercheur de la manche 1")
		return
	# le prop se deguise sur l'objet le plus proche
	var hider: CharacterBody3D = arena.players[2]
	var prop_pos: Vector3 = arena.props[0]["pos"]
	hider.global_position = prop_pos + Vector3(0.5, 0, 0)
	hider.pvp_target_position = hider.global_position
	arena._server_do_morph(2)
	await get_tree().process_frame
	if int(arena.morphs.get(2, -1)) < 0 or hider.model.visible:
		_fail("le prop ne s'est pas deguise")
		return
	# changer rapidement de prop ne doit jamais empiler deux visuels
	arena._client_set_morph(2, arena.Prop.TREE)
	arena._client_set_morph(2, arena.Prop.PUMPKIN)
	var morph_visual_count := 0
	for child in hider.get_children():
		if str(child.name) == "MorphVisual" or child.get_meta("morph_visual", false):
			morph_visual_count += 1
	if morph_visual_count != 1:
		_fail("un seul visuel de prop attendu apres changement rapide (%d)" % morph_visual_count)
		return
	# fin de cachette acceleree
	arena.phase_time_left = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if arena.phase != arena.Phase.HUNT:
		_fail("phase HUNT attendue apres la cachette")
		return
	var seeker: CharacterBody3D = arena.players[1]
	seeker.global_position = Vector3.ZERO
	hider.global_position = Vector3(8.5, 0, 8.5)
	hider.pvp_target_position = hider.global_position
	var before_prop_positions: Dictionary = {}
	for prop in arena.props:
		before_prop_positions[int(prop["id"])] = prop["pos"]
	var moved_prop: bool = arena._server_try_move_random_prop()
	await get_tree().process_frame
	if not moved_prop:
		_fail("un objet decor devait pouvoir bouger pendant la chasse")
		return
	var moved_prop_count := 0
	for prop in arena.props:
		var prop_id := int(prop["id"])
		if prop["pos"] != before_prop_positions[prop_id]:
			moved_prop_count += 1
			if not arena._is_prop_spot_clear(prop_id, prop["pos"], float(prop["radius"])):
				_fail("un objet mobile chevauche un autre objet")
				return
	if moved_prop_count != 1:
		_fail("un seul objet decor devait bouger (%d)" % moved_prop_count)
		return
	# coup manque : -1 PV pour le chercheur
	seeker.global_position = Vector3.ZERO
	seeker.rotation.y = PI
	hider.global_position = Vector3(0, 0, 5)
	hider.pvp_target_position = hider.global_position
	arena._server_apply_strike(1)
	if seeker.hp != arena.SEEKER_HP - 1:
		_fail("le coup manque devait couter 1 PV au chercheur (PV=%d)" % seeker.hp)
		return
	# premier coup au but
	seeker.rotation.y = 0.0
	hider.global_position = seeker.global_position + Vector3(0, 0, 1.0)
	hider.pvp_target_position = hider.global_position
	arena._server_apply_strike(1)
	if hider.hp != arena.HIDER_HP - 1:
		_fail("le prop devait perdre 1 PV (PV=%d)" % hider.hp)
		return
	# deuxieme coup apres la fenetre d'invulnerabilite
	await get_tree().create_timer(1.1).timeout
	hider.global_position = seeker.global_position + Vector3(0, 0, 1.0)
	hider.pvp_target_position = hider.global_position
	arena._server_apply_strike(1)
	await get_tree().process_frame
	if not hider.dead:
		_fail("le prop devait etre elimine")
		return
	if not hider.model.visible:
		_fail("le prop elimine devait etre revele")
		return
	if arena.phase != arena.Phase.OVER:
		_fail("la manche devait se terminer quand tous les props sont morts")
		return
	if int(arena.kills.get(1, 0)) != 1:
		_fail("le chercheur devait compter 1 elimination")
		return
	# retour au lobby et soins
	arena.phase_time_left = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if arena.phase != arena.Phase.LOBBY:
		_fail("retour au lobby attendu apres la manche")
		return
	if hider.dead or hider.hp != 8:
		_fail("les joueurs devaient etre soignes au lobby (PV=%d)" % hider.hp)
		return
	print("TEST OK - manche prop hunt complete : deguisement, coup manque, elimination, retour lobby")
	get_tree().quit(0)

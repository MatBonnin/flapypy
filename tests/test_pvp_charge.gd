extends Node
## Vérifie en conditions réelles (partie hébergée) que la charge du bec
## fonctionne en PvP : barre visible, charge qui monte, projectile accéléré.

func _ready() -> void:
	var arena: Node3D = load("res://scenes/pvp_arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	# pas d'ENet : le peer hors-ligne par défaut est déjà serveur (id=1),
	# on reproduit ce que fait _host_game sans ouvrir de port
	var local_id: int = arena.multiplayer.get_unique_id()
	arena._client_spawn_player(local_id, "Testeur", Vector3.ZERO, 8, false)
	arena._start_match()
	await get_tree().process_frame
	var player: CharacterBody3D = arena.players.get(local_id)
	if player == null:
		print("ECHEC: pas de joueur local")
		get_tree().quit(1)
		return
	Input.action_press("arena_throw_beak")
	player._start_beak_charge()
	for i in 40:
		await get_tree().physics_frame
	var bar_built: bool = player._charge_bar_bg != null
	var bar_visible: bool = bar_built and player._charge_bar_bg.visible
	var charge_value: float = player.beak_charge
	Input.action_release("arena_throw_beak")
	await get_tree().physics_frame
	var projectile_mult := -1.0
	for projectile in arena.projectiles.values():
		if is_instance_valid(projectile):
			projectile_mult = projectile.speed_mult
	var ok: bool = bar_built and bar_visible and charge_value > 0.3 and projectile_mult > 1.2
	print("%s - barre construite: %s, visible: %s, charge: %.2f, mult projectile: %.2f" % [
		"TEST OK" if ok else "TEST ECHEC",
		str(bar_built), str(bar_visible), charge_value, projectile_mult,
	])
	get_tree().quit(0 if ok else 1)

extends CharacterBody3D

signal hp_changed(hp: int)
signal hit_landed
signal died

enum Pickup { HEART, BAGUETTE, GOLD_BEAK, COFFEE, MUSHROOM }
enum Upgrade { VITALITY, CLUB, BEAK_DMG, BEAK_SPEED, DOUBLE_JUMP, BOOTS }

const BeakProjectileScene := preload("res://scenes/beak_projectile.tscn")

const SPEED := 4.5
const ARENA_HALF := 9.8
const GRAVITY := 22.0
const JUMP_SPEED := 7.5
const ATTACK_RANGE := 1.6
const ATTACK_ARC := 1.1
const ATTACK_COOLDOWN := 0.45
const BEAK_COOLDOWN := 0.7
const HURT_INVULN := 1.0
const MAX_HP := 8
const ACTION_MOVE_UP := "arena_move_up"
const ACTION_MOVE_DOWN := "arena_move_down"
const ACTION_MOVE_LEFT := "arena_move_left"
const ACTION_MOVE_RIGHT := "arena_move_right"
const ACTION_ATTACK := "arena_attack"
const ACTION_THROW_BEAK := "arena_throw_beak"
const ACTION_JUMP := "arena_jump"
const REGEN_DELAY := 4.0   # secondes sans dégât avant que la vie remonte
const REGEN_INTERVAL := 1.5 # secondes entre chaque PV régénéré
const FP_MOUSE_SENS := 0.003 # sensibilité souris en vue première personne (rad/pixel)
const FP_PITCH_LIMIT := 1.25 # inclinaison verticale max du regard (rad)

var hp := MAX_HP
var max_hp := MAX_HP
var melee_bonus := 0
var beak_damage := 2
var beak_cd_mult := 1.0
var speed_mult := 1.0
var max_jumps := 1
var jumps_left := 1
var vy := 0.0
var attack_timer := 0.0
var beak_timer := 0.0
var invuln_timer := 0.0
var no_damage_time := 0.0
var regen_timer := 0.0
var baguette_timer := 0.0
var triple_timer := 0.0
var coffee_timer := 0.0
var giant_timer := 0.0
var base_scale := 1.0
var anim_time := 0.0
var swing := 0.0
var attacking := false
var dead := false
var sfx: Node = null
var pvp_enabled := false
var pvp_peer_id := 0
var pvp_arena: Node = null
var pvp_target_position := Vector3.ZERO
var pvp_target_rotation := 0.0
var first_person := false
var fp_pitch := 0.0
var fp_sens_mult := 1.0

var _meshes: Array[MeshInstance3D] = []
var _gold_mat: Material = null
var _flash_mat: StandardMaterial3D
var _pvp_base_mats := {}
var _damage_overlay: ColorRect = null

@onready var model: Node3D = $Model
@onready var right_arm: Node3D = $Model/RightArm
@onready var left_arm: Node3D = $Model/ArmPivotL
@onready var leg_l: Node3D = $Model/LegPivotL
@onready var leg_r: Node3D = $Model/LegPivotR
@onready var beak: MeshInstance3D = $Model/Beak
@onready var club: MeshInstance3D = $Model/RightArm/Club
@onready var club_tip: MeshInstance3D = $Model/RightArm/ClubTip
@onready var baguette: MeshInstance3D = $Model/RightArm/Baguette

func _ready() -> void:
	_collect_meshes(model)
	for m in _meshes:
		_pvp_base_mats[m] = m.material_override
	pvp_target_position = global_position
	pvp_target_rotation = rotation.y
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1, 0.3, 0.3)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(0.9, 0.15, 0.15)

func _physics_process(delta: float) -> void:
	if pvp_enabled and not _is_local_pvp_player():
		# le serveur s'appuie sur invuln_timer pour les degats des joueurs
		# distants : il doit continuer a s'ecouler ici aussi
		invuln_timer = maxf(invuln_timer - delta, 0.0)
		global_position = global_position.lerp(pvp_target_position, minf(1.0, 18.0 * delta))
		rotation.y = lerp_angle(rotation.y, pvp_target_rotation, minf(1.0, 18.0 * delta))
		_apply_anim()
		return
	if dead:
		return
	attack_timer = maxf(attack_timer - delta, 0.0)
	invuln_timer = maxf(invuln_timer - delta, 0.0)
	if not pvp_enabled:
		_update_regen(delta)
	_update_buffs(delta)
	if beak_timer > 0.0:
		beak_timer -= delta
		if beak_timer <= 0.0:
			# le bec repousse
			beak.visible = true
			beak.scale = Vector3(0.1, 0.1, 0.1)
			var tw := create_tween()
			tw.tween_property(beak, "scale", Vector3.ONE, 0.15)
	var input := Input.get_vector(
		ACTION_MOVE_LEFT,
		ACTION_MOVE_RIGHT,
		ACTION_MOVE_UP,
		ACTION_MOVE_DOWN
	)
	var dir := Vector3.ZERO
	if first_person:
		# En première personne la souris oriente le regard ; les touches
		# déplacent relativement à la vue (avant/arrière + pas latéraux).
		if input != Vector2.ZERO:
			var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
			var right := Vector3(-cos(rotation.y), 0.0, sin(rotation.y))
			dir = (forward * -input.y + right * input.x).normalized()
	elif input != Vector2.ZERO:
		dir = Vector3(input.x, 0.0, input.y).normalized()
	var speed := SPEED * speed_mult
	if coffee_timer > 0.0:
		speed *= 1.6
	velocity = dir * speed
	move_and_slide()
	position.x = clampf(position.x, -ARENA_HALF, ARENA_HALF)
	position.z = clampf(position.z, -ARENA_HALF, ARENA_HALF)
	# saut : la hauteur est gérée à la main (pas de gravité sur le déplacement)
	vy -= GRAVITY * delta
	position.y += vy * delta
	if position.y <= 0.0:
		position.y = 0.0
		vy = 0.0
		jumps_left = max_jumps
	if dir != Vector3.ZERO:
		if not first_person:
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 12.0 * delta)
		anim_time += delta * 2.0 * speed
		swing = sin(anim_time) * 0.55
	else:
		swing = lerpf(swing, 0.0, 10.0 * delta)
	_apply_anim()

func _apply_anim() -> void:
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	left_arm.rotation.x = -swing
	if not attacking:
		right_arm.rotation.x = swing * 0.6
	model.position.y = absf(swing) * 0.08

func _unhandled_input(event: InputEvent) -> void:
	if pvp_enabled and not _is_local_pvp_player():
		return
	if first_person and event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := FP_MOUSE_SENS * fp_sens_mult
		rotation.y -= event.relative.x * sens
		fp_pitch = clampf(fp_pitch - event.relative.y * sens, -FP_PITCH_LIMIT, FP_PITCH_LIMIT)
		return
	if dead:
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(ACTION_ATTACK):
		attack()
	elif event.is_action_pressed(ACTION_THROW_BEAK):
		throw_beak()
	elif event.is_action_pressed(ACTION_JUMP):
		jump()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			throw_beak()

func jump() -> void:
	if dead or jumps_left <= 0:
		return
	jumps_left -= 1
	vy = JUMP_SPEED
	if sfx:
		sfx.play_flap()

func _update_regen(delta: float) -> void:
	# La vie remonte seulement après un moment sans prendre de coup :
	# récompense l'esquive sans aider quand on se fait déborder.
	no_damage_time += delta
	if hp >= max_hp or no_damage_time < REGEN_DELAY:
		return
	regen_timer += delta
	if regen_timer >= REGEN_INTERVAL:
		regen_timer = 0.0
		hp = mini(hp + 1, max_hp)
		hp_changed.emit(hp)

func _update_buffs(delta: float) -> void:
	if baguette_timer > 0.0:
		baguette_timer -= delta
		if baguette_timer <= 0.0:
			club.visible = true
			club_tip.visible = true
			baguette.visible = false
	if triple_timer > 0.0:
		triple_timer -= delta
		if triple_timer <= 0.0:
			_gold_mat = null
			beak.material_override = null
	if coffee_timer > 0.0:
		coffee_timer -= delta
	if giant_timer > 0.0:
		giant_timer -= delta
		if giant_timer <= 0.0:
			base_scale = 1.0
			var tw := create_tween()
			tw.tween_property(model, "scale", Vector3.ONE, 0.3)

func apply_pickup(type: int) -> void:
	if dead:
		return
	match type:
		Pickup.HEART:
			hp = mini(hp + 2, max_hp + 4)
			hp_changed.emit(hp)
		Pickup.BAGUETTE:
			baguette_timer = 10.0
			club.visible = false
			club_tip.visible = false
			baguette.visible = true
		Pickup.GOLD_BEAK:
			triple_timer = 10.0
			var gold := StandardMaterial3D.new()
			gold.albedo_color = Color(1.0, 0.84, 0.2)
			gold.metallic = 0.8
			gold.roughness = 0.3
			_gold_mat = gold
			beak.material_override = gold
		Pickup.COFFEE:
			coffee_timer = 8.0
		Pickup.MUSHROOM:
			giant_timer = 8.0
			base_scale = 1.9
			var tw := create_tween()
			tw.tween_property(model, "scale", Vector3.ONE * base_scale, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func apply_upgrade(id: int) -> void:
	match id:
		Upgrade.VITALITY:
			max_hp += 2
			hp = max_hp
			hp_changed.emit(hp)
		Upgrade.CLUB:
			melee_bonus += 1
		Upgrade.BEAK_DMG:
			beak_damage += 1
		Upgrade.BEAK_SPEED:
			beak_cd_mult *= 0.7
		Upgrade.DOUBLE_JUMP:
			max_jumps = 2
		Upgrade.BOOTS:
			speed_mult *= 1.15

func _melee_damage() -> int:
	var dmg := 1 + melee_bonus
	if baguette_timer > 0.0:
		dmg += 1
	if giant_timer > 0.0:
		dmg += 2
	return dmg

func _melee_range() -> float:
	var melee_range := ATTACK_RANGE
	if baguette_timer > 0.0:
		melee_range = 2.8
	if giant_timer > 0.0:
		melee_range = maxf(melee_range, 2.6)
	return melee_range

func attack() -> void:
	if dead or attacking or attack_timer > 0.0:
		return
	attack_timer = ATTACK_COOLDOWN
	attacking = true
	if sfx:
		sfx.play_flap()
	var tw := create_tween()
	tw.tween_property(right_arm, "rotation:x", -1.9, 0.08)
	tw.tween_callback(_strike)
	tw.tween_property(right_arm, "rotation:x", 0.0, 0.18)
	tw.tween_callback(func() -> void: attacking = false)

func throw_beak() -> void:
	if dead or beak_timer > 0.0:
		return
	if pvp_enabled:
		beak_timer = (0.35 if triple_timer > 0.0 else BEAK_COOLDOWN) * beak_cd_mult
		beak.visible = false
		if sfx:
			sfx.play_flap()
		if pvp_arena != null and _is_local_pvp_player():
			var dir := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
			pvp_arena.request_pvp_beak(pvp_peer_id, beak.global_position, dir, rotation.y, beak_damage)
		return
	beak_timer = (0.35 if triple_timer > 0.0 else BEAK_COOLDOWN) * beak_cd_mult
	beak.visible = false
	if sfx:
		sfx.play_flap()
	var angles: Array[float] = [0.0]
	if triple_timer > 0.0:
		angles = [-0.3, 0.0, 0.3]
	for a in angles:
		var proj: Area3D = BeakProjectileScene.instantiate()
		get_parent().add_child(proj)
		var ang := rotation.y + a
		proj.damage = beak_damage
		proj.direction = Vector3(sin(ang), 0.0, cos(ang))
		proj.rotation.y = ang
		proj.global_position = beak.global_position

func _strike() -> void:
	if pvp_enabled:
		if pvp_arena != null and _is_local_pvp_player():
			pvp_arena.request_pvp_strike(pvp_peer_id)
		return
	var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var damage := _melee_damage()
	var melee_range := _melee_range()
	var hit := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to: Vector3 = enemy.global_position - global_position
		to.y = 0.0
		if to.length() <= melee_range and fwd.angle_to(to.normalized()) <= ATTACK_ARC:
			enemy.take_damage(damage, to.normalized())
			hit = true
	if hit:
		hit_landed.emit()
		if sfx:
			sfx.play_hit()

func take_damage(amount: int) -> void:
	if pvp_enabled and not multiplayer.is_server():
		return
	if dead or invuln_timer > 0.0:
		return
	invuln_timer = HURT_INVULN
	no_damage_time = 0.0
	regen_timer = 0.0
	hp -= amount
	if sfx:
		sfx.play_hit()
	_flash()
	hp_changed.emit(hp)
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3.ONE * base_scale * 0.85, 0.06)
	tw.tween_property(model, "scale", Vector3.ONE * base_scale, 0.1)
	if hp <= 0:
		dead = true
		var dt := create_tween()
		dt.tween_property(model, "rotation:x", -1.5, 0.5).set_trans(Tween.TRANS_BOUNCE)
		died.emit()

func _collect_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			_meshes.append(child)
		_collect_meshes(child)

func _is_local_pvp_player() -> bool:
	return not pvp_enabled or pvp_peer_id == multiplayer.get_unique_id()

func set_pvp_remote_state(pos: Vector3, rot_y: float, new_hp: int, is_dead: bool) -> void:
	pvp_target_position = pos
	pvp_target_rotation = rot_y
	set_pvp_health(new_hp, is_dead)

func set_pvp_health(new_hp: int, is_dead: bool) -> void:
	var old_hp := hp
	var was_dead := dead
	hp = new_hp
	dead = is_dead
	if hp < old_hp:
		_flash()
	hp_changed.emit(hp)
	if dead and not was_dead:
		attacking = false
		var dt := create_tween()
		dt.tween_property(model, "rotation:x", -1.5, 0.25)
	elif not dead:
		model.rotation.x = 0.0

func pvp_respawn(pos: Vector3, hp_value: int) -> void:
	global_position = pos
	pvp_target_position = pos
	velocity = Vector3.ZERO
	vy = 0.0
	jumps_left = max_jumps
	hp = hp_value
	dead = false
	invuln_timer = 1.2
	no_damage_time = 0.0
	regen_timer = 0.0
	attack_timer = 0.0
	beak_timer = 0.0
	baguette_timer = 0.0
	triple_timer = 0.0
	coffee_timer = 0.0
	giant_timer = 0.0
	base_scale = 1.0
	attacking = false
	model.rotation.x = 0.0
	model.scale = Vector3.ONE
	beak.visible = true
	beak.material_override = null
	_gold_mat = null
	_unflash()
	hp_changed.emit(hp)

func set_pvp_color(color: Color) -> void:
	for m in _meshes:
		if m.name.begins_with("Eye") or m.name.begins_with("Pupil"):
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		m.material_override = mat
		_pvp_base_mats[m] = mat

func play_pvp_attack_visual() -> void:
	if attacking:
		return
	attacking = true
	var tw := create_tween()
	tw.tween_property(right_arm, "rotation:x", -1.9, 0.08)
	tw.tween_property(right_arm, "rotation:x", 0.0, 0.18)
	tw.tween_callback(func() -> void: attacking = false)

func _flash() -> void:
	for m in _meshes:
		m.material_override = _flash_mat
	var tw := create_tween()
	tw.tween_callback(_unflash).set_delay(0.1)
	# en vue première personne le modèle est caché : le retour visuel
	# des dégâts passe par un flash rouge plein écran
	if first_person and _is_local_pvp_player():
		_flash_screen()

func _flash_screen() -> void:
	if _damage_overlay == null:
		var layer := CanvasLayer.new()
		layer.layer = 50
		_damage_overlay = ColorRect.new()
		_damage_overlay.color = Color(0.9, 0.05, 0.05, 0.0)
		_damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_damage_overlay)
		add_child(layer)
	_damage_overlay.color.a = 0.35
	var tw := create_tween()
	tw.tween_property(_damage_overlay, "color:a", 0.0, 0.45)

func _unflash() -> void:
	for m in _meshes:
		if m == beak and _gold_mat != null:
			m.material_override = _gold_mat
		elif pvp_enabled:
			m.material_override = _pvp_base_mats.get(m)
		else:
			m.material_override = null

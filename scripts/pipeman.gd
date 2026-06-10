class_name Pipeman
extends CharacterBody3D
## Bonhomme-tuyau. Plusieurs variantes : normal, coureur (rapide, fragile),
## tank (lent, costaud), cracheur (tire à distance) et boss (énorme).

signal killed(pos: Vector3, kind: int)

enum Kind { NORMAL, RUNNER, TANK, SHOOTER, BOSS }

const PipeShotScene := preload("res://scenes/pipe_shot.tscn")

const ARENA_HALF := 9.8
const BASE_ATTACK_RANGE := 1.25
const ATTACK_COOLDOWN := 1.5

var kind := Kind.NORMAL
var hp := 2
var max_hp_value := 2
var speed := 2.2
var damage := 1
var attack_range := BASE_ATTACK_RANGE
var scale_factor := 1.0
var attack_timer := 0.0
var shoot_timer := 2.0
var ring_timer := 4.0
var anim_time := 0.0
var swing := 0.0
var lunging := false
var dying := false
var sfx: Node = null
var player: CharacterBody3D = null

var _meshes: Array[MeshInstance3D] = []
var _tint_mats := {}
var _flash_mat: StandardMaterial3D

@onready var model: Node3D = $Model
@onready var arm_l: Node3D = $Model/ArmPivotL
@onready var arm_r: Node3D = $Model/ArmPivotR
@onready var leg_l: Node3D = $Model/LegPivotL
@onready var leg_r: Node3D = $Model/LegPivotR
@onready var col: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	_collect_meshes(model)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1, 1, 1)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(0.9, 0.9, 0.9)

func setup(k: int) -> void:
	kind = k
	match k:
		Kind.RUNNER:
			hp = 1
			speed = randf_range(3.4, 4.0)
			damage = 1
			scale_factor = 0.72
			_tint(Color(0.62, 0.78, 0.2))
		Kind.TANK:
			hp = 6
			speed = randf_range(1.1, 1.4)
			damage = 2
			scale_factor = 1.45
			_tint(Color(0.16, 0.4, 0.42))
		Kind.SHOOTER:
			hp = 2
			speed = randf_range(1.5, 1.9)
			damage = 1
			scale_factor = 0.95
			shoot_timer = randf_range(1.0, 2.0)
			_tint(Color(0.52, 0.32, 0.62))
		Kind.BOSS:
			hp = 25
			speed = 1.5
			damage = 2
			scale_factor = 2.6
			_tint(Color(0.72, 0.18, 0.15))
		_:
			hp = 2
			speed = randf_range(1.8, 2.5)
			damage = 1
			scale_factor = 1.0
	max_hp_value = hp
	attack_range = BASE_ATTACK_RANGE * maxf(scale_factor, 1.0)
	var cap: CapsuleShape3D = col.shape.duplicate()
	cap.radius *= scale_factor
	cap.height *= scale_factor
	col.shape = cap
	col.position.y *= scale_factor
	# pop d'apparition
	model.scale = Vector3.ONE * scale_factor * 0.05
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3.ONE * scale_factor, 0.25)

func _physics_process(delta: float) -> void:
	if dying or player == null or not is_instance_valid(player):
		return
	attack_timer = maxf(attack_timer - delta, 0.0)
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 8.0 * delta)
	var move_dir := Vector3.ZERO
	if player.dead:
		pass
	elif kind == Kind.SHOOTER:
		shoot_timer -= delta
		if dist > 6.5:
			move_dir = to.normalized()
		elif dist < 3.5:
			move_dir = -to.normalized()
		if shoot_timer <= 0.0 and dist < 10.0:
			shoot_timer = 2.4
			_shoot(to.normalized())
	else:
		if kind == Kind.BOSS:
			ring_timer -= delta
			if ring_timer <= 0.0:
				ring_timer = 5.0
				_ring_attack()
		if dist > attack_range:
			move_dir = to.normalized()
		elif attack_timer <= 0.0:
			attack_timer = ATTACK_COOLDOWN
			_attack()
	if move_dir != Vector3.ZERO:
		velocity = move_dir * speed
		move_and_slide()
		position.x = clampf(position.x, -ARENA_HALF, ARENA_HALF)
		position.z = clampf(position.z, -ARENA_HALF, ARENA_HALF)
		position.y = 0.0
		anim_time += delta * 8.0
		swing = sin(anim_time) * 0.5
	else:
		velocity = Vector3.ZERO
		swing = lerpf(swing, 0.0, 10.0 * delta)
	_apply_anim()

func _apply_anim() -> void:
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	arm_l.rotation.x = -swing
	if not lunging:
		arm_r.rotation.x = swing
	model.position.y = absf(swing) * 0.08 * scale_factor

func _attack() -> void:
	lunging = true
	if sfx:
		sfx.play_flap()
	var tw := create_tween()
	tw.tween_property(arm_r, "rotation:x", -1.8, 0.12)
	tw.parallel().tween_property(model, "position:z", 0.35 * scale_factor, 0.12)
	tw.tween_callback(_strike)
	tw.tween_property(arm_r, "rotation:x", 0.0, 0.18)
	tw.parallel().tween_property(model, "position:z", 0.0, 0.18)
	tw.tween_callback(func() -> void: lunging = false)

func _strike() -> void:
	if dying or not is_instance_valid(player) or player.dead:
		return
	if player.position.y > 0.6:
		return  # le joueur a sauté : coup esquivé
	var to := player.global_position - global_position
	to.y = 0.0
	if to.length() <= attack_range + 0.35 * scale_factor:
		player.take_damage(damage)

func _shoot(dir: Vector3) -> void:
	lunging = true
	if sfx:
		sfx.play_flap()
	var tw := create_tween()
	tw.tween_property(arm_r, "rotation:x", -2.2, 0.12)
	tw.tween_property(arm_r, "rotation:x", 0.0, 0.2)
	tw.tween_callback(func() -> void: lunging = false)
	_spawn_shot(dir)

func _ring_attack() -> void:
	if sfx:
		sfx.play_flap()
	for i in 8:
		var ang := TAU * i / 8.0
		_spawn_shot(Vector3(sin(ang), 0.0, cos(ang)))

func _spawn_shot(dir: Vector3) -> void:
	var shot: Area3D = PipeShotScene.instantiate()
	get_parent().add_child(shot)
	shot.direction = dir
	shot.damage = damage
	shot.global_position = global_position + dir * 0.6 * scale_factor + Vector3(0, 0.55, 0)

func take_damage(amount: int, knock_dir: Vector3) -> void:
	if dying:
		return
	hp -= amount
	global_position += knock_dir * 0.5 / scale_factor
	_flash()
	if hp <= 0:
		dying = true
		killed.emit(global_position, kind)
		var tw := create_tween()
		tw.tween_property(model, "scale", Vector3.ONE * 0.05, 0.18)
		tw.tween_callback(queue_free)
	else:
		var tw := create_tween()
		tw.tween_property(model, "scale", Vector3.ONE * scale_factor * 0.85, 0.06)
		tw.tween_property(model, "scale", Vector3.ONE * scale_factor, 0.1)

func _collect_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			_meshes.append(child)
		_collect_meshes(child)

func _tint(color: Color) -> void:
	for m in _meshes:
		if m.name.begins_with("Eye") or m.name.begins_with("Pupil"):
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		m.material_override = mat
		_tint_mats[m] = mat

func _flash() -> void:
	for m in _meshes:
		m.material_override = _flash_mat
	var tw := create_tween()
	tw.tween_callback(_unflash).set_delay(0.08)

func _unflash() -> void:
	for m in _meshes:
		m.material_override = _tint_mats.get(m)

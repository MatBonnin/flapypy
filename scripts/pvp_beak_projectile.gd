extends Area3D
## Projectile PvP : visuel sur tous les pairs, degats uniquement cote hote.

const SPEED := 11.0
const LIFETIME := 1.6

var projectile_id := 0
var owner_id := 0
var direction := Vector3.FORWARD
var damage := 2
var pvp_arena: Node = null
var life := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * SPEED * delta
	rotate_object_local(Vector3(0, 0, 1), 18.0 * delta)
	life += delta
	if life > LIFETIME:
		if multiplayer.is_server() and pvp_arena != null:
			pvp_arena.server_pvp_beak_expired(projectile_id)
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server() or pvp_arena == null:
		return
	if body.is_in_group("pvp_players") and body.pvp_peer_id != owner_id:
		pvp_arena.server_pvp_beak_hit(projectile_id, owner_id, body.pvp_peer_id, damage)
	elif body is StaticBody3D:
		pvp_arena.server_pvp_beak_expired(projectile_id)
	queue_free()

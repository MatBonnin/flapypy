extends Area3D
## Projectile des tuyaux cracheurs : vole bas et tout droit,
## sauter par-dessus permet de l'esquiver.

const SPEED := 7.0
const LIFETIME := 3.0

var direction := Vector3.FORWARD
var damage := 1
var life := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * SPEED * delta
	rotation.y += 8.0 * delta
	life += delta
	if life > LIFETIME:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.take_damage(damage)
	queue_free()

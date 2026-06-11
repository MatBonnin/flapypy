extends Area3D
## Le bec lancé par l'oiseau : file tout droit en tournant sur lui-même,
## blesse le premier ennemi touché et disparaît sur les obstacles.

const SPEED := 11.0
const LIFETIME := 1.6

var direction := Vector3.FORWARD
var damage := 2
var speed_mult := 1.0
var life := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * SPEED * speed_mult * delta
	rotate_object_local(Vector3(0, 0, 1), 18.0 * speed_mult * delta)
	life += delta
	if life > LIFETIME:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("enemies"):
		body.take_damage(damage, direction)
	queue_free()

extends Area3D

const GRAVITY := 25.0
const FLAP_VELOCITY := 8.0
const MAX_FALL_SPEED := 14.0
const CEILING_Y := 12.0
const RADIUS := 0.45

var velocity := 0.0
var active := false

func _physics_process(delta: float) -> void:
	if not active:
		return
	velocity = maxf(velocity - GRAVITY * delta, -MAX_FALL_SPEED)
	position.y += velocity * delta
	if position.y > CEILING_Y:
		position.y = CEILING_Y
		velocity = minf(velocity, 0.0)
	rotation.z = clampf(velocity * 0.06, -0.9, 0.45)

func flap() -> void:
	velocity = FLAP_VELOCITY

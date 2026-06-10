extends Area2D

const GRAVITY := 1800.0
const FLAP_VELOCITY := -520.0
const MAX_FALL_SPEED := 900.0
const RADIUS := 15.0

var velocity := 0.0
var active := false

func _physics_process(delta: float) -> void:
	if not active:
		return
	velocity = minf(velocity + GRAVITY * delta, MAX_FALL_SPEED)
	position.y += velocity * delta
	if position.y < RADIUS:
		position.y = RADIUS
		velocity = maxf(velocity, 0.0)
	rotation = clampf(velocity / 900.0, -0.4, 1.2)

func flap() -> void:
	velocity = FLAP_VELOCITY

func _draw() -> void:
	# Aile (derrière le corps)
	draw_circle(Vector2(-7.0, 4.0), 7.0, Color("d9a426"))
	# Corps
	draw_circle(Vector2.ZERO, RADIUS, Color("f7d046"))
	# Bec
	draw_colored_polygon(PackedVector2Array([
		Vector2(11.0, 1.0), Vector2(23.0, 6.0), Vector2(11.0, 10.0),
	]), Color("e8842c"))
	# Oeil
	draw_circle(Vector2(6.0, -5.0), 4.5, Color.WHITE)
	draw_circle(Vector2(7.5, -5.0), 2.2, Color.BLACK)

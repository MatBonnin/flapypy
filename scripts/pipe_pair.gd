extends Node2D

const GAP_SIZE := 190.0
const SPEED := 200.0

var stopped := false

func setup(gap_center: float) -> void:
	$TopPipe.position.y = gap_center - GAP_SIZE / 2.0
	$BottomPipe.position.y = gap_center + GAP_SIZE / 2.0

func stop() -> void:
	stopped = true

func _process(delta: float) -> void:
	if stopped:
		return
	position.x -= SPEED * delta
	if position.x < -120.0:
		queue_free()

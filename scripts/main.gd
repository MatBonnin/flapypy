extends Node2D

const PipePairScene := preload("res://scenes/pipe_pair.tscn")
const SAVE_PATH := "user://highscore.cfg"

const GROUND_Y := 720.0
const GAP_CENTER_MIN := 170.0
const GAP_CENTER_MAX := 550.0
const BIRD_START := Vector2(130.0, 360.0)
const RESTART_DELAY_MS := 600

enum State { READY, PLAYING, DEAD }

var state := State.READY
var score := 0
var best := 0
var death_time := 0
var hover_time := 0.0

@onready var bird: Area2D = $Bird
@onready var pipes: Node2D = $Pipes
@onready var spawn_timer: Timer = $PipeSpawnTimer
@onready var score_label: Label = $UI/ScoreLabel
@onready var message_label: Label = $UI/MessageLabel
@onready var sfx: Node = $Sfx

func _ready() -> void:
	best = _load_best()
	bird.area_entered.connect(_on_bird_area_entered)
	spawn_timer.timeout.connect(_spawn_pipe_pair)
	score_label.text = "0"
	message_label.text = "Espace ou clic pour voler\nRecord : %d" % best

func _unhandled_input(event: InputEvent) -> void:
	if not _is_flap_input(event):
		return
	match state:
		State.READY:
			_start_game()
		State.PLAYING:
			bird.flap()
			sfx.play_flap()
		State.DEAD:
			if Time.get_ticks_msec() - death_time > RESTART_DELAY_MS:
				get_tree().reload_current_scene()

func _is_flap_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return event.pressed
	return event.is_action_pressed("ui_accept") and not event.is_echo()

func _process(delta: float) -> void:
	if state == State.READY:
		hover_time += delta
		bird.position.y = BIRD_START.y + sin(hover_time * 4.0) * 12.0
	elif bird.position.y > GROUND_Y - bird.RADIUS:
		bird.position.y = GROUND_Y - bird.RADIUS
		bird.active = false
		if state == State.PLAYING:
			_die()

func _start_game() -> void:
	state = State.PLAYING
	message_label.text = ""
	bird.active = true
	bird.flap()
	sfx.play_flap()
	_spawn_pipe_pair()
	spawn_timer.start()

func _spawn_pipe_pair() -> void:
	var pair := PipePairScene.instantiate()
	pair.position = Vector2(560.0, 0.0)
	pair.setup(randf_range(GAP_CENTER_MIN, GAP_CENTER_MAX))
	pipes.add_child(pair)

func _on_bird_area_entered(area: Area2D) -> void:
	if state != State.PLAYING:
		return
	if area.is_in_group("hazard"):
		_die()
	elif area.is_in_group("score"):
		score += 1
		score_label.text = str(score)
		sfx.play_score()
		area.set_deferred("monitorable", false)

func _die() -> void:
	state = State.DEAD
	death_time = Time.get_ticks_msec()
	spawn_timer.stop()
	for pipe in pipes.get_children():
		pipe.stop()
	sfx.play_hit()
	if score > best:
		best = score
		_save_best()
	message_label.text = "Game Over\nScore : %d   Record : %d\nAppuie pour rejouer" % [score, best]

func _load_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return int(cfg.get_value("game", "best", 0))
	return 0

func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "best", best)
	cfg.save(SAVE_PATH)

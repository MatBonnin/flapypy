extends Node
## Effets sonores : fichiers audio CC0 (packs Kenney, kenney.nl), joués avec
## une variation de hauteur aléatoire pour éviter la répétition.

const SOUND_DIR := "res://assets/sounds/"

## Chaque banque regroupe des variantes d'un même effet ; une variante est
## tirée au hasard à chaque lecture.
const BANKS := {
	"flap": ["cloth1.ogg", "cloth2.ogg", "cloth3.ogg", "cloth4.ogg"],
	"swing": ["knifeSlice.ogg", "knifeSlice2.ogg"],
	"hit": [
		"impactPunch_medium_000.ogg", "impactPunch_medium_001.ogg",
		"impactPunch_medium_002.ogg", "impactPunch_medium_003.ogg",
		"impactPunch_medium_004.ogg",
	],
	"hurt": [
		"impactPunch_heavy_000.ogg", "impactPunch_heavy_001.ogg",
		"impactPunch_heavy_002.ogg", "impactPunch_heavy_003.ogg",
		"impactPunch_heavy_004.ogg",
	],
	"step": [
		"footstep_grass_000.ogg", "footstep_grass_001.ogg",
		"footstep_grass_002.ogg", "footstep_grass_003.ogg",
		"footstep_grass_004.ogg",
	],
	"throw": ["phaserUp2.ogg"],
	"charge_full": ["confirmation_001.ogg"],
	"score": ["pluck_001.ogg", "pluck_002.ogg"],
	"pickup_heart": ["powerUp4.ogg"],
	"pickup_baguette": ["drawKnife1.ogg"],
	"pickup_gold": ["handleCoins.ogg"],
	"pickup_coffee": ["pepSound3.ogg"],
	"pickup_mushroom": ["powerUp8.ogg"],
	"upgrade": ["threeTone1.ogg"],
	"win": ["powerUp1.ogg"],
	"lose": ["lowDown.ogg"],
	"kill": ["impactBell_heavy_002.ogg"],
	"shoot": ["laser6.ogg"],
	"morph": ["phaseJump3.ogg"],
	"click": ["click_002.ogg"],
}

## Volume par banque (dB) pour équilibrer les sons entre eux.
const VOLUMES := {
	"flap": -8.0,
	"swing": -6.0,
	"step": -16.0,
	"hit": -4.0,
	"hurt": -4.0,
	"throw": -8.0,
	"shoot": -10.0,
	"score": -6.0,
	"click": -6.0,
	"kill": -6.0,
}

var _banks := {}

func _ready() -> void:
	for bank_name in BANKS:
		var streams: Array[AudioStream] = []
		for file in BANKS[bank_name]:
			var stream: AudioStream = load(SOUND_DIR + file)
			if stream != null:
				streams.append(stream)
		if streams.is_empty():
			continue
		var player := AudioStreamPlayer.new()
		player.volume_db = float(VOLUMES.get(bank_name, 0.0))
		add_child(player)
		_banks[bank_name] = {"player": player, "streams": streams}

func play(bank_name: String, pitch_min := 0.92, pitch_max := 1.08) -> void:
	if not _banks.has(bank_name):
		return
	var entry: Dictionary = _banks[bank_name]
	var player: AudioStreamPlayer = entry["player"]
	player.stream = entry["streams"].pick_random()
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.play()

# --- API historique ---

func play_flap() -> void:
	play("flap", 0.85, 1.2)

func play_score() -> void:
	play("score", 0.95, 1.2)

func play_hit() -> void:
	play("hit", 0.85, 1.2)

# --- Nouveaux effets ---

func play_swing() -> void:
	play("swing", 0.9, 1.15)

func play_hurt() -> void:
	play("hurt", 0.85, 1.1)

func play_step() -> void:
	play("step", 0.85, 1.2)

func play_throw() -> void:
	play("throw", 0.95, 1.1)

func play_charge_full() -> void:
	play("charge_full", 1.0, 1.0)

func play_pickup(bank_name: String) -> void:
	play(bank_name, 0.98, 1.05)

func play_upgrade() -> void:
	play("upgrade", 1.0, 1.0)

func play_win() -> void:
	play("win", 1.0, 1.0)

func play_lose() -> void:
	play("lose", 0.95, 1.0)

func play_kill() -> void:
	play("kill", 0.95, 1.1)

func play_shoot() -> void:
	play("shoot", 0.9, 1.15)

func play_morph() -> void:
	play("morph", 0.95, 1.1)

func play_click() -> void:
	play("click", 0.95, 1.1)

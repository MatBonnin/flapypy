extends Node
## Petits effets sonores générés procéduralement (aucun fichier audio requis).

const MIX_RATE := 22050

var _flap := AudioStreamPlayer.new()
var _score := AudioStreamPlayer.new()
var _hit := AudioStreamPlayer.new()

func _ready() -> void:
	_flap.stream = _make_sweep(350.0, 750.0, 0.10)
	_score.stream = _make_sweep(900.0, 1300.0, 0.09)
	_hit.stream = _make_noise(0.18)
	for player in [_flap, _score, _hit]:
		add_child(player)

func play_flap() -> void:
	_flap.pitch_scale = randf_range(0.85, 1.2)
	_flap.play()

func play_score() -> void:
	_score.pitch_scale = randf_range(0.9, 1.15)
	_score.play()

func play_hit() -> void:
	_hit.pitch_scale = randf_range(0.8, 1.25)
	_hit.play()

func _make_sweep(from_hz: float, to_hz: float, duration: float) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		phase += TAU * lerpf(from_hz, to_hz, t) / MIX_RATE
		var sample := sin(phase) * (1.0 - t) * 11000.0
		data.encode_s16(i * 2, int(sample))
	return _make_wav(data)

func _make_noise(duration: float) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / count
		var sample := randf_range(-1.0, 1.0) * (1.0 - t) * 9000.0
		data.encode_s16(i * 2, int(sample))
	return _make_wav(data)

func _make_wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	return wav

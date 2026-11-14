class_name Calls
extends Node3D

## Clips from scripts/animals.py (game/audio/animals/sources.json). Calls stay rare and quiet under the music.

## `gap` seconds; `level` dB at UNIT metres, the conures' contact call softest as it is their loudest. UNIT 2 m with
## levels 6 dB lower put an animal 5 to 10 m off 18 to 28 dB under the music, unheard.
const CALLS := {
	"murmur": {"clips": 8, "gap": 4.0, "level": -8.0},
	"grind": {"clips": 4, "gap": 3.0, "level": -10.0},
	"click": {"clips": 4, "gap": 2.5, "level": -12.0},
	"chatter": {"clips": 5, "gap": 8.0, "level": -8.0},
	"chirp": {"clips": 8, "gap": 6.0, "level": -9.0},
	"contact": {"clips": 4, "gap": 15.0, "level": -15.0},
	"quack": {"clips": 4, "gap": 8.0, "level": -3.0},
	"peep": {"clips": 4, "gap": 12.0, "level": -10.0},
	"bleat": {"clips": 10, "gap": 14.0, "level": -4.0},
	"mew": {"clips": 6, "gap": 12.0, "level": -6.0},
	"yip": {"clips": 4, "gap": 20.0, "level": -9.0},
	"croak": {"clips": 11, "gap": 2.5, "level": -11.0},
	"hoot": {"clips": 11, "gap": 9.0, "level": -9.0},
	"chitter": {"clips": 10, "gap": 6.0, "level": -13.0},
	"rustle": {"clips": 8, "gap": 2.0, "level": -16.0},
}
const SOFT := ["murmur", "grind", "click", "rustle"]
## Quack and peep are here because ducks fed from a hand over the pond are that near.
const CLOSE := ["murmur", "grind", "click", "quack", "peep"]
const ANY_GAP := 3.0
const UNIT := 6.0
## dB above CUTOFF Hz; the clips are already rolled off there.
const FAR_SHELF := -12.0
const CUTOFF := 3000.0
const NEAR := 2.5
const VOICES := 6

var viewer: Node3D
var rng := RandomNumberGenerator.new()
var _clips := {}
var _last := {}
var _since := {}
var _since_any := INF
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
## Per kind [calls played, metres from the head of the last or -1], for the play log.
var played := {}


func _init(eyes: Node3D, seed: int) -> void:
	viewer = eyes
	rng.seed = seed
	for kind in CALLS:
		_clips[kind] = []
		for i in CALLS[kind].clips:
			_clips[kind].append(load("res://audio/animals/%s%d.ogg" % [kind, i]))
		_since[kind] = INF
		_last[kind] = -1
	for i in VOICES:
		var v := AudioStreamPlayer3D.new()
		v.unit_size = UNIT
		v.max_db = 0.0
		v.max_distance = 45.0
		v.attenuation_filter_cutoff_hz = CUTOFF
		v.attenuation_filter_db = FAR_SHELF
		_voices.append(v)
		add_child(v)


func tick(delta: float) -> void:
	_since_any += delta
	for kind in _since:
		_since[kind] += delta


func call_out(kind: String, at: Vector3) -> bool:
	var soft := kind in SOFT
	if _since[kind] < CALLS[kind].gap or (_since_any < ANY_GAP and not soft):
		return false
	_since[kind] = 0.0
	if not soft:
		_since_any = 0.0
	var options: Array = _clips[kind]
	var pick := rng.randi() % (options.size() - 1)
	if pick >= _last[kind]:
		pick += 1
	_last[kind] = pick
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	v.stream = options[pick]
	v.volume_db = CALLS[kind].level + rng.randf_range(-2.0, 1.0)
	v.pitch_scale = rng.randf_range(0.93, 1.06)
	v.position = at
	v.play()
	var heard: Array = played.get_or_add(kind, [0, 0.0])
	heard[0] += 1
	var off := _from_head(at)
	heard[1] = snappedf(off, 0.1) if is_finite(off) else -1.0
	return true


func now_and_then(kind: String, at: Vector3, every: float, delta: float) -> bool:
	if rng.randf() >= delta / every or (near_head(at) and kind not in CLOSE):
		return false
	return call_out(kind, at)


func near_head(at: Vector3) -> bool:
	return _from_head(at) < NEAR


func _from_head(at: Vector3) -> float:
	return viewer.global_position.distance_to(at) if viewer != null and viewer.is_inside_tree() else INF

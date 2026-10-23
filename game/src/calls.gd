class_name Calls
extends Node3D

## The animals' voices: short recordings (scripts/animals.py, game/audio/animals/sources.json) played at the
## animal that calls. Calls stay rare and quiet under the music: each kind waits its own while between calls,
## any two calls but the soft ones are a little apart, no clip plays twice running, and an animal near the head makes
## only its close calls.

## Clips per call, and the least time between two calls of it.
const CLIPS := {
	"murmur": 8, "grind": 4, "click": 4, "chatter": 5, "chirp": 8, "contact": 4,
	"quack": 4, "peep": 4, "bleat": 10, "mew": 6, "yip": 4,
}
const GAP := {
	"murmur": 4.0, "grind": 3.0, "click": 2.5, "chatter": 8.0, "chirp": 6.0, "contact": 15.0,
	"quack": 8.0, "peep": 12.0, "bleat": 14.0, "mew": 12.0, "yip": 20.0,
}
## Level at UNIT metres, before the distance falls it off: the conures' contact call softest, as it is their
## loudest. At 2 m and 6 dB lower, an animal 5 to 10 m off called 18 to 28 dB under the music, which no one heard.
const LEVEL := {
	"murmur": -8.0, "grind": -10.0, "click": -12.0, "chatter": -8.0, "chirp": -9.0, "contact": -15.0,
	"quack": -3.0, "peep": -10.0, "bleat": -4.0, "mew": -6.0, "yip": -9.0,
}
## Calls quiet enough that no other call waits on them: a conure on the hand or watching a face up close murmurs and
## works its beak.
const SOFT := ["murmur", "grind", "click"]
## Calls an animal still makes beside the head: the soft ones, and the ducks' low quacks and peeps, as a family fed from
## a hand held over the pond is that near.
const CLOSE := ["murmur", "grind", "click", "quack", "peep"]
const ANY_GAP := 3.0
const UNIT := 6.0
## How much the distance takes off above CUTOFF Hz; the clips are already rolled off there.
const FAR_SHELF := -12.0
const CUTOFF := 3000.0
## An animal nearer the head than this makes no call of its own but its CLOSE ones, and those its doings bring.
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
## Per kind, the calls played and how far from the head the last was, for the play log.
var played := {}


func _init(eyes: Node3D, seed: int) -> void:
	viewer = eyes
	rng.seed = seed
	for kind in CLIPS:
		_clips[kind] = []
		for i in CLIPS[kind]:
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


## `kind` from `at` now, unless one was too lately. True if it called.
func call_out(kind: String, at: Vector3) -> bool:
	var soft := kind in SOFT
	if _since[kind] < GAP[kind] or (_since_any < ANY_GAP and not soft):
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
	v.volume_db = LEVEL[kind] + rng.randf_range(-2.0, 1.0)
	v.pitch_scale = rng.randf_range(0.93, 1.06)
	v.position = at
	v.play()
	var heard: Array = played.get_or_add(kind, [0, 0.0])
	heard[0] += 1
	heard[1] = snappedf(viewer.global_position.distance_to(at), 0.1) if viewer != null and viewer.is_inside_tree() else -1.0
	return true


## `kind` from `at` about once every `every` seconds of an animal's doing something, while the head keeps its
## distance.
func now_and_then(kind: String, at: Vector3, every: float, delta: float) -> bool:
	if rng.randf() >= delta / every or (calm(at) and kind not in CLOSE):
		return false
	return call_out(kind, at)


func calm(at: Vector3) -> bool:
	return viewer != null and viewer.is_inside_tree() and viewer.global_position.distance_to(at) < NEAR

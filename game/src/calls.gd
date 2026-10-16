class_name Calls
extends Node3D

## The animals' voices: short recordings (scripts/animals.py, game/audio/animals/sources.json) played at the
## animal that calls. Calls stay rare and quiet under the music: each kind waits its own while between calls,
## any two calls are a little apart, no clip plays twice running, and an animal near the head stays calm.

## Clips per call, and the least time between two calls of it.
const CLIPS := {"chirp": 6, "chatter": 4, "quack": 4, "peep": 4, "bleat": 10}
const GAP := {"chirp": 8.0, "chatter": 10.0, "quack": 8.0, "peep": 12.0, "bleat": 14.0}
## Level at UNIT metres, before the distance falls it off: the conures' softest, as their calls are the highest.
const LEVEL := {"chirp": -15.0, "chatter": -14.0, "quack": -9.0, "peep": -16.0, "bleat": -10.0}
const ANY_GAP := 3.0
const UNIT := 2.0
## An animal nearer the head than this makes no call of its own, only those its doings bring.
const CALM := 2.5
const VOICES := 4

var viewer: Node3D
var rng := RandomNumberGenerator.new()
var _clips := {}
var _last := {}
var _since := {}
var _since_any := INF
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0


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
		v.attenuation_filter_cutoff_hz = 3000.0
		_voices.append(v)
		add_child(v)


func tick(delta: float) -> void:
	_since_any += delta
	for kind in _since:
		_since[kind] += delta


## `kind` from `at` now, unless one was too lately. True if it called.
func call_out(kind: String, at: Vector3) -> bool:
	if _since[kind] < GAP[kind] or _since_any < ANY_GAP:
		return false
	_since[kind] = 0.0
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
	return true


## `kind` from `at` about once every `every` seconds of an animal's doing something, while the head keeps its
## distance.
func now_and_then(kind: String, at: Vector3, every: float, delta: float) -> bool:
	if rng.randf() >= delta / every or calm(at):
		return false
	return call_out(kind, at)


func calm(at: Vector3) -> bool:
	return viewer != null and viewer.is_inside_tree() and viewer.global_position.distance_to(at) < CALM

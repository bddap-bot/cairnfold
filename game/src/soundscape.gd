class_name Soundscape
extends Node

## Music and the meadow, pre-rendered by scripts/compose.py and mixed on the audio thread; this node sets layer volumes
## and places the birds. The wind turns with the head; the birds call one at a time from out in the meadow, by day a
## song and at night an owl, and crickets fill the night. Both fall away with the head's height over the ground and go
## under water. What actions sound like is Cues'.

const STEMS := ["bed", "lead", "orn"]
## Layer gains in dB while idle and while building: building keeps the bed and lets the tune recede.
const IDLE := [0.0, 0.0, 0.0]
const BUILDING := [-3.0, -14.0, -40.0]
const QUIET_AFTER := 4.0
## Sun elevations in degrees over which the songbirds wake at dawn; the crickets start up by Daylight.DUSK.
const DAWN := Vector2(-10.0, 2.0)
## Heights of the head over the ground in metres over which the birds and crickets fall silent.
const ALOFT := Vector2(6.0, 25.0)
const SONGS := 8
const HOOTS := 3
## Seconds between calls at full level, on average; fewer as the level falls. An owl calls far less often.
const SONG_EVERY := 5.0
const HOOT_EVERY := 25.0
## Where a call comes from: how far from the head across the ground, and how high over it.
const AWAY := Vector2(10.0, 30.0)
const PERCH := Vector2(2.0, 7.0)
const BIRD_DB := -24.0
const NIGHT_DB := -28.0
## How fast the night bed follows its level, per second, so surfacing from a pond brings the crickets back gently.
const NIGHT_EASE := 1.0
const UNIT := 6.0

var tool: WallTool
var rig: Rig
var look: Look
var night := AudioStreamPlayer.new()
var rng := RandomNumberGenerator.new()
var _songs: Array[AudioStream] = []
var _hoots: Array[AudioStream] = []
var bird := AudioStreamPlayer3D.new()
var _dark := 0.0
var music := AudioStreamPlayer.new()
var meadow := AudioStreamPlayer.new()
var sections: Array[AudioStreamSynchronized] = []
var gains := IDLE.duplicate()
var since_edit := INF
var _offsets: Array[float] = []


func _init(builder: WallTool, flora_tool: FloraTool, player: Rig, light: Look, seed: int) -> void:
	tool = builder
	rig = player
	look = light
	rng.seed = seed
	tool.built.connect(_on_edit)
	flora_tool.planted.connect(_on_edit)
	var list := AudioStreamPlaylist.new()
	list.loop = true
	list.fade_time = 3.0
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://audio/music.json"))
	list.stream_count = manifest.size()
	var at := 0.0
	for i in manifest.size():
		var s: Dictionary = manifest[i]
		var sync := AudioStreamSynchronized.new()
		sync.stream_count = STEMS.size()
		for j in STEMS.size():
			var ogg: AudioStreamOggVorbis = load("res://audio/music/%s.%s.ogg" % [s.name, STEMS[j]])
			ogg.bpm = s.bpm
			ogg.beat_count = int(s.beats)
			sync.set_sync_stream(j, ogg)
		list.set_list_stream(i, sync)
		sections.append(sync)
		_offsets.append(at)
		at += s.beats * 60.0 / s.bpm
	music.stream = list
	music.volume_db = -5.0
	add_child(music)
	var bed: AudioStreamOggVorbis = load("res://audio/meadow.ogg")
	bed.loop = true
	meadow.stream = bed
	meadow.volume_db = -6.0
	add_child(meadow)
	var crickets: AudioStreamOggVorbis = load("res://audio/night.ogg")
	crickets.loop = true
	night.stream = crickets
	night.volume_db = -80.0
	add_child(night)
	for i in SONGS:
		_songs.append(load("res://audio/birds/song%d.ogg" % i))
	for i in HOOTS:
		_hoots.append(load("res://audio/birds/hoot%d.ogg" % i))
	bird.unit_size = UNIT
	bird.max_db = 0.0
	bird.max_distance = 60.0
	add_child(bird)


func _ready() -> void:
	play_from(randi() % _offsets.size())
	meadow.play(randf() * meadow.stream.get_length())
	night.play(randf() * night.stream.get_length())


func play_from(section: int) -> void:
	music.play(_offsets[section])


func _process(delta: float) -> void:
	since_edit += delta
	var building := tool.busy() or since_edit < QUIET_AFTER
	var target: Array = BUILDING if building else IDLE
	for j in STEMS.size():
		var rate := 1.5 if target[j] < gains[j] else 0.25
		var g: float = lerpf(gains[j], target[j], 1.0 - exp(-rate * delta))
		if absf(g - gains[j]) > 0.01:
			gains[j] = g
			for s in sections:
				s.set_sync_stream_volume(j, g)
	_meadow(delta)


func _meadow(delta: float) -> void:
	var head := rig.head.global_position
	var elevation := Daylight.elevation(look.time)
	var above := head.y - Terrain.height_at(head.x, head.z)
	var dark := night_level(elevation, above, rig.under)
	_dark = move_toward(_dark, dark, NIGHT_EASE * delta)
	night.volume_db = NIGHT_DB + linear_to_db(maxf(_dark, 0.001))
	night.stream_paused = _dark < 0.001
	if bird.playing:
		return
	var day := song_level(elevation, above, rig.under)
	if rng.randf() < delta * day / SONG_EVERY:
		_call(_songs, head, day)
	elif rng.randf() < delta * dark / HOOT_EVERY:
		_call(_hoots, head, dark)


## How fully the songbirds sing with the sun `elevation` degrees up and the head `above` metres over the ground.
static func song_level(elevation: float, above: float, under: bool) -> float:
	return 0.0 if under else smoothstep(DAWN.x, DAWN.y, elevation) * _low(above)


## How fully the night sounds, the crickets and the owl.
static func night_level(elevation: float, above: float, under: bool) -> float:
	return 0.0 if under else Daylight.night(elevation) * _low(above)


static func _low(above: float) -> float:
	return 1.0 - smoothstep(ALOFT.x, ALOFT.y, above)


func _call(clips: Array[AudioStream], head: Vector3, level: float) -> void:
	bird.stream = clips[rng.randi() % clips.size()]
	bird.volume_db = BIRD_DB + linear_to_db(level) + rng.randf_range(-3.0, 1.0)
	bird.pitch_scale = rng.randf_range(0.94, 1.06)
	bird.position = perch(head, rng)
	bird.play()


## Where a bird calls from, about a head at `head`.
static func perch(head: Vector3, from: RandomNumberGenerator) -> Vector3:
	var way := Vector2.from_angle(from.randf() * TAU) * from.randf_range(AWAY.x, AWAY.y)
	var at := Vector3(head.x + way.x, 0.0, head.z + way.y)
	at.y = Terrain.height_at(at.x, at.z) + from.randf_range(PERCH.x, PERCH.y)
	return at


func _on_edit() -> void:
	since_edit = 0.0

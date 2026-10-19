class_name Soundscape
extends Node

## Music, meadow bed and building sounds. Everything is pre-rendered by scripts/compose.py and
## mixed on the audio thread; this node only sets layer volumes and starts one-shots.

const STEMS := ["bed", "lead", "orn"]
## Layer gains in dB while idle and while building: building keeps the bed and lets the tune recede.
const IDLE := [0.0, 0.0, 0.0]
const BUILDING := [-3.0, -14.0, -40.0]
const QUIET_AFTER := 4.0
const FX := {"stone": 5, "settle": 3, "arch": 2, "crumble": 2, "dip": 3, "fill": 2, "plop": 3, "nibble": 4}
const VOICES := 10

var tool: WallTool
var music := AudioStreamPlayer.new()
var meadow := AudioStreamPlayer.new()
var sections: Array[AudioStreamSynchronized] = []
var gains := IDLE.duplicate()
var since_edit := INF
var _fx := {}
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _offsets: Array[float] = []


func _init(builder: WallTool, flora_tool: FloraTool, water: Water) -> void:
	tool = builder
	tool.built.connect(_on_built)
	flora_tool.planted.connect(_on_planted)
	water.splashed.connect(_play)
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
	for kind in FX:
		_fx[kind] = []
		for i in FX[kind]:
			_fx[kind].append(load("res://audio/fx/%s%d.ogg" % [kind, i]))
	for i in VOICES:
		var v := AudioStreamPlayer3D.new()
		v.unit_size = 3.0
		v.max_distance = 80.0
		v.volume_db = -4.0
		_voices.append(v)
		add_child(v)


func _ready() -> void:
	play_from(randi() % _offsets.size())
	meadow.play(randf() * meadow.stream.get_length())


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


func _on_planted() -> void:
	since_edit = 0.0


func _on_built(kind: StringName, at: Vector3) -> void:
	since_edit = 0.0
	_play(kind, at)


func _play(kind: StringName, at: Vector3) -> void:
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	var options: Array = _fx[kind]
	v.stream = options[randi() % options.size()]
	v.pitch_scale = randf_range(0.9, 1.1)
	v.global_position = at
	v.play()

class_name Cues
extends Node3D

## What every player action sounds and feels like, from one table (docs/design.md, "Action feedback"). A call site
## names its action and where it happened; the table says the sound, its level and spread of pitch, the pulse the
## hand that did it feels, and how often a continuous action may repeat, so dragging and painting come out as a
## texture. The sounds are rendered by scripts/compose.py into game/audio/fx and play from a fixed pool of 3D voices
## at the action. What a hand feels touching a surface is HandStop.FEEL's, not this table's.

enum Act {
	WALL_LAY, WALL_SETTLE, WALL_LIFT, WALL_STRETCH, WALL_CRUMBLE, WALL_RESTYLE, ARCH,
	ROOF_SHAPE, ROOF_FLAT,
	HOUSE_TAKE, HOUSE_MOVE, HOUSE_STRETCH,
	STAIRS_LAY, STAIRS_SET,
	FITTING, FITTING_OFF,
	FLORA_PAINT, STONE_PAINT, PATH_LAY, TREE_PLANT,
	GROUND_SHAPE, POND_POUR, POND_FILL, DIP, PLOP, NIBBLE,
	DELETE_SWEEP, WIPE_CHARGE, WIPE,
	DIAL_TURN, DIAL_SET,
	SKY_TURN,
	EASEL_PLACE, BRUSH_TAKE, BRUSH_DIP, CANVAS_STROKE, CHARCOAL_STROKE, SHEET_TEAR,
	PHOTO, SEEDS_THROW,
	WHEEL_OPEN, WHEEL_HOVER, WHEEL_PICK,
	UNDO, REDO,
	TELEPORT, TURN,
	VISIT_HOVER, VISIT_GO,
	PLAYER_JOINS, PLAYER_LEAVES,
	BIRDS_STARTLE, HAND_PERCH, HAND_PECK,
	REFUSED, CAPPED,
}

## Per action: `sound`, a family of clips in game/audio/fx (`sound`0.ogg and on, `SOUNDS` of them), or "" for none;
## `db`, its level at UNIT metres; `tune`, its pitch, spread by `spread` either way each play; `bend`, how far a
## `tension` of 1 takes the pitch; `feel`, the pulse as [amplitude, seconds, pulses, seconds from one to the next], or [] for
## none, its amplitude raised by up to `tighten` of itself at full tension; `every`, the least seconds between two
## plays from one hand.
const TABLE := {
	Act.WALL_LAY: {"sound": "stone", "db": -6.0, "spread": 0.1, "feel": [0.12, 0.012, 1, 0.0], "every": 0.06},
	Act.WALL_SETTLE: {"sound": "settle", "db": -4.0, "spread": 0.1, "feel": [0.3, 0.03, 2, 0.1]},
	Act.WALL_LIFT: {"sound": "stone", "db": -7.0, "spread": 0.12, "feel": [0.14, 0.012, 1, 0.0], "every": 0.07},
	Act.WALL_STRETCH: {"sound": "bow", "db": -8.0, "spread": 0.03, "bend": 0.7, "feel": [0.1, 0.03, 1, 0.0], "tighten": 2.0, "every": 0.11},
	Act.WALL_CRUMBLE: {"sound": "crumble", "db": -4.0, "spread": 0.1},
	Act.WALL_RESTYLE: {"sound": "settle", "db": -6.0, "spread": 0.1},
	Act.ARCH: {"sound": "arch", "db": -4.0, "spread": 0.1},
	Act.ROOF_SHAPE: {"sound": "wood", "db": -9.0, "spread": 0.08, "feel": [0.12, 0.015, 1, 0.0], "every": 0.06},
	Act.ROOF_FLAT: {"sound": "settle", "db": -6.0, "spread": 0.1, "feel": [0.3, 0.03, 1, 0.0], "every": 0.06},
	Act.HOUSE_TAKE: {"sound": "lift", "db": -6.0, "spread": 0.08, "feel": [0.3, 0.04, 1, 0.0]},
	Act.HOUSE_MOVE: {"sound": "scrape", "db": -11.0, "spread": 0.12, "feel": [0.07, 0.012, 1, 0.0], "every": 0.09},
	Act.HOUSE_STRETCH: {"sound": "bow", "db": -7.0, "spread": 0.03, "bend": 0.8, "feel": [0.1, 0.03, 1, 0.0], "tighten": 2.5, "every": 0.11},
	Act.STAIRS_LAY: {"sound": "stone", "db": -8.0, "spread": 0.1, "tune": 0.85, "feel": [0.1, 0.012, 1, 0.0], "every": 0.12},
	Act.STAIRS_SET: {"sound": "settle", "db": -5.0, "spread": 0.1, "feel": [0.3, 0.03, 2, 0.1]},
	Act.FITTING: {"sound": "wood", "db": -5.0, "spread": 0.08, "feel": [0.3, 0.025, 1, 0.0]},
	Act.FITTING_OFF: {"sound": "wood", "db": -7.0, "spread": 0.06, "tune": 0.8, "feel": [0.2, 0.02, 1, 0.0]},
	Act.FLORA_PAINT: {"sound": "rustle", "db": -12.0, "spread": 0.15, "feel": [0.05, 0.01, 1, 0.0], "every": 0.14},
	Act.STONE_PAINT: {"sound": "gravel", "db": -11.0, "spread": 0.12, "feel": [0.07, 0.01, 1, 0.0], "every": 0.12},
	Act.PATH_LAY: {"sound": "gravel", "db": -10.0, "spread": 0.12, "tune": 0.9, "feel": [0.08, 0.012, 1, 0.0], "every": 0.12},
	Act.TREE_PLANT: {"sound": "soil", "db": -4.0, "spread": 0.1, "feel": [0.35, 0.04, 1, 0.0]},
	Act.GROUND_SHAPE: {"sound": "soil", "db": -12.0, "spread": 0.15, "feel": [0.25, 0.02, 1, 0.0], "every": 0.05},
	Act.POND_POUR: {"sound": "", "feel": [0.25, 0.08, 1, 0.0]},
	Act.POND_FILL: {"sound": "fill", "db": -4.0, "spread": 0.1},
	Act.DIP: {"sound": "dip", "db": -4.0, "spread": 0.1},
	Act.PLOP: {"sound": "plop", "db": -4.0, "spread": 0.1},
	Act.NIBBLE: {"sound": "nibble", "db": -4.0, "spread": 0.1, "feel": [0.12, 0.025, 1, 0.0], "every": 0.12},
	Act.DELETE_SWEEP: {"sound": "gravel", "db": -9.0, "spread": 0.15, "tune": 0.8, "feel": [0.15, 0.015, 1, 0.0], "every": 0.1},
	Act.WIPE_CHARGE: {"sound": "", "feel": [0.05, 0.02, 1, 0.0], "tighten": 5.0, "every": 0.18},
	Act.WIPE: {"sound": "sweep", "db": -2.0, "spread": 0.02, "feel": [0.6, 0.12, 2, 0.27]},
	Act.DIAL_TURN: {"sound": "tock", "db": -12.0, "spread": 0.04, "feel": [0.25, 0.02, 1, 0.0], "every": 0.04},
	Act.DIAL_SET: {"sound": "pick", "db": -10.0, "spread": 0.0, "feel": [0.3, 0.03, 1, 0.0]},
	Act.SKY_TURN: {"sound": "tock", "db": -16.0, "spread": 0.03, "tune": 0.7, "feel": [0.2, 0.02, 1, 0.0], "every": 0.04},
	Act.EASEL_PLACE: {"sound": "wood", "db": -5.0, "spread": 0.06, "tune": 0.75, "feel": [0.35, 0.04, 1, 0.0]},
	Act.BRUSH_TAKE: {"sound": "tock", "db": -12.0, "spread": 0.06, "tune": 1.2, "feel": [0.3, 0.03, 1, 0.0]},
	Act.BRUSH_DIP: {"sound": "dip", "db": -18.0, "spread": 0.1, "tune": 1.3, "feel": [0.2, 0.02, 1, 0.0]},
	Act.CANVAS_STROKE: {"sound": "brush", "db": -18.0, "spread": 0.1, "feel": [0.05, 0.008, 1, 0.0], "tighten": 1.5, "every": 0.035},
	Act.CHARCOAL_STROKE: {"sound": "brush", "db": -18.0, "spread": 0.12, "tune": 0.8, "feel": [0.07, 0.005, 1, 0.0], "tighten": 1.5, "every": 0.025},
	Act.SHEET_TEAR: {"sound": "tear", "db": -8.0, "spread": 0.06, "feel": [0.3, 0.06, 1, 0.0]},
	Act.PHOTO: {"sound": "shutter", "db": -8.0, "spread": 0.04, "feel": [0.4, 0.04, 1, 0.0]},
	Act.SEEDS_THROW: {"sound": "scatter", "db": -8.0, "spread": 0.1, "feel": [0.2, 0.03, 1, 0.0]},
	Act.WHEEL_OPEN: {"sound": "tock", "db": -14.0, "spread": 0.03, "tune": 0.8, "feel": [0.15, 0.02, 1, 0.0]},
	Act.WHEEL_HOVER: {"sound": "tock", "db": -18.0, "spread": 0.05, "tune": 1.15, "feel": [0.1, 0.012, 1, 0.0], "every": 0.05},
	Act.WHEEL_PICK: {"sound": "pick", "db": -11.0, "spread": 0.0, "feel": [0.3, 0.03, 1, 0.0]},
	Act.UNDO: {"sound": "undo", "db": -11.0, "spread": 0.0, "feel": [0.2, 0.02, 1, 0.0]},
	Act.REDO: {"sound": "redo", "db": -11.0, "spread": 0.0, "feel": [0.2, 0.02, 1, 0.0]},
	Act.TELEPORT: {"sound": "whoosh", "db": -14.0, "spread": 0.06, "feel": [0.12, 0.05, 1, 0.0]},
	Act.TURN: {"sound": "", "feel": [0.08, 0.015, 1, 0.0]},
	Act.VISIT_HOVER: {"sound": "tock", "db": -16.0, "spread": 0.04, "tune": 1.1, "feel": [0.12, 0.015, 1, 0.0]},
	Act.VISIT_GO: {"sound": "hello", "db": -10.0, "spread": 0.0, "feel": [0.3, 0.04, 1, 0.0]},
	Act.PLAYER_JOINS: {"sound": "hello", "db": -12.0, "spread": 0.0, "every": 2.0},
	Act.PLAYER_LEAVES: {"sound": "bye", "db": -12.0, "spread": 0.0, "every": 2.0},
	Act.BIRDS_STARTLE: {"sound": "flutter", "db": -8.0, "spread": 0.12, "every": 0.5},
	Act.HAND_PERCH: {"sound": "", "feel": [0.2, 0.04, 2, 0.09]},
	Act.HAND_PECK: {"sound": "", "feel": [0.06, 0.01, 1, 0.0], "every": 0.4},
	Act.REFUSED: {"sound": "tock", "db": -12.0, "spread": 0.03, "tune": 0.6, "feel": [0.35, 0.05, 2, 0.12]},
	Act.CAPPED: {"sound": "grunt", "db": -8.0, "spread": 0.05, "feel": [0.4, 0.05, 2, 0.15]},
}
const SOUNDS := {
	"stone": 5, "settle": 3, "arch": 2, "crumble": 2, "dip": 3, "fill": 2, "plop": 3, "nibble": 4,
	"bow": 3, "lift": 2, "scrape": 4, "wood": 3, "rustle": 4, "gravel": 4, "soil": 3, "sweep": 1, "tock": 3,
	"pick": 3, "brush": 4, "tear": 2, "shutter": 2, "scatter": 3, "undo": 1, "redo": 1, "whoosh": 2, "hello": 1,
	"bye": 1, "flutter": 3, "grunt": 2,
}
## The sounds there were before this table; every other one is checked for band energy against them
## (tests/test_cues.py).
const REFERENCE := ["stone", "settle", "arch", "crumble", "dip", "fill"]
## The voices sounds share: a sound past these takes the voice that started longest ago.
const VOICES := 12
const UNIT := 3.0

static var _live: Cues
## Plays asked for per action since start, for tests.
static var asked := {}

var _clips := {}
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _last := {}
## Seconds of game time since start, so a fixed-rate render thins continuous actions as play does.
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
## Pulses still to come, as [when, hand, amplitude, seconds]: OpenXR plays a pulse at once, whatever its delay.
var _due: Array[Array] = []


func _init() -> void:
	name = "Cues"
	process_mode = Node.PROCESS_MODE_ALWAYS
	for kind in SOUNDS:
		_clips[kind] = []
		for i in SOUNDS[kind]:
			_clips[kind].append(load("res://audio/fx/%s%d.ogg" % [kind, i]))
	for i in VOICES:
		var v := AudioStreamPlayer3D.new()
		v.unit_size = UNIT
		v.max_distance = 80.0
		_voices.append(v)
		add_child(v)


func _enter_tree() -> void:
	_live = self


func _process(delta: float) -> void:
	_clock += delta
	while not _due.is_empty() and _due[0][0] <= _clock:
		var p: Array = _due.pop_front()
		if is_instance_valid(p[1]):
			p[1].trigger_haptic_pulse(&"haptic", 0.0, p[2], p[3], 0.0)


func _exit_tree() -> void:
	if _live == self:
		_live = null


## `act` happened at `at`, done by `hand` if a hand did it, `tension` of the way to its stretch's end. Calls closer
## together than the action's `every` from one hand come to nothing, so a site can call each step it makes.
static func play(act: Act, at: Vector3, hand: XRController3D = null, tension := 0.0) -> void:
	var cue: Dictionary = TABLE[act]
	asked[act] = asked.get(act, 0) + 1
	if _live == null:
		return
	var now := _live._clock
	var key := [act, hand.get_instance_id() if hand != null else 0]
	if now - _live._last.get(key, -INF) < cue.get("every", 0.0):
		return
	_live._last[key] = now
	_live._sound(cue, at, clampf(tension, 0.0, 1.0))
	if hand != null and is_instance_valid(hand):
		feel(hand, cue.get("feel", []), 1.0 + cue.get("tighten", 0.0) * clampf(tension, 0.0, 1.0))


## A pulse as the table writes one, `louder` times as strong.
static func feel(hand: XRController3D, pulse: Array, louder := 1.0) -> void:
	if pulse.is_empty():
		return
	var amp := minf(pulse[0] * louder, 1.0)
	hand.trigger_haptic_pulse(&"haptic", 0.0, amp, pulse[1], 0.0)
	if _live == null:
		return
	for i in range(1, pulse[2]):
		_live._due.append([_live._clock + i * pulse[3], hand, amp, pulse[1]])
	_live._due.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


## Only the pulse `act` gives, in `hand`: for one action felt in more than one hand.
static func felt(act: Act, hand: XRController3D) -> void:
	feel(hand, TABLE[act].get("feel", []))


func _sound(cue: Dictionary, at: Vector3, tension: float) -> void:
	if cue.sound == "":
		return
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	var options: Array = _clips[cue.sound]
	v.stream = options[_rng.randi() % options.size()]
	var spread: float = cue.get("spread", 0.0)
	v.pitch_scale = cue.get("tune", 1.0) * (1.0 + cue.get("bend", 0.0) * tension) * _rng.randf_range(1.0 - spread, 1.0 + spread)
	v.volume_db = cue.db + _rng.randf_range(-1.5, 1.0)
	v.global_position = at
	v.play()


## How far a stretch from `from` to `to` has gone, as a tension from 0 to 1: doubling is all the way.
static func stretch(from: float, to: float) -> float:
	return clampf(absf(to - from) / maxf(absf(from), 1e-3), 0.0, 1.0)

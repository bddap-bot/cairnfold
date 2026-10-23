class_name Cues
extends Node3D

## What every player action sounds and feels like, from one table (docs/design.md, "Action feedback"). A call site
## names its action and where it happened; the table says the sound, its level and spread of pitch, the pulse the
## hand that did it feels, and how often a continuous action may repeat, so dragging and painting come out as a
## texture. The sounds are rendered by scripts/compose.py, or cut from recordings by scripts/fx_recordings.py, into game/audio/fx and play from a fixed pool of 3D voices
## at the action. What a hand feels touching a surface is HandStop.FEEL's, not this table's.

enum Act {
	WALL_LAY, WALL_SETTLE, WALL_LIFT, WALL_STRETCH, WALL_CRUMBLE, WALL_RESTYLE, ARCH,
	ROOF_SHAPE, ROOF_FLAT,
	HOUSE_TAKE, HOUSE_MOVE, HOUSE_STRETCH,
	STAIRS_LAY, STAIRS_SET,
	FITTING, FITTING_OFF,
	FLORA_PAINT, STONE_PAINT, PATH_LAY, TREE_PLANT, BOULDER_PLACE, BOULDER_MOVE,
	GROUND_SHAPE, POND_POUR, POND_FILL, DIP, PLOP, NIBBLE,
	DELETE_SWEEP, WIPE_CHARGE, WIPE,
	DIAL_TURN, DIAL_SET,
	SKY_TURN,
	EASEL_PLACE, BRUSH_TAKE, BRUSH_DIP, SHEET_TEAR,
	PHOTO, VIDEO_START, VIDEO_STOP, SEEDS_THROW,
	BOOK_PAGE,
	WHEEL_OPEN, WHEEL_HOVER, WHEEL_PICK,
	UNDO, REDO,
	TELEPORT, TELEPORT_ONTO, TURN,
	PLAYER_JOINS, PLAYER_LEAVES,
	BIRDS_STARTLE, HAND_PERCH, HAND_PECK, HAND_FLIT, HAND_HOP, HAND_PREEN, HAND_LOOK,
	REFUSED, CAPPED,
}

## Per action: `sound`, a family of clips in game/audio/fx (`sound`0.ogg and on, `SOUNDS` of them), or "" for none;
## `db`, its level at UNIT metres; `tune`, its pitch, spread by `spread` either way each play; `bend`, how far a
## `tension` of 1 takes the pitch and `swell` how many dB louder it plays it; `weigh`, dB louder for each doubling of
## the `heft` of what did it, and `deepen`, how far its pitch falls as heft grows (pitch over heft to that power); `feel`, the pulse as [amplitude, seconds, pulses, seconds from one to the next], or [] for
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
	Act.BOULDER_PLACE: {"sound": "thud", "db": -7.0, "spread": 0.08, "swell": 8.0, "weigh": 3.5, "deepen": 0.2, "feel": [0.3, 0.04, 1, 0.0], "tighten": 1.5},
	Act.BOULDER_MOVE: {"sound": "whoosh", "db": -17.0, "spread": 0.05, "bend": 0.3, "swell": 12.0, "weigh": 2.5, "deepen": 0.15, "every": 0.2},
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
	Act.SHEET_TEAR: {"sound": "tear", "db": -8.0, "spread": 0.06, "feel": [0.3, 0.06, 1, 0.0]},
	Act.PHOTO: {"sound": "shutter", "db": -8.0, "spread": 0.04, "feel": [0.4, 0.04, 1, 0.0]},
	Act.VIDEO_START: {"sound": "roll", "db": -12.0, "spread": 0.03, "feel": [0.3, 0.03, 2, 0.08]},
	Act.VIDEO_STOP: {"sound": "cut", "db": -12.0, "spread": 0.03, "feel": [0.45, 0.07, 1, 0.0]},
	Act.BOOK_PAGE: {"sound": "page", "db": -16.0, "spread": 0.08, "feel": [0.08, 0.015, 1, 0.0]},
	Act.SEEDS_THROW: {"sound": "scatter", "db": -8.0, "spread": 0.1, "feel": [0.2, 0.03, 1, 0.0]},
	Act.WHEEL_OPEN: {"sound": "tock", "db": -14.0, "spread": 0.03, "tune": 0.8, "feel": [0.15, 0.02, 1, 0.0]},
	Act.WHEEL_HOVER: {"sound": "tock", "db": -18.0, "spread": 0.05, "tune": 1.15, "feel": [0.1, 0.012, 1, 0.0], "every": 0.05},
	Act.WHEEL_PICK: {"sound": "pick", "db": -11.0, "spread": 0.0, "feel": [0.3, 0.03, 1, 0.0]},
	Act.UNDO: {"sound": "undo", "db": -11.0, "spread": 0.0, "feel": [0.2, 0.02, 1, 0.0]},
	Act.REDO: {"sound": "redo", "db": -11.0, "spread": 0.0, "feel": [0.2, 0.02, 1, 0.0]},
	Act.TELEPORT: {"sound": "swish", "db": -12.0, "spread": 0.06, "feel": [0.12, 0.05, 1, 0.0]},
	Act.TELEPORT_ONTO: {"sound": "cloth", "db": -12.0, "spread": 0.06, "feel": [0.12, 0.05, 1, 0.0]},
	Act.TURN: {"sound": "", "feel": [0.08, 0.015, 1, 0.0]},
	Act.PLAYER_JOINS: {"sound": "hello", "db": -12.0, "spread": 0.0, "every": 2.0},
	Act.PLAYER_LEAVES: {"sound": "bye", "db": -12.0, "spread": 0.0, "every": 2.0},
	Act.BIRDS_STARTLE: {"sound": "flutter", "db": -8.0, "spread": 0.12, "every": 0.5},
	Act.HAND_PERCH: {"sound": "", "feel": [0.025, 0.012, 1, 0.0]},
	Act.HAND_PECK: {"sound": "", "feel": [0.012, 0.006, 1, 0.0]},
	Act.HAND_FLIT: {"sound": "", "feel": [0.015, 0.009, 1, 0.0]},
	Act.HAND_HOP: {"sound": "", "feel": [0.018, 0.008, 1, 0.0]},
	Act.HAND_PREEN: {"sound": "", "feel": [0.008, 0.005, 1, 0.0]},
	Act.HAND_LOOK: {"sound": "", "feel": [0.005, 0.004, 1, 0.0]},
	Act.REFUSED: {"sound": "tock", "db": -12.0, "spread": 0.03, "tune": 0.6, "feel": [0.35, 0.05, 2, 0.12]},
	Act.CAPPED: {"sound": "grunt", "db": -8.0, "spread": 0.05, "feel": [0.4, 0.05, 2, 0.15]},
}
const SOUNDS := {
	"stone": 5, "settle": 3, "arch": 2, "crumble": 2, "dip": 3, "fill": 2, "plop": 3, "nibble": 4,
	"bow": 3, "lift": 2, "scrape": 4, "wood": 3, "rustle": 4, "gravel": 4, "soil": 3, "sweep": 1, "tock": 3,
	"pick": 3, "tear": 2, "shutter": 2, "scatter": 3, "undo": 1, "redo": 1, "swish": 1, "cloth": 1, "hello": 1,
	"bye": 1, "flutter": 3, "grunt": 2, "thud": 3, "whoosh": 3, "page": 3, "roll": 1, "cut": 1,
}
## The sounds there were before this table; every other one is checked for band energy against them
## (tests/test_cues.py).
const REFERENCE := ["stone", "settle", "arch", "crumble", "dip", "fill"]
## The voices sounds share: a sound past these takes the voice that started longest ago.
const VOICES := 12
## The most any sound's level reaches, however hard or heavy what made it, in dB.
const LOUDEST := 2.0
const UNIT := 3.0

## Per-build choice: soft (default), paper, dark, or off. No runtime menu.
const CHARCOAL_PROFILE := "soft"
const CHARCOAL_GRAINS := 8
const CHARCOAL_INTERVAL := 0.1

## Contact feedback is independent of paint samples and brush load. Distances are metres.
class CanvasFeel:
	var touching := false
	var hard := false
	var tooth := 0.0
	var until_hard := 0.0

	func step(stick: bool, on: bool, pressure: float, speed: float, distance: float, limit: bool, dt: float) -> Vector2:
		var was_on := touching
		var was_hard := hard
		touching = on
		hard = on and not stick and limit
		until_hard -= dt
		if not on:
			tooth = 0.0
			return Vector2.ZERO
		if not stick:
			if hard and (not was_hard or until_hard <= 0.0):
				until_hard = 0.025
				return Vector2(0.055, 0.035)
			if not was_on:
				return Vector2(0.025, 0.006)
			return Vector2.ZERO
		if speed <= 0.002 or distance <= 0.0:
			return Vector2.ZERO
		tooth += distance
		if tooth < 0.0018:
			return Vector2.ZERO
		tooth = fmod(tooth, 0.0018)
		return Vector2(0.015 + 0.045 * clampf(pressure, 0.0, 1.0), 0.004)


static var _live: Cues
## Plays asked for per action since start, for tests.
static var asked := {}
## Pulses per action per hand's instance id since start, for tests.
static var pulsed := {}

var _canvas := {}
var _charcoal: Array[AudioStream] = []
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
	if CHARCOAL_PROFILE != "off":
		for i in CHARCOAL_GRAINS:
			_charcoal.append(load("res://audio/charcoal/%s%d.ogg" % [CHARCOAL_PROFILE, i]))
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


## `act` happened at `at`, done by `hand` if a hand did it, `tension` of the way to its stretch's end, by something of
## `heft` (a boulder's scale). Calls closer together than the action's `every` from one hand come to nothing, so a site
## can call each step it makes.
static func play(act: Act, at: Vector3, hand: XRController3D = null, tension := 0.0, heft := 1.0) -> void:
	play_in(act, at, [hand] if hand != null else [], tension, heft)


## `act` done by every hand in `hands` at once, as two hands stretching one house: one sound, a pulse in each hand.
static func play_in(act: Act, at: Vector3, hands: Array, tension := 0.0, heft := 1.0) -> void:
	var cue: Dictionary = TABLE[act]
	asked[act] = asked.get(act, 0) + 1
	if _live == null:
		return
	var now := _live._clock
	var key := [act]
	for h: XRController3D in hands:
		key.append(h.get_instance_id())
	if now - _live._last.get(key, -INF) < cue.get("every", 0.0):
		return
	_live._last[key] = now
	_live._sound(cue, at, clampf(tension, 0.0, 1.0), heft)
	for h: XRController3D in hands:
		if is_instance_valid(h):
			feel(h, cue.get("feel", []), 1.0 + cue.get("tighten", 0.0) * clampf(tension, 0.0, 1.0))
			var by: Dictionary = pulsed.get_or_add(act, {})
			by[h.get_instance_id()] = by.get(h.get_instance_id(), 0) + 1


## Called each physical-contact frame, including stationary and unloaded brushes.
static func canvas_contact(hand: XRController3D, at: Vector3, stick: bool, touching: bool, pressure: float, speed: float, distance: float, hard: bool) -> void:
	if _live == null or not is_instance_valid(hand):
		return
	_live._canvas_contact(hand, at, stick, touching, pressure, speed, distance, hard)


static func canvas_leave(hand: XRController3D) -> void:
	canvas_contact(hand, Vector3.ZERO, false, false, 0.0, 0.0, 0.0, false)


func _canvas_contact(hand: XRController3D, at: Vector3, stick: bool, touching: bool, pressure: float, speed: float, distance: float, hard: bool) -> void:
	var key := hand.get_instance_id()
	if not _canvas.has(key):
		if not touching:
			return
		var holder := Node3D.new()
		add_child(holder)
		var voices: Array[AudioStreamPlayer3D] = []
		for i in 2:
			var voice := AudioStreamPlayer3D.new()
			voice.unit_size = 0.5
			voice.max_distance = 4.0
			holder.add_child(voice)
			voices.append(voice)
		_canvas[key] = {"feel": CanvasFeel.new(), "voices": voices, "time": _clock, "grain_at": -INF, "grain": -1, "next": 0, "hand": hand}
	var c: Dictionary = _canvas[key]
	var was_hard: bool = c.feel.hard
	var pulse: Vector2 = c.feel.step(stick, touching, pressure, speed, distance, hard, _clock - c.time)
	c.time = _clock
	if was_hard and not c.feel.hard:
		hand.trigger_haptic_pulse(&"haptic", 0.0, 0.0, 0.0, 0.0)
	if pulse.x > 0.0:
		feel(hand, [pulse.x, pulse.y, 1, 0.0])
	if not touching or not stick or speed <= 0.002 or distance <= 0.0:
		for voice: AudioStreamPlayer3D in c.voices:
			voice.stop()
		c.grain_at = -INF
		return
	if _charcoal.is_empty() or _clock - c.grain_at < CHARCOAL_INTERVAL:
		return
	c.grain_at = _clock
	# Never repeat the previous excerpt; the two voices overlap their soft envelopes.
	c.grain = (c.grain + 1 + _rng.randi_range(0, CHARCOAL_GRAINS - 2)) % CHARCOAL_GRAINS
	var voice: AudioStreamPlayer3D = c.voices[c.next]
	c.next = 1 - c.next
	voice.stream = _charcoal[c.grain]
	voice.global_position = at
	voice.pitch_scale = clampf(0.85 + speed * 0.3, 0.85, 1.05)
	voice.volume_db = -8.0 + linear_to_db(0.15 + 0.35 * clampf(pressure, 0.0, 1.0)) + linear_to_db(clampf(speed / 0.12, 0.0, 1.0))
	voice.play()


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


func _sound(cue: Dictionary, at: Vector3, tension: float, heft: float) -> void:
	if cue.sound == "":
		return
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	var options: Array = _clips[cue.sound]
	v.stream = options[_rng.randi() % options.size()]
	var spread: float = cue.get("spread", 0.0)
	v.pitch_scale = cue.get("tune", 1.0) * (1.0 + cue.get("bend", 0.0) * tension) * pow(heft, -cue.get("deepen", 0.0)) * _rng.randf_range(1.0 - spread, 1.0 + spread)
	v.volume_db = minf(cue.db + cue.get("swell", 0.0) * tension + cue.get("weigh", 0.0) * log(heft) / log(2.0) + _rng.randf_range(-1.5, 1.0), LOUDEST)
	v.global_position = at
	v.play()


## How far a stretch from `from` to `to` has gone, as a tension from 0 to 1: doubling is all the way.
static func stretch(from: float, to: float) -> float:
	return clampf(absf(to - from) / maxf(absf(from), 1e-3), 0.0, 1.0)

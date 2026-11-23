extends "res://../tests/support/suite.gd"

## A wearer who starts low, putting the headset on seated or bent over, and then stands: the view never goes black
## on its own, and the scale follows their stature at their next teleport.

const STEP := 1.0 / 60.0
const LOW_M := 1.0
const STAND_M := 1.5
## Covers luma under 20 of 255 over a lit scene.
const BLACK := 0.85

var terrain := Terrain.new()


func _initialize() -> void:
	var rig := Rig.new(terrain)
	root.add_child(rig)
	_finish.call_deferred(rig)


func _finish(rig: Rig) -> void:
	rig.set_process(false)
	rig.wear(Avatar.open(Avatar.built_in(0), Color.WHITE))
	rig.place(terrain.ground(0, 0), 0.0)
	rig._pending = null
	rig._fade_t = -1.0
	var cuts := [0]
	rig.jumped.connect(func() -> void: cuts[0] += 1)
	var black := 0
	var t := 0.0
	while t < 30.0:
		var eye := LOW_M if t < 6.0 else lerpf(LOW_M, STAND_M, clampf((t - 6.0) / 4.0, 0.0, 1.0))
		rig.head.position = Vector3(0.1, eye * rig.world_scale, -0.1)
		rig._process(STEP)
		if rig._fade_mat.albedo_color.a > BLACK:
			black += 1
		t += STEP
	check(black == 0 and cuts[0] == 0, "a wearer rising from %.2f m to stand at %.2f m sees no blackout: %d black frames over %d cuts" % [LOW_M, STAND_M, black, cuts[0]])
	Metrics._notes.clear()
	rig.teleport(terrain.ground(0, -6), 0.0)
	for i in int(2.0 * Rig.FADE / STEP) + 2:
		rig.head.position = Vector3(0.1, STAND_M * rig.world_scale, -0.1)
		rig._process(STEP)
	var want := rig.body.eye_height / STAND_M
	check(absf(rig.world_scale - want) < 0.01 and cuts[0] == 1, "their next teleport fits them to the avatar: a scale of %.3f, %.3f wanted, %d cut" % [rig.world_scale, want, cuts[0]])
	var said := Metrics._notes.map(func(n: Dictionary) -> String: return n.what)
	check(said.any(func(w: String) -> bool: return w.contains("teleport")) and said.any(func(w: String) -> bool: return w.contains("%.3f" % want)), "the record says the view faded for a teleport and the scale it took: %s" % [said])
	finish()

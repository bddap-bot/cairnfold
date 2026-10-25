extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


## The demo's teleport onto the bridge must land there for any head pose an unworn headset settles in: its aim once
## grazed the deck's far edge, so a millimetre of head tracking decided between the deck and the grass 16 m beyond.
func _run() -> void:
	boot_main()
	await process_frame
	# The bridge fixture exceeds capacity; this test checks its teleport landing.
	main.world.bounded = false
	var steps := Driver.read("res://../demo/stairs.json").filter(func(s: Dictionary) -> bool: return s.op != "capture")
	var at := steps.find_custom(func(s: Dictionary) -> bool: return s.op == "aim")
	var aim: Dictionary = steps[at]
	aim.erase("capture")
	await play(steps.slice(0, at))
	var house: Dictionary = main.world.state.stairs.values().filter(func(s: Dictionary) -> bool: return s.rail == "wood")[0]
	var foot: Vector3 = house.a if house.a.y < house.b.y else house.b
	check(absf(foot.y - main.world.terrain.height_at(foot.x, foot.z)) < 0.05, "the flight up to the flat-roofed house starts on the lawn, not at roof height: %s" % foot)
	check(main.tool.aim(Vector3(9, 60, 0), Vector3.DOWN).on == -1, "a ray straight down beside a flat roof meets the ground, not the roof's level")
	var rig: Rig = main.rig
	var head: Transform3D = rig.head.global_transform
	for pitch in [-0.3, 0.0, 0.3]:
		for yaw in [-0.3, 0.0, 0.3]:
			var tilted := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(head.basis.x, deg_to_rad(pitch)) * head.basis, head.origin)
			rig.aim(Driver.aim_pose(tilted, aim.dir))
			check(rig.aim_ground != null and rig.aim_ground.y > 1.5, "head turned %s° up, %s° left: the ray lands on the bridge, not %s" % [pitch, yaw, rig.aim_ground])
	rig.hide_markers()
	await play([aim])
	check(rig.global_position.y > 1.5 and absf(rig.head.global_position.z - -0.5) < 0.6, "the demo's teleport stands on the bridge: %s" % rig.head.global_position)
	finish()

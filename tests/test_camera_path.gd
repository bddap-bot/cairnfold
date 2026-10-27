extends "res://../tests/support/suite.gd"

## The authored camera a replay can be re-rendered from (--camera, scripts/render.sh with CAIRNFOLD_CAMERA).

const KEYS := [
	{"t": 0.0, "eye": [0, 2, 8], "at": [0, 1, 0]},
	{"t": 2.0, "eye": [6, 3, 6], "at": [0, 1, 0]},
	{"t": 4.0, "eye": [8, 4, -2], "at": [0, 1, 0]},
]


func _initialize() -> void:
	await process_frame
	var keys: Variant = CameraPath.read(_written(JSON.stringify([KEYS[2], KEYS[0], KEYS[1]])))
	check(keys is Array and keys.map(func(k: Dictionary) -> float: return k.t) == [0.0, 2.0, 4.0], "the keys read back in time order: %s" % [keys])
	_follows_the_keys(keys)
	for bad in ["{}", "[]", '[{"t": 0, "eye": [0, 1], "at": [0, 0, 0]}]', '[{"eye": [0, 1, 2], "at": [0, 0, 0]}]', '[{"t": 0, "eye": [0, 1, 2], "at": [0, 1, 2]}]',
			'[{"t": 0, "eye": [0, 5, 0], "at": [0, 1, 0]}]']:
		check(CameraPath.read(_written(bad)) is String, "%s is refused with why" % bad)
	await _a_launch_with_a_camera_sees_from_it(_written(JSON.stringify(KEYS)))
	finish()


func _follows_the_keys(keys: Array) -> void:
	for k: Dictionary in keys:
		var at := CameraPath.at(keys, k.t)
		check(at.origin.is_equal_approx(k.eye) and _looks_at(at, k.at), "at %.1f s the camera is at its key: %s" % [k.t, at])
	check(CameraPath.at(keys, -1.0).is_equal_approx(CameraPath.at(keys, 0.0)) and CameraPath.at(keys, 9.0).is_equal_approx(CameraPath.at(keys, 4.0)),
		"before the first key and after the last it holds there")
	var last := CameraPath.at(keys, 0.0).origin
	var steps := []
	for i in range(1, 401):
		var o := CameraPath.at(keys, i * 0.01).origin
		steps.append(o.distance_to(last))
		last = o
	check(steps.max() < 0.1 and steps.slice(1).all(func(s: float) -> bool: return s > 0.0), "it moves on every step, never jumps: largest %.3f m" % steps.max())
	var mid := CameraPath.at(keys, 1.0)
	check(not mid.origin.is_equal_approx(keys[0].eye) and _looks_at(mid, keys[0].at), "between keys it moves, looking at the point every key looks at")


func _a_launch_with_a_camera_sees_from_it(path: String) -> void:
	boot_main({"camera": path, "desktop": true})
	await frames(5)
	var cam := root.get_viewport().get_camera_3d()
	check(cam is CameraPath, "the view is the camera path's, not the head's: %s" % cam)
	if cam is CameraPath:
		check(cam.cull_mask & Quality.SELF_LAYER != 0, "it sees the player's own body, as an onlooker would")
		check(cam.global_transform.is_equal_approx(CameraPath.at(cam.keys, cam._t)), "it stands where its keys put it at its game time %.3f s" % cam._t)
		check(cam._t > 0.0, "its clock runs with the game's")
	var hand: Hand = main.rig.right
	var button := "right_hand/" + Controls.input("wheel", "right_hand")
	Buttons.injected[button] = true
	await frames(2)
	var head := main.rig.head
	check(hand.picking and hand._wheel_root.global_basis.is_equal_approx(ToolWheel.facing(hand.global_position, head.global_position, -head.global_basis.z)),
		"a wheel opens facing the player's head, not the onlooker, so a replay picks the tools the session did")
	Buttons.injected.erase(button)
	main.queue_free()
	await process_frame


func _looks_at(t: Transform3D, target: Vector3) -> bool:
	return (-t.basis.z).is_equal_approx((target - t.origin).normalized())


func _written(text: String) -> String:
	var path := "user://camera-%d.json" % text.hash()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return ProjectSettings.globalize_path(path)

extends "res://../tests/support/suite.gd"

## Headless checks of fitting a wearer to their avatar: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_fit.gd

const STEP := 1.0 / 60.0
## A wearer's arm, shoulder to the grip of a held controller, over their eye height standing.
const ARM := 0.42

var terrain := Terrain.new()


func _initialize() -> void:
	_stature_is_the_height_stood_at()
	var rig := Rig.new(terrain)
	root.add_child(rig)
	_finish.call_deferred(rig)


func _finish(rig: Rig) -> void:
	rig.set_process(false)
	var godette := Avatar.read(FileAccess.get_file_as_bytes(_sample("godette-0.x.vrm")))
	var crimsom := Avatar.read(FileAccess.get_file_as_bytes(_sample("crimsom-1.0.vrm")))
	var short := _one_avatar_fits_any_wearer(rig, crimsom, "Crimsom", 1.45)
	var tall := _one_avatar_fits_any_wearer(rig, crimsom, "Crimsom", 1.85)
	check(short < 1.1 and absf(short - tall) < 0.01, "Crimsom's arm reaches as far whoever wears it: the forearm %.2f and %.2f times its length at a wearer's full reach" % [short, tall])
	for scene: PackedScene in [godette, Avatar.built_in(2)]:
		_one_avatar_fits_any_wearer(rig, scene, "Godette" if scene == godette else "the hood", 1.7)
	_a_refit_waits_for_a_fade(rig, crimsom)
	finish()


## Crouching, kneeling, tiptoe or a moment's jump leave the wearer's standing eye height as it is; a wearer seated
## throughout is measured seated, and until measured is the typical one.
func _stature_is_the_height_stood_at() -> void:
	var s := Stature.new()
	check(s.eye(Rig.EYE) == Rig.EYE, "unmeasured, a wearer is typical")
	s.add(1.72, 60.0)
	s.add(1.05, 20.0)
	s.add(0.7, 5.0)
	s.add(1.84, 2.0)
	s.add(2.1, 0.3)
	check(absf(s.eye(Rig.EYE) - 1.72) < 0.006, "a wearer who stands, crouches, kneels and jumps stands at 1.72 m: %.3f" % s.eye(Rig.EYE))
	var seated := Stature.new()
	seated.add(1.18, 30.0)
	seated.add(1.25, 1.0)
	check(absf(seated.eye(Rig.EYE) - 1.18) < 0.006, "a seated wearer is measured seated: %.3f" % seated.eye(Rig.EYE))


## Stands a wearer whose eyes are `eye_m` over the floor in `scene`, measured standing still until the fit settles.
func _wear(rig: Rig, scene: PackedScene, eye_m: float) -> Avatar:
	rig.stature = Stature.new()
	rig.wear(Avatar.open(scene, Color.WHITE))
	rig.place(terrain.ground(0, 0), 0.0)
	for i in int((Stature.SETTLE + 4.0 * Rig.FADE) / STEP) + 2:
		rig.head.position = Vector3(0.1, eye_m * rig.world_scale, -0.2)
		rig._process(STEP)
	rig.pose_body()
	return rig.body


## Whatever the wearer's height, the avatar stands at its own size with its feet on the floor and its eyes where the
## wearer sees from; and how far its forearm stretches, over its length, with the wearer's arm held out at full reach.
func _one_avatar_fits_any_wearer(rig: Rig, scene: PackedScene, name: String, eye_m: float) -> float:
	var a := _wear(rig, scene, eye_m)
	var what := "%s worn by a wearer with eyes %.2f m up" % [name, eye_m]
	var floor_y := rig.global_position.y
	var head_y := rig.head.global_position.y - floor_y
	check(absf(rig.world_scale - a.eye_height / eye_m) < 0.01 and absf(head_y - a.eye_height) < 0.01, "%s sees from its eyes, %.3f m up, at a scale of %.3f: from %.3f at %.3f" % [what, a.eye_height, a.eye_height / eye_m, head_y, rig.world_scale])
	var drawn := a.global_transform.basis.get_scale()
	check(drawn.is_equal_approx(Vector3.ONE), "%s is drawn at its own size: %s" % [what, drawn])
	var hips_to_head := a.bone("hips").origin.distance_to(a.bone("head").origin)
	var at_rest: float = a._hips.rest.origin.distance_to(a._head.rest.origin)
	check(absf(hips_to_head - at_rest) < 0.001, "%s keeps its proportions: hips to head %.3f m, %.3f at rest" % [what, hips_to_head, at_rest])
	if a._joints.has("leftFoot"):
		var ankle := a.bone("leftFoot").origin
		var foot: float = ankle.y - rig.floor_under.call(ankle + Vector3.UP)
		var rest: float = a._joints.leftFoot.rest.origin.y
		check(absf(foot - rest) < 0.01, "%s stands on the floor: its foot %.3f m up, %.3f at rest" % [what, foot, rest])
	var arm := a._arms[0]
	var shoulder := a._get_joint(arm.upper).origin
	var out := (shoulder - a.to_local(rig.head.global_position)) * Vector3(1, 0, 1)
	var reach := ARM * eye_m * rig.world_scale
	rig.left.global_position = a.to_global(shoulder + out.normalized() * reach)
	rig.pose_body()
	var stretch := a._get_joint(arm.end).origin.distance_to(a._get_joint(arm.lower).origin) / arm.lower_length
	rig.left.transform = Transform3D.IDENTITY
	return stretch


## A new avatar is fitted behind a fade, as a teleport is, never by the world growing in view.
func _a_refit_waits_for_a_fade(rig: Rig, scene: PackedScene) -> void:
	_wear(rig, scene, 1.6)
	var before := rig.world_scale
	rig.wear(Avatar.open(Avatar.built_in(0), Color.WHITE))
	rig._process(STEP)
	check(rig.world_scale == before and rig._fade.visible, "a new avatar fades the view before it changes the scale")
	for i in int(2.0 * Rig.FADE / STEP) + 2:
		rig._process(STEP)
	check(absf(rig.world_scale - rig.body.eye_height / 1.6) < 0.01 and not rig._fade.visible, "and the view returns at the new avatar's scale: %.3f" % rig.world_scale)


func _sample(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../tests/avatars").path_join(name)

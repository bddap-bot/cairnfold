extends "res://../tests/support/suite.gd"

## A held book-sized board, casting nothing into the sun's map, lays its shadow (HeldShadow) on ground that reads it as
## the garden's does in every frame while the hand trembles and drifts, under the eyes' sun (Look) and a view as wide
## as a headset's; and at three hours that shadow darkens the ground, never past the sun's own shadow there. Needs a
## RenderingDevice, so scripts/test.sh runs it on the desktop renderer:
## godot4 --path game --xr-mode off --script ../tests/gpu_held_shadow.gd

const FRAMES := 90
const SIZE := Vector2i(480, 400)

var vp: SubViewport
var look: Look
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	vp = SubViewport.new()
	vp.size = SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	look = Look.build(vp)
	look.show_lake(false)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var reads := Shader.new()
	reads.code = """shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
#include "res://src/held_shadow.gdshaderinc"
varying vec3 held;
void vertex() { held = held_coord((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz); }
void fragment() { ALBEDO = vec3(0.6) * held_lit(held); ROUGHNESS = 1.0; }
"""
	ground.material_override = ShaderMaterial.new()
	ground.material_override.shader = reads
	vp.add_child(ground)
	cam = Camera3D.new()
	cam.fov = 96.0
	cam.near = Rig.NEAR
	cam.far = Rig.FAR
	vp.add_child(cam)
	await _held()
	await _darkness()
	finish()


func _held() -> void:
	var book := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Book.BOARD
	book.mesh = board
	book.material_override = _matte(Color(1, 0, 0))
	book.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(book)
	var held := Vector3(0.0, 1.2, -0.5)
	var toward := Daylight.toward_light(look.time)
	var shade := held - toward * (held.y / toward.y)
	cam.look_at_from_position(Vector3(0, Rig.EYE, 0.6), shade.lerp(held, 0.3))
	var counts: Array[int] = []
	for f in FRAMES + 8:
		var t := f / 72.0
		book.position = held + Vector3(sin(t * 37.0), sin(t * 29.0 + 1.0), sin(t * 41.0 + 2.0)) * 0.003 + Vector3(0.05, 0.0, 0.02) * t
		book.rotation = Vector3(0.05 * sin(t * 11.0), 0.3, 0.04 * sin(t * 13.0))
		var half := Book.BOARD * 0.5
		HeldShadow.cast(book.global_transform, Rect2(-half.x, -half.z, Book.BOARD.x, Book.BOARD.z), look.time)
		await RenderingServer.frame_post_draw
		if f >= 8:
			counts.append(_shaded(vp.get_texture().get_image(), Rect2i(Vector2i(cam.unproject_position(shade)) - Vector2i(90, 90), Vector2i(180, 180))))
	var steps := 0
	for i in range(1, counts.size()):
		steps = maxi(steps, absi(counts[i] - counts[i - 1]))
	var least: int = counts.min()
	print("held shadow: pixels %d to %d, largest change between frames %d" % [least, counts.max(), steps])
	check(least > 40, "the held book casts a shadow in every frame: %s" % [counts])
	check(steps * 10 < least, "which changes between frames no more than its motion does: %d of %d" % [steps, least])
	book.queue_free()


## Level ground under a held shadow, against ground in the sun's own shadow of a wide board, and in sun.
func _darkness() -> void:
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3, 0.05, 3)
	board.mesh = bm
	vp.add_child(board)
	for t in [0.29, Daylight.DEFAULT, 0.5]:
		look.set_time(t)
		var toward := Daylight.toward_light(t)
		board.position = Vector3(0, 1.5, 0)
		var real := board.position - toward * (1.5 / toward.y)
		HeldShadow.cast(Transform3D(Basis(), real + Vector3(4, 0, 0) + toward * 1.5 / toward.y), Rect2(-1.5, -1.5, 3, 3), t)
		cam.look_at_from_position(real + Vector3(0, 8, 6), real)
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var at := func(p: Vector3) -> float: return img.get_pixelv(Vector2i(cam.unproject_position(p))).get_luminance()
		var sun: float = at.call(real + Vector3(-4, 0, 0))
		var want: float = at.call(real)
		var got: float = at.call(real + Vector3(4, 0, 0))
		print("held shadow at %.3f: sun %.3f, its shadow %.3f, held shadow %.3f" % [t, sun, want, got])
		check(got < sun - 0.03 and got > want - 0.02, "a held shadow at %.3f darkens sunlit ground (%.3f) to %.3f, not past the sun's own shadow (%.3f)" % [t, sun, got, want])
	board.queue_free()


func _matte(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


## Grey pixels in `around` darker than the lit ground at the image's bottom edge: the book's shadow, its own red faces
## aside.
func _shaded(img: Image, around: Rect2i) -> int:
	var lit := img.get_pixel(SIZE.x / 2, SIZE.y - 2).get_luminance()
	var n := 0
	var r := around.intersection(Rect2i(Vector2i.ZERO, SIZE))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			if c.r - c.g < 0.1 and c.get_luminance() < lit * 0.85:
				n += 1
	return n



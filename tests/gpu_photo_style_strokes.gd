extends "res://../tests/support/booted.gd"

## Paint strokes of known colours, seen square-on on the camera's screen: each colour-filtered style draws each stroke
## as light as plain does, scaled by the style's tone, so a yellow stroke stays lighter than a red, and a red than a blue.

## Canvas v of each stroke's centre line, and the pigment it is painted in.
const STROKES := {"yellow": [0.25, 1], "red": [0.5, 3], "blue": [0.75, 5]}
## Of the canvas's height, the view's: the screen sees canvas alone.
const FILL := 0.9
## Mono against plain: the pass tones before tonemapping, whose toe takes more off a grey than off a saturated colour's
## brightest channel, so a dry blue stroke comes out 0.71 of plain's light.
const TOE := 0.35
## A tinted style against mono, which the toe bends alike.
const SLACK := 0.15


func _run() -> void:
	var strokes := []
	for name: String in STROKES:
		var v: float = STROKES[name][0]
		strokes.append(Driver.stroke(Vector2(0.1, v), Vector2(0.9, v), Brushwork.PIGMENTS[STROKES[name][1]]))
	await play([
		{"op": "place", "x": 0, "z": 6},
		{"op": "easel", "x": 0, "z": 3, "facing": [0, 6]},
		{"op": "painting", "easel": 0, "strokes": strokes},
	])
	var e: Easels.Easel = main.easels.find(main.easels.easels.keys()[0])
	await until(func() -> bool: return not e.canvas.wet(), "the strokes dry")

	var frame := e.canvas_frame()
	var view_height := Brushwork.METRES.y * FILL
	var at := Transform3D(frame.basis, frame.origin + frame.basis.z * view_height * 0.5 / tan(deg_to_rad(PhotoTool.FOV) * 0.5))
	var tool: PhotoTool = main.photo_tool
	var seen := {}
	for kind: PhotoStyle.Kind in [PhotoStyle.Kind.PLAIN, PhotoStyle.Kind.MONO, PhotoStyle.Kind.SEPIA, PhotoStyle.Kind.CYANOTYPE]:
		tool.wear(kind, false)
		var img := await tool.render_screen(at)
		var lumas := {}
		for name: String in STROKES:
			lumas[name] = _luma(img, 0.5 + (STROKES[name][0] - 0.5) * Brushwork.METRES.y / view_height)
		seen[kind] = lumas
	tool.wear(PhotoStyle.Kind.PLAIN, false)
	var plain: Dictionary = seen[PhotoStyle.Kind.PLAIN]
	for kind: PhotoStyle.Kind in seen:
		print("%s: %s" % [PhotoStyle.named(kind), seen[kind]])
	check(plain.yellow > plain.red and plain.red > plain.blue, "plain draws yellow over red over blue in light: %s" % [plain])
	var mono: Dictionary = seen[PhotoStyle.Kind.MONO]
	for name: String in STROKES:
		check(absf(mono[name] / plain[name] - 1.0) < TOE, "mono draws the %s stroke as light as plain: %.4f against %.4f" % [name, mono[name], plain[name]])
	for kind: PhotoStyle.Kind in [PhotoStyle.Kind.MONO, PhotoStyle.Kind.SEPIA, PhotoStyle.Kind.CYANOTYPE]:
		var tone: Basis = PhotoStyle.TONES[kind]
		# The light a tone of rows LUMA * k gives a grey of light 1.
		var gain := PhotoStyle.LUMA.dot(Vector3(tone[0].x, tone[1].x, tone[2].x) / PhotoStyle.LUMA.x)
		var styled: Dictionary = seen[kind]
		for name: String in STROKES:
			check(absf(styled[name] / mono[name] / gain - 1.0) < SLACK, "%s draws the %s stroke as mono does, by its tone's %.2f: %.4f against %.4f" % [PhotoStyle.named(kind), name, gain, styled[name], mono[name]])
		check(styled.yellow > styled.red and styled.red > styled.blue, "%s keeps yellow over red over blue: %s" % [PhotoStyle.named(kind), styled])
	finish()


## The median linear luma along the middle of the screen's row at `y`, a share of its height.
func _luma(img: Image, y: float) -> float:
	var row := int(y * img.get_height())
	var out := PackedFloat32Array()
	for x in range(int(img.get_width() * 0.3), int(img.get_width() * 0.7)):
		var c := img.get_pixel(x, row).srgb_to_linear()
		out.append(PhotoStyle.LUMA.dot(Vector3(c.r, c.g, c.b)))
	out.sort()
	return out[out.size() / 2]

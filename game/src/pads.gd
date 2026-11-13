class_name Pads
extends Crowd

## The lilypads on every pond (PadLayout), one MultiMesh. A pad opens out once its pond has filled; a pond changed
## keeps the pads it had where they still float.

## Seconds a pad takes to open out.
const GROW := 1.5
## How far over its pond's level a pad lies, clear of the surface drawn under it.
const LIFT := 0.012
const SEGMENTS := 10

var _water: Water
var _laid: Array[PadLayout.Leaf] = []
var _on: Array[PondWater] = []
## How far each pad has opened, by where it lies.
var _grown := {}
## Each shown pond's pads as last laid, by its layout, with the quota they were laid for: an edit lays again only the
## ponds it changed.
var _known := {}


func _init(water: Water) -> void:
	_water = water
	super(water.terrain, leaf(), PadLayout.CAP, "res://src/lilypad.gdshader", true)
	set_process(false)


## A pad one across its radius, flat, facing up: a disc with a notch cut to its middle at +x. UV.x runs 0 at the
## middle to 1 at the rim, UV.y once round it.
static func leaf() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var notch := TAU / (SEGMENTS * 2.0)
	for s in SEGMENTS:
		var corners := [[0.0, 0.0]]
		for end in [1, 0]:
			corners.append([1.0, lerpf(notch, TAU - notch, (s + end) / float(SEGMENTS))])
		for c: Array in corners:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(c[0], c[1] / TAU))
			st.add_vertex(Vector3(cos(c[1]), 0.0, sin(c[1])) * c[0])
	st.index()
	return st.commit()


func lay(ponds: Array[PondWater]) -> void:
	_laid.clear()
	_on.clear()
	var grown := {}
	var kept := {}
	for w in ponds:
		var want := PadLayout.quota(w.pond.cells.size(), PadLayout.CAP - _laid.size())
		var known: Array = _known.get(w.pond, [])
		if known.is_empty() or known[0] != want:
			known = [want, PadLayout.pads(w.pond, _water.terrain.height_at, want)]
		kept[w.pond] = known
		for p: PadLayout.Leaf in known[1]:
			_laid.append(p)
			_on.append(w)
			grown[p.at] = _grown.get(p.at, 0.0)
	_grown = grown
	_known = kept
	_show()


func count() -> int:
	return _laid.size()


func pad(i: int) -> PadLayout.Leaf:
	return _laid[i]


func _process(delta: float) -> void:
	for i in _laid.size():
		if _on[i].full():
			_grown[_laid[i].at] = minf(_grown[_laid[i].at] + delta / GROW, 1.0)
	_show()


func _show() -> void:
	var growing := false
	for i in _laid.size():
		var p := _laid[i]
		var open: float = _grown[p.at]
		growing = growing or open < 1.0
		put(i, Transform3D(Basis(Vector3.UP, p.turn).scaled(Vector3.ONE * p.radius), Vector3(p.at.x, _on[i].pond.level + LIFT, p.at.y)), Color(open, p.turn, 0, 0), p.colour)
	upload(_laid.size())
	set_process(growing)

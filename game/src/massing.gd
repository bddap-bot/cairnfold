class_name Massing
extends RefCounted

## The room a standing build takes up, worked out from its laid ground curve: the top another build stands on,
## and the space where a build joined to it lays nothing (docs/design.md, "Buildings on buildings"). Pure data,
## never changed once made, so worker threads laying other builds read it freely.

## How far past an open wall's faces a build standing on its top still rests on it.
const REACH := 0.3
## A joined build's stones this near a house or tower's centre line stand: walls laid along the same line both stay.
const SLACK := 0.05
const CELL := 1.0

var closed := false
## The centre line on the ground plane: round a house or tower, along an open wall.
var line := PackedVector2Array()
## Where the stones stand: one height for a closed wall, one per point of an open one.
var feet := PackedFloat32Array()
## From the feet to the top another build stands on.
var rise := 0.0
## The roof surface is the ceiling of the room under it.
var roof: RoofLayout
## The centre line shrunk by SLACK: inside it lies a joined build's room.
var inner: Array[PackedVector2Array] = []
## The outer faces, where a build standing here rests.
var outer: Array[PackedVector2Array] = []
## Out to where a roof's eaves would reach: under it lies what a build standing here covers.
var eaves: Array[PackedVector2Array] = []
## Encloses everything above, grown by REACH.
var rect := Rect2()
var _cells := {}
var _key := []


## The solid of a resampled layout, with the roof on it if any.
static func of(layout: WallLayout, cover: RoofLayout) -> Massing:
	var s := Massing.new()
	s.closed = layout.closed
	s.rise = layout.height + WallLayout.CAP
	var half := WallLayout.THICKNESS * 0.5
	if s.closed:
		for p in layout.points:
			s.line.append(Vector2(p.x, p.z))
		s.feet.append(layout.samples[0].y if layout.samples.size() > 0 else 0.0)
		s.inner = Geometry2D.offset_polygon(s.line, -SLACK)
		s.outer = Geometry2D.offset_polygon(s.line, half)
		s.eaves = Geometry2D.offset_polygon(s.line, half + (cover.overhang if cover != null else RoofLayout.OVERHANG))
		if cover != null and (not cover.flat() or cover.curve != 0.0):
			s.roof = RoofLayout.new()
			s.roof.kind = cover.kind
			s.roof.corners = layout.points.duplicate()
			s.roof.center = cover.center
			s.roof.radius = cover.radius
			s.roof.pitch = cover.pitch
			s.roof.curve = cover.curve
			s.roof.overhang = cover.overhang
			s.roof.base = s.feet[0] + s.rise
			s.roof.foot = layout.stands_at() if layout.samples.size() > 0 else -INF
	else:
		for q in layout.samples:
			s.line.append(Vector2(q.x, q.z))
			s.feet.append(q.y)
		if s.line.size() > 1:
			s.outer = Geometry2D.offset_polyline(s.line, half)
		s.eaves = s.outer
		for i in s.line.size():
			var c := Vector2i((s.line[i] / CELL).floor())
			if not s._cells.has(c):
				s._cells[c] = PackedInt32Array()
			s._cells[c].append(i)
	s.rect = Rect2(s.line[0] if s.line.size() > 0 else Vector2.ZERO, Vector2.ZERO)
	for p in s.line:
		s.rect = s.rect.expand(p)
	s.rect = s.rect.grow(half + maxf(REACH, cover.overhang if cover != null else RoofLayout.OVERHANG))
	s._key = [s.closed, s.line, s.feet, s.rise, [s.roof.kind, s.roof.pitch, s.roof.curve, s.roof.overhang] if s.roof != null else null]
	return s


## Whether `other` takes up the same room.
func same(other: Massing) -> bool:
	return other != null and _key == other._key


## Height of the top a build standing at (x, z) rests on, or NAN where this one is not under it.
func rest(x: float, z: float) -> float:
	var p := Vector2(x, z)
	if not rect.has_point(p):
		return NAN
	if closed:
		return feet[0] + rise if encloses(p, outer) else NAN
	var i := _nearest(p, WallLayout.THICKNESS * 0.5 + REACH)
	return feet[i] + rise if i >= 0 else NAN


## Whether `p` lies in the room inside this house or tower, between its feet and its roof or top: a joined
## build lays nothing there.
func holds(p: Vector3) -> bool:
	if not closed or not rect.has_point(Vector2(p.x, p.z)) or p.y < feet[0]:
		return false
	var ceiling := roof.height_at(p.x, p.z) if roof != null else feet[0] + rise
	return p.y < ceiling and encloses(Vector2(p.x, p.z), inner)


## Whether `p` lies under this build and above the top it stands on: what it stands on lays nothing there.
func covers(p: Vector3) -> bool:
	var at := Vector2(p.x, p.z)
	if not rect.has_point(at) or not encloses(at, eaves):
		return false
	var i := 0 if closed else _nearest(at, WallLayout.THICKNESS)
	return i >= 0 and p.y > feet[i] + WallLayout.SINK


func _nearest(p: Vector2, within: float) -> int:
	var best := within * within
	var found := -1
	var c := Vector2i((p / CELL).floor())
	var span := ceili(within / CELL)
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			for i: int in _cells.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var d := line[i].distance_squared_to(p)
				if d <= best:
					best = d
					found = i
	return found


## Holes come back from Geometry2D nested in their outlines, so a point inside an odd count of them is inside.
static func encloses(p: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	var n := 0
	for poly in polygons:
		if Geometry2D.is_point_in_polygon(p, poly):
			n += 1
	return n % 2 == 1

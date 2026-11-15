class_name Interior
extends Bake

## Inside a room, light comes only through its openings, whatever the shadow map holds: shell shadow boxes leak at
## every joint and the ladder's lowest steps cast no sun shadow. room_field per STEP: r how far inside a room's wall
## centre line, g lowest floor less BELOW, b highest ceiling, a group row. room_data: a row per group of its lit openings.

## Metres; well within a wall's half-thickness, so a face reads its own side however its texel's corners fall.
const STEP := 0.25
const SIZE := int(Terrain.SIZE / STEP)
## Metres below the floor a room reaches, so a floor raised by a later lay stays in it.
const BELOW := 0.5
## Added to a row across an opening; room_row_at rounds it away. Rows stay under 256, where a half float holds it.
const OPENING_MARK := 0.25
## A stack shares its height this far outside its centre line, over its walls' stones.
const SHELL_REACH := WallLayout.THICKNESS * 0.5 + STEP
## room_data row: the count, then OPENING texels per opening.
const WIDTH := 256
const GROUPS := 256
## room_field's alpha where no room is.
const NO_ROOM := 0
const OPENING := 4

var field := ImageTexture.new()
var data := ImageTexture.new()
## Unmasked lights every shell as if no room stood: the driver's "interior" layer measures the rooms' cost by it.
var masked := true:
	set(value):
		masked = value
		RenderingServer.global_shader_parameter_set(&"room_field", field if masked else _unmasked)
		RenderingServer.global_shader_parameter_set(&"room_nearest", field if masked else _unmasked)
var _unmasked := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBAH))
var _rooms := Lamps.Rooms.new()
var to_light := Vector3.UP
var _cells := false
var _solved_toward := Vector3.UP


func _init() -> void:
	field.set_image(Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBAH))
	data.set_image(Image.create_empty(WIDTH, GROUPS, false, Image.FORMAT_RGBAF))


func install() -> void:
	masked = masked
	RenderingServer.global_shader_parameter_set(&"room_data", data)


func enclose(rooms: Lamps.Rooms) -> void:
	_rooms = rooms
	_cells = true


func _next() -> Callable:
	if not _cells and (_rooms.all.is_empty() or to_light.is_equal_approx(_solved_toward)):
		return Callable()
	var job := {"rooms": _rooms, "toward": to_light, "cells": _cells}
	_cells = false
	_solved_toward = to_light
	return _work.bind(job)


static func _work(job: Dictionary) -> Dictionary:
	var packed := pack(job.rooms, job.toward, job.cells)
	var out := {"data": Image.create_from_data(WIDTH, GROUPS, false, Image.FORMAT_RGBAF, packed.data.to_byte_array())}
	if job.cells:
		out.field = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBAF, packed.field.to_byte_array())
		out.field.convert(Image.FORMAT_RGBAH)
	return out


func _take(out: Dictionary) -> void:
	if out.has("field"):
		field.update(out.field)
	data.update(out.data)


## A group past GROUPS - 1 rows, or whose openings overflow WIDTH, goes unmasked.
static func pack(rooms: Lamps.Rooms, toward: Vector3, cells := true) -> Dictionary:
	var field_floats := PackedFloat32Array()
	if cells:
		field_floats.resize(SIZE * SIZE * 4)
	var floats := PackedFloat32Array()
	floats.resize(WIDTH * GROUPS * 4)
	var row := NO_ROOM
	for members: Array in rooms.covered:
		var portals := []
		for m: Lamps.Room in members:
			for o: Dictionary in m.portals:
				var crossed := crossing(o, toward)
				if not crossed.is_empty():
					portals.append(crossed)
		if row == GROUPS - 1 or 1 + portals.size() * OPENING > WIDTH:
			continue
		row += 1
		var at := row * WIDTH * 4
		floats[at] = portals.size()
		if cells:
			for m: Lamps.Room in members:
				_fill(field_floats, m, row)
		for k in portals.size():
			var crossed: Array = portals[k]
			for i in crossed.size():
				floats[at + (1 + k * OPENING) * 4 + i] = crossed[i]
	if cells:
		for members: Array in rooms.covered:
			for m: Lamps.Room in members:
				_mark_openings(field_floats, m)
	return {"field": field_floats, "data": floats}


## Texels as interior.gdshaderinc reads them: 0-1 across and up from the sill's middle where the ray to the light
## crosses the opening, as dot(p, xyz) + w; 2 the plane to stand inside, half-width; 3 height, rounding. A deep
## reveal narrows the patch. Empty if no light gets through.
static func crossing(o: Dictionary, toward: Vector3) -> Array:
	var n: Vector3 = o.out
	var facing := toward.dot(n)
	if facing <= 1e-3:
		return []
	var side := Vector3(-n.z, 0.0, n.x)
	var across := side - n * (toward.dot(side) / facing)
	var up := Vector3.UP - n * (toward.y / facing)
	var depth: float = o.depth
	var shift := Vector2(toward.dot(side), toward.y) * (depth / facing)
	var half: float = o.half - absf(shift.x)
	var tall: float = o.tall - 2.0 * absf(shift.y)
	if half <= 0.0 or tall <= 0.0:
		return []
	var at: Vector3 = o.at
	return [across.x, across.y, across.z, -at.dot(across), up.x, up.y, up.z, -at.dot(up) - absf(shift.y),
		n.x, n.z, at.dot(n) + depth, half, tall, minf(absf(o.round), half) * signf(o.round), 0.0, 0.0]


## Storeys stacked on one wall line share a texel's floor-to-ceiling span, so a stone rising into the next storey
## stays in; a wing or set-in storey keeps its own.
static func _fill(field: PackedFloat32Array, room: Lamps.Room, row: int) -> void:
	var bounds := room.rect.grow(WallLayout.THICKNESS + STEP)
	var a := _texel_of(bounds.position)
	var b := _texel_of(bounds.end)
	for j in range(maxi(a.y, 0), mini(b.y + 1, SIZE)):
		for i in range(maxi(a.x, 0), mini(b.x + 1, SIZE)):
			var middle := Vector2(-Terrain.SIZE * 0.5 + (i + 0.5) * STEP, -Terrain.SIZE * 0.5 + (j + 0.5) * STEP)
			var inside := INF
			for line in room.massing.centre:
				for k in line.size():
					var near := Geometry2D.get_closest_point_to_segment(middle, line[k], line[(k + 1) % line.size()])
					inside = minf(inside, middle.distance_to(near))
			if not Massing.encloses(middle, room.massing.centre):
				inside = -inside
			var ceiling: float = room.roof.height_at(middle.x, middle.y) if room.roof != null else room.top
			var bottom := room.floor - BELOW
			var at := (j * SIZE + i) * 4
			if field[at + 3] > 0.0 and inside > -SHELL_REACH and absf(inside - field[at]) < STEP and (room.floor - BELOW <= field[at + 2] + BELOW and field[at + 1] <= ceiling + BELOW):
				bottom = minf(bottom, field[at + 1])
				ceiling = maxf(ceiling, field[at + 2])
				field[at + 1] = bottom
				field[at + 2] = ceiling
			if field[at + 3] > 0.0 and field[at] >= inside:
				continue
			field[at] = inside
			field[at + 1] = bottom
			field[at + 2] = ceiling
			field[at + 3] = row


## A reveal's face stands outside the centre line as a corner stone does; only the mark keeps it lit from outside.
static func _mark_openings(field: PackedFloat32Array, room: Lamps.Room) -> void:
	for o: Dictionary in room.portals:
		var at := Vector2(o.at.x, o.at.z)
		var out := Vector2(o.out.x, o.out.z)
		var side := Vector2(-out.y, out.x)
		var reach: float = o.half + STEP
		var a := _texel_of(at - Vector2.ONE * (reach + WallLayout.THICKNESS))
		var b := _texel_of(at + Vector2.ONE * (reach + WallLayout.THICKNESS))
		for j in range(maxi(a.y, 0), mini(b.y + 1, SIZE)):
			for i in range(maxi(a.x, 0), mini(b.x + 1, SIZE)):
				var to := Vector2(-Terrain.SIZE * 0.5 + (i + 0.5) * STEP, -Terrain.SIZE * 0.5 + (j + 0.5) * STEP) - at
				var texel := (j * SIZE + i) * 4 + 3
				if absf(to.dot(side)) <= reach and absf(to.dot(out)) <= WallLayout.THICKNESS * 0.5 + STEP and field[texel] > 0.0:
					field[texel] = floorf(field[texel]) + OPENING_MARK


static func _texel_of(p: Vector2) -> Vector2i:
	return Vector2i(((p + Vector2.ONE * Terrain.SIZE * 0.5) / STEP).floor())

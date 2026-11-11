class_name Interior
extends Bake

## Sun and moon reach inside a house or tower only through its openings (interior.gdshaderinc). The shell's shadow
## boxes leave gaps a shadow-map texel wide at every joint, and the ladder's lowest steps draw no sun shadows at all;
## so a shell shader lights a point inside a room only where the way to the light leaves it through a door, window,
## arch or dormer window, whatever the shadow map holds. The rooms (Lamps.Room) go to the shaders as three global
## textures: room_field, over the play area every STEP, how far inside a room's walls' centre line a point lies, the
## room's floor and ceiling there and its group's row; room_top, the highest ceiling of the rooms a point lies inside,
## which room_field's one room per texel cannot say of a stack of storeys; and room_data, a row per group of the openings facing the
## light, each as the light crosses it from inside. The field is remade when the rooms change, the rows when the
## light moves too.

## Metres between room_field's texels: well within the half-thickness either side of the centre line that a wall's
## faces stand at, so a face reads its own side however its texel's corners fall.
const STEP := 0.25
const SIZE := int(Terrain.SIZE / STEP)
## How far below the floor a room reaches, so a floor raised by a later lay stays in it.
const BELOW := 0.5
## Texels in a room_data row: the count, then OPENING per opening.
const WIDTH := 256
## Rows: room_field's alpha names the row, NO_ROOM where no room is.
const GROUPS := 256
const NO_ROOM := 0
const OPENING := 4

var field := ImageTexture.new()
var top := ImageTexture.new()
var data := ImageTexture.new()
## Whether the shaders read the rooms: unmasked, every shell is lit as if no room stood, which the driver's "interior"
## layer measures the rooms' cost against.
var masked := true:
	set(value):
		masked = value
		RenderingServer.global_shader_parameter_set(&"room_field", field if masked else _unmasked)
		RenderingServer.global_shader_parameter_set(&"room_nearest", field if masked else _unmasked)
var _unmasked := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBAH))
var _rooms := Lamps.Rooms.new()
## The way to the sun or moon.
var to_light := Vector3.UP
## Whether the next solve packs the field too, and the light the last one packed rows from.
var _cells := false
var _solved_toward := Vector3.UP


func _init() -> void:
	field.set_image(Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBAH))
	top.set_image(Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RH))
	data.set_image(Image.create_empty(WIDTH, GROUPS, false, Image.FORMAT_RGBAF))


func install() -> void:
	masked = masked
	RenderingServer.global_shader_parameter_set(&"room_data", data)
	RenderingServer.global_shader_parameter_set(&"room_top", top)


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
		out.top = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, packed.top.to_byte_array())
		out.top.convert(Image.FORMAT_RH)
	return out


func _take(out: Dictionary) -> void:
	if out.has("field"):
		field.update(out.field)
		top.update(out.top)
	data.update(out.data)


## The textures' contents for `rooms` lit from `toward`: room_field's floats, unless `cells` is false, and room_data's
## floats. Only covered groups are packed; past GROUPS - 1 of them, or a row's WIDTH, the rest go unmasked.
static func pack(rooms: Lamps.Rooms, toward: Vector3, cells := true) -> Dictionary:
	var field_floats := PackedFloat32Array()
	var tops := PackedFloat32Array()
	if cells:
		field_floats.resize(SIZE * SIZE * 4)
		tops.resize(SIZE * SIZE)
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
				_fill(field_floats, tops, m, row)
		for k in portals.size():
			var crossed: Array = portals[k]
			for i in crossed.size():
				floats[at + (1 + k * OPENING) * 4 + i] = crossed[i]
	return {"field": field_floats, "top": tops, "data": floats}


## An opening as interior.gdshaderinc reads it with the light from `toward`: where a point's ray toward the light
## crosses its plane, across and up from the middle of its sill, as dot(p, xyz) + w of the first two texels, narrowed
## by how far the ray runs across through the wall's depth so a deep reveal narrows the patch; the plane the point must
## stand inside, its half-width and its rounding, then its height. Empty for one facing away from the light or seen
## too obliquely to let any through.
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


## Writes `room`'s field over the texels round it: how far inside its walls' centre line each lies (negative
## outside), the lowest it reaches below its floor, its ceiling and `row`, where it is further inside than any
## neighbour already there; `tops` takes its ceiling wherever a texel lies inside it and that is the highest yet.
static func _fill(field: PackedFloat32Array, tops: PackedFloat32Array, room: Lamps.Room, row: int) -> void:
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
			if inside > 0.0:
				tops[j * SIZE + i] = maxf(tops[j * SIZE + i], ceiling)
			var at := (j * SIZE + i) * 4
			if field[at + 3] > 0.0 and field[at] >= inside:
				continue
			field[at] = inside
			field[at + 1] = room.floor - BELOW
			field[at + 2] = ceiling
			field[at + 3] = row


static func _texel_of(p: Vector2) -> Vector2i:
	return Vector2i(((p + Vector2.ONE * Terrain.SIZE * 0.5) / STEP).floor())

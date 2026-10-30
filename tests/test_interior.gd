extends "res://../tests/support/suite.gd"

## Headless checks of the rooms the sun reaches only through openings (Interior): godot4 --headless --path game
## --script ../tests/test_interior.gd


func _init() -> void:
	_a_house_packs_its_shape_and_openings()
	_an_open_loop_is_left_out()
	_a_dormer_window_lets_the_sun_in()
	_houses_apart_take_their_own_rows()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


## A 7×5 house from x 0 to 7 and z -2.5 to 2.5, an archway in the middle of the wall at z -2.5 and a window in the
## middle of the wall at z 2.5, its roof bearing `dormers`.
func _house(cover := WallLayout.Cover.ROOF, dormers: Array[Vector2] = [], at := Vector3.ZERO) -> Lamps.Room:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(at, at + Vector3(7, 0, 0), 5)
	w.closed = true
	w.cover = cover
	w.top = WallLayout.Top.CAP
	w.height = 2.4
	w.openings.assign([3.5].map(WallLayout.archway))
	w.openings.append_array([Vector4(15.5, 1.6, 0, 1)])
	w.build(Terrain.flat)
	var roof: RoofLayout = null
	if cover == WallLayout.Cover.ROOF:
		roof = RoofLayout.new()
		roof.pitch = 2.5
	var massing := Massing.of(w, roof)
	if massing.roof != null:
		massing.roof.dormers = dormers
	return Lamps.Room.of(w, massing, massing.roof)


func _cell(packed: Dictionary, x: float, z: float) -> int:
	var c := Vector2i(((Vector2(x, z) + Vector2.ONE * Terrain.SIZE * 0.5) / Interior.STEP).floor())
	return int(packed.field[(c.y * Interior.SIZE + c.x) * 4 + 3])


## How far inside the room's walls' centre line the field puts (x, z).
func _inside(packed: Dictionary, x: float, z: float) -> float:
	var c := Vector2i(((Vector2(x, z) + Vector2.ONE * Terrain.SIZE * 0.5) / Interior.STEP).floor())
	return packed.field[(c.y * Interior.SIZE + c.x) * 4]


func _texel(packed: Dictionary, row: int, texel: int) -> Vector4:
	var at := (row * Interior.WIDTH + texel) * 4
	return Vector4(packed.data[at], packed.data[at + 1], packed.data[at + 2], packed.data[at + 3])


## Toward a sun high over the archway's side: its light can come in through the archway, never the window.
const OVER_ARCH := Vector3(0.0, 0.8, -0.6)


func _a_house_packs_its_shape_and_openings() -> void:
	var packed := Interior.pack([_house()], OVER_ARCH)
	check(_cell(packed, 3.5, 0.0) == 1 and _cell(packed, 0.1, -2.4) == 1, "the house's cells name its row")
	check(_cell(packed, 3.5, 6.0) == 0 and _cell(packed, -4.0, 0.0) == 0, "the meadow round it names none")
	check(_texel(packed, 1, 0).x == 1.0, "of its two openings only the archway faces the sun: %s" % _texel(packed, 1, 0))
	check(_inside(packed, 3.5, 0.0) > 2.0 and _inside(packed, 0.5, 0.0) > 0.0 and _inside(packed, 0.5, 0.0) < 0.75, "the field runs to the walls' centre line: %.2f, %.2f" % [_inside(packed, 3.5, 0.0), _inside(packed, 0.5, 0.0)])
	check(_inside(packed, -0.5, 0.0) < 0.0, "and below zero past it: %.2f" % _inside(packed, -0.5, 0.0))
	var plane := _texel(packed, 1, 3)
	check(Vector2(plane.x, plane.y).is_equal_approx(Vector2(0.0, -1.0)), "the archway faces out of the house: %s" % plane)
	var size := _texel(packed, 1, 4)
	check(size.x > 0.5 and is_equal_approx(size.y, plane.w), "its head rounded across its width: %s, %s" % [plane, size])
	var lit := _lit(packed, Vector3(3.5, 1.0, -2.5) - OVER_ARCH * 1.2)
	var dark := _lit(packed, Vector3(1.0, 0.3, 1.5))
	check(lit < 0.0 and dark > 0.0, "a point on the floor whose way to the sun leaves through the archway is lit, one at the back is not: %.2f, %.2f" % [lit, dark])
	check(Interior.pack([_house()], Vector3.UP).data[Interior.WIDTH * 4] == 0.0, "a sun straight overhead comes through no opening")


## The archway's edge distance for `p` as interior.gdshaderinc reckons it, negative inside its outline.
func _lit(packed: Dictionary, p: Vector3) -> float:
	var across := _texel(packed, 1, 1)
	var up := _texel(packed, 1, 2)
	var plane := _texel(packed, 1, 3)
	var size := _texel(packed, 1, 4)
	var at := Vector2(p.dot(Vector3(across.x, across.y, across.z)) + across.w, p.dot(Vector3(up.x, up.y, up.z)) + up.w)
	var top := absf(size.y)
	var edge := maxf(absf(at.x) - plane.w, maxf(-at.y, at.y - size.x))
	var upper := Vector2(absf(at.x) - (plane.w - top), at.y - (size.x - top))
	if upper.x > 0.0 and upper.y > 0.0:
		edge = upper.length() - top
	return edge


func _an_open_loop_is_left_out() -> void:
	var packed := Interior.pack([_house(WallLayout.Cover.OPEN)], OVER_ARCH)
	check(_cell(packed, 3.5, 0.0) == 0, "a loop open to the sky masks no sun")


func _a_dormer_window_lets_the_sun_in() -> void:
	var room := _house(WallLayout.Cover.ROOF, [Vector2(0.0, 1.5)])
	var windows := room.roof.dormer_windows()
	check(windows.size() == 1, "the dormer stands on the slope")
	if windows.is_empty():
		return
	var toward: Vector3 = (windows[0].out + Vector3.UP).normalized()
	var packed := Interior.pack([room], toward)
	check(_texel(packed, 1, 0).x >= 1.0, "a sun before its front comes in through its window: %s" % _texel(packed, 1, 0))
	check(windows[0].at.y > room.roof.base, "up in the roof: %s" % windows[0].at)


func _houses_apart_take_their_own_rows() -> void:
	var a := _house()
	var b := _house(WallLayout.Cover.ROOF, [], Vector3(20, 0, 0))
	var packed := Interior.pack([a, b], OVER_ARCH)
	check(_cell(packed, 3.5, 0.0) == 1 and _cell(packed, 23.5, 0.0) == 2, "apart, each house has its own row")

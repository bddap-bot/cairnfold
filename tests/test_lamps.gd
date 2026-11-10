extends "res://../tests/support/suite.gd"

## Headless checks of baked lantern light in and around a house: godot4 --headless --path game --script ../tests/test_lamps.gd

var ground := PackedFloat32Array()


func _init() -> void:
	ground.resize(Bounce.CELLS * Bounce.CELLS)
	_merged_rooms_share_light()
	_a_house_keeps_its_light_in()
	_windows_and_doors_let_it_out()
	_window_strength_does_not_brighten_the_room()
	_a_house_keeps_light_out()
	_an_open_loop_lets_light_up()
	_openings_admit_exterior_light()
	_rooms_limit_sky()
	_a_room_passes_on_the_light_it_lets_in()
	_sky_stays_out_a_layer_over_the_roof()
	_a_live_hump_solves_nothing()
	finish()


func _at(layers: Array[PackedByteArray], x: float, z: float, layer: int) -> float:
	var c := Bounce.column(x, z)
	return layers[layer][(c.y * Bounce.CELLS + c.x) * 4] / 255.0 * Lamps.ENCODE


func _a_house_keeps_its_light_in() -> void:
	var house := lit_house()
	var flame := PackedVector3Array([Vector3(1.0, 1.8, 0.0)])
	var open := Lamps.shine(flame, ground)
	var held := Lamps.shine(flame, ground, Lamps.Rooms.new([house]))
	check(_at(held, 3.5, 0.5, 0) > 0.1 and _at(held, 3.5, 0.5, 0) == _at(open, 3.5, 0.5, 0), "the floor is as lit as without walls: %.2f, %.2f" % [_at(held, 3.5, 0.5, 0), _at(open, 3.5, 0.5, 0)])
	check(_at(held, 6.5, 1.5, 3) == _at(open, 6.5, 1.5, 3), "and so is the far end under the roof")
	check(_at(open, 3.5, 0.5, 5) > 0.05 and _at(held, 3.5, 0.5, 5) == 0.0, "the air over the roof stays dark: %.2f without walls" % _at(open, 3.5, 0.5, 5))
	check(_at(open, -1.5, 0.5, 1) > 0.1 and _at(held, -1.5, 0.5, 1) == 0.0, "and the air beyond a wall without openings")


func _windows_and_doors_let_it_out() -> void:
	var house := lit_house()
	var held := Lamps.shine(PackedVector3Array([Vector3(3.5, 1.8, 0.0)]), ground, Lamps.Rooms.new([house]))
	var window := _at(held, 3.5, 4.5, 0)
	var door := _at(held, 3.5, -4.5, 0)
	check(window > 0.1, "light falls on the ground outside a window: %.2f" % window)
	check(_at(held, 3.5, 6.5, 0) == 0.0, "and is gone a few metres out")
	check(_at(held, 3.5, 4.5, 2) == 0.0, "and none rises toward the eaves over it")
	check(door > 0.0 and door < window * 0.5, "a doorway lets a little out: %.2f beside the window's %.2f" % [door, window])


func _a_house_keeps_light_out() -> void:
	var house := lit_house()
	var flame := PackedVector3Array([Vector3(7.8, 1.8, 0.5)])
	var held := Lamps.shine(flame, ground, Lamps.Rooms.new([house]))
	check(_at(held, 3.5, 0.5, 1) == 0.0, "a lantern outside lights nothing inside")
	check(_at(Lamps.shine(flame, ground), -0.5, 0.5, 1) > 0.0 and _at(held, -0.5, 0.5, 1) == 0.0, "nor beyond the house")
	check(_at(held, 8.5, 0.5, 0) > 0.3, "but lights its own side")


func _window_strength_does_not_brighten_the_room() -> void:
	var house := lit_house()
	var flames := PackedVector3Array([Vector3(3.5, 1.8, 0.0)])
	var bright := Lamps.shine(flames, ground, Lamps.Rooms.new([house]))
	for o in house.openings:
		if o.gives != Lamps.DOOR:
			o.gives = 1.0
	var plain := Lamps.shine(flames, ground, Lamps.Rooms.new([house]))
	check(absf(_at(bright, 3.5, 4.5, 0) - _at(plain, 3.5, 4.5, 0) * Lamps.WINDOW_GLOW) < Lamps.ENCODE / 255.0 * Lamps.WINDOW_GLOW,
		"the window strength reaches the ground outside")
	check(_at(bright, 3.5, 0.5, 1) == _at(plain, 3.5, 0.5, 1), "window strength leaves the interior's light alone")
	check(_at(bright, 3.5, -4.5, 0) == _at(plain, 3.5, -4.5, 0), "window strength leaves the doorway's spill alone")
	var dark := Lamps.shine(PackedVector3Array(), ground, Lamps.Rooms.new([house]))
	check(_at(dark, 3.5, 4.5, 0) == 0.0, "without an interior flame the window gives no light")
	check(Stones.shared_material().get_shader_parameter("window_glow") == Lamps.WINDOW_GLOW, "the pane and spill share their strength")


func _an_open_loop_lets_light_up() -> void:
	var yard := lit_house(WallLayout.Cover.OPEN)
	var held := Lamps.shine(PackedVector3Array([Vector3(1.0, 1.8, 0.0)]), ground, Lamps.Rooms.new([yard]))
	check(_at(held, 3.5, 0.5, 4) > 0.0, "over a loop without a roof the light goes up")
	check(_at(held, -1.5, 0.5, 1) == 0.0, "its walls still hold it in")


func _merged_rooms_share_light() -> void:
	var layouts: Array[WallLayout] = []
	var masses: Array[Massing] = []
	for x in [0.0, 3.0, 6.0]:
		var w := WallLayout.new()
		w.points = WallLayout.rectangle(Vector3(x, 0, 0), Vector3(x + 5, 0, 0), 5)
		w.closed = true
		w.cover = WallLayout.Cover.DECK
		w.height = 3.0
		w.build(Terrain.flat)
		layouts.append(w)
		masses.append(Massing.of(w, null))
	var rooms: Array[Lamps.Room] = []
	for i in layouts.size():
		for j in layouts.size():
			if i != j:
				layouts[i].joined.append(masses[j])
		rooms.append(Lamps.Room.of(layouts[i], Massing.of(layouts[i], null)))
	var flame := PackedVector3Array([Vector3(1.5, 1.8, 0.5)])
	var open := Lamps.shine(flame, ground)
	var merged := Lamps.shine(flame, ground, Lamps.Rooms.new(rooms))
	for x in [4.5, 5.5, 7.5]:
		print("merge light x=%.1f: %.6f; unobstructed %.6f" % [x, _at(merged, x, 0.5, 1), _at(open, x, 0.5, 1)])
		check(_at(open, x, 0.5, 1) > 0.0 and _at(merged, x, 0.5, 1) == _at(open, x, 0.5, 1), "light crosses both old seams, including the third room")
	check(_at(merged, 5.5, 3.5, 1) == 0.0, "merged outer walls keep their light in")

	rooms.reverse()
	var reversed := Lamps.shine(flame, ground, Lamps.Rooms.new(rooms))
	check(reversed == merged, "merged light does not depend on building order")
	layouts[1].joined.clear()
	layouts[2].joined.clear()
	layouts[0].joined.clear()
	rooms.clear()
	for i in layouts.size():
		rooms.append(Lamps.Room.of(layouts[i], Massing.of(layouts[i], null)))
	var apart := Lamps.shine(flame, ground, Lamps.Rooms.new(rooms))
	check(_at(apart, 7.5, 0.5, 1) == 0.0, "overlapping outlines alone do not connect rooms without removed walls")


func _a_live_hump_solves_nothing() -> void:
	var terrain := Terrain.new()
	var lamps := Lamps.new()
	lamps.terrain = terrain
	lamps.light([], PackedVector3Array([Vector3(1.0, 1.8, 0.0)]))
	lamps.finish()
	terrain.set_hump(0, 1.0, 0.0, 3.0, 1.0)
	lamps.update()
	check(lamps._task < 0, "a stroke's live hump, which the light never stands on, starts no solve")
	terrain.clear_hump(0)
	lamps.finish()
	var cells := Terrain.cells_around(1.0, 0.0, 3)
	var before := terrain.read(cells)
	var raised := before.duplicate()
	for i in raised.size():
		raised[i] += 1.0
	terrain.write(cells, raised)
	lamps.update()
	check(lamps._task >= 0, "ground raised under a lantern solves its light again")
	lamps.stop()


func _openings_admit_exterior_light() -> void:
	var room := lit_house()
	var flame := PackedVector3Array([Vector3(3.5, 1.2, -4.5)])
	var lit := Lamps.shine(flame, ground, Lamps.Rooms.new([room]))
	var near := _at(lit, 3.5, -1.5, 0)
	var far := _at(lit, 3.5, 1.5, 0)
	check(near > 0.0 and far < near, "an exterior flame spills through the arch and fades with depth")
	room.openings.clear()
	var closed := Lamps.shine(flame, ground, Lamps.Rooms.new([room]))
	check(_at(closed, 3.5, -1.5, 0) == 0.0, "closing the opening blocks that same flame")
	check(_at(closed, 3.5, -4.5, 0) > 0.0, "the exterior stays lit")


## The probes over and around `room` after it bounds them, the column bake having given every one `baked` and the
## builds `paint`, lit from `sun`.
func _sky_result(room: Lamps.Room, sun := Vector3.UP, paint := Color(0.6, 0.6, 0.6), baked := 255) -> Dictionary:
	var result := {"area": Rect2i(Bounce.column(-2, -4), Vector2i(12, 9)), "layers": []}
	for k in Bounce.LAYERS:
		var bytes := PackedByteArray()
		bytes.resize(result.area.size.x * result.area.size.y * 4)
		bytes.fill(baked)
		for i in range(3, bytes.size(), 4):
			bytes[i] = 255
		result.layers.append(bytes)
	var colors := PackedColorArray()
	colors.resize(Bounce.CELLS * Bounce.CELLS)
	colors.fill(paint)
	Bounce.enclose_probes(result, ground, Lamps.Rooms.new([room]), colors, sun)
	return result


func _bounce(result: Dictionary, x: float, z: float, layer := 0) -> int:
	var p := Bounce.column(x, z) - result.area.position as Vector2i
	return result.layers[layer][(p.y * result.area.size.x + p.x) * 4]


func _sky(result: Dictionary, x: float, z: float, layer := 0) -> int:
	var p := Bounce.column(x, z) - result.area.position as Vector2i
	return result.layers[layer][(p.y * result.area.size.x + p.x) * 4 + 3]


## A face under the roof reads the volume half a metre out, between layers a metre apart: a sealed room's probes less
## than a layer over its roof stay dark, and those clear of that band keep the sky for the roof's own covering.
func _sky_stays_out_a_layer_over_the_roof() -> void:
	var room := lit_house()
	room.openings.clear()
	var result := _sky_result(room)
	var band := 0
	var clear := 0
	for x in [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5]:
		for z in [-1.5, -0.5, 0.5, 1.5]:
			var over: float = room.roof.height_at(x, z) + Terrain.STEP * 0.5
			for k in Bounce.LAYERS:
				var y := k + 0.5
				if y >= over and y < over + Terrain.STEP * 0.5:
					band += 1
					check(_sky(result, x, z, k) == 0, "a probe %.2f m over the roof at (%.1f, %.1f) stays dark" % [y - over + Terrain.STEP * 0.5, x, z])
				elif y >= over + Terrain.STEP * 1.5:
					clear += 1
					check(_sky(result, x, z, k) == 255, "a probe a layer clear of the roof at (%.1f, %.1f) sees the sky" % [x, z])
	check(band > 0 and clear > 0, "the house has probes in and clear of the band over its roof")


## Light let in through a room's openings lights its back corner and ceiling off its walls and floor: sunlight only
## while the sun stands before an opening, sky light always, and less off darker stone.
func _a_room_passes_on_the_light_it_lets_in() -> void:
	var room := lit_house()
	var before_door := Vector3(0.0, 0.5, -1.0).normalized()
	var lit := _sky_result(room, before_door, Color(0.6, 0.6, 0.6), 0)
	var behind := _sky_result(room, -before_door, Color(0.6, 0.6, 0.6), 0)
	var dark := _sky_result(room, before_door, Color(0.2, 0.2, 0.2), 0)
	check(_bounce(lit, 0.5, 1.5, 2) > 0, "the sun through the door lights the back corner under the roof: %d" % _bounce(lit, 0.5, 1.5, 2))
	check(_bounce(lit, 0.5, 1.5, 2) > _bounce(behind, 0.5, 1.5, 2), "a sun behind the house lights less of its inside")
	check(_sky(behind, 0.5, 1.5, 2) > 0, "sky light let in still reaches the back corner under the roof")
	check(_bounce(dark, 0.5, 1.5, 2) < _bounce(lit, 0.5, 1.5, 2) and _sky(dark, 0.5, 1.5, 2) < _sky(lit, 0.5, 1.5, 2), "darker stone passes on less")
	room.openings.clear()
	var sealed := _sky_result(room, before_door, Color(0.6, 0.6, 0.6), 0)
	check(_bounce(sealed, 0.5, 1.5, 2) == 0 and _sky(sealed, 0.5, 1.5, 2) == 0, "a sealed room passes on nothing")


func _rooms_limit_sky() -> void:
	var room := lit_house()
	var result := _sky_result(room)
	check(_sky(result, 3.5, -1.5) > _sky(result, 0.5, 0.5), "daylight is stronger near an opening than in the back corner")
	room.openings.clear()
	result = _sky_result(room)
	check(_sky(result, 3.5, -1.5) == 0, "a closed room sees no sky even if the column bake leaks")
	var at := Bounce.column(3.5, -1.5) - result.area.position as Vector2i
	check(result.layers[0][(at.y * result.area.size.x + at.x) * 4] == 0, "a sealed room receives no exterior bounced sunlight")
	check(room.holds(Vector3(7.0, 1.0, 0.0), true) and not room.holds(Vector3(7.0, 1.0, 0.0)), "boundary probes cover the inner face without classifying exterior lamps as inside")
	check(_sky(result, -1.5, 0.5) == 255, "exterior sky remains unchanged")
	check(_sky(result, -0.5, 0.5) == 0, "the boundary probe cannot interpolate sky onto the inside face")
	var yard := lit_house(WallLayout.Cover.OPEN)
	yard.openings.clear()
	check(_sky(_sky_result(yard), 3.5, -1.5) == 255, "a roofless courtyard remains open to the sky")

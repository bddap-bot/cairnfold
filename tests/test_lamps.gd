extends SceneTree

## Headless checks of baked lantern light in and around a house: godot4 --headless --path game --script ../tests/test_lamps.gd

var failures := 0
var ground := PackedFloat32Array()


func _init() -> void:
	ground.resize(Bounce.CELLS * Bounce.CELLS)
	_merged_rooms_share_light()
	_a_house_keeps_its_light_in()
	_windows_and_doors_let_it_out()
	_window_strength_does_not_brighten_the_room()
	_a_house_keeps_light_out()
	_an_open_loop_lets_light_up()
	_a_live_hump_solves_nothing()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(_x: float, _z: float) -> float:
	return 0.0


## A 7×5 house on flat ground from x 0 to 7 and z -2.5 to 2.5, with an arched door in the middle of the wall at
## z -2.5 and a window in the middle of the wall at z 2.5.
func _house(cover := WallLayout.Cover.ROOF) -> Lamps.Room:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(7, 0, 0), 5)
	w.closed = true
	w.cover = cover
	w.top = WallLayout.Top.CAP
	w.height = 2.4
	w.openings.assign([3.5].map(WallLayout.archway))
	w.openings.append_array([Vector4(15.5, 1.6, 0, 1)])
	w.build(_flat)
	var roof: RoofLayout = null
	if cover == WallLayout.Cover.ROOF:
		roof = RoofLayout.new()
		roof.pitch = 2.5
	return Lamps.Room.of(w, Massing.of(w, roof))


func _at(layers: Array[PackedByteArray], x: float, z: float, layer: int) -> float:
	var c := Bounce.column(x, z)
	return layers[layer][c.y * Bounce.CELLS + c.x] / 255.0 * Lamps.ENCODE


func _a_house_keeps_its_light_in() -> void:
	var house := _house()
	var flame := PackedVector3Array([Vector3(1.0, 1.8, 0.0)])
	var open := Lamps.shine(flame, ground)
	var held := Lamps.shine(flame, ground, [house])
	_check(_at(held, 3.5, 0.5, 0) > 0.1 and _at(held, 3.5, 0.5, 0) == _at(open, 3.5, 0.5, 0), "the floor is as lit as without walls: %.2f, %.2f" % [_at(held, 3.5, 0.5, 0), _at(open, 3.5, 0.5, 0)])
	_check(_at(held, 6.5, 1.5, 3) == _at(open, 6.5, 1.5, 3), "and so is the far end under the roof")
	_check(_at(open, 3.5, 0.5, 5) > 0.05 and _at(held, 3.5, 0.5, 5) == 0.0, "the air over the roof stays dark: %.2f without walls" % _at(open, 3.5, 0.5, 5))
	_check(_at(open, -1.5, 0.5, 1) > 0.1 and _at(held, -1.5, 0.5, 1) == 0.0, "and the air beyond a wall without openings")


func _windows_and_doors_let_it_out() -> void:
	var house := _house()
	var held := Lamps.shine(PackedVector3Array([Vector3(3.5, 1.8, 0.0)]), ground, [house])
	var window := _at(held, 3.5, 4.5, 0)
	var door := _at(held, 3.5, -4.5, 0)
	_check(window > 0.1, "light falls on the ground outside a window: %.2f" % window)
	_check(_at(held, 3.5, 6.5, 0) == 0.0, "and is gone a few metres out")
	_check(_at(held, 3.5, 4.5, 2) == 0.0, "and none rises toward the eaves over it")
	_check(door > 0.0 and door < window * 0.5, "a doorway lets a little out: %.2f beside the window's %.2f" % [door, window])


func _a_house_keeps_light_out() -> void:
	var house := _house()
	var flame := PackedVector3Array([Vector3(7.8, 1.8, 0.5)])
	var held := Lamps.shine(flame, ground, [house])
	_check(_at(held, 3.5, 0.5, 1) == 0.0, "a lantern outside lights nothing inside")
	_check(_at(Lamps.shine(flame, ground), -0.5, 0.5, 1) > 0.0 and _at(held, -0.5, 0.5, 1) == 0.0, "nor beyond the house")
	_check(_at(held, 8.5, 0.5, 0) > 0.3, "but lights its own side")


func _window_strength_does_not_brighten_the_room() -> void:
	var house := _house()
	var flames := PackedVector3Array([Vector3(3.5, 1.8, 0.0)])
	var bright := Lamps.shine(flames, ground, [house])
	for o in house.openings:
		if o.gives != Lamps.DOOR:
			o.gives = 1.0
	var plain := Lamps.shine(flames, ground, [house])
	_check(absf(_at(bright, 3.5, 4.5, 0) - _at(plain, 3.5, 4.5, 0) * Lamps.WINDOW_GLOW) < Lamps.ENCODE / 255.0 * Lamps.WINDOW_GLOW,
		"the window strength reaches the ground outside")
	_check(_at(bright, 3.5, 0.5, 1) == _at(plain, 3.5, 0.5, 1), "window strength leaves the interior's light alone")
	_check(_at(bright, 3.5, -4.5, 0) == _at(plain, 3.5, -4.5, 0), "window strength leaves the doorway's spill alone")
	var dark := Lamps.shine(PackedVector3Array(), ground, [house])
	_check(_at(dark, 3.5, 4.5, 0) == 0.0, "without an interior flame the window gives no light")
	_check(Stones.shared_material().get_shader_parameter("window_glow") == Lamps.WINDOW_GLOW, "the pane and spill share their strength")


func _an_open_loop_lets_light_up() -> void:
	var yard := _house(WallLayout.Cover.OPEN)
	var held := Lamps.shine(PackedVector3Array([Vector3(1.0, 1.8, 0.0)]), ground, [yard])
	_check(_at(held, 3.5, 0.5, 4) > 0.0, "over a loop without a roof the light goes up")
	_check(_at(held, -1.5, 0.5, 1) == 0.0, "its walls still hold it in")


func _merged_rooms_share_light() -> void:
	var layouts: Array[WallLayout] = []
	var masses: Array[Massing] = []
	for x in [0.0, 3.0, 6.0]:
		var w := WallLayout.new()
		w.points = WallLayout.rectangle(Vector3(x, 0, 0), Vector3(x + 5, 0, 0), 5)
		w.closed = true
		w.cover = WallLayout.Cover.DECK
		w.height = 3.0
		w.build(_flat)
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
	var merged := Lamps.shine(flame, ground, rooms)
	for x in [4.5, 5.5, 7.5]:
		print("merge light x=%.1f: %.6f; unobstructed %.6f" % [x, _at(merged, x, 0.5, 1), _at(open, x, 0.5, 1)])
		_check(_at(open, x, 0.5, 1) > 0.0 and _at(merged, x, 0.5, 1) == _at(open, x, 0.5, 1), "light crosses both old seams, including the third room")
	_check(_at(merged, 5.5, 3.5, 1) == 0.0, "merged outer walls keep their light in")

	rooms.reverse()
	var reversed := Lamps.shine(flame, ground, rooms)
	_check(reversed == merged, "merged light does not depend on building order")
	layouts[1].joined.clear()
	layouts[2].joined.clear()
	layouts[0].joined.clear()
	rooms.clear()
	for i in layouts.size():
		rooms.append(Lamps.Room.of(layouts[i], Massing.of(layouts[i], null)))
	var apart := Lamps.shine(flame, ground, rooms)
	_check(_at(apart, 7.5, 0.5, 1) == 0.0, "overlapping outlines alone do not connect rooms without removed walls")


func _a_live_hump_solves_nothing() -> void:
	var lamps := Lamps.new()
	lamps.light([], PackedVector3Array([Vector3(1.0, 1.8, 0.0)]))
	lamps.finish()
	Terrain.set_hump(0, 1.0, 0.0, 3.0, 1.0)
	lamps.update()
	_check(lamps._task < 0, "a stroke's live hump, which the light never stands on, starts no solve")
	Terrain.clear_hump(0)
	lamps.finish()
	var cells := Terrain.cells_around(1.0, 0.0, 3)
	var before := Terrain.read(cells)
	var raised := before.duplicate()
	for i in raised.size():
		raised[i] += 1.0
	Terrain.write(cells, raised)
	lamps.update()
	_check(lamps._task >= 0, "ground raised under a lantern solves its light again")
	lamps.stop()
	Terrain.write(cells, before)

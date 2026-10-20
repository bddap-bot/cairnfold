extends SceneTree

## Headless checks that the teleport ray lands on whatever solid it meets in the garden, a pitched roof, a tree, a
## wall's top: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_teleport_solids.gd

var failures := 0
var main: Node


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var rig: Rig = main.rig
	rig.set_process(false)
	var world: World = main.world
	world.load_from(OS.get_temp_dir().path_join("nestcombe-teleport-%d.garden" % OS.get_process_id()))
	_onto_a_pitched_roof(rig, world)
	_onto_a_tree(rig, world)
	_onto_a_wall_top(rig, world)
	_onto_a_raised_floor(rig, world)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _pose(origin: Vector3, dir: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(dir, Vector3.UP), origin)


func _wall_data(points: PackedVector3Array) -> Dictionary:
	return {"points": points, "height": 2.6, "seed": 3, "closed": false, "top": 0, "fence": false, "openings": PackedVector4Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(), "ruins": PackedVector2Array(), "rise": 0.0, "plaster": false, "gable_end": 0, "timber_style": 0, "storey_floors": false, "on": PackedInt32Array(), "paint": Palette.plain()}


## Aims at `at` from `from`, lands, and checks the player stands upright where the ray hit, on `surface`'s height.
func _lands(rig: Rig, from: Vector3, at: Vector3, surface: Callable, what: String) -> void:
	rig.aim(_pose(from, at - from))
	var g: Variant = rig.aim_ground
	_check(g != null and rig.aim_lift == 0.0, "a ray %s has a landing where it hits: %s up %.2f" % [what, g, rig.aim_lift])
	if g == null:
		return
	rig.place(g, rig.aim_lift)
	var h := rig.head.global_position
	var stand := rig.global_position.y
	var want: float = surface.call(h)
	_check(absf(stand - want) < 0.3, "aimed %s, the player stands on it: %.2f for %.2f, ground %.2f" % [what, stand, want, Terrain.height_at(h.x, h.z)])
	_check(rig.global_basis.y.is_equal_approx(Vector3.UP), "aimed %s, the player stands upright" % what)


func _onto_a_pitched_roof(rig: Rig, world: World) -> void:
	var d := _wall_data(PackedVector3Array(WallLayout.rectangle(Terrain.ground(-40, 30), Terrain.ground(-34, 30), 4.0)))
	d.closed = true
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": Terrain.ground(-37, 30), "radius": 2.0, "pitch": 1.6, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "flag": false, "thatch": false}
	world._order({"op": "wall", "walls": [d]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	var r: RoofLayout = w.roof
	var f := r.frame()
	var slope: Vector3 = Vector3(f.mid.x, 0.0, f.mid.z) + f.across * r.half_span() * 0.5
	slope.y = r.height_at(slope.x, slope.z)
	var on_roof := func(p: Vector3) -> float: return r.height_at(p.x, p.z)
	_lands(rig, slope + Vector3(0, 9, 0) + f.across * 6.0, slope, on_roof, "from the air down onto a pitched roof")
	_lands(rig, Terrain.ground(slope.x, slope.z) + f.across * (r.half_span() + 3.0) + Vector3.UP * 1.2, slope, on_roof, "from the ground up onto a pitched roof")
	world._order({"op": "unwall", "ids": PackedInt32Array([w.id])}, 1)


func _onto_a_tree(rig: Rig, world: World) -> void:
	var flora: Flora = main.flora_tool.flora
	world._order({"op": "plant", "kind": "tree", "seed": 4, "at": Terrain.ground(-20, 40)}, 1)
	flora.grow_now()
	var parts: Array = flora.placed("tree")[-1]
	var crown: Flora.Plant = parts[-1]
	var top: Vector3 = crown.xform.translated(Vector3.UP * Terrain.base_at(crown.anchor.x, crown.anchor.z)) * crown.pool.mesh.get_aabb().get_center()
	var from := top + Vector3(0, 6, 8)
	var hit: Dictionary = flora.solid_hit(from, (top - from).normalized(), 50.0)
	_check(not hit.is_empty(), "a ray down at a tree's crown strikes it")
	var high := func(_p: Vector3) -> float: return hit.get("point", Vector3.ZERO).y
	_lands(rig, from, top, high, "down onto a tree")
	_check(rig.global_position.y - Terrain.height_at(top.x, top.z) > 1.0, "the landing on a tree is up in it, not on the ground under it")


func _onto_a_wall_top(rig: Rig, world: World) -> void:
	world._order({"op": "wall", "walls": [_wall_data(PackedVector3Array([Terrain.ground(10, -30), Terrain.ground(16, -30)]))]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	var mid := Terrain.ground(13, -30)
	var top := mid + Vector3.UP * (w.layout.height + WallLayout.CAP)
	var on_top := func(_p: Vector3) -> float: return top.y
	_lands(rig, top + Vector3(0, 5, 6), top, on_top, "down onto a wall's top")
	world._order({"op": "unwall", "ids": PackedInt32Array([w.id])}, 1)


func _onto_a_raised_floor(rig: Rig, world: World) -> void:
	var d := _wall_data(PackedVector3Array(WallLayout.rectangle(Terrain.ground(30, 30), Terrain.ground(36, 30), 4.0)))
	d.closed = true
	d.rise = 1.5
	d.openings = PackedVector4Array([3.0].map(WallLayout.archway))
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": Terrain.ground(33, 30), "radius": 2.0, "pitch": 1.6, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "flag": false, "thatch": false}
	world._order({"op": "wall", "walls": [d]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	var level := w.layout.floors[0]
	var inside := Vector3(33.5, level, 30.0)
	var on_floor := func(_p: Vector3) -> float: return level
	_check(level > Terrain.height_at(inside.x, inside.z) + 1.0, "the raised house's floor stands over the ground: %.2f" % level)
	_lands(rig, Vector3(32.5, level + 1.6, 30.3), inside, on_floor, "down onto a raised house's floor from inside")
	_check(is_equal_approx(main.tool.floor_under(inside + Vector3.UP * 0.5), level), "standing inside, the player stands on the floor, not the ground under it")
	var middle := Terrain.ground(33.0, 30.0)
	Ground.settle()
	_check(Ground.laid_bare(middle.x, middle.z) > 0.99, "the meadow under the floor is worn bare: %.2f" % Ground.laid_bare(middle.x, middle.z))
	_check(Ground.laid_bare(33.0, 30.0 + 2.0 + 1.0) < 0.01, "the meadow outside the walls is not")
	world._order({"op": "unwall", "ids": PackedInt32Array([w.id])}, 1)
	Ground.settle()
	_check(Ground.laid_bare(middle.x, middle.z) < 0.01, "taken away, the house gives the meadow back")

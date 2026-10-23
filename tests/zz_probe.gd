extends SceneTree
var main: Node
func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()
func _wall_data(points: PackedVector3Array) -> Dictionary:
	return {"points": points, "height": 2.6, "seed": 3, "closed": false, "top": 0, "fence": false, "openings": PackedVector4Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(), "ruins": PackedVector2Array(), "rise": 0.0, "plaster": false, "plinth_plaster": false, "gable_end": 0, "timber_style": 0, "on": PackedInt32Array(), "paint": Palette.plain()}
func _run() -> void:
	await process_frame
	main.world.bounded = false
	await process_frame
	var rig: Rig = main.rig
	rig.set_process(false)
	var world: World = main.world
	world.load_from(OS.get_temp_dir().path_join("nestcombe-probe-%d.garden" % OS.get_process_id()))
	var d := _wall_data(PackedVector3Array([Terrain.ground(-6, -14), Terrain.ground(6, -14)]))
	d.top = WallLayout.Top.CAP
	d.ruins = PackedVector2Array([Vector2(8.5, 9.5)])
	world._order({"op": "wall", "walls": [d]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	for k in range(40):
		var xo := 0.25 + k * 0.2
		var mid := w.layout.point_at(xo)
		var face := mid + Vector3(0, 0, WallLayout.THICKNESS * 0.5)
		var front := Terrain.ground(face.x, face.z + Rig.STAND_OFF)
		var from := Vector3(face.x, front.y + 1.6, face.z + 6.0)
		var line := "x%.0f:" % xo
		for i in range(2, 25):
			var up := i * 0.1
			var dir := (Vector3(face.x, front.y + up, face.z) - from).normalized()
			var s: Variant = rig.solid_hit.call(from, dir, 20.0)
			var b: float = rig._beneath(s - dir * 0.02) if s != null else NAN
			rig.aim(Transform3D(Basis.looking_at(dir, Vector3.UP), from))
			var g: Variant = rig.aim_ground
			if s != null and b >= s.y - Rig.FOOTING: line += " %.1f:%.3f" % [up, s.y - b]
		print(line)
	Main.quit(self, 0)

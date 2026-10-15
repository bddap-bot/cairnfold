class_name Wall
extends Node3D

## A drawn wall. Its stones and ivy are packed into instance buffers by part; while the wall changes it
## draws them itself, and once it settles it hands them to the glade's Masonry, which draws them per chunk.

enum Part { STONE, MORTAR, STONE_SHADOW, TILE, TILE_SHADOW, IVY }

static var _kinds: Array[Masonry.Kind] = []
static var _plaster: ShaderMaterial

var layout := WallLayout.new()
var masonry: Masonry
## Lantern flames and flags: few, alive, and drawn by the wall itself.
var _fittings := Fittings.new()
var finished := false
## The id of the build command that put it up; -1 while it is still being drawn.
var id := -1
## The roof on a house or tower, laid again with the walls under it.
var roof: RoofLayout
## Seconds since the wall was finished: how far its ivy has grown.
var ivy_age := 0.0
## Encloses every stone, for pointing.
var pick_bounds := AABB()
var _parts: Array[PackedFloat32Array] = []
## Each part's own MultiMesh while it is not settled, made when first needed.
var _live: Array[MultiMeshInstance3D] = []
var _gables: MeshInstance3D
var _settled := false
var _roof_live := false
var _ivy_times := PackedFloat32Array()
var _ivy_task := -1
var _ivy_baked := {}
var _ivy_stale := false
var _build_task := -1
var _build_stale := false
## Counts settling rebuilds, so a worker's layout that one overtook is dropped.
var _build_gen := 0
var _build_job: WallLayout
var _build_out := {}
## The preview now shown, with the ground revision it stands on: a settling rebuild with the same inputs
## takes it rather than laying the stones again.
var _shown: WallLayout
var _shown_ground := -1
var _settle_when_laid := false
## Stones a newer layout replaced. Freeing a long wall's thousands of them takes milliseconds, so the wall's
## next worker task does it.
var _litter: Array[Array] = []
## Where a bird can stand on the top (`WallLayout.perches`), and the `layout.laid` they were worked out from.
var _perches := PackedVector3Array()
var _perches_laid := -1
var _perch_task := -1
var _perch_out := {}


## How each Part is drawn. Stones, roof tiles and the mortar between stones cast no shadow; a plain box per
## stone or tile does, at a ninth of the triangles. Mortar only shows in the gaps, so it is a plain box too.
static func kinds() -> Array[Masonry.Kind]:
	if _kinds.is_empty():
		var box := BoxMesh.new()
		var leaf := ShaderMaterial.new()
		leaf.shader = load("res://src/ivy.gdshader")
		var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shadow := Masonry.Kind.new(box, null, false, false, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
		_kinds.resize(Part.size())
		_kinds[Part.STONE] = Masonry.Kind.new(Stones.mesh(), Stones.shared_material(), true, true, off, true)
		_kinds[Part.MORTAR] = Masonry.Kind.new(box, Stones.shared_material(), true, true, off)
		_kinds[Part.STONE_SHADOW] = shadow
		_kinds[Part.TILE] = Masonry.Kind.new(Meshes.rounded_box(0.22, 2, 41), Stones.shared_material(), true, true, off, true)
		_kinds[Part.TILE_SHADOW] = shadow
		_kinds[Part.IVY] = Masonry.Kind.new(Meshes.sprig(), leaf, true, false, off)
	return _kinds


func _init(seed: int, glade: Masonry) -> void:
	layout.seed = seed
	masonry = glade
	add_child(_fittings)
	_parts.resize(Part.size())
	_live.resize(Part.size())


## Puts a roof on this closed wall; its stones then stop flush under the eaves.
func add_roof(r: RoofLayout) -> void:
	roof = r
	_cover()
	if _plaster == null:
		_plaster = ShaderMaterial.new()
		_plaster.shader = load("res://src/plaster.gdshader")
		_plaster.set_shader_parameter("albedo", Color(0.8, 0.73, 0.6))
	_gables = MeshInstance3D.new()
	_gables.material_override = _plaster
	add_child(_gables)


## The wall as a build command carries it.
func data() -> Dictionary:
	var d := {
		"points": PackedVector3Array(layout.points), "height": layout.height, "arches": PackedFloat32Array(layout.arches),
		"seed": layout.seed, "closed": layout.closed, "top": int(layout.top), "fence": layout.fence,
		"windows": PackedVector2Array(layout.windows), "lanterns": PackedVector3Array(layout.lanterns), "flags": PackedFloat32Array(layout.flags),
		"ruins": PackedVector2Array(layout.ruins), "plaster": layout.plaster,
	}
	if roof != null:
		d.roof = {"kind": int(roof.kind), "center": roof.center, "radius": roof.radius, "pitch": roof.pitch, "curve": roof.curve, "seed": roof.seed, "chimneys": PackedVector2Array(roof.chimneys), "flag": roof.flag}
	return d


func set_data(d: Dictionary) -> void:
	layout.points.assign(Array(d.points))
	layout.height = d.height
	layout.arches.assign(Array(d.arches))
	layout.seed = d.seed
	layout.closed = d.closed
	layout.top = d.top as WallLayout.Top
	layout.fence = d.fence
	layout.plaster = d.get("plaster", false)
	layout.windows.assign(Array(d.windows))
	layout.lanterns.assign(Array(d.lanterns))
	layout.flags.assign(Array(d.flags))
	layout.ruins.assign(Array(d.ruins))
	if d.has("roof"):
		if roof == null:
			add_roof(RoofLayout.new())
		for k in ["center", "radius", "pitch", "curve", "seed", "flag"]:
			roof.set(k, d.roof[k])
		roof.kind = d.roof.kind as RoofLayout.Kind
		roof.chimneys.assign(Array(d.roof.chimneys))
		_cover()


func _cover() -> void:
	layout.cover = WallLayout.Cover.OPEN if roof == null else WallLayout.Cover.DECK if roof.flat() else WallLayout.Cover.ROOF


func _ready() -> void:
	set_process(finished or _build_task >= 0)


func _process(delta: float) -> void:
	if _build_task >= 0 and WorkerThreadPool.is_task_completed(_build_task):
		WorkerThreadPool.wait_for_task_completion(_build_task)
		_build_task = -1
		if _build_out.gen == _build_gen:
			_litter.append(layout.stones)
			layout.adopt(_build_job)
			_take(_build_out)
			_shown = _build_job
			_shown_ground = _build_out.ground
			if _settle_when_laid and not _build_stale:
				_shown_ground = Terrain.revision
				rebuild()
			else:
				_lay_dressing()
				_sync()
		if _build_stale:
			_build_live()
	if finished:
		ivy_age += delta
	if _ivy_task >= 0 and WorkerThreadPool.is_task_completed(_ivy_task):
		WorkerThreadPool.wait_for_task_completion(_ivy_task)
		_ivy_task = -1
		_parts[Part.IVY] = _ivy_baked.buffer
		_ivy_times = _ivy_baked.times
		_sync()
		if _ivy_stale:
			_layout_ivy()
	if _live[Part.IVY] != null:
		var mm := _live[Part.IVY].multimesh
		mm.visible_instance_count = mini(_ivy_times.bsearch(ivy_age), mm.instance_count)
	if _build_task < 0 and not _ivy_growing():
		set_process(false)
		if _settled:
			_sync()


func _ivy_growing() -> bool:
	return _ivy_task >= 0 or (not _ivy_times.is_empty() and ivy_age <= _ivy_times[-1])


func _exit_tree() -> void:
	for t in [_ivy_task, _build_task, _perch_task]:
		if t >= 0:
			WorkerThreadPool.wait_for_task_completion(t)
	_ivy_task = -1
	_build_task = -1
	_perch_task = -1
	masonry.remove(get_instance_id())


## Where a bird can stand on the wall's top, as last worked out. Working them out reads every stone, several
## milliseconds for a long wall, so once the stones are laid again it is done on a worker thread, and not while a
## newer preview is being laid; until it is done, the old ones stand.
func perches() -> PackedVector3Array:
	if _perch_task >= 0 and WorkerThreadPool.is_task_completed(_perch_task):
		WorkerThreadPool.wait_for_task_completion(_perch_task)
		_perch_task = -1
		_perches = _perch_out.points
		_perches_laid = _perch_out.laid
	if _perch_task < 0 and _perches_laid != layout.laid and not laying():
		var job := WallLayout.new()
		job.stones = layout.stones.duplicate()
		job.cover = layout.cover
		var out := {"laid": layout.laid}
		_perch_out = out
		_perch_task = WorkerThreadPool.add_task(func(): out.points = job.perches())
	return _perches


## Ivy for a long wall takes longer than a frame to lay out, so it grows on a worker thread from a snapshot.
func _layout_ivy() -> void:
	set_process(true)
	if _ivy_task >= 0:
		_ivy_stale = true
		return
	_ivy_stale = false
	var shape := layout.snapshot()
	var out := _ivy_baked
	out.clear()
	var litter := _sweep()
	_ivy_task = WorkerThreadPool.add_task(func():
		_drop(litter)
		out.merge(IvyLayout.bake(shape)))


## Lays the stones again. With `settle`, at once, and the wall then settles into the Masonry with its ivy.
## Without, while a stroke, a grip lift or a house footprint is still moving: the stones are laid on a worker
## thread, since a long wall takes several frames' worth of main-thread time, and appear when ready.
func rebuild(settle := true) -> void:
	_settled = finished and settle
	_settle_when_laid = false
	if not settle:
		_build_live()
		return
	_build_gen += 1
	_build_stale = false
	if _build_task >= 0 and _build_out.ground == Terrain.revision and _build_job.same_inputs(layout):
		WorkerThreadPool.wait_for_task_completion(_build_task)
		_build_task = -1
		_take(_build_out)
		_shown = _build_job
		_shown_ground = Terrain.revision
	if _shown != null and _shown_ground == Terrain.revision and _shown.same_inputs(layout):
		layout.adopt(_shown)
	else:
		layout.build(Terrain.height_at)
		_take(pack(layout, kinds()))
	_shown = null
	_lay_dressing()
	if _settled and not layout.fence:
		_layout_ivy()
	_sync()


## Lays the stones again on a worker thread and settles when they are laid, for ground that moved under a wall
## nobody holds: every rebuild(false) until then is ground still moving under it, so the last preview stands on
## the ground as it settled.
func settle_when_laid() -> void:
	rebuild(false)
	_settle_when_laid = true


func _sweep() -> Array[Array]:
	var litter := _litter
	_litter = []
	return litter


static func _drop(litter: Array[Array]) -> void:
	for stones in litter:
		stones.clear()


## Whether a preview is still being laid on a worker thread.
func laying() -> bool:
	return _build_task >= 0


func _build_live() -> void:
	set_process(true)
	if _build_task >= 0:
		_build_stale = true
		return
	_build_stale = false
	var job := layout.inputs()
	var out := _build_out
	out.clear()
	out.gen = _build_gen
	out.ground = Terrain.revision
	var ks := kinds()
	_build_job = job
	var litter := _sweep()
	_build_task = WorkerThreadPool.add_task(func():
		_drop(litter)
		job.build(Terrain.height_at)
		out.merge(Wall.pack(job, ks)))


## Lays the roof again; `live` while its pitch is being pulled, so it stays out of the Masonry until let go.
## Going flat or back up changes the top the walls lay, so their stones are laid again too.
func rebuild_roof(live := false) -> void:
	var cover := layout.cover
	_cover()
	if layout.cover != cover:
		rebuild(false)
	var was_live := _roof_live
	_roof_live = live
	_pack_roof()
	if live and was_live:
		_show(Part.TILE)
		_show(Part.TILE_SHADOW)
	else:
		_sync()


## The roof, or else the lanterns and flags, laid again over the stones.
func _lay_dressing() -> void:
	if roof != null:
		_pack_roof()
	else:
		_fittings.lay(layout.flames, layout.cloths)


func _pack_roof() -> void:
	roof.base = layout.samples[0].y + layout.height + WallLayout.CAP
	if roof.kind == RoofLayout.Kind.GABLE:
		roof.corners = layout.laid_points
	roof.build()
	var tile := kinds()[Part.TILE]
	var shadow := kinds()[Part.TILE_SHADOW]
	var tiles := PackedFloat32Array()
	tiles.resize(roof.tiles.size() * tile.stride())
	var shadows := PackedFloat32Array()
	shadows.resize(roof.tiles.size() * shadow.stride())
	for i in roof.tiles.size():
		var t: Dictionary = roof.tiles[i]
		tile.write(tiles, i, t.xform, t.color, t.ao, Palette.code(t.kind))
		shadow.write(shadows, i, t.xform)
	_parts[Part.TILE] = tiles
	_parts[Part.TILE_SHADOW] = shadows
	_fittings.lay(layout.flames, layout.cloths + roof.cloths)
	var tris := roof.gable_faces
	if tris.is_empty():
		_gables.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in tris:
		st.add_vertex(p)
	st.generate_normals()
	_gables.mesh = st.commit()


## A built layout's stones as instance buffers by Part, and the box enclosing them. Reads nothing but its
## arguments, so it runs on a worker thread.
static func pack(built: WallLayout, ks: Array[Masonry.Kind]) -> Dictionary:
	var stone := ks[Part.STONE]
	var mortar := ks[Part.MORTAR]
	var shadow := ks[Part.STONE_SHADOW]
	var mortars := 0
	var plaster := 0
	for s in built.stones:
		if s.kind in ["mortar", "plaster"]:
			mortars += 1
		if s.kind == "plaster":
			plaster += 1
	var stones := built.stones.size() - mortars
	var bufs: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	bufs[0].resize(stones * stone.stride())
	bufs[1].resize(mortars * mortar.stride())
	bufs[2].resize((stones + plaster) * shadow.stride())
	var n := [0, 0, 0]
	var box := AABB(built.samples[0] if built.samples.size() > 0 else Vector3.ZERO, Vector3.ZERO)
	for s in built.stones:
		var x: Transform3D = s.xform
		if s.kind in ["mortar", "plaster"]:
			mortar.write(bufs[1], n[1], x, s.color, s.ao, Palette.code(s.kind))
			n[1] += 1
		else:
			x.basis = x.basis * Stones.FLIPS[s.variant]
			stone.write(bufs[0], n[0], x, s.color, s.ao, Palette.code(s.kind))
			n[0] += 1
		if s.kind != "mortar":
			shadow.write(bufs[2], n[2], x)
			n[2] += 1
		box = box.expand(x.origin)
	return {"stone": bufs[0], "mortar": bufs[1], "shadow": bufs[2], "bounds": box.grow(0.6)}


func _take(packed: Dictionary) -> void:
	_parts[Part.STONE] = packed.stone
	_parts[Part.MORTAR] = packed.mortar
	_parts[Part.STONE_SHADOW] = packed.shadow
	pick_bounds = packed.bounds


## Puts each part where it belongs: with the Masonry once settled (ivy once grown, a roof once let go), else
## drawn here.
func _sync() -> void:
	var placed: Array[PackedFloat32Array] = []
	for p in Part.size():
		var settle := _settled
		if p == Part.IVY:
			settle = settle and not _ivy_growing()
		elif p == Part.TILE or p == Part.TILE_SHADOW:
			settle = settle and not _roof_live
		placed.append(_parts[p] if settle else PackedFloat32Array())
		_show(p, not settle)
	masonry.place(get_instance_id(), pick_bounds.get_center(), placed)


func _show(p: int, live := true) -> void:
	var buf := _parts[p] if live and (p != Part.IVY or _settled) else PackedFloat32Array()
	if _live[p] == null:
		if buf.is_empty():
			return
		_live[p] = kinds()[p].instance()
		add_child(_live[p])
	var mm := _live[p].multimesh
	mm.instance_count = buf.size() / kinds()[p].stride()
	if mm.instance_count > 0:
		mm.buffer = buf


func footprint() -> Rect2:
	return layout.bounds.grow(WallLayout.THICKNESS)


## Distance from a ray to this wall's body, with the arc length it is nearest.
func ray_distance(origin: Vector3, dir: Vector3) -> Dictionary:
	var best_d := INF
	var best_i := 0
	var best_t := 0.0
	var best_p := Vector3.ZERO
	var up := Vector3.UP * (layout.height + WallLayout.CAP)
	var ud := up.dot(dir)
	var denom := up.dot(up) - ud * ud
	for i in layout.samples.size():
		var a := layout.samples[i]
		var w := origin - a
		var sc := 0.0 if absf(denom) < 1e-6 else clampf((up.dot(w) - ud * dir.dot(w)) / denom, 0.0, 1.0)
		var t := maxf(0.0, ud * sc - dir.dot(w))
		var p := a + up * sc
		var d := p.distance_to(origin + dir * t)
		if d < best_d:
			best_d = d
			best_i = i
			best_t = t
			best_p = p
	return {"distance": best_d, "s": layout.lengths[best_i] if best_d < INF else 0.0, "point": best_p, "along": best_t if best_d < INF else INF}

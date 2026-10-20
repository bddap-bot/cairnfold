class_name Wall
extends Node3D

## A drawn wall. Its stones and ivy are packed into instance buffers by part and drawn per ground chunk: while the
## wall changes by its own Masonry, so far chunks draw coarse stones as settled ones do, and once it settles by the
## glade's.

enum Part { STONE, MORTAR, STONE_SHADOW, TILE, TILE_SHADOW, COAT, IVY, TIMBER, FLOOR }
## The parts a build's paint colours.
const PAINTED: Array[Part] = [Part.STONE, Part.MORTAR, Part.TILE, Part.COAT, Part.TIMBER, Part.FLOOR]

static var _kinds: Array[Masonry.Kind] = []
## A roof's materials are made as the game loads: a shader made on first use stalled the Quest 2's frame 0.25 to 1.5 s
## as the session's first house went up.
static var _plaster := _material("res://src/plaster.gdshader", WallLayout.PLASTER)
static var _thatch := _material("res://src/thatch.gdshader")
static var _lime := _material("res://src/torching.gdshader", WallLayout.PLASTER)
static var _roof_wood := _wood()

var layout := WallLayout.new()
var masonry: Masonry
## The ground it is laid on, as this player sees it: it follows a live hump while one is pulled.
var terrain: Terrain
## Lantern flames and flags: few, alive, and drawn by the wall itself.
var _fittings := Fittings.new()
var _smoke := Smoke.new()
var finished := false
## The reshape data it is laid with in place of the garden's own, empty when laid as the garden has it.
var reshaped := {}
## The id of the build command that put it up; -1 while it is still being drawn.
var id := -1
## The roof on a house or tower, laid again with the walls under it.
var roof: RoofLayout
## Its swatch of each material (Palette.plain), for its stones, roof, woodwork and plaster alike.
var paint := Palette.plain()
## The paint the packed parts are coloured in, which a lay or a recolour under way may not have caught up with.
var _painted := Palette.plain()
var _recolour_task := -1
## A recolour's inputs (`laid`, the lay it scales, and the paint it scales `to`) and the parts it scaled.
var _recoloured := {}
## Counts the lays taken, so a recolour of parts a newer lay replaced is dropped.
var _laid := 0
## The walls' own mortar, which a deck's bed joins in Part.MORTAR.
var _wall_mortar := PackedFloat32Array()
## The ids of the builds it stands on; empty on the ground.
var on := PackedInt32Array()
## The room it takes up as last laid, for the builds it meets (WallTool).
var massing: Massing
## Seconds since the wall was finished: how far its ivy has grown.
var ivy_age := 0.0
## Encloses every stone, for pointing.
var pick_bounds := AABB()
## The sample `ray_distance` found nearest last, where it looks first.
var _nearest := 0
var _ruin_pick: Array[TriangleMesh] = []
var _parts: Array[PackedFloat32Array] = []
## Each part's buffer split by ground chunk (`Masonry.split`), as the Masonry takes it.
var _chunked: Array[Dictionary] = []
## Draws the parts while the wall is not settled, made when first needed.
var _drawn: Masonry
## Which parts the last `_sync` placed with the Masonry. While the same ones stay there and nothing else draws them,
## new stones replace the old chunk by chunk over the next frames, so a long wall laid again (an arch opening) spends no
## frame drawing all its chunks at once. Ivy passing between the wall's own and the Masonry shows twice for those frames:
## the wall keeps drawing its grown ivy until the Masonry has drawn it (`_ivy_handoff`).
var _in_masonry := []
var _ivy_handoff := false
## Ivy's own MultiMesh while it grows, made when first needed: it shows as much of it as has grown.
var _ivy: MultiMeshInstance3D
var _gables: MeshInstance3D
var _coat: MeshInstance3D
var _coat_far: MeshInstance3D
var _torching: MeshInstance3D
var _ceiling: MeshInstance3D
## The wall's mortar and plaster slabs, which hide what stands behind them from the renderer.
var _occluder: OccluderInstance3D
## The roof faces its meshes were built from; a lay that leaves them alone keeps the meshes.
var _faced := []
var _settled := false
var _ivy_times := PackedFloat32Array()
var _ivy_task := -1
var _ivy_baked := {}
var _ivy_stale := false
var _build_task := -1
var _build_stale := false
## A lay: its inputs (`job`, `roof`, the ground's `revision`) and what the worker laid from them (`out`).
var _build := {}
## The lay now shown; a settling rebuild from the same inputs takes it rather than laying the stones again.
var _shown := {}
## Whether the wall settles once the lay under way lands; `rebuild(false)` clears it.
var _settle_on_land := false
## The wall in hand this one is the garden's copy of, shown until this one's stones are laid.
var _stand_in: Wall
## Stones a newer layout replaced. Freeing a long wall's thousands of them takes milliseconds, so the wall's
## next worker task does it.
var _litter: Array[Array] = []
## Where a bird can stand on the top (`WallLayout.perches`), and the `layout.laid` they were worked out from.
var _perches := PackedVector3Array()
var _perches_laid := -1
var _perch_task := -1
var _perch_out := {}


## How each Part is drawn. Stones, roof tiles and the mortar between stones cast no shadow; a plain box per
## stone or tile does, at a ninth of the triangles. Far off, a tile is a plain box too: from the air a roof's rounded
## tiles cost the Quest 2 ten times what plain ones do. Mortar only shows in the gaps, so it is a plain box too. A
## thatched roof's coat is a mesh of its own, from rows RoofLayout.FAR_STEP apart past the near distance; its slabs cast
## its shadow and stand in it for the bounce light. A timber, and a sawn plank of a boarded wall, gable or fence, is a
## plain box near, where a stone's lumps would cost it nine times the triangles and read no different on planed wood;
## far it is the coarse stone in a shader that reads nothing per pixel, since a few pixels wide its shading is what it
## costs. A floor's
## flags and planks are drawn as timbers are, but lie in the walls' own shade and the light around them: they cast
## no shadow and shade no bounce light, which reads a room's builds from its roof down.
static func kinds() -> Array[Masonry.Kind]:
	if _kinds.is_empty():
		var box := BoxMesh.new()
		var leaf := ShaderMaterial.new()
		leaf.shader = load("res://src/ivy.gdshader")
		Quality.full_detail(leaf)
		var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shadow := Masonry.Kind.new(Meshes.plain_box(), null, false, false, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
		_kinds.resize(Part.size())
		_kinds[Part.STONE] = Masonry.Kind.new(Stones.mesh(), Stones.small_material(), true, true, off, true)
		_kinds[Part.STONE].far = Stones.far_mesh()
		_kinds[Part.STONE].size = WallLayout.LONGEST
		_kinds[Part.MORTAR] = Masonry.Kind.new(box, Stones.shared_material(), true, true, off)
		_kinds[Part.STONE_SHADOW] = shadow
		_kinds[Part.TILE] = Masonry.Kind.new(Meshes.rounded_box(0.22, 2, 41), Stones.small_material(), true, true, off, true)
		_kinds[Part.TILE].far = Stones.far_mesh()
		_kinds[Part.TILE_SHADOW] = shadow
		_kinds[Part.COAT] = Masonry.Kind.new(Meshes.plain_box(), null, true, true, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, true)
		_kinds[Part.IVY] = Masonry.Kind.new(Meshes.sprig(), leaf, true, false, off)
		_kinds[Part.TIMBER] = Masonry.Kind.new(box, Stones.shared_material(), true, true, off, true)
		_kinds[Part.TIMBER].far = Stones.far_mesh()
		_kinds[Part.TIMBER].far_material = ShaderMaterial.new()
		_kinds[Part.TIMBER].far_material.shader = load("res://src/timber_far.gdshader")
		_kinds[Part.FLOOR] = Masonry.Kind.new(box, Stones.shared_material(), true, true, off)
		_kinds[Part.FLOOR].far = _kinds[Part.TIMBER].far
		_kinds[Part.FLOOR].far_material = _kinds[Part.TIMBER].far_material
		_reach(Quality.ladder[0].stone_near_m, Quality.ladder[0].ivy_m)
	return _kinds


## Moves ivy's reach toward `step`'s as grass reach moves (Quality.reach), and how far stones are drawn whole
## to it at once, since a chunk's stones change mesh in one frame wherever the line falls; true once there.
static func approach(step: Quality.Step, delta: float, glade: Masonry) -> bool:
	var ks := kinds()
	var ivy := Quality.reach(ks[Part.IVY].reach, step.ivy_m, delta)
	if step.stone_near_m != ks[Part.STONE].near or ivy != ks[Part.IVY].reach:
		_reach(step.stone_near_m, ivy)
		glade.set_ranges()
		if glade.is_inside_tree():
			for ceiling in glade.get_tree().get_nodes_in_group(&"roof_ceilings"):
				ceiling.visibility_range_end = step.stone_near_m + (ceiling.mesh.get_aabb().size.length() * 0.5 if ceiling.mesh != null else 0.0)
	return ivy == step.ivy_m


static func _reach(stone_near: float, ivy: float) -> void:
	_kinds[Part.STONE].near = stone_near
	_kinds[Part.TIMBER].near = stone_near
	_kinds[Part.FLOOR].near = stone_near
	_kinds[Part.TILE].near = stone_near
	_kinds[Part.IVY].reach = ivy
	_kinds[Part.IVY].material.set_shader_parameter("reach", ivy)


func _init(seed: int, glade: Masonry, ground: Terrain) -> void:
	layout.seed = seed
	masonry = glade
	terrain = ground
	add_child(_fittings)
	add_child(_smoke)
	_parts.resize(Part.size())
	_chunked.resize(Part.size())


## A material of `shader`, its albedo `albedo` if given. Color uniforms convert to linear; the wall instance buffer
## carries raw RGB, so the albedo goes as a Vector3.
static func _material(shader: String, albedo: Variant = null) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader)
	if albedo != null:
		var c: Color = albedo
		m.set_shader_parameter("albedo", Vector3(c.r, c.g, c.b))
	return m


static func _wood() -> ShaderMaterial:
	var m := _material("res://src/roof_timber.gdshader")
	m.set_shader_parameter("window_glow", Lamps.WINDOW_GLOW)
	m.set_shader_parameter("glass_colour", Vector3(WallLayout.GLASS.r, WallLayout.GLASS.g, WallLayout.GLASS.b))
	StoneStyles.apply(m)
	return m


## Puts a roof on this closed wall; its stones then stop flush under the eaves.
func add_roof(r: RoofLayout) -> void:
	roof = r
	_cover()
	_gables = MeshInstance3D.new()
	_gables.material_override = _plaster
	add_child(_gables)
	_coat = MeshInstance3D.new()
	_coat_far = MeshInstance3D.new()
	for coat in [_coat, _coat_far]:
		coat.material_override = _thatch
		coat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(coat)
	_faced = []
	_torching = MeshInstance3D.new()
	_torching.material_override = _lime
	# One face thick and facing down: cast from its front only, it would let the sun through the tiles' gaps.
	_torching.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(_torching)
	_ceiling = MeshInstance3D.new()
	_ceiling.material_override = _roof_wood
	_ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ceiling.visibility_range_end = kinds()[Part.TIMBER].near
	_ceiling.add_to_group(&"roof_ceilings")
	add_child(_ceiling)
	_tint_roof()


## The wall as a build command carries it.
func data() -> Dictionary:
	var d := {
		"points": PackedVector3Array(layout.points), "height": layout.height, "rise": layout.rise,
		"seed": layout.seed, "closed": layout.closed, "top": int(layout.top), "fence": layout.fence,
		"openings": PackedVector4Array(layout.openings), "lanterns": PackedVector3Array(layout.lanterns), "flags": PackedFloat32Array(layout.flags), "clutter": PackedVector4Array(layout.clutter),
		"ruins": PackedVector2Array(layout.ruins), "finish": int(layout.finish), "wear": layout.wear, "foundation": int(layout.foundation), "planks": layout.planks, "gable_end": int(layout.gable_end), "on": PackedInt32Array(on), "paint": PackedInt32Array(paint),
	}
	if roof != null:
		d.roof = {"kind": int(roof.kind), "center": roof.center, "radius": roof.radius, "pitch": roof.pitch, "curve": roof.curve, "seed": roof.seed, "chimneys": PackedVector2Array(roof.chimneys), "dormers": PackedVector2Array(roof.dormers), "hatches": PackedVector2Array(roof.hatches), "overhang": roof.overhang, "deck": int(roof.deck), "flag": roof.flag, "thatch": roof.thatch}
	return d


func set_data(d: Dictionary) -> void:
	reshaped = {}
	layout.set_data(d)
	on = d.on
	repaint(d.paint)
	if d.has("roof"):
		if roof == null:
			add_roof(RoofLayout.new())
		roof.set_data(d.roof)
		_cover()


func _cover() -> void:
	layout.cover = WallLayout.Cover.OPEN if roof == null else WallLayout.Cover.DECK if roof.flat() else WallLayout.Cover.ROOF


func _ready() -> void:
	set_process(finished or _build_task >= 0 or _recolour_task >= 0)


func _process(delta: float) -> void:
	if _build_task >= 0 and WorkerThreadPool.is_task_completed(_build_task):
		_land()
	if _recolour_task >= 0 and WorkerThreadPool.is_task_completed(_recolour_task):
		_land_recolour()
	if finished:
		ivy_age += delta
	if _ivy_task >= 0 and WorkerThreadPool.is_task_completed(_ivy_task):
		WorkerThreadPool.wait_for_task_completion(_ivy_task)
		_ivy_task = -1
		_parts[Part.IVY] = _ivy_baked.buffer
		_chunked[Part.IVY] = _ivy_baked.chunks
		_ivy_times = _ivy_baked.times
		_sync()
		if _ivy_stale:
			_layout_ivy()
	if _ivy_handoff and masonry.drawn(get_instance_id()):
		_ivy_handoff = false
		_show_ivy(false)
	if _ivy != null:
		var mm := _ivy.multimesh
		mm.visible_instance_count = mini(_ivy_times.bsearch(ivy_age), mm.instance_count)
	if _build_task < 0 and _recolour_task < 0 and not _ivy_growing() and not _ivy_handoff:
		set_process(false)
		if _settled:
			_sync()


## Waits for the stones being laid and coloured and takes them, for a caller that reads them at once.
func lay_now() -> void:
	while _build_task >= 0 or _recolour_task >= 0:
		if _build_task >= 0:
			_land()
		else:
			_land_recolour()


func _land() -> void:
	WorkerThreadPool.wait_for_task_completion(_build_task)
	_build_task = -1
	_litter.append(layout.stones)
	_shown = _build
	if _build_stale:
		_build_live()
	if _settle_on_land and _build_task < 0:
		_settle()
	else:
		_put_shown()
		_sync()


func _ivy_growing() -> bool:
	return _ivy_task >= 0 or (not _ivy_times.is_empty() and ivy_age <= _ivy_times[-1])


func _exit_tree() -> void:
	masonry.remove(get_instance_id())
	if _stand_in != null:
		_stand_in.queue_free()


## A worker task outliving its wall crashes the engine at exit, so its tasks are waited for at quit. A wall freed in play
## leaves them running to `reap`, which takes them as they finish: waiting here held a deleting frame for a whole
## wall's ivy, 25 ms on a Quest 2. A wall freed outside the tree never exits it, so this is where its tasks are left.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for t in [_ivy_task, _build_task, _perch_task, _recolour_task]:
			if t >= 0:
				_orphans.append(t)
		if quitting:
			reap(true)


## Tasks left running by walls since freed.
static var _orphans := PackedInt32Array()
## Set as the game quits, after which a freed wall waits for its tasks.
static var quitting := false


## Takes the finished tasks walls left behind, or with `all` waits for every one.
static func reap(all := false) -> void:
	var left := PackedInt32Array()
	for t in _orphans:
		if all or WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			left.append(t)
	_orphans = left


## Where a bird can stand on the wall's top, as last worked out. Working them out reads every stone, several
## milliseconds for a long wall, so once the stones are laid again it is done on a worker thread, and not while a
## newer preview is being laid; until it is done, the old ones stand. With `now` the stones are laid and their
## perches worked out before it returns, for a caller stepping time without frames.
func perches(now := false) -> PackedVector3Array:
	if now:
		lay_now()
	_take_perches(false)
	if _perch_task < 0 and _perches_laid != layout.laid and not laying():
		var job := WallLayout.new()
		job.stones = layout.stones.duplicate()
		job.cover = layout.cover
		var out := {"laid": layout.laid}
		_perch_out = out
		_perch_task = WorkerThreadPool.add_task(func(): out.points = job.perches())
	_take_perches(now)
	return _perches


func _take_perches(wait: bool) -> void:
	if _perch_task >= 0 and (wait or WorkerThreadPool.is_task_completed(_perch_task)):
		WorkerThreadPool.wait_for_task_completion(_perch_task)
		_perch_task = -1
		_perches = _perch_out.points
		_perches_laid = _perch_out.laid


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
	var ivy := kinds()[Part.IVY]
	_ivy_task = WorkerThreadPool.add_task(func():
		_drop(litter)
		out.merge(IvyLayout.bake(shape))
		out.chunks = Masonry.split(out.buffer, ivy))


## Lays the stones again on a worker thread, since a long wall takes several frames' worth of main-thread time;
## the stones standing show until the new ones are laid. Without `settle` while a stroke, a grip lift, a roof pull
## or a house footprint is still moving; with it the wall then settles into the Masonry with its ivy.
func rebuild(settle := true) -> void:
	_settle_on_land = settle
	if not settle:
		_settled = false
	if settle and _build_task < 0 and _laid_from(_shown):
		_settle()
	else:
		_build_live()


## Takes the place of `preview`, the wall in hand that this one is the garden's copy of: it shows until this
## one's stones are laid, which are its own if it laid them from the same inputs on the same ground.
func stand_in(preview: Wall) -> void:
	preview.set_process(false)
	_stand_in = preview
	if preview._build_task < 0:
		_shown = preview._shown


## Whether lay `b` was laid from this wall's inputs as they stand, on the ground as it stands.
func _laid_from(b: Dictionary) -> bool:
	if b.is_empty() or b.revision != terrain.shown_revision or not b.job.same_inputs(layout) or (b.roof == null) != (roof == null):
		return false
	return roof == null or b.roof.same_inputs(roof)


func _put_shown() -> void:
	layout.adopt(_shown.job)
	_take(_shown.out)
	_lay_dressing(_shown.out.get("roofed", {}))
	_recolour()


func _settle() -> void:
	_settled = finished
	_settle_on_land = false
	_put_shown()
	if _settled and not layout.fence:
		_layout_ivy()
	_sync()


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
	if roof != null:
		_cover()
	if _build_task >= 0:
		_build_stale = not _laid_from(_build)
		return
	_build_stale = false
	var job := layout.inputs()
	var roof_job := roof.inputs() if roof != null else null
	job.gable = roof_job
	var out := {}
	_build = {"job": job, "roof": roof_job, "revision": terrain.shown_revision, "out": out}
	var ks := kinds()
	var litter := _sweep()
	var height := terrain.held_height(true)
	var water := terrain.held_water(true)
	var revision := terrain.shown_revision
	var colours := paint.duplicate()
	_build_task = WorkerThreadPool.add_task(func():
		_drop(litter)
		job.build(height, water, revision)
		if roof_job != null:
			out.roofed = Wall.pack_roof(job, roof_job, ks, colours)
		out.merge(Wall.pack(job, ks, colours)), true)


## The roof, or else the lanterns and flags, laid again over the stones; `roofed` is a roof already laid on
## these stones on a worker thread (`pack_roof`).
func _lay_dressing(roofed := {}) -> void:
	if roof != null:
		_pack_roof(roofed)
	else:
		_fittings.lay(layout.flames, layout.cloths, paint[Palette.Element.LANTERN])
		_smoke.lay(PackedVector3Array())


## Lays `r` on a built layout's walls and packs its tiles as instance buffers by Part. Touches nothing but its
## arguments, so it runs on a worker thread.
static func pack_roof(built: WallLayout, r: RoofLayout, ks: Array[Masonry.Kind], colours: PackedInt32Array) -> Dictionary:
	r.base = built.samples[0].y + built.height + WallLayout.CAP
	r.foot = built.stands_at()
	r.stepped = built.gable_kind() == WallLayout.GableEnd.STEPS
	if r.kind == RoofLayout.Kind.GABLE:
		r.corners = built.laid_points
	r.build(WallLayout.PLASTER_INSET if built.plaster and built.gable_end == WallLayout.GableEnd.WALL else WallLayout.THICKNESS * 0.5)
	built.hide_roof(r)
	built.fit_under(r)
	var mortar: PackedFloat32Array = _pack_parts(r.mortar, func(_m: Dictionary) -> Array: return [Part.MORTAR], ks, colours)[Part.MORTAR]
	var slabs: PackedFloat32Array = _pack_parts(r.slabs, func(_m: Dictionary) -> Array: return [Part.COAT], ks, colours)[Part.COAT]
	var tiled := _pack_parts(r.tiles, func(_t: Dictionary) -> Array: return [Part.TILE, Part.TILE_SHADOW], ks, colours)
	var tiles := tiled[Part.TILE]
	var shadows := tiled[Part.TILE_SHADOW]
	var chunks := {Part.TILE: Masonry.split(tiles, ks[Part.TILE]), Part.TILE_SHADOW: Masonry.split(shadows, ks[Part.TILE_SHADOW]), Part.COAT: Masonry.split(slabs, ks[Part.COAT])}
	return {"roof": r, "tiles": tiles, "shadows": shadows, "slabs": slabs, "chunks": chunks, "mortar": mortar}


func _pack_roof(roofed := {}) -> void:
	if roofed.is_empty():
		roofed = pack_roof(layout, roof, kinds(), _painted)
	else:
		roof.adopt(roofed.roof)
	_parts[Part.TILE] = roofed.tiles
	_parts[Part.TILE_SHADOW] = roofed.shadows
	_parts[Part.COAT] = roofed.slabs
	for part in roofed.chunks:
		_chunked[part] = roofed.chunks[part]
	if not roofed.mortar.is_empty():
		_parts[Part.MORTAR] = _wall_mortar + roofed.mortar
		_chunked[Part.MORTAR] = Masonry.split(_parts[Part.MORTAR], kinds()[Part.MORTAR])
	_fittings.lay(layout.flames, layout.cloths + roof.cloths, paint[Palette.Element.LANTERN])
	_smoke.lay(roof.vents)
	var faces := [roof.coat, roof.gable_faces, roof.torching_faces, roof.timber_faces]
	if faces == _faced:
		return
	_faced = faces.duplicate(true)
	_coat.mesh = _coat_mesh(roof.coat)
	_coat_far.mesh = _coat_mesh(roof.coat_far)
	_coat.visibility_range_end = kinds()[Part.STONE].near + (_coat.mesh.get_aabb().size.length() * 0.5 if _coat.mesh != null else 0.0)
	_coat_far.visibility_range_begin = _coat.visibility_range_end
	_gables.mesh = _faces_mesh(faces[1])
	_torching.mesh = _faces_mesh(faces[2])
	_ceiling.mesh = _faces_mesh(faces[3], true)
	_ceiling.visibility_range_end = kinds()[Part.TIMBER].near + (_ceiling.mesh.get_aabb().size.length() * 0.5 if _ceiling.mesh != null else 0.0)


static func _coat_mesh(arrays: Array) -> ArrayMesh:
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX].is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _faces_mesh(tris: PackedVector3Array, flat_normals := false) -> ArrayMesh:
	if tris.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if flat_normals:
		st.set_smooth_group(-1)
	for p in tris:
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()


## A built layout's stones as instance buffers by Part, and the box enclosing them. Reads nothing but its
## arguments, so it runs on a worker thread.
static func pack(built: WallLayout, ks: Array[Masonry.Kind], colours: PackedInt32Array) -> Dictionary:
	var route := func(s: Dictionary) -> Array:
		var own := Part.MORTAR if s.kind in ["mortar", "plaster", "bed"] else Part.TIMBER if s.kind in ["timber", "board"] else Part.FLOOR if s.kind in ["flagstone", "plank"] else Part.STONE
		return [own] if s.kind in ["mortar", "crop"] or s.kind in WallLayout.FLOOR_KINDS else [own, Part.STONE_SHADOW]
	var bufs := _pack_parts(built.stones, route, ks, colours)
	var box := AABB(built.samples[0] if built.samples.size() > 0 else Vector3.ZERO, Vector3.ZERO)
	for s in built.stones:
		box = box.expand(s.xform.origin)
	var chunks := {}
	for part in [Part.STONE, Part.MORTAR, Part.STONE_SHADOW, Part.TIMBER, Part.FLOOR]:
		chunks[part] = Masonry.split(bufs[part], ks[part])
	return {"stone": bufs[Part.STONE], "mortar": bufs[Part.MORTAR], "shadow": bufs[Part.STONE_SHADOW], "timber": bufs[Part.TIMBER], "floor": bufs[Part.FLOOR], "chunks": chunks, "bounds": box.grow(0.6), "paint": colours, "ruin_pick": _pack_ruin(built), "occluder": _pack_occluder(built)}


## The boxes of a layout's mortar and plaster as occluder triangles: they stand behind the stones' faces, so whatever
## they hide is hidden.
static func _pack_occluder(built: WallLayout) -> Array:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for s: Dictionary in built.stones:
		if s.kind != "mortar" and s.kind != "plaster":
			continue
		var x: Transform3D = s.xform
		var base := verts.size()
		for c in 8:
			verts.append(x * Vector3(0.5 if c & 1 else -0.5, 0.5 if c & 2 else -0.5, 0.5 if c & 4 else -0.5))
		for f: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			idx.append_array(PackedInt32Array([base + f[0], base + f[1], base + f[2], base + f[0], base + f[2], base + f[3]]))
	return [verts, idx]


## `parts` as instance buffers by Part, in their order: each in the Parts `into` names for it, its own first and then
## its shadow's if it casts one. A stone turns by its variant (FLIPS); stones and tiles are glazed.
static func _pack_parts(parts: Array, into: Callable, ks: Array[Masonry.Kind], colours: PackedInt32Array) -> Array[PackedFloat32Array]:
	var routes := parts.map(into)
	var n := PackedInt32Array()
	n.resize(Part.size())
	for route: Array in routes:
		for part: Part in route:
			n[part] += 1
	var bufs: Array[PackedFloat32Array] = []
	for part in Part.size():
		bufs.append(PackedFloat32Array())
		bufs[part].resize(n[part] * ks[part].stride())
	n.fill(0)
	for i in parts.size():
		var s: Dictionary = parts[i]
		var x: Transform3D = s.xform
		var ends: Vector2 = s.get("ends", Vector2.ZERO)
		var own: Part = routes[i][0]
		if own == Part.STONE:
			x.basis = x.basis * Stones.FLIPS[s.variant]
			ends = Stones.ends(s)
		var colour := Stones.glazed(s, _painted_as(s, colours)) if own == Part.STONE or own == Part.TILE else _painted_as(s, colours)
		for part: Part in routes[i]:
			ks[part].write(bufs[part], n[part], x, colour, s.ao, Palette.code(s.kind), ends)
			n[part] += 1
	return bufs


## A laid part's colour in `colours`.
static func _painted_as(part: Dictionary, colours: PackedInt32Array) -> Color:
	var e := int(Palette.code(part.kind))
	return part.color * Palette.tint(e, colours[e]) if e != 0 else part.color


## Paints the wall in `to`. Its packed parts are scaled from the swatches they carry onto the new ones in place, a pass
## over its pieces instead of a lay, and its lanterns burn in theirs.
func repaint(to: PackedInt32Array) -> void:
	if to == paint:
		return
	var lit := to[Palette.Element.LANTERN] != paint[Palette.Element.LANTERN]
	paint = to.duplicate()
	if lit:
		_fittings.lay(layout.flames, layout.cloths + roof.cloths if roof != null else layout.cloths, paint[Palette.Element.LANTERN])
	_tint_roof()
	_recolour()


func _tint_roof() -> void:
	if _gables != null:
		var t := Palette.tint(Palette.Element.PLASTER, paint[Palette.Element.PLASTER])
		# The shared lining material starts with plaster RGB; tint converts the backing as well as its swatch.
		var g := t
		if layout.gable_end == WallLayout.GableEnd.BOARDS:
			g = Palette.tint(Palette.Element.WOOD, paint[Palette.Element.WOOD]) * WallLayout.WOOD / WallLayout.PLASTER
		elif not layout.plaster:
			g = Palette.tint(Palette.Element.STONE, paint[Palette.Element.STONE]) * WallLayout.MORTAR * 0.8 / WallLayout.PLASTER
		_gables.set_instance_shader_parameter(&"tint", Vector3(g.r, g.g, g.b))
		var straw := Palette.tint(Palette.Element.THATCH, paint[Palette.Element.THATCH])
		for coat in [_coat, _coat_far]:
			coat.set_instance_shader_parameter(&"tint", Vector3(straw.r, straw.g, straw.b))
		_torching.set_instance_shader_parameter(&"tint", Vector3(t.r, t.g, t.b))
		var wood := WallLayout.WOOD * Palette.tint(Palette.Element.TIMBER, paint[Palette.Element.TIMBER])
		_ceiling.set_instance_shader_parameter(&"timber_color", Vector3(wood.r, wood.g, wood.b))


## Brings the packed parts from `_painted` to `paint` on a worker thread, a pass over every piece being too long for a
## frame on a big build; the parts as they stand show until it lands. The buffers are shared with the lay they came
## from, which may be taken again, so they are copied, not scaled in place.
func _recolour() -> void:
	if _painted == paint or _recolour_task >= 0:
		return
	if PAINTED.all(func(p: Part) -> bool: return _parts[p].is_empty()):
		_painted = paint.duplicate()
		return
	var scale := {}
	for e in Palette.SWATCHES:
		if _painted[e] != paint[e] and e != Palette.Element.LANTERN:
			var a := Palette.tint(e, _painted[e])
			var b := Palette.tint(e, paint[e])
			scale[float(e)] = Vector3(b.r / a.r, b.g / a.g, b.b / a.b)
	if scale.is_empty():
		_painted = paint.duplicate()
		return
	var ks := kinds()
	var parts := {}
	for p in PAINTED:
		parts[p] = [_parts[p], _chunked[p], ks[p].stride()]
	var out := {"laid": _laid, "to": paint.duplicate()}
	_recoloured = out
	set_process(true)
	_recolour_task = WorkerThreadPool.add_task(func():
		for p in parts:
			var stride: int = parts[p][2]
			var chunks := {}
			for key in parts[p][1]:
				chunks[key] = Wall._scaled(parts[p][1][key], stride, scale)
			out[p] = [Wall._scaled(parts[p][0], stride, scale), chunks])


func _land_recolour() -> void:
	WorkerThreadPool.wait_for_task_completion(_recolour_task)
	_recolour_task = -1
	var out := _recoloured
	if out.laid == _laid:
		for p in PAINTED:
			_parts[p] = out[p][0]
			_chunked[p] = out[p][1]
		_painted = out.to
		_sync()
	_recolour()


## `buf` (Masonry.Kind: colour at 12, material code at 17) with each piece's colour scaled by its material's `scale`.
static func _scaled(from: PackedFloat32Array, stride: int, scale: Dictionary) -> PackedFloat32Array:
	var buf := from.duplicate()
	for i in range(0, buf.size(), stride):
		var k: Variant = scale.get(buf[i + 17])
		if k != null:
			buf[i + 12] *= k.x
			buf[i + 13] *= k.y
			buf[i + 14] *= k.z
	return buf


func _take(packed: Dictionary) -> void:
	_laid += 1
	_painted = packed.paint
	_parts[Part.STONE] = packed.stone
	_wall_mortar = packed.mortar
	_parts[Part.MORTAR] = packed.mortar
	_parts[Part.STONE_SHADOW] = packed.shadow
	_parts[Part.TIMBER] = packed.timber
	_parts[Part.FLOOR] = packed.floor
	for part in packed.chunks:
		_chunked[part] = packed.chunks[part]
	pick_bounds = packed.bounds
	_ruin_pick = packed.ruin_pick
	if _occluder == null:
		_occluder = OccluderInstance3D.new()
		_occluder.occluder = ArrayOccluder3D.new()
		add_child(_occluder)
	(_occluder.occluder as ArrayOccluder3D).set_arrays(packed.occluder[0], packed.occluder[1])


## Draws the stones laid here rather than with the glade's, so moving this wall moves them, as a hold carries it.
func draw_live() -> void:
	if _settled:
		_settled = false
		_sync()


## Puts each part where it belongs: with the glade's Masonry once settled (ivy once grown), else drawn here, uploaded
## at once so the stones drawn here are always the ones laid, which a carry's transform is placed for; a part moving
## between the two is uploaded by both this frame, so none blinks out.
func _sync() -> void:
	var placed: Array[Dictionary] = []
	var drawn: Array[Dictionary] = []
	var live := false
	for p in Part.size():
		var settle := _settled and (p != Part.IVY or not _ivy_growing())
		placed.append(_chunked[p] if settle else {})
		drawn.append(_chunked[p] if not settle and p != Part.IVY else {})
		live = live or not drawn[p].is_empty()
	var parts := placed.map(func(d: Dictionary) -> bool: return not d.is_empty())
	var swapped := not live and _drawn == null and _stand_in == null and _in_masonry.size() == parts.size()
	_ivy_handoff = swapped and parts[Part.IVY] and (_ivy_handoff or not _in_masonry[Part.IVY])
	swapped = swapped and range(parts.size()).all(func(p: int) -> bool: return p == Part.IVY or parts[p] == _in_masonry[p])
	_in_masonry = parts
	masonry.place(get_instance_id(), placed)
	if live:
		if _drawn == null:
			_drawn = Masonry.new(kinds())
			add_child(_drawn)
		_drawn.place(get_instance_id(), drawn)
		_drawn.flush()
	elif _drawn != null:
		_drawn.queue_free()
		_drawn = null
	if not swapped:
		_ivy_handoff = false
		masonry.flush()
	if _ivy_handoff:
		set_process(true)
	_show_ivy(_ivy_handoff or (_settled and _ivy_growing()))
	if _stand_in != null:
		_stand_in.queue_free()
		_stand_in = null


func _show_ivy(growing: bool) -> void:
	var buf := _parts[Part.IVY] if growing else PackedFloat32Array()
	if _ivy == null:
		if buf.is_empty():
			return
		_ivy = kinds()[Part.IVY].instance()
		add_child(_ivy)
	var mm := _ivy.multimesh
	mm.instance_count = buf.size() / kinds()[Part.IVY].stride()
	if mm.instance_count > 0:
		mm.buffer = buf


func footprint() -> Rect2:
	return layout.bounds.grow(WallLayout.THICKNESS)


## Distance from a ray to this wall's body, with the arc length it is nearest: the first stretch the ray passes
## through, so a ray into a house finds the side facing it, or else the stretch it passes nearest.
func ray_distance(origin: Vector3, dir: Vector3) -> Dictionary:
	var reach := 0.1 if layout.fence else WallLayout.THICKNESS * 0.5
	var best_key := Vector2.INF
	var best_d := INF
	var best_i := 0
	var best_t := 0.0
	var best_p := Vector3.ZERO
	# The sample nearest last time, a hand's ray moving little between frames, bounds what any sample must come within.
	var bound := Vector2.INF
	if _nearest < layout.samples.size():
		var seen := _sample_near(_nearest, origin, dir, reach)
		if not seen.is_empty():
			bound = seen[0]
	# How far a sample stands from the ray seen from above bounds its distance below, so a sample that could neither
	# be in reach nor nearer than the best is passed over, with every sample after it too near along the wall to do better.
	var flat := Vector2(dir.x, dir.z)
	var across := flat.normalized() if flat.length_squared() > 1e-12 else Vector2.ZERO
	var from := Vector2(origin.x, origin.z)
	var lengths := layout.lengths
	var next := 0
	while next < layout.samples.size():
		var i := next
		next += 1
		var off := Vector2(layout.samples[i].x, layout.samples[i].z) - from
		# Less a margin over float error, so the bound never passes the distance it bounds.
		var least := (absf(across.cross(off)) if across != Vector2.ZERO else off.length()) - 1e-3
		var beat := reach if best_key.x == 0.0 or bound.x == 0.0 else maxf(reach, minf(best_d, bound.y + 1e-3))
		if least >= beat:
			# Samples within arc length `least - beat` of this one stand no nearer than `beat` either.
			next = maxi(next, lengths.bsearch(lengths[i] + least - beat, false))
			continue
		var near := _sample_near(i, origin, dir, reach)
		if not near.is_empty() and near[0] < best_key:
			best_key = near[0]
			best_d = near[1]
			best_i = i
			best_t = near[2]
			best_p = near[3]
	_nearest = best_i
	return {"distance": best_d, "s": layout.lengths[best_i] if best_d < INF else 0.0, "point": best_p, "along": best_t if best_d < INF else INF, "through": best_key.x == 0.0}


## Sample `i`'s upright and the ray's nearest approach to it, as [key, distance, along the ray, point on the upright]
## (`ray_distance` orders keys: within `reach` by how far along, else by how near), or empty where the wall hides it.
func _sample_near(i: int, origin: Vector3, dir: Vector3, reach: float) -> Array:
	var under := layout.depths[i] if i < layout.depths.size() else 0.0
	var a := layout.samples[i] + Vector3.DOWN * under
	var up := Vector3.UP * (layout.height + WallLayout.CAP + under)
	var ud := up.dot(dir)
	var denom := up.dot(up) - ud * ud
	var w := origin - a
	var sc := 0.0 if absf(denom) < 1e-6 else clampf((up.dot(w) - ud * dir.dot(w)) / denom, 0.0, 1.0)
	var t := maxf(0.0, ud * sc - dir.dot(w))
	var p := a + up * sc
	if layout.hides(p):
		return []
	var d := p.distance_to(origin + dir * t)
	return [Vector2(0.0, t) if d < reach else Vector2(1.0, d), d, t, p]


## Intersects the continuous wall body between samples, including its foundation and top; `through_arches` sees
## through each arch's opening to the stone round it.
func ray_hit(origin: Vector3, dir: Vector3, through_arches := false) -> Dictionary:
	if not _ruin_pick.is_empty():
		return _ruin_hit(origin, dir)
	var best := {}
	var n := layout.samples.size()
	var half := 0.1 if layout.fence else WallLayout.THICKNESS * 0.5
	# A stretch's box stands on the strip `half` either side of it, so a ray passing further from that strip, seen
	# from above, cannot meet it; arc length bounds how far apart two samples stand, so a sample far from the ray skips
	# every stretch after it that cannot come near: a long wall costs a ray a few steps away from it.
	var flat := Vector2(dir.x, dir.z)
	var across := flat.normalized() if flat.length_squared() > 1e-12 else Vector2.ZERO
	var from := Vector2(origin.x, origin.z)
	var lengths := layout.lengths
	var next := 0
	while next < (n if layout.closed else n - 1):
		var i := next
		next += 1
		var j := (i + 1) % n
		var a := layout.samples[i]
		var b := layout.samples[j]
		var off := Vector2(a.x, a.z) - from
		var gap := (absf(across.cross(off)) if across != Vector2.ZERO else off.length()) - half - 0.01
		if gap > 0.0 and i < n - 1:
			var past := lengths.bsearch(lengths[i] + gap) - 1
			if past > i:
				next = past
				continue
		var edge := b - a
		var length := Vector2(edge.x, edge.z).length()
		if length < 1e-6:
			continue
		if across.dot(Vector2(a.x + b.x, a.z + b.z) * 0.5 - from) < -(length * 0.5 + half + 0.01):
			continue
		var x := Vector3(edge.x, 0, edge.z) / length
		var z := x.cross(Vector3.UP)
		var slope := edge.y / length
		var offset := origin - a
		var ox := offset.dot(x)
		var dx := dir.dot(x)
		var local := Vector3(ox, offset.y - slope * ox, offset.dot(z))
		var direction := Vector3(dx, dir.y - slope * dx, dir.dot(z))
		var under := maxf(layout.depths[i], layout.depths[j]) if layout.depths.size() == n else 0.0
		var height := layout.height + layout.top_rise()
		var box := AABB(Vector3(0, -under, -half), Vector3(length, height + under, half * 2.0))
		var hit: Variant = local if box.has_point(local) else box.intersects_ray(local, direction)
		if hit == null:
			continue
		var t: float = (hit - local).dot(direction) / direction.length_squared()
		if layout.hides(origin + dir * t):
			continue
		if t >= best.get("along", INF):
			continue
		var end := layout.lengths[j] if j > 0 else layout.length()
		var arched := through_arches and _open(i, end, length, local + direction * t)
		if arched:
			var open := func(at: float) -> bool: return _open(i, end, length, local + direction * at)
			t = _first_solid(open, t, _exit(box, local, direction))
			if t == INF or layout.hides(origin + dir * t):
				continue
		if t < best.get("along", INF):
			var at: Vector3 = local + direction * t
			var face := Rig.box_normal(box, at)
			var side := arched or Rig.side(x * face.x + (Vector3.UP - x * slope) * face.y + z * face.z)
			best = {"along": t, "point": origin + dir * t, "s": lerpf(layout.lengths[i], end, clampf(at.x / length, 0.0, 1.0)), "distance": 0.0, "side": side}
	return best


## Whether point `p`, in the frame of the stretch from sample `i` to arc length `end`, `length` long, lies in an arch.
func _open(i: int, end: float, length: float, p: Vector3) -> bool:
	return layout.open_at(lerpf(layout.lengths[i], end, p.x / length), p.y)


## Where a ray inside `box` leaves it.
static func _exit(box: AABB, local: Vector3, direction: Vector3) -> float:
	var out := INF
	for k in 3:
		if absf(direction[k]) > 1e-9:
			out = minf(out, ((box.end[k] if direction[k] > 0.0 else box.position[k]) - local[k]) / direction[k])
	return out


## The first `along` from `from` to `to` that is not `open`, to a millimetre, or INF where the ray stays open, as it
## does through an arch. An arch's opening narrows only upward, so stepping finer than a jamb's thickness finds it.
static func _first_solid(open: Callable, from: float, to: float) -> float:
	var steps := clampi(ceili((to - from) / 0.05), 1, 400)
	var last := from
	for k in steps:
		var at := lerpf(from, to, float(k + 1) / steps)
		if not open.call(at):
			for n in 8:
				var mid := (last + at) * 0.5
				if open.call(mid):
					last = mid
				else:
					at = mid
			return at
		last = at
	return INF


## A ruined wall has no continuous body. Build its query trees with the masonry on the worker,
## so aiming through several gaps does not scan every remaining stone each frame.
static func _pack_ruin(built: WallLayout) -> Array[TriangleMesh]:
	var out: Array[TriangleMesh] = []
	if built.ruins.is_empty():
		return out
	var indices := [0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6, 0, 4, 2, 4, 6, 2, 1, 3, 5, 5, 3, 7, 0, 1, 4, 4, 1, 5, 2, 6, 3, 3, 6, 7]
	var faces: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	for stone in built.stones:
		var kind := 1 if stone.kind == "rubble" else 0
		var corners := WallLayout.drawn_corners(stone)
		for index in indices:
			faces[kind].append(corners[index])
	for vertices in faces:
		var mesh: TriangleMesh
		if not vertices.is_empty():
			mesh = TriangleMesh.new()
			mesh.create_from_faces(vertices)
		out.append(mesh)
	return out


## A stone's top below where the masonry round it stands, a proud stone's lip, is part of the face, not a ledge.
func _ruin_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	for i in _ruin_pick.size():
		var mesh := _ruin_pick[i]
		var hit := mesh.intersect_ray(origin, dir) if mesh != null else {}
		if hit.is_empty():
			continue
		var along: float = (hit.position - origin).dot(dir) / dir.length_squared()
		if along < best.get("along", INF):
			var normal: Vector3 = hit.normal if hit.normal.dot(dir) < 0.0 else -hit.normal
			var s := layout.closest_s(hit.position)
			var face: bool = i == 0 and hit.position.y < layout.frame_at(s).point.y + layout.standing(s) - layout.course_height() * 0.5
			best = {"along": along, "point": hit.position, "s": s, "distance": 0.0, "rubble": i == 1, "side": face or Rig.side(normal)}
	return best

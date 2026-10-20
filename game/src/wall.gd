class_name Wall
extends Node3D

## A drawn wall. Its stones and ivy are packed into instance buffers by part and drawn per ground chunk: while the
## wall changes by its own Masonry, so far chunks draw coarse stones as settled ones do, and once it settles by the
## glade's.

enum Part { STONE, MORTAR, STONE_SHADOW, TILE, TILE_SHADOW, COAT, IVY, TIMBER, FLOOR }
## The parts a build's paint colours.
const PAINTED: Array[Part] = [Part.STONE, Part.MORTAR, Part.TILE, Part.COAT, Part.TIMBER, Part.FLOOR]

static var _kinds: Array[Masonry.Kind] = []
static var _plaster: ShaderMaterial
static var _thatch: ShaderMaterial
static var _lime: ShaderMaterial

var layout := WallLayout.new()
var masonry: Masonry
## Lantern flames and flags: few, alive, and drawn by the wall itself.
var _fittings := Fittings.new()
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
var _parts: Array[PackedFloat32Array] = []
## Each part's buffer split by ground chunk (`Masonry.split`), as the Masonry takes it.
var _chunked: Array[Dictionary] = []
## Draws the parts while the wall is not settled, made when first needed.
var _drawn: Masonry
## Ivy's own MultiMesh while it grows, made when first needed: it shows as much of it as has grown.
var _ivy: MultiMeshInstance3D
var _gables: MeshInstance3D
var _coat: MeshInstance3D
var _torching: MeshInstance3D
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
## thatched roof's coat is a mesh of its own; its slabs cast its shadow and stand in it for the bounce light. A
## timber is a plain box near, where a stone's lumps would cost it nine times the triangles; far it is the coarse
## stone in a shader that reads nothing per pixel, since a few pixels wide its shading is what it costs. A floor's
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
		_kinds[Part.STONE] = Masonry.Kind.new(Stones.mesh(), Stones.shared_material(), true, true, off, true)
		_kinds[Part.STONE].far = Stones.far_mesh()
		_kinds[Part.MORTAR] = Masonry.Kind.new(box, Stones.shared_material(), true, true, off)
		_kinds[Part.STONE_SHADOW] = shadow
		_kinds[Part.TILE] = Masonry.Kind.new(Meshes.rounded_box(0.22, 2, 41), Stones.shared_material(), true, true, off, true)
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


## Moves ivy's reach toward `step`'s as grass reach moves (Quality.REACH_RATE), and how far stones are drawn whole
## to it at once, since a chunk's stones change mesh in one frame wherever the line falls; true once there.
static func approach(step: Quality.Step, delta: float, glade: Masonry) -> bool:
	var ks := kinds()
	var ivy := move_toward(ks[Part.IVY].reach, step.ivy_m, Quality.REACH_RATE * delta)
	if step.stone_near_m != ks[Part.STONE].near or ivy != ks[Part.IVY].reach:
		_reach(step.stone_near_m, ivy)
		glade.set_ranges()
	return ivy == step.ivy_m


static func _reach(stone_near: float, ivy: float) -> void:
	_kinds[Part.STONE].near = stone_near
	_kinds[Part.TIMBER].near = stone_near
	_kinds[Part.FLOOR].near = stone_near
	_kinds[Part.TILE].near = stone_near
	_kinds[Part.IVY].reach = ivy
	_kinds[Part.IVY].material.set_shader_parameter("reach", ivy)


func _init(seed: int, glade: Masonry) -> void:
	layout.seed = seed
	masonry = glade
	add_child(_fittings)
	_parts.resize(Part.size())
	_chunked.resize(Part.size())


## Puts a roof on this closed wall; its stones then stop flush under the eaves.
func add_roof(r: RoofLayout) -> void:
	roof = r
	_cover()
	if _plaster == null:
		_plaster = ShaderMaterial.new()
		_plaster.shader = load("res://src/plaster.gdshader")
		# Color uniforms convert to linear; the wall instance buffer carries raw RGB.
		var c := WallLayout.PLASTER
		_plaster.set_shader_parameter("albedo", Vector3(c.r, c.g, c.b))
		_plaster.set_shader_parameter("detail", Look.detail_noise())
	if _thatch == null:
		_thatch = ShaderMaterial.new()
		_thatch.shader = load("res://src/thatch.gdshader")
		_thatch.set_shader_parameter("detail", Look.detail_noise())
	_gables = MeshInstance3D.new()
	_gables.material_override = _plaster
	add_child(_gables)
	_coat = MeshInstance3D.new()
	_coat.material_override = _thatch
	_coat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_coat)
	if _lime == null:
		_lime = ShaderMaterial.new()
		_lime.shader = load("res://src/torching.gdshader")
		_lime.set_shader_parameter("albedo", WallLayout.PLASTER)
		_lime.set_shader_parameter("detail", Look.detail_noise())
	_torching = MeshInstance3D.new()
	_torching.material_override = _lime
	# One face thick and facing down: cast from its front only, it would let the sun through the tiles' gaps.
	_torching.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(_torching)
	_tint_roof()


## The wall as a build command carries it.
func data() -> Dictionary:
	var d := {
		"points": PackedVector3Array(layout.points), "height": layout.height, "rise": layout.rise, "arches": PackedFloat32Array(layout.arches),
		"seed": layout.seed, "closed": layout.closed, "top": int(layout.top), "fence": layout.fence,
		"windows": PackedVector2Array(layout.windows), "lanterns": PackedVector3Array(layout.lanterns), "flags": PackedFloat32Array(layout.flags),
		"ruins": PackedVector2Array(layout.ruins), "plaster": layout.plaster, "gable_end": int(layout.gable_end), "timber_style": layout.timber_style, "storey_floors": layout.storey_floors, "on": PackedInt32Array(on), "paint": PackedInt32Array(paint),
	}
	if roof != null:
		d.roof = {"kind": int(roof.kind), "center": roof.center, "radius": roof.radius, "pitch": roof.pitch, "curve": roof.curve, "seed": roof.seed, "chimneys": PackedVector2Array(roof.chimneys), "flag": roof.flag, "thatch": roof.thatch}
	return d


func set_data(d: Dictionary) -> void:
	reshaped = {}
	layout.points.assign(Array(d.points))
	layout.height = d.height
	layout.rise = d.rise
	layout.arches.assign(Array(d.arches))
	layout.seed = d.seed
	layout.closed = d.closed
	layout.top = d.top as WallLayout.Top
	layout.fence = d.fence
	layout.plaster = d.plaster
	layout.timber_style = d.timber_style
	layout.storey_floors = d.storey_floors
	layout.gable_end = d.gable_end as WallLayout.GableEnd
	layout.windows.assign(Array(d.windows))
	layout.lanterns.assign(Array(d.lanterns))
	layout.flags.assign(Array(d.flags))
	layout.ruins.assign(Array(d.ruins))
	on = d.on
	repaint(d.paint)
	if d.has("roof"):
		if roof == null:
			add_roof(RoofLayout.new())
		for k in ["center", "radius", "pitch", "curve", "seed", "flag", "thatch"]:
			roof.set(k, d.roof[k])
		roof.kind = d.roof.kind as RoofLayout.Kind
		roof.chimneys.assign(Array(d.roof.chimneys))
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
	if _ivy != null:
		var mm := _ivy.multimesh
		mm.visible_instance_count = mini(_ivy_times.bsearch(ivy_age), mm.instance_count)
	if _build_task < 0 and _recolour_task < 0 and not _ivy_growing():
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


## A wall freed outside the tree never exits it, and a worker task outliving its wall crashes the engine at exit.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for t in [_ivy_task, _build_task, _perch_task, _recolour_task]:
			if t >= 0:
				WorkerThreadPool.wait_for_task_completion(t)


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
	if b.is_empty() or b.revision != Terrain.revision or not b.job.same_inputs(layout) or (b.roof == null) != (roof == null):
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
	_build = {"job": job, "roof": roof_job, "revision": Terrain.revision, "out": out}
	var ks := kinds()
	var litter := _sweep()
	var height := Terrain.held_height()
	var water := Terrain.held_water()
	var colours := paint.duplicate()
	_build_task = WorkerThreadPool.add_task(func():
		_drop(litter)
		job.build(height, water)
		if roof_job != null:
			out.roofed = Wall.pack_roof(job, roof_job, ks, colours)
		out.merge(Wall.pack(job, ks, colours)))


## The roof, or else the lanterns and flags, laid again over the stones; `roofed` is a roof already laid on
## these stones on a worker thread (`pack_roof`).
func _lay_dressing(roofed := {}) -> void:
	if roof != null:
		_pack_roof(roofed)
	else:
		_fittings.lay(layout.flames, layout.cloths)


## Lays `r` on a built layout's walls and packs its tiles as instance buffers by Part. Touches nothing but its
## arguments, so it runs on a worker thread.
static func pack_roof(built: WallLayout, r: RoofLayout, ks: Array[Masonry.Kind], colours: PackedInt32Array) -> Dictionary:
	r.base = built.samples[0].y + built.height + WallLayout.CAP
	r.stepped = built.gable_end == WallLayout.GableEnd.STEPS
	if r.kind == RoofLayout.Kind.GABLE:
		r.corners = built.laid_points
	r.build()
	built.hide_roof(r)
	built.fit_under(r)
	var tile := ks[Part.TILE]
	var shadow := ks[Part.TILE_SHADOW]
	var bed := ks[Part.MORTAR]
	var mortar := PackedFloat32Array()
	mortar.resize(r.mortar.size() * bed.stride())
	for i in r.mortar.size():
		var m: Dictionary = r.mortar[i]
		bed.write(mortar, i, m.xform, _painted_as(m, colours), m.ao, Palette.code(m.kind))
	var slab := ks[Part.COAT]
	var slabs := PackedFloat32Array()
	slabs.resize(r.slabs.size() * slab.stride())
	for i in r.slabs.size():
		var m: Dictionary = r.slabs[i]
		slab.write(slabs, i, m.xform, _painted_as(m, colours), m.ao, Palette.code(m.kind))
	var tiles := PackedFloat32Array()
	tiles.resize(r.tiles.size() * tile.stride())
	var shadows := PackedFloat32Array()
	shadows.resize(r.tiles.size() * shadow.stride())
	for i in r.tiles.size():
		var t: Dictionary = r.tiles[i]
		tile.write(tiles, i, t.xform, _painted_as(t, colours), t.ao, Palette.code(t.kind))
		shadow.write(shadows, i, t.xform)
	var chunks := {Part.TILE: Masonry.split(tiles, tile), Part.TILE_SHADOW: Masonry.split(shadows, shadow), Part.COAT: Masonry.split(slabs, slab)}
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
	_fittings.lay(layout.flames, layout.cloths + roof.cloths)
	_coat.mesh = null
	if not roof.coat.is_empty() and not roof.coat[Mesh.ARRAY_VERTEX].is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, roof.coat)
		_coat.mesh = mesh
	var plastered := layout.plaster and layout.gable_end == WallLayout.GableEnd.WALL
	_gables.mesh = _faces_mesh(roof.gable_faces if plastered else PackedVector3Array())
	_torching.mesh = _faces_mesh(roof.torching_faces)


static func _faces_mesh(tris: PackedVector3Array) -> ArrayMesh:
	if tris.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in tris:
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()


## A built layout's stones as instance buffers by Part, and the box enclosing them. Reads nothing but its
## arguments, so it runs on a worker thread.
static func pack(built: WallLayout, ks: Array[Masonry.Kind], colours: PackedInt32Array) -> Dictionary:
	var stone := ks[Part.STONE]
	var mortar := ks[Part.MORTAR]
	var shadow := ks[Part.STONE_SHADOW]
	var timber := ks[Part.TIMBER]
	var paving := ks[Part.FLOOR]
	var counts := {}
	for s in built.stones:
		counts[s.kind] = counts.get(s.kind, 0) + 1
	var mortars: int = counts.get("mortar", 0) + counts.get("plaster", 0) + counts.get("bed", 0)
	var floor: int = counts.get("flagstone", 0) + counts.get("plank", 0)
	var beams: int = counts.get("timber", 0)
	var stones := built.stones.size() - mortars - beams - floor
	var bufs: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	bufs[0].resize(stones * stone.stride())
	bufs[1].resize(mortars * mortar.stride())
	bufs[2].resize((built.stones.size() - counts.get("mortar", 0) - counts.get("bed", 0) - floor) * shadow.stride())
	bufs[3].resize(beams * timber.stride())
	bufs[4].resize(floor * paving.stride())
	var n := [0, 0, 0, 0, 0]
	var box := AABB(built.samples[0] if built.samples.size() > 0 else Vector3.ZERO, Vector3.ZERO)
	for s in built.stones:
		var x: Transform3D = s.xform
		if s.kind in ["mortar", "plaster", "bed"]:
			mortar.write(bufs[1], n[1], x, _painted_as(s, colours), s.ao, Palette.code(s.kind), s.get("ends", Vector2.ZERO))
			n[1] += 1
		elif s.kind == "timber":
			timber.write(bufs[3], n[3], x, _painted_as(s, colours), s.ao, Palette.code(s.kind))
			n[3] += 1
		elif s.kind in ["flagstone", "plank"]:
			paving.write(bufs[4], n[4], x, _painted_as(s, colours), s.ao, Palette.code(s.kind))
			n[4] += 1
		else:
			x.basis = x.basis * Stones.FLIPS[s.variant]
			var c := _painted_as(s, colours)
			c.a = 0.0 if s.kind == "glass" else 1.0
			stone.write(bufs[0], n[0], x, c, s.ao, Palette.code(s.kind))
			n[0] += 1
		if s.kind != "mortar" and not s.kind in WallLayout.FLOOR_KINDS:
			shadow.write(bufs[2], n[2], x)
			n[2] += 1
		box = box.expand(x.origin)
	var chunks := {}
	var parts: Array[Part] = [Part.STONE, Part.MORTAR, Part.STONE_SHADOW, Part.TIMBER, Part.FLOOR]
	for i in bufs.size():
		chunks[parts[i]] = Masonry.split(bufs[i], ks[parts[i]])
	return {"stone": bufs[0], "mortar": bufs[1], "shadow": bufs[2], "timber": bufs[3], "floor": bufs[4], "chunks": chunks, "bounds": box.grow(0.6), "paint": colours}


## A laid part's colour in `colours`.
static func _painted_as(part: Dictionary, colours: PackedInt32Array) -> Color:
	var e := int(Palette.code(part.kind))
	return part.color * Palette.tint(e, colours[e]) if e != 0 else part.color


## Paints the wall in `to`. Its packed parts are scaled from the swatches they carry onto the new ones in place, a pass
## over its pieces instead of a lay.
func repaint(to: PackedInt32Array) -> void:
	if to == paint:
		return
	paint = to.duplicate()
	_tint_roof()
	_recolour()


func _tint_roof() -> void:
	if _gables != null:
		var t := Palette.tint(Palette.Element.PLASTER, paint[Palette.Element.PLASTER])
		_gables.set_instance_shader_parameter(&"tint", Vector3(t.r, t.g, t.b))
		var straw := Palette.tint(Palette.Element.THATCH, paint[Palette.Element.THATCH])
		_coat.set_instance_shader_parameter(&"tint", Vector3(straw.r, straw.g, straw.b))
		_torching.set_instance_shader_parameter(&"tint", Vector3(t.r, t.g, t.b))


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
		if _painted[e] != paint[e]:
			var a := Palette.tint(e, _painted[e])
			var b := Palette.tint(e, paint[e])
			scale[float(e)] = Vector3(b.r / a.r, b.g / a.g, b.b / a.b)
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


## Puts each part where it belongs: with the glade's Masonry once settled (ivy once grown), else drawn here.
func _sync() -> void:
	var placed: Array[Dictionary] = []
	var drawn: Array[Dictionary] = []
	var live := false
	for p in Part.size():
		var settle := _settled and (p != Part.IVY or not _ivy_growing())
		placed.append(_chunked[p] if settle else {})
		drawn.append(_chunked[p] if not settle and p != Part.IVY else {})
		live = live or not drawn[p].is_empty()
	masonry.place(get_instance_id(), placed)
	if live:
		if _drawn == null:
			_drawn = Masonry.new(kinds())
			add_child(_drawn)
		_drawn.place(get_instance_id(), drawn)
	elif _drawn != null:
		_drawn.queue_free()
		_drawn = null
	_show_ivy(_settled and _ivy_growing())
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
	for i in layout.samples.size():
		var under := layout.depths[i] if i < layout.depths.size() else 0.0
		var a := layout.samples[i] + Vector3.DOWN * under
		var up := Vector3.UP * (layout.height + WallLayout.CAP + under)
		var ud := up.dot(dir)
		var denom := up.dot(up) - ud * ud
		var w := origin - a
		var sc := 0.0 if absf(denom) < 1e-6 else clampf((up.dot(w) - ud * dir.dot(w)) / denom, 0.0, 1.0)
		var t := maxf(0.0, ud * sc - dir.dot(w))
		var p := a + up * sc
		var d := p.distance_to(origin + dir * t)
		var key := Vector2(0.0, t) if d < reach else Vector2(1.0, d)
		if key < best_key:
			best_key = key
			best_d = d
			best_i = i
			best_t = t
			best_p = p
	return {"distance": best_d, "s": layout.lengths[best_i] if best_d < INF else 0.0, "point": best_p, "along": best_t if best_d < INF else INF, "through": best_key.x == 0.0}


## Intersects the continuous wall body between samples, including its foundation and top.
func ray_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var n := layout.samples.size()
	var half := 0.1 if layout.fence else WallLayout.THICKNESS * 0.5
	for i in n if layout.closed else n - 1:
		var j := (i + 1) % n
		var a := layout.samples[i]
		var b := layout.samples[j]
		var edge := b - a
		var length := Vector2(edge.x, edge.z).length()
		if length < 1e-6:
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
		var height := layout.height + WallLayout.CAP
		var box := AABB(Vector3(0, -under, -half), Vector3(length, height + under, half * 2.0))
		var hit: Variant = local if box.has_point(local) else box.intersects_ray(local, direction)
		if hit == null:
			continue
		var t: float = (hit - local).dot(direction) / direction.length_squared()
		if t < best.get("along", INF):
			var end := layout.lengths[j] if j > 0 else layout.length()
			best = {"along": t, "point": origin + dir * t, "s": lerpf(layout.lengths[i], end, clampf(hit.x / length, 0.0, 1.0)), "distance": 0.0}
	return best

class_name Wall
extends Node3D

enum Part { STONE, MORTAR, STONE_SHADOW, TILE, TILE_SHADOW, COAT, IVY, TIMBER, FLOOR }
const PAINTED: Array[Part] = [Part.STONE, Part.MORTAR, Part.TILE, Part.COAT, Part.TIMBER, Part.FLOOR]

static var _kinds: Array[Masonry.Kind] = []
## Made at load: a shader made on first use stalled the Quest 2's frame 0.25 to 1.5 s at the session's first house.
static var _plaster := _material(preload("res://src/plaster.gdshader"), WallLayout.PLASTER)
static var _thatch := _material(preload("res://src/thatch.gdshader"))
static var _lime := _material(preload("res://src/torching.gdshader"), WallLayout.PLASTER)
static var _roof_wood := Stones.stone(preload("res://src/roof_timber.gdshader"))

var layout := WallLayout.new()
var masonry: Masonry
## As this player sees it, following a live hump while one is pulled.
var terrain: Terrain
var _fittings := Fittings.new()
var _smoke := Smoke.new()
var finished := false
## Laid in place of the garden's reshape data; empty when laid as the garden has it.
var reshaped := {}
## -1 while it is still being drawn.
var id := -1
var roof: RoofLayout
var paint := Palette.plain()
## The paint the packed parts carry, which may lag `paint` while a lay or recolour is under way.
var _painted := Palette.plain()
var _recolour_task := -1
var _recoloured := {}
var _laid := 0
var _wall_mortar := PackedFloat32Array()
## Ids of the builds it stands on; empty on the ground.
var on := PackedInt32Array()
var massing: Massing
var ivy_age := 0.0
var pick_bounds := AABB()
var _nearest := 0
var _ruin_pick: Array[TriangleMesh] = []
var _parts: Array[PackedFloat32Array] = []
var _chunked: Array[Dictionary] = []
var _drawn: Masonry
## The glade draws what `_sync` places over later frames (drawing a wall's chunks at once took 4 to 12 ms of a Steam
## Frame frame as a sculpt settled every wall); until then the wall draws its live stones, stand-in and ivy.
var _handoff := false
var _live := false
var _ivy_placed := false
var _ivy_handoff := false
var _ivy: MultiMeshInstance3D
var _gables: MeshInstance3D
var _coat: MeshInstance3D
var _coat_far: MeshInstance3D
var _torching: MeshInstance3D
var _ceiling: MeshInstance3D
var _occluder: OccluderInstance3D
var _faced := []
var _settled := false
var _ivy_times := PackedFloat32Array()
var _ivy_task := -1
var _ivy_baked := {}
var _ivy_stale := false
var _build_task := -1
var _build_stale := false
var _queued := false
## Laid from the frame after it fell due, so the frame applying a garden change does not lay it too; Budget.RELAYS a frame.
var due := Callable():
	set(lay):
		if lay.is_valid() and not due.is_valid():
			_due_since = Engine.get_process_frames()
			set_process(true)
		due = lay
var _due_since := 0
static var _due_frame := -1
static var _due_laid := 0
var _build := {}
var _shown := {}
var _settle_on_land := false
var _stand_in: Wall
## Freeing a long wall's thousands of stones takes milliseconds, so the wall's next worker task does it.
var _litter: Array[Array] = []
var _perches := PackedVector3Array()
var _perches_laid := -1
var _perch_task := -1
var _perch_out := {}


## A plain box per stone or tile casts the shadow, at a ninth of the triangles. Far tiles are plain boxes: from the air
## rounded ones cost the Quest 2 ten times as much. Near timber is a box, as planed wood shows no lumps; far, a shader with
## no per-pixel work. Floors cast no shadow and shade no bounce light, which reads a room's builds from its roof down.
static func kinds() -> Array[Masonry.Kind]:
	if _kinds.is_empty():
		var box := BoxMesh.new()
		var leaf := _material(preload("res://src/ivy.gdshader"))
		Quality.full_detail(leaf)
		var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shadow := Masonry.Kind.new(Meshes.plain_box(), null, false, false, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
		_kinds.resize(Part.size())
		_kinds[Part.STONE] = Masonry.Kind.new(Stones.mesh(), Stones.small_material(), true, true, off, true)
		_kinds[Part.STONE].far = Stones.far_mesh()
		_kinds[Part.STONE].far_baked = Stones.baked_material()
		_kinds[Part.STONE].size = WallLayout.LONGEST
		_kinds[Part.MORTAR] = Masonry.Kind.new(box, Stones.shared_material(), true, true, off)
		_kinds[Part.STONE_SHADOW] = shadow
		_kinds[Part.TILE] = Masonry.Kind.new(Meshes.rounded_box(0.22, 2, 41), Stones.small_material(), true, true, off, true)
		_kinds[Part.TILE].far = Stones.far_mesh()
		_kinds[Part.TILE].far_baked = Stones.baked_material()
		var roof_shadow := _material(preload("res://src/roof_shadow.gdshader"))
		_kinds[Part.TILE_SHADOW] = Masonry.Kind.new(Meshes.plain_box(), roof_shadow, false, false, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
		_kinds[Part.COAT] = Masonry.Kind.new(Meshes.plain_box(), roof_shadow, true, true, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, true)
		_kinds[Part.IVY] = Masonry.Kind.new(Meshes.sprig(), leaf, true, false, off)
		_kinds[Part.TIMBER] = Masonry.Kind.new(box, Stones.shared_material(), true, true, off, true)
		_kinds[Part.TIMBER].far = Stones.far_mesh()
		_kinds[Part.TIMBER].far_material = _material(preload("res://src/timber_far.gdshader"))
		_kinds[Part.TIMBER].far_baked = _material(preload("res://src/timber_far_baked.gdshader"))
		_kinds[Part.FLOOR] = Masonry.Kind.new(box, Stones.shared_material(), true, true, off)
		_kinds[Part.FLOOR].far = _kinds[Part.TIMBER].far
		_kinds[Part.FLOOR].far_material = _kinds[Part.TIMBER].far_material
		_kinds[Part.FLOOR].far_baked = _kinds[Part.TIMBER].far_baked
		_reach(Quality.ladder[0].stone_near_m, Quality.ladder[0].ivy_m)
	return _kinds


## Stone reach jumps at once, as a chunk changes mesh in one frame anyway; ivy eases as grass does. True once there.
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


## Color uniforms convert to linear and the wall instance buffer carries raw RGB, so the albedo goes as a Vector3.
static func _material(shader: Shader, albedo: Variant = null) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	if albedo != null:
		var c: Color = albedo
		m.set_shader_parameter("albedo", Vector3(c.r, c.g, c.b))
	return m


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


func data() -> Dictionary:
	var d := {
		"points": PackedVector3Array(layout.points), "height": layout.height, "rise": layout.rise,
		"seed": layout.seed, "closed": layout.closed, "top": int(layout.top), "fence": layout.fence,
		"openings": PackedVector4Array(layout.openings), "lanterns": PackedVector3Array(layout.lanterns), "flags": PackedFloat32Array(layout.flags), "clutter": PackedVector4Array(layout.clutter),
		"ruins": PackedVector2Array(layout.ruins), "finish": int(layout.finish), "wear": layout.wear, "foundation": int(layout.foundation), "planks": layout.planks, "gable_end": int(layout.gable_end), "on": PackedInt32Array(on), "paint": PackedInt32Array(paint),
	}
	if roof != null:
		d.roof = roof.data()
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
	set_process(finished or laying() or _recolour_task >= 0)


func _process(delta: float) -> void:
	if due.is_valid() and Engine.get_process_frames() > _due_since and _may_lay_due():
		_lay_due()
	if _queued and _slot_free():
		_queued = false
		_lay()
	var done := _build_task >= 0 and WorkerThreadPool.is_task_completed(_build_task)
	if _build_task >= 0 and (Work.due(_build_task) if finished else done):
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
	if _handoff and masonry.drawn(get_instance_id()):
		_hand_off()
	if _ivy != null:
		var mm := _ivy.multimesh
		mm.visible_instance_count = mini(_ivy_times.bsearch(ivy_age), mm.instance_count)
	if not laying() and _recolour_task < 0 and not _ivy_growing() and not _handoff:
		set_process(false)
		if _settled:
			_sync()


func lay_now() -> void:
	if due.is_valid():
		_lay_due()
	while _build_task >= 0 or _queued or _recolour_task >= 0:
		if _queued:
			_queued = false
			_lay()
		if _build_task >= 0:
			_land()
		else:
			_land_recolour()


## A settling lay whose inputs changed is dropped: shown, its stones would stand apart from the glade's meanwhile.
func _land() -> void:
	Work.take(_build_task)
	_build_task = -1
	if _build_stale and _settle_on_land:
		_litter.append(_build.job.stones)
		_build_live()
		return
	_litter.append(layout.stones)
	_shown = _build
	if _build_stale:
		_build_live()
	if _settle_on_land and not laying():
		_settle()
	else:
		_put_shown()
		_occlude(PackedVector3Array(), PackedInt32Array())
		_sync()


func _ivy_growing() -> bool:
	return _ivy_task >= 0 or (not _ivy_times.is_empty() and ivy_age <= _ivy_times[-1])


## A stand-in let go as its wall leaves may outlive the glade.
func _exit_tree() -> void:
	if is_instance_valid(masonry):
		masonry.remove(get_instance_id())
		if _drawn != null:
			masonry.announce(get_instance_id(), Masonry.nothing(masonry.kinds.size()))
	if is_instance_valid(_stand_in):
		_stand_in.queue_free()


## A task outliving its wall crashes the engine at exit; in play `reap` takes them, as waiting here held a frame 25 ms
## on a Quest 2. Here, not `_exit_tree`, since a wall freed outside the tree never exits it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for t in [_ivy_task, _build_task, _perch_task, _recolour_task]:
			if t >= 0:
				_orphans.append(t)
		if quitting:
			reap(true)


static var _orphans := PackedInt32Array()
static var quitting := false


static func reap(all := false) -> void:
	var left := PackedInt32Array()
	for t in _orphans:
		if all or WorkerThreadPool.is_task_completed(t):
			Work.take(t)
		else:
			left.append(t)
	_orphans = left


## On a worker: it reads every stone, milliseconds for a long wall. `now` is for a caller stepping time without frames.
func perches(now := false) -> PackedVector3Array:
	if now:
		lay_now()
		_take_perches(true)
		if _perches_laid != layout.laid:
			_perches = layout.perches()
			_perches_laid = layout.laid
		return _perches
	_take_perches(false)
	if _perch_task < 0 and _perches_laid != layout.laid and not laying():
		var job := WallLayout.new()
		job.stones = layout.stones.duplicate()
		job.cover = layout.cover
		var out := {"laid": layout.laid}
		_perch_out = out
		_perch_task = Work.start(func(): out.points = job.perches(), Budget.PERCH_FRAMES)
	_take_perches(false)
	return _perches


func _take_perches(wait: bool) -> void:
	if _perch_task >= 0 and (wait or Work.due(_perch_task)):
		Work.take(_perch_task)
		_perch_task = -1
		_perches = _perch_out.points
		_perches_laid = _perch_out.laid


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


## On a worker; the standing stones show until it lands. `settle` is false while a stroke, grip lift, roof pull or
## house footprint is still moving.
func rebuild(settle := true) -> void:
	_settle_on_land = settle
	if not settle:
		_settled = false
	if settle and _build_task < 0 and _laid_from(_shown):
		_queued = false
		_settle()
	else:
		_build_live()


## `preview`, the wall in hand, shows until this copy's stones are laid. It lands whenever its worker is done, which no
## frame decides, so this copy lays its own.
func stand_in(preview: Wall) -> void:
	preview.set_process(false)
	_stand_in = preview


func _laid_from(b: Dictionary) -> bool:
	if b.is_empty() or b.revision != terrain.shown_revision() or not b.job.same_inputs(layout) or (b.roof == null) != (roof == null):
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
	_occlude(_shown.out.occluder[0], _shown.out.occluder[1])
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


func laying() -> bool:
	return _build_task >= 0 or _queued or due.is_valid()


static func _may_lay_due() -> bool:
	if _due_frame != Engine.get_process_frames():
		_due_frame = Engine.get_process_frames()
		_due_laid = 0
	return not Budget.frame_deadline or _due_laid < Budget.RELAYS


func _lay_due() -> void:
	var lay := due
	due = Callable()
	lay.call()
	_due_laid += 1


## The frames garden walls' lays come due at, each holding its slot until then: a sculpt relays every wall at once, and
## unbounded they take every worker while the frame waits on the pool. A wall in hand holds none.
static var _lays := PackedInt32Array()


func _build_live() -> void:
	set_process(true)
	if roof != null:
		_cover()
	if _build_task >= 0:
		_build_stale = not _laid_from(_build)
		return
	if _queued:
		return
	if finished and not _slot_free():
		_queued = true
		return
	_lay()


static func _slot_free() -> bool:
	var running := PackedInt32Array()
	for at in _lays:
		if at > Work.now():
			running.append(at)
	_lays = running
	return _lays.size() < Budget.WALL_LAYS


func _lay() -> void:
	set_process(true)
	_build_stale = false
	var job := layout.inputs()
	var roof_job := roof.inputs() if roof != null else null
	job.gable = roof_job
	var out := {}
	_build = {"job": job, "roof": roof_job, "revision": terrain.shown_revision(), "out": out}
	var ks := kinds()
	var litter := _sweep()
	var height := terrain.held_height(true)
	var water := terrain.held_water(true)
	var revision := terrain.shown_revision()
	var colours := paint.duplicate()
	var frames := Budget.lay_frames(Budget.wall(data())) if finished else Budget.LAY_FRAMES
	_build_task = Work.start(func():
		_drop(litter)
		job.build(height, water, revision)
		if roof_job != null:
			out.roofed = Wall.pack_roof(job, roof_job, ks, colours)
		out.merge(Wall.pack(job, ks, colours)), frames)
	if finished:
		_lays.append(Work.now() + frames)


func _lay_dressing(roofed: Dictionary) -> void:
	if roof != null:
		_pack_roof(roofed)
	else:
		_fittings.lay(layout.flames, layout.cloths, paint[Palette.Element.LANTERN])
		_smoke.lay(PackedVector3Array())


## Touches nothing but its arguments: it runs on a worker thread.
static func pack_roof(built: WallLayout, r: RoofLayout, ks: Array[Masonry.Kind], colours: PackedInt32Array) -> Dictionary:
	built.seat(r)
	r.build(WallLayout.PLASTER_INSET if built.plastered() and built.gable_kind() == WallLayout.GableEnd.WALL else WallLayout.THICKNESS * 0.5)
	built.hide_roof(r)
	built.fit_under(r)
	var mortar: PackedFloat32Array = _pack_parts(r.mortar, func(_m: Dictionary) -> Array: return [Part.MORTAR], ks, colours)[Part.MORTAR]
	var slabs: PackedFloat32Array = _pack_parts(r.slabs, func(_m: Dictionary) -> Array: return [Part.COAT], ks, colours)[Part.COAT]
	var tiled := _pack_parts(r.tiles, func(t: Dictionary) -> Array: return [Part.TILE] if t.kind == "glass" else [Part.TILE, Part.TILE_SHADOW], ks, colours)
	var tiles := tiled[Part.TILE]
	var shadows := tiled[Part.TILE_SHADOW]
	var chunks := {Part.TILE: Masonry.split(tiles, ks[Part.TILE]), Part.TILE_SHADOW: Masonry.split(shadows, ks[Part.TILE_SHADOW]), Part.COAT: Masonry.split(slabs, ks[Part.COAT])}
	return {"roof": r, "tiles": tiles, "shadows": shadows, "slabs": slabs, "chunks": chunks, "mortar": mortar}


func _pack_roof(roofed: Dictionary) -> void:
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
	var plastered := layout.plastered() and layout.gable_kind() == WallLayout.GableEnd.WALL
	var faces := [roof.coat, roof.gable_faces if plastered else PackedVector3Array(), roof.torching_faces, roof.timber_faces, PackedVector3Array() if plastered else roof.gable_faces]
	if faces == _faced:
		return
	_faced = faces.duplicate(true)
	_coat.mesh = _coat_mesh(roof.coat)
	_coat_far.mesh = _coat_mesh(roof.coat_far)
	_coat.visibility_range_end = kinds()[Part.STONE].near + (_coat.mesh.get_aabb().size.length() * 0.5 if _coat.mesh != null else 0.0)
	_coat_far.visibility_range_begin = _coat.visibility_range_end
	_gables.mesh = _faces_mesh(faces[1])
	_torching.mesh = _faces_mesh(faces[2], false, faces[4])
	_ceiling.mesh = _faces_mesh(faces[3], true)
	_ceiling.visibility_range_end = kinds()[Part.TIMBER].near + (_ceiling.mesh.get_aabb().size.length() * 0.5 if _ceiling.mesh != null else 0.0)


static func _coat_mesh(arrays: Array) -> ArrayMesh:
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX].is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _faces_mesh(tris: PackedVector3Array, flat_normals := false, backing := PackedVector3Array()) -> ArrayMesh:
	if tris.is_empty() and backing.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if flat_normals:
		st.set_smooth_group(-1)
	st.set_color(Color(0, 0, 0))
	for p in tris:
		st.add_vertex(p)
	# A gable's two backing faces lie on its centre line, wound apart: smoothed together, their normals would cancel.
	st.set_smooth_group(-1)
	st.set_color(Color(1, 0, 0))
	for p in backing:
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()


static func stone_parts(stones: Array[Dictionary], ks: Array[Masonry.Kind]) -> Array[Dictionary]:
	var wall := WallLayout.new()
	wall.stones = stones
	var packed := pack(wall, ks, Palette.plain())
	var parts: Array[Dictionary] = []
	for k in Part.size():
		parts.append(packed.chunks.get(k, {}))
	return parts


## Reads nothing but its arguments: it runs on a worker thread.
static func pack(built: WallLayout, ks: Array[Masonry.Kind], colours: PackedInt32Array) -> Dictionary:
	var route := func(s: Dictionary) -> Array:
		var own := Part.MORTAR if s.kind in ["mortar", "plaster", "bed"] else Part.TIMBER if s.kind in ["timber", "board"] else Part.FLOOR if s.kind in ["flagstone", "plank"] else Part.STONE
		# Glass casts no shadow: the sun through a window lands on the floor inside (Interior).
		return [own] if s.kind in ["mortar", "crop", "glass"] or s.kind in WallLayout.FLOOR_KINDS else [own, Part.STONE_SHADOW]
	var bufs := _pack_parts(built.stones, route, ks, colours)
	var box := AABB(built.samples[0] if built.samples.size() > 0 else Vector3.ZERO, Vector3.ZERO)
	for s in built.stones:
		box = box.expand(s.xform.origin)
	var chunks := {}
	for part in [Part.STONE, Part.MORTAR, Part.STONE_SHADOW, Part.TIMBER, Part.FLOOR]:
		chunks[part] = Masonry.split(bufs[part], ks[part])
	return {"stone": bufs[Part.STONE], "mortar": bufs[Part.MORTAR], "shadow": bufs[Part.STONE_SHADOW], "timber": bufs[Part.TIMBER], "floor": bufs[Part.FLOOR], "chunks": chunks, "bounds": box.grow(0.6), "paint": colours, "ruin_pick": _pack_ruin(built), "occluder": _pack_occluder(built)}


## Mortar and plaster stand behind the stones' faces, so whatever they hide is hidden.
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


## `into` names each part's Parts, its own first.
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


static func _painted_as(part: Dictionary, colours: PackedInt32Array) -> Color:
	var e := int(Palette.code(part.kind))
	return part.color * Palette.tint(e, colours[e]) if e != 0 else part.color


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
		# The lining material's albedo is plaster, so other backings are tinted relative to it.
		var g := t
		if layout.gable_kind() == WallLayout.GableEnd.BOARDS:
			g = Palette.tint(Palette.Element.WOOD, paint[Palette.Element.WOOD]) * WallLayout.WOOD / WallLayout.PLASTER
		elif not layout.plastered():
			g = Palette.tint(Palette.Element.STONE, paint[Palette.Element.STONE]) * WallLayout.MORTAR * 0.8 / WallLayout.PLASTER
		_gables.set_instance_shader_parameter(&"tint", Vector3(g.r, g.g, g.b))
		_torching.set_instance_shader_parameter(&"backing_tint", Vector3(g.r, g.g, g.b))
		var straw := Palette.tint(Palette.Element.THATCH, paint[Palette.Element.THATCH])
		for coat in [_coat, _coat_far]:
			coat.set_instance_shader_parameter(&"tint", Vector3(straw.r, straw.g, straw.b))
		_torching.set_instance_shader_parameter(&"tint", Vector3(t.r, t.g, t.b))
		var wood := WallLayout.WOOD * Palette.tint(Palette.Element.TIMBER, paint[Palette.Element.TIMBER])
		_ceiling.set_instance_shader_parameter(&"timber_color", Vector3(wood.r, wood.g, wood.b))


## On a worker, too long for a frame on a big build. The buffers are shared with a lay that may be taken again, so copied.
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
		parts[p] = [_parts[p], ks[p]]
	var out := {"laid": _laid, "to": paint.duplicate()}
	_recoloured = out
	set_process(true)
	_recolour_task = WorkerThreadPool.add_task(func():
		for p in parts:
			var flat := Wall._scaled(parts[p][0], parts[p][1].stride(), scale)
			out[p] = [flat, Masonry.split(flat, parts[p][1])])


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


## Masonry.Kind instance layout: colour at 12, material code at 17.
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


## Only a settling lay occludes, and only a changed occluder is set: every occluder change rebuilds the occlusion BVH,
## which a sculpt relaying every wall turned into frames of waiting. A wall occluding nothing has no node: a carry moving
## even an empty one rebuilds it.
func _occlude(vertices: PackedVector3Array, indices: PackedInt32Array) -> void:
	if vertices.is_empty():
		if _occluder != null:
			_occluder.free()
			_occluder = null
		return
	if _occluder == null:
		_occluder = OccluderInstance3D.new()
		_occluder.occluder = ArrayOccluder3D.new()
		add_child(_occluder)
	var occluder := _occluder.occluder as ArrayOccluder3D
	if occluder.vertices != vertices or occluder.indices != indices:
		occluder.set_arrays(vertices, indices)


## For a wall a hold set back as it was laid, which no lay settles.
func occlude_shown() -> void:
	if _occluder == null:
		_occlude(_shown.out.occluder[0], _shown.out.occluder[1])


## So a carrying hold moves its stones; the glade lets them go at once (`Masonry.flush`) or they stay where taken from.
## A lay under way lands live too: settled, its stones would go to the glade and stay there as the hold carries the rest.
func draw_live() -> void:
	_settle_on_land = false
	_occlude(PackedVector3Array(), PackedInt32Array())
	if _settled:
		_settled = false
		_sync()


## Stones drawn here upload at once, so they are always the ones laid, which a carry's transform is placed for. A wall
## drawing its own stones keeps drawing the latest lay until the glade draws it: the roof's faces show that lay at once.
func _sync() -> void:
	var placed: Array[Dictionary] = []
	var drawn: Array[Dictionary] = []
	for p in Part.size():
		var settle := _settled and (p != Part.IVY or not _ivy_growing())
		placed.append(_chunked[p] if settle else {})
		drawn.append(_chunked[p] if p != Part.IVY else {})
	var ivy_placed := not placed[Part.IVY].is_empty()
	_ivy_handoff = ivy_placed and (_ivy_handoff or not _ivy_placed)
	_ivy_placed = ivy_placed
	masonry.place(get_instance_id(), placed)
	_live = not _settled and drawn.any(func(d: Dictionary) -> bool: return not d.is_empty())
	_handoff = not masonry.drawn(get_instance_id())
	if _live or (_handoff and _drawn != null):
		if _drawn == null:
			_drawn = Masonry.new(kinds())
			_drawn.carry = transform
			add_child(_drawn)
		_drawn.place(get_instance_id(), drawn)
		_drawn.flush()
		# The bounce volume reads pieces as the glade announces them, whichever draws them.
		masonry.announce(get_instance_id(), drawn)
	if _handoff:
		set_process(true)
		_show_ivy(_ivy_handoff or (_settled and _ivy_growing()))
	else:
		_hand_off()


## Moves the build as a hold carries it; what it draws itself keeps the light of where it was laid.
func carry(x: Transform3D) -> void:
	transform = x
	if _drawn != null:
		_drawn.carry = x
	for g: GeometryInstance3D in [_gables, _coat, _coat_far, _torching, _ceiling]:
		if g != null:
			Masonry.show_carry(g, x)


func _hand_off() -> void:
	_handoff = false
	_ivy_handoff = false
	if _drawn != null and not _live:
		_drawn.queue_free()
		_drawn = null
	if is_instance_valid(_stand_in):
		_stand_in.queue_free()
	_stand_in = null
	_show_ivy(_settled and _ivy_growing())


func _show_ivy(growing: bool) -> void:
	var buf := _parts[Part.IVY] if growing else PackedFloat32Array()
	if _ivy == null:
		if buf.is_empty():
			return
		_ivy = kinds()[Part.IVY].instance()
		add_child(_ivy)
	kinds()[Part.IVY].fill(_ivy.multimesh, buf)


func footprint() -> Rect2:
	return layout.bounds.grow(WallLayout.THICKNESS)


## The first stretch the ray passes through, so a ray into a house finds the side facing it, else the one it nears most.
func ray_distance(origin: Vector3, dir: Vector3) -> Dictionary:
	var reach := layout.half_thickness()
	var best_key := Vector2.INF
	var best_d := INF
	var best_i := 0
	var best_t := 0.0
	var best_p := Vector3.ZERO
	# A hand's ray moves little between frames, so the sample nearest last time bounds what any sample must come within.
	var bound := Vector2.INF
	if _nearest < layout.samples.size():
		var seen := _sample_near(_nearest, origin, dir, reach)
		if not seen.is_empty():
			bound = seen[0]
	# A sample's distance from the ray seen from above bounds its true one: one out of reach skips those near it along
	# the wall.
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


## `through_arches` sees through each arch's opening to the stone round it.
func ray_hit(origin: Vector3, dir: Vector3, through_arches := false) -> Dictionary:
	if not _ruin_pick.is_empty():
		return _ruin_hit(origin, dir)
	var best := {}
	var n := layout.samples.size()
	var half := layout.half_thickness()
	# Arc length bounds how far apart two samples stand, so a sample far from the ray (seen from above) skips every
	# stretch after it that cannot come near: a long wall costs a ray a few steps.
	var flat := Vector2(dir.x, dir.z)
	var across := flat.normalized() if flat.length_squared() > 1e-12 else Vector2.ZERO
	var from := Vector2(origin.x, origin.z)
	var lengths := layout.lengths
	var height := layout.height + layout.top_rise()
	# So does one behind the ray's start, or past `clear`: over every top, under every foot or past the nearest hit yet.
	var feet := layout.feet()
	var climb := dir.y / flat.length() if across != Vector2.ZERO else 0.0
	var clear := INF
	if climb > 0.0:
		clear = maxf(feet.y + height - origin.y, 0.0) / climb
	elif climb < 0.0:
		clear = minf(feet.x - origin.y, 0.0) / climb
	var next := 0
	while next < (n if layout.closed else n - 1):
		var i := next
		next += 1
		var a := layout.samples[i]
		var off := Vector2(a.x, a.z) - from
		var along := across.dot(off)
		var gap := maxf(maxf(absf(across.cross(off)) if across != Vector2.ZERO else off.length(), along - clear), -along) - half - 0.01
		if gap > 0.0 and i < n - 1:
			var past := lengths.bsearch(lengths[i] + gap) - 1
			if past > i:
				next = past
				continue
		var b := layout.samples[(i + 1) % n]
		if across.dot(Vector2(a.x + b.x, a.z + b.z) * 0.5 - from) < -(Vector2(b.x - a.x, b.z - a.z).length() * 0.5 + half + 0.01):
			continue
		var hit := _stretch_hit(i, origin, dir, through_arches, best.get("along", INF), half, height)
		if not hit.is_empty():
			best = hit
			clear = minf(clear, best.along * flat.length())
	return best


func _stretch_hit(i: int, origin: Vector3, dir: Vector3, through_arches: bool, nearer_than: float, half: float, height: float) -> Dictionary:
	var n := layout.samples.size()
	var j := (i + 1) % n
	var a := layout.samples[i]
	var edge := layout.samples[j] - a
	var length := Vector2(edge.x, edge.z).length()
	if length < 1e-6:
		return {}
	var x := Vector3(edge.x, 0, edge.z) / length
	var z := x.cross(Vector3.UP)
	var slope := edge.y / length
	var offset := origin - a
	var ox := offset.dot(x)
	var dx := dir.dot(x)
	var local := Vector3(ox, offset.y - slope * ox, offset.dot(z))
	var direction := Vector3(dx, dir.y - slope * dx, dir.dot(z))
	var under := maxf(layout.depths[i], layout.depths[j]) if layout.depths.size() == n else 0.0
	var box := AABB(Vector3(0, -under, -half), Vector3(length, height + under, half * 2.0))
	var hit: Variant = local if box.has_point(local) else box.intersects_ray(local, direction)
	if hit == null:
		return {}
	var t: float = (hit - local).dot(direction) / direction.length_squared()
	if layout.hides(origin + dir * t) or t >= nearer_than:
		return {}
	var end := layout.lengths[j] if j > 0 else layout.length()
	var arched := through_arches and _open(i, end, length, local + direction * t)
	if arched:
		var open := func(at: float) -> bool: return _open(i, end, length, local + direction * at)
		t = _first_solid(open, t, _exit(box, local, direction))
		if t == INF or layout.hides(origin + dir * t) or t >= nearer_than:
			return {}
	var at: Vector3 = local + direction * t
	var face := Rig.box_normal(box, at)
	var side := arched or Rig.side(x * face.x + (Vector3.UP - x * slope) * face.y + z * face.z)
	return {"along": t, "point": origin + dir * t, "s": lerpf(layout.lengths[i], end, clampf(at.x / length, 0.0, 1.0)), "distance": 0.0, "side": side}


## `p` is in the stretch's frame.
func _open(i: int, end: float, length: float, p: Vector3) -> bool:
	return layout.open_at(lerpf(layout.lengths[i], end, p.x / length), p.y)


static func _exit(box: AABB, local: Vector3, direction: Vector3) -> float:
	var out := INF
	for k in 3:
		if absf(direction[k]) > 1e-9:
			out = minf(out, ((box.end[k] if direction[k] > 0.0 else box.position[k]) - local[k]) / direction[k])
	return out


## An arch's opening narrows only upward, so stepping finer than a jamb's thickness finds the first solid point.
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


## A ruin has no continuous body; its query trees are built on the worker so aiming does not scan every stone a frame.
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
			var face: bool = i == 0 and hit.position.y < layout.frame_at(s).point.y + layout.standing(s) - WallLayout.COURSE * 0.5
			best = {"along": along, "point": hit.position, "s": s, "distance": 0.0, "rubble": i == 1, "side": face or Rig.side(normal)}
	return best

class_name Flora
extends Node3D

## Every plant in the glade: the meadow's own and those painted or placed since. Painted plants of each
## kind share one MultiMesh allocated up front, so painting writes instances without resizing GPU buffers. A plant's
## transform and its anchor count their height from the ground under it, which its shader reads from the
## terrain each frame, so reshaping the ground moves no instance and leaves no plant a stale height.

const PAINTED_GRASS := 12000
## The meadow's grass cells are small, so a cell turns sparse close to where its clumps do.
const GRASS_CELL := 8.0
## From GRASS_LOD_BEGIN out, over GRASS_LOD_BAND, a clump draws fewer, wider blades (Meshes.grass_clump): far blades
## are slivers whose cost is their count, not their pixels. Over the same band all but the GRASS_SURVIVORS share of
## clumps (by FloraLayout.thin_rank) sink away, so past it a cell draws its survivors alone, from a mesh of the kept
## blades only. Survivors sink away in turn from GRASS_SURVIVORS_FROM of the grass reach out to it, each at its own
## distance: the meadow thins with distance instead of ending at a ring of growing blades.
const GRASS_LOD_BEGIN := 8.0
const GRASS_LOD_BAND := 4.0
const GRASS_SURVIVORS := 0.25
const GRASS_SURVIVORS_FROM := 0.5
## A clump draws CLUMP_BLADES blades, each CLUMP_WIDE times a blade's width, covering what seven narrower ones did:
## near grass costs the Quest 2 its triangles as well as its pixels.
const CLUMP_BLADES := 5
const CLUMP_WIDE := 1.4
## Land flowers past this distance draw as their far patches (flora_far.gdshader).
const FLOWER_NEAR := 12.0
## Petals a flower head opens.
const PETALS := 4
const PAINTED_MOSS := 256
const PAINTED_FLOWERS := 4000
const PLACED_TREES := 64
const PLACED_BUSHES := 256
## The shade blob's size against the box around a crown's blobs, which their lumps and gaps do not fill.
const SHADE_FIT := 0.8
## Where an untracked hand is, as far as the grass knows.
const NO_HAND := Vector3(0, -1000, 0)
## Plant kinds as build commands name them: painted in strokes, or placed one at a time.
const BRUSHES := ["grass", "flowers", "moss"]
const PLACED := ["tree", "bush"]
const SOLID_CELL := 8.0
## The meadow's own trunks, crowns and bushes each bake into one MultiMesh, not one a square: the Quest 2 pays 7 to
## 19 µs a draw whatever it holds, more than their few thousand triangles cost off screen (docs/design.md, "Crowns").
const SOLID_POOL_CELL := INF
## How long a frame spends growing committed strokes: a stroke of thousands of plants grows over a few frames
## rather than in the one its command applied in.
const GROW_USEC := 1500

## When no committed stroke is left growing.
signal grown


## One kind of plant, in numbered slots. Slots filled before `keep()` are the meadow's own: `keep()` bakes them into
## one MultiMesh per `cell` square, so the camera culls those off screen, and they are never recycled. A pool with a
## `sparse` mesh also bakes, per cell, the plants whose rank (colour alpha) is under `survivors` drawn with it, and
## draws that instead of the whole cell once the cell lies wholly beyond `sparse_from`. Later slots fill `capacity`
## in order and, once it is full, replace the oldest; each is drawn in a Patch, a growing MultiMesh per `cell`
## square, so painted plants off screen or past reach cost nothing either. Every tree has the same number of
## blobs, so the trunk and foliage pools recycle in step.
class Pool:
	const GONE := Vector3(1e9, 0, 1e9)
	const GRID := 2.0
	var cell: float
	var sparse: Mesh
	var sparse_from := INF
	var survivors := 0.0
	## What the meadow's own plants bake with, where they need less than placed ones: no water plant parts.
	var kept_mesh: Mesh
	var capacity: int
	var far: MultiMesh
	var far_live: MultiMeshInstance3D
	## For the painted and meadow grass, where the ground paints it past the clumps' reach.
	var cover: FloraCover
	## Set on each patch's instance: the shaders tell placed plants from the meadow's own by it.
	var planted := 0.0
	var material: Material
	## Bumped by every `Plant.draw`, so the crowns' shade can follow a tool's preview.
	var draws := 0
	## The mesh each plant was made with; `draw_with` may draw a simpler one in its place.
	var mesh: Mesh
	var drawn: Mesh
	var kept := 0
	var _count := 0
	var last := -1
	var _next := 0
	## Bumped each time a slot is reused, so a remembered plant knows when its slot has moved on.
	var stamps := PackedInt32Array()
	var anchors := PackedVector3Array()
	## Bumped with every change to `anchors` or a plant's transform, so a reader can tell nothing moved.
	var anchored := 0
	var plants: Array[Plant] = []
	var _parent: Node3D
	var terrain: Terrain
	var _shadows: bool
	## Each slot's colour and custom data, and each painted slot's drawn transform: a MultiMesh does not give them
	## back, and a patch moves its instances about.
	var _colors := PackedColorArray()
	var _customs := PackedColorArray()
	var _xforms: Array[Transform3D] = []
	var _patches := {}
	## By painted slot (slot - kept), the patch drawing it and its instance there.
	var _patch_of: Array[Patch] = []
	var _index_in_patch := PackedInt32Array()
	var _cell_of: Array[MultiMesh] = []
	var _index_in_cell := PackedInt32Array()
	var _cells: Array[MultiMeshInstance3D] = []
	var _sparse_cells: Array[MultiMeshInstance3D] = []
	var _sparse_cell_of: Array[MultiMesh] = []
	var _index_in_sparse := PackedInt32Array()
	var _centres := PackedVector2Array()
	## The layers each of `_cells` was last given, so `cull` writes only a change.
	var _cell_layers := PackedInt32Array()
	## With `indexed`, slots by the GRID square their anchor fell in, for finding plants near a point without a
	## pass over all.
	var indexed := false
	var _grid := {}
	## Its plants grow in soil: one standing on rock (Terrain.ROCK) is not drawn, and is again once the ground under it
	## is gentle enough to hold soil.
	var soil := false

	func _init(parent: Flora, m: Mesh, slots: int, mat: Material, shadows: bool, size := 16.0) -> void:
		terrain = parent.terrain
		mesh = m
		drawn = m
		cell = size
		capacity = slots
		_parent = parent
		material = mat
		_shadows = shadows
		stamps.resize(slots)
		anchors.resize(slots)
		plants.resize(slots)
		_colors.resize(slots)
		_customs.resize(slots)
		_xforms.resize(slots)
		_patch_of.resize(slots)
		_index_in_patch.resize(slots)

	## `custom`'s blue and alpha are taken for `anchor`.
	func add(xform: Transform3D, color: Color, anchor: Vector3, custom := Color()) -> Plant:
		var i := kept + _count
		if _count < capacity:
			_count += 1
		elif capacity == 0:
			return null
		else:
			i = kept + _next
			_next = (_next + 1) % capacity
			_unpatch(i - kept)
		last = i
		if indexed and plants[i] != null:
			_unindex(i)
		if cover != null and plants[i] != null:
			cover.touch(plants[i].anchor)
		var ground := terrain.height_at(anchor.x, anchor.z)
		xform.origin.y -= ground
		anchor.y -= ground
		custom.b = anchor.x
		custom.a = anchor.z
		var rock := soil and terrain.rock_at(anchor.x, anchor.z)
		_colors[i] = color
		_customs[i] = custom
		_xforms[i] = _drawn_as(xform, rock)
		_patch(i - kept)
		if far != null:
			far.visible_instance_count = kept + _count
			far.set_instance_transform(i, _xforms[i])
			far.set_instance_color(i, color)
			far.set_instance_custom_data(i, custom)
		stamps[i] += 1
		anchors[i] = anchor
		anchored += 1
		plants[i] = Plant.new(self, i, xform, anchor)
		plants[i].rock = rock
		if indexed:
			_grid.get_or_add(square(anchor), []).append(i)
		if cover != null:
			cover.looks[i] = FloraCover.look(color, custom)
			cover.touch(anchor)
		return plants[i]

	## Draws painted slot `j` from its `_xforms`, `_colors` and `_customs` in the patch of the square it stands in.
	func _patch(j: int) -> void:
		var i := kept + j
		var key := Vector2i(floori(_xforms[i].origin.x / cell), floori(_xforms[i].origin.z / cell))
		var p: Patch = _patches.get(key)
		if p == null:
			p = Patch.new()
			p.key = key
			p.mm = MultiMesh.new()
			_setup(p.mm, drawn, Patch.FIRST)
			p.mm.visible_instance_count = 0
			p.mmi = _show(p.mm)
			p.mmi.set_instance_shader_parameter(&"planted", planted)
			_patches[key] = p
		var n := p.slots.size()
		if n == p.mm.instance_count:
			p.mm.instance_count = n * 2
			terrain.lift(p.mm, p.box)
			for k in n:
				_write(p, k, p.slots[k])
		var ground := terrain.bounds()
		var box := _xforms[i] * mesh.get_aabb()
		box.position.y += ground.position.y
		box.size.y += ground.size.y
		box = box.grow(0.5)
		if n == 0 or not p.box.encloses(box):
			p.box = box if n == 0 else p.box.merge(box)
			terrain.lift(p.mm, p.box)
		p.slots.append(i)
		p.mm.visible_instance_count = n + 1
		p.mmi.visible = true
		_patch_of[j] = p
		_index_in_patch[j] = n
		_write(p, n, i)

	## Takes painted slot `j` out of its patch, its last instance moving into the gap.
	func _unpatch(j: int) -> void:
		var p := _patch_of[j]
		if p == null:
			return
		var k := _index_in_patch[j]
		var end: int = p.slots.size() - 1
		if k != end:
			var moved: int = p.slots[end]
			p.slots[k] = moved
			_index_in_patch[moved - kept] = k
			_write(p, k, moved)
		p.slots.resize(end)
		p.mm.visible_instance_count = end
		p.mmi.visible = end > 0
		_patch_of[j] = null

	func _write(p: Patch, k: int, i: int) -> void:
		p.mm.set_instance_transform(k, _xforms[i])
		p.mm.set_instance_color(k, _colors[i])
		p.mm.set_instance_custom_data(k, _customs[i])

	static func square(at: Vector3) -> Vector2i:
		return Vector2i(floori(at.x / GRID), floori(at.z / GRID))

	## The slots indexed in a grid square (`square`).
	func in_square(at: Vector2i) -> Array:
		return _grid.get(at, [])

	func _unindex(i: int) -> void:
		_grid[square(plants[i].anchor)].erase(i)

	## The standing plants within `radius` of `p` across the ground.
	func near(p: Vector3, radius: float) -> Array[Plant]:
		var out: Array[Plant] = []
		var r2 := radius * radius
		var lo := square(p - Vector3(radius, 0, radius))
		var hi := square(p + Vector3(radius, 0, radius))
		for j in range(lo.y, hi.y + 1):
			for i in range(lo.x, hi.x + 1):
				for slot: int in _grid.get(Vector2i(i, j), []):
					var q := anchors[slot]
					if (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) < r2:
						out.append(plants[slot])
		return out

	func keep() -> void:
		kept = _count
		var cells := {}
		for i in kept:
			var o := plants[i].xform.origin
			cells.get_or_add(Vector2i(floori(o.x / cell), floori(o.z / cell)), []).append(i)
		_cell_of.resize(kept)
		_index_in_cell.resize(kept)
		_sparse_cell_of.resize(kept)
		_index_in_sparse.resize(kept)
		for key: Vector2i in cells:
			var slots: Array = cells[key]
			var whole := _bake(slots, kept_mesh if kept_mesh != null else drawn)
			for j in slots.size():
				_cell_of[slots[j]] = whole
				_index_in_cell[slots[j]] = j
			_cells.append(_show(whole))
			_cell_layers.append(1)
			_centres.append((Vector2(key) + Vector2(0.5, 0.5)) * cell)
			if sparse != null:
				var few := slots.filter(func(i: int) -> bool: return _colors[i].a < survivors)
				var mmi: MultiMeshInstance3D = null
				if not few.is_empty():
					var m := _bake(few, sparse)
					for j in few.size():
						_sparse_cell_of[few[j]] = m
						_index_in_sparse[few[j]] = j
					mmi = _show(m)
					mmi.visible = false
					mmi.layers = Quality.LADDER_LAYER
				_sparse_cells.append(mmi)
		for p: Patch in _patches.values():
			p.mmi.free()
		_patches = {}
		capacity -= kept
		_count = 0
		_patch_of.fill(null)

	func _bake(slots: Array, drawn: Mesh) -> MultiMesh:
		var m := MultiMesh.new()
		_setup(m, drawn, slots.size())
		var box: AABB = plants[slots[0]].xform * mesh.get_aabb()
		for j in slots.size():
			var i: int = slots[j]
			m.set_instance_transform(j, _drawn_as(plants[i].xform, plants[i].rock))
			m.set_instance_color(j, _colors[i])
			m.set_instance_custom_data(j, _customs[i])
			box = box.merge(plants[i].xform * mesh.get_aabb())
		# Heights are kept above the ground, which the shaders add; wind and hands bend blades a little further.
		var ground := terrain.bounds()
		box.position.y += ground.position.y
		box.size.y += ground.size.y
		terrain.lift(m, box.grow(0.5))
		return m

	## What draws the painted plants.
	func patches() -> Array[MultiMeshInstance3D]:
		var out: Array[MultiMeshInstance3D] = []
		for p: Patch in _patches.values():
			out.append(p.mmi)
		return out

	func size() -> int:
		return kept + _count

	## Back to the kept plants; plants remembered from the rest no longer find their slots.
	func reset() -> void:
		for i in range(kept, size()):
			if indexed:
				_unindex(i)
			plants[i] = null
			stamps[i] += 1
		for p: Patch in _patches.values():
			p.slots.clear()
			p.mm.visible_instance_count = 0
			p.mmi.visible = false
		_patch_of.fill(null)
		_count = 0
		if far != null:
			far.visible_instance_count = kept
		if cover != null:
			cover.touch_all()
		_next = 0

	func place(slot: int, xform: Transform3D) -> void:
		xform = _drawn_as(xform, plants[slot].rock)
		if slot < kept:
			_cell_of[slot].set_instance_transform(_index_in_cell[slot], xform)
			if _sparse_cell_of[slot] != null:
				_sparse_cell_of[slot].set_instance_transform(_index_in_sparse[slot], xform)
		else:
			_unpatch(slot - kept)
			_xforms[slot] = xform
			_patch(slot - kept)
		if far != null:
			far.set_instance_transform(slot, xform)
		if cover != null:
			cover.touch(plants[slot].anchor)

	## Moves a plant to `xform` (its height counted as `add` takes it) in `color`, where it stands or not.
	func repose(p: Plant, xform: Transform3D, color: Color) -> void:
		if not p.current():
			return
		xform.origin.y -= terrain.height_at(p.anchor.x, p.anchor.z)
		p.xform = xform
		anchored += 1
		if p.shown():
			place(p.slot, xform)
		if p.slot < kept:
			_cell_of[p.slot].set_instance_color(_index_in_cell[p.slot], color)
			_cover_cell(p.slot)
		else:
			_colors[p.slot] = color
			_write(_patch_of[p.slot - kept], _index_in_patch[p.slot - kept], p.slot)
		if far != null:
			far.set_instance_color(p.slot, color)

	## Moves a plant `by` across the ground, its anchor with it, drawn with `custom` (as `add` takes it). Its height
	## above the ground stays, so it stands on the ground where it now is.
	func shift(p: Plant, by: Vector3, custom: Color) -> void:
		if not p.current():
			return
		if indexed:
			_unindex(p.slot)
		if cover != null:
			cover.touch(p.anchor)
		p.anchor += by
		p.xform.origin += by
		p.rock = soil and terrain.rock_at(p.anchor.x, p.anchor.z)
		if anchors[p.slot] != GONE:
			anchors[p.slot] = p.anchor
		anchored += 1
		if indexed:
			_grid.get_or_add(square(p.anchor), []).append(p.slot)
		set_custom(p.slot, Color(custom.r, custom.g, p.anchor.x, p.anchor.z))
		if p.drawn:
			place(p.slot, p.xform)
		if p.slot < kept:
			_cover_cell(p.slot)

	## Turns a plant `by` radians about the vertical through `about`, across the ground.
	func spin(p: Plant, about: Vector3, by: float) -> void:
		if not p.current():
			return
		var r := Basis(Vector3.UP, by)
		var o := Vector3(about.x, p.xform.origin.y, about.z)
		p.xform = Transform3D(r * p.xform.basis, o + r * (p.xform.origin - o))
		if p.drawn:
			place(p.slot, p.xform)
		if p.slot < kept:
			_cover_cell(p.slot)

	## Finds again which of its plants standing in `area` across the ground are on rock, as the ground now lies.
	func reground(area: Rect2) -> void:
		if not soil:
			return
		var slots: Array = range(size())
		if indexed:
			slots = []
			var lo := square(Vector3(area.position.x, 0, area.position.y))
			var hi := square(Vector3(area.end.x, 0, area.end.y))
			for j in range(lo.y, hi.y + 1):
				for i in range(lo.x, hi.x + 1):
					slots.append_array(_grid.get(Vector2i(i, j), []))
		for slot: int in slots:
			var p := plants[slot]
			if p == null or not area.has_point(Vector2(p.anchor.x, p.anchor.z)):
				continue
			var rock := terrain.rock_at(p.anchor.x, p.anchor.z)
			if rock != p.rock:
				p.rock = rock
				if p.drawn:
					place(slot, p.xform)

	static func _drawn_as(xform: Transform3D, rock: bool) -> Transform3D:
		return Transform3D(Basis.from_scale(Vector3.ZERO), xform.origin) if rock else xform

	func set_custom(slot: int, custom: Color) -> void:
		if slot < kept:
			_cell_of[slot].set_instance_custom_data(_index_in_cell[slot], custom)
			if _sparse_cell_of[slot] != null:
				_sparse_cell_of[slot].set_instance_custom_data(_index_in_sparse[slot], custom)
		else:
			_customs[slot] = custom
			_write(_patch_of[slot - kept], _index_in_patch[slot - kept], slot)
		if far != null:
			far.set_instance_custom_data(slot, custom)

	## Widens a kept plant's cell box to take it in as it now stands, so the camera does not cull it.
	func _cover_cell(slot: int) -> void:
		var cell := _cell_of[slot]
		var ground := terrain.bounds()
		var box := plants[slot].xform * mesh.get_aabb()
		box.position.y += ground.position.y
		box.size.y += ground.size.y
		cell.custom_aabb = cell.custom_aabb.merge(box.grow(0.5))

	func draw_with(m: Mesh) -> void:
		drawn = m
		for c in _cells:
			c.multimesh.mesh = m
		for p: Patch in _patches.values():
			p.mm.mesh = m

	## Not `visibility_range_end`: that measures to the box's centre, which sits high above the ground because a
	## cell's box spans every height the terrain can be pulled to. A cell out of reach stays for a photo. Patches reach
	## `painted_reach`: a painted flower may be an iris or a lily, drawn further than the meadow's land flowers.
	func cull(eye: Vector3, reach: float, painted_reach := reach) -> void:
		var half := Vector2(cell, cell) * 0.5
		for i in _cells.size():
			var off := (_centres[i] - Vector2(eye.x, eye.z)).abs() - half
			var d := Vector2(maxf(off.x, 0.0), maxf(off.y, 0.0)).length()
			var layers := 1 if d < minf(sparse_from, reach) else Quality.FULL_LAYER
			if layers != _cell_layers[i]:
				_cell_layers[i] = layers
				_cells[i].layers = layers
			if sparse != null and _sparse_cells[i] != null:
				_sparse_cells[i].visible = d >= sparse_from and d < reach
		for p: Patch in _patches.values():
			var lo := Vector2(p.box.position.x, p.box.position.z) - Vector2(eye.x, eye.z)
			var hi := Vector2(p.box.end.x, p.box.end.z) - Vector2(eye.x, eye.z)
			var gap := Vector2(maxf(maxf(lo.x, -hi.x), 0.0), maxf(maxf(lo.y, -hi.y), 0.0))
			var layers := 1 if gap.length() < painted_reach else Quality.FULL_LAYER
			if layers != p.layers:
				p.layers = layers
				p.mmi.layers = layers

	func _setup(m: MultiMesh, drawn: Mesh, count: int) -> void:
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = true
		m.use_custom_data = true
		m.mesh = drawn
		m.instance_count = count

	## The distant layer is one draw per pool. Keeping it whole costs fewer draws than pairing every near cell.
	func far_with(mat: ShaderMaterial) -> void:
		far = MultiMesh.new()
		_setup(far, Flora.far_mesh(), capacity)
		far.visible_instance_count = 0
		terrain.lift(far, terrain.bounds())
		far_live = _show(far)
		far_live.material_override = mat
		far_live.layers = Quality.LADDER_LAYER

	func _show(m: MultiMesh) -> MultiMeshInstance3D:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = m
		mmi.material_override = material
		if not _shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parent.add_child(mmi)
		return mmi


## The painted plants of one pool standing in one `cell` square: `slots` in the order `mm` draws them. Its capacity
## doubles when it fills, so painting rarely resizes a GPU buffer and an unpainted square costs none.
class Patch:
	const FIRST := 64
	var key: Vector2i
	var mm: MultiMesh
	var mmi: MultiMeshInstance3D
	var slots := PackedInt32Array()
	## The layers `Pool.cull` last gave `mmi`.
	var layers := 1
	## Around the plants it has drawn since it was last empty, through every height the ground can reach, so the
	## camera culls a patch by where its plants stand rather than by its whole square.
	var box: AABB


## A tree or bush, as what the delete tool's beam strikes: its parts (a tree's trunk then its blobs), and the
## circle across the ground that holds them, so a beam is tested against their boxes only when it passes over it.
## A tree also keeps the seed its shape is drawn from, its species and its scale; a bush's species is -1.
class Solid:
	var parts: Array[Plant]
	var centre: Vector2
	var radius: float
	var seed := 0
	var species := -1
	var scale := 1.0
	var moss := false
	## How far it is turned about its foot from how it grew, in radians.
	var turn := 0.0
	## Where its first part's anchor stood as it grew.
	var home: Vector3
	## Its shade blob's instance in `crown_shade` as last fitted, or -1 for none.
	var shade := -1

	func _init(p: Array[Plant]) -> void:
		parts = p
		home = p[0].anchor
		fit()

	func fit() -> void:
		var box: AABB = parts[0].xform * parts[0].pool.mesh.get_aabb()
		for part in parts:
			box = box.merge(part.xform * part.pool.mesh.get_aabb())
		centre = Vector2(box.get_center().x, box.get_center().z)
		radius = Vector2(box.size.x, box.size.z).length() * 0.5


## One instance in a pool, remembered so it can be taken out and put back.
class Plant:
	var pool: Pool
	var slot: int
	var stamp: int
	var xform: Transform3D
	## Where it stands, its height counted from the ground under it as `xform`'s is.
	var anchor: Vector3
	## Where build commands find it: its group (0 is the meadow's own, else the command that grew it)
	## and its place in that group.
	var group := -1
	var index := -1
	var drawn := true
	## On rock its pool's soil does not reach, so not drawn, though it stands.
	var rock := false

	func _init(p: Pool, i: int, x: Transform3D, a: Vector3) -> void:
		pool = p
		slot = i
		stamp = p.stamps[i]
		xform = x
		anchor = a

	func current() -> bool:
		return pool.stamps[slot] == stamp

	## Where it stands on the ground as the ground now lies.
	func foot() -> Vector3:
		return anchor + Vector3.UP * pool.terrain.height_at(anchor.x, anchor.z)

	func shown() -> bool:
		return current() and pool.anchors[slot] != Pool.GONE

	func set_shown(on: bool) -> void:
		if not current():
			return
		draw(on)
		pool.anchors[slot] = anchor if on else Pool.GONE
		pool.anchored += 1

	## Draws it standing or not without changing whether it stands, for a tool's preview.
	func draw(on: bool) -> void:
		if current():
			drawn = on
			pool.draws += 1
			pool.place(slot, xform if on else Transform3D(Basis.from_scale(Vector3.ZERO), xform.origin))


var moss: Pool
var ghost_moss: Pool
var grass: Pool
var grass_mat := ShaderMaterial.new()
var flowers: Pool
var trunks: Pool
var foliage: Pool
var bushes: Pool
## The sun's shade of every standing tree and bush, cast by one coarse blob fitted to its crown instead of by each
## blob: the shadow pass draws one low-detail mesh a crown, and the blobs no longer shade one another in patches.
var crown_shade := MultiMesh.new()
var _shaded := -1
## Every tree and bush, meadow's own and planted, by its first part's pool and slot.
var _solids := {}
var _kept_solids := {}
## The meadow never changes once kept, so which of its plants are which is worked out then, not on every wipe.
var _meadow_trees := PackedInt32Array()
var _meadow_bushes := PackedInt32Array()
var _meadow_scenery := PackedInt32Array()
## The keys of the solids whose circles reach into each SOLID_CELL square, so a beam tests only those it passes
## over; a key may linger where its slot's earlier tree stood.
var _solid_cells := {}
## Every plant a build command can name, by group, in the order its command grew them.
var groups := {}
## Committed strokes still growing, oldest first. Their spots were fixed as their commands applied, and any
## command on their plants or the ground's heights grows them first, so every machine fills its pools alike.
var _growing: Array[Growth] = []
## A player's own stroke while it is painted and until its build command comes back, drawn apart from the
## garden's plants so that those fill their pools in command order on every machine.
var ghost_grass: Pool
var ghost_flowers: Pool
## How far from the eye grass is drawn, as Quality steps it; sub-pixel blades beyond it cost the Quest 2 most of its frame.
var grass_reach: float = Quality.ladder[0].grass_m:
	set(m):
		grass_reach = m
		grass_mat.set_shader_parameter(&"draw_reach", m)
		if ground_mat != null:
			ground_mat.set_shader_parameter(&"draw_reach", m)
## The quality reach still controls aquatic flowers; land meshes hand off to patches by FLOWER_NEAR.
var flower_reach: float = Quality.ladder[0].flowers_m:
	set(m):
		flower_reach = m
		flower_mat.set_shader_parameter(&"draw_reach", minf(m, FLOWER_NEAR))
		flower_mat.set_shader_parameter(&"water_reach", m)
		if flower_far != null:
			flower_far.set_shader_parameter(&"draw_reach", minf(m, FLOWER_NEAR))
## Which of `_blobs` the foliage is drawn with, as Quality steps it.
var blob_detail: int = Quality.ladder[0].blob_detail:
	set(n):
		if n != blob_detail:
			blob_detail = n
			foliage.draw_with(_blobs[n])
			bushes.draw_with(_blobs[n])
var flower_mat: ShaderMaterial
var flower_far: ShaderMaterial
## The meadow's ground, which paints the grass past its clumps' reach (FloraCover).
var ground_mat: ShaderMaterial
static var _far_mesh: ArrayMesh
## Bumped whenever a tree or bush stands up or goes, so what was gathered from them knows it is stale.
var changes := 0
## Foliage blobs at each detail, made up front so a step changes only which one is drawn.
var _blobs := {}
var terrain: Terrain
var marks: Ground


func _init(ground: Terrain, laid: Ground) -> void:
	terrain = ground
	marks = laid
	grass_mat.shader = load("res://src/grass.gdshader")
	for k in Meadow.GRASS:
		grass_mat.set_shader_parameter(k, Meadow.GRASS[k])
	_grass_lod(grass_mat)
	part(NO_HAND, NO_HAND)
	var clump := Meshes.grass_clump(CLUMP_BLADES, 1, 3, false, CLUMP_WIDE)
	var bloom := Meshes.flower(PETALS, Color.WHITE, true)
	grass = Pool.new(self, clump, Meadow.GRASS_CLUMPS + PAINTED_GRASS, grass_mat, false, GRASS_CELL)
	grass.sparse = Meshes.grass_clump(CLUMP_BLADES, 1, 3, true, CLUMP_WIDE)
	grass.survivors = GRASS_SURVIVORS
	grass.sparse_from = GRASS_LOD_BEGIN + GRASS_LOD_BAND
	flower_mat = _plant_material("flower", 0.8)
	flower_mat.set_shader_parameter("stalk", Meshes.STALK)
	flower_mat.set_shader_parameter("eye", Meshes.EYE)
	flower_mat.set_shader_parameter(&"stem", Meshes.FLOWER_HEIGHT)
	flower_mat.set_shader_parameter(&"leaf_shoulder", Meshes.LEAF_SHOULDER)
	flower_mat.set_shader_parameter(&"draw_reach", minf(flower_reach, FLOWER_NEAR))
	flower_mat.set_shader_parameter(&"water_reach", flower_reach)
	Quality.full_detail(flower_mat)
	flowers = Pool.new(self, bloom, Meadow.FLOWERS + PAINTED_FLOWERS, flower_mat, false)
	flowers.kept_mesh = Meshes.flower(PETALS)
	grass.indexed = true
	flowers.indexed = true
	ghost_grass = Pool.new(self, clump, Commands.MAX_STROKE * 2, grass_mat, false)
	ghost_flowers = Pool.new(self, bloom, Commands.MAX_STROKE * 2, flower_mat, false)
	for pool in [grass, flowers, ghost_grass, ghost_flowers]:
		pool.soil = true
	grass.cover = FloraCover.new(grass.plants.size())
	flower_far = _far_material()
	for pool in [flowers, ghost_flowers]:
		pool.far_with(flower_far)
	for pool in [grass, ghost_grass, flowers, ghost_flowers]:
		pool.planted = 1.0
	var moss_mat := ShaderMaterial.new()
	moss_mat.shader = load("res://src/moss.gdshader")
	moss = Pool.new(self, Meshes.moss(), PAINTED_MOSS, moss_mat, false)
	moss.indexed = true
	ghost_moss = Pool.new(self, moss.mesh, PAINTED_MOSS, moss_mat, false)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.3
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1
	trunks = Pool.new(self, trunk, Meadow.TREES + PLACED_TREES, _plant_material("plant", 1.0), true, SOLID_POOL_CELL)
	var leaf_mat := _plant_material("leaf", 1.0)
	leaf_mat.set_shader_parameter("backlight", Color(0.25, 0.35, 0.08))
	leaf_mat.set_shader_parameter("crown_lump", Meshes.BLOB_LUMP)
	for step in Quality.ladder:
		_blobs.get_or_add(step.blob_detail, Meshes.blob(4, step.blob_detail))
	foliage = Pool.new(self, _blobs[blob_detail], (Meadow.TREES + PLACED_TREES) * FloraLayout.BLOBS, leaf_mat, false, SOLID_POOL_CELL)
	bushes = Pool.new(self, _blobs[blob_detail], Meadow.BUSHES + PLACED_BUSHES, leaf_mat, false, SOLID_POOL_CELL)
	crown_shade.transform_format = MultiMesh.TRANSFORM_3D
	crown_shade.use_colors = true
	crown_shade.use_custom_data = true
	crown_shade.mesh = Meshes.blob(4, 1)
	crown_shade.instance_count = Meadow.TREES + PLACED_TREES + Meadow.BUSHES + PLACED_BUSHES
	crown_shade.custom_aabb = terrain.bounds()
	var shade := MultiMeshInstance3D.new()
	shade.multimesh = crown_shade
	shade.material_override = leaf_mat
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(shade)


## A far flower: one triangle facing the eye.
static func far_mesh() -> ArrayMesh:
	if _far_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in [Vector3(-0.5, 0, 0), Vector3(0, 0.5, 0), Vector3(0.5, 0, 0)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
		st.index()
		_far_mesh = st.commit()
	return _far_mesh


func _far_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/flora_far.gdshader")
	mat.set_shader_parameter(&"stem", Meshes.FLOWER_HEIGHT)
	mat.set_shader_parameter(&"draw_reach", minf(flower_reach, FLOWER_NEAR))
	return mat


## Has the ground `mat` paint the grass where its clumps have sunk away.
func paint_ground(mat: ShaderMaterial) -> void:
	ground_mat = mat
	_grass_lod(mat)


## Gives `mat` the grass's reach and LOD band (flora_lod.gdshaderinc), so the ground paints the grass where it sinks.
func _grass_lod(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"draw_reach", grass_reach)
	mat.set_shader_parameter(&"lod_begin", GRASS_LOD_BEGIN)
	mat.set_shader_parameter(&"lod_band", GRASS_LOD_BAND)
	mat.set_shader_parameter(&"survivors", GRASS_SURVIVORS)
	mat.set_shader_parameter(&"survivors_from", GRASS_SURVIVORS_FROM)
	Quality.full_detail(mat)


static func _plant_material(shader: String, roughness: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/%s.gdshader" % shader)
	mat.set_shader_parameter("roughness", roughness)
	return mat


func _process(_delta: float) -> void:
	_grow(GROW_USEC)
	_shade_crowns()
	grass.cover.settle(grass)
	var eye := get_viewport().get_camera_3d()
	if eye != null:
		grass.cull(eye.global_position, grass_reach)
		flowers.cull(eye.global_position, minf(flower_reach, FLOWER_NEAR), flower_reach)


## Fits a shade blob to each standing crown's blobs when any tree or bush has changed or been drawn otherwise.
func _shade_crowns() -> void:
	var seen := _shade_seen()
	if seen == _shaded:
		return
	_shaded = seen
	var n := 0
	for solid: Solid in _solids.values():
		var first := solid.parts[0]
		solid.shade = -1
		if not first.shown() or not first.drawn or n == crown_shade.instance_count:
			continue
		solid.shade = n
		crown_shade.set_instance_transform(n, shade_of(solid.parts))
		crown_shade.set_instance_custom_data(n, Color(0, 0, first.anchor.x, first.anchor.z))
		n += 1
	crown_shade.visible_instance_count = n


func _shade_seen() -> int:
	return changes + trunks.draws + foliage.draws + bushes.draws


## Where the shade blob of a tree or bush (its parts) stands, fitted to the box around its blobs.
func shade_of(parts: Array) -> Transform3D:
	var blobs: Array = parts.slice(1) if parts[0].pool == trunks else parts
	var box: AABB = blobs[0].xform * foliage.mesh.get_aabb()
	for b: Plant in blobs:
		box = box.merge(b.xform * foliage.mesh.get_aabb())
	return Transform3D(Basis.from_scale(box.size * SHADE_FIT / crown_shade.mesh.get_aabb().size), box.get_center())


## Moves grass and flower reach toward `step`'s (Quality.reach) and draws its blobs; whether both reaches are
## there, since a step still under way is not yet the step's cost.
func approach(step: Quality.Step, delta: float) -> bool:
	var grass_m := Quality.reach(grass_reach, step.grass_m, delta)
	if grass_m != grass_reach:
		grass_reach = grass_m
	var flowers_m := Quality.reach(flower_reach, step.flowers_m, delta)
	if flowers_m != flower_reach:
		flower_reach = flowers_m
	blob_detail = step.blob_detail
	return grass_reach == step.grass_m and flower_reach == step.flowers_m


## The ground under `area` moved (GroundGrab.reshaped): grass and flowers there that now stand on rock go, and those
## the ground gives soil again come back. A stroke's live hump moves no heights, so only a settled one is read; a
## plant is found again the moment it is added or moved, so the GPU never tests it a frame.
func reground(area: Rect2, settled: bool) -> void:
	if not settled:
		return
	area = area.grow(Terrain.STEP * 2.0)
	for pool in [grass, flowers, ghost_grass, ghost_flowers]:
		pool.reground(area)


func part(left: Vector3, right: Vector3) -> void:
	grass_mat.set_shader_parameter(&"hand_left", left)
	grass_mat.set_shader_parameter(&"hand_right", right)


func add_grass(p: Vector3, rng: RandomNumberGenerator, pool := grass) -> Plant:
	var v := rng.randf_range(0.85, 1.1)
	var c := FloraLayout.clump(p, FloraLayout.GRASS_CLUMP)
	return pool.add(FloraLayout.grass(p, c, rng), Color(v, v, v, FloraLayout.thin_rank(p)), p, Color(FloraLayout.dryness(p), FloraLayout.clump_trait(c, FloraLayout.Trait.TINT, FloraLayout.GRASS_CLUMP), 0, 0))


func add_flower(p: Vector3, rng: RandomNumberGenerator, pool := flowers) -> Plant:
	return pool.add(FloraLayout.flower(p, rng), FloraLayout.flower_color(p), p, Color(FloraLayout.bloom_rank(p), 0, 0, 0))


## A tree of `species` at `at`, its shape drawn from `seed`.
func add_tree(at: Vector3, seed: int, species := FloraLayout.Species.OAK) -> Array[Plant]:
	var t := FloraLayout.tree(at, seed, species)
	var parts: Array[Plant] = []
	var trunk := trunks.add(t.trunk, t.bark, at)
	if trunk == null:
		return parts
	parts.append(trunk)
	for b in t.blobs:
		var blob := foliage.add(b[0], b[1], at)
		if blob != null:
			parts.append(blob)
	var solid := _solid(Vector2i(0, trunk.slot), parts)
	solid.seed = seed
	solid.species = species
	return parts


## The species of the tree whose trunk is `trunk`, or -1 for none standing in its slot.
func species_of(trunk: Plant) -> int:
	var solid: Solid = _solids.get(Vector2i(0, trunk.slot))
	return solid.species if trunk.pool == trunks and trunk.current() and solid != null and solid.parts[0] == trunk else -1


## The scale of the tree whose trunk is `trunk`, or 0 for none standing in its slot.
func scale_of(trunk: Plant) -> float:
	return _solids[Vector2i(0, trunk.slot)].scale if species_of(trunk) >= 0 else 0.0


## How high over the ground the tree whose trunk is `trunk` reaches.
func top_of(trunk: Plant) -> float:
	var top := 0.0
	for p in _solids[Vector2i(0, trunk.slot)].parts:
		top = maxf(top, (p.xform * p.pool.mesh.get_aabb()).end.y)
	return top


## Grows the tree whose trunk is `trunk` again as `species` at `scale`, from its own seed, in the slots it holds.
func set_look(trunk: Plant, species: FloraLayout.Species, scale: float) -> void:
	var was := species_of(trunk)
	if was < 0 or was == species and is_equal_approx(scale_of(trunk), scale):
		return
	var key := Vector2i(0, trunk.slot)
	var solid: Solid = _solids[key]
	var t := FloraLayout.tree(trunk.foot(), solid.seed, species, scale)
	trunks.repose(trunk, t.trunk, t.bark)
	for i in mini(t.blobs.size(), solid.parts.size() - 1):
		foliage.repose(solid.parts[i + 1], t.blobs[i][0], t.blobs[i][1])
	solid.species = species
	solid.scale = scale
	var yaw := solid.turn
	solid.turn = 0.0
	_spin(solid, yaw)
	solid.fit()
	changes += 1
	_index(key, solid)


## Moves the tree or bush whose first part is `first` to stand at `at` across the ground, as though it had grown
## there: its parts keep their shape and their heights above the ground, so nothing grows again.
func move(first: Plant, at: Vector3) -> void:
	var key := _key_of(first)
	var solid: Solid = _solids.get(key)
	if solid == null or solid.parts[0] != first or not first.current():
		return
	var by := Vector3(at.x - first.anchor.x, 0.0, at.z - first.anchor.z)
	if by.is_zero_approx():
		return
	var synced := _shade_seen() == _shaded
	for p in solid.parts:
		p.pool.shift(p, by, Color(1.0 if solid.moss and p.pool == trunks else 0.0, 0, 0, 0))
	_refit(key, solid, synced)


## Turns the tree or bush whose first part is `first` to `yaw` radians about its foot from how it grew.
func turn_to(first: Plant, yaw: float) -> void:
	var key := _key_of(first)
	var solid: Solid = _solids.get(key)
	if solid == null or solid.parts[0] != first or not first.current() or is_equal_approx(yaw, solid.turn):
		return
	var synced := _shade_seen() == _shaded
	_spin(solid, yaw - solid.turn)
	_refit(key, solid, synced)


## How far the tree or bush whose first part is `first` is turned from how it grew.
func turn_of(first: Plant) -> float:
	return _solids[_key_of(first)].turn


func _spin(solid: Solid, by: float) -> void:
	var about := solid.parts[0].anchor
	for p in solid.parts:
		p.pool.spin(p, about, by)
	solid.turn += by


## Fits `solid` again after it moved. A carried tree moves every frame: only its own shade is fitted again, not every
## crown's.
func _refit(key: Vector2i, solid: Solid, synced: bool) -> void:
	solid.fit()
	_index(key, solid)
	changes += 1
	if synced:
		_shaded = _shade_seen()
		if solid.shade >= 0:
			var first := solid.parts[0]
			crown_shade.set_instance_transform(solid.shade, shade_of(solid.parts))
			crown_shade.set_instance_custom_data(solid.shade, Color(0, 0, first.anchor.x, first.anchor.z))


## Where the tree or bush whose first part is `first` stood as it grew, across the ground.
func home_of(first: Plant) -> Vector3:
	return _solids[_key_of(first)].home


func _key_of(first: Plant) -> Vector2i:
	return Vector2i(0 if first.pool == trunks else 1, first.slot)


func add_bush(at: Vector3, rng: RandomNumberGenerator) -> Array[Plant]:
	var b := FloraLayout.bush(at, rng)
	var parts: Array[Plant] = []
	var blob := bushes.add(b[0], b[1], at)
	if blob != null:
		parts.append(blob)
		_solid(Vector2i(1, blob.slot), parts)
	return parts


func _solid(key: Vector2i, parts: Array[Plant]) -> Solid:
	changes += 1
	var solid := Solid.new(parts)
	_solids[key] = solid
	_index(key, solid)
	return solid


func _index(key: Vector2i, solid: Solid) -> void:
	for j in range(floori((solid.centre.y - solid.radius) / SOLID_CELL), floori((solid.centre.y + solid.radius) / SOLID_CELL) + 1):
		for i in range(floori((solid.centre.x - solid.radius) / SOLID_CELL), floori((solid.centre.x + solid.radius) / SOLID_CELL) + 1):
			_solid_cells.get_or_add(Vector2i(i, j), {})[key] = true


## What a plant counts as in the build budget (Budget.UNITS): a tree by its trunk, and nothing for its blobs.
func unit_of(p: Plant) -> String:
	return {grass: "grass", flowers: "flower", trunks: "tree", bushes: "bush", moss: "moss"}.get(p.pool, "")


## The plants so far are the meadow's own: group 0, which every machine grows alike.
func keep() -> void:
	var meadow: Array[Plant] = []
	for p: Pool in [grass, flowers, trunks, foliage, bushes, moss]:
		meadow.append_array(p.plants.slice(0, p.size()))
		p.keep()
	_name(0, meadow)
	_kept_solids = _solids.duplicate()
	_meadow_trees = _meadow_where(func(p: Plant) -> bool: return p.pool == trunks)
	_meadow_bushes = _meadow_where(func(p: Plant) -> bool: return p.pool == bushes)
	_meadow_scenery = _meadow_where(func(p: Plant) -> bool: return p.pool != grass)


## Where the meadow's own trees' trunks stand in its group.
func meadow_trees() -> PackedInt32Array:
	return _meadow_trees


func meadow_bushes() -> PackedInt32Array:
	return _meadow_bushes


## The meadow's own flowers, bushes and trees: all of it but its grass.
func meadow_scenery() -> PackedInt32Array:
	return _meadow_scenery


func _meadow_where(take: Callable) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p: Plant in groups[0]:
		if take.call(p):
			out.append(p.index)
	return out


func _name(group: int, plants: Array[Plant]) -> void:
	for i in plants.size():
		if plants[i] != null:
			plants[i].group = group
			plants[i].index = i
	groups[group] = plants


## Whether a painted plant would land on bare ground (a path or stone) in the garden, where it would be
## parted to nothing yet take a slot.
func on_path(p: Vector3) -> bool:
	return marks.laid_bare(p.x, p.z) > 0.9


## One dab of a brush into the ghost pools: `count` plants of `kind` spread over a disc, none on bare ground,
## placed by `rng` and drawn by `look`, the two streams `grow` grows its plants from.
func dab(kind: String, center: Vector3, radius: float, count: int, rng: RandomNumberGenerator, look: RandomNumberGenerator) -> Array[Plant]:
	var out: Array[Plant] = []
	for p in FloraLayout.brush(center, radius, count, rng, terrain.height_at):
		out.append(null if kind != "moss" and marks.bare(p.x, p.z) > 0.9 else _paint(kind, p, look, true))
	return out


func add_moss(p: Vector3, rng: RandomNumberGenerator, pool: Pool = null) -> Plant:
	var size := rng.randf_range(0.65, 1.1)
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
	return (moss if pool == null else pool).add(Transform3D(basis, p), Color(0.055, 0.13, 0.015) * rng.randf_range(0.8, 1.3), p)


func set_moss(trunk: Plant, on: bool) -> void:
	if species_of(trunk) < 0:
		return
	_solids[Vector2i(0, trunk.slot)].moss = on
	trunks.set_custom(trunk.slot, Color(1.0 if on else 0.0, 0, trunk.anchor.x, trunk.anchor.z))


func _paint(kind: String, p: Vector3, rng: RandomNumberGenerator, ghost: bool) -> Plant:
	if kind == "moss":
		return add_moss(p, rng, ghost_moss if ghost else moss)
	if kind == "grass":
		return add_grass(p, rng, ghost_grass if ghost else grass)
	return add_flower(p, rng, ghost_flowers if ghost else flowers)


## Grows a group from its build command: a seeded paint stroke, which grows exactly the plants its
## author's ghost showed, or a placed tree or bush. A stroke records in `skip` the plants that fell on bare ground when it
## grew, so a garden rebuilt later grows the same plants whatever paths and stone stand by then.
## A stroke's plants are null until they grow, over the frames that follow (see `grow_now`), each on the ground as
## it is then.
func grow(id: int, g: Dictionary) -> Array[Plant]:
	var plants: Array[Plant] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = g.seed
	if g.kind in PLACED:
		var at := Vector3(g.at.x, terrain.height_at(g.at.x, g.at.z), g.at.z)
		plants = add_tree(at, g.seed) if g.kind == "tree" else add_bush(at, rng)
		_name(id, plants)
		return plants
	var growth := Growth.new()
	growth.group = id
	growth.kind = g.kind
	growth.looks = looks(g.seed)
	var record := not g.has("skip")
	var skip := {}
	for i in g.get("skip", []):
		skip[i] = true
	var skipped := PackedInt32Array()
	var laid := marks.laid_image() if record and g.kind != "moss" else null
	for d in g.dabs:
		for p in FloraLayout.brush(d[0], d[1], d[2], rng, _level):
			if skip.has(growth.spots.size()) or laid != null and Ground.bare_in(laid, p.x, p.z) > 0.9:
				skipped.append(growth.spots.size())
				growth.spots.append(null)
			else:
				growth.spots.append(p)
	g.skip = skipped
	plants.resize(growth.spots.size())
	groups[id] = plants
	_growing.append(growth)
	return plants


## Where a stroke seeded `seed` draws its plants' looks from, apart from their spots, so the spots can be
## fixed before the plants grow.
static func looks(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x1007
	return rng


## A committed stroke growing: its plants' spots (null where one fell on bare ground) and how many have grown.
class Growth:
	var group: int
	var kind: String
	var spots: Array = []
	var looks: RandomNumberGenerator
	var next := 0


static func _level(_x: float, _z: float) -> float:
	return 0.0


## Grows every committed stroke now.
func grow_now() -> void:
	_grow(-1)


func growing() -> bool:
	return not _growing.is_empty()


## Grows the oldest strokes' plants for about `usec` microseconds of `clock`, or all of them for a negative `usec`.
func _grow(usec: int, clock := Time.get_ticks_usec) -> void:
	if _growing.is_empty():
		return
	var start: int = clock.call()
	while not _growing.is_empty():
		var g := _growing[0]
		while g.next < g.spots.size():
			var spot: Variant = g.spots[g.next]
			if spot != null:
				var p := _paint(g.kind, Vector3(spot.x, terrain.height_at(spot.x, spot.z) - FloraLayout.SINK, spot.z), g.looks, false)
				if p != null:
					p.group = g.group
					p.index = g.next
				groups[g.group][g.next] = p
			g.next += 1
			if usec >= 0 and clock.call() - start > usec:
				return
		_growing.pop_front()
	grown.emit()


func clear_ghosts() -> void:
	ghost_grass.reset()
	ghost_flowers.reset()
	ghost_moss.reset()


## Shows or hides the plants at `indices` of a group; returns the indices that changed.
func set_shown(group: int, indices: PackedInt32Array, on: bool) -> PackedInt32Array:
	grow_now()
	changes += 1
	var changed := PackedInt32Array()
	var plants: Array = groups.get(group, [])
	for i in indices:
		var p: Plant = plants[i] if i >= 0 and i < plants.size() else null
		if p != null and p.current() and p.shown() != on:
			p.set_shown(on)
			changed.append(i)
	return changed


## Back to the meadow alone, every one of its plants standing. Ghosts stay with the strokes still on their way.
func reset() -> void:
	changes += 1
	if growing():
		_growing.clear()
		grown.emit()
	for p: Pool in [grass, flowers, trunks, foliage, bushes, moss]:
		p.reset()
		# Only the taken are stood again, found natively: visiting each of the meadow's tens of thousands of plants
		# in script held a Quest's frame for hundreds of milliseconds. A plant a tool shows taken is the tool's to
		# draw again once its command settles.
		var at := p.anchors.find(Pool.GONE)
		while at >= 0 and at < p.kept:
			p.plants[at].set_shown(true)
			at = p.anchors.find(Pool.GONE, at + 1)
	groups = {0: groups[0]}
	for i in _meadow_trees:
		set_moss(groups[0][i], false)
	_solids = _kept_solids.duplicate()
	_solid_cells.clear()
	for key: Vector2i in _solids:
		var solid: Solid = _solids[key]
		move(solid.parts[0], solid.home)
		turn_to(solid.parts[0], 0.0)
		if solid.species > FloraLayout.Species.OAK or solid.scale != 1.0:
			set_look(solid.parts[0], FloraLayout.Species.OAK, 1.0)
		_index(key, solid)


## The standing tree or bush a ray from `origin` along `dir` strikes first within `reach`: its parts, where it
## strikes, how far along `dir` and whether on a side, or {} for none. Each part is struck within its mesh's box, set on the ground as
## its shader sets it. Solids whose parts are keys of `skip` let the ray through.
func solid_hit(origin: Vector3, dir: Vector3, reach: float, skip := {}) -> Dictionary:
	var best := {}
	var best_t := reach
	var dx := dir.x * reach
	var dz := dir.z * reach
	var span := maxf(dx * dx + dz * dz, 1e-9)
	var keys := {}
	var steps := ceili(sqrt(span) / (SOLID_CELL * 0.25))
	for k in steps + 1:
		var at := Vector2i(floori((origin.x + dx * k / steps) / SOLID_CELL), floori((origin.z + dz * k / steps) / SOLID_CELL))
		keys.merge(_solid_cells.get(at, {}))
	for key: Vector2i in keys:
		var solid: Solid = _solids[key]
		var cx := solid.centre.x - origin.x
		var cz := solid.centre.y - origin.z
		var u := clampf((cx * dx + cz * dz) / span, 0.0, 1.0)
		cx -= dx * u
		cz -= dz * u
		if cx * cx + cz * cz > solid.radius * solid.radius or not solid.parts[0].shown() or skip.has(solid.parts[0]):
			continue
		for part in solid.parts:
			var at := part.xform.translated(Vector3.UP * terrain.height_at(part.anchor.x, part.anchor.z))
			var inv := at.affine_inverse()
			var box := part.pool.mesh.get_aabb()
			var local: Variant = box.intersects_ray(inv * origin, inv.basis * dir)
			if local == null:
				continue
			var hit: Vector3 = at * local
			var t := (hit - origin).dot(dir)
			if t < best_t:
				best_t = t
				best = {"plants": solid.parts, "point": hit, "along": t, "side": Rig.side(inv.basis.transposed() * Rig.box_normal(box, local))}
	return best


## The standing trees and bushes whose ground circles reach into `area`, each as its parts.
func solids_in(area: Rect2) -> Array[Array]:
	var keys := {}
	for j in range(floori(area.position.y / SOLID_CELL), floori(area.end.y / SOLID_CELL) + 1):
		for i in range(floori(area.position.x / SOLID_CELL), floori(area.end.x / SOLID_CELL) + 1):
			keys.merge(_solid_cells.get(Vector2i(i, j), {}))
	var out: Array[Array] = []
	for key: Vector2i in keys:
		var solid: Solid = _solids[key]
		if solid.parts[0].shown() and area.grow(solid.radius).has_point(solid.centre):
			out.append(solid.parts)
	return out


func solids() -> Array[Array]:
	var out: Array[Array] = []
	for solid: Solid in _solids.values():
		if solid.parts[0].shown():
			out.append(solid.parts)
	return out


## The standing trees (each as its trunk then its blobs) or bushes placed in the garden; the meadow's own are left out.
func placed(kind: String) -> Array[Array]:
	var pool := trunks if kind == "tree" else bushes
	var out: Array[Array] = []
	for parts in solids():
		if parts[0].pool == pool and parts[0].slot >= pool.kept:
			out.append(parts)
	return out


## Grass and flowers standing within `radius` of `p` across the ground.
func plants_near(p: Vector3, radius: float) -> Array[Plant]:
	var out := grass.near(p, radius)
	out.append_array(flowers.near(p, radius))
	out.append_array(moss.near(p, radius))
	return out


## Where trees and bushes stand, which a wall arches over.
func obstacles() -> PackedVector3Array:
	var out := PackedVector3Array()
	for pool in [trunks, bushes]:
		for i in pool.size():
			if pool.anchors[i] != Pool.GONE:
				out.append(pool.anchors[i])
	return out


## Pools and their plants point at each other; the cycle is cut here so both are freed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for p in [grass, flowers, trunks, foliage, bushes, moss, ghost_grass, ghost_flowers, ghost_moss]:
			p.plants.clear()

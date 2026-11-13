class_name Flora
extends Node3D

## A plant's transform and anchor count height from the ground under it, which its shader adds from the terrain
## each frame, so reshaping the ground moves no instance.

const PAINTED_GRASS := 12000
## Small, so a cell turns sparse near where its clumps do.
const GRASS_CELL := 8.0
## Past GRASS_LOD_BEGIN + GRASS_LOD_BAND only the GRASS_SURVIVORS share of clumps (FloraLayout.thin_rank) is drawn;
## those sink in turn from GRASS_SURVIVORS_FROM of the reach, so the meadow thins instead of ending at a ring.
const GRASS_LOD_BEGIN := 4.0
const GRASS_LOD_BAND := 4.0
const GRASS_SURVIVORS := 0.25
const GRASS_SURVIVORS_FROM := 0.5
## Fewer, wider blades: the Quest 2 pays more for near blades' slivers than for their pixels (docs/design.md).
const CLUMP_BLADES := 3
const CLUMP_WIDE := 2.33
## Past it land flowers draw as far patches (flora_far.gdshader).
const FLOWER_NEAR := 12.0
const PETALS := 4
const PAINTED_MOSS := 256
const PAINTED_FLOWERS := 4000
const PLACED_TREES := 64
const PLACED_BUSHES := 256
## A crown's lumps and gaps do not fill the box around its blobs.
const SHADE_FIT := 0.8
const NO_HAND := Vector3(0, -1000, 0)
const BRUSHES := ["grass", "flowers", "moss"]
const PLACED := ["tree", "bush"]
const SOLID_CELL := 8.0
## One MultiMesh per pool: a Quest 2 draw costs 7 to 19 µs, more than its triangles off screen (docs/design.md).
const SOLID_POOL_CELL := INF

signal grown


## Slots filled before `keep()` are the meadow's own, baked per `cell` and never recycled; later slots replace the
## oldest once `capacity` fills. Every tree has the same number of blobs, so the trunk and foliage pools recycle in step.
class Pool:
	const GONE := Vector3(1e9, 0, 1e9)
	const GRID := 2.0
	var cell: float
	var sparse_from := INF
	var survivors := 0.0
	## The meadow's own need no water plant parts.
	var kept_mesh: Mesh
	var capacity: int
	var far: MultiMesh
	var far_live: MultiMeshInstance3D
	var cover: FloraCover
	## The shaders tell placed plants from the meadow's own by it.
	var planted := 0.0
	var material: Material
	var draws := 0
	var mesh: Mesh
	var drawn: Mesh
	var kept := 0
	var _count := 0
	var last := -1
	var _next := 0
	var stamps := PackedInt32Array()
	var anchors := PackedVector3Array()
	## Bumped on every change to `anchors` or a plant's transform; readers cache against it.
	var anchored := 0
	var plants: Array[Plant] = []
	var _parent: Node3D
	var terrain: Terrain
	var _shadows: bool
	## Patches move their instances about, so each slot's data is kept here.
	var _colors := PackedColorArray()
	var _customs := PackedColorArray()
	var _xforms: Array[Transform3D] = []
	var _patches := {}
	## Indexed by painted slot (slot - kept).
	var _patch_of: Array[Patch] = []
	var _index_in_patch := PackedInt32Array()
	var _cell_of: Array[MultiMesh] = []
	var _index_in_cell := PackedInt32Array()
	var _cells: Array[MultiMeshInstance3D] = []
	var _sparse_cells: Array[MultiMeshInstance3D] = []
	var _sparse_cell_of: Array[MultiMesh] = []
	var _index_in_sparse := PackedInt32Array()
	var _centres := PackedVector2Array()
	var _cell_layers := PackedInt32Array()
	var indexed := false
	var _grid := {}
	var soil := false
	var water_plants_further := false
	## How far its plants are drawn past their mesh, in the heights their transforms scale it to: a bare trunk's boughs.
	var overhang := 0.0

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

	func _patch(j: int) -> void:
		var i := kept + j
		var key := Vector2i(floori(_xforms[i].origin.x / cell), floori(_xforms[i].origin.z / cell))
		var p: Patch = _patches.get(key)
		if p == null:
			p = Patch.new()
			p.mm = MultiMesh.new()
			setup(p.mm, drawn, Patch.FIRST)
			p.mm.visible_instance_count = 0
			p.mmi = _show(p.mm)
			p.mmi.set_instance_shader_parameter(&"planted", planted)
			if survivors > 0.0:
				p.few = MultiMesh.new()
				setup(p.few, drawn, Patch.FIRST)
				p.few.visible_instance_count = 0
				p.few_mmi = _show(p.few)
				p.few_mmi.set_instance_shader_parameter(&"planted", planted)
				p.few_mmi.layers = Quality.LADDER_LAYER
				p.few_mmi.visible = false
			_patches[key] = p
		var n := p.slots.size()
		if n == p.mm.instance_count:
			p.mm.instance_count = n * 2
			terrain.lift(p.mm, p.box)
			if p.few != null:
				p.few.instance_count = n * 2
				p.few.visible_instance_count = p.survivors
				terrain.lift(p.few, p.box)
			for k in n:
				_write(p, k, p.slots[k])
		var box := _over_ground(_box(_xforms[i]))
		if n == 0 or not p.box.encloses(box):
			p.box = box if n == 0 else p.box.merge(box)
			terrain.lift(p.mm, p.box)
			if p.few != null:
				terrain.lift(p.few, p.box)
		p.slots.append(i)
		p.water_plants = (n > 0 and p.water_plants) or water_plants_further and _water_plant(i)
		p.mm.visible_instance_count = n + 1
		p.mmi.visible = true
		_patch_of[j] = p
		_index_in_patch[j] = n
		_write(p, n, i)
		if _colors[i].a < survivors:
			_swap(p, n, p.survivors)
			p.survivors += 1
			if p.few != null:
				p.few.visible_instance_count = p.survivors

	func _unpatch(j: int) -> void:
		var p := _patch_of[j]
		if p == null:
			return
		var k := _index_in_patch[j]
		var end: int = p.slots.size() - 1
		if k < p.survivors:
			p.survivors -= 1
			_swap(p, k, p.survivors)
			k = p.survivors
			if p.few != null:
				p.few.visible_instance_count = p.survivors
		_swap(p, k, end)
		p.slots.resize(end)
		p.mm.visible_instance_count = end
		p.mmi.visible = end > 0
		_patch_of[j] = null

	func _swap(p: Patch, a: int, b: int) -> void:
		if a == b:
			return
		var i: int = p.slots[a]
		p.slots[a] = p.slots[b]
		p.slots[b] = i
		_index_in_patch[p.slots[a] - kept] = a
		_index_in_patch[i - kept] = b
		_write(p, a, p.slots[a])
		_write(p, b, i)

	func _write(p: Patch, k: int, i: int) -> void:
		p.mm.set_instance_transform(k, _xforms[i])
		p.mm.set_instance_color(k, _colors[i])
		p.mm.set_instance_custom_data(k, _customs[i])
		if p.few != null and _colors[i].a < survivors:
			p.few.set_instance_transform(k, _xforms[i])
			p.few.set_instance_color(k, _colors[i])
			p.few.set_instance_custom_data(k, _customs[i])

	static func square(at: Vector3) -> Vector2i:
		return Vector2i(floori(at.x / GRID), floori(at.z / GRID))

	func in_square(at: Vector2i) -> Array:
		return _grid.get(at, [])

	func _unindex(i: int) -> void:
		_grid[square(plants[i].anchor)].erase(i)

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
			var baked := kept_mesh if kept_mesh != null else drawn
			var whole := _bake(slots, baked)
			for j in slots.size():
				_cell_of[slots[j]] = whole
				_index_in_cell[slots[j]] = j
			_cells.append(_show(whole))
			_cell_layers.append(1)
			_centres.append((Vector2(key) + Vector2(0.5, 0.5)) * cell)
			if survivors > 0.0:
				var few := slots.filter(func(i: int) -> bool: return _colors[i].a < survivors)
				var mmi: MultiMeshInstance3D = null
				if not few.is_empty():
					var m := _bake(few, baked)
					for j in few.size():
						_sparse_cell_of[few[j]] = m
						_index_in_sparse[few[j]] = j
					mmi = _show(m)
					mmi.visible = false
					mmi.layers = Quality.LADDER_LAYER
				_sparse_cells.append(mmi)
		for p: Patch in _patches.values():
			p.mmi.free()
			if p.few_mmi != null:
				p.few_mmi.free()
		_patches = {}
		capacity -= kept
		_count = 0
		_patch_of.fill(null)

	func _bake(slots: Array, drawn: Mesh) -> MultiMesh:
		var m := MultiMesh.new()
		setup(m, drawn, slots.size())
		var box: AABB = _box(plants[slots[0]].xform)
		for j in slots.size():
			var i: int = slots[j]
			m.set_instance_transform(j, _drawn_as(plants[i].xform, plants[i].rock))
			m.set_instance_color(j, _colors[i])
			m.set_instance_custom_data(j, _customs[i])
			box = box.merge(_box(plants[i].xform))
		terrain.lift(m, _over_ground(box))
		return m

	func patches() -> Array[MultiMeshInstance3D]:
		var out: Array[MultiMeshInstance3D] = []
		for p: Patch in _patches.values():
			out.append(p.mmi)
		return out

	func size() -> int:
		return kept + _count

	func reset() -> void:
		for i in range(kept, size()):
			if indexed:
				_unindex(i)
			plants[i] = null
			stamps[i] += 1
		for p: Patch in _patches.values():
			p.slots.clear()
			p.survivors = 0
			p.mm.visible_instance_count = 0
			p.mmi.visible = false
			if p.few != null:
				p.few.visible_instance_count = 0
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

	func repose(p: Plant, xform: Transform3D, color: Color) -> void:
		if not p.current():
			return
		xform.origin.y -= terrain.height_at(p.anchor.x, p.anchor.z)
		p.xform = xform
		anchored += 1
		if p.shown():
			place(p.slot, xform)
		_colors[p.slot] = color
		if p.slot < kept:
			_cell_of[p.slot].set_instance_color(_index_in_cell[p.slot], color)
			_cover_cell(p.slot)
		else:
			_write(_patch_of[p.slot - kept], _index_in_patch[p.slot - kept], p.slot)
		if far != null:
			far.set_instance_color(p.slot, color)

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

	func spin(p: Plant, about: Vector3, by: float) -> void:
		if not p.current():
			return
		var r := Basis(Vector3.UP, by)
		var o := Vector3(about.x, p.xform.origin.y, about.z)
		p.xform = Transform3D(r * p.xform.basis, o + r * (p.xform.origin - o))
		anchored += 1
		if p.drawn:
			place(p.slot, p.xform)
		if p.slot < kept:
			_cover_cell(p.slot)

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

	func _cover_cell(slot: int) -> void:
		var cell := _cell_of[slot]
		cell.custom_aabb = cell.custom_aabb.merge(_over_ground(_box(plants[slot].xform)))

	func colour_of(slot: int) -> Color:
		return _colors[slot]

	## The box a plant standing at `xform` is drawn within.
	func _box(xform: Transform3D) -> AABB:
		return (xform * mesh.get_aabb()).grow(overhang * xform.basis.y.length())

	## The shaders add the ground's height; the margin is for wind and hands bending blades.
	func _over_ground(box: AABB) -> AABB:
		var ground := terrain.bounds()
		box.position.y += ground.position.y
		box.size.y += ground.size.y
		return box.grow(0.5)

	func draw_with(m: Mesh) -> void:
		drawn = m
		for c in _cells:
			c.multimesh.mesh = m
		for p: Patch in _patches.values():
			p.mm.mesh = m
			if p.few != null:
				p.few.mesh = m

	## Not `visibility_range_end`: it measures to the box's centre, high above the ground as the box spans every terrain
	## height. Out of reach goes to FULL_LAYER so a photo still sees it; water plants draw out to `water_reach`.
	func cull(eye: Vector3, reach: float, water_reach := reach) -> void:
		var half := Vector2(cell, cell) * 0.5
		for i in _cells.size():
			var off := (_centres[i] - Vector2(eye.x, eye.z)).abs() - half
			var d := Vector2(maxf(off.x, 0.0), maxf(off.y, 0.0)).length()
			var layers := 1 if d < minf(sparse_from, reach) else Quality.FULL_LAYER
			if layers != _cell_layers[i]:
				_cell_layers[i] = layers
				_cells[i].layers = layers
			if survivors > 0.0 and _sparse_cells[i] != null:
				_sparse_cells[i].visible = d >= sparse_from and d < reach
		for p: Patch in _patches.values():
			var lo := Vector2(p.box.position.x, p.box.position.z) - Vector2(eye.x, eye.z)
			var hi := Vector2(p.box.end.x, p.box.end.z) - Vector2(eye.x, eye.z)
			var gap := Vector2(maxf(maxf(lo.x, -hi.x), 0.0), maxf(maxf(lo.y, -hi.y), 0.0)).length()
			var end := water_reach if p.water_plants else reach
			var layers := 1 if gap < minf(sparse_from, end) else Quality.FULL_LAYER
			if layers != p.layers:
				p.layers = layers
				p.mmi.layers = layers
			if p.few != null:
				p.few_mmi.visible = p.survivors > 0 and gap >= sparse_from and gap < end

	func rewet(area: Rect2) -> void:
		if not water_plants_further:
			return
		for p: Patch in _patches.values():
			if not area.intersects(Rect2(p.box.position.x, p.box.position.z, p.box.size.x, p.box.size.z)):
				continue
			p.water_plants = false
			for i in p.slots:
				if _water_plant(i):
					p.water_plants = true
					break

	## Mirrors plant.gdshaderinc's `water_form`, but any depth over zero counts, not only its 2 cm, so rounding
	## hides none.
	func _water_plant(slot: int) -> bool:
		var root := _xforms[slot].origin
		return planted > 0.0 and terrain.depth_at(root.x, root.z) > 0.0

	static func setup(m: MultiMesh, drawn: Mesh, count: int) -> void:
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = true
		m.use_custom_data = true
		m.mesh = drawn
		m.instance_count = count

	func far_with(mat: ShaderMaterial) -> void:
		far = MultiMesh.new()
		setup(far, Flora.far_mesh(), capacity)
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


## Doubles when full, so painting rarely resizes a GPU buffer and an unpainted square costs none.
class Patch:
	const FIRST := 64
	var mm: MultiMesh
	var mmi: MultiMeshInstance3D
	## The first `survivors` instances, ranked by colour alpha (FloraLayout.thin_rank), which `Pool._swap` keeps first.
	var few: MultiMesh
	var few_mmi: MultiMeshInstance3D
	var survivors := 0
	var slots := PackedInt32Array()
	var layers := 1
	## So the camera culls a patch by where its plants stand, not its whole square.
	var box: AABB
	## May stay set after its water plant leaves, until the ground or ponds under it next change.
	var water_plants := false


## A tree or bush. `centre` and `radius` bound it across the ground, so a beam tests its parts' boxes only over it.
class Solid:
	var parts: Array[Plant]
	var centre: Vector2
	var radius: float
	var seed := 0
	var species := -1
	var scale := 1.0
	var moss := false
	## Radians about its foot from how it grew.
	var turn := 0.0
	var home: Vector3
	## Its instance in `crown_shade`, or -1.
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


class Plant:
	var pool: Pool
	var slot: int
	var stamp: int
	var xform: Transform3D
	var anchor: Vector3
	## 0 is the meadow's own, else the build command that grew it.
	var group := -1
	var index := -1
	var drawn := true
	var rock := false

	func _init(p: Pool, i: int, x: Transform3D, a: Vector3) -> void:
		pool = p
		slot = i
		stamp = p.stamps[i]
		xform = x
		anchor = a

	func current() -> bool:
		return pool.stamps[slot] == stamp

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

	## For a tool's preview: whether it stands is unchanged.
	func draw(on: bool) -> void:
		if current():
			drawn = on
			pool.draws += 1
			pool.place(slot, Pool._drawn_as(xform, not on))


var moss: Pool
var ghost_moss: Pool
var grass: Pool
var grass_mat := ShaderMaterial.new()
var flowers: Pool
var trunks: Pool
var foliage: Pool
var bushes: Pool
## Each crown casts the sun's shade as one coarse blob, so its blobs do not shade one another in patches.
var crown_shade := MultiMesh.new()
## Drawn for the trunks while the season on show is a winter (Palette.wintry).
var _bare_trunk: ArrayMesh
var _bare := false
var _shaded := -1
var _solids := {}
var _kept_solids := {}
## The meadow never changes once kept, so which of its plants are which is found then, not on every wipe.
var meadow_trees := PackedInt32Array()
var meadow_bushes := PackedInt32Array()
var meadow_scenery := PackedInt32Array()
var meadow_digest := ""
## A key may linger where its slot's earlier tree stood.
var _solid_cells := {}
var groups := {}
## Their spots were fixed as their commands applied, and any command on their plants or the ground's heights grows
## them first, so every machine fills its pools alike.
var _growing: Array[Growth] = []
## A player's stroke until its command comes back, apart so the garden's pools fill in command order on every machine.
var ghost_grass: Pool
var ghost_flowers: Pool
## Sub-pixel blades beyond it cost the Quest 2 most of its frame.
var grass_reach: float = Quality.ladder[0].grass_m:
	set(m):
		grass_reach = m
		grass_mat.set_shader_parameter(&"draw_reach", m)
		for mat in ground_mats:
			mat.set_shader_parameter(&"draw_reach", m)
var flower_reach: float = Quality.ladder[0].flowers_m:
	set(m):
		flower_reach = m
		flower_mat.set_shader_parameter(&"draw_reach", minf(m, FLOWER_NEAR))
		flower_mat.set_shader_parameter(&"water_reach", m)
		if flower_far != null:
			flower_far.set_shader_parameter(&"draw_reach", minf(m, FLOWER_NEAR))
var blob_detail: int = Quality.ladder[0].blob_detail:
	set(n):
		if n != blob_detail:
			blob_detail = n
			foliage.draw_with(_blobs[n])
			bushes.draw_with(_blobs[n])
var flower_mat: ShaderMaterial
var flower_far: ShaderMaterial
var ground_mats: Array[ShaderMaterial] = []
static var _far_mesh: ArrayMesh
var changes := 0
## Made up front so a Quality step only swaps which is drawn.
var _blobs := {}
var terrain: Terrain
var marks: Ground


func _init(ground: Terrain, laid: Ground) -> void:
	terrain = ground
	marks = laid
	grass_mat.shader = preload("res://src/grass.gdshader")
	for k in Meadow.GRASS:
		grass_mat.set_shader_parameter(k, Meadow.GRASS[k])
	_grass_lod(grass_mat)
	part(NO_HAND, NO_HAND)
	var clump := Meshes.grass_clump(CLUMP_BLADES, 1, CLUMP_WIDE)
	var bloom := Meshes.flower(PETALS, Color.WHITE, true)
	grass = Pool.new(self, clump, Meadow.GRASS_CLUMPS + PAINTED_GRASS, grass_mat, false, GRASS_CELL)
	grass.survivors = GRASS_SURVIVORS
	grass.sparse_from = GRASS_LOD_BEGIN + GRASS_LOD_BAND
	flower_mat = _plant_material(preload("res://src/flower.gdshader"), 0.8)
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
	flowers.water_plants_further = true
	var moss_mat := ShaderMaterial.new()
	moss_mat.shader = preload("res://src/moss.gdshader")
	moss = Pool.new(self, Meshes.moss(), PAINTED_MOSS, moss_mat, false)
	moss.indexed = true
	ghost_moss = Pool.new(self, moss.mesh, PAINTED_MOSS, moss_mat, false)
	trunks = Pool.new(self, ToolModels.cylinder(0.16, 0.3, 1.0, 8), Meadow.TREES + PLACED_TREES, _plant_material(preload("res://src/plant.gdshader"), 1.0), true, SOLID_POOL_CELL)
	trunks.material.set_shader_parameter("bough_from", Meshes.BOUGH_FROM)
	_bare_trunk = Meshes.bare_trunk(trunks.mesh)
	var out := 0.0
	for v: Vector3 in _bare_trunk.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		out = maxf(out, Vector2(v.x, v.z).length())
	var spread: float = FloraLayout.BOUGH_SPREAD.values().max()
	trunks.overhang = maxf(_bare_trunk.get_aabb().end.y - trunks.mesh.get_aabb().end.y, out * spread)
	var leaf_mat := _plant_material(preload("res://src/leaf.gdshader"), 1.0)
	leaf_mat.set_shader_parameter("backlight", Color(0.25, 0.35, 0.08))
	leaf_mat.set_shader_parameter("crown_lump", Meshes.BLOB_LUMP)
	for step in Quality.ladder:
		_blobs.get_or_add(step.blob_detail, Meshes.blob(4, step.blob_detail))
	foliage = Pool.new(self, _blobs[blob_detail], (Meadow.TREES + PLACED_TREES) * FloraLayout.BLOBS, leaf_mat, false, SOLID_POOL_CELL)
	bushes = Pool.new(self, _blobs[blob_detail], Meadow.BUSHES + PLACED_BUSHES, leaf_mat, false, SOLID_POOL_CELL)
	Pool.setup(crown_shade, Meshes.blob(4, 1), Meadow.TREES + PLACED_TREES + Meadow.BUSHES + PLACED_BUSHES)
	crown_shade.custom_aabb = terrain.bounds()
	var shade := MultiMeshInstance3D.new()
	shade.multimesh = crown_shade
	shade.material_override = leaf_mat
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(shade)


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
	mat.shader = preload("res://src/flora_far.gdshader")
	mat.set_shader_parameter(&"stem", Meshes.FLOWER_HEIGHT)
	mat.set_shader_parameter(&"draw_reach", minf(flower_reach, FLOWER_NEAR))
	return mat


func paint_ground(mats: Array[ShaderMaterial]) -> void:
	ground_mats = mats
	for mat in mats:
		_grass_lod(mat)


func _grass_lod(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"draw_reach", grass_reach)
	mat.set_shader_parameter(&"lod_begin", GRASS_LOD_BEGIN)
	mat.set_shader_parameter(&"lod_band", GRASS_LOD_BAND)
	mat.set_shader_parameter(&"survivors", GRASS_SURVIVORS)
	mat.set_shader_parameter(&"survivors_from", GRASS_SURVIVORS_FROM)
	Quality.full_detail(mat)


static func _plant_material(shader: Shader, roughness: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("roughness", roughness)
	return mat


func _process(_delta: float) -> void:
	_grow(Budget.GROW_PLANTS if Budget.frame_deadline else -1)
	if Palette.wintry() != _bare:
		_bare = Palette.wintry()
		trunks.draw_with(_bare_trunk if _bare else trunks.mesh)
	_shade_crowns()
	grass.cover.settle(grass)
	var eye := get_viewport().get_camera_3d()
	if eye != null:
		grass.cull(eye.global_position, grass_reach)
		flowers.cull(eye.global_position, minf(flower_reach, FLOWER_NEAR), flower_reach)


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
		_place_shade(solid)
		n += 1
	crown_shade.visible_instance_count = n


func _shade_seen() -> int:
	return changes + trunks.draws + foliage.draws + bushes.draws


func _place_shade(solid: Solid) -> void:
	crown_shade.set_instance_transform(solid.shade, shade_of(solid.parts))
	crown_shade.set_instance_custom_data(solid.shade, Color(0, 0, solid.parts[0].anchor.x, solid.parts[0].anchor.z))
	var blob: Plant = solid.parts[-1]
	crown_shade.set_instance_color(solid.shade, Color(Color.WHITE, blob.pool.colour_of(blob.slot).a))


func shade_of(parts: Array) -> Transform3D:
	var blobs: Array = parts.slice(1) if parts[0].pool == trunks else parts
	var box: AABB = blobs[0].xform * foliage.mesh.get_aabb()
	for b: Plant in blobs:
		box = box.merge(b.xform * foliage.mesh.get_aabb())
	return Transform3D(Basis.from_scale(box.size * SHADE_FIT / crown_shade.mesh.get_aabb().size), box.get_center())


## Whether both reaches are there: a step still under way is not yet the step's cost.
func approach(step: Quality.Step, delta: float) -> bool:
	var grass_m := Quality.reach(grass_reach, step.grass_m, delta)
	if grass_m != grass_reach:
		grass_reach = grass_m
	var flowers_m := Quality.reach(flower_reach, step.flowers_m, delta)
	if flowers_m != flower_reach:
		flower_reach = flowers_m
	blob_detail = step.blob_detail
	return grass_reach == step.grass_m and flower_reach == step.flowers_m


## A stroke's live hump moves no heights, so only a settled one is read.
func reground(area: Rect2, settled: bool) -> void:
	if not settled:
		return
	area = area.grow(Terrain.STEP * 2.0)
	for pool in [grass, flowers, ghost_grass, ghost_flowers]:
		pool.reground(area)
	flowers.rewet(area)


func rewet(area: Rect2) -> void:
	flowers.rewet(area.grow(Terrain.STEP))


func part(left: Vector3, right: Vector3) -> void:
	grass_mat.set_shader_parameter(&"hand_left", left)
	grass_mat.set_shader_parameter(&"hand_right", right)


func add_grass(p: Vector3, rng: RandomNumberGenerator, pool := grass) -> Plant:
	var v := rng.randf_range(0.85, 1.1)
	var c := FloraLayout.clump(p, FloraLayout.GRASS_CLUMP)
	return pool.add(FloraLayout.grass(p, c, rng), Color(v, v, v, FloraLayout.thin_rank(p)), p, Color(FloraLayout.dryness(p), FloraLayout.clump_trait(c, FloraLayout.Trait.TINT, FloraLayout.GRASS_CLUMP), 0, 0))


func add_flower(p: Vector3, rng: RandomNumberGenerator, pool := flowers) -> Plant:
	return pool.add(FloraLayout.flower(p, rng), FloraLayout.flower_color(p), p, Color(FloraLayout.bloom_rank(p), 0, 0, 0))


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
	var solid := _solid(_key_of(trunk), parts)
	solid.seed = seed
	solid.species = species
	return parts


func species_of(trunk: Plant) -> int:
	var solid := _standing(trunk)
	return solid.species if trunk.pool == trunks and solid != null else -1


func scale_of(trunk: Plant) -> float:
	return _solids[_key_of(trunk)].scale if species_of(trunk) >= 0 else 0.0


func top_of(trunk: Plant) -> float:
	var top := 0.0
	for p in _solids[_key_of(trunk)].parts:
		top = maxf(top, (p.xform * p.pool.mesh.get_aabb()).end.y)
	return top


func set_look(trunk: Plant, species: FloraLayout.Species, scale: float) -> void:
	var was := species_of(trunk)
	if was < 0 or was == species and is_equal_approx(scale_of(trunk), scale):
		return
	var key := _key_of(trunk)
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
	_refit(key, solid, false)


func move(first: Plant, at: Vector3) -> void:
	var solid := _standing(first)
	if solid == null:
		return
	var by := Vector3(at.x - first.anchor.x, 0.0, at.z - first.anchor.z)
	if by.is_zero_approx():
		return
	var synced := _shade_seen() == _shaded
	for p in solid.parts:
		p.pool.shift(p, by, Color(1.0 if solid.moss and p.pool == trunks else 0.0, 0, 0, 0))
	_refit(_key_of(first), solid, synced)


func turn_to(first: Plant, yaw: float) -> void:
	var solid := _standing(first)
	if solid == null or is_equal_approx(yaw, solid.turn):
		return
	var synced := _shade_seen() == _shaded
	_spin(solid, yaw - solid.turn)
	_refit(_key_of(first), solid, synced)


func turn_of(first: Plant) -> float:
	var solid := _standing(first)
	return solid.turn if solid != null else 0.0


func _standing(first: Plant) -> Solid:
	var solid: Solid = _solids.get(_key_of(first))
	return solid if first.current() and solid != null and solid.parts[0] == first else null


func _spin(solid: Solid, by: float) -> void:
	var about := solid.parts[0].anchor
	for p in solid.parts:
		p.pool.spin(p, about, by)
	solid.turn += by


## A carried tree moves every frame: with `synced`, only its own shade is fitted again, not every crown's.
func _refit(key: Vector2i, solid: Solid, synced: bool) -> void:
	solid.fit()
	_index(key, solid)
	changes += 1
	if synced:
		_shaded = _shade_seen()
		if solid.shade >= 0:
			_place_shade(solid)


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


## Names in Budget.UNITS.
func unit_of(p: Plant) -> String:
	return {grass: "grass", flowers: "flower", trunks: "tree", bushes: "bush", moss: "moss"}.get(p.pool, "")


func _pools() -> Array[Pool]:
	return [grass, flowers, trunks, foliage, bushes, moss]


func keep(scattered := 0) -> void:
	var meadow: Array[Plant] = []
	for p: Pool in _pools():
		meadow.append_array(p.plants.slice(0, p.size()))
		p.keep()
	_name(0, meadow)
	_kept_solids = _solids.duplicate()
	meadow_trees = _meadow_where(func(p: Plant) -> bool: return p.pool == trunks)
	meadow_bushes = _meadow_where(func(p: Plant) -> bool: return p.pool == bushes)
	meadow_scenery = _meadow_where(func(p: Plant) -> bool: return p.pool != grass)
	var pools := PackedByteArray()
	for p: Plant in groups[0]:
		pools.append(_pools().find(p.pool))
	pools.append_array(var_to_bytes(scattered))
	meadow_digest = Session.sha256(pools).left(16)


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


## A plant there would be parted to nothing yet take a slot.
func on_path(p: Vector3) -> bool:
	return marks.laid_bare(p.x, p.z) > 0.9


## `rng` and `look` are the streams `grow` grows its plants from, so the ghost shows what will grow.
func dab(kind: String, center: Vector3, radius: float, count: int, rng: RandomNumberGenerator, look: RandomNumberGenerator) -> Array[Plant]:
	var out: Array[Plant] = []
	for p in FloraLayout.brush(center, radius, count, rng, terrain.height_at):
		out.append(null if kind != "moss" and marks.bare(p.x, p.z) > 0.9 else _paint(kind, p, look, true))
	return out


func add_moss(p: Vector3, rng: RandomNumberGenerator, pool := moss) -> Plant:
	var size := rng.randf_range(0.65, 1.1)
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
	return pool.add(Transform3D(basis, p), Color(0.055, 0.13, 0.015) * rng.randf_range(0.8, 1.3), p)


func set_moss(trunk: Plant, on: bool) -> void:
	if species_of(trunk) < 0:
		return
	_solids[_key_of(trunk)].moss = on
	trunks.set_custom(trunk.slot, Color(1.0 if on else 0.0, 0, trunk.anchor.x, trunk.anchor.z))


func _paint(kind: String, p: Vector3, rng: RandomNumberGenerator, ghost: bool) -> Plant:
	if kind == "moss":
		return add_moss(p, rng, ghost_moss if ghost else moss)
	if kind == "grass":
		return add_grass(p, rng, ghost_grass if ghost else grass)
	return add_flower(p, rng, ghost_flowers if ghost else flowers)


## A stroke records in `skip` the plants that fell on bare ground, so a garden rebuilt later grows the same plants
## whatever paths and stone stand by then.
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
		for p in FloraLayout.brush(d[0], d[1], d[2], rng, Terrain.flat):
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


## Apart from the spots' stream, so the spots can be fixed before the plants grow.
static func looks(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x1007
	return rng


class Growth:
	var group: int
	var kind: String
	var spots: Array = []
	var looks: RandomNumberGenerator
	var next := 0


func grow_now() -> void:
	_grow(-1)


func growing() -> bool:
	return not _growing.is_empty()


func _grow(count: int) -> void:
	if _growing.is_empty():
		return
	var painted := 0
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
				painted += 1
			g.next += 1
			if count >= 0 and painted >= count:
				return
		_growing.pop_front()
	grown.emit()


func clear_ghosts() -> void:
	ghost_grass.reset()
	ghost_flowers.reset()
	ghost_moss.reset()


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


func reset() -> void:
	changes += 1
	if growing():
		_growing.clear()
		grown.emit()
	for p: Pool in _pools():
		p.reset()
		# Only the taken, found natively: a script visit of every meadow plant held a Quest frame for hundreds of ms. A
		# plant a tool shows taken is the tool's to draw again once its command settles.
		var at := p.anchors.find(Pool.GONE)
		while at >= 0 and at < p.kept:
			p.plants[at].set_shown(true)
			at = p.anchors.find(Pool.GONE, at + 1)
	groups = {0: groups[0]}
	for i in meadow_trees:
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


## Each part is tested within its mesh's box raised to the ground, as its shader draws it.
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


func placed(kind: String) -> Array[Array]:
	var pool := trunks if kind == "tree" else bushes
	var out: Array[Array] = []
	for parts in solids():
		if parts[0].pool == pool and parts[0].slot >= pool.kept:
			out.append(parts)
	return out


func plants_near(p: Vector3, radius: float) -> Array[Plant]:
	var out := grass.near(p, radius)
	out.append_array(flowers.near(p, radius))
	out.append_array(moss.near(p, radius))
	return out


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
		for p: Pool in _pools() + [ghost_grass, ghost_flowers, ghost_moss]:
			p.plants.clear()

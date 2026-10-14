class_name Ground
extends RefCounted

## What the ground is made of: one texel per TEXEL over the play area, shared with shaders as the global
## ground_mask (ground.gdshaderinc). Red is trodden earth, green is stone, neither is meadow. Every path
## and painted stroke is a mark that stamps soft discs onto it, and the mask is those marks replayed in
## the order of their build commands' ids, so lifting any one (undo) leaves exactly what the rest made, and
## every machine replays them alike. `laid` holds the garden's marks alone, for what build commands read;
## the shown image adds a player's own strokes still being drawn or on their way.

## EARTH wears the ground to earth over whatever was there; STONE lays stone over it, earth included, and
## MEADOW takes back only stone, so a path under painted-out stone keeps its wear.
enum Kind { MEADOW, EARTH, STONE }

const SIZE := 512
const TEXEL := Terrain.SIZE / SIZE

static var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RG8)
static var texture := ImageTexture.create_from_image(image)
static var laid := Image.create(SIZE, SIZE, false, Image.FORMAT_RG8)
## The garden's marks in id order, with their ids alongside.
static var _marks: Array[Object] = []
static var _ids: Array[int] = []
## Finished strokes on their way to the garden, still shown.
static var _held: Array[Object] = []
## Counts rewears, so a path being drawn can tell its wear was wiped.
static var rewears := 0
## True while a whole garden is being swapped in: one rewear at the end instead of one per mark.
static var quiet := false
static var _brushes := {}


## A painted ground stroke: soft discs of one kind, replayed in order.
class Stroke:
	var kind: Kind
	## x, z, full radius and the width of the fade past it.
	var stamps := PackedVector4Array()

	func _init(m: Kind) -> void:
		kind = m

	func add(x: float, z: float, radius: float, verge: float) -> bool:
		if not Ground.stamp(Ground.image, x, z, radius, verge, kind):
			return false
		stamps.append(Vector4(x, z, radius, verge))
		Ground.upload()
		return true

	func wear(onto: Image) -> void:
		for s in stamps:
			Ground.stamp(onto, s.x, s.y, s.z, s.w, kind)


static func install() -> void:
	_marks.clear()
	_ids.clear()
	_held.clear()
	rewear()
	RenderingServer.global_shader_parameter_set(&"ground_mask", texture)


static func _texel(x: float, z: float, from := image) -> Color:
	return from.get_pixel(clampi(int((x / Terrain.SIZE + 0.5) * SIZE), 0, SIZE - 1), clampi(int((z / Terrain.SIZE + 0.5) * SIZE), 0, SIZE - 1))


## How bare of plants the ground is at a point, 0 meadow to 1 earth or stone, as the plant shaders read it.
static func bare(x: float, z: float) -> float:
	var c := _texel(x, z)
	return minf(c.r + c.g, 1.0)


## The same from the garden's marks alone.
static func laid_bare(x: float, z: float) -> float:
	var c := _texel(x, z, laid)
	return minf(c.r + c.g, 1.0)


static func stone(x: float, z: float) -> float:
	return _texel(x, z).g


## Adds the garden's mark from build command `id`, in its place by id.
static func lay(mark: Object, id: int) -> void:
	var i := _ids.bsearch(id)
	_ids.insert(i, id)
	_marks.insert(i, mark)
	if i == _marks.size() - 1 and not quiet:
		mark.wear(laid)
		_show()
	else:
		rewear()


static func lift(mark: Object) -> void:
	var i := _marks.find(mark)
	if i >= 0:
		_marks.remove_at(i)
		_ids.remove_at(i)
	rewear()


## Keeps showing a player's finished stroke until `release`, when its command has landed or been turned down.
static func hold(mark: Object) -> void:
	_held.append(mark)


static func release(mark: Object) -> void:
	_held.erase(mark)
	rewear()


## The garden swapped for another: its marks and held strokes go.
static func clear() -> void:
	_marks.clear()
	_ids.clear()
	_held.clear()
	rewear()


## The garden's marks in order into `laid`, then held strokes over them into the shown image.
static func rewear() -> void:
	if quiet:
		return
	laid.fill(Color(0, 0, 0))
	for m in _marks:
		m.wear(laid)
	_show()


static func _show() -> void:
	image.copy_from(laid)
	for m in _held:
		m.wear(image)
	rewears += 1
	upload()


static func upload() -> void:
	texture.update(image)


## Blends a disc of `kind` onto `onto`: full out to `radius`, fading to nothing over `verge` past it.
## False if it fell off the mask, or was meadow that found no stone to take: a stamp that changes nothing
## now may still matter on a replay once an earlier mark is lifted.
static func stamp(onto: Image, x: float, z: float, radius: float, verge: float, kind: Kind) -> bool:
	var fade := _brush(radius, verge)
	var side := int(sqrt(fade.size()))
	var r := (side - 1) / 2
	var at := Vector2i(roundi((x / Terrain.SIZE + 0.5) * SIZE - 0.5) - r, roundi((z / Terrain.SIZE + 0.5) * SIZE - 0.5) - r)
	var area := Rect2i(at, Vector2i(side, side)).intersection(Rect2i(0, 0, SIZE, SIZE))
	if area.size.x <= 0 or area.size.y <= 0:
		return false
	var region := onto.get_region(area)
	var px := region.get_data()
	var changed := false
	for j in area.size.y:
		var row := (area.position.y - at.y + j) * side + area.position.x - at.x
		for i in area.size.x:
			var a := fade[row + i]
			if a == 0:
				continue
			var k := (j * area.size.x + i) * 2
			var e := px[k]
			var g := px[k + 1]
			match kind:
				Kind.EARTH:
					px[k] = e + ((255 - e) * a + 127) / 255
					px[k + 1] = g - (g * a + 127) / 255
				Kind.STONE:
					px[k + 1] = g + ((255 - g) * a + 127) / 255
				Kind.MEADOW:
					px[k + 1] = g - (g * a + 127) / 255
			changed = changed or px[k] != e or px[k + 1] != g
	if changed:
		region.set_data(area.size.x, area.size.y, false, Image.FORMAT_RG8, px)
		onto.blit_rect(region, Rect2i(Vector2i.ZERO, area.size), area.position)
	return changed or kind != Kind.MEADOW


## A disc's coverage, 0 to 255, row by row.
static func _brush(radius: float, verge: float) -> PackedByteArray:
	var key := Vector2i(roundi(radius / TEXEL * 4.0), roundi(verge / TEXEL * 4.0))
	if not _brushes.has(key):
		var inner := key.x * TEXEL / 4.0
		var fade := maxf(key.y * TEXEL / 4.0, TEXEL)
		var r := ceili((inner + fade) / TEXEL)
		var out := PackedByteArray()
		for y in r * 2 + 1:
			for x in r * 2 + 1:
				out.append(roundi(255.0 * clampf((inner + fade - Vector2(x - r, y - r).length() * TEXEL) / fade, 0.0, 1.0)))
		_brushes[key] = out
	return _brushes[key]

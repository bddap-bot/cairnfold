class_name Ground
extends RefCounted

## What the ground is made of: one texel per TEXEL over the play area, shared with shaders as the global
## ground_mask (ground.gdshaderinc). Red is trodden earth, green is stone, neither is meadow. Every path
## and painted stroke is a mark that stamps soft discs onto it, and the mask is those marks replayed in
## the order they were laid, so lifting any one (undo) leaves exactly what the rest made.

## EARTH wears the ground to earth over whatever was there; STONE lays stone over it, earth included, and
## MEADOW takes back only stone, so a path under painted-out stone keeps its wear.
enum Kind { MEADOW, EARTH, STONE }

const SIZE := 512
const TEXEL := Terrain.SIZE / SIZE

static var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RG8)
static var texture := ImageTexture.create_from_image(image)
static var _marks: Array[Object] = []
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
	rewear()
	RenderingServer.global_shader_parameter_set(&"ground_mask", texture)


static func _texel(x: float, z: float) -> Color:
	return image.get_pixel(clampi(int((x / Terrain.SIZE + 0.5) * SIZE), 0, SIZE - 1), clampi(int((z / Terrain.SIZE + 0.5) * SIZE), 0, SIZE - 1))


## How bare of plants the ground is at a point, 0 meadow to 1 earth or stone, as the plant shaders read it.
static func bare(x: float, z: float) -> float:
	var c := _texel(x, z)
	return minf(c.r + c.g, 1.0)


static func stone(x: float, z: float) -> float:
	return _texel(x, z).g


## Adds a mark already stamped onto the live mask, or stamps it now.
static func lay(mark: Object, worn := false) -> void:
	_marks.append(mark)
	if not worn:
		mark.wear(image)
		upload()


static func lift(mark: Object) -> void:
	_marks.erase(mark)
	rewear()


static func rewear() -> void:
	image.fill(Color(0, 0, 0))
	for m in _marks:
		m.wear(image)
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

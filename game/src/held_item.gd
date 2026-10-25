class_name HeldItem
extends Node3D

## A held model's description travels only when it changes; the existing hand pose carries its motion. A conure's
## detail is 1 when it stands on a shoulder (`perched`) rather than in a cupped hand; a brush's or palette's is the
## easel it was taken from, which shows it gone (`EaselTool`), or 0.
enum Kind { TOOL, BRUSH, PALETTE, BOOK, BIRD }

## What a player across the garden holds, which `EaselTool` reads.
const GROUP := &"held_item"
## Where in a state its detail is.
const DETAIL := 5

var state: Array = []
var model: Node3D
var easels: Easels
## The ground a held bird is lit over.
var terrain: Terrain


static func describe(hand: Hand, painting: EaselTool, book: Book) -> Array:
	if not hand.tracked():
		return []
	if hand.carried is Conure:
		return [Kind.BIRD, hand.carried.colouring, BirdCarry.HOLD, Color.WHITE, 0.0, 0, false, Vector3.ZERO]
	var kind := Kind.TOOL
	var index := int(hand.tool)
	var source: Node3D = hand.model(hand.tool)
	var colour := Color.WHITE
	var load := 0.0
	var detail := 0
	var bend := Vector3.ZERO
	if hand.tool == Hand.Tool.NONE:
		return []
	if hand.tool == Hand.Tool.EASEL:
		if painting == null:
			return []
		var p := painting.painter(hand)
		if p.peel != null:
			return []
		if p.palette != null:
			kind = Kind.PALETTE
			index = p.kit
			detail = p.palette.id
			source = p.palette.palettes[p.kit]
		else:
			kind = Kind.BRUSH
			index = p.brush
			detail = p.brush_from
			source = p.models[p.brush]
			colour = p.tip.albedo_color
			load = p.load
			bend = p.bend
	elif hand.tool == Hand.Tool.BOOK:
		if book == null or book.holder != hand:
			return []
		kind = Kind.BOOK
		index = book.page()
		source = book
	if not source.visible:
		return []
	var local := hand.body.global_transform.affine_inverse() * source.global_transform
	return [kind, index, local, colour, load, detail, hand.holds_seeds(), bend]


## The conure on `rig`'s shoulder `side`, standing on it in the torso's frame, without the hand's cup.
static func perched(rig: Rig, side: int) -> Array:
	var c := rig.shoulders[side]
	if c == null:
		return []
	return [Kind.BIRD, c.colouring, Transform3D(Basis.IDENTITY, Torso.SHOULDERS[side]), Color.WHITE, 0.0, 1, false, Vector3.ZERO]


static func same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	if a.is_empty():
		return true
	return a[0] == b[0] and a[1] == b[1] and (a[2] as Transform3D).is_equal_approx(b[2]) and (a[3] as Color).is_equal_approx(b[3]) and is_equal_approx(a[4], b[4]) and a[5] == b[5] and a[6] == b[6] and (a[7] as Vector3).is_equal_approx(b[7])


static func valid(s: Array) -> bool:
	if s.is_empty():
		return true
	if s.size() != 8 or s[0] is not int or s[1] is not int or s[2] is not Transform3D or s[3] is not Color or s[4] is not float or s[5] is not int or s[6] is not bool or s[7] is not Vector3:
		return false
	var t: Transform3D = s[2]
	var c: Color = s[3]
	var bend: Vector3 = s[7]
	if not bend.is_finite() or bend.length() > CanvasContact.BEND + CanvasContact.SKIN:
		return false
	if not t.is_finite() or t.origin.length() > 3.0 or t.basis.get_scale().length() > 6.0 or not is_finite(c.r + c.g + c.b + c.a) or not is_finite(s[4]) or s[4] < 0.0 or s[4] > 1.0:
		return false
	match s[0]:
		Kind.TOOL:
			return s[1] >= 0 and s[1] < Hand.Tool.size() and not s[1] in Hand.UNMODELLED
		Kind.BRUSH:
			return s[1] in Brushwork.Brush.values() and s[5] >= 0
		Kind.PALETTE:
			return s[1] in Easels.KITS and s[5] > 0
		Kind.BIRD:
			return s[1] >= 0 and s[1] < Conure.PLUMAGES.size() and s[5] in [0, 1]
		Kind.BOOK:
			return s[1] >= 0 and s[1] <= ceili(Lessons.PAGES.size() / 2.0) + 1
	return false


func show_state(s: Array) -> void:
	var rebuild: bool = state.is_empty() or s.is_empty() or state[0] != s[0] or state[5] != s[5] or state[1] != s[1] and s[0] != Kind.BOOK
	if not rebuild and state[1] != s[1] and model != null:
		(model as Book).turn_to(s[1])
	state = s.duplicate()
	if rebuild and model != null:
		remove_child(model)
		model.queue_free()
		model = null
	if s.is_empty():
		return
	if model == null:
		match s[0]:
			Kind.TOOL:
				model = ToolModels.build(s[1])
			Kind.BRUSH:
				model = ToolModels.brush(s[1])
				if not Brushwork.is_stick(s[1]):
					(model.get_node("tip") as MeshInstance3D).material_override = StandardMaterial3D.new()
			Kind.PALETTE:
				var e := easels.find(s[5]) if easels != null else null
				model = e.palettes[s[1]].duplicate() if e != null else Easels.watercolours() if s[1] == Brushwork.Medium.WATER else Easels.oils()
			Kind.BIRD:
				model = Conure.new(0.0, s[1])
				model.terrain = terrain
				if s[5] == 0:
					model.add_child(BirdCarry.cup())
			Kind.BOOK:
				model = Book.new(false)
				(model as Book).at = s[1]
				(model as Book)._lay()
				model.set_process(false)
		model.top_level = false
		add_child(model)
	model.visible = true
	model.transform = s[2]
	if s[0] == Kind.BRUSH and not Brushwork.is_stick(s[1]):
		var tip := (model.get_node("tip") as MeshInstance3D).material_override as StandardMaterial3D
		tip.albedo_color = s[3]
		tip.roughness = 0.25 if s[4] > 0.02 else 0.7
		ToolModels.bend(model, s[1], s[7])


## Whether the holder's hand is drawn as what it holds alone, as their own view draws it: a bird perches on a hand.
func replaces_hand() -> bool:
	return not state.is_empty() and state[0] != Kind.BIRD


func feeds() -> bool:
	return not state.is_empty() and state[0] == Kind.TOOL and state[1] == Hand.Tool.SEEDS and state[6]


static func label(s: Array) -> String:
	if s.is_empty():
		return "none"
	match s[0]:
		Kind.TOOL:
			return Hand.Tool.keys()[s[1]].to_lower()
		Kind.BRUSH:
			return Brushwork.Brush.keys()[s[1]].to_lower()
		Kind.PALETTE:
			return "%s palette" % Brushwork.Medium.keys()[s[1]].to_lower()
		Kind.BIRD:
			return "conure"
		Kind.BOOK:
			return "book"
	return ""


func _process(delta: float) -> void:
	if model is Conure:
		model.animate(delta)

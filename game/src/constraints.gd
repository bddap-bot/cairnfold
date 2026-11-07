class_name Constraints
extends SkeletonModifier3D

## An avatar's Unity transform constraints (UNITY_constraints), solved each frame as VRChat solves them after its
## animator: each places a bone from the weighted sources it names, in the file's order, every one seeing those before
## it. A skeleton modifier, so it runs once the frame's pose and springs have set the bones; Avatar keeps it the last.

enum Kind { PARENT, POSITION, LOOK_AT }

const KINDS := {"Parent": Kind.PARENT, "Position": Kind.POSITION, "LookAt": Kind.LOOK_AT}


class Source:
	## The skeleton bone it follows, or -1 for a fixed place in the world.
	var bone := -1
	var world := Transform3D.IDENTITY
	var offset := Transform3D.IDENTITY
	var weight := 1.0


class Constraint:
	var bone := -1
	var kind := Kind.PARENT
	var weight := 1.0
	var sources: Array[Source] = []
	var translation: Array[bool] = []
	var rotation: Array[bool] = []
	var rest := Transform3D.IDENTITY
	var offset := Transform3D.IDENTITY


var constraints: Array[Constraint] = []
## The weight an expression target gives every constraint on a bone, by bone, in place of the one the file saves.
var weights := {}
## Each constrained bone's world transform as the last solve left it, which a constraint sourcing its own bone follows.
var _previous := {}


## The constraints `definitions` (the "constraints" meta Constraints.read makes) on `skeleton`'s bones, each left out
## whose bone or source bone the skeleton lacks.
func _init(definitions: Array, skeleton: Skeleton3D) -> void:
	for d: Dictionary in definitions:
		var c := Constraint.new()
		c.bone = skeleton.find_bone(str(d.node))
		c.kind = KINDS[d.kind]
		c.weight = d.weight
		c.translation.assign(d.translation)
		c.rotation.assign(d.rotation)
		c.rest = matrix(d.rest)
		c.offset = matrix(d.offset)
		for e: Dictionary in d.sources:
			var s := Source.new()
			s.weight = e.weight
			s.offset = matrix(e.offset)
			if e.has("node"):
				s.bone = skeleton.find_bone(str(e.node))
				if s.bone < 0:
					c.bone = -1
			else:
				s.world = matrix(e.world)
			if s.weight > 0.0:
				c.sources.append(s)
		if c.bone >= 0:
			constraints.append(c)


## The solver among `skeleton`'s modifiers, or null.
static func of(skeleton: Skeleton3D) -> Constraints:
	for child: Node in skeleton.get_children():
		if child is Constraints:
			return child
	return null


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	var body := sk.global_transform
	for c in constraints:
		var weight: float = weights.get(c.bone, c.weight)
		var up := sk.get_bone_parent(c.bone)
		var parent := body * sk.get_bone_global_pose(up) if up >= 0 else body
		var current := body * sk.get_bone_global_pose(c.bone)
		var position := Vector3.ZERO
		var turn := Quaternion.IDENTITY
		var total := 0.0
		for s in c.sources:
			var world := s.world
			if s.bone == c.bone:
				world = _previous.get(c.bone, current)
			elif s.bone >= 0:
				world = body * sk.get_bone_global_pose(s.bone)
			var target := world * s.offset if c.kind == Kind.PARENT else world
			position += target.origin * s.weight
			turn = turn.slerp(target.basis.get_rotation_quaternion(), s.weight / (total + s.weight))
			total += s.weight
		var rest := parent * c.rest
		var rest_turn := rest.basis.get_rotation_quaternion()
		var current_turn := current.basis.get_rotation_quaternion()
		var to := rest.origin
		var toward := rest_turn
		if total > 0.0:
			position /= total
			match c.kind:
				Kind.POSITION:
					to = position + c.offset.origin
				Kind.PARENT:
					to = position
					toward = turn
				Kind.LOOK_AT:
					var forward := position - current.origin
					var right := Vector3.UP.cross(forward)
					if forward.is_zero_approx() or right.is_zero_approx():
						toward = current_turn
					else:
						forward = forward.normalized()
						right = right.normalized()
						toward = Basis(right, forward.cross(right), forward).get_rotation_quaternion() * c.offset.basis.get_rotation_quaternion()
		var placed := Transform3D(Basis(current_turn if c.kind == Kind.POSITION else rest_turn.slerp(toward, weight)).scaled_local(current.basis.get_scale()),
			current.origin if c.kind == Kind.LOOK_AT else rest.origin.lerp(to, weight))
		var local := parent.affine_inverse() * placed
		var at := local.origin
		var r := local.basis.get_rotation_quaternion()
		if c.kind != Kind.LOOK_AT:
			var held := sk.get_bone_pose_position(c.bone)
			for axis in 3:
				if not c.translation[axis]:
					at[axis] = held[axis]
		if c.kind == Kind.PARENT and c.rotation.has(false):
			var angles := Basis(r).get_euler(EULER_ORDER_YXZ)
			var held := Basis(sk.get_bone_pose_rotation(c.bone)).get_euler(EULER_ORDER_YXZ)
			for axis in 3:
				if not c.rotation[axis]:
					angles[axis] = held[axis]
			r = Basis.from_euler(angles, EULER_ORDER_YXZ).get_rotation_quaternion()
		sk.set_bone_pose_position(c.bone, at)
		sk.set_bone_pose_rotation(c.bone, r.normalized())
		_previous[c.bone] = parent * sk.get_bone_pose(c.bone)


## The file's UNITY_constraints extension `extension` with each node index as the name of `nodes`' node, as the
## "constraints" meta the converter writes: [] for none, or for one malformed anywhere, since files come from other
## players and a constraint dropped from its group would place a prop where no runtime does.
static func read(extension: Variant, nodes: Array[GLTFNode]) -> Array:
	var list: Variant = extension.get("constraints") if extension is Dictionary else null
	if not list is Array:
		return []
	var out := []
	var node := func(i: Variant) -> String: return nodes[int(i)].resource_name if i is float and i == floorf(i) and i >= 0 and i < nodes.size() else ""
	var mask := func(m: Variant) -> bool: return m is Array and m.size() == 3 and m.all(func(b: Variant) -> bool: return b is bool)
	for c: Variant in list:
		if not (c is Dictionary and KINDS.has(c.get("kind")) and node.call(c.get("node")) != "" and _weight(c.get("weight", 1.0), 1.0)
				and mask.call(c.get("translation")) and mask.call(c.get("rotation")) and _matrix(c.get("rest")) and _matrix(c.get("offset"))
				and c.get("sources") is Array):
			return []
		var sources := []
		for s: Variant in c.sources:
			if not (s is Dictionary and _weight(s.get("weight", 0.0), INF) and _matrix(s.get("offset"))):
				return []
			var source := {"weight": s.get("weight", 0.0), "offset": s.offset}
			if s.has("node"):
				source.node = node.call(s.node)
				if source.node == "":
					return []
			elif _matrix(s.get("world")):
				source.world = s.world
			else:
				return []
			sources.append(source)
		out.append({"kind": c.kind, "node": node.call(c.node), "weight": c.get("weight", 1.0), "translation": c.translation, "rotation": c.rotation, "rest": c.rest, "offset": c.offset, "sources": sources})
	return out


static func _weight(w: Variant, most: float) -> bool:
	return w is float and is_finite(w) and w >= 0.0 and w <= most


## Whether `m` is a column-major 4x4 of finite numbers whose 3x3 part inverts.
static func _matrix(m: Variant) -> bool:
	return m is Array and m.size() == 16 and m.all(func(x: Variant) -> bool: return x is float and is_finite(x)) and absf(matrix(m).basis.determinant()) >= 1e-9


## A column-major 4x4 as the affine transform it holds.
static func matrix(m: Array) -> Transform3D:
	return Transform3D(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10]), Vector3(m[12], m[13], m[14]))

class_name Landing
extends Node3D

## The player's own avatar at a teleport's target, in their pose now, so they see themselves arrive before they go.

var _avatar: Avatar


func _init() -> void:
	top_level = true
	visible = false


func wear(a: Avatar) -> void:
	if _avatar != null:
		_avatar.queue_free()
	_avatar = Avatar.open(a.scene, a.tint)
	add_child(_avatar)


## `size` times life size, posed as `rig`'s player is now about the floor under their head.
func put(at: Vector3, size: float, rig: Rig) -> void:
	visible = true
	var ahead := -rig.head.global_basis.z
	var turn := Basis(Vector3.UP, atan2(-ahead.x, -ahead.z))
	global_transform = Transform3D(turn.scaled(Vector3.ONE * size), at)
	if _avatar == null:
		return
	var h := rig.head.global_position
	var mine := Transform3D(turn, Vector3(h.x, rig.global_position.y, h.z)).affine_inverse()
	_avatar.torso = (mine.basis * rig.torso().basis).get_euler().y
	_avatar.palms = [rig.left.palm, rig.right.palm]
	_avatar.pose(mine * rig.head.global_transform, mine * rig.left.body.global_transform, mine * rig.right.body.global_transform, rig.gaze.look)

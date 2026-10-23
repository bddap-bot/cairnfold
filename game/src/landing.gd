class_name Landing
extends Node3D

## Where a teleport will set the player down: their own avatar standing there, facing as they will, in the pose they
## hold now, so they see themselves arrive before they go.

var _avatar: Avatar


func _init() -> void:
	top_level = true
	visible = false


## Opens a copy of `a`, the player's avatar, to stand at the target.
func wear(a: Avatar) -> void:
	if _avatar != null:
		_avatar.queue_free()
	_avatar = Avatar.open(a.scene, a.tint)
	add_child(_avatar)


## Stands the avatar at `at`, `size` times life size, turned and posed as `rig`'s player is now about the floor under
## their head.
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
	_avatar.pose(mine * rig.head.global_transform, mine * rig.left.global_transform, mine * rig.right.global_transform, rig.gaze.look)

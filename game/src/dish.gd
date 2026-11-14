class_name Dish
extends Node3D

## Another player's seed dish; this player's animals eat from it as from a hand here.

var eyes := Vector3.ZERO


func _init(draw := true) -> void:
	if draw:
		var item := HeldItem.new()
		add_child(item)
		item.show_state([HeldItem.Kind.TOOL, Hand.Tool.SEEDS, Transform3D(Basis(), Hand.TOP), Color.WHITE, 0.0, 0, true])
	visible = false
	add_to_group("dishes")

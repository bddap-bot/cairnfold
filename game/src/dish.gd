class_name Dish
extends Node3D

## Another player's seed dish, in their avatar's hand while they hold it out (`Session`): this player's animals eat
## from it as from a hand here.

## Where the eyes of the player holding it are, for an animal deciding whether to come to look at.
var eyes := Vector3.ZERO


func _init() -> void:
	var model := ToolModels.build(Hand.Tool.SEEDS)
	model.position = Hand.TOP
	add_child(model)
	visible = false
	add_to_group("dishes")

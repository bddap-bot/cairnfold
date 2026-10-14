class_name History
extends Node

## One undo and redo history for every tool: each edit records how to take itself back and redo itself.

const LIMIT := 200


class Step:
	var undo: Callable
	var redo: Callable
	## Nodes the step acts on; one taken out of the scene is freed once no remaining step holds it.
	var holds: Array[Node]

	func _init(u: Callable, r: Callable, h: Array[Node]) -> void:
		undo = u
		redo = r
		holds = h


var undo_stack: Array[Step] = []
var redo_stack: Array[Step] = []
## True while an edit is under way (a stroke drawn, a wall pulled); undo and redo are ignored then.
var busy := func() -> bool: return false
var _buttons: Buttons


func _init(left: Hand) -> void:
	_buttons = Buttons.new(left).watch(["ax_button", "by_button"])


func _process(_delta: float) -> void:
	if _buttons.pressed("ax_button"):
		undo()
	if _buttons.pressed("by_button"):
		redo()
	_buttons.latch()


## Records an edit already made. A new edit after an undo drops the redo steps.
func add(undo_it: Callable, redo_it: Callable, holds: Array[Node] = []) -> void:
	var dropped := redo_stack
	redo_stack = []
	undo_stack.append(Step.new(undo_it, redo_it, holds))
	if undo_stack.size() > LIMIT:
		dropped.append(undo_stack.pop_front())
	_forget(dropped)


func undo() -> void:
	if undo_stack.is_empty() or busy.call():
		return
	var s: Step = undo_stack.pop_back()
	s.undo.call()
	redo_stack.append(s)


func redo() -> void:
	if redo_stack.is_empty() or busy.call():
		return
	var s: Step = redo_stack.pop_back()
	s.redo.call()
	undo_stack.append(s)


func _forget(dropped: Array[Step]) -> void:
	var kept := {}
	for s in undo_stack + redo_stack:
		for n in s.holds:
			kept[n] = true
	for s in dropped:
		for n in s.holds:
			if is_instance_valid(n) and n.get_parent() == null and not kept.has(n):
				n.free()


func _exit_tree() -> void:
	var all := undo_stack + redo_stack
	undo_stack = []
	redo_stack = []
	_forget(all)

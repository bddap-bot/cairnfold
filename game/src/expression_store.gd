class_name ExpressionStore
extends Node

## One writer serializes snapshots; changing avatars cannot race a previous avatar's pending save.
const PATH := "user://expressions.json"
var loaded := false
var chosen := {}
var _task := -1
var _out := {}
var _dirty := false
var _player: ExpressionPlayer
var _key := ""
var _revision := -1


func _ready() -> void:
	_task = WorkerThreadPool.add_task(func() -> void:
		var values: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else {}
		_out["values"] = values if values is Dictionary else {})


func wear(player: ExpressionPlayer, key: String) -> void:
	_remember()
	_player = player
	_key = key
	_revision = -1
	if loaded:
		_restore()


## Returns the worn avatar to its creator's defaults and forgets what was saved for it.
func reset() -> void:
	if not loaded or not is_instance_valid(_player):
		return
	_player.state.reset()
	_revision = _player.state.revision
	if chosen.erase(_key):
		_dirty = true


func _restore() -> void:
	if is_instance_valid(_player):
		_player.state.restore(chosen.get(_key, {}))
		_revision = _player.state.revision


func _remember() -> void:
	if loaded and is_instance_valid(_player) and _key != "" and _revision != _player.state.revision:
		_revision = _player.state.revision
		var values := _player.state.saved()
		if chosen.get(_key, {}) != values:
			chosen[_key] = values
			_dirty = true


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if not loaded:
			chosen = _out.values
			loaded = true
			_restore()
	_remember()
	if loaded and _dirty and _task < 0:
		_dirty = false
		var snapshot := JSON.stringify(chosen)
		_task = WorkerThreadPool.add_task(func() -> void: _write(snapshot))


static func _write(snapshot: String) -> void:
	var file := FileAccess.open(PATH + ".new", FileAccess.WRITE)
	if file == null:
		push_error("Cannot save avatar parameters: %s" % FileAccess.get_open_error())
		return
	file.store_string(snapshot)
	file.close()
	var error := DirAccess.rename_absolute(PATH + ".new", PATH)
	if error != OK:
		push_error("Cannot replace avatar parameters: %s" % error)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
	_remember()
	if _dirty:
		_write(JSON.stringify(chosen))

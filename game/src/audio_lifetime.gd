extends Node

const QUIT_WAIT_MIXES := 20
const QUIT_WAIT_MSEC := 10000

var _quitting := false


func _ready() -> void:
	get_tree().process_frame.connect(_sync_mixer)


## Godot retires playback bus data after two main-thread updates. A delayed mixer can still
## be copying it. Finish that mix before the next update reclaims last frame's retired data;
## a mixer starting after this barrier sees the replacement. The signal also runs while paused.
func _sync_mixer() -> void:
	AudioServer.lock()
	AudioServer.unlock()


## A playback is freed on the main thread only after the audio thread has mixed its stop, so a sound
## still playing when the tree quits outlives the engine, its streams with it. Playbacks go in the order
## they were stopped, so a silent marker stopped last also waits out the sounds of nodes already freed.
## A 3D player hands a new playback to the audio thread on its next physics tick and holds it until then,
## even through stop().
func finish(code := 0) -> void:
	var tree := get_tree()
	if _quitting:
		return
	_quitting = true
	var marker := AudioStreamPlayer.new()
	marker.stream = AudioStreamGenerator.new()
	tree.root.add_child(marker)
	marker.play()
	await tree.physics_frame
	await tree.process_frame
	var held: Array[WeakRef] = []
	for kind in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for p in tree.root.find_children("*", kind, true, false):
			if p.has_stream_playback():
				held.append(weakref(p.get_stream_playback()))
			p.stop()
	var playing := func() -> int: return held.filter(func(w: WeakRef) -> bool: return w.get_ref() != null).size()
	var until := Time.get_ticks_msec() + QUIT_WAIT_MSEC
	var mixes := 0
	var since := AudioServer.get_time_since_last_mix()
	while playing.call() > 0 and mixes < QUIT_WAIT_MIXES and Time.get_ticks_msec() < until:
		await tree.process_frame
		var now := AudioServer.get_time_since_last_mix()
		if now < since:
			mixes += 1
		since = now
	if playing.call() > 0:
		push_error("%d sounds still in use at exit" % playing.call())
	tree.quit(code)


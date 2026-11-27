extends Node

const QUIT_WAIT_MIXES := 20
const QUIT_WAIT_MSEC := 10000

var _quitting := false


## A playback frees only after the audio thread mixes its stop, so one playing at quit outlives the engine. They free
## in stop order, so a marker stopped last waits out freed nodes' sounds. A 3D player holds a new playback until its
## next physics tick, even through stop().
func finish(code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	var tree := get_tree()
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


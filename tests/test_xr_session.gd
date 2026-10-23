extends "res://../tests/support/suite.gd"


class Simulation:
	extends Node
	var frames := 0
	func _process(_delta: float) -> void:
		frames += 1


func _initialize() -> void:
	_run.call_deferred()


func _game(label: String) -> Main:
	var branch := Node.new()
	branch.name = label
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var game := Main.new()
	game.name = "Game"
	branch.add_child(game)
	return game


## Pausing mid-aim drops the aim and its halo, and the stick let go in the system menu teleports nowhere.
func _pause_drops_the_aim(game: Main) -> void:
	var rig := game.rig
	rig.left.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.3, -1), Vector3.UP), rig.head.global_position + Vector3(0, -0.4, -0.3))
	Hand.injected_sticks["left_hand"] = Vector2(0, 1)
	for frame in 4:
		await process_frame
	check(rig.aim_hand == rig.left and rig._landing.visible, "the left stick aims a teleport")
	var at := rig.global_position
	game.xr.session_visible.emit()
	await process_frame
	check(rig.aim_hand == null and not rig._landing.visible, "pausing drops the aim and hides its halo")
	Hand.injected_sticks.clear()
	await process_frame
	game.xr.session_focussed.emit()
	for frame in 12:
		await process_frame
	check(rig.global_position == at, "the stick let go during the pause teleports nowhere")


func _run() -> void:
	var host := _game("Host")
	var guest := _game("Guest")
	host.session.first_port = Session.PORT + 48
	host.session.host()
	check(host.session.port != 0, "host opens a local co-op session")
	guest.session.join("127.0.0.1", host.session.port)
	for frame in 600:
		await process_frame
		if host.session.players() == 2 and guest.session.avatars.has(1):
			break
	check(host.session.players() == 2 and guest.session.avatars.has(1), "co-op peer joins before focus loss")
	var peer := guest.multiplayer.multiplayer_peer
	var ids := host.multiplayer.get_peers()
	# This pause must survive a played session's timeouts, not the scripted co-op exemption.
	for game in [host, guest]:
		for id in game.multiplayer.get_peers():
			(game.multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id).set_timeout(0, 0, 0)
	var sim := Simulation.new()
	guest.add_child(sim)
	var audio := AudioStreamPlayer.new()
	audio.stream = load("res://audio/lap.ogg")
	guest.add_child(audio)
	audio.play()
	var cues := Cues._live
	var cue_voice: AudioStreamPlayer3D = cues._voices[0]
	cue_voice.stream = audio.stream
	cue_voice.play()
	guest.xr = OpenXRInterface.new()
	guest._watch_xr()
	guest.xr.session_focussed.emit()
	await process_frame
	check(not paused and not audio.stream_paused, "focused game runs with audio")
	for signal_name in ["session_visible", "session_synchronized", "session_stopping", "idle", "session_begun"]:
		if signal_name == "idle":
			guest._xr_state(OpenXRInterface.SESSION_STATE_IDLE)
		else:
			guest.xr.emit_signal(signal_name)
		var frames := sim.frames
		var network_clock := guest.session._clock
		var cue_clock := cues._clock
		for frame in 12:
			await process_frame
		if signal_name == "idle":
			var started := Time.get_ticks_msec()
			while Time.get_ticks_msec() - started < 35000:
				await process_frame
				OS.delay_msec(10)
			print("tests: co-op paused for %d ms with normal ENet timeouts" % (Time.get_ticks_msec() - started))
		check(paused and sim.frames == frames and audio.stream_paused, "%s pauses simulation and audio" % signal_name)
		check(not guest.rig.left.visible and not guest.rig.right.visible, "%s hides the player's hands" % signal_name)
		check(cue_voice.stream_paused and cues._clock == cue_clock, "%s pauses action sounds and queued haptics" % signal_name)
		check(guest.session._clock > network_clock, "%s keeps networking processing" % signal_name)
		check(not root.get_node("AudioLifetime")._quitting and is_instance_valid(guest), "%s never quits" % signal_name)
		check(host.multiplayer.get_peers() == ids and guest.multiplayer.multiplayer_peer == peer and guest.session.avatars.has(1), "%s preserves the same co-op peer" % signal_name)
	Buttons.injected["left_hand/ax_button"] = true
	var undos: int = Cues.asked.get(Cues.Act.UNDO, 0)
	guest.xr.session_focussed.emit()
	var before := sim.frames
	for frame in 12:
		await process_frame
	check(not paused and sim.frames > before and not audio.stream_paused, "focus return resumes simulation and audio")
	check(Cues.asked.get(Cues.Act.UNDO, 0) == undos, "a button pressed in the system menu and still held fires nothing on return")
	Buttons.injected.clear()
	await _pause_drops_the_aim(guest)
	check(guest.rig.left.visible and guest.rig.right.visible, "focus return shows the player's hands")
	check(not root.get_node("AudioLifetime")._quitting and host.multiplayer.get_peers() == ids and guest.multiplayer.multiplayer_peer == peer, "return retains the game and co-op connection")
	guest.args["script"] = "demo/costs.json"
	guest.xr.session_visible.emit()
	before = sim.frames
	for frame in 12:
		await process_frame
	check(not paused and sim.frames > before, "a scripted game plays on without focus")
	finish()

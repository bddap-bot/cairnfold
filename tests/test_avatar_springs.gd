extends "res://../tests/support/suite.gd"

const SpringDefinition = preload("res://addons/avatar_workshop/spring_definition.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	boot_main()
	await frames(3)
	var session := main.session
	var hand := main.rig.right
	hand.held_still = true
	hand.tool = Hand.Tool.NONE
	var body := main.rig.body
	check(body.springs != null and not body.springs.chains.is_empty(), "wearer has a live spring chain")
	var key := "right_hand/" + Controls.input("grab", "right_hand")
	hand.global_position = body.springs.tip(0)
	Buttons.injected[key] = true
	await frames(3)
	check(session._spring_holds.get(0) == [session.multiplayer.get_unique_id(), 1], "wearer's grip acquires the chain")
	check(hand.taken(), "chain grip consumes the hand before tools")
	var held := body.springs.tip(0)
	hand.global_position += Vector3(0.08, 0.07, 0)
	await frames(40)
	check(body.springs.tip(0).distance_to(held) > 0.025, "wearer's hand pulls the tip")
	Buttons.injected.erase(key)
	await frames(3)
	check(session._spring_holds.is_empty(), "wearer's release clears the hold")
	var peer := Avatar.open(Avatar.built_in(1), Color.WHITE)
	main.add_child(peer)
	peer.simulate_springs = false
	session.avatars[42] = peer
	var eyes := Transform3D(Basis.IDENTITY, main.rig.head.global_position + Vector3(0.3, 0, 0))
	var grasp := Transform3D(Basis.IDENTITY, body.springs.tip(0))
	peer.pose(eyes, grasp, grasp)
	session._hold_spring(42, 0, 0)
	check(session._spring_holds.get(0) == [42, 0], "remote player's nearby hand acquires the chain")
	var before := body.springs.tip(0)
	grasp.origin += Vector3(-0.07, 0.08, 0)
	peer.pose(eyes, grasp, grasp)
	await frames(40)
	check(body.springs.tip(0).distance_to(before) > 0.025, "remote pose pulls the wearer's solver")
	session._hold_spring(42, 0, -1)
	check(session._spring_holds.is_empty(), "remote release clears the hold")
	grasp.origin = eyes.origin + Vector3(4, 0, 0)
	peer.pose(eyes, grasp, grasp)
	session._hold_spring(42, 0, 0)
	check(session._spring_holds.is_empty(), "distant remote grab is rejected")
	await frames(60)
	var resting := body.springs.tip(0)
	grasp.origin = resting + Vector3(0.03, 0, 0)
	peer.pose(eyes, grasp, grasp)
	await frames(20)
	check(body.springs.tip(0).distance_to(grasp.origin) >= Session.HAND_RADIUS - 0.002, "another player's hand pokes the wearer's chain aside")
	body.springs.chains[0].collide = SpringDefinition.WEARER
	await frames(60)
	check(body.springs.tip(0).distance_to(resting) < 0.01, "a chain that only its wearer's hands push lets another's through")
	body.springs.chains[0].grab = SpringDefinition.WEARER
	grasp.origin = body.springs.tip(0)
	peer.pose(eyes, grasp, grasp)
	session._hold_spring(42, 0, 0)
	check(session._spring_holds.is_empty(), "a chain only its wearer may grab refuses another's hand")
	grasp.origin = eyes.origin + Vector3(4, 0, 0)
	peer.pose(eyes, grasp, grasp)
	body.springs.chains[0].collide = SpringDefinition.WEARER | SpringDefinition.OTHERS
	body.springs.chains[0].grab = SpringDefinition.WEARER | SpringDefinition.OTHERS
	hand.global_position = resting + Vector3(0, 0, 0.03)
	await frames(20)
	check(body.springs.tip(0).distance_to(hand.global_position) >= Session.HAND_RADIUS - 0.002, "the wearer's own hand pokes their chain aside")
	hand.global_position = resting + Vector3(1, 0, 0)
	session.avatars[0] = peer
	session._pose(eyes, grasp, grasp, Vector3.FORWARD, PackedVector3Array([Vector3.ZERO]), {})
	check(session._targets.has(0), "head and hands continue while a different avatar's springs are loading")
	session._targets.erase(0)
	session.avatars.erase(0)
	session.avatars.erase(42)
	peer.queue_free()
	for i in Avatar.BUILT_IN.size():
		var avatar := Avatar.open(Avatar.built_in(i), Color.WHITE)
		main.add_child(avatar)
		avatar.stand()
		check(avatar.springs.chains.size() > 0, "built-in %d imports a chain" % i)
		avatar.queue_free()
	var legacy := Avatar.read(FileAccess.get_file_as_bytes("res://../tests/avatars/godette-0.x.vrm"))
	check(legacy != null, "legacy chained VRM reads as an avatar")
	if legacy != null:
		var avatar := Avatar.open(legacy, Color.WHITE)
		main.add_child(avatar)
		avatar.stand()
		check(avatar.springs.chains.size() > 0, "legacy chains resolve to skeleton bones")
		avatar.springs.advance(1.0 / 60.0)
		check(avatar.springs.state().size() > 0, "legacy chain produces a shared state")
		avatar.queue_free()
	await frames(2)
	finish()

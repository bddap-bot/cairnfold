extends "res://../tests/support/suite.gd"

## A far flower draws from its own buffer: each painted or kept flower's slot there holds exactly what its near instance
## holds. The headless dummy renderer keeps no instance buffers, so scripts/test.sh runs this on the desktop renderer:
## godot4 --path game --xr-mode off --script ../tests/gpu_flora.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		check(false, "no RenderingDevice; run on the desktop renderer")
		finish()
		return
	_far_plants_follow_the_pool()
	finish()


func _far_plants_follow_the_pool() -> void:
	var flora := Flora.new()
	root.add_child(flora)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for pool: Flora.Pool in [flora.flowers, flora.ghost_flowers]:
		var far: MultiMeshInstance3D = pool.far_live
		check(far.layers == Quality.LADDER_LAYER, "the far representation leaves full-detail photos alone")
		check(far.multimesh.mesh.get_faces().size() == 3, "a far plant is one triangle")
		var p := pool.add(Transform3D(Basis.IDENTITY, Vector3(4, 0, 5)), Color.RED, Vector3(4, 0, 5))
		check(far.multimesh.visible_instance_count == 1, "painting shows a near and far instance together")
		_check_far_buffers(pool)
		p.set_shown(false)
		_check_far_buffers(pool)
		check(not p.shown(), "mowing addresses the same plant")
		p.set_shown(true)
		_check_far_buffers(pool)
		pool.keep()
		_check_far_buffers(pool)
		var cell: MultiMesh = pool._cell_of[0]
		check(pool.far.visible_instance_count == 1 and cell.instance_count == 1, "keeping retains the same far slot while baking its near cell")
		check(far.multimesh.instance_count == pool.capacity + pool.kept, "the far batch retains capacity for kept and painted slots")
		pool.add(FloraLayout.flower(Vector3(9, 0, 5), rng), Color.BLUE, Vector3(9, 0, 5))
		pool.repose(p, Transform3D(Basis.from_scale(Vector3.ONE * 1.2), p.foot()), Color.GREEN)
		_check_far_buffers(pool)
		pool.reset()
		_check_far_buffers(pool)
		check(far.multimesh.visible_instance_count == pool.kept, "reset leaves only the kept far plants")
	flora.queue_free()


func _check_far_buffers(pool: Flora.Pool) -> void:
	for i in pool.size():
		var source: MultiMesh = pool._cell_of[i] if i < pool.kept else pool._patch_of[i - pool.kept].mm
		var index: int = pool._index_in_cell[i] if i < pool.kept else pool._index_in_patch[i - pool.kept]
		check(source.buffer.slice(index * 20, (index + 1) * 20) == pool.far.buffer.slice(i * 20, (i + 1) * 20), "both representations contain identical transforms, colours and custom attributes")

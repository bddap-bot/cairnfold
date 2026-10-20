extends SceneTree

## Spatial playback continually replaces the bus data copied by the mix thread. This also
## runs under a debugger that suspends that copy while the main thread advances (issue #64).
var voices: Array[AudioStreamPlayer3D] = []
var frames := 0


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	for i in 64:
		var voice := AudioStreamPlayer3D.new()
		voice.stream = AudioStreamGenerator.new()
		root.add_child(voice)
		voice.play()
		voices.append(voice)


func _process(_delta: float) -> bool:
	frames += 1
	for v in voices:
		v.position.x = sin(frames * 0.1)
	if frames % 1000 == 0:
		paused = not paused
	if frames == 20000:
		paused = false
		print("tests: ok (20000 spatial playback frames, paused and running)")
		Main.quit(self)
	return false

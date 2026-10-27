class_name Take
extends Node

## The microphone during an armed performance take (PlayLog.ARM): heard on a muted bus of its own, so it is never played,
## and handed to the session's record each frame. It goes when the record ends. The bus stays, muted and empty: removed
## while the microphone's last buffer fades, that buffer would fall back to the master bus and be heard.
const BUS := "Take"
## The longest stall the capture rides out without losing the microphone's frames.
const BUFFER_SECONDS := 5.0
var play_log: PlayLog
var _capture := AudioEffectCapture.new()
var _microphone := AudioStreamPlayer.new()


func _init(into: PlayLog) -> void:
	play_log = into


func _ready() -> void:
	# Android asks the wearer for the microphone the moment one opens, and once allowed keeps it open past the take; the
	# dev tool that arms a take grants it beforehand instead.
	if OS.has_feature("android") and not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		push_warning("a performance take needs RECORD_AUDIO granted before it starts; nothing is captured")
		queue_free()
		return
	var bus := AudioServer.get_bus_index(BUS)
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, BUS)
		AudioServer.set_bus_mute(bus, true)
	_capture.buffer_length = BUFFER_SECONDS
	AudioServer.add_bus_effect(bus, _capture)
	_microphone.stream = AudioStreamMicrophone.new()
	_microphone.bus = BUS
	add_child(_microphone)
	_microphone.play()


func _process(_delta: float) -> void:
	if play_log.ended():
		queue_free()
		return
	play_log.listen(_capture.get_buffer(_capture.get_frames_available()))


func _exit_tree() -> void:
	_microphone.stop()
	var bus := AudioServer.get_bus_index(BUS)
	if bus == -1:
		return
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == _capture:
			AudioServer.remove_bus_effect(bus, i)
			return

class_name Stature
extends RefCounted

## The wearer's standing eye height in real metres: the height the head is at or below for STANDING of the time, so
## crouching or tiptoe does not move it; one who plays seated is measured seated, and so stands as tall as their avatar.

const STANDING := 0.9
const LOWEST := 0.5
const HIGHEST := 2.4
const BIN := 0.01
const SETTLE := 2.0

var _time := PackedFloat64Array()
var _total := 0.0


func _init() -> void:
	_time.resize(_bin(HIGHEST) + 1)


func _bin(eye_m: float) -> int:
	return int(round((clampf(eye_m, LOWEST, HIGHEST) - LOWEST) / BIN))


func add(eye_m: float, seconds: float) -> void:
	_time[_bin(eye_m)] += seconds
	_total += seconds


func eye(typical: float) -> float:
	if _total < SETTLE:
		return typical
	var below := 0.0
	for i in _time.size():
		below += _time[i]
		if below >= STANDING * _total:
			return LOWEST + i * BIN
	return HIGHEST

class_name Stature
extends RefCounted

## The wearer's standing eye height in real metres: the highest the eyes have stood through any HOLD, so standing up is
## measured as soon as it is held, while a jump or a reach on tiptoe is not, and crouching or kneeling after never
## lowers it. Until there is LONG of it, it is at least the typical height: a wearer who starts seated or kneeling is not
## taken for a short one, while one who plays seated throughout is measured seated, and so stands as tall as their
## avatar.

const LOWEST := 0.5
const HIGHEST := 2.4
const HOLD := 3.0
const LONG := 60.0

var _total := 0.0
var _held := 0.0
## [end time, height] of the readings still inside HOLD that no later one undercuts, so the first is its lowest.
var _window: Array[Vector2] = []


func add(eye_m: float, seconds: float) -> void:
	var h := clampf(eye_m, LOWEST, HIGHEST)
	if not _window.is_empty():
		_window[-1].x = _total
	while not _window.is_empty() and _window[-1].y >= h:
		_window.pop_back()
	_window.append(Vector2(INF, h))
	_total += seconds
	while _window[0].x <= _total - HOLD:
		_window.pop_front()
	if _total >= HOLD:
		_held = maxf(_held, _window[0].y)


func eye(typical: float) -> float:
	if _total < HOLD:
		return typical
	return _held if _total >= LONG else maxf(_held, typical)

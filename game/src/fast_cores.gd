## Keeps the main thread off the machine's slowest cores. On the Steam Frame the game may run on cores 0 to 4, and
## 0 and 1 are the slow ones: a frame the scheduler runs there takes its scripts and draw calls two to three times as
## long, and the runtime drops to every other refresh for a second or more.
class_name FastCores


## Narrows the calling thread to the cores it may run on that are not clocked as low as the machine's slowest, and
## never widens it, so a runtime that placed the thread already keeps its choice. Threads started before it, the
## engine's workers among them, keep every core.
static func keep_this_thread() -> void:
	var stat := _line("/proc/thread-self/stat")
	var allowed := _cpus(_status_field("/proc/thread-self/status", "Cpus_allowed_list"))
	if stat.is_empty() or allowed.is_empty():
		return
	var clocks := {}
	var cpus := DirAccess.get_directories_at("/sys/devices/system/cpu")
	for name in cpus:
		if name.begins_with("cpu") and name.substr(3).is_valid_int():
			var hz := _line("/sys/devices/system/cpu/%s/cpufreq/cpuinfo_max_freq" % name)
			if hz.is_valid_int():
				clocks[int(name.substr(3))] = int(hz)
	var keep := fast(allowed, clocks)
	if keep == allowed:
		return
	var mask := 0
	for c in keep:
		mask |= 1 << c
	var out := []
	var tid := stat.get_slice(" ", 0)
	if OS.execute("taskset", ["-p", "%x" % mask, tid], out, true) != 0:
		print("fast cores: taskset failed: ", out)
		return
	print("fast cores: main thread on cores %s of %s" % [keep, allowed])


## Of the cores in `allowed`, those clocked above the slowest of all cores in `clocks` (core to its top clock); all of
## `allowed` where that leaves none or a core's clock is unknown.
static func fast(allowed: Array[int], clocks: Dictionary) -> Array[int]:
	if clocks.is_empty() or allowed.any(func(c: int) -> bool: return not clocks.has(c)):
		return allowed
	var slowest: int = clocks.values().min()
	var keep: Array[int] = allowed.filter(func(c: int) -> bool: return clocks[c] > slowest)
	return keep if not keep.is_empty() else allowed


## The cores a list such as "0-4,6" names.
static func _cpus(list: String) -> Array[int]:
	var out: Array[int] = []
	for part in list.strip_edges().split(",", false):
		var ends := part.split("-")
		if not ends[0].is_valid_int() or not ends[-1].is_valid_int():
			return []
		for c in range(int(ends[0]), int(ends[-1]) + 1):
			out.append(c)
	return out


static func _status_field(path: String, field: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with(field + ":"):
			return line.substr(field.length() + 1)
	return ""


static func _line(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_line()

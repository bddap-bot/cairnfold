class_name StressLayout
extends RefCounted

## The densest build a benchmark asks for: parallel walls `spacing` apart filling a disc of `radius`,
## each a stroke of ground points every couple of metres. The rows straddle the centre line, so a viewer
## at the centre stands between two of them.


static func walls(radius: float, spacing: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var z := -(floorf(radius / spacing - 0.5) + 0.5) * spacing
	while z < radius:
		var half := sqrt(radius * radius - z * z)
		if half >= 1.0:
			var row := PackedVector2Array()
			var n := maxi(1, ceili(half * 2.0 / 2.0))
			for i in n + 1:
				row.append(Vector2(lerpf(-half, half, float(i) / n), z))
			out.append(row)
		z += spacing
	return out


## Total wall length in a stress layout.
static func length(rows: Array[PackedVector2Array]) -> float:
	var total := 0.0
	for r in rows:
		total += r[0].distance_to(r[-1])
	return total

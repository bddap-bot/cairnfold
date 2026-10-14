class_name Budget
extends RefCounted

## The frame every build must fit, and what building costs against it: the one source of these numbers.
## scripts/bench.sh holds the stress scene to them; a resource the player can see would read them too.

## One graphics configuration for every headset, held to the weakest: the Quest 2 at 72 Hz.
const REFRESH_HZ := 72.0
## The share of each refresh period the game's GPU work may take; the compositor's warp needs the rest.
const GPU_SHARE := 0.9
static func gpu_ms() -> float:
	return 1000.0 / REFRESH_HZ * GPU_SHARE


static func info() -> Dictionary:
	return {"refresh_hz": REFRESH_HZ, "gpu_ms": gpu_ms()}

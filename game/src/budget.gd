class_name Budget
extends RefCounted

## The frame every build must fit, and what building costs against it: the one source of these numbers.
## scripts/bench.sh holds the stress scene to them; a resource the player can see would read them too.
## Lantern light is baked (`Lamps`) and costs the frame nothing however many hang: a lantern counts by its meshes.

## One graphics configuration for every headset, held to the weakest: the Quest 2 at 72 Hz.
const REFRESH_HZ := 72.0
## The share of each refresh period the game's GPU work may take; the compositor's warp needs the rest.
const GPU_SHARE := 0.9
## What building costs: GPU microseconds a frame per stone laid (WallLayout.stones, ivy, mortar and shadow
## included), the one number a visible budget would count. Fitted on the Quest 2 from the stress scene's walls
## over every flora pool full, from the air, the costlier view (see "Frame budget" in docs/design.md).
const STONE_US := 0.81


static func gpu_ms() -> float:
	return 1000.0 / REFRESH_HZ * GPU_SHARE


static func stones_ms(stones: int) -> float:
	return stones * STONE_US / 1000.0


static func info() -> Dictionary:
	return {"refresh_hz": REFRESH_HZ, "gpu_ms": gpu_ms()}

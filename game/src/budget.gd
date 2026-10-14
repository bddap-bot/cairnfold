class_name Budget
extends RefCounted

## The frame every build must fit, and what building costs against it: the one source of these numbers.
## scripts/bench.sh holds the stress scene to them; a resource the player can see would read them too.

## One graphics configuration for every headset, held to the weakest: the Quest 2 at 72 Hz.
const REFRESH_HZ := 72.0
## The share of each refresh period the game's GPU work may take; the compositor's warp needs the rest.
const GPU_SHARE := 0.9
## What building costs: GPU microseconds a frame per stone laid (WallLayout.stones, ivy, mortar and shadow
## included), the one number a visible budget would count. Fitted on the Steam Frame from the stress scene's
## walls seen from the air (159 to 973 m, 2.6 to 9 m tall, within 10% of it); a Quest 2 run replaces it.
const STONE_US := 0.14


static func gpu_ms() -> float:
	return 1000.0 / REFRESH_HZ * GPU_SHARE


static func stones_ms(stones: int) -> float:
	return stones * STONE_US / 1000.0


static func info() -> Dictionary:
	return {"refresh_hz": REFRESH_HZ, "gpu_ms": gpu_ms()}

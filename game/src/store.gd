class_name Store
extends RefCounted

## The Horizon Store's entitlement check (VRC.Quest.Security.1). Only a store APK (`scripts/android.sh quest OUT store`)
## carries the Platform SDK and the app's id in res://store.tres; every other build has neither and plays unchecked.


## Ends the game unless the store says the headset's user owns the game. The SDK answers from its cache when offline.
static func check() -> void:
	if not Engine.has_singleton("MetaPlatformSDK"):
		return
	var sdk := Engine.get_singleton("MetaPlatformSDK")
	var result: Object = await sdk.initialize_platform_async(str(load("res://store.tres").get_meta("app_id"))).completed
	if not result.is_error():
		result = await sdk.entitlement_get_is_viewer_entitled_async().completed
	if result.is_error():
		print("store: not entitled (%s)" % result.error)
		# Once the Platform SDK has started, Godot's own quit never finishes on a Quest 2, and a player who does not own
		# the game has nothing to save.
		OS.kill(OS.get_process_id())
		return
	print("store: entitled")

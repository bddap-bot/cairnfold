class_name Store
extends RefCounted

## Entitlement check (VRC.Quest.Security.1). Only a store APK (`scripts/android.sh quest OUT store`) carries the
## Platform SDK and res://store.tres; every other build plays unchecked.


## The SDK answers from its cache when offline.
static func check() -> void:
	if not Engine.has_singleton("MetaPlatformSDK"):
		print("store: no Platform SDK, unchecked")
		return
	var sdk := Engine.get_singleton("MetaPlatformSDK")
	var result: Object = await sdk.initialize_platform_async(str(load("res://store.tres").get_meta("app_id"))).completed
	if not result.is_error():
		result = await sdk.entitlement_get_is_viewer_entitled_async().completed
	if result.is_error():
		print("store: not entitled (%s) %d ms after launch" % [result.error, Time.get_ticks_msec()])
		# Once the Platform SDK has started, Godot's quit never finishes on a Quest 2; a non-owner has nothing to save.
		OS.kill(OS.get_process_id())
		return
	print("store: entitled %d ms after launch" % Time.get_ticks_msec())

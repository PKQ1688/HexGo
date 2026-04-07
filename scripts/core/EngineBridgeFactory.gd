class_name EngineBridgeFactory
extends RefCounted

const GDScriptEngineBridgeRef = preload("res://scripts/core/GDScriptEngineBridge.gd")
const NativeMatchEngineBridgeRef = preload("res://scripts/core/NativeMatchEngineBridge.gd")


static func create_engine(prefer_native: bool = true, preferred_radius: int = 5):
	if prefer_native:
		var native_bridge = NativeMatchEngineBridgeRef.new(preferred_radius)
		if native_bridge.is_available():
			return native_bridge
		return GDScriptEngineBridgeRef.new(
			preferred_radius,
			true,
			"%s Falling back to built-in GDScript engine." % native_bridge.backend_status
		)
	return GDScriptEngineBridgeRef.new(preferred_radius, false, "Using built-in GDScript engine.")

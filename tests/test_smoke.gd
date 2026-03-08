extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	assert(scene != null, "Failed to load Main.tscn.")
	var main = scene.instantiate()
	assert(main != null, "Failed to instantiate Main.tscn.")
	root.add_child(main)
	await process_frame
	print("Smoke scene test passed.")
	quit()

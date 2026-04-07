extends SceneTree

func _init():
    var bridge_script = preload("res://scripts/core/NativeMatchEngineBridge.gd")
    var bridge = bridge_script.new(1)
    print("bridge", bridge)
    quit()

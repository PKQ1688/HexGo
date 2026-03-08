class_name PassButtonController
extends Button

signal pass_pressed


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	pass_pressed.emit()


class_name MatchSetupDialog
extends Control

signal start_requested(match_config)

const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")

@onready var black_control: OptionButton = $Overlay/PanelContainer/VBoxContainer/BlackRow/BlackControl
@onready var white_control: OptionButton = $Overlay/PanelContainer/VBoxContainer/WhiteRow/WhiteControl
@onready var difficulty: OptionButton = $Overlay/PanelContainer/VBoxContainer/DifficultyRow/Difficulty
@onready var start_button: Button = $Overlay/PanelContainer/VBoxContainer/StartButton


func _ready() -> void:
	_populate_options()
	start_button.pressed.connect(func() -> void:
		start_requested.emit({
			"black_control": black_control.selected,
			"white_control": white_control.selected,
			"ai_difficulty": difficulty.selected,
		})
	)


func show_dialog(config: Dictionary = {}) -> void:
	var normalized := MatchConfigRef.normalize(config)
	black_control.select(int(normalized["black_control"]))
	white_control.select(int(normalized["white_control"]))
	difficulty.select(int(normalized["ai_difficulty"]))
	visible = true


func hide_dialog() -> void:
	visible = false


func _populate_options() -> void:
	if black_control.item_count > 0:
		return

	for label in ["玩家", "AI"]:
		black_control.add_item(label)
		white_control.add_item(label)

	for label in ["简单", "中等", "困难"]:
		difficulty.add_item(label)

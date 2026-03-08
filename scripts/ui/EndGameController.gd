class_name EndGameController
extends Control

signal restart_requested
signal quit_requested

const GameStateRef = preload("res://scripts/core/GameState.gd")

@onready var result_title: Label = $Overlay/PanelContainer/VBoxContainer/ResultTitle
@onready var score_detail: Label = $Overlay/PanelContainer/VBoxContainer/ScoreDetail
@onready var restart_button: Button = $Overlay/PanelContainer/VBoxContainer/ButtonRow/RestartButton
@onready var quit_button: Button = $Overlay/PanelContainer/VBoxContainer/ButtonRow/QuitButton


func _ready() -> void:
	hide_dialog()
	restart_button.pressed.connect(func() -> void:
		hide_dialog()
		restart_requested.emit()
	)
	quit_button.pressed.connect(func() -> void:
		quit_requested.emit()
	)


func show_result(scores: Dictionary, breakdown: Dictionary) -> void:
	var black_total := int(scores.get(GameStateRef.Player.BLACK, 0))
	var white_total := int(scores.get(GameStateRef.Player.WHITE, 0))
	if black_total == white_total:
		result_title.text = "平局"
	elif black_total > white_total:
		result_title.text = "黑方获胜"
	else:
		result_title.text = "白方获胜"

	var black_data: Dictionary = breakdown.get(GameStateRef.Player.BLACK, {"pieces": 0, "territory": 0, "total": 0})
	var white_data: Dictionary = breakdown.get(GameStateRef.Player.WHITE, {"pieces": 0, "territory": 0, "total": 0})
	score_detail.text = "黑方：棋子 %d，领地 %d，合计 %d\n白方：棋子 %d，领地 %d，合计 %d" % [
		black_data["pieces"],
		black_data["territory"],
		black_data["total"],
		white_data["pieces"],
		white_data["territory"],
		white_data["total"],
	]
	visible = true


func hide_dialog() -> void:
	visible = false

class_name HUDController
extends CanvasLayer

signal pass_pressed
signal resume_play_requested
signal confirm_score_requested

const GameStateRef = preload("res://scripts/core/GameState.gd")

@onready var player_indicator: Label = $MarginContainer/PanelContainer/VBoxContainer/PlayerIndicator
@onready var status_label: Label = $MarginContainer/PanelContainer/VBoxContainer/StatusLabel
@onready var black_score: Label = $MarginContainer/PanelContainer/VBoxContainer/ScorePanel/BlackScore
@onready var white_score: Label = $MarginContainer/PanelContainer/VBoxContainer/ScorePanel/WhiteScore
@onready var pass_button = $MarginContainer/PanelContainer/VBoxContainer/PassButton
@onready var scoring_actions: HBoxContainer = $MarginContainer/PanelContainer/VBoxContainer/ScoringActions
@onready var resume_button: Button = $MarginContainer/PanelContainer/VBoxContainer/ScoringActions/ResumePlayButton
@onready var confirm_button: Button = $MarginContainer/PanelContainer/VBoxContainer/ScoringActions/ConfirmScoreButton


func _ready() -> void:
	pass_button.pass_pressed.connect(func() -> void:
		pass_pressed.emit()
	)
	resume_button.pressed.connect(func() -> void:
		resume_play_requested.emit()
	)
	confirm_button.pressed.connect(func() -> void:
		confirm_score_requested.emit()
	)


func update_turn(current_player: int, breakdown: Dictionary, phase: int) -> void:
	match phase:
		GameStateRef.Phase.SCORING:
			player_indicator.text = "◇  计分阶段"
			status_label.text = "点击棋子切换死活状态，确认后结束对局。"
		GameStateRef.Phase.GAME_OVER:
			player_indicator.text = "—  对局结束"
			status_label.text = "对局已结束。"
		_:
			if current_player == GameStateRef.Player.BLACK:
				player_indicator.text = "●  黑方回合"
			else:
				player_indicator.text = "○  白方回合"
			status_label.text = "规则：连续两次 Pass 进入计分，禁止自杀，支持打劫。"

	var black_data: Dictionary = breakdown.get(GameStateRef.Player.BLACK, {"pieces": 0, "territory": 0, "total": 0})
	var white_data: Dictionary = breakdown.get(GameStateRef.Player.WHITE, {"pieces": 0, "territory": 0, "total": 0})

	black_score.text = "● 黑  子:%d  地:%d  计:%d" % [black_data["pieces"], black_data["territory"], black_data["total"]]
	white_score.text = "○ 白  子:%d  地:%d  计:%d" % [white_data["pieces"], white_data["territory"], white_data["total"]]
	pass_button.disabled = phase != GameStateRef.Phase.WAITING
	scoring_actions.visible = phase == GameStateRef.Phase.SCORING

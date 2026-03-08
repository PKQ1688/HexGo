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
	var current_label := "当前回合：黑方" if current_player == GameStateRef.Player.BLACK else "当前回合：白方"
	player_indicator.text = current_label
	player_indicator.modulate = Color(0.08, 0.08, 0.12) if current_player == GameStateRef.Player.BLACK else Color(0.96, 0.96, 0.96)

	match phase:
		GameStateRef.Phase.SCORING:
			player_indicator.text = "计分阶段"
			player_indicator.modulate = Color(0.96, 0.96, 0.96)
			status_label.text = "点击棋子切换死活，确认后结束；如有争议可继续对局。"
		GameStateRef.Phase.GAME_OVER:
			status_label.text = "对局已结束。"
		_:
			status_label.text = "规则：连续两次 Pass 进入计分，禁止自杀，支持打劫。"

	var black_data: Dictionary = breakdown.get(GameStateRef.Player.BLACK, {"pieces": 0, "territory": 0, "total": 0})
	var white_data: Dictionary = breakdown.get(GameStateRef.Player.WHITE, {"pieces": 0, "territory": 0, "total": 0})

	black_score.text = "黑方  棋子: %d  领地: %d  合计: %d" % [black_data["pieces"], black_data["territory"], black_data["total"]]
	white_score.text = "白方  棋子: %d  领地: %d  合计: %d" % [white_data["pieces"], white_data["territory"], white_data["total"]]
	pass_button.disabled = phase != GameStateRef.Phase.WAITING
	scoring_actions.visible = phase == GameStateRef.Phase.SCORING

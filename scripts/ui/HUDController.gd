class_name HUDController
extends CanvasLayer

signal pass_pressed
signal resume_play_requested
signal confirm_score_requested

const GameStateRef = preload("res://scripts/core/GameState.gd")
const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")

@onready var player_indicator: Label = $MarginContainer/PanelContainer/VBoxContainer/PlayerIndicator
@onready var mode_label: Label = $MarginContainer/PanelContainer/VBoxContainer/ModeLabel
@onready var status_label: Label = $MarginContainer/PanelContainer/VBoxContainer/StatusLabel
@onready var black_score: Label = $MarginContainer/PanelContainer/VBoxContainer/ScorePanel/BlackScore
@onready var white_score: Label = $MarginContainer/PanelContainer/VBoxContainer/ScorePanel/WhiteScore
@onready var pass_button = $MarginContainer/PanelContainer/VBoxContainer/PassButton
@onready var scoring_actions: HBoxContainer = $MarginContainer/PanelContainer/VBoxContainer/ScoringActions
@onready var resume_button: Button = $MarginContainer/PanelContainer/VBoxContainer/ScoringActions/ResumePlayButton
@onready var confirm_button: Button = $MarginContainer/PanelContainer/VBoxContainer/ScoringActions/ConfirmScoreButton

var match_config: Dictionary = MatchConfigRef.default_config()
var ai_thinking: bool = false


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


func set_match_config(config: Dictionary) -> void:
	match_config = MatchConfigRef.normalize(config)
	mode_label.text = "黑方：%s    白方：%s" % [
		MatchConfigRef.player_mode_label(match_config, GameStateRef.Player.BLACK),
		MatchConfigRef.player_mode_label(match_config, GameStateRef.Player.WHITE),
	]


func set_ai_thinking(is_thinking: bool) -> void:
	ai_thinking = is_thinking


func update_turn(current_player: int, breakdown: Dictionary, phase: int) -> void:
	match phase:
		GameStateRef.Phase.SCORING:
			player_indicator.text = "◇  计分阶段"
			status_label.text = "点击整串棋切换死活；红叉棋子为死子，蓝底黑点/金底白环分别表示黑白领地。"
		GameStateRef.Phase.GAME_OVER:
			player_indicator.text = "—  对局结束"
			status_label.text = "对局已结束。"
		_:
			var current_control := MatchConfigRef.get_player_control(match_config, current_player)
			if current_player == GameStateRef.Player.BLACK:
				player_indicator.text = "●  黑方思考中" if current_control == MatchConfigRef.PlayerControl.AI and ai_thinking else "●  黑方回合"
			else:
				player_indicator.text = "○  白方思考中" if current_control == MatchConfigRef.PlayerControl.AI and ai_thinking else "○  白方回合"
			if current_control == MatchConfigRef.PlayerControl.AI and ai_thinking:
				status_label.text = "AI 思考中… 将自动落子，计分阶段仍由玩家手动确认。"
			else:
				status_label.text = "蓝底黑点表示黑方势力，金底白环表示白方势力；悬停棋子看气口，悬停空位预览落子结果。"

	var black_data: Dictionary = breakdown.get(GameStateRef.Player.BLACK, {"pieces": 0, "territory": 0, "total": 0})
	var white_data: Dictionary = breakdown.get(GameStateRef.Player.WHITE, {"pieces": 0, "territory": 0, "total": 0})

	black_score.text = "● 黑  子:%d  地:%d  计:%d" % [black_data["pieces"], black_data["territory"], black_data["total"]]
	white_score.text = "○ 白  子:%d  地:%d  计:%d" % [white_data["pieces"], white_data["territory"], white_data["total"]]
	var ai_turn := phase == GameStateRef.Phase.WAITING and MatchConfigRef.get_player_control(match_config, current_player) == MatchConfigRef.PlayerControl.AI
	pass_button.disabled = phase != GameStateRef.Phase.WAITING or ai_turn
	scoring_actions.visible = phase == GameStateRef.Phase.SCORING

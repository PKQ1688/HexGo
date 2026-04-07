class_name MatchSetupDialog
extends Control

signal start_requested(match_config)

const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")

@onready var description_label: Label = $Overlay/PanelContainer/VBoxContainer/Description
@onready var black_control: OptionButton = $Overlay/PanelContainer/VBoxContainer/BlackRow/BlackControl
@onready var white_control: OptionButton = $Overlay/PanelContainer/VBoxContainer/WhiteRow/WhiteControl
@onready var difficulty_label: Label = $Overlay/PanelContainer/VBoxContainer/DifficultyRow/DifficultyLabel
@onready var difficulty: OptionButton = $Overlay/PanelContainer/VBoxContainer/DifficultyRow/Difficulty
@onready var start_button: Button = $Overlay/PanelContainer/VBoxContainer/StartButton


func _ready() -> void:
	_populate_options()
	difficulty_label.text = "策略档位"
	black_control.item_selected.connect(func(_index: int) -> void:
		_refresh_description()
	)
	white_control.item_selected.connect(func(_index: int) -> void:
		_refresh_description()
	)
	difficulty.item_selected.connect(func(_index: int) -> void:
		_refresh_description()
	)
	start_button.pressed.connect(func() -> void:
		var shared_difficulty := difficulty.selected
		var config := MatchConfigRef.default_config()
		config["black_agent"] = MatchConfigRef.build_agent_spec(black_control.selected, shared_difficulty)
		config["white_agent"] = MatchConfigRef.build_agent_spec(white_control.selected, shared_difficulty)
		start_requested.emit(MatchConfigRef.normalize(config))
	)
	_refresh_description()


func show_dialog(config: Dictionary = {}) -> void:
	var normalized := MatchConfigRef.normalize(config)
	var black_agent: Dictionary = normalized["black_agent"]
	var white_agent: Dictionary = normalized["white_agent"]
	black_control.select(int(black_agent.get("type", MatchConfigRef.AgentType.HUMAN)))
	white_control.select(int(white_agent.get("type", MatchConfigRef.AgentType.HEURISTIC)))
	difficulty.select(MatchConfigRef.get_shared_difficulty(normalized))
	_refresh_description()
	visible = true


func hide_dialog() -> void:
	visible = false


func _populate_options() -> void:
	if black_control.item_count > 0:
		return

	for label: String in MatchConfigRef.agent_type_option_labels():
		black_control.add_item(label)
		white_control.add_item(label)

	for label in ["简单", "中等", "困难"]:
		difficulty.add_item(label)


func _refresh_description() -> void:
	var black_type := black_control.selected
	var white_type := white_control.selected
	if black_type == MatchConfigRef.AgentType.RL or white_type == MatchConfigRef.AgentType.RL:
		description_label.text = "RL 代理会优先请求本地推理服务；若服务不可用，则回退到内置启发式策略。计分阶段仍由玩家手动确认。"
		return
	if black_type == MatchConfigRef.AgentType.LLM or white_type == MatchConfigRef.AgentType.LLM:
		description_label.text = "LLM 代理会优先请求本地或远程模型服务；若服务不可用，则回退到内置启发式策略。计分阶段仍由玩家手动确认。"
		return
	if black_type == MatchConfigRef.AgentType.HEURISTIC or white_type == MatchConfigRef.AgentType.HEURISTIC:
		description_label.text = "启发式 AI 使用项目内置策略。策略档位决定当前代理的默认强度。计分阶段仍由玩家手动确认。"
		return
	description_label.text = "双人对局。计分阶段仍由玩家手动确认。"

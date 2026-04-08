class_name Main
extends Node

const AIControllerRef = preload("res://scripts/ai/AIController.gd")
const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")
const GameStateRef = preload("res://scripts/core/GameState.gd")
const MatchSetupDialogRef = preload("res://scripts/ui/MatchSetupDialog.gd")
const HexLayout = preload("res://scripts/render/HexLayout.gd")

const UI_ZOOM_DEFAULT: float = 1.0
const UI_ZOOM_MIN: float = 0.8
const UI_ZOOM_MAX: float = 1.6
const UI_ZOOM_STEP: float = 0.1

@export var board_radius: int = 5
@export var hex_size: float = 36.0

var layout: HexLayout
var match_config: Dictionary = MatchConfigRef.default_config()

@onready var game_state = $GameState
@onready var ai_controller: AIControllerRef = $AIController
@onready var board_view = $Board
@onready var hud = $HUD
@onready var end_game_dialog = $EndGameDialog
@onready var match_setup_dialog: MatchSetupDialogRef = $MatchSetupDialog


func _ready() -> void:
	layout = HexLayout.new(hex_size, Vector2.ZERO)
	set_process_unhandled_key_input(true)
	_connect_signals()
	_center_board()
	get_viewport().size_changed.connect(_center_board)
	hud.set_match_config(match_config)
	hud.set_ai_thinking(false)
	board_view.set_interaction_enabled(false)
	match_setup_dialog.show_dialog(match_config)


func _connect_signals() -> void:
	board_view.input_handler.cell_clicked.connect(_on_cell_clicked)
	board_view.input_handler.cell_hovered.connect(_on_cell_hovered)
	hud.pass_pressed.connect(_on_pass_pressed)
	hud.resume_play_requested.connect(_on_resume_play_requested)
	hud.confirm_score_requested.connect(_on_confirm_score_requested)
	end_game_dialog.restart_requested.connect(_on_restart_requested)
	end_game_dialog.quit_requested.connect(_on_quit_requested)
	match_setup_dialog.start_requested.connect(_on_match_start_requested)
	ai_controller.thinking_changed.connect(_on_ai_thinking_changed)

	game_state.board_initialized.connect(_on_board_initialized)
	game_state.piece_placed.connect(board_view.piece_renderer.place_piece)
	game_state.pieces_captured.connect(board_view.piece_renderer.capture_pieces)
	game_state.territory_formed.connect(board_view.territory_renderer.set_player_territory)
	game_state.turn_completed.connect(_on_turn_completed)
	game_state.game_over.connect(_on_game_over)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if _apply_zoom_shortcut(event):
		get_viewport().set_input_as_handled()


func _center_board() -> void:
	board_view.position = get_viewport().get_visible_rect().size / 2.0


func _apply_zoom_shortcut(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	if not event.is_command_or_control_pressed():
		return false

	match event.keycode:
		KEY_EQUAL, KEY_KP_ADD:
			_adjust_ui_zoom(UI_ZOOM_STEP)
			return true
		KEY_MINUS, KEY_KP_SUBTRACT:
			_adjust_ui_zoom(-UI_ZOOM_STEP)
			return true
		KEY_0, KEY_KP_0:
			_set_ui_zoom(UI_ZOOM_DEFAULT)
			return true

	return false


func _adjust_ui_zoom(delta: float) -> void:
	_set_ui_zoom(get_tree().root.content_scale_factor + delta)


func _set_ui_zoom(scale_factor: float) -> void:
	var next_scale := snappedf(clampf(scale_factor, UI_ZOOM_MIN, UI_ZOOM_MAX), 0.05)
	if is_equal_approx(get_tree().root.content_scale_factor, next_scale):
		return
	get_tree().root.content_scale_factor = next_scale
	_center_board()


func _on_board_initialized(board) -> void:
	board_view.setup_board(board, layout, game_state)
	if not board_view.influence_renderer.preview_summary_changed.is_connected(_on_preview_summary_changed):
		board_view.influence_renderer.preview_summary_changed.connect(_on_preview_summary_changed)
	board_view.sync_from_board(board, game_state.get_scoring_board(), game_state.get_marked_dead_keys(), game_state.get_visible_threats())
	_refresh_turn_ui()
	end_game_dialog.hide_dialog()


func _on_cell_clicked(coord) -> void:
	if coord == null:
		return
	if game_state.is_scoring_phase():
		game_state.toggle_dead_group(coord)
	else:
		ai_controller.submit_move_coord(coord)


func _on_cell_hovered(coord) -> void:
	var is_valid: bool = false
	if coord != null:
		is_valid = game_state.can_toggle_dead_at(coord) if game_state.is_scoring_phase() else game_state.can_place_at(coord)
	board_view.update_hover(coord, is_valid)


func _on_preview_summary_changed(summary: Dictionary) -> void:
	hud.set_preview_summary(summary)


func _on_pass_pressed() -> void:
	ai_controller.submit_pass()


func _on_turn_completed(player: int, _scores: Dictionary) -> void:
	board_view.sync_from_board(game_state.board, game_state.get_scoring_board(), game_state.get_marked_dead_keys(), game_state.get_visible_threats())
	_refresh_turn_ui(player)
	if game_state.phase == GameStateRef.Phase.GAME_OVER:
		board_view.update_hover(null, false)


func _on_game_over(scores: Dictionary) -> void:
	end_game_dialog.show_result(scores, game_state.score_breakdown)


func _on_restart_requested() -> void:
	ai_controller.cancel_pending_turn()
	hud.set_ai_thinking(false)
	board_view.set_interaction_enabled(false)
	match_setup_dialog.show_dialog(match_config)


func _on_resume_play_requested() -> void:
	ai_controller.resume_play()


func _on_confirm_score_requested() -> void:
	ai_controller.confirm_scoring()


func _on_quit_requested() -> void:
	get_tree().quit()


func start_match(config: Dictionary = {}) -> void:
	match_config = MatchConfigRef.normalize(config)
	hud.set_match_config(match_config)
	hud.set_ai_thinking(false)
	ai_controller.configure(game_state, match_config)
	match_setup_dialog.hide_dialog()
	board_view.set_interaction_enabled(false)
	game_state.setup_game(board_radius)


func _on_match_start_requested(config: Dictionary) -> void:
	start_match(config)


func _on_ai_thinking_changed(is_thinking: bool) -> void:
	hud.set_ai_thinking(is_thinking)
	_refresh_turn_ui()


func _refresh_turn_ui(player: int = -1) -> void:
	if player < 0:
		player = game_state.current_player
	var interaction_enabled := false
	match game_state.phase:
		GameStateRef.Phase.WAITING:
			interaction_enabled = MatchConfigRef.get_player_control(match_config, game_state.current_player) == MatchConfigRef.PlayerControl.HUMAN
		GameStateRef.Phase.SCORING:
			interaction_enabled = true
		_:
			interaction_enabled = false

	board_view.set_interaction_enabled(interaction_enabled)
	hud.update_turn(player, game_state.score_breakdown, game_state.phase)

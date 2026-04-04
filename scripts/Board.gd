class_name Board
extends Node2D

const BoardRendererRef = preload("res://scripts/render/BoardRenderer.gd")
const BoardBackdropRendererRef = preload("res://scripts/render/BoardBackdropRenderer.gd")
const InfluenceRendererRef = preload("res://scripts/render/InfluenceRenderer.gd")
const InputHandlerRef = preload("res://scripts/input/InputHandler.gd")
const PieceRendererRef = preload("res://scripts/render/PieceRenderer.gd")
const TerritoryRendererRef = preload("res://scripts/render/TerritoryRenderer.gd")

@onready var backdrop_renderer: BoardBackdropRendererRef = $BoardBackdropRenderer
@onready var board_renderer: BoardRendererRef = $BoardRenderer
@onready var influence_renderer: InfluenceRendererRef = $InfluenceRenderer
@onready var piece_renderer: PieceRendererRef = $PieceRenderer
@onready var territory_renderer: TerritoryRendererRef = $TerritoryRenderer
@onready var input_handler: InputHandlerRef = $InputHandler


func setup_board(board_model, layout_model, game_state) -> void:
	backdrop_renderer.z_index = -1
	board_renderer.z_index = 0
	territory_renderer.z_index = 1
	influence_renderer.z_index = 2
	piece_renderer.z_index = 3
	backdrop_renderer.setup(board_model, layout_model)
	board_renderer.setup(board_model, layout_model)
	influence_renderer.setup(board_model, layout_model, game_state)
	piece_renderer.setup(board_model, layout_model)
	territory_renderer.setup(board_model, layout_model)
	input_handler.setup(layout_model, self, game_state)


func update_hover(coord, is_valid: bool) -> void:
	board_renderer.update_hover(coord, is_valid)
	influence_renderer.update_focus(coord, is_valid)


func sync_from_board(board_model, scoring_board = null, marked_dead_keys: Array = [], visible_threats: Dictionary = {}) -> void:
	update_hover(null, false)
	piece_renderer.sync_from_board(board_model)
	piece_renderer.set_dead_stones(marked_dead_keys)
	piece_renderer.sync_threat_levels(visible_threats)
	territory_renderer.sync_from_board(scoring_board if scoring_board != null else board_model)
	influence_renderer.sync_from_board(board_model)


func set_interaction_enabled(enabled: bool) -> void:
	input_handler.set_input_enabled(enabled)
	if not enabled:
		update_hover(null, false)

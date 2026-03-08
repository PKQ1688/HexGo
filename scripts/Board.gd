class_name Board
extends Node2D

const BoardRendererRef = preload("res://scripts/render/BoardRenderer.gd")
const InputHandlerRef = preload("res://scripts/input/InputHandler.gd")
const PieceRendererRef = preload("res://scripts/render/PieceRenderer.gd")
const TerritoryRendererRef = preload("res://scripts/render/TerritoryRenderer.gd")

@onready var board_renderer: BoardRendererRef = $BoardRenderer
@onready var piece_renderer: PieceRendererRef = $PieceRenderer
@onready var territory_renderer: TerritoryRendererRef = $TerritoryRenderer
@onready var input_handler: InputHandlerRef = $InputHandler


func setup_board(board_model, layout_model, game_state) -> void:
	board_renderer.setup(board_model, layout_model)
	piece_renderer.setup(board_model, layout_model)
	territory_renderer.setup(board_model, layout_model)
	input_handler.setup(layout_model, self, game_state)


func update_hover(coord, is_valid: bool) -> void:
	board_renderer.update_hover(coord, is_valid)


func sync_from_board(board_model, scoring_board = null, marked_dead_keys: Array = []) -> void:
	piece_renderer.sync_from_board(board_model)
	piece_renderer.set_dead_stones(marked_dead_keys)
	territory_renderer.sync_from_board(scoring_board if scoring_board != null else board_model)

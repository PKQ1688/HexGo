class_name PieceRenderer
extends Node2D

const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const PieceScene = preload("res://scenes/Piece.tscn")

var layout = null
var piece_nodes: Dictionary = {}

@onready var pieces_container: Node2D = $Pieces


func setup(board_model, layout_model) -> void:
	layout = layout_model
	sync_from_board(board_model)


func sync_from_board(board_model) -> void:
	var desired: Dictionary = {}
	for coord in board_model.all_coords:
		var state: int = board_model.get_cell(coord)
		if state != HexBoardRef.CellState.BLACK and state != HexBoardRef.CellState.WHITE:
			continue
		desired[coord.to_key()] = state
		if piece_nodes.has(coord.to_key()):
			continue
		_create_piece(coord, 0 if state == HexBoardRef.CellState.BLACK else 1, false)

	for key: String in piece_nodes.keys():
		if desired.has(key):
			continue
		var node = piece_nodes[key]
		piece_nodes.erase(key)
		node.queue_free()

	set_dead_stones([])
	sync_threat_levels({})


func sync_threat_levels(threat_map: Dictionary) -> void:
	for key: String in piece_nodes.keys():
		var piece = piece_nodes[key]
		var entry: Dictionary = threat_map.get(key, {})
		var threat_level := String(entry.get("threat_level", "SAFE"))
		piece.set_threat_level(threat_level)


func place_piece(coord, player: int) -> void:
	var key: String = coord.to_key()
	if piece_nodes.has(key):
		return
	_create_piece(coord, player, true)


func capture_pieces(coords: Array) -> void:
	for coord in coords:
		var key: String = coord.to_key()
		if not piece_nodes.has(key):
			continue
		var node = piece_nodes[key]
		piece_nodes.erase(key)
		node.play_capture_animation()


func set_dead_stones(keys: Array) -> void:
	var marked: Dictionary = {}
	for key in keys:
		marked[str(key)] = true

	for key: String in piece_nodes.keys():
		piece_nodes[key].set_dead_marked(marked.has(key))


func _create_piece(coord, player: int, animate: bool) -> void:
	var piece = PieceScene.instantiate()
	pieces_container.add_child(piece)
	piece.position = layout.cube_to_pixel(coord)
	piece.set_player(player)
	piece_nodes[coord.to_key()] = piece
	if animate:
		piece.play_place_animation()

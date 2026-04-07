class_name ActionCodec
extends RefCounted

const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")

var board_radius: int = 0
var _ordered_coords: Array[HexCoordRef] = []
var _index_by_key: Dictionary = {}


func _init(radius: int = 0) -> void:
	if radius > 0:
		configure_radius(radius)


func configure_radius(radius: int) -> void:
	var board := HexBoardRef.new()
	board.initialize(radius)
	configure_board(board)


func configure_board(board: HexBoardRef) -> void:
	board_radius = board.board_radius
	_ordered_coords.clear()
	for coord in board.all_coords:
		_ordered_coords.append(coord.duplicated())
	_ordered_coords.sort_custom(func(a: HexCoordRef, b: HexCoordRef) -> bool:
		if a.q != b.q:
			return a.q < b.q
		if a.r != b.r:
			return a.r < b.r
		return a.s < b.s
	)
	_index_by_key.clear()
	for index in range(_ordered_coords.size()):
		_index_by_key[_ordered_coords[index].to_key()] = index


func get_ordered_coords() -> Array:
	var coords: Array = []
	for coord in _ordered_coords:
		coords.append(coord.duplicated())
	return coords


func action_count() -> int:
	return _ordered_coords.size() + 1


func pass_action_index() -> int:
	return _ordered_coords.size()


func is_pass_action(action_index: int) -> bool:
	return action_index == pass_action_index()


func coord_to_action_index(coord: HexCoordRef) -> int:
	if coord == null:
		return -1
	return int(_index_by_key.get(coord.to_key(), -1))


func action_index_to_coord(action_index: int):
	if action_index < 0 or action_index >= _ordered_coords.size():
		return null
	return _ordered_coords[action_index].duplicated()


func encode_move(coord: HexCoordRef) -> Dictionary:
	var action_index := coord_to_action_index(coord)
	if action_index < 0:
		return {}
	return {
		"type": "move",
		"action_index": action_index,
		"coord": coord.duplicated(),
	}


func decode_action_index(action_index: int) -> Dictionary:
	if is_pass_action(action_index):
		return {
			"type": "pass",
			"action_index": action_index,
		}
	var coord = action_index_to_coord(action_index)
	if coord == null:
		return {}
	return {
		"type": "move",
		"action_index": action_index,
		"coord": coord,
	}


func legal_action_mask(state) -> Array:
	var mask: Array = []
	for coord in _ordered_coords:
		mask.append(1 if state.can_place_at(coord) else 0)
	mask.append(1 if state.can_pass() else 0)
	return mask

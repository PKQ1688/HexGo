class_name HexBoard
extends RefCounted

const HexCoordRef = preload("res://scripts/core/HexCoord.gd")

enum CellState {
	EMPTY,
	BLACK,
	WHITE,
	TERRITORY_BLACK,
	TERRITORY_WHITE,
}

var cells: Dictionary = {}
var board_radius: int = 0
var all_coords: Array[HexCoordRef] = []


func initialize(radius: int) -> void:
	board_radius = radius
	cells.clear()
	all_coords.clear()

	for q in range(-board_radius, board_radius + 1):
		for r in range(-board_radius, board_radius + 1):
			var coord := HexCoordRef.new(q, r)
			if max(abs(coord.q), abs(coord.r), abs(coord.s)) > board_radius:
				continue
			all_coords.append(coord)
			cells[coord.to_key()] = CellState.EMPTY


func is_valid_coord(coord: HexCoordRef) -> bool:
	if coord == null:
		return false
	return max(abs(coord.q), abs(coord.r), abs(coord.s)) <= board_radius


func get_cell(coord: HexCoordRef) -> int:
	if not is_valid_coord(coord):
		return -1
	return int(cells.get(coord.to_key(), CellState.EMPTY))


func set_cell(coord: HexCoordRef, state: int) -> void:
	if not is_valid_coord(coord):
		return
	cells[coord.to_key()] = state


func get_neighbors(coord: HexCoordRef) -> Array[HexCoordRef]:
	var result: Array[HexCoordRef] = []
	for neighbor in coord.neighbors():
		if is_valid_coord(neighbor):
			result.append(neighbor)
	return result


func get_empty_cells() -> Array[HexCoordRef]:
	var result: Array[HexCoordRef] = []
	for coord in all_coords:
		if get_cell(coord) == CellState.EMPTY:
			result.append(coord)
	return result


func clone():
	var copy = new()
	copy.initialize(board_radius)
	copy.cells = cells.duplicate(true)
	copy.all_coords.clear()
	for coord in all_coords:
		copy.all_coords.append(coord.duplicated())
	return copy

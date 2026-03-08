class_name CaptureResolver
extends RefCounted

const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")


static func resolve(board: HexBoardRef, attacker_state: int) -> Array:
	var defender_state: int = HexBoardRef.CellState.BLACK
	if attacker_state == HexBoardRef.CellState.BLACK:
		defender_state = HexBoardRef.CellState.WHITE

	var captured: Array = []
	var visited_groups: Dictionary = {}

	for coord in board.all_coords:
		if board.get_cell(coord) != defender_state:
			continue
		if visited_groups.has(coord.to_key()):
			continue

		var group := find_group(board, coord, defender_state)
		for item in group:
			visited_groups[item.to_key()] = true

		if get_liberties(board, group) == 0:
			captured.append_array(group)

	return captured


static func find_group(board: HexBoardRef, start_coord: HexCoordRef, target_state: int) -> Array:
	if board.get_cell(start_coord) != target_state:
		return []

	var visited: Dictionary = {}
	var queue: Array = [start_coord]
	var group: Array = []

	while not queue.is_empty():
		var current: HexCoordRef = queue.pop_front()
		var current_key := current.to_key()
		if visited.has(current_key):
			continue

		visited[current_key] = true
		group.append(current)

		for neighbor in board.get_neighbors(current):
			var neighbor_key := neighbor.to_key()
			if visited.has(neighbor_key):
				continue
			if board.get_cell(neighbor) == target_state:
				queue.append(neighbor)

	return group


static func get_liberties(board: HexBoardRef, group: Array) -> int:
	var liberty_set: Dictionary = {}
	for coord in group:
		for neighbor in board.get_neighbors(coord):
			if board.get_cell(neighbor) == HexBoardRef.CellState.EMPTY:
				liberty_set[neighbor.to_key()] = true
	return liberty_set.size()

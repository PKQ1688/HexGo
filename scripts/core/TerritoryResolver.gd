class_name TerritoryResolver
extends RefCounted

const CaptureResolverRef = preload("res://scripts/core/CaptureResolver.gd")
const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")


static func resolve(board: HexBoardRef, owner_state: int) -> Array:
	var regions_by_owner := resolve_all(board)
	return regions_by_owner.get(owner_state, [])


static func resolve_all(board: HexBoardRef) -> Dictionary:
	var result := {
		HexBoardRef.CellState.BLACK: [],
		HexBoardRef.CellState.WHITE: [],
	}
	var visited: Dictionary = {}

	for coord in board.all_coords:
		if board.get_cell(coord) != HexBoardRef.CellState.EMPTY:
			continue
		if visited.has(coord.to_key()):
			continue

		var region := CaptureResolverRef.find_group(board, coord, HexBoardRef.CellState.EMPTY)
		for item in region:
			visited[item.to_key()] = true

		var owner := determine_region_owner(board, region)
		if owner == HexBoardRef.CellState.BLACK or owner == HexBoardRef.CellState.WHITE:
			result[owner].append_array(region)

	return result


static func determine_region_owner(board: HexBoardRef, region: Array) -> int:
	var border_players: Dictionary = {}
	var touches_boundary := false

	for coord in region:
		var neighbors := board.get_neighbors(coord)
		if neighbors.size() < 6:
			touches_boundary = true
			break

		for neighbor in neighbors:
			match board.get_cell(neighbor):
				HexBoardRef.CellState.BLACK:
					border_players[HexBoardRef.CellState.BLACK] = true
				HexBoardRef.CellState.WHITE:
					border_players[HexBoardRef.CellState.WHITE] = true

	if touches_boundary:
		return -1
	if border_players.size() != 1:
		return -1

	return int(border_players.keys()[0])

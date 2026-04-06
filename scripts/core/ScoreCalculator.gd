class_name ScoreCalculator
extends RefCounted

const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const TerritoryResolverRef = preload("res://scripts/core/TerritoryResolver.gd")


static func calculate(board: HexBoardRef, dead_stones: Dictionary = {}) -> Dictionary:
	return totals_from_breakdown(calculate_breakdown(board, dead_stones))


static func calculate_breakdown(board: HexBoardRef, dead_stones: Dictionary = {}) -> Dictionary:
	var scoring_board: HexBoardRef = build_scoring_board(board, dead_stones)
	var territory_map: Dictionary = TerritoryResolverRef.resolve_all(scoring_board)
	return calculate_breakdown_from_territory_map(scoring_board, territory_map)


static func calculate_from_territory_map(board: HexBoardRef, territory_map: Dictionary, dead_stones: Dictionary = {}) -> Dictionary:
	if not dead_stones.is_empty():
		return calculate(board, dead_stones)
	return totals_from_breakdown(calculate_breakdown_from_territory_map(board, territory_map))


static func calculate_breakdown_from_territory_map(board: HexBoardRef, territory_map: Dictionary) -> Dictionary:
	var result := {
		0: {"pieces": 0, "territory": 0, "total": 0},
		1: {"pieces": 0, "territory": 0, "total": 0},
	}

	for coord in board.all_coords:
		match board.get_cell(coord):
			HexBoardRef.CellState.BLACK:
				result[0]["pieces"] += 1
			HexBoardRef.CellState.WHITE:
				result[1]["pieces"] += 1

	result[0]["territory"] = territory_map.get(HexBoardRef.CellState.BLACK, []).size()
	result[1]["territory"] = territory_map.get(HexBoardRef.CellState.WHITE, []).size()

	result[0]["total"] = result[0]["pieces"] + result[0]["territory"]
	result[1]["total"] = result[1]["pieces"] + result[1]["territory"]
	return result


static func totals_from_breakdown(breakdown: Dictionary) -> Dictionary:
	return {
		0: int(breakdown[0]["total"]),
		1: int(breakdown[1]["total"]),
	}


static func build_scoring_board(board: HexBoardRef, dead_stones: Dictionary = {}) -> HexBoardRef:
	var scoring_board: HexBoardRef = board.clone()
	for key: String in dead_stones.keys():
		scoring_board.cells[key] = HexBoardRef.CellState.EMPTY
	return scoring_board

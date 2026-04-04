class_name ThreatAnalyzer
extends RefCounted

const CaptureResolverRef = preload("res://scripts/core/CaptureResolver.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")
const HexBoardRef = preload("res://scripts/core/HexBoard.gd")

const THREAT_LIBERTIES_KEY := "liberties"
const THREAT_LEVEL_KEY := "threat_level"

const THREAT_LEVEL_SAFE := "SAFE"
const THREAT_LEVEL_WARNING := "WARNING"
const THREAT_LEVEL_DANGER := "DANGER"


static func analyze(board: HexBoardRef) -> Dictionary:
	var result: Dictionary = {}
	var visited: Dictionary = {}

	for coord in board.all_coords:
		var state := board.get_cell(coord)
		if state != HexBoardRef.CellState.BLACK and state != HexBoardRef.CellState.WHITE:
			continue

		var key := coord.to_key()
		if visited.has(key):
			continue

		var group := CaptureResolverRef.find_group(board, coord, state)
		var liberties := CaptureResolverRef.get_liberties(board, group)
		var threat_level := _threat_level_for_liberties(liberties)

		for item: HexCoordRef in group:
			var item_key: String = item.to_key()
			visited[item_key] = true
			result[item_key] = {
				THREAT_LIBERTIES_KEY: liberties,
				THREAT_LEVEL_KEY: threat_level,
			}

	return result


static func _threat_level_for_liberties(liberties: int) -> String:
	if liberties <= 1:
		return THREAT_LEVEL_DANGER
	if liberties == 2:
		return THREAT_LEVEL_WARNING
	return THREAT_LEVEL_SAFE

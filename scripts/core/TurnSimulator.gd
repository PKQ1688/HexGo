class_name TurnSimulator
extends RefCounted

const CaptureResolverRef = preload("res://scripts/core/CaptureResolver.gd")
const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")
const ScoreCalculatorRef = preload("res://scripts/core/ScoreCalculator.gd")
const TerritoryResolverRef = preload("res://scripts/core/TerritoryResolver.gd")

const PLAYER_BLACK := 0
const PLAYER_WHITE := 1


static func simulate_place(
	source_board: HexBoardRef,
	current_player: int,
	previous_board_signature: String,
	current_board_signature: String,
	coord: HexCoordRef,
	dead_stones: Dictionary = {}
) -> Dictionary:
	var signature := current_board_signature
	if signature == "" and source_board != null:
		signature = board_signature(source_board)
	var result := {
		"legal": false,
		"board": source_board,
		"captured": [],
		"captured_count": 0,
		"territory_map": {},
		"scores": {},
		"board_signature": signature,
		"next_player": current_player,
		"ended_by_double_pass": false,
		"consecutive_passes": 0,
		"self_group": [],
		"self_group_liberties": 0,
	}
	if source_board == null or coord == null:
		return result
	if not source_board.is_valid_coord(coord):
		return result
	if source_board.get_cell(coord) != HexBoardRef.CellState.EMPTY:
		return result

	var board_copy: HexBoardRef = source_board.clone()
	var piece_state := _player_to_piece_state(current_player)
	board_copy.set_cell(coord, piece_state)

	var captured: Array = CaptureResolverRef.resolve(board_copy, piece_state)
	for captured_coord in captured:
		board_copy.set_cell(captured_coord, HexBoardRef.CellState.EMPTY)

	var self_group := CaptureResolverRef.find_group(board_copy, coord, piece_state)
	if self_group.is_empty():
		return result

	var liberties := CaptureResolverRef.get_liberties(board_copy, self_group)
	if liberties <= 0:
		return result

	var next_signature := board_signature(board_copy)
	if previous_board_signature != "" and next_signature == previous_board_signature:
		return result

	var territory_map := TerritoryResolverRef.resolve_all(board_copy)
	result["legal"] = true
	result["board"] = board_copy
	result["captured"] = _duplicate_coords(captured)
	result["captured_count"] = captured.size()
	result["territory_map"] = territory_map
	result["scores"] = ScoreCalculatorRef.calculate_from_territory_map(board_copy, territory_map, dead_stones)
	result["board_signature"] = next_signature
	result["next_player"] = _other_player(current_player)
	result["self_group"] = _duplicate_coords(self_group)
	result["self_group_liberties"] = liberties
	result["consecutive_passes"] = 0
	return result


static func simulate_pass(
	source_board: HexBoardRef,
	current_player: int,
	current_board_signature: String,
	consecutive_passes: int,
	dead_stones: Dictionary = {}
) -> Dictionary:
	var result := _base_result(source_board, current_player, current_board_signature, dead_stones)
	if source_board == null:
		return result

	var pass_count := consecutive_passes + 1
	result["legal"] = true
	result["consecutive_passes"] = pass_count
	result["ended_by_double_pass"] = pass_count >= 2
	result["next_player"] = _other_player(current_player)
	return result


static func board_signature(target_board: HexBoardRef) -> String:
	var tokens: PackedStringArray = []
	for coord in target_board.all_coords:
		tokens.append(str(target_board.get_cell(coord)))
	return ",".join(tokens)


static func _base_result(source_board: HexBoardRef, current_player: int, current_board_signature: String, dead_stones: Dictionary) -> Dictionary:
	var board_copy = null if source_board == null else source_board.clone()
	var signature := current_board_signature
	if signature == "" and source_board != null:
		signature = board_signature(source_board)

	return {
		"legal": false,
		"board": board_copy,
		"captured": [],
		"captured_count": 0,
		"territory_map": {} if source_board == null else _duplicate_territory_map(TerritoryResolverRef.resolve_all(source_board)),
		"scores": {} if source_board == null else ScoreCalculatorRef.calculate(source_board, dead_stones),
		"board_signature": signature,
		"next_player": current_player,
		"ended_by_double_pass": false,
		"consecutive_passes": 0,
		"self_group": [],
		"self_group_liberties": 0,
	}


static func _player_to_piece_state(player: int) -> int:
	return HexBoardRef.CellState.BLACK if player == PLAYER_BLACK else HexBoardRef.CellState.WHITE


static func _other_player(player: int) -> int:
	return PLAYER_WHITE if player == PLAYER_BLACK else PLAYER_BLACK


static func _duplicate_coords(coords: Array) -> Array:
	var result: Array = []
	for coord in coords:
		result.append(coord.duplicated())
	return result


static func _duplicate_territory_map(territory_map: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for owner in territory_map.keys():
		result[owner] = _duplicate_coords(territory_map[owner])
	return result

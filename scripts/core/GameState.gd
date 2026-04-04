class_name GameState
extends Node

const CaptureResolverRef = preload("res://scripts/core/CaptureResolver.gd")
const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")
const ScoreCalculatorRef = preload("res://scripts/core/ScoreCalculator.gd")
const ThreatAnalyzerRef = preload("res://scripts/core/ThreatAnalyzer.gd")
const TerritoryResolverRef = preload("res://scripts/core/TerritoryResolver.gd")
const TurnSimulatorRef = preload("res://scripts/core/TurnSimulator.gd")

signal board_initialized(board)
signal piece_placed(coord, player)
signal pieces_captured(coords)
signal territory_formed(coords, player)
signal turn_completed(player, scores)
signal scoring_state_changed(marked_dead_keys)
signal game_over(scores)

enum Player {
	BLACK,
	WHITE,
}

enum Phase {
	WAITING,
	PLACING,
	RESOLVING_CAPTURE,
	RESOLVING_TERRITORY,
	SCORING,
	GAME_OVER,
}

@export var board_radius: int = 5

var board: HexBoardRef = HexBoardRef.new()
var current_player: int = Player.BLACK
var phase: int = Phase.WAITING
var consecutive_passes: int = 0
var move_history: Array = []
var scores: Dictionary = {Player.BLACK: 0, Player.WHITE: 0}
var score_breakdown: Dictionary = {}
var marked_dead_stones: Dictionary = {}
var previous_board_signature: String = ""
var current_board_signature: String = ""
var resume_player_after_scoring: int = Player.BLACK


func setup_game(radius: int = board_radius) -> void:
	board_radius = radius
	board.initialize(board_radius)
	current_player = Player.BLACK
	phase = Phase.WAITING
	consecutive_passes = 0
	move_history.clear()
	marked_dead_stones.clear()
	previous_board_signature = ""
	current_board_signature = TurnSimulatorRef.board_signature(board)
	resume_player_after_scoring = Player.BLACK
	_update_scores()
	_emit_scoring_preview()
	board_initialized.emit(board)
	scoring_state_changed.emit([])
	turn_completed.emit(current_player, scores)


func switch_player() -> void:
	current_player = _other_player(current_player)


func record_pass() -> void:
	if phase != Phase.WAITING:
		return

	var result := TurnSimulatorRef.simulate_pass(
		board,
		current_player,
		current_board_signature,
		consecutive_passes,
		marked_dead_stones
	)
	consecutive_passes = int(result["consecutive_passes"])
	move_history.append({
		"type": "pass",
		"player": current_player,
	})

	if result["ended_by_double_pass"]:
		_enter_scoring_phase()
		return

	switch_player()
	_update_scores()
	_emit_scoring_preview()
	turn_completed.emit(current_player, scores)


func can_place_at(coord: HexCoordRef) -> bool:
	if phase != Phase.WAITING:
		return false
	if not board.is_valid_coord(coord):
		return false
	if board.get_cell(coord) != HexBoardRef.CellState.EMPTY:
		return false
	return bool(TurnSimulatorRef.simulate_place(
		board,
		current_player,
		previous_board_signature,
		current_board_signature,
		coord
	)["legal"])


func execute_turn(coord: HexCoordRef) -> bool:
	if phase != Phase.WAITING:
		return false
	if not can_place_at(coord):
		return false

	var result := TurnSimulatorRef.simulate_place(
		board,
		current_player,
		previous_board_signature,
		current_board_signature,
		coord
	)
	if not result["legal"]:
		return false

	phase = Phase.PLACING
	piece_placed.emit(coord, current_player)

	phase = Phase.RESOLVING_CAPTURE
	var captured: Array = result["captured"]
	if not captured.is_empty():
		pieces_captured.emit(captured)

	_apply_board_state(result["board"])

	phase = Phase.RESOLVING_TERRITORY
	var territory_map: Dictionary = result["territory_map"]
	var black_territory: Array = territory_map.get(HexBoardRef.CellState.BLACK, [])
	var white_territory: Array = territory_map.get(HexBoardRef.CellState.WHITE, [])

	territory_formed.emit(black_territory, Player.BLACK)
	territory_formed.emit(white_territory, Player.WHITE)

	consecutive_passes = 0
	move_history.append({
		"type": "move",
		"coord": coord.duplicated(),
		"player": current_player,
		"captured": _duplicate_coords(captured),
		"territory_black": _duplicate_coords(black_territory),
		"territory_white": _duplicate_coords(white_territory),
	})

	previous_board_signature = current_board_signature
	current_board_signature = result["board_signature"]
	switch_player()
	phase = Phase.WAITING
	_update_scores()
	turn_completed.emit(current_player, scores)

	return true


func is_scoring_phase() -> bool:
	return phase == Phase.SCORING


func get_visible_threats() -> Dictionary:
	if phase == Phase.SCORING or phase == Phase.GAME_OVER:
		return {}

	var threat_map: Dictionary = ThreatAnalyzerRef.analyze(board)
	var visible_threats: Dictionary = {}
	for key in threat_map:
		var entry: Dictionary = threat_map[key]
		if String(entry.get(ThreatAnalyzerRef.THREAT_LEVEL_KEY, ThreatAnalyzerRef.THREAT_LEVEL_SAFE)) == ThreatAnalyzerRef.THREAT_LEVEL_SAFE:
			continue
		visible_threats[key] = entry
	return visible_threats


func can_toggle_dead_at(coord: HexCoordRef) -> bool:
	if phase != Phase.SCORING:
		return false
	if not board.is_valid_coord(coord):
		return false
	var state := board.get_cell(coord)
	return state == HexBoardRef.CellState.BLACK or state == HexBoardRef.CellState.WHITE


func toggle_dead_group(coord: HexCoordRef) -> bool:
	if not can_toggle_dead_at(coord):
		return false

	var state := board.get_cell(coord)
	var group := CaptureResolverRef.find_group(board, coord, state)
	var should_mark := false
	for item in group:
		if not marked_dead_stones.has(item.to_key()):
			should_mark = true
			break

	for item in group:
		var key: String = item.to_key()
		if should_mark:
			marked_dead_stones[key] = state
		else:
			marked_dead_stones.erase(key)

	_update_scores()
	_emit_scoring_preview()
	scoring_state_changed.emit(get_marked_dead_keys())
	turn_completed.emit(current_player, scores)
	return true


func resume_play() -> bool:
	if phase != Phase.SCORING:
		return false
	marked_dead_stones.clear()
	scoring_state_changed.emit([])
	consecutive_passes = 0
	current_player = resume_player_after_scoring
	phase = Phase.WAITING
	_update_scores()
	_emit_scoring_preview()
	turn_completed.emit(current_player, scores)
	return true


func confirm_scoring() -> bool:
	if phase != Phase.SCORING:
		return false
	_finish_game()
	return true


func get_marked_dead_keys() -> Array:
	return marked_dead_stones.keys()


func get_scoring_board():
	return ScoreCalculatorRef.build_scoring_board(board, marked_dead_stones)


func build_turn_snapshot() -> Dictionary:
	return {
		"board": board.clone(),
		"current_player": current_player,
		"previous_board_signature": previous_board_signature,
		"current_board_signature": current_board_signature,
		"consecutive_passes": consecutive_passes,
		"scores": scores.duplicate(true),
		"score_breakdown": score_breakdown.duplicate(true),
		"move_count": move_history.size(),
		"board_radius": board_radius,
	}


func _enter_scoring_phase() -> void:
	phase = Phase.SCORING
	resume_player_after_scoring = _other_player(current_player)
	_update_scores()
	_emit_scoring_preview()
	scoring_state_changed.emit(get_marked_dead_keys())
	turn_completed.emit(current_player, scores)


func _finish_game() -> void:
	phase = Phase.GAME_OVER
	_update_scores()
	_emit_scoring_preview()
	turn_completed.emit(current_player, scores)
	game_over.emit(scores)


func _update_scores() -> void:
	scores = ScoreCalculatorRef.calculate(board, marked_dead_stones)
	score_breakdown = ScoreCalculatorRef.calculate_breakdown(board, marked_dead_stones)


func _other_player(player: int) -> int:
	return Player.WHITE if player == Player.BLACK else Player.BLACK


func _player_to_piece_state(player: int) -> int:
	return HexBoardRef.CellState.BLACK if player == Player.BLACK else HexBoardRef.CellState.WHITE


func _emit_scoring_preview() -> void:
	var preview_board = get_scoring_board()
	var territory_map: Dictionary = TerritoryResolverRef.resolve_all(preview_board)
	territory_formed.emit(territory_map.get(HexBoardRef.CellState.BLACK, []), Player.BLACK)
	territory_formed.emit(territory_map.get(HexBoardRef.CellState.WHITE, []), Player.WHITE)


func _apply_board_state(source_board: HexBoardRef) -> void:
	board.board_radius = source_board.board_radius
	board.cells = source_board.cells.duplicate(true)
	board.all_coords.clear()
	for coord in source_board.all_coords:
		board.all_coords.append(coord.duplicated())


func _duplicate_coords(coords: Array) -> Array:
	var result: Array = []
	for coord in coords:
		result.append(coord.duplicated())
	return result

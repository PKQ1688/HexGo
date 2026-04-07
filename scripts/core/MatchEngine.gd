class_name MatchEngine
extends RefCounted

const CaptureResolverRef = preload("res://scripts/core/CaptureResolver.gd")
const EngineProtocolRef = preload("res://scripts/core/EngineProtocol.gd")
const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")
const ScoreCalculatorRef = preload("res://scripts/core/ScoreCalculator.gd")
const ThreatAnalyzerRef = preload("res://scripts/core/ThreatAnalyzer.gd")
const TerritoryResolverRef = preload("res://scripts/core/TerritoryResolver.gd")
const TurnSimulatorRef = preload("res://scripts/core/TurnSimulator.gd")

const EVENT_BOARD_INITIALIZED := "board_initialized"
const EVENT_PIECE_PLACED := "piece_placed"
const EVENT_PIECES_CAPTURED := "pieces_captured"
const EVENT_TERRITORY_FORMED := "territory_formed"
const EVENT_TURN_COMPLETED := "turn_completed"
const EVENT_SCORING_STATE_CHANGED := "scoring_state_changed"
const EVENT_GAME_OVER := "game_over"

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

var board_radius: int = 5
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

var _pending_events: Array = []


func setup_game(radius: int = board_radius) -> void:
	_pending_events.clear()
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
	_queue_scoring_preview_events()
	_queue_event(EVENT_BOARD_INITIALIZED, {
		"board": board,
	})
	_queue_event(EVENT_SCORING_STATE_CHANGED, {
		"marked_dead_keys": [],
	})
	_queue_turn_completed_event()


func switch_player() -> void:
	current_player = _other_player(current_player)


func record_pass() -> void:
	_pending_events.clear()
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
	_queue_scoring_preview_events()
	_queue_turn_completed_event()


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
	_pending_events.clear()
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
	_queue_event(EVENT_PIECE_PLACED, {
		"coord": coord.duplicated(),
		"player": current_player,
	})

	phase = Phase.RESOLVING_CAPTURE
	var captured: Array = result["captured"]
	if not captured.is_empty():
		_queue_event(EVENT_PIECES_CAPTURED, {
			"coords": _duplicate_coords(captured),
		})

	_apply_board_state(result["board"])

	phase = Phase.RESOLVING_TERRITORY
	var territory_map: Dictionary = result["territory_map"]
	var black_territory: Array = territory_map.get(HexBoardRef.CellState.BLACK, [])
	var white_territory: Array = territory_map.get(HexBoardRef.CellState.WHITE, [])
	_queue_territory_event(Player.BLACK, black_territory)
	_queue_territory_event(Player.WHITE, white_territory)

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
	current_board_signature = String(result["board_signature"])
	switch_player()
	phase = Phase.WAITING
	_update_scores()
	_queue_turn_completed_event()
	return true


func can_pass() -> bool:
	return phase == Phase.WAITING


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
	_pending_events.clear()
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
	_queue_scoring_preview_events()
	_queue_event(EVENT_SCORING_STATE_CHANGED, {
		"marked_dead_keys": get_marked_dead_keys(),
	})
	_queue_turn_completed_event()
	return true


func resume_play() -> bool:
	_pending_events.clear()
	if phase != Phase.SCORING:
		return false
	marked_dead_stones.clear()
	_queue_event(EVENT_SCORING_STATE_CHANGED, {
		"marked_dead_keys": [],
	})
	consecutive_passes = 0
	current_player = resume_player_after_scoring
	phase = Phase.WAITING
	_update_scores()
	_queue_scoring_preview_events()
	_queue_turn_completed_event()
	return true


func confirm_scoring() -> bool:
	_pending_events.clear()
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


func build_observation(action_codec = null, rules_config: Dictionary = {}) -> Dictionary:
	return EngineProtocolRef.serialize_observation(self, action_codec, rules_config)


func consume_events() -> Array:
	var events := _pending_events
	_pending_events = []
	return events


func _enter_scoring_phase() -> void:
	phase = Phase.SCORING
	resume_player_after_scoring = _other_player(current_player)
	_update_scores()
	_queue_scoring_preview_events()
	_queue_event(EVENT_SCORING_STATE_CHANGED, {
		"marked_dead_keys": get_marked_dead_keys(),
	})
	_queue_turn_completed_event()


func _finish_game() -> void:
	phase = Phase.GAME_OVER
	_update_scores()
	_queue_scoring_preview_events()
	_queue_turn_completed_event()
	_queue_event(EVENT_GAME_OVER, {
		"scores": scores.duplicate(true),
	})


func _update_scores() -> void:
	var scoring_board = ScoreCalculatorRef.build_scoring_board(board, marked_dead_stones)
	var territory_map: Dictionary = TerritoryResolverRef.resolve_all(scoring_board)
	score_breakdown = ScoreCalculatorRef.calculate_breakdown_from_territory_map(scoring_board, territory_map)
	scores = ScoreCalculatorRef.totals_from_breakdown(score_breakdown)


func _queue_scoring_preview_events() -> void:
	var preview_board = get_scoring_board()
	var territory_map: Dictionary = TerritoryResolverRef.resolve_all(preview_board)
	_queue_territory_event(Player.BLACK, territory_map.get(HexBoardRef.CellState.BLACK, []))
	_queue_territory_event(Player.WHITE, territory_map.get(HexBoardRef.CellState.WHITE, []))


func _queue_territory_event(player: int, coords: Array) -> void:
	_queue_event(EVENT_TERRITORY_FORMED, {
		"coords": _duplicate_coords(coords),
		"player": player,
	})


func _queue_turn_completed_event() -> void:
	_queue_event(EVENT_TURN_COMPLETED, {
		"player": current_player,
		"scores": scores.duplicate(true),
	})


func _queue_event(event_type: String, data: Dictionary = {}) -> void:
	var event := data.duplicate(true)
	event["type"] = event_type
	_pending_events.append(event)


func _other_player(player: int) -> int:
	return Player.WHITE if player == Player.BLACK else Player.BLACK


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

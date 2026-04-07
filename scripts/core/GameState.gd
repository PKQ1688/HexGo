class_name GameState
extends Node

const MatchEngineRef = preload("res://scripts/core/MatchEngine.gd")
const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")

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

var _engine: MatchEngineRef = MatchEngineRef.new()

@export var board_radius: int = 5

var board: HexBoardRef:
	get:
		return _engine.board

var current_player: int:
	get:
		return _engine.current_player
	set(value):
		_engine.current_player = value

var phase: int:
	get:
		return _engine.phase
	set(value):
		_engine.phase = value

var consecutive_passes: int:
	get:
		return _engine.consecutive_passes
	set(value):
		_engine.consecutive_passes = value

var move_history: Array:
	get:
		return _engine.move_history
	set(value):
		_engine.move_history = value

var scores: Dictionary:
	get:
		return _engine.scores
	set(value):
		_engine.scores = value

var score_breakdown: Dictionary:
	get:
		return _engine.score_breakdown
	set(value):
		_engine.score_breakdown = value

var marked_dead_stones: Dictionary:
	get:
		return _engine.marked_dead_stones
	set(value):
		_engine.marked_dead_stones = value

var previous_board_signature: String:
	get:
		return _engine.previous_board_signature
	set(value):
		_engine.previous_board_signature = value

var current_board_signature: String:
	get:
		return _engine.current_board_signature
	set(value):
		_engine.current_board_signature = value

var resume_player_after_scoring: int:
	get:
		return _engine.resume_player_after_scoring
	set(value):
		_engine.resume_player_after_scoring = value


func _init() -> void:
	_engine.board_radius = board_radius


func setup_game(radius: int = board_radius) -> void:
	board_radius = radius
	_engine.setup_game(radius)
	_flush_engine_events()


func switch_player() -> void:
	_engine.switch_player()


func record_pass() -> void:
	_engine.record_pass()
	_flush_engine_events()


func can_pass() -> bool:
	return _engine.can_pass()


func can_place_at(coord: HexCoordRef) -> bool:
	return _engine.can_place_at(coord)


func execute_turn(coord: HexCoordRef) -> bool:
	var success := _engine.execute_turn(coord)
	_flush_engine_events()
	return success


func is_scoring_phase() -> bool:
	return _engine.is_scoring_phase()


func get_visible_threats() -> Dictionary:
	return _engine.get_visible_threats()


func can_toggle_dead_at(coord: HexCoordRef) -> bool:
	return _engine.can_toggle_dead_at(coord)


func toggle_dead_group(coord: HexCoordRef) -> bool:
	var success := _engine.toggle_dead_group(coord)
	_flush_engine_events()
	return success


func resume_play() -> bool:
	var success := _engine.resume_play()
	_flush_engine_events()
	return success


func confirm_scoring() -> bool:
	var success := _engine.confirm_scoring()
	_flush_engine_events()
	return success


func get_marked_dead_keys() -> Array:
	return _engine.get_marked_dead_keys()


func get_scoring_board():
	return _engine.get_scoring_board()


func build_turn_snapshot() -> Dictionary:
	return _engine.build_turn_snapshot()


func build_observation(action_codec = null) -> Dictionary:
	return _engine.build_observation(action_codec)


func _flush_engine_events() -> void:
	for event in _engine.consume_events():
		match String(event.get("type", "")):
			MatchEngineRef.EVENT_BOARD_INITIALIZED:
				board_initialized.emit(event.get("board"))
			MatchEngineRef.EVENT_PIECE_PLACED:
				piece_placed.emit(event.get("coord"), int(event.get("player", Player.BLACK)))
			MatchEngineRef.EVENT_PIECES_CAPTURED:
				pieces_captured.emit(event.get("coords", []))
			MatchEngineRef.EVENT_TERRITORY_FORMED:
				territory_formed.emit(event.get("coords", []), int(event.get("player", Player.BLACK)))
			MatchEngineRef.EVENT_TURN_COMPLETED:
				turn_completed.emit(int(event.get("player", Player.BLACK)), event.get("scores", {}))
			MatchEngineRef.EVENT_SCORING_STATE_CHANGED:
				scoring_state_changed.emit(event.get("marked_dead_keys", []))
			MatchEngineRef.EVENT_GAME_OVER:
				game_over.emit(event.get("scores", {}))

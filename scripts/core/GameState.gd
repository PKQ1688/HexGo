class_name GameState
extends Node

const EngineBridgeFactoryRef = preload("res://scripts/core/EngineBridgeFactory.gd")
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

var _engine = null

@export var board_radius: int = 5
@export var prefer_native_engine: bool = true

var board: HexBoardRef:
	get:
		_ensure_engine()
		return _engine.get_board()

var current_player: int:
	get:
		_ensure_engine()
		return _engine.get_current_player()
	set(value):
		_ensure_engine()
		_engine.set_current_player(value)

var phase: int:
	get:
		_ensure_engine()
		return _engine.get_phase()
	set(value):
		_ensure_engine()
		_engine.set_phase(value)

var consecutive_passes: int:
	get:
		_ensure_engine()
		return _engine.get_consecutive_passes()
	set(value):
		_ensure_engine()
		_engine.set_consecutive_passes(value)

var move_history: Array:
	get:
		_ensure_engine()
		return _engine.get_move_history()
	set(value):
		_ensure_engine()
		_engine.set_move_history(value)

var scores: Dictionary:
	get:
		_ensure_engine()
		return _engine.get_scores()
	set(value):
		_ensure_engine()
		_engine.set_scores(value)

var score_breakdown: Dictionary:
	get:
		_ensure_engine()
		return _engine.get_score_breakdown()
	set(value):
		_ensure_engine()
		_engine.set_score_breakdown(value)

var marked_dead_stones: Dictionary:
	get:
		_ensure_engine()
		return _engine.get_marked_dead_stones()
	set(value):
		_ensure_engine()
		_engine.set_marked_dead_stones(value)

var previous_board_signature: String:
	get:
		_ensure_engine()
		return _engine.get_previous_board_signature()
	set(value):
		_ensure_engine()
		_engine.set_previous_board_signature(value)

var current_board_signature: String:
	get:
		_ensure_engine()
		return _engine.get_current_board_signature()
	set(value):
		_ensure_engine()
		_engine.set_current_board_signature(value)

var resume_player_after_scoring: int:
	get:
		_ensure_engine()
		return _engine.get_resume_player_after_scoring()
	set(value):
		_ensure_engine()
		_engine.set_resume_player_after_scoring(value)


func _init() -> void:
	_engine = EngineBridgeFactoryRef.create_engine(prefer_native_engine, board_radius)


func setup_game(radius: int = board_radius) -> void:
	board_radius = radius
	_ensure_engine()
	_engine.setup_game(radius)
	_flush_engine_events()


func switch_player() -> void:
	_ensure_engine()
	_engine.switch_player()


func record_pass() -> void:
	_ensure_engine()
	_engine.record_pass()
	_flush_engine_events()


func can_pass() -> bool:
	_ensure_engine()
	return _engine.can_pass()


func can_place_at(coord: HexCoordRef) -> bool:
	_ensure_engine()
	return _engine.can_place_at(coord)


func execute_turn(coord: HexCoordRef) -> bool:
	_ensure_engine()
	var success: bool = bool(_engine.execute_turn(coord))
	_flush_engine_events()
	return success


func is_scoring_phase() -> bool:
	_ensure_engine()
	return _engine.is_scoring_phase()


func get_visible_threats() -> Dictionary:
	_ensure_engine()
	return _engine.get_visible_threats()


func can_toggle_dead_at(coord: HexCoordRef) -> bool:
	_ensure_engine()
	return _engine.can_toggle_dead_at(coord)


func toggle_dead_group(coord: HexCoordRef) -> bool:
	_ensure_engine()
	var success: bool = bool(_engine.toggle_dead_group(coord))
	_flush_engine_events()
	return success


func resume_play() -> bool:
	_ensure_engine()
	var success: bool = bool(_engine.resume_play())
	_flush_engine_events()
	return success


func confirm_scoring() -> bool:
	_ensure_engine()
	var success: bool = bool(_engine.confirm_scoring())
	_flush_engine_events()
	return success


func get_marked_dead_keys() -> Array:
	_ensure_engine()
	return _engine.get_marked_dead_keys()


func get_scoring_board():
	_ensure_engine()
	return _engine.get_scoring_board()


func build_turn_snapshot() -> Dictionary:
	_ensure_engine()
	return _engine.build_turn_snapshot()


func build_observation(action_codec = null, rules_config: Dictionary = {}) -> Dictionary:
	_ensure_engine()
	return _engine.build_observation(action_codec, rules_config)


func is_native_engine_active() -> bool:
	_ensure_engine()
	return bool(_engine.get_backend_info().get("native_active", false))


func get_engine_backend_info() -> Dictionary:
	_ensure_engine()
	return _engine.get_backend_info()


func _ensure_engine() -> void:
	var needs_new_engine := _engine == null
	if not needs_new_engine:
		var backend_info: Dictionary = _engine.get_backend_info()
		needs_new_engine = bool(backend_info.get("requested_native", false)) != prefer_native_engine
	if not needs_new_engine:
		return
	_engine = EngineBridgeFactoryRef.create_engine(prefer_native_engine, board_radius)


func _flush_engine_events() -> void:
	_ensure_engine()
	for event in _engine.consume_events():
		match String(event.get("type", "")):
			MatchEngineRef.EVENT_BOARD_INITIALIZED:
				board_initialized.emit(event.get("board", board))
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

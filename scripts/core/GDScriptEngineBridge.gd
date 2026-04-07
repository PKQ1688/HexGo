class_name GDScriptEngineBridge
extends "res://scripts/core/BaseEngineBridge.gd"

const MatchEngineRef = preload("res://scripts/core/MatchEngine.gd")

var _engine: MatchEngineRef = MatchEngineRef.new()


func _init(preferred_radius: int = 5, requested_native_value: bool = false, backend_status_value: String = "") -> void:
	backend_name = "gdscript"
	requested_native = requested_native_value
	backend_status = backend_status_value if backend_status_value != "" else "Using built-in GDScript engine."
	_engine.board_radius = preferred_radius


func is_available() -> bool:
	return true


func get_board_radius() -> int:
	return _engine.board_radius


func set_board_radius(value: int) -> void:
	_engine.board_radius = value


func get_board():
	return _engine.board


func get_current_player() -> int:
	return _engine.current_player


func set_current_player(value: int) -> void:
	_engine.current_player = value


func get_phase() -> int:
	return _engine.phase


func set_phase(value: int) -> void:
	_engine.phase = value


func get_consecutive_passes() -> int:
	return _engine.consecutive_passes


func set_consecutive_passes(value: int) -> void:
	_engine.consecutive_passes = value


func get_move_history() -> Array:
	return _engine.move_history


func set_move_history(value: Array) -> void:
	_engine.move_history = value


func get_scores() -> Dictionary:
	return _engine.scores


func set_scores(value: Dictionary) -> void:
	_engine.scores = value


func get_score_breakdown() -> Dictionary:
	return _engine.score_breakdown


func set_score_breakdown(value: Dictionary) -> void:
	_engine.score_breakdown = value


func get_marked_dead_stones() -> Dictionary:
	return _engine.marked_dead_stones


func set_marked_dead_stones(value: Dictionary) -> void:
	_engine.marked_dead_stones = value


func get_previous_board_signature() -> String:
	return _engine.previous_board_signature


func set_previous_board_signature(value: String) -> void:
	_engine.previous_board_signature = value


func get_current_board_signature() -> String:
	return _engine.current_board_signature


func set_current_board_signature(value: String) -> void:
	_engine.current_board_signature = value


func get_resume_player_after_scoring() -> int:
	return _engine.resume_player_after_scoring


func set_resume_player_after_scoring(value: int) -> void:
	_engine.resume_player_after_scoring = value


func setup_game(radius: int = get_board_radius()) -> void:
	_engine.setup_game(radius)


func switch_player() -> void:
	_engine.switch_player()


func record_pass() -> void:
	_engine.record_pass()


func can_pass() -> bool:
	return _engine.can_pass()


func can_place_at(coord) -> bool:
	return _engine.can_place_at(coord)


func execute_turn(coord) -> bool:
	return _engine.execute_turn(coord)


func is_scoring_phase() -> bool:
	return _engine.is_scoring_phase()


func get_visible_threats() -> Dictionary:
	return _engine.get_visible_threats()


func can_toggle_dead_at(coord) -> bool:
	return _engine.can_toggle_dead_at(coord)


func toggle_dead_group(coord) -> bool:
	return _engine.toggle_dead_group(coord)


func resume_play() -> bool:
	return _engine.resume_play()


func confirm_scoring() -> bool:
	return _engine.confirm_scoring()


func get_marked_dead_keys() -> Array:
	return _engine.get_marked_dead_keys()


func get_scoring_board():
	return _engine.get_scoring_board()


func build_turn_snapshot() -> Dictionary:
	return _engine.build_turn_snapshot()


func build_observation(action_codec = null, rules_config: Dictionary = {}) -> Dictionary:
	return _engine.build_observation(action_codec, rules_config)


func consume_events() -> Array:
	return _engine.consume_events()

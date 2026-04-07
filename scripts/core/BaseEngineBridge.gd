class_name BaseEngineBridge
extends RefCounted

const HexBoardRef = preload("res://scripts/core/HexBoard.gd")

var backend_name: String = "unknown"
var backend_status: String = ""
var requested_native: bool = false

var board_radius: int:
	get:
		return get_board_radius()
	set(value):
		set_board_radius(value)

var board:
	get:
		return get_board()

var current_player: int:
	get:
		return get_current_player()
	set(value):
		set_current_player(value)

var phase: int:
	get:
		return get_phase()
	set(value):
		set_phase(value)

var consecutive_passes: int:
	get:
		return get_consecutive_passes()
	set(value):
		set_consecutive_passes(value)

var move_history: Array:
	get:
		return get_move_history()
	set(value):
		set_move_history(value)

var scores: Dictionary:
	get:
		return get_scores()
	set(value):
		set_scores(value)

var score_breakdown: Dictionary:
	get:
		return get_score_breakdown()
	set(value):
		set_score_breakdown(value)

var marked_dead_stones: Dictionary:
	get:
		return get_marked_dead_stones()
	set(value):
		set_marked_dead_stones(value)

var previous_board_signature: String:
	get:
		return get_previous_board_signature()
	set(value):
		set_previous_board_signature(value)

var current_board_signature: String:
	get:
		return get_current_board_signature()
	set(value):
		set_current_board_signature(value)

var resume_player_after_scoring: int:
	get:
		return get_resume_player_after_scoring()
	set(value):
		set_resume_player_after_scoring(value)


func is_available() -> bool:
	return false


func is_native_backend() -> bool:
	return backend_name == "native" and is_available()


func get_backend_info() -> Dictionary:
	return {
		"requested_native": requested_native,
		"active_backend": backend_name,
		"native_active": is_native_backend(),
		"status": backend_status,
	}


func get_board_radius() -> int:
	return 0


func set_board_radius(_value: int) -> void:
	pass


func get_board():
	return null


func get_current_player() -> int:
	return 0


func set_current_player(_value: int) -> void:
	pass


func get_phase() -> int:
	return 0


func set_phase(_value: int) -> void:
	pass


func get_consecutive_passes() -> int:
	return 0


func set_consecutive_passes(_value: int) -> void:
	pass


func get_move_history() -> Array:
	return []


func set_move_history(_value: Array) -> void:
	pass


func get_scores() -> Dictionary:
	return {}


func set_scores(_value: Dictionary) -> void:
	pass


func get_score_breakdown() -> Dictionary:
	return {}


func set_score_breakdown(_value: Dictionary) -> void:
	pass


func get_marked_dead_stones() -> Dictionary:
	return {}


func set_marked_dead_stones(_value: Dictionary) -> void:
	pass


func get_previous_board_signature() -> String:
	return ""


func set_previous_board_signature(_value: String) -> void:
	pass


func get_current_board_signature() -> String:
	return ""


func set_current_board_signature(_value: String) -> void:
	pass


func get_resume_player_after_scoring() -> int:
	return 0


func set_resume_player_after_scoring(_value: int) -> void:
	pass


func setup_game(_radius: int = get_board_radius()) -> void:
	pass


func switch_player() -> void:
	pass


func record_pass() -> void:
	pass


func can_pass() -> bool:
	return false


func can_place_at(_coord) -> bool:
	return false


func execute_turn(_coord) -> bool:
	return false


func is_scoring_phase() -> bool:
	return false


func get_visible_threats() -> Dictionary:
	return {}


func can_toggle_dead_at(_coord) -> bool:
	return false


func toggle_dead_group(_coord) -> bool:
	return false


func resume_play() -> bool:
	return false


func confirm_scoring() -> bool:
	return false


func get_marked_dead_keys() -> Array:
	return []


func get_scoring_board():
	var board_copy := HexBoardRef.new()
	board_copy.initialize(get_board_radius())
	return board_copy


func build_turn_snapshot() -> Dictionary:
	return {}


func build_observation(_action_codec = null, _rules_config: Dictionary = {}) -> Dictionary:
	return {}


func consume_events() -> Array:
	return []

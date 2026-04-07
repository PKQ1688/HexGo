class_name EngineProtocol
extends RefCounted

const PROTOCOL_VERSION := 1
const PLAYER_BLACK := 0
const PLAYER_WHITE := 1
const PHASE_WAITING := 0
const PHASE_PLACING := 1
const PHASE_RESOLVING_CAPTURE := 2
const PHASE_RESOLVING_TERRITORY := 3
const PHASE_SCORING := 4
const PHASE_GAME_OVER := 5


static func player_name(player: int) -> String:
	return "black" if player == PLAYER_BLACK else "white"


static func phase_name(phase: int) -> String:
	match phase:
		PHASE_PLACING:
			return "placing"
		PHASE_RESOLVING_CAPTURE:
			return "resolving_capture"
		PHASE_RESOLVING_TERRITORY:
			return "resolving_territory"
		PHASE_SCORING:
			return "scoring"
		PHASE_GAME_OVER:
			return "game_over"
		_:
			return "waiting"


static func build_rules_config(board_radius: int, rules_config: Dictionary = {}) -> Dictionary:
	return {
		"board_radius": board_radius,
		"scoring_mode": String(rules_config.get("scoring_mode", "manual_review")),
	}


static func serialize_coord(coord) -> Array:
	if coord == null:
		return []
	return [int(coord.q), int(coord.r)]


static func serialize_coords(coords: Array) -> Array:
	var result: Array = []
	for coord in coords:
		result.append(serialize_coord(coord))
	return result


static func serialize_scores(scores: Dictionary) -> Dictionary:
	return {
		"black": int(scores.get(PLAYER_BLACK, 0)),
		"white": int(scores.get(PLAYER_WHITE, 0)),
	}


static func serialize_score_breakdown(score_breakdown: Dictionary) -> Dictionary:
	return {
		"black": _serialize_player_breakdown(score_breakdown.get(PLAYER_BLACK, {})),
		"white": _serialize_player_breakdown(score_breakdown.get(PLAYER_WHITE, {})),
	}


static func serialize_observation(state, action_codec = null, rules_config: Dictionary = {}) -> Dictionary:
	var ordered_coords := _ordered_coords(state.board, action_codec)
	var legal_action_mask := _legal_action_mask(state, ordered_coords, action_codec)
	var legal_action_indices: Array = []
	for action_index in range(legal_action_mask.size()):
		if int(legal_action_mask[action_index]) != 0:
			legal_action_indices.append(action_index)

	var pass_action_index := ordered_coords.size()
	if action_codec != null and action_codec.has_method("pass_action_index"):
		pass_action_index = int(action_codec.pass_action_index())

	return {
		"board": state.board.clone(),
		"current_player": int(state.current_player),
		"previous_board_signature": String(state.previous_board_signature),
		"current_board_signature": String(state.current_board_signature),
		"consecutive_passes": int(state.consecutive_passes),
		"scores": state.scores.duplicate(true),
		"score_breakdown": state.score_breakdown.duplicate(true),
		"move_count": int(state.move_history.size()),
		"board_radius": int(state.board_radius),
		"protocol_version": PROTOCOL_VERSION,
		"rules": build_rules_config(int(state.board_radius), rules_config),
		"phase": int(state.phase),
		"phase_name": phase_name(int(state.phase)),
		"current_player_name": player_name(int(state.current_player)),
		"scores_by_player": serialize_scores(state.scores),
		"score_breakdown_by_player": serialize_score_breakdown(state.score_breakdown),
		"marked_dead_keys": _sorted_string_array(state.get_marked_dead_keys()),
		"ordered_coords": serialize_coords(ordered_coords),
		"cells": _serialize_cells(state.board, ordered_coords),
		"action_count": ordered_coords.size() + 1,
		"pass_action_index": pass_action_index,
		"legal_action_mask": legal_action_mask,
		"legal_action_indices": legal_action_indices,
		"result": _build_result(int(state.phase), state.scores),
	}


static func transport_observation(snapshot: Dictionary) -> Dictionary:
	return {
		"protocol_version": int(snapshot.get("protocol_version", PROTOCOL_VERSION)),
		"rules": snapshot.get("rules", {}),
		"board_radius": int(snapshot.get("board_radius", 0)),
		"phase_id": int(snapshot.get("phase", PHASE_WAITING)),
		"phase": String(snapshot.get("phase_name", phase_name(int(snapshot.get("phase", PHASE_WAITING))))),
		"current_player": int(snapshot.get("current_player", PLAYER_BLACK)),
		"current_player_name": String(snapshot.get("current_player_name", player_name(int(snapshot.get("current_player", PLAYER_BLACK))))),
		"consecutive_passes": int(snapshot.get("consecutive_passes", 0)),
		"move_count": int(snapshot.get("move_count", 0)),
		"previous_board_signature": String(snapshot.get("previous_board_signature", "")),
		"current_board_signature": String(snapshot.get("current_board_signature", "")),
		"scores": snapshot.get("scores_by_player", {}),
		"score_breakdown": snapshot.get("score_breakdown_by_player", {}),
		"marked_dead_keys": snapshot.get("marked_dead_keys", []),
		"ordered_coords": snapshot.get("ordered_coords", []),
		"cells": snapshot.get("cells", []),
		"action_count": int(snapshot.get("action_count", 0)),
		"pass_action_index": int(snapshot.get("pass_action_index", -1)),
		"legal_action_mask": snapshot.get("legal_action_mask", []),
		"legal_action_indices": snapshot.get("legal_action_indices", []),
		"result": snapshot.get("result", {}),
	}


static func serialize_event(event: Dictionary) -> Dictionary:
	var serialized := {
		"type": String(event.get("type", "")),
	}
	if event.has("player"):
		var player := int(event.get("player", PLAYER_BLACK))
		serialized["player"] = player
		serialized["player_name"] = player_name(player)
	if event.has("coord"):
		serialized["coord"] = serialize_coord(event.get("coord"))
	if event.has("coords"):
		serialized["coords"] = serialize_coords(event.get("coords", []))
	if event.has("scores"):
		serialized["scores"] = serialize_scores(event.get("scores", {}))
	if event.has("marked_dead_keys"):
		serialized["marked_dead_keys"] = _sorted_string_array(event.get("marked_dead_keys", []))
	if event.has("board") and event.get("board") != null:
		serialized["board_radius"] = int(event.get("board").board_radius)
	return serialized


static func serialize_events(events: Array) -> Array:
	var serialized: Array = []
	for event in events:
		serialized.append(serialize_event(event))
	return serialized


static func _ordered_coords(board, action_codec = null) -> Array:
	if action_codec != null and action_codec.has_method("get_ordered_coords"):
		return action_codec.get_ordered_coords()
	var ordered_coords: Array = []
	for coord in board.all_coords:
		ordered_coords.append(coord.duplicated())
	ordered_coords.sort_custom(func(a, b):
		if a.q != b.q:
			return a.q < b.q
		if a.r != b.r:
			return a.r < b.r
		return a.s < b.s
	)
	return ordered_coords


static func _serialize_cells(board, ordered_coords: Array) -> Array:
	var cells: Array = []
	for coord in ordered_coords:
		cells.append(int(board.get_cell(coord)))
	return cells


static func _legal_action_mask(state, ordered_coords: Array, action_codec = null) -> Array:
	if action_codec != null and action_codec.has_method("legal_action_mask"):
		return action_codec.legal_action_mask(state)
	var mask: Array = []
	for coord in ordered_coords:
		mask.append(1 if state.can_place_at(coord) else 0)
	mask.append(1 if state.can_pass() else 0)
	return mask


static func _build_result(phase: int, scores: Dictionary) -> Dictionary:
	if phase != PHASE_GAME_OVER:
		return {
			"is_game_over": false,
			"winner": "",
			"margin": 0,
		}
	var black_score := int(scores.get(PLAYER_BLACK, 0))
	var white_score := int(scores.get(PLAYER_WHITE, 0))
	var winner := ""
	if black_score > white_score:
		winner = "black"
	elif white_score > black_score:
		winner = "white"
	return {
		"is_game_over": true,
		"winner": winner,
		"margin": abs(black_score - white_score),
	}


static func _serialize_player_breakdown(entry: Dictionary) -> Dictionary:
	return {
		"pieces": int(entry.get("pieces", 0)),
		"territory": int(entry.get("territory", 0)),
		"total": int(entry.get("total", 0)),
	}


static func _sorted_string_array(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result

class_name NativeBridgeCodec
extends RefCounted

const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")


static func export_state(state: Dictionary, marked_dead_keys: Array) -> Dictionary:
	return {
		"board_radius": int(state.get("board_radius", 5)),
		"current_player": int(state.get("current_player", 0)),
		"phase": int(state.get("phase", 0)),
		"consecutive_passes": int(state.get("consecutive_passes", 0)),
		"move_history": state.get("move_history", []).duplicate(true),
		"scores": state.get("scores", {}).duplicate(true),
		"score_breakdown": state.get("score_breakdown", {}).duplicate(true),
		"marked_dead_keys": marked_dead_keys.duplicate(),
		"previous_board_signature": String(state.get("previous_board_signature", "")),
		"current_board_signature": String(state.get("current_board_signature", "")),
		"resume_player_after_scoring": int(state.get("resume_player_after_scoring", 0)),
	}


static func import_state(snapshot: Dictionary, current_state: Dictionary) -> Dictionary:
	var board_radius := int(snapshot.get("board_radius", current_state.get("board_radius", 5)))
	var board = board_from_snapshot(snapshot, board_radius)
	return {
		"board": board,
		"board_radius": int(board.board_radius),
		"current_player": int(snapshot.get("current_player", current_state.get("current_player", 0))),
		"phase": int(snapshot.get("phase", snapshot.get("phase_id", current_state.get("phase", 0)))),
		"consecutive_passes": int(snapshot.get("consecutive_passes", current_state.get("consecutive_passes", 0))),
		"move_history": snapshot.get("move_history", current_state.get("move_history", [])).duplicate(true),
		"scores": decode_scores(snapshot.get("scores", current_state.get("scores", {})), current_state.get("scores", {})),
		"score_breakdown": decode_score_breakdown(snapshot.get("score_breakdown", current_state.get("score_breakdown", {})), current_state.get("score_breakdown", {})),
		"marked_dead_stones": decode_marked_dead_stones(snapshot.get("marked_dead_keys", current_state.get("marked_dead_stones", {}).keys())),
		"previous_board_signature": String(snapshot.get("previous_board_signature", current_state.get("previous_board_signature", ""))),
		"current_board_signature": String(snapshot.get("current_board_signature", current_state.get("current_board_signature", ""))),
		"resume_player_after_scoring": int(snapshot.get("resume_player_after_scoring", current_state.get("resume_player_after_scoring", 0))),
	}


static func hydrate_events(events: Array, board) -> Array:
	var hydrated: Array = []
	for raw_event in events:
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw_event.duplicate(true)
		if event.has("coord"):
			event["coord"] = coord_from_value(event["coord"])
		if event.has("coords"):
			event["coords"] = coords_from_value(event["coords"])
		if event.has("scores"):
			event["scores"] = decode_scores(event["scores"])
		if (event.has("board_radius") or String(event.get("type", "")) == "board_initialized") and not event.has("board"):
			event["board"] = board
		hydrated.append(event)
	return hydrated


static func board_from_snapshot(snapshot: Dictionary, fallback_radius: int = 5):
	var source_board = snapshot.get("board")
	if source_board != null and source_board is HexBoardRef:
		return source_board.clone()

	var board := HexBoardRef.new()
	board.initialize(int(snapshot.get("board_radius", fallback_radius)))
	var ordered_coords: Array = snapshot.get("ordered_coords", [])
	var cells: Array = snapshot.get("cells", [])
	var limit: int = min(ordered_coords.size(), cells.size())
	for index in range(limit):
		var coord = coord_from_value(ordered_coords[index])
		if coord == null:
			continue
		board.set_cell(coord, int(cells[index]))
	return board


static func decode_scores(raw_scores, fallback: Dictionary = {}) -> Dictionary:
	if typeof(raw_scores) != TYPE_DICTIONARY:
		return fallback.duplicate(true) if not fallback.is_empty() else {0: 0, 1: 0}
	if raw_scores.has(0) or raw_scores.has(1):
		return raw_scores.duplicate(true)
	return {
		0: int(raw_scores.get("black", 0)),
		1: int(raw_scores.get("white", 0)),
	}


static func decode_score_breakdown(raw_breakdown, fallback: Dictionary = {}) -> Dictionary:
	if typeof(raw_breakdown) != TYPE_DICTIONARY:
		return fallback.duplicate(true)
	if raw_breakdown.has(0) or raw_breakdown.has(1):
		return raw_breakdown.duplicate(true)
	return {
		0: _decode_player_breakdown(raw_breakdown.get("black", {})),
		1: _decode_player_breakdown(raw_breakdown.get("white", {})),
	}


static func decode_marked_dead_stones(marked_dead_keys) -> Dictionary:
	var dead_stones: Dictionary = {}
	var keys: Array = []
	if typeof(marked_dead_keys) == TYPE_DICTIONARY:
		keys = marked_dead_keys.keys()
	elif typeof(marked_dead_keys) == TYPE_ARRAY:
		keys = marked_dead_keys
	for item in keys:
		var key: String = String(item)
		if key == "":
			continue
		dead_stones[key] = true
	return dead_stones


static func coords_from_value(raw_coords) -> Array:
	var coords: Array = []
	if typeof(raw_coords) != TYPE_ARRAY:
		return coords
	for raw_coord in raw_coords:
		var coord = coord_from_value(raw_coord)
		if coord != null:
			coords.append(coord)
	return coords


static func coord_from_value(raw_coord):
	if raw_coord == null:
		return null
	if raw_coord is HexCoordRef:
		return raw_coord.duplicated()
	if raw_coord is Vector2i:
		return HexCoordRef.new(int(raw_coord.x), int(raw_coord.y))
	if typeof(raw_coord) == TYPE_ARRAY and raw_coord.size() >= 2:
		return HexCoordRef.new(int(raw_coord[0]), int(raw_coord[1]))
	if typeof(raw_coord) == TYPE_DICTIONARY and raw_coord.has("q") and raw_coord.has("r"):
		return HexCoordRef.new(int(raw_coord["q"]), int(raw_coord["r"]))
	return null


static func native_coord_argument(coord) -> Vector2i:
	var decoded_coord = coord_from_value(coord)
	if decoded_coord == null:
		return Vector2i.ZERO
	return Vector2i(decoded_coord.q, decoded_coord.r)


static func _decode_player_breakdown(entry) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {"pieces": 0, "territory": 0, "total": 0}
	return {
		"pieces": int(entry.get("pieces", 0)),
		"territory": int(entry.get("territory", 0)),
		"total": int(entry.get("total", 0)),
	}

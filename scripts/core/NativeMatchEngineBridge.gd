class_name NativeMatchEngineBridge
extends "res://scripts/core/BaseEngineBridge.gd"

const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")
const EngineProtocolRef = preload("res://scripts/core/EngineProtocol.gd")
const ScoreCalculatorRef = preload("res://scripts/core/ScoreCalculator.gd")
const ThreatAnalyzerRef = preload("res://scripts/core/ThreatAnalyzer.gd")

const NATIVE_CLASS_CANDIDATES := [
	"HexGoNativeEngine",
	"HexGoNativeMatchEngine",
]

var _native_engine = null
var _board_radius: int = 5
var _board: HexBoardRef = HexBoardRef.new()
var _current_player: int = 0
var _phase: int = 0
var _consecutive_passes: int = 0
var _move_history: Array = []
var _scores: Dictionary = {0: 0, 1: 0}
var _score_breakdown: Dictionary = {}
var _marked_dead_stones: Dictionary = {}
var _previous_board_signature: String = ""
var _current_board_signature: String = ""
var _resume_player_after_scoring: int = 0


func _init(preferred_radius: int = 5) -> void:
	backend_name = "native"
	requested_native = true
	_board_radius = preferred_radius
	_board.initialize(_board_radius)
	backend_status = _build_unavailable_status()
	var class_name := _resolve_native_class_name()
	if class_name == "":
		return
	_native_engine = ClassDB.instantiate(class_name)
	if _native_engine == null:
		backend_status = "Native engine class '%s' could not be instantiated." % class_name
		return
	if not _native_engine.has_method("setup_game") or not _native_engine.has_method("consume_events"):
		_native_engine = null
		backend_status = "Native engine '%s' does not implement the required bridge contract yet." % class_name
		return
	backend_status = "Using native engine bridge class '%s'." % class_name
	setup_game(preferred_radius)


static func is_supported() -> bool:
	return _resolve_native_class_name() != ""


static func _resolve_native_class_name() -> String:
	for class_name in NATIVE_CLASS_CANDIDATES:
		if ClassDB.class_exists(class_name):
			return class_name
	return ""


func is_available() -> bool:
	return _native_engine != null


func get_board_radius() -> int:
	return _board_radius


func set_board_radius(value: int) -> void:
	_board_radius = value
	if _board.board_radius != _board_radius:
		_board.initialize(_board_radius)
	_push_state_to_native()


func get_board():
	return _board


func get_current_player() -> int:
	return _current_player


func set_current_player(value: int) -> void:
	_current_player = value
	_push_state_to_native()


func get_phase() -> int:
	return _phase


func set_phase(value: int) -> void:
	_phase = value
	_push_state_to_native()


func get_consecutive_passes() -> int:
	return _consecutive_passes


func set_consecutive_passes(value: int) -> void:
	_consecutive_passes = value
	_push_state_to_native()


func get_move_history() -> Array:
	return _move_history


func set_move_history(value: Array) -> void:
	_move_history = value
	_push_state_to_native()


func get_scores() -> Dictionary:
	return _scores


func set_scores(value: Dictionary) -> void:
	_scores = value
	_push_state_to_native()


func get_score_breakdown() -> Dictionary:
	return _score_breakdown


func set_score_breakdown(value: Dictionary) -> void:
	_score_breakdown = value
	_push_state_to_native()


func get_marked_dead_stones() -> Dictionary:
	return _marked_dead_stones


func set_marked_dead_stones(value: Dictionary) -> void:
	_marked_dead_stones = value
	_push_state_to_native()


func get_previous_board_signature() -> String:
	return _previous_board_signature


func set_previous_board_signature(value: String) -> void:
	_previous_board_signature = value
	_push_state_to_native()


func get_current_board_signature() -> String:
	return _current_board_signature


func set_current_board_signature(value: String) -> void:
	_current_board_signature = value
	_push_state_to_native()


func get_resume_player_after_scoring() -> int:
	return _resume_player_after_scoring


func set_resume_player_after_scoring(value: int) -> void:
	_resume_player_after_scoring = value
	_push_state_to_native()


func setup_game(radius: int = get_board_radius()) -> void:
	_board_radius = radius
	_board.initialize(_board_radius)
	if not is_available():
		return
	_native_engine.call("setup_game", radius)
	_sync_from_native()


func switch_player() -> void:
	if not is_available():
		_current_player = 1 if _current_player == 0 else 0
		return
	_native_engine.call("switch_player")
	_sync_from_native()


func record_pass() -> void:
	if not is_available():
		return
	_native_engine.call("record_pass")
	_sync_from_native()


func can_pass() -> bool:
	if not is_available():
		return false
	return bool(_native_engine.call("can_pass"))


func can_place_at(coord) -> bool:
	if not is_available():
		return false
	return bool(_native_engine.call("can_place_at", _native_coord_argument(coord)))


func execute_turn(coord) -> bool:
	if not is_available():
		return false
	var success := bool(_native_engine.call("execute_turn", _native_coord_argument(coord)))
	_sync_from_native()
	return success


func is_scoring_phase() -> bool:
	if not is_available():
		return _phase == 4
	return bool(_native_engine.call("is_scoring_phase"))


func get_visible_threats() -> Dictionary:
	if is_available() and _native_engine.has_method("get_visible_threats"):
		var threat_map = _native_engine.call("get_visible_threats")
		if typeof(threat_map) == TYPE_DICTIONARY:
			return threat_map
	return _local_visible_threats()


func can_toggle_dead_at(coord) -> bool:
	if not is_available():
		return false
	return bool(_native_engine.call("can_toggle_dead_at", _native_coord_argument(coord)))


func toggle_dead_group(coord) -> bool:
	if not is_available():
		return false
	var success := bool(_native_engine.call("toggle_dead_group", _native_coord_argument(coord)))
	_sync_from_native()
	return success


func resume_play() -> bool:
	if not is_available():
		return false
	var success := bool(_native_engine.call("resume_play"))
	_sync_from_native()
	return success


func confirm_scoring() -> bool:
	if not is_available():
		return false
	var success := bool(_native_engine.call("confirm_scoring"))
	_sync_from_native()
	return success


func get_marked_dead_keys() -> Array:
	var keys := _marked_dead_stones.keys()
	keys.sort()
	return keys


func get_scoring_board():
	if is_available() and _native_engine.has_method("get_scoring_board"):
		var scoring_board = _native_engine.call("get_scoring_board")
		if scoring_board != null and scoring_board is HexBoardRef:
			return scoring_board
		if typeof(scoring_board) == TYPE_DICTIONARY:
			var decoded_board = _board_from_snapshot(scoring_board)
			if decoded_board != null:
				return decoded_board
	return ScoreCalculatorRef.build_scoring_board(_board, _marked_dead_stones)


func build_turn_snapshot() -> Dictionary:
	if is_available() and _native_engine.has_method("build_turn_snapshot"):
		var snapshot = _native_engine.call("build_turn_snapshot")
		if typeof(snapshot) == TYPE_DICTIONARY:
			return snapshot
	return {
		"board": _board.clone(),
		"current_player": _current_player,
		"previous_board_signature": _previous_board_signature,
		"current_board_signature": _current_board_signature,
		"consecutive_passes": _consecutive_passes,
		"scores": _scores.duplicate(true),
		"score_breakdown": _score_breakdown.duplicate(true),
		"move_count": _move_history.size(),
		"board_radius": _board_radius,
	}


func build_observation(action_codec = null, rules_config: Dictionary = {}) -> Dictionary:
	if is_available() and _native_engine.has_method("build_observation"):
		var observation = _native_engine.call("build_observation", action_codec, rules_config)
		if typeof(observation) == TYPE_DICTIONARY:
			return observation
	return EngineProtocolRef.serialize_observation(self, action_codec, rules_config)


func consume_events() -> Array:
	if not is_available():
		return []
	var events = _native_engine.call("consume_events")
	if typeof(events) != TYPE_ARRAY:
		return []
	return _hydrate_events(events)


func _push_state_to_native() -> void:
	if not is_available() or not _native_engine.has_method("import_state"):
		return
	_native_engine.call("import_state", _export_state_for_native())


func _sync_from_native() -> void:
	if not is_available() or not _native_engine.has_method("export_state"):
		return
	var snapshot = _native_engine.call("export_state")
	if typeof(snapshot) != TYPE_DICTIONARY:
		return
	_import_state(snapshot)


func _export_state_for_native() -> Dictionary:
	return {
		"board_radius": _board_radius,
		"current_player": _current_player,
		"phase": _phase,
		"consecutive_passes": _consecutive_passes,
		"move_history": _move_history.duplicate(true),
		"scores": _scores.duplicate(true),
		"score_breakdown": _score_breakdown.duplicate(true),
		"marked_dead_keys": get_marked_dead_keys(),
		"previous_board_signature": _previous_board_signature,
		"current_board_signature": _current_board_signature,
		"resume_player_after_scoring": _resume_player_after_scoring,
	}


func _import_state(snapshot: Dictionary) -> void:
	_board_radius = int(snapshot.get("board_radius", _board_radius))
	_current_player = int(snapshot.get("current_player", _current_player))
	_phase = int(snapshot.get("phase", snapshot.get("phase_id", _phase)))
	_consecutive_passes = int(snapshot.get("consecutive_passes", _consecutive_passes))
	_move_history = snapshot.get("move_history", _move_history).duplicate(true)
	_previous_board_signature = String(snapshot.get("previous_board_signature", _previous_board_signature))
	_current_board_signature = String(snapshot.get("current_board_signature", _current_board_signature))
	_resume_player_after_scoring = int(snapshot.get("resume_player_after_scoring", _resume_player_after_scoring))
	_scores = _decode_scores(snapshot.get("scores", _scores))
	_score_breakdown = _decode_score_breakdown(snapshot.get("score_breakdown", _score_breakdown))
	_marked_dead_stones = _decode_marked_dead_stones(snapshot.get("marked_dead_keys", _marked_dead_stones.keys()))
	_rebuild_board(snapshot)


func _rebuild_board(snapshot: Dictionary) -> void:
	var source_board = snapshot.get("board")
	if source_board != null and source_board is HexBoardRef:
		_board = source_board.clone()
		_board_radius = _board.board_radius
		return

	_board.initialize(_board_radius)
	var ordered_coords := snapshot.get("ordered_coords", [])
	var cells := snapshot.get("cells", [])
	var limit := min(ordered_coords.size(), cells.size())
	for index in range(limit):
		var coord = _coord_from_value(ordered_coords[index])
		if coord == null:
			continue
		_board.set_cell(coord, int(cells[index]))


func _hydrate_events(events: Array) -> Array:
	var hydrated: Array = []
	for raw_event in events:
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw_event.duplicate(true)
		if event.has("coord"):
			event["coord"] = _coord_from_value(event["coord"])
		if event.has("coords"):
			event["coords"] = _coords_from_value(event["coords"])
		if event.has("scores"):
			event["scores"] = _decode_scores(event["scores"])
		if (event.has("board_radius") or String(event.get("type", "")) == "board_initialized") and not event.has("board"):
			event["board"] = _board
		hydrated.append(event)
	return hydrated


func _decode_scores(raw_scores) -> Dictionary:
	if typeof(raw_scores) != TYPE_DICTIONARY:
		return {0: 0, 1: 0}
	if raw_scores.has(0) or raw_scores.has(1):
		return raw_scores.duplicate(true)
	return {
		0: int(raw_scores.get("black", 0)),
		1: int(raw_scores.get("white", 0)),
	}


func _decode_score_breakdown(raw_breakdown) -> Dictionary:
	if typeof(raw_breakdown) != TYPE_DICTIONARY:
		return {}
	if raw_breakdown.has(0) or raw_breakdown.has(1):
		return raw_breakdown.duplicate(true)
	return {
		0: _decode_player_breakdown(raw_breakdown.get("black", {})),
		1: _decode_player_breakdown(raw_breakdown.get("white", {})),
	}


func _decode_player_breakdown(entry) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {"pieces": 0, "territory": 0, "total": 0}
	return {
		"pieces": int(entry.get("pieces", 0)),
		"territory": int(entry.get("territory", 0)),
		"total": int(entry.get("total", 0)),
	}


func _decode_marked_dead_stones(marked_dead_keys: Array) -> Dictionary:
	var dead_stones: Dictionary = {}
	for item in marked_dead_keys:
		var key: String = String(item)
		if key == "":
			continue
		dead_stones[key] = true
	return dead_stones


func _coords_from_value(raw_coords) -> Array:
	var coords: Array = []
	if typeof(raw_coords) != TYPE_ARRAY:
		return coords
	for raw_coord in raw_coords:
		var coord = _coord_from_value(raw_coord)
		if coord != null:
			coords.append(coord)
	return coords


func _coord_from_value(raw_coord):
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


func _native_coord_argument(coord) -> Vector2i:
	var decoded_coord = _coord_from_value(coord)
	if decoded_coord == null:
		return Vector2i.ZERO
	return Vector2i(decoded_coord.q, decoded_coord.r)


func _board_from_snapshot(snapshot: Dictionary):
	var board := HexBoardRef.new()
	var radius := int(snapshot.get("board_radius", _board_radius))
	board.initialize(radius)
	var ordered_coords := snapshot.get("ordered_coords", [])
	var cells := snapshot.get("cells", [])
	var limit := min(ordered_coords.size(), cells.size())
	for index in range(limit):
		var coord = _coord_from_value(ordered_coords[index])
		if coord == null:
			continue
		board.set_cell(coord, int(cells[index]))
	return board


func _local_visible_threats() -> Dictionary:
	if _phase == 4 or _phase == 5:
		return {}
	var threat_map: Dictionary = ThreatAnalyzerRef.analyze(_board)
	var visible_threats: Dictionary = {}
	for key in threat_map:
		var entry: Dictionary = threat_map[key]
		if String(entry.get(ThreatAnalyzerRef.THREAT_LEVEL_KEY, ThreatAnalyzerRef.THREAT_LEVEL_SAFE)) == ThreatAnalyzerRef.THREAT_LEVEL_SAFE:
			continue
		visible_threats[key] = entry
	return visible_threats


func _build_unavailable_status() -> String:
	return "Native engine bridge unavailable. Build and register one of %s through GDExtension." % [", ".join(NATIVE_CLASS_CANDIDATES)]

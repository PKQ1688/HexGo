class_name NativeMatchEngineBridge
extends "res://scripts/core/BaseEngineBridge.gd"

const EngineProtocolRef = preload("res://scripts/core/EngineProtocol.gd")
const NativeBridgeCodecRef = preload("res://scripts/core/NativeBridgeCodec.gd")
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
	var native_class_name: String = _resolve_native_class_name()
	if native_class_name == "":
		return
	_native_engine = ClassDB.instantiate(native_class_name)
	if _native_engine == null:
		backend_status = "Native engine class '%s' could not be instantiated." % native_class_name
		return
	if not _native_engine.has_method("setup_game") or not _native_engine.has_method("consume_events"):
		_native_engine = null
		backend_status = "Native engine '%s' does not implement the required bridge contract yet." % native_class_name
		return
	backend_status = "Using native engine bridge class '%s'." % native_class_name
	setup_game(preferred_radius)


static func is_supported() -> bool:
	return _resolve_native_class_name() != ""


static func _resolve_native_class_name() -> String:
	for candidate in NATIVE_CLASS_CANDIDATES:
		if ClassDB.class_exists(candidate):
			return candidate
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
	return bool(_native_engine.call("can_place_at", NativeBridgeCodecRef.native_coord_argument(coord)))


func execute_turn(coord) -> bool:
	if not is_available():
		return false
	var success := bool(_native_engine.call("execute_turn", NativeBridgeCodecRef.native_coord_argument(coord)))
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
	return bool(_native_engine.call("can_toggle_dead_at", NativeBridgeCodecRef.native_coord_argument(coord)))


func toggle_dead_group(coord) -> bool:
	if not is_available():
		return false
	var success := bool(_native_engine.call("toggle_dead_group", NativeBridgeCodecRef.native_coord_argument(coord)))
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
			var decoded_board = NativeBridgeCodecRef.board_from_snapshot(scoring_board, _board_radius)
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
	return NativeBridgeCodecRef.hydrate_events(events, _board)


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
	return NativeBridgeCodecRef.export_state(_current_state(), get_marked_dead_keys())


func _import_state(snapshot: Dictionary) -> void:
	var state: Dictionary = NativeBridgeCodecRef.import_state(snapshot, _current_state())
	_board = state["board"]
	_board_radius = int(state["board_radius"])
	_current_player = int(state["current_player"])
	_phase = int(state["phase"])
	_consecutive_passes = int(state["consecutive_passes"])
	_move_history = state["move_history"]
	_scores = state["scores"]
	_score_breakdown = state["score_breakdown"]
	_marked_dead_stones = state["marked_dead_stones"]
	_previous_board_signature = String(state["previous_board_signature"])
	_current_board_signature = String(state["current_board_signature"])
	_resume_player_after_scoring = int(state["resume_player_after_scoring"])


func _current_state() -> Dictionary:
	return {
		"board": _board,
		"board_radius": _board_radius,
		"current_player": _current_player,
		"phase": _phase,
		"consecutive_passes": _consecutive_passes,
		"move_history": _move_history,
		"scores": _scores,
		"score_breakdown": _score_breakdown,
		"marked_dead_stones": _marked_dead_stones,
		"previous_board_signature": _previous_board_signature,
		"current_board_signature": _current_board_signature,
		"resume_player_after_scoring": _resume_player_after_scoring,
	}


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

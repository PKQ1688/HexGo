class_name RLAgent
extends "res://scripts/agents/BaseAgent.gd"

const EasyAIStrategyRef = preload("res://scripts/ai/EasyAIStrategy.gd")
const HardAIStrategyRef = preload("res://scripts/ai/HardAIStrategy.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")
const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")
const MediumAIStrategyRef = preload("res://scripts/ai/MediumAIStrategy.gd")

var _http_request := HTTPRequest.new()
var _pending_request: bool = false
var _last_observation: Dictionary = {}


func _ready() -> void:
	if _http_request.get_parent() == null:
		_http_request.timeout = float(agent_spec.get("timeout_seconds", 8.0)) if not agent_spec.is_empty() else 8.0
		_http_request.request_completed.connect(_on_request_completed)
		add_child(_http_request)


func setup(spec: Dictionary, context: Dictionary = {}) -> void:
	super.setup(spec, context)
	if _http_request.get_parent() != null:
		_http_request.timeout = float(agent_spec.get("timeout_seconds", 8.0))


func request_action(observation: Dictionary) -> void:
	_last_observation = observation.duplicate(true)
	var endpoint := String(agent_spec.get("endpoint", "")).strip_edges()
	if endpoint == "":
		status_changed.emit("RL endpoint missing, using heuristic fallback.")
		action_ready.emit(_fallback_action(_last_observation))
		return

	if _http_request.get_parent() == null:
		add_child(_http_request)
		_http_request.request_completed.connect(_on_request_completed)
	_http_request.timeout = float(agent_spec.get("timeout_seconds", 8.0))
	_pending_request = true
	var payload := {
		"agent_type": "rl",
		"model_id": String(agent_spec.get("model_id", "")),
		"observation": observation,
		"legal_action_mask": observation.get("legal_action_mask", []),
	}
	var error := _http_request.request(
		endpoint,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if error != OK:
		_pending_request = false
		status_changed.emit("RL request failed to start, using heuristic fallback.")
		action_ready.emit(_fallback_action(_last_observation))


func cancel() -> void:
	if _pending_request:
		_http_request.cancel_request()
		_pending_request = false


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending_request = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		status_changed.emit("RL service unavailable, using heuristic fallback.")
		action_ready.emit(_fallback_action(_last_observation))
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		status_changed.emit("RL service returned invalid JSON, using heuristic fallback.")
		action_ready.emit(_fallback_action(_last_observation))
		return

	var action := _action_from_response(parsed)
	if action.is_empty():
		status_changed.emit("RL service returned an invalid action, using heuristic fallback.")
		action_ready.emit(_fallback_action(_last_observation))
		return

	action_ready.emit(action)


func _action_from_response(response: Dictionary) -> Dictionary:
	var action_codec = get_action_codec()
	if response.has("action_index"):
		if action_codec == null:
			return {}
		return action_codec.decode_action_index(int(response["action_index"]))
	if response.get("type", "") == "pass":
		return {"type": "pass"}
	if response.has("coord") and typeof(response["coord"]) == TYPE_DICTIONARY:
		var coord_data: Dictionary = response["coord"]
		if coord_data.has("q") and coord_data.has("r"):
			return {"type": "move", "coord": HexCoordRef.new(int(coord_data["q"]), int(coord_data["r"]))}
	if response.has("q") and response.has("r"):
		return {"type": "move", "coord": HexCoordRef.new(int(response["q"]), int(response["r"]))}
	return {}


func _fallback_action(observation: Dictionary) -> Dictionary:
	return _fallback_strategy().choose_action(observation)


func _fallback_strategy():
	var difficulty := int(agent_spec.get("fallback_difficulty", MatchConfigRef.AIDifficulty.MEDIUM))
	match difficulty:
		MatchConfigRef.AIDifficulty.EASY:
			return EasyAIStrategyRef.new()
		MatchConfigRef.AIDifficulty.HARD:
			return HardAIStrategyRef.new()
		_:
			return MediumAIStrategyRef.new()

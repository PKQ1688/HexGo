class_name RemoteAgent
extends "res://scripts/agents/BaseAgent.gd"

const EasyAIStrategyRef = preload("res://scripts/ai/EasyAIStrategy.gd")
const EngineProtocolRef = preload("res://scripts/core/EngineProtocol.gd")
const HardAIStrategyRef = preload("res://scripts/ai/HardAIStrategy.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")
const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")
const MediumAIStrategyRef = preload("res://scripts/ai/MediumAIStrategy.gd")

var _http_request: HTTPRequest = HTTPRequest.new()
var _pending_request: bool = false
var _last_observation: Dictionary = {}


func _ready() -> void:
	_ensure_http_request()


func setup(spec: Dictionary, context: Dictionary = {}) -> void:
	super.setup(spec, context)
	if _http_request.get_parent() != null:
		_http_request.timeout = _timeout_seconds()


func request_action(observation: Dictionary) -> void:
	_last_observation = observation.duplicate(true)
	var endpoint: String = String(agent_spec.get("endpoint", "")).strip_edges()
	if endpoint == "":
		_emit_fallback("%s endpoint missing, using heuristic fallback." % _remote_label())
		return

	_ensure_http_request()
	_http_request.timeout = _timeout_seconds()
	_pending_request = true
	var error: int = _http_request.request(
		endpoint,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(_build_payload(_last_observation))
	)
	if error != OK:
		_pending_request = false
		_emit_fallback("%s request failed to start, using heuristic fallback." % _remote_label())


func cancel() -> void:
	if _pending_request:
		_http_request.cancel_request()
		_pending_request = false


func _remote_label() -> String:
	return "Remote"


func _build_payload(observation: Dictionary) -> Dictionary:
	return {
		"agent_type": "remote",
		"observation": EngineProtocolRef.transport_observation(observation),
	}


func _on_valid_response(_response: Dictionary) -> void:
	pass


func _ensure_http_request() -> void:
	if _http_request.get_parent() == null:
		_http_request.timeout = _timeout_seconds()
		add_child(_http_request)
	if not _http_request.request_completed.is_connected(_on_request_completed):
		_http_request.request_completed.connect(_on_request_completed)


func _timeout_seconds() -> float:
	return maxf(0.5, float(agent_spec.get("timeout_seconds", 8.0)))


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending_request = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_emit_fallback("%s service unavailable, using heuristic fallback." % _remote_label())
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_emit_fallback("%s service returned invalid JSON, using heuristic fallback." % _remote_label())
		return

	_on_valid_response(parsed)
	var action: Dictionary = _action_from_response(parsed)
	if action.is_empty():
		_emit_fallback("%s service returned an invalid action, using heuristic fallback." % _remote_label())
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


func _emit_fallback(status: String) -> void:
	status_changed.emit(status)
	action_ready.emit(_fallback_action(_last_observation))


func _fallback_action(observation: Dictionary) -> Dictionary:
	return _fallback_strategy().choose_action(observation)


func _fallback_strategy():
	var difficulty: int = int(agent_spec.get("fallback_difficulty", MatchConfigRef.AIDifficulty.MEDIUM))
	match difficulty:
		MatchConfigRef.AIDifficulty.EASY:
			return EasyAIStrategyRef.new()
		MatchConfigRef.AIDifficulty.HARD:
			return HardAIStrategyRef.new()
		_:
			return MediumAIStrategyRef.new()

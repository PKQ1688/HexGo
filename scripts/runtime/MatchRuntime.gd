class_name MatchRuntime
extends Node

signal action_ready(action)
signal thinking_changed(is_thinking)
signal agent_status_changed(player, status)
signal agent_explanation_ready(player, text)

const AgentFactoryRef = preload("res://scripts/agents/AgentFactory.gd")
const ActionCodecRef = preload("res://scripts/core/ActionCodec.gd")
const GameStateRef = preload("res://scripts/core/GameState.gd")
const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")

@export var think_delay_min: float = 0.0
@export var think_delay_max: float = 0.0

var game_state = null
var match_config: Dictionary = MatchConfigRef.default_config()
var rng := RandomNumberGenerator.new()
var _is_thinking: bool = false
var _action_codec: ActionCodecRef = ActionCodecRef.new()
var _agents: Dictionary = {}
var _pending_agent_player: int = -1

var think_timer := Timer.new()


func _ready() -> void:
	rng.randomize()
	think_timer.one_shot = true
	think_timer.timeout.connect(_on_think_timeout)
	add_child(think_timer)


func configure(state, config: Dictionary) -> void:
	cancel_pending_turn()
	_disconnect_game_state()
	_clear_agents()

	game_state = state
	match_config = MatchConfigRef.normalize(config)
	_action_codec = ActionCodecRef.new()
	_rebuild_agents()

	if game_state != null:
		if not game_state.board_initialized.is_connected(_on_board_initialized):
			game_state.board_initialized.connect(_on_board_initialized)
		if not game_state.turn_completed.is_connected(_on_turn_completed):
			game_state.turn_completed.connect(_on_turn_completed)
		if game_state.board != null and game_state.board.board_radius > 0:
			_action_codec.configure_board(game_state.board)
			_maybe_schedule_agent_turn()


func is_thinking() -> bool:
	return _is_thinking


func cancel_pending_turn() -> void:
	if not think_timer.is_stopped():
		think_timer.stop()
	for agent in _agents.values():
		agent.cancel()
	_pending_agent_player = -1
	_finish_thinking()


func get_action_codec() -> ActionCodecRef:
	return _action_codec


func build_observation() -> Dictionary:
	if game_state == null:
		return {}
	return game_state.build_observation(_action_codec, match_config.get("rules", {}))


func legal_action_mask() -> Array:
	if game_state == null:
		return []
	return _action_codec.legal_action_mask(game_state)


func get_engine_backend_info() -> Dictionary:
	if game_state == null or not game_state.has_method("get_engine_backend_info"):
		return {}
	return game_state.get_engine_backend_info()


func submit_move_coord(coord) -> bool:
	return _submit_action({
		"type": "move",
		"coord": coord,
	}, true)


func submit_action_index(action_index: int) -> bool:
	var action := _action_codec.decode_action_index(action_index)
	if action.is_empty():
		return false
	return _submit_action(action, true)


func submit_pass() -> bool:
	return _submit_action(_pass_action(), true)


func resume_play() -> bool:
	if game_state == null:
		return false
	return game_state.resume_play()


func confirm_scoring() -> bool:
	if game_state == null:
		return false
	return game_state.confirm_scoring()


func _disconnect_game_state() -> void:
	if game_state == null:
		return
	if game_state.turn_completed.is_connected(_on_turn_completed):
		game_state.turn_completed.disconnect(_on_turn_completed)
	if game_state.board_initialized.is_connected(_on_board_initialized):
		game_state.board_initialized.disconnect(_on_board_initialized)


func _clear_agents() -> void:
	for player in _agents.keys():
		var agent = _agents[player]
		if agent == null:
			continue
		agent.cancel()
		if agent.get_parent() == self:
			agent.queue_free()
		else:
			agent.free()
	_agents.clear()
	_pending_agent_player = -1


func _rebuild_agents() -> void:
	for player in [GameStateRef.Player.BLACK, GameStateRef.Player.WHITE]:
		var spec := MatchConfigRef.get_agent_spec(match_config, player)
		var agent = AgentFactoryRef.create_agent(spec)
		if agent == null:
			continue
		add_child(agent)
		agent.setup(spec, {"action_codec": _action_codec})
		agent.action_ready.connect(_on_agent_action_ready.bind(player))
		agent.status_changed.connect(_on_agent_status_changed.bind(player))
		agent.explanation_ready.connect(_on_agent_explanation_ready.bind(player))
		_agents[player] = agent


func _on_board_initialized(board) -> void:
	_action_codec.configure_board(board)


func _on_turn_completed(_player: int, _scores: Dictionary) -> void:
	_maybe_schedule_agent_turn()


func _maybe_schedule_agent_turn() -> void:
	if game_state == null or game_state.board == null or game_state.board.board_radius <= 0:
		cancel_pending_turn()
		return
	if game_state.phase != GameStateRef.Phase.WAITING:
		cancel_pending_turn()
		return
	if MatchConfigRef.is_human_agent(match_config, game_state.current_player):
		cancel_pending_turn()
		return
	if not _agents.has(game_state.current_player):
		cancel_pending_turn()
		return
	if _pending_agent_player >= 0 or _is_thinking or not think_timer.is_stopped():
		return

	_is_thinking = true
	thinking_changed.emit(true)
	var min_delay: float = minf(think_delay_min, think_delay_max)
	var max_delay: float = maxf(think_delay_min, think_delay_max)
	if max_delay <= 0.0:
		call_deferred("_on_think_timeout")
		return
	think_timer.wait_time = rng.randf_range(maxf(0.01, min_delay), maxf(0.01, max_delay))
	think_timer.start()


func _on_think_timeout() -> void:
	if game_state == null or game_state.phase != GameStateRef.Phase.WAITING:
		cancel_pending_turn()
		return
	var player := game_state.current_player
	if MatchConfigRef.is_human_agent(match_config, player):
		cancel_pending_turn()
		return
	if not _agents.has(player):
		cancel_pending_turn()
		return

	_pending_agent_player = player
	_agents[player].request_action(build_observation())


func _on_agent_action_ready(action: Dictionary, player: int) -> void:
	if game_state == null:
		cancel_pending_turn()
		return
	if player != _pending_agent_player:
		return
	var normalized := _normalize_action(action)
	_pending_agent_player = -1
	_finish_thinking()
	action_ready.emit(normalized)
	if _submit_action(normalized, false):
		return
	_submit_action(_pass_action(), false)


func _on_agent_status_changed(status, player: int) -> void:
	agent_status_changed.emit(player, status)


func _on_agent_explanation_ready(text: String, player: int) -> void:
	agent_explanation_ready.emit(player, text)


func _submit_action(action: Dictionary, require_human_control: bool) -> bool:
	if game_state == null or action.is_empty():
		return false
	if game_state.phase != GameStateRef.Phase.WAITING:
		return false

	var is_human_turn := MatchConfigRef.is_human_agent(match_config, game_state.current_player)
	if require_human_control and not is_human_turn:
		return false
	if not require_human_control and is_human_turn:
		return false

	if action.get("type", "pass") == "move":
		var coord = action.get("coord")
		if coord == null and action.has("action_index"):
			coord = _action_codec.action_index_to_coord(int(action["action_index"]))
		if coord == null:
			return false
		return game_state.execute_turn(coord)

	game_state.record_pass()
	return true


func _normalize_action(action: Dictionary) -> Dictionary:
	if action.is_empty():
		return _pass_action()
	if action.get("type", "pass") == "move":
		if action.has("action_index") and not action.has("coord"):
			var decoded := _action_codec.decode_action_index(int(action["action_index"]))
			if not decoded.is_empty():
				return decoded
		if action.has("coord"):
			var encoded := _action_codec.encode_move(action["coord"])
			if not encoded.is_empty():
				return encoded
	return _pass_action()


func _pass_action() -> Dictionary:
	return {
		"type": "pass",
		"action_index": _action_codec.pass_action_index(),
	}


func _finish_thinking() -> void:
	if _is_thinking:
		_is_thinking = false
		thinking_changed.emit(false)

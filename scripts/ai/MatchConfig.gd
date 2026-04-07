class_name MatchConfig
extends RefCounted

enum PlayerControl {
	HUMAN,
	AI,
}

enum AIDifficulty {
	EASY,
	MEDIUM,
	HARD,
}

enum AgentType {
	HUMAN,
	HEURISTIC,
	RL,
	LLM,
}


static func default_rules_config() -> Dictionary:
	return {
		"scoring_mode": "manual_review",
	}


static func default_agent_spec(agent_type: int = AgentType.HUMAN, difficulty: int = AIDifficulty.MEDIUM) -> Dictionary:
	return {
		"type": agent_type,
		"difficulty": difficulty,
		"fallback_difficulty": difficulty,
		"model_id": "",
		"endpoint": "",
		"candidate_count": 8,
		"temperature": 0.2,
		"timeout_seconds": 8.0,
	}


static func build_agent_spec(agent_type: int, difficulty: int = AIDifficulty.MEDIUM, extra: Dictionary = {}) -> Dictionary:
	var spec: Dictionary = default_agent_spec(agent_type, difficulty)
	for key: String in extra.keys():
		spec[key] = extra[key]
	return _sanitize_agent_spec(spec)


static func default_config() -> Dictionary:
	var config: Dictionary = {
		"rules": default_rules_config(),
		"black_agent": default_agent_spec(AgentType.HUMAN, AIDifficulty.MEDIUM),
		"white_agent": default_agent_spec(AgentType.HEURISTIC, AIDifficulty.MEDIUM),
		"black_control": PlayerControl.HUMAN,
		"white_control": PlayerControl.AI,
		"ai_difficulty": AIDifficulty.MEDIUM,
	}
	_sync_legacy_fields_in_place(config)
	return config


static func normalize(config: Dictionary = {}) -> Dictionary:
	var merged: Dictionary = default_config().duplicate(true)
	var shared_difficulty: int = int(config.get("ai_difficulty", merged["ai_difficulty"]))

	if config.has("rules") and typeof(config["rules"]) == TYPE_DICTIONARY:
		for key: String in config["rules"].keys():
			merged["rules"][key] = config["rules"][key]

	if config.has("black_control"):
		merged["black_control"] = int(config["black_control"])
		merged["black_agent"] = default_agent_spec(_agent_type_from_legacy_control(int(config["black_control"])), shared_difficulty)
	if config.has("white_control"):
		merged["white_control"] = int(config["white_control"])
		merged["white_agent"] = default_agent_spec(_agent_type_from_legacy_control(int(config["white_control"])), shared_difficulty)

	if config.has("black_agent") and typeof(config["black_agent"]) == TYPE_DICTIONARY:
		merged["black_agent"] = _merge_agent_spec(merged["black_agent"], config["black_agent"])
	if config.has("white_agent") and typeof(config["white_agent"]) == TYPE_DICTIONARY:
		merged["white_agent"] = _merge_agent_spec(merged["white_agent"], config["white_agent"])

	if config.has("ai_difficulty"):
		merged["ai_difficulty"] = shared_difficulty
		_apply_shared_difficulty_if_needed(merged["black_agent"], config.get("black_agent", {}), shared_difficulty)
		_apply_shared_difficulty_if_needed(merged["white_agent"], config.get("white_agent", {}), shared_difficulty)

	for key: String in config.keys():
		if key in ["rules", "black_agent", "white_agent"]:
			continue
		merged[key] = config[key]

	merged["black_agent"] = _sanitize_agent_spec(merged["black_agent"])
	merged["white_agent"] = _sanitize_agent_spec(merged["white_agent"])
	_sync_legacy_fields_in_place(merged)
	return merged


static func get_agent_spec(config: Dictionary, player: int) -> Dictionary:
	var normalized: Dictionary = normalize(config)
	return normalized["black_agent"] if player == 0 else normalized["white_agent"]


static func get_agent_type(config: Dictionary, player: int) -> int:
	return int(get_agent_spec(config, player).get("type", AgentType.HUMAN))


static func is_human_agent(config: Dictionary, player: int) -> bool:
	return get_agent_type(config, player) == AgentType.HUMAN


static func is_autonomous_agent(config: Dictionary, player: int) -> bool:
	return not is_human_agent(config, player)


static func get_player_control(config: Dictionary, player: int) -> int:
	return PlayerControl.HUMAN if is_human_agent(config, player) else PlayerControl.AI


static func get_shared_difficulty(config: Dictionary) -> int:
	var normalized: Dictionary = normalize(config)
	return int(normalized["ai_difficulty"])


static func difficulty_label(difficulty: int) -> String:
	match difficulty:
		AIDifficulty.EASY:
			return "简单"
		AIDifficulty.HARD:
			return "困难"
		_:
			return "中等"


static func agent_type_label(agent_type: int) -> String:
	match agent_type:
		AgentType.HEURISTIC:
			return "启发式AI"
		AgentType.RL:
			return "RL"
		AgentType.LLM:
			return "LLM"
		_:
			return "玩家"


static func agent_type_option_labels() -> Array:
	return [
		agent_type_label(AgentType.HUMAN),
		agent_type_label(AgentType.HEURISTIC),
		agent_type_label(AgentType.RL),
		agent_type_label(AgentType.LLM),
	]


static func player_mode_label(config: Dictionary, player: int) -> String:
	var spec: Dictionary = get_agent_spec(config, player)
	var agent_type: int = int(spec.get("type", AgentType.HUMAN))
	match agent_type:
		AgentType.HEURISTIC:
			return "启发式AI（%s）" % difficulty_label(int(spec.get("difficulty", AIDifficulty.MEDIUM)))
		AgentType.RL:
			var rl_model: String = String(spec.get("model_id", "")).strip_edges()
			return "RL（%s）" % rl_model if rl_model != "" else "RL"
		AgentType.LLM:
			var llm_model: String = String(spec.get("model_id", "")).strip_edges()
			return "LLM（%s）" % llm_model if llm_model != "" else "LLM"
		_:
			return "玩家"


static func _merge_agent_spec(base_spec: Dictionary, override_spec: Dictionary) -> Dictionary:
	var merged: Dictionary = base_spec.duplicate(true)
	for key: String in override_spec.keys():
		merged[key] = override_spec[key]
	return merged


static func _sanitize_agent_spec(spec: Dictionary) -> Dictionary:
	var agent_type: int = int(spec.get("type", AgentType.HUMAN))
	var difficulty: int = int(spec.get("difficulty", AIDifficulty.MEDIUM))
	var sanitized: Dictionary = default_agent_spec(agent_type, difficulty)
	for key: String in spec.keys():
		sanitized[key] = spec[key]
	sanitized["type"] = agent_type
	sanitized["difficulty"] = difficulty
	sanitized["fallback_difficulty"] = int(sanitized.get("fallback_difficulty", difficulty))
	var model_id: String = String(sanitized.get("model_id", "")).strip_edges()
	var endpoint: String = String(sanitized.get("endpoint", "")).strip_edges()
	if agent_type == AgentType.RL:
		if model_id == "":
			model_id = OS.get_environment("HEXGO_RL_MODEL_ID").strip_edges()
		if endpoint == "":
			endpoint = OS.get_environment("HEXGO_RL_ENDPOINT").strip_edges()
	elif agent_type == AgentType.LLM:
		if model_id == "":
			model_id = OS.get_environment("HEXGO_LLM_MODEL_ID").strip_edges()
		if endpoint == "":
			endpoint = OS.get_environment("HEXGO_LLM_ENDPOINT").strip_edges()
	sanitized["model_id"] = model_id
	sanitized["endpoint"] = endpoint
	sanitized["candidate_count"] = max(1, int(sanitized.get("candidate_count", 8)))
	sanitized["temperature"] = float(sanitized.get("temperature", 0.2))
	sanitized["timeout_seconds"] = maxf(0.5, float(sanitized.get("timeout_seconds", 8.0)))
	return sanitized


static func _agent_type_from_legacy_control(control: int) -> int:
	return AgentType.HUMAN if control == PlayerControl.HUMAN else AgentType.HEURISTIC


static func _apply_shared_difficulty_if_needed(agent_spec: Dictionary, provided_spec, shared_difficulty: int) -> void:
	if typeof(provided_spec) != TYPE_DICTIONARY:
		agent_spec["difficulty"] = shared_difficulty
		agent_spec["fallback_difficulty"] = shared_difficulty
		return
	if not provided_spec.has("difficulty"):
		agent_spec["difficulty"] = shared_difficulty
	if not provided_spec.has("fallback_difficulty"):
		agent_spec["fallback_difficulty"] = shared_difficulty


static func _sync_legacy_fields_in_place(config: Dictionary) -> void:
	var black_agent: Dictionary = _sanitize_agent_spec(config.get("black_agent", default_agent_spec(AgentType.HUMAN)))
	var white_agent: Dictionary = _sanitize_agent_spec(config.get("white_agent", default_agent_spec(AgentType.HEURISTIC)))
	config["black_agent"] = black_agent
	config["white_agent"] = white_agent
	config["black_control"] = PlayerControl.HUMAN if int(black_agent.get("type", AgentType.HUMAN)) == AgentType.HUMAN else PlayerControl.AI
	config["white_control"] = PlayerControl.HUMAN if int(white_agent.get("type", AgentType.HUMAN)) == AgentType.HUMAN else PlayerControl.AI

	var ai_difficulty: int = AIDifficulty.MEDIUM
	if int(white_agent.get("type", AgentType.HUMAN)) != AgentType.HUMAN:
		ai_difficulty = int(white_agent.get("difficulty", AIDifficulty.MEDIUM))
	elif int(black_agent.get("type", AgentType.HUMAN)) != AgentType.HUMAN:
		ai_difficulty = int(black_agent.get("difficulty", AIDifficulty.MEDIUM))
	config["ai_difficulty"] = ai_difficulty

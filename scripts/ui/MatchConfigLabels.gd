class_name MatchConfigLabels
extends RefCounted

const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")


static func difficulty_label(difficulty: int) -> String:
	match difficulty:
		MatchConfigRef.AIDifficulty.EASY:
			return "简单"
		MatchConfigRef.AIDifficulty.HARD:
			return "困难"
		_:
			return "中等"


static func agent_type_label(agent_type: int) -> String:
	match agent_type:
		MatchConfigRef.AgentType.HEURISTIC:
			return "启发式AI"
		MatchConfigRef.AgentType.RL:
			return "RL"
		MatchConfigRef.AgentType.LLM:
			return "LLM"
		_:
			return "玩家"


static func agent_type_option_labels() -> Array:
	return [
		agent_type_label(MatchConfigRef.AgentType.HUMAN),
		agent_type_label(MatchConfigRef.AgentType.HEURISTIC),
		agent_type_label(MatchConfigRef.AgentType.RL),
		agent_type_label(MatchConfigRef.AgentType.LLM),
	]


static func player_mode_label(config: Dictionary, player: int) -> String:
	var spec: Dictionary = MatchConfigRef.get_agent_spec(config, player)
	var agent_type: int = int(spec.get("type", MatchConfigRef.AgentType.HUMAN))
	match agent_type:
		MatchConfigRef.AgentType.HEURISTIC:
			return "启发式AI（%s）" % difficulty_label(int(spec.get("difficulty", MatchConfigRef.AIDifficulty.MEDIUM)))
		MatchConfigRef.AgentType.RL:
			var rl_model: String = String(spec.get("model_id", "")).strip_edges()
			return "RL（%s）" % rl_model if rl_model != "" else "RL"
		MatchConfigRef.AgentType.LLM:
			var llm_model: String = String(spec.get("model_id", "")).strip_edges()
			return "LLM（%s）" % llm_model if llm_model != "" else "LLM"
		_:
			return "玩家"

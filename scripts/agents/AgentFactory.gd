class_name AgentFactory
extends RefCounted

const HeuristicAgentRef = preload("res://scripts/agents/HeuristicAgent.gd")
const LLMAgentRef = preload("res://scripts/agents/LLMAgent.gd")
const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")
const RLAgentRef = preload("res://scripts/agents/RLAgent.gd")


static func create_agent(agent_spec: Dictionary):
	var agent_type: int = int(agent_spec.get("type", MatchConfigRef.AgentType.HUMAN))
	match agent_type:
		MatchConfigRef.AgentType.HEURISTIC:
			return HeuristicAgentRef.new()
		MatchConfigRef.AgentType.RL:
			return RLAgentRef.new()
		MatchConfigRef.AgentType.LLM:
			return LLMAgentRef.new()
		_:
			return null

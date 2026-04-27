class_name RLAgent
extends "res://scripts/agents/RemoteAgent.gd"


func _remote_label() -> String:
	return "RL"


func _build_payload(observation: Dictionary) -> Dictionary:
	var transport_observation: Dictionary = EngineProtocolRef.transport_observation(observation)
	return {
		"agent_type": "rl",
		"model_id": String(agent_spec.get("model_id", "")),
		"observation": transport_observation,
		"legal_action_mask": transport_observation.get("legal_action_mask", []),
	}

class_name LLMAgent
extends "res://scripts/agents/RemoteAgent.gd"

const CandidateGeneratorRef = preload("res://scripts/agents/CandidateGenerator.gd")


func _remote_label() -> String:
	return "LLM"


func _build_payload(observation: Dictionary) -> Dictionary:
	var action_codec = get_action_codec()
	var transport_observation: Dictionary = EngineProtocolRef.transport_observation(observation)
	return {
		"agent_type": "llm",
		"model_id": String(agent_spec.get("model_id", "")),
		"temperature": float(agent_spec.get("temperature", 0.2)),
		"observation": transport_observation,
		"legal_action_mask": transport_observation.get("legal_action_mask", []),
		"candidates": CandidateGeneratorRef.top_candidates(observation, action_codec, int(agent_spec.get("candidate_count", 8))),
	}


func _on_valid_response(response: Dictionary) -> void:
	if response.has("reason"):
		explanation_ready.emit(String(response["reason"]))

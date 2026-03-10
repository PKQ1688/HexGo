class_name MediumAIStrategy
extends "res://scripts/ai/BaseAIStrategy.gd"

const AIHeuristicsRef = preload("res://scripts/ai/AIHeuristics.gd")


func choose_action(state_snapshot: Dictionary) -> Dictionary:
	var ranked: Array = AIHeuristicsRef.rank_place_actions(state_snapshot)
	if ranked.is_empty():
		return {"type": "pass"}

	if AIHeuristicsRef.should_pass(state_snapshot, float(ranked[0]["score"])):
		return {"type": "pass"}
	return ranked[0]["action"]

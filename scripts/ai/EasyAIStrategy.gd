class_name EasyAIStrategy
extends "res://scripts/ai/BaseAIStrategy.gd"

const AIHeuristicsRef = preload("res://scripts/ai/AIHeuristics.gd")

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func choose_action(state_snapshot: Dictionary) -> Dictionary:
	var ranked: Array = AIHeuristicsRef.rank_place_actions(state_snapshot)
	if ranked.is_empty():
		return {"type": "pass"}

	var pick_count: int = min(3, ranked.size())
	return ranked[rng.randi_range(0, pick_count - 1)]["action"]

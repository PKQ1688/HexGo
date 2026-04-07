class_name CandidateGenerator
extends RefCounted

const AIHeuristicsRef = preload("res://scripts/ai/AIHeuristics.gd")


static func top_candidates(observation: Dictionary, action_codec = null, limit: int = 8) -> Array:
	var ranked: Array = AIHeuristicsRef.rank_place_actions(observation)
	var candidates: Array = []
	var capped_limit := min(limit, ranked.size())
	for index in range(capped_limit):
		var entry: Dictionary = ranked[index]
		var action: Dictionary = entry.get("action", {})
		var coord = action.get("coord")
		var result: Dictionary = entry.get("result", {})
		candidates.append({
			"action_index": _action_index_for(action_codec, coord),
			"coord": null if coord == null else {"q": coord.q, "r": coord.r},
			"coord_key": "" if coord == null else coord.to_key(),
			"captures": int(result.get("captured_count", 0)),
			"self_liberties": int(result.get("self_group_liberties", 0)),
			"score": float(entry.get("score", 0.0)),
		})
	return candidates


static func _action_index_for(action_codec, coord) -> int:
	if action_codec == null or coord == null:
		return -1
	return int(action_codec.coord_to_action_index(coord))

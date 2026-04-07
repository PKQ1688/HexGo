class_name HardAIStrategy
extends "res://scripts/ai/BaseAIStrategy.gd"

const AIHeuristicsRef = preload("res://scripts/ai/AIHeuristics.gd")

var time_budget_ms: int = 400
var top_k: int = 8


func choose_action(state_snapshot: Dictionary) -> Dictionary:
	var ranked: Array = AIHeuristicsRef.rank_place_actions(state_snapshot)
	if ranked.is_empty():
		return {"type": "pass"}
	if AIHeuristicsRef.should_pass(state_snapshot, float(ranked[0]["score"])):
		return {"type": "pass"}

	var limit: int = min(top_k, ranked.size())
	var depth: int = 2
	if limit <= 4 and int(state_snapshot.get("move_count", 0)) >= 8:
		depth = 3

	var root_player: int = int(state_snapshot["current_player"])
	var started_at: int = Time.get_ticks_msec()
	var best_score: float = -INF
	var best_coord = ranked[0]["action"]["coord"].duplicated()

	for index in range(limit):
		if Time.get_ticks_msec() - started_at >= time_budget_ms:
			break
		var candidate: Dictionary = ranked[index]
		var next_snapshot: Dictionary = AIHeuristicsRef.build_next_snapshot(state_snapshot, candidate["result"], "move")
		var score: float = _search(next_snapshot, root_player, depth - 1, -INF, INF, started_at)
		var timed_out_after_search: bool = Time.get_ticks_msec() - started_at >= time_budget_ms
		if timed_out_after_search and index > 0:
			break
		if score > best_score:
			best_score = score
			best_coord = candidate["action"]["coord"].duplicated()
		if timed_out_after_search:
			break

	return {"type": "move", "coord": best_coord}


func _search(snapshot: Dictionary, root_player: int, depth: int, alpha: float, beta: float, started_at: int) -> float:
	if depth <= 0 or int(snapshot.get("consecutive_passes", 0)) >= 2:
		return AIHeuristicsRef.score_position(snapshot, root_player)
	if Time.get_ticks_msec() - started_at >= time_budget_ms:
		return AIHeuristicsRef.score_position(snapshot, root_player)

	var ranked: Array = AIHeuristicsRef.rank_place_actions(snapshot)
	if ranked.is_empty():
		var pass_result: Dictionary = AIHeuristicsRef.simulate_pass(snapshot)
		var next_snapshot: Dictionary = AIHeuristicsRef.build_next_snapshot(snapshot, pass_result, "pass")
		return _search(next_snapshot, root_player, depth - 1, alpha, beta, started_at)

	var limit: int = min(5, ranked.size())
	var maximizing: bool = int(snapshot["current_player"]) == root_player
	var value: float = -INF if maximizing else INF

	for index in range(limit):
		if Time.get_ticks_msec() - started_at >= time_budget_ms:
			break
		var next_snapshot: Dictionary = AIHeuristicsRef.build_next_snapshot(snapshot, ranked[index]["result"], "move")
		var child_value: float = _search(next_snapshot, root_player, depth - 1, alpha, beta, started_at)
		if maximizing:
			value = maxf(value, child_value)
			alpha = maxf(alpha, value)
		else:
			value = minf(value, child_value)
			beta = minf(beta, value)
		if beta <= alpha:
			break

	if value == -INF or value == INF:
		return AIHeuristicsRef.score_position(snapshot, root_player)
	return value

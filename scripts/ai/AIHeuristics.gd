class_name AIHeuristics
extends RefCounted

const CaptureResolverRef = preload("res://scripts/core/CaptureResolver.gd")
const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const HexCoordRef = preload("res://scripts/core/HexCoord.gd")
const ScoreCalculatorRef = preload("res://scripts/core/ScoreCalculator.gd")
const TerritoryResolverRef = preload("res://scripts/core/TerritoryResolver.gd")
const TurnSimulatorRef = preload("res://scripts/core/TurnSimulator.gd")


static func rank_place_actions(snapshot: Dictionary, perspective_player: int = -1) -> Array:
	var player: int = perspective_player if perspective_player >= 0 else int(snapshot["current_player"])
	var ranked: Array = []
	var board: HexBoardRef = snapshot["board"]
	var current_scores: Dictionary = snapshot.get("scores", {})
	if current_scores.is_empty():
		current_scores = ScoreCalculatorRef.calculate(board)
	var territory_before: Dictionary = snapshot.get("territory_map", {})
	if territory_before.is_empty():
		territory_before = TerritoryResolverRef.resolve_all(board)
	for coord in board.get_empty_cells():
		var result: Dictionary = TurnSimulatorRef.simulate_place(
			board,
			int(snapshot["current_player"]),
			String(snapshot["previous_board_signature"]),
			String(snapshot["current_board_signature"]),
			coord
		)
		if not result["legal"]:
			continue

		var action: Dictionary = {"type": "move", "coord": coord.duplicated()}
		ranked.append({
			"action": action,
			"result": result,
			"score": score_move(snapshot, result, player, coord, current_scores, territory_before),
		})

	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return ranked


static func score_move(
	snapshot: Dictionary,
	result: Dictionary,
	perspective_player: int,
	coord: HexCoordRef,
	current_scores: Dictionary = {},
	territory_before: Dictionary = {},
) -> float:
	var next_snapshot: Dictionary = build_next_snapshot(snapshot, result, "move")
	var board_before: HexBoardRef = snapshot["board"]
	var board_after: HexBoardRef = result["board"]
	var own_piece: int = piece_state_for_player(perspective_player)
	var enemy_piece: int = piece_state_for_player(other_player(perspective_player))
	var move_count: int = int(snapshot.get("move_count", 0))
	var total_cells: int = max(1, board_before.all_coords.size())
	var early_bias := 1.0 - clampf(float(move_count) / float(total_cells), 0.0, 1.0)

	if current_scores.is_empty():
		current_scores = snapshot.get("scores", {})
	if current_scores.is_empty():
		current_scores = ScoreCalculatorRef.calculate(board_before)
	var next_scores: Dictionary = result.get("scores", {})
	if next_scores.is_empty():
		next_scores = ScoreCalculatorRef.calculate(board_after)
	var score_gain := float(next_scores.get(perspective_player, 0) - current_scores.get(perspective_player, 0))

	if territory_before.is_empty():
		territory_before = snapshot.get("territory_map", {})
	if territory_before.is_empty():
		territory_before = TerritoryResolverRef.resolve_all(board_before)
	var territory_after: Dictionary = result.get("territory_map", {})
	if territory_after.is_empty():
		territory_after = TerritoryResolverRef.resolve_all(board_after)
	var territory_gain := float(
		territory_after.get(own_piece, []).size() - territory_before.get(own_piece, []).size()
	)

	var captured_score := float(result["captured_count"]) * 22.0
	var self_group_liberties := int(result.get("self_group_liberties", 0))
	var safety_bonus := 0.0
	if self_group_liberties <= 1:
		safety_bonus -= 18.0
	elif self_group_liberties == 2:
		safety_bonus -= 4.0
	else:
		safety_bonus += min(self_group_liberties, 4) * 3.0

	var friendly_links := _count_adjacent_state(board_before, coord, own_piece)
	var enemy_neighbors := _count_adjacent_state(board_before, coord, enemy_piece)
	var pressure_bonus := _adjacent_group_pressure(board_after, coord, enemy_piece, 1) * 10.0
	var center_bonus := float(max(0, int(snapshot.get("board_radius", board_before.board_radius)) - coord.distance(HexCoordRef.new()))) * (2.2 * early_bias)
	var isolated_penalty := -7.0 if friendly_links == 0 and self_group_liberties <= 2 else 0.0

	return score_position(next_snapshot, perspective_player) + captured_score + score_gain * 6.0 + territory_gain * 5.0 + safety_bonus + float(friendly_links) * 3.0 + float(enemy_neighbors) * 1.8 + pressure_bonus + center_bonus + isolated_penalty


static func score_position(snapshot: Dictionary, perspective_player: int) -> float:
	var board: HexBoardRef = snapshot["board"]
	var other: int = other_player(perspective_player)
	var scores: Dictionary = snapshot.get("scores", {})
	if scores.is_empty():
		scores = ScoreCalculatorRef.calculate(board)
	var score_diff := float(scores.get(perspective_player, 0) - scores.get(other, 0))

	var own_piece: int = piece_state_for_player(perspective_player)
	var enemy_piece: int = piece_state_for_player(other)
	var territory_map: Dictionary = snapshot.get("territory_map", {})
	if territory_map.is_empty():
		territory_map = TerritoryResolverRef.resolve_all(board)
	var territory_diff := float(territory_map.get(own_piece, []).size() - territory_map.get(enemy_piece, []).size())
	var safety_diff := _group_safety(board, own_piece) - _group_safety(board, enemy_piece)
	var threat_diff := _atari_pressure(board, enemy_piece) - _atari_pressure(board, own_piece)
	var move_count: int = int(snapshot.get("move_count", 0))
	var total_cells: int = max(1, board.all_coords.size())
	var early_bias := 1.0 - clampf(float(move_count) / float(total_cells), 0.0, 1.0)
	var center_diff := (_center_presence(board, own_piece) - _center_presence(board, enemy_piece)) * early_bias

	return score_diff * 12.0 + territory_diff * 4.0 + safety_diff * 2.4 + threat_diff * 5.5 + center_diff * 0.7


static func should_pass(snapshot: Dictionary, best_score: float) -> bool:
	var board: HexBoardRef = snapshot["board"]
	var move_count: int = int(snapshot.get("move_count", 0))
	var total_cells: int = max(1, board.all_coords.size())
	if move_count < int(float(total_cells) * 0.68):
		return false

	var scores: Dictionary = snapshot.get("scores", {})
	if scores.is_empty():
		scores = ScoreCalculatorRef.calculate(board)
	var player: int = int(snapshot["current_player"])
	var other: int = other_player(player)
	return best_score < 14.0 and int(scores.get(player, 0)) >= int(scores.get(other, 0))


static func simulate_pass(snapshot: Dictionary) -> Dictionary:
	return TurnSimulatorRef.simulate_pass(
		snapshot["board"],
		int(snapshot["current_player"]),
		String(snapshot["current_board_signature"]),
		int(snapshot.get("consecutive_passes", 0))
	)


static func build_next_snapshot(snapshot: Dictionary, result: Dictionary, action_type: String) -> Dictionary:
	var next_previous_signature := String(snapshot.get("previous_board_signature", ""))
	if action_type == "move":
		next_previous_signature = String(snapshot.get("current_board_signature", ""))

	return {
		"board": result["board"],
		"current_player": int(result["next_player"]),
		"previous_board_signature": next_previous_signature,
		"current_board_signature": String(result.get("board_signature", "")),
		"consecutive_passes": int(result.get("consecutive_passes", 0)),
		"scores": result.get("scores", {}),
		"territory_map": result.get("territory_map", {}),
		"move_count": int(snapshot.get("move_count", 0)) + 1,
		"board_radius": int(snapshot.get("board_radius", 0)),
	}


static func piece_state_for_player(player: int) -> int:
	return HexBoardRef.CellState.BLACK if player == 0 else HexBoardRef.CellState.WHITE


static func other_player(player: int) -> int:
	return 1 if player == 0 else 0


static func _count_adjacent_state(board: HexBoardRef, coord: HexCoordRef, cell_state: int) -> int:
	var count := 0
	for neighbor in board.get_neighbors(coord):
		if board.get_cell(neighbor) == cell_state:
			count += 1
	return count


static func _adjacent_group_pressure(board: HexBoardRef, coord: HexCoordRef, cell_state: int, max_liberties: int) -> int:
	var seen: Dictionary = {}
	var pressured := 0
	for neighbor in board.get_neighbors(coord):
		if board.get_cell(neighbor) != cell_state:
			continue
		var key: String = neighbor.to_key()
		if seen.has(key):
			continue
		var group := CaptureResolverRef.find_group(board, neighbor, cell_state)
		for item in group:
			seen[item.to_key()] = true
		if CaptureResolverRef.get_liberties(board, group) <= max_liberties:
			pressured += 1
	return pressured


static func _group_safety(board: HexBoardRef, cell_state: int) -> float:
	var visited: Dictionary = {}
	var safety := 0.0
	for coord in board.all_coords:
		if board.get_cell(coord) != cell_state:
			continue
		if visited.has(coord.to_key()):
			continue

		var group := CaptureResolverRef.find_group(board, coord, cell_state)
		for item in group:
			visited[item.to_key()] = true

		var liberties := CaptureResolverRef.get_liberties(board, group)
		if liberties <= 1:
			safety -= 9.0 + float(group.size()) * 1.2
		elif liberties == 2:
			safety -= 2.5
		else:
			safety += min(liberties, 4) * 1.8 + float(group.size()) * 0.4
	return safety


static func _atari_pressure(board: HexBoardRef, target_state: int) -> float:
	var visited: Dictionary = {}
	var pressure := 0.0
	for coord in board.all_coords:
		if board.get_cell(coord) != target_state:
			continue
		if visited.has(coord.to_key()):
			continue

		var group := CaptureResolverRef.find_group(board, coord, target_state)
		for item in group:
			visited[item.to_key()] = true

		var liberties := CaptureResolverRef.get_liberties(board, group)
		if liberties == 1:
			pressure += 2.5 + float(group.size())
		elif liberties == 2:
			pressure += 0.8
	return pressure


static func _center_presence(board: HexBoardRef, cell_state: int) -> float:
	var center := HexCoordRef.new()
	var score := 0.0
	for coord in board.all_coords:
		if board.get_cell(coord) != cell_state:
			continue
		score += float(max(0, board.board_radius - coord.distance(center)))
	return score

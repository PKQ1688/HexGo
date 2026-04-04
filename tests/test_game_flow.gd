extends SceneTree

const GameState = preload("res://scripts/core/GameState.gd")
const HexBoard = preload("res://scripts/core/HexBoard.gd")
const HexCoord = preload("res://scripts/core/HexCoord.gd")
const ThreatAnalyzer = preload("res://scripts/core/ThreatAnalyzer.gd")

var _turn_events: Array = []
var _captured_events: Array = []
var _territory_events: Array = []
var _game_over_scores: Dictionary = {}


func _init() -> void:
	_run_tests()
	quit()


func _run_tests() -> void:
	_test_basic_turn_and_occupied_rejection()
	_test_suicide_move_rejected()
	_test_capture_flow()
	_test_territory_flow()
	_test_scoring_phase_and_resume()
	_test_confirm_score_game_over()
	_test_visible_threats_follow_phase()
	print("All game flow tests passed.")


func _new_state(radius: int = 3) -> GameState:
	var state := GameState.new()
	state.turn_completed.connect(func(player: int, scores: Dictionary) -> void:
		_turn_events.append({"player": player, "scores": scores.duplicate(true)})
	)
	state.pieces_captured.connect(func(coords: Array) -> void:
		_captured_events.append(coords.duplicate())
	)
	state.territory_formed.connect(func(coords: Array, player: int) -> void:
		_territory_events.append({"player": player, "coords": coords.duplicate()})
	)
	state.game_over.connect(func(scores: Dictionary) -> void:
		_game_over_scores = scores.duplicate(true)
	)
	state.setup_game(radius)
	return state


func _reset_events() -> void:
	_turn_events.clear()
	_captured_events.clear()
	_territory_events.clear()
	_game_over_scores.clear()


func _test_basic_turn_and_occupied_rejection() -> void:
	_reset_events()
	var state := _new_state(3)
	var move := HexCoord.new(0, 0)

	_assert(state.can_place_at(move), "Initial empty cell should be placeable.")
	_assert(state.execute_turn(move), "First legal move should succeed.")
	_assert(state.board.get_cell(move) == HexBoard.CellState.BLACK, "First move should place a black stone.")
	_assert(state.current_player == GameState.Player.WHITE, "Turn should switch after a successful move.")
	_assert(not state.can_place_at(move), "Occupied cell should not remain placeable.")
	_assert(not state.execute_turn(move), "Playing on an occupied cell should fail.")
	_assert(state.move_history.size() == 1, "Rejected move should not enter move history.")
	_assert(_turn_events.size() >= 2, "Setup and move should both emit turn_completed.")
	state.free()


func _test_capture_flow() -> void:
	_reset_events()
	var state := _new_state(2)
	var sequence := [
		HexCoord.new(1, 0),
		HexCoord.new(0, 0),
		HexCoord.new(1, -1),
		HexCoord.new(2, -1),
		HexCoord.new(0, -1),
		HexCoord.new(2, -2),
		HexCoord.new(-1, 0),
		HexCoord.new(1, 1),
		HexCoord.new(-1, 1),
		HexCoord.new(0, 2),
		HexCoord.new(0, 1),
	]

	for coord in sequence:
		_assert(state.execute_turn(coord), "Capture sequence should contain only legal moves.")

	var center_state := state.board.get_cell(HexCoord.new(0, 0))
	_assert(center_state == HexBoard.CellState.EMPTY, "Captured center should become empty under go-style rules.")
	_assert(_captured_events.size() == 1, "Capture flow should emit one capture event.")
	_assert(_captured_events[0].size() == 1, "Single surrounded stone should produce one captured coordinate.")
	_assert(_captured_events[0][0].equals(HexCoord.new(0, 0)), "Captured coordinate should be the surrounded center stone.")
	state.free()


func _test_suicide_move_rejected() -> void:
	_reset_events()
	var state := _new_state(2)
	state.board.set_cell(HexCoord.new(1, 0), HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(1, -1), HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(0, -1), HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(-1, 0), HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(-1, 1), HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(0, 1), HexBoard.CellState.WHITE)

	var move := HexCoord.new(0, 0)
	_assert(not state.can_place_at(move), "Pure suicide move should be rejected.")
	_assert(not state.execute_turn(move), "Executing a suicide move should fail.")
	_assert(state.board.get_cell(move) == HexBoard.CellState.EMPTY, "Rejected suicide move should not alter the board.")
	state.free()


func _test_territory_flow() -> void:
	_reset_events()
	var state := _new_state(3)
	var sequence := [
		HexCoord.new(1, 0),
		HexCoord.new(3, -3),
		HexCoord.new(1, -1),
		HexCoord.new(3, -2),
		HexCoord.new(0, -1),
		HexCoord.new(3, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(2, -3),
		HexCoord.new(-1, 1),
		HexCoord.new(2, -2),
		HexCoord.new(0, 1),
	]

	for coord in sequence:
		_assert(state.execute_turn(coord), "Territory sequence should contain only legal moves.")

	var center := HexCoord.new(0, 0)
	_assert(state.board.get_cell(center) == HexBoard.CellState.EMPTY, "Enclosed point should remain empty during play.")
	_assert(state.score_breakdown[GameState.Player.BLACK]["territory"] == 1, "Black territory score should include the enclosed center.")
	var found_black_territory := false
	for event in _territory_events:
		if event["player"] == GameState.Player.BLACK and event["coords"].size() == 1 and event["coords"][0].equals(center):
			found_black_territory = true
			break
	_assert(found_black_territory, "Territory flow should emit the enclosed center in territory_formed.")
	state.free()


func _test_scoring_phase_and_resume() -> void:
	_reset_events()
	var state := _new_state(3)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(3, -3),
		HexCoord.new(1, -1),
		HexCoord.new(3, -2),
		HexCoord.new(0, -1),
		HexCoord.new(3, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(2, -3),
		HexCoord.new(-1, 1),
		HexCoord.new(2, -2),
		HexCoord.new(0, 1),
	]:
		_assert(state.execute_turn(coord), "Setup before scoring should contain only legal moves.")

	state.record_pass()
	_assert(state.current_player == GameState.Player.BLACK, "Single pass should hand turn to the opponent.")
	_assert(state.phase == GameState.Phase.WAITING, "Single pass should not end the game.")

	state.record_pass()
	_assert(state.phase == GameState.Phase.SCORING, "Two consecutive passes should enter scoring phase.")
	_assert(state.can_toggle_dead_at(HexCoord.new(1, 0)), "Scoring phase should allow toggling stones as dead.")
	_assert(state.toggle_dead_group(HexCoord.new(1, 0)), "Toggling a black group dead should succeed.")
	_assert(state.marked_dead_stones.size() == 6, "Entire surrounded black ring should be markable as dead.")
	_assert(state.score_breakdown[GameState.Player.BLACK]["pieces"] == 0, "Marked dead stones should be excluded from live stone count.")
	_assert(state.resume_play(), "Scoring phase should allow resuming play.")
	_assert(state.phase == GameState.Phase.WAITING, "Resuming should return to normal play.")
	_assert(state.current_player == GameState.Player.WHITE, "恢复对局后应轮到第二次 Pass 之后的下一手。")
	_assert(state.marked_dead_stones.is_empty(), "Resuming play should clear dead-stone markings.")
	state.free()


func _test_confirm_score_game_over() -> void:
	_reset_events()
	var state := _new_state(2)
	state.record_pass()
	state.record_pass()
	_assert(state.phase == GameState.Phase.SCORING, "Double pass should enter scoring before final confirmation.")
	_assert(state.confirm_scoring(), "Confirming score from scoring phase should succeed.")
	_assert(state.phase == GameState.Phase.GAME_OVER, "Confirming score should end the game.")
	_assert(not _game_over_scores.is_empty(), "Final confirmation should emit game_over.")
	state.free()


func _test_visible_threats_follow_phase() -> void:
	_reset_events()
	var state := _new_state(3)
	state.board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.BLACK)
	for neighbor in HexCoord.new(0, 0).neighbors():
		state.board.set_cell(neighbor, HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(3, 0), HexBoard.CellState.BLACK)

	var threat_map: Dictionary = state.get_visible_threats()
	var expected_map: Dictionary = ThreatAnalyzer.analyze(state.board)
	_assert(threat_map.size() == 1, "Visible threats should exclude SAFE groups during normal play.")
	_assert(threat_map.has(HexCoord.new(0, 0).to_key()), "Visible threats should include the threatened center group.")
	_assert(not threat_map.has(HexCoord.new(3, 0).to_key()), "Visible threats should exclude SAFE groups.")
	_assert(threat_map == {
		HexCoord.new(0, 0).to_key(): expected_map[HexCoord.new(0, 0).to_key()],
	}, "Visible threats should match analyzed non-SAFE metadata for the active phase.")

	state.record_pass()
	state.record_pass()
	_assert(state.phase == GameState.Phase.SCORING, "Double pass should enter scoring phase.")
	_assert(state.get_visible_threats().is_empty(), "Visible threats should be hidden during scoring.")

	_assert(state.confirm_scoring(), "Confirming scoring should succeed.")
	_assert(state.phase == GameState.Phase.GAME_OVER, "Confirming scoring should end the game.")
	_assert(state.get_visible_threats().is_empty(), "Visible threats should remain hidden after game over.")
	state.free()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)

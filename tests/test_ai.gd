extends SceneTree

const EasyAIStrategy = preload("res://scripts/ai/EasyAIStrategy.gd")
const HardAIStrategy = preload("res://scripts/ai/HardAIStrategy.gd")
const MatchConfig = preload("res://scripts/ai/MatchConfig.gd")
const MatchRuntime = preload("res://scripts/runtime/MatchRuntime.gd")
const MediumAIStrategy = preload("res://scripts/ai/MediumAIStrategy.gd")
const GameState = preload("res://scripts/core/GameState.gd")
const HexBoard = preload("res://scripts/core/HexBoard.gd")
const HexCoord = preload("res://scripts/core/HexCoord.gd")
const ScoreCalculator = preload("res://scripts/core/ScoreCalculator.gd")
const TurnSimulator = preload("res://scripts/core/TurnSimulator.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_turn_simulator_consistency()
	_test_medium_and_hard_ai_prefer_capture()
	_test_ai_strategies_force_pass_after_turn_limit()
	await _test_match_runtime_emits_action_for_agent_turn()
	await _test_rl_and_llm_agents_fallback_without_service()
	await _test_autonomous_match_turn_limit_enters_scoring()
	await _test_main_human_black_vs_ai_white()
	await _test_main_ai_black_vs_human_white()
	print("All AI tests passed.")
	quit()


func _test_turn_simulator_consistency() -> void:
	var state := GameState.new()
	state.setup_game(2)
	var open_move := HexCoord.new(0, 0)
	var open_result := TurnSimulator.simulate_place(
		state.board,
		state.current_player,
		state.previous_board_signature,
		state.current_board_signature,
		open_move
	)
	_assert(open_result["legal"] == state.can_place_at(open_move), "Simulator should match GameState legality on open moves.")

	state.board.set_cell(HexCoord.new(1, 0), HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(1, -1), HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(0, -1), HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(-1, 0), HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(-1, 1), HexBoard.CellState.WHITE)
	state.board.set_cell(HexCoord.new(0, 1), HexBoard.CellState.WHITE)
	state.current_board_signature = TurnSimulator.board_signature(state.board)
	var suicide_result := TurnSimulator.simulate_place(
		state.board,
		state.current_player,
		state.previous_board_signature,
		state.current_board_signature,
		open_move
	)
	_assert(not state.can_place_at(open_move), "GameState should still reject suicide moves after simulator refactor.")
	_assert(not suicide_result["legal"], "Simulator should reject suicide moves.")

	var pass_result := TurnSimulator.simulate_pass(state.board, state.current_player, state.current_board_signature, 1)
	_assert(pass_result["ended_by_double_pass"], "Second simulated pass should mark double-pass scoring transition.")
	state.free()


func _test_medium_and_hard_ai_prefer_capture() -> void:
	var board := HexBoard.new()
	board.initialize(2)
	board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.WHITE)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
	]:
		board.set_cell(coord, HexBoard.CellState.BLACK)

	var snapshot := _build_snapshot(board, GameState.Player.BLACK, 6)
	var target := HexCoord.new(0, 1)
	var easy_action: Dictionary = EasyAIStrategy.new().choose_action(snapshot)
	_assert(easy_action["type"] == "move", "Easy AI should return a move when legal points exist.")
	var medium_action: Dictionary = MediumAIStrategy.new().choose_action(snapshot)
	_assert(medium_action["type"] == "move" and medium_action["coord"].equals(target), "Medium AI should take the direct capture.")

	var hard_ai := HardAIStrategy.new()
	hard_ai.time_budget_ms = 80
	var hard_action: Dictionary = hard_ai.choose_action(snapshot)
	_assert(hard_action["type"] == "move" and hard_action["coord"].equals(target), "Hard AI should also prioritize the direct capture.")


func _test_ai_strategies_force_pass_after_turn_limit() -> void:
	var board := HexBoard.new()
	board.initialize(2)
	var snapshot := _build_snapshot(board, GameState.Player.BLACK, board.all_coords.size() * 6)
	for strategy in [EasyAIStrategy.new(), MediumAIStrategy.new(), HardAIStrategy.new()]:
		var action: Dictionary = strategy.choose_action(snapshot)
		_assert(action.get("type", "") == "pass", "AI strategies should force pass once the autonomous turn limit is reached.")


func _test_match_runtime_emits_action_for_agent_turn() -> void:
	var state := GameState.new()
	var controller := MatchRuntime.new()
	controller.think_delay_min = 0.0
	controller.think_delay_max = 0.0
	root.add_child(state)
	root.add_child(controller)

	var actions: Array = []
	controller.action_ready.connect(func(action: Dictionary) -> void:
		actions.append(action)
	)
	controller.configure(state, {
		"black_control": MatchConfig.PlayerControl.AI,
		"white_control": MatchConfig.PlayerControl.HUMAN,
		"ai_difficulty": MatchConfig.AIDifficulty.EASY,
	})
	state.setup_game(2)
	await _await_frames(2)
	_assert(actions.size() == 1, "MatchRuntime should emit one action when an agent turn begins.")
	_assert(actions[0]["type"] == "move", "MatchRuntime should emit a concrete move action when legal moves exist.")
	_assert(actions[0].has("action_index") and int(actions[0]["action_index"]) >= 0, "MatchRuntime should emit a stable action_index for runtime consumers.")

	controller.queue_free()
	state.queue_free()
	await _await_frames(1)


func _test_rl_and_llm_agents_fallback_without_service() -> void:
	for agent_type in [MatchConfig.AgentType.RL, MatchConfig.AgentType.LLM]:
		var state := GameState.new()
		var controller := MatchRuntime.new()
		controller.think_delay_min = 0.0
		controller.think_delay_max = 0.0
		root.add_child(state)
		root.add_child(controller)

		var actions: Array = []
		controller.action_ready.connect(func(action: Dictionary) -> void:
			actions.append(action)
		)
		controller.configure(state, {
			"black_agent": MatchConfig.build_agent_spec(agent_type, MatchConfig.AIDifficulty.EASY, {
				"use_environment": false,
			}),
			"white_agent": MatchConfig.build_agent_spec(MatchConfig.AgentType.HUMAN, MatchConfig.AIDifficulty.EASY),
		})
		state.setup_game(2)
		await _await_frames(2)
		_assert(actions.size() == 1, "Remote agent should still produce a move when no endpoint is configured.")
		_assert(actions[0]["type"] == "move", "Remote fallback should still produce a concrete move action.")
		_assert(actions[0].has("action_index"), "Remote fallback action should still include action_index.")

		controller.queue_free()
		state.queue_free()
		await _await_frames(1)


func _test_autonomous_match_turn_limit_enters_scoring() -> void:
	var state := GameState.new()
	var controller := MatchRuntime.new()
	controller.think_delay_min = 0.0
	controller.think_delay_max = 0.0
	root.add_child(state)
	root.add_child(controller)

	var statuses: Array = []
	controller.agent_status_changed.connect(func(_player: int, status: String) -> void:
		statuses.append(status)
	)
	controller.configure(state, {
		"rules": {
			"max_turns": 4,
		},
		"black_agent": MatchConfig.build_agent_spec(MatchConfig.AgentType.HEURISTIC, MatchConfig.AIDifficulty.EASY),
		"white_agent": MatchConfig.build_agent_spec(MatchConfig.AgentType.HEURISTIC, MatchConfig.AIDifficulty.EASY),
	})
	state.setup_game(2)
	await _await_frames(20)
	_assert(state.phase == GameState.Phase.SCORING, "Autonomous matches should enter scoring when the turn limit is reached.")
	_assert(state.move_history.size() >= 6, "Turn-limit scoring should append the two forced passes.")
	_assert(_has_status_containing(statuses, "Turn limit reached"), "Turn-limit scoring should emit a status for UI/runtime consumers.")
	_assert(state.confirm_scoring(), "Turn-limited scoring should still be confirmable.")
	_assert(state.phase == GameState.Phase.GAME_OVER, "Confirming turn-limited scoring should end the game.")

	controller.queue_free()
	state.queue_free()
	await _await_frames(1)


func _test_main_human_black_vs_ai_white() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	main.match_runtime.think_delay_min = 0.0
	main.match_runtime.think_delay_max = 0.0
	main.start_match({
		"black_control": MatchConfig.PlayerControl.HUMAN,
		"white_control": MatchConfig.PlayerControl.AI,
		"ai_difficulty": MatchConfig.AIDifficulty.EASY,
	})
	await _await_frames(1)
	_assert(main.game_state.execute_turn(HexCoord.new(0, 0)), "Human side should be able to make the opening move.")
	await _await_frames(3)
	_assert(main.game_state.move_history.size() >= 2, "AI white should answer automatically after the human move.")
	_assert(main.game_state.current_player == GameState.Player.BLACK, "After AI white responds, turn should return to black.")

	main.queue_free()
	await _await_frames(1)


func _test_main_ai_black_vs_human_white() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	main.match_runtime.think_delay_min = 0.0
	main.match_runtime.think_delay_max = 0.0
	main.start_match({
		"black_control": MatchConfig.PlayerControl.AI,
		"white_control": MatchConfig.PlayerControl.HUMAN,
		"ai_difficulty": MatchConfig.AIDifficulty.EASY,
	})
	await _await_frames(3)
	_assert(main.game_state.move_history.size() >= 1, "AI black should make the opening move automatically.")
	_assert(main.game_state.current_player == GameState.Player.WHITE, "After AI black moves, turn should pass to white.")

	main.queue_free()
	await _await_frames(1)


func _build_snapshot(board: HexBoard, current_player: int, move_count: int) -> Dictionary:
	return {
		"board": board.clone(),
		"current_player": current_player,
		"previous_board_signature": "",
		"current_board_signature": TurnSimulator.board_signature(board),
		"consecutive_passes": 0,
		"scores": ScoreCalculator.calculate(board),
		"move_count": move_count,
		"board_radius": board.board_radius,
	}


func _await_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _has_status_containing(statuses: Array, needle: String) -> bool:
	for status in statuses:
		if String(status).contains(needle):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)

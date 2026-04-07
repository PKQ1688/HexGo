extends SceneTree

const ActionCodec = preload("res://scripts/core/ActionCodec.gd")
const CaptureResolver = preload("res://scripts/core/CaptureResolver.gd")
const EngineProtocol = preload("res://scripts/core/EngineProtocol.gd")
const GameState = preload("res://scripts/core/GameState.gd")
const HexBoard = preload("res://scripts/core/HexBoard.gd")
const HexCoord = preload("res://scripts/core/HexCoord.gd")
const HexLayout = preload("res://scripts/render/HexLayout.gd")
const MatchEngine = preload("res://scripts/core/MatchEngine.gd")
const NativeMatchEngineBridge = preload("res://scripts/core/NativeMatchEngineBridge.gd")
const ScoreCalculator = preload("res://scripts/core/ScoreCalculator.gd")
const ThreatAnalyzer = preload("res://scripts/core/ThreatAnalyzer.gd")
const TerritoryResolver = preload("res://scripts/core/TerritoryResolver.gd")


func _init() -> void:
	_run_tests()
	quit()


func _run_tests() -> void:
	_test_round_trip()
	_test_board_size()
	_test_runtime_scripts_load()
	_test_engine_protocol_observation()
	_test_native_bridge_observation_fallback()
	_test_game_state_backend_selection()
	_test_action_codec()
	_test_match_engine_events()
	_test_capture()
	_test_threat_analysis()
	_test_territory()
	_test_boundary_not_territory()
	_test_score()
	print("All core tests passed.")


func _test_round_trip() -> void:
	var layout := HexLayout.new(40.0, Vector2.ZERO)
	var coord := HexCoord.new(2, -1)
	var pixel := layout.cube_to_pixel(coord)
	var back := layout.pixel_to_cube(pixel)
	_assert(back.equals(coord), "Cube/pixel round trip failed.")


func _test_board_size() -> void:
	var board := HexBoard.new()
	board.initialize(3)
	_assert(board.all_coords.size() == 37, "Board size formula failed for radius 3.")


func _test_runtime_scripts_load() -> void:
	var match_config_script = load("res://scripts/ai/MatchConfig.gd")
	_assert(match_config_script != null, "MatchConfig script should load successfully.")
	var agent_factory_script = load("res://scripts/agents/AgentFactory.gd")
	_assert(agent_factory_script != null, "AgentFactory script should load successfully.")
	var runtime_script = load("res://scripts/runtime/MatchRuntime.gd")
	_assert(runtime_script != null, "MatchRuntime script should load successfully.")


func _test_engine_protocol_observation() -> void:
	var engine := MatchEngine.new()
	engine.setup_game(1)
	engine.consume_events()
	var codec := ActionCodec.new(1)
	var observation := engine.build_observation(codec, {"scoring_mode": "manual_review"})
	_assert(int(observation.get("protocol_version", -1)) == EngineProtocol.PROTOCOL_VERSION, "Observation should expose the shared protocol version.")
	_assert(observation.get("phase_name", "") == "waiting", "Fresh observation should serialize the waiting phase.")
	_assert(observation.get("current_player_name", "") == "black", "Fresh observation should serialize black as the starting player.")
	_assert(observation.get("rules", {}).get("board_radius", -1) == 1, "Observation rules should include board radius.")
	_assert(observation.get("rules", {}).get("scoring_mode", "") == "manual_review", "Observation rules should include scoring mode.")
	_assert(observation.get("cells", []).size() == 7, "Radius-1 observation should expose 7 serialized cells.")
	_assert(observation.get("ordered_coords", []).size() == 7, "Observation should expose ordered coords for the action space.")
	_assert(observation.get("legal_action_mask", []).size() == 8, "Observation legal mask should include pass.")
	_assert(not observation.get("result", {}).get("is_game_over", true), "Fresh observation should not be marked as finished.")

	var transport := EngineProtocol.transport_observation(observation)
	_assert(not transport.has("board"), "Transport observation should strip non-JSON board objects.")
	_assert(transport.get("scores", {}).get("black", -1) == 0, "Transport observation should expose player-keyed scores.")

	_assert(engine.execute_turn(HexCoord.new(0, 0)), "Protocol observation test should be able to play an opening move.")
	var serialized_events := EngineProtocol.serialize_events(engine.consume_events())
	_assert(serialized_events.size() >= 2, "Serialized event batch should include move events.")
	_assert(serialized_events[0].get("type", "") == MatchEngine.EVENT_PIECE_PLACED, "Serialized event batch should preserve event ordering.")
	_assert(serialized_events[0].get("coord", []) == [0, 0], "Piece placed event should serialize coord arrays.")
	_assert(serialized_events[serialized_events.size() - 1].get("type", "") == MatchEngine.EVENT_TURN_COMPLETED, "Serialized event batch should end with turn_completed.")


func _test_native_bridge_observation_fallback() -> void:
	var bridge := NativeMatchEngineBridge.new(1)
	bridge.setup_game(1)
	var observation := bridge.build_observation(ActionCodec.new(1), {"scoring_mode": "auto_settle"})
	_assert(int(observation.get("protocol_version", -1)) == EngineProtocol.PROTOCOL_VERSION, "Native bridge fallback should still emit the shared protocol version.")
	_assert(observation.get("rules", {}).get("scoring_mode", "") == "auto_settle", "Native bridge fallback observation should preserve rules config.")
	_assert(observation.get("cells", []).size() == 7, "Native bridge fallback observation should serialize board cells.")
	_assert(observation.get("legal_action_mask", []).size() == 8, "Native bridge fallback observation should expose a legal mask including pass.")


func _test_game_state_backend_selection() -> void:
	var fallback_state := GameState.new()
	fallback_state.prefer_native_engine = false
	fallback_state.setup_game(1)
	var fallback_info := fallback_state.get_engine_backend_info()
	_assert(String(fallback_info.get("active_backend", "")) == "gdscript", "GameState should allow forcing the GDScript backend.")
	_assert(not bool(fallback_info.get("native_active", true)), "Forced GDScript backend should not report a native backend.")
	_assert(fallback_state.board.all_coords.size() == 7, "Forced GDScript backend should still initialize the board.")
	fallback_state.free()

	var preferred_state := GameState.new()
	preferred_state.prefer_native_engine = true
	preferred_state.setup_game(1)
	var preferred_info := preferred_state.get_engine_backend_info()
	_assert(bool(preferred_info.get("requested_native", false)), "Native-preferred GameState should record that native was requested.")
	var active_backend := String(preferred_info.get("active_backend", ""))
	_assert(active_backend == "native" or active_backend == "gdscript", "GameState backend should resolve to native or gdscript.")
	_assert(preferred_state.board.all_coords.size() == 7, "Native-preferred GameState should still initialize the board.")
	if not bool(preferred_info.get("native_active", false)):
		_assert(String(preferred_info.get("status", "")) != "", "Fallback backend should explain why native is unavailable.")
	preferred_state.free()


func _test_action_codec() -> void:
	var codec := ActionCodec.new(2)
	var pass_index := codec.pass_action_index()
	_assert(codec.action_count() == 20, "Radius-2 action space should contain 19 cells plus pass.")
	_assert(codec.is_pass_action(pass_index), "Pass action index should decode as pass.")

	var center := HexCoord.new(0, 0)
	var center_index := codec.coord_to_action_index(center)
	_assert(center_index >= 0 and center_index < pass_index, "Center coord should map to a non-pass action index.")
	var decoded_center: Dictionary = codec.decode_action_index(center_index)
	_assert(decoded_center.get("type", "") == "move", "Decoded center action should be a move.")
	_assert(decoded_center.has("coord") and decoded_center["coord"].equals(center), "Center action should round-trip through ActionCodec.")
	_assert(codec.decode_action_index(pass_index).get("type", "") == "pass", "Pass index should decode to a pass action.")

	var engine := MatchEngine.new()
	engine.setup_game(1)
	engine.consume_events()
	var radius_one_codec := ActionCodec.new(1)
	var mask: Array = radius_one_codec.legal_action_mask(engine)
	_assert(mask.size() == 8, "Radius-1 legal action mask should include 7 cells plus pass.")
	for value in mask:
		_assert(int(value) == 1, "Fresh game legal mask should allow every move and pass.")

	_assert(engine.execute_turn(center), "MatchEngine should allow an opening center move on radius 1.")
	engine.consume_events()
	mask = radius_one_codec.legal_action_mask(engine)
	_assert(mask[radius_one_codec.coord_to_action_index(center)] == 0, "Played coordinate should become illegal in the action mask.")
	_assert(mask[radius_one_codec.pass_action_index()] == 1, "Pass should remain legal during a normal turn.")


func _test_match_engine_events() -> void:
	var engine := MatchEngine.new()
	engine.setup_game(2)
	var setup_events: Array = engine.consume_events()
	_assert(setup_events.size() == 5, "MatchEngine setup should emit preview, board init, scoring state, and turn completion events.")
	_assert(String(setup_events[0].get("type", "")) == MatchEngine.EVENT_TERRITORY_FORMED, "Setup should start with preview territory events.")
	_assert(String(setup_events[1].get("type", "")) == MatchEngine.EVENT_TERRITORY_FORMED, "Setup should emit both territory preview owners.")
	_assert(String(setup_events[2].get("type", "")) == MatchEngine.EVENT_BOARD_INITIALIZED, "Setup should emit board initialization after preview events.")
	_assert(String(setup_events[3].get("type", "")) == MatchEngine.EVENT_SCORING_STATE_CHANGED, "Setup should emit initial scoring state after board initialization.")
	_assert(String(setup_events[4].get("type", "")) == MatchEngine.EVENT_TURN_COMPLETED, "Setup should finish with turn_completed.")

	var opening := HexCoord.new(0, 0)
	_assert(engine.execute_turn(opening), "MatchEngine should accept a legal opening move.")
	var turn_events: Array = engine.consume_events()
	_assert(not turn_events.is_empty(), "A successful MatchEngine move should emit events.")
	_assert(String(turn_events[0].get("type", "")) == MatchEngine.EVENT_PIECE_PLACED, "A successful move should first emit piece_placed.")
	_assert(String(turn_events[turn_events.size() - 1].get("type", "")) == MatchEngine.EVENT_TURN_COMPLETED, "A successful move should end with turn_completed.")
	_assert(engine.board.get_cell(opening) == HexBoard.CellState.BLACK, "Opening move should update the underlying MatchEngine board.")


func _test_capture() -> void:
	var board := HexBoard.new()
	board.initialize(2)
	board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.WHITE)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
		HexCoord.new(0, 1),
	]:
		board.set_cell(coord, HexBoard.CellState.BLACK)
	var captured := CaptureResolver.resolve(board, HexBoard.CellState.BLACK)
	_assert(captured.size() == 1 and captured[0].equals(HexCoord.new(0, 0)), "Single stone capture failed.")


func _test_threat_analysis() -> void:
	var empty_board := HexBoard.new()
	empty_board.initialize(2)
	var empty_map := ThreatAnalyzer.analyze(empty_board)
	_assert(empty_map.is_empty(), "Empty board should not produce threat entries.")

	var black_group_board := HexBoard.new()
	black_group_board.initialize(2)
	for coord in [
		HexCoord.new(0, 0),
		HexCoord.new(1, 0),
	]:
		black_group_board.set_cell(coord, HexBoard.CellState.BLACK)
	for coord in [
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
		HexCoord.new(1, 1),
		HexCoord.new(2, -1),
	]:
		black_group_board.set_cell(coord, HexBoard.CellState.WHITE)
	var black_group_map := ThreatAnalyzer.analyze(black_group_board)
	_assert(black_group_map.size() == 8, "Threat analysis should only cover occupied stones.")
	for coord in [
		HexCoord.new(0, 0),
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
		HexCoord.new(1, 1),
		HexCoord.new(2, -1),
	]:
		_assert(black_group_map.has(coord.to_key()), "Threat analysis missed occupied coord %s." % coord.to_key())
	_assert_group_entries(
		black_group_map,
		[HexCoord.new(0, 0), HexCoord.new(1, 0)],
		2,
		ThreatAnalyzer.THREAT_LEVEL_WARNING
	)

	var disconnected_board := HexBoard.new()
	disconnected_board.initialize(2)
	disconnected_board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.BLACK)
	disconnected_board.set_cell(HexCoord.new(2, 0), HexBoard.CellState.BLACK)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
	]:
		disconnected_board.set_cell(coord, HexBoard.CellState.WHITE)
	var disconnected_map := ThreatAnalyzer.analyze(disconnected_board)
	_assert_group_entries(
		disconnected_map,
		[HexCoord.new(0, 0)],
		1,
		ThreatAnalyzer.THREAT_LEVEL_DANGER
	)
	_assert_threat_entry(disconnected_map, HexCoord.new(2, 0), 2, ThreatAnalyzer.THREAT_LEVEL_WARNING)

	var danger_board := HexBoard.new()
	danger_board.initialize(2)
	danger_board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.BLACK)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 1),
		HexCoord.new(0, 1),
	]:
		danger_board.set_cell(coord, HexBoard.CellState.WHITE)
	var danger_map := ThreatAnalyzer.analyze(danger_board)
	_assert_threat_entry(danger_map, HexCoord.new(0, 0), 1, ThreatAnalyzer.THREAT_LEVEL_DANGER)

	var zero_liberty_board := HexBoard.new()
	zero_liberty_board.initialize(1)
	zero_liberty_board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.BLACK)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
		HexCoord.new(0, 1),
	]:
		zero_liberty_board.set_cell(coord, HexBoard.CellState.WHITE)
	var zero_liberty_map := ThreatAnalyzer.analyze(zero_liberty_board)
	_assert_threat_entry(zero_liberty_map, HexCoord.new(0, 0), 0, ThreatAnalyzer.THREAT_LEVEL_DANGER)

	var safe_board := HexBoard.new()
	safe_board.initialize(2)
	safe_board.set_cell(HexCoord.new(2, 0), HexBoard.CellState.BLACK)
	var safe_map := ThreatAnalyzer.analyze(safe_board)
	_assert_threat_entry(safe_map, HexCoord.new(2, 0), 3, ThreatAnalyzer.THREAT_LEVEL_SAFE)

	var many_liberties_board := HexBoard.new()
	many_liberties_board.initialize(3)
	many_liberties_board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.BLACK)
	var many_liberties_map := ThreatAnalyzer.analyze(many_liberties_board)
	_assert_threat_entry(many_liberties_map, HexCoord.new(0, 0), 6, ThreatAnalyzer.THREAT_LEVEL_SAFE)


func _test_territory() -> void:
	var board := HexBoard.new()
	board.initialize(3)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
		HexCoord.new(0, 1),
	]:
		board.set_cell(coord, HexBoard.CellState.BLACK)
	var region := TerritoryResolver.resolve(board, HexBoard.CellState.BLACK)
	_assert(region.size() == 1 and region[0].equals(HexCoord.new(0, 0)), "Closed territory detection failed.")


func _test_boundary_not_territory() -> void:
	var board := HexBoard.new()
	board.initialize(2)
	board.set_cell(HexCoord.new(0, -1), HexBoard.CellState.BLACK)
	board.set_cell(HexCoord.new(1, -1), HexBoard.CellState.BLACK)
	board.set_cell(HexCoord.new(1, 0), HexBoard.CellState.BLACK)
	var region := TerritoryResolver.resolve(board, HexBoard.CellState.BLACK)
	_assert(region.is_empty(), "Boundary-connected empty region should not become territory.")


func _test_score() -> void:
	var board := HexBoard.new()
	board.initialize(3)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
		HexCoord.new(0, 1),
	]:
		board.set_cell(coord, HexBoard.CellState.BLACK)
	board.set_cell(HexCoord.new(2, -2), HexBoard.CellState.WHITE)
	var scores := ScoreCalculator.calculate(board)
	_assert(scores[0] == 7 and scores[1] == 1, "Chinese-style score calculation failed.")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _assert_threat_entry(
	threat_map: Dictionary,
	coord: HexCoord,
	expected_liberties: int,
	expected_level: String,
) -> void:
	var entry: Dictionary = threat_map.get(coord.to_key(), {})
	_assert(not entry.is_empty(), "Threat analysis missing entry for %s." % coord.to_key())
	_assert(entry.size() == 2, "Threat analysis should only expose %s and %s for %s." % [ThreatAnalyzer.THREAT_LIBERTIES_KEY, ThreatAnalyzer.THREAT_LEVEL_KEY, coord.to_key()])
	_assert(entry.has(ThreatAnalyzer.THREAT_LIBERTIES_KEY), "Threat analysis missing %s for %s." % [ThreatAnalyzer.THREAT_LIBERTIES_KEY, coord.to_key()])
	_assert(entry.has(ThreatAnalyzer.THREAT_LEVEL_KEY), "Threat analysis missing %s for %s." % [ThreatAnalyzer.THREAT_LEVEL_KEY, coord.to_key()])
	_assert(typeof(entry.get(ThreatAnalyzer.THREAT_LIBERTIES_KEY)) == TYPE_INT, "Threat liberties must be int for %s." % coord.to_key())
	_assert(typeof(entry.get(ThreatAnalyzer.THREAT_LEVEL_KEY)) == TYPE_STRING, "Threat level must be String for %s." % coord.to_key())
	_assert(int(entry[ThreatAnalyzer.THREAT_LIBERTIES_KEY]) == expected_liberties, "Unexpected liberty count for %s." % coord.to_key())
	_assert(String(entry[ThreatAnalyzer.THREAT_LEVEL_KEY]) == expected_level, "Unexpected threat level for %s." % coord.to_key())


func _assert_group_entries(
	threat_map: Dictionary,
	coords: Array,
	expected_liberties: int,
	expected_level: String,
) -> void:
	for coord: HexCoord in coords:
		_assert_threat_entry(threat_map, coord, expected_liberties, expected_level)

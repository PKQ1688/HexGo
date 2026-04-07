extends SceneTree

const ActionCodec = preload("res://scripts/core/ActionCodec.gd")
const EngineProtocol = preload("res://scripts/core/EngineProtocol.gd")
const HexBoard = preload("res://scripts/core/HexBoard.gd")
const HexCoord = preload("res://scripts/core/HexCoord.gd")
const MatchEngine = preload("res://scripts/core/MatchEngine.gd")
const ScoreCalculator = preload("res://scripts/core/ScoreCalculator.gd")
const TurnSimulator = preload("res://scripts/core/TurnSimulator.gd")

const OUTPUT_PATH := "res://tests/fixtures/shared_engine/parity_cases.json"
const RULES := {"scoring_mode": "manual_review"}


func _init() -> void:
	var payload := _build_payload()
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		_fail("Failed to create fixture directory: %s" % absolute_path.get_base_dir())

	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_fail("Failed to open fixture file for writing: %s" % absolute_path)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("Exported shared engine parity fixtures to %s" % absolute_path)
	quit()


func _build_payload() -> Dictionary:
	return {
		"protocol_version": EngineProtocol.PROTOCOL_VERSION,
		"generated_by": "tests/export_shared_engine_fixtures.gd",
		"cases": [
			_build_initial_state_case(),
			_build_opening_move_case(),
			_build_capture_case(),
			_build_double_pass_case(),
			_build_toggle_dead_group_case(),
		],
	}


func _build_initial_state_case() -> Dictionary:
	var engine := MatchEngine.new()
	engine.setup_game(2)
	var codec := ActionCodec.new(2)
	var initial_events := EngineProtocol.serialize_events(engine.consume_events())
	return {
		"name": "initial_radius_2",
		"rules": EngineProtocol.build_rules_config(2, RULES),
		"initial": engine.build_observation(codec, RULES),
		"bootstrap_events": initial_events,
		"steps": [],
	}


func _build_opening_move_case() -> Dictionary:
	var engine := MatchEngine.new()
	engine.setup_game(2)
	engine.consume_events()
	var codec := ActionCodec.new(2)
	var center := HexCoord.new(0, 0)
	return _build_case_with_steps(
		"opening_center_move",
		engine,
		codec,
		[
			{"operation": "move", "coord": center},
		]
	)


func _build_capture_case() -> Dictionary:
	var engine := MatchEngine.new()
	engine.setup_game(2)
	engine.consume_events()
	engine.board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.WHITE)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
	]:
		engine.board.set_cell(coord, HexBoard.CellState.BLACK)
	engine.current_player = MatchEngine.Player.BLACK
	_sync_engine_state(engine)
	var codec := ActionCodec.new(2)
	return _build_case_with_steps(
		"single_capture",
		engine,
		codec,
		[
			{"operation": "move", "coord": HexCoord.new(0, 1)},
		]
	)


func _build_double_pass_case() -> Dictionary:
	var engine := MatchEngine.new()
	engine.setup_game(2)
	engine.consume_events()
	var codec := ActionCodec.new(2)
	return _build_case_with_steps(
		"double_pass_to_scoring",
		engine,
		codec,
		[
			{"operation": "pass"},
			{"operation": "pass"},
		]
	)


func _build_toggle_dead_group_case() -> Dictionary:
	var engine := MatchEngine.new()
	engine.setup_game(2)
	engine.consume_events()
	var codec := ActionCodec.new(2)
	return _build_case_with_steps(
		"toggle_dead_group_after_scoring",
		engine,
		codec,
		[
			{"operation": "move", "coord": HexCoord.new(0, 0)},
			{"operation": "pass"},
			{"operation": "pass"},
			{"operation": "toggle_dead_group", "coord": HexCoord.new(0, 0)},
		]
	)


func _build_case_with_steps(name: String, engine, codec, operations: Array) -> Dictionary:
	var steps: Array = []
	for operation in operations:
		steps.append(_apply_operation(engine, codec, operation))
	return {
		"name": name,
		"rules": EngineProtocol.build_rules_config(engine.board_radius, RULES),
		"initial": engine.build_observation(codec, RULES) if operations.is_empty() else null,
		"initial_before_steps": engine.build_observation(codec, RULES) if not operations.is_empty() else {},
		"steps": steps,
	}


func _apply_operation(engine, codec, operation: Dictionary) -> Dictionary:
	var before := engine.build_observation(codec, RULES)
	var accepted := false
	var serialized_action := {
		"operation": String(operation.get("operation", "unknown")),
	}
	match String(operation.get("operation", "")):
		"move":
			var coord = operation.get("coord")
			serialized_action["coord"] = EngineProtocol.serialize_coord(coord)
			serialized_action["action_index"] = int(codec.coord_to_action_index(coord))
			accepted = engine.execute_turn(coord)
		"pass":
			serialized_action["action_index"] = int(codec.pass_action_index())
			accepted = engine.record_pass()
		"toggle_dead_group":
			var toggle_coord = operation.get("coord")
			serialized_action["coord"] = EngineProtocol.serialize_coord(toggle_coord)
			accepted = engine.toggle_dead_group(toggle_coord)
		"resume_play":
			accepted = engine.resume_play()
		"confirm_scoring":
			accepted = engine.confirm_scoring()
		_:
			accepted = false
	var events := EngineProtocol.serialize_events(engine.consume_events())
	var after := engine.build_observation(codec, RULES)
	return {
		"before": before,
		"action": serialized_action,
		"accepted": accepted,
		"events": events,
		"after": after,
	}


func _sync_engine_state(engine) -> void:
	engine.phase = MatchEngine.Phase.WAITING
	engine.consecutive_passes = 0
	engine.previous_board_signature = ""
	engine.current_board_signature = TurnSimulator.board_signature(engine.board)
	engine.score_breakdown = ScoreCalculator.calculate_breakdown(engine.board, engine.marked_dead_stones)
	engine.scores = ScoreCalculator.totals_from_breakdown(engine.score_breakdown)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

extends SceneTree

const HexBoard = preload("res://scripts/core/HexBoard.gd")
const HexCoord = preload("res://scripts/core/HexCoord.gd")
const MatchConfig = preload("res://scripts/ai/MatchConfig.gd")
const ThreatAnalyzer = preload("res://scripts/core/ThreatAnalyzer.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	assert(scene != null, "Failed to load Main.tscn.")
	var main = scene.instantiate()
	assert(main != null, "Failed to instantiate Main.tscn.")
	root.add_child(main)
	main.start_match({
		"black_control": MatchConfig.PlayerControl.HUMAN,
		"white_control": MatchConfig.PlayerControl.HUMAN,
	})
	await process_frame
	_assert(main.board_view.influence_renderer.heatmap_container.get_child_count() == 0, "Heatmap container should start empty.")
	var center := HexCoord.new(0, 0)
	var moves := [
		center,
		HexCoord.new(1, 0),
		HexCoord.new(3, 0),
		HexCoord.new(0, 1),
		HexCoord.new(3, -1),
		HexCoord.new(-1, 1),
		HexCoord.new(4, -1),
		HexCoord.new(-1, 0),
	]
	for move in moves:
		_assert(main.game_state.execute_turn(move), "Expected legal move in smoke test for %s." % move.to_key())
		await process_frame

	_assert(main.board_view.influence_renderer.heatmap_container.get_child_count() == 0, "Heatmap container should stay empty after board updates.")
	var visible_threats: Dictionary = main.game_state.get_visible_threats()
	_assert(visible_threats.has(center.to_key()), "Center stone should be present in visible threats.")
	var center_threat: Dictionary = visible_threats[center.to_key()]
	var threat_level := String(center_threat.get(ThreatAnalyzer.THREAT_LEVEL_KEY, ""))
	_assert(threat_level == ThreatAnalyzer.THREAT_LEVEL_WARNING or threat_level == ThreatAnalyzer.THREAT_LEVEL_DANGER, "Center stone should be WARNING or DANGER, got %s." % threat_level)

	var center_piece = main.board_view.piece_renderer.piece_nodes[center.to_key()]
	assert(center_piece != null, "Expected center piece node to exist.")
	var danger_badge = center_piece.get_node("DangerBadge")
	assert(danger_badge != null, "Expected center piece to have a DangerBadge node.")
	_assert(danger_badge.visible, "Expected center piece's DangerBadge to be visible.")
	main.queue_free()
	await process_frame

	await _test_capture_visuals_stay_in_sync(scene)
	await process_frame
	await _test_window_zoom_shortcuts(scene)
	await process_frame
	print("Smoke scene test passed.")
	quit()


func _test_capture_visuals_stay_in_sync(scene: PackedScene) -> void:
	var main = scene.instantiate()
	root.add_child(main)
	main.start_match({
		"black_control": MatchConfig.PlayerControl.HUMAN,
		"white_control": MatchConfig.PlayerControl.HUMAN,
	})
	await process_frame

	for move in [
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
	]:
		_assert(main.game_state.execute_turn(move), "Expected legal move in capture visual sync test for %s." % move.to_key())
		await process_frame

	await create_timer(0.35).timeout
	var expected_pieces: int = _live_piece_count(main.game_state.board)
	var rendered_pieces: int = main.board_view.piece_renderer.pieces_container.get_child_count()
	_assert(rendered_pieces == expected_pieces, "Captured stones should not remain rendered. Expected %d rendered pieces, got %d." % [expected_pieces, rendered_pieces])

	main.queue_free()
	await process_frame


func _test_window_zoom_shortcuts(scene: PackedScene) -> void:
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame

	var root_window = main.get_tree().root
	var original_scale: float = root_window.content_scale_factor
	root_window.content_scale_factor = 1.0
	main._center_board()

	var zoom_in_event := InputEventKey.new()
	zoom_in_event.pressed = true
	zoom_in_event.keycode = KEY_EQUAL
	zoom_in_event.meta_pressed = true
	zoom_in_event.ctrl_pressed = true
	_assert(main._apply_zoom_shortcut(zoom_in_event), "Cmd/Ctrl + = should trigger UI zoom in.")
	_assert(is_equal_approx(root_window.content_scale_factor, 1.1), "Cmd/Ctrl + = should increase UI zoom scale to 1.1.")

	var zoom_out_event := InputEventKey.new()
	zoom_out_event.pressed = true
	zoom_out_event.keycode = KEY_MINUS
	zoom_out_event.meta_pressed = true
	zoom_out_event.ctrl_pressed = true
	_assert(main._apply_zoom_shortcut(zoom_out_event), "Cmd/Ctrl + - should trigger UI zoom out.")
	_assert(is_equal_approx(root_window.content_scale_factor, 1.0), "Cmd/Ctrl + - should restore UI zoom scale to 1.0.")

	root_window.content_scale_factor = 1.3
	main._center_board()
	var reset_event := InputEventKey.new()
	reset_event.pressed = true
	reset_event.keycode = KEY_0
	reset_event.meta_pressed = true
	reset_event.ctrl_pressed = true
	_assert(main._apply_zoom_shortcut(reset_event), "Cmd/Ctrl + 0 should reset UI zoom.")
	_assert(is_equal_approx(root_window.content_scale_factor, 1.0), "Cmd/Ctrl + 0 should reset UI zoom scale to 1.0.")

	root_window.content_scale_factor = original_scale
	main._center_board()
	main.queue_free()
	await process_frame


func _live_piece_count(board) -> int:
	var count := 0
	for coord in board.all_coords:
		var state: int = board.get_cell(coord)
		if state == HexBoard.CellState.BLACK or state == HexBoard.CellState.WHITE:
			count += 1
	return count


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)

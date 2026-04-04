extends SceneTree

const HexCoord = preload("res://scripts/core/HexCoord.gd")
const ThreatAnalyzer = preload("res://scripts/core/ThreatAnalyzer.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	assert(scene != null, "Failed to load Main.tscn.")
	var main = scene.instantiate()
	assert(main != null, "Failed to instantiate Main.tscn.")
	root.add_child(main)
	main.start_match({})
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
	await process_frame
	print("Smoke scene test passed.")
	quit()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)

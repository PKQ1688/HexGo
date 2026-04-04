class_name InfluenceRenderer
extends Node2D

signal preview_summary_changed(summary)

const CaptureResolverRef = preload("res://scripts/core/CaptureResolver.gd")
const HexBoardRef = preload("res://scripts/core/HexBoard.gd")

const BLACK_TINT := Color(0.21, 0.60, 0.96, 1.0)
const WHITE_TINT := Color(0.96, 0.73, 0.20, 1.0)
const INVALID_TINT := Color(0.93, 0.27, 0.22, 1.0)
const CAPTURE_TINT := Color(1.0, 0.48, 0.38, 1.0)
const INSPECT_TINT := Color(0.89, 0.94, 1.0, 1.0)

var board = null
var layout = null
var game_state = null
@onready var heatmap_container: Node2D = $Heatmap
@onready var preview_container: Node2D = $Preview


func setup(board_model, layout_model, state) -> void:
	board = board_model
	layout = layout_model
	game_state = state
	sync_from_board(board_model)


func sync_from_board(board_model) -> void:
	board = board_model
	_clear_heatmap()
	clear_preview()


func clear_preview() -> void:
	for child in preview_container.get_children():
		child.queue_free()
	preview_summary_changed.emit({})


func update_focus(coord, is_valid: bool) -> void:
	clear_preview()

	if board == null or layout == null or game_state == null or coord == null:
		return

	var cell_state: int = board.get_cell(coord)
	if cell_state == HexBoardRef.CellState.BLACK or cell_state == HexBoardRef.CellState.WHITE:
		_show_group_preview(coord, cell_state)
		return

	if cell_state != HexBoardRef.CellState.EMPTY or game_state.is_scoring_phase():
		return

	_show_move_preview(coord, is_valid)


func _clear_heatmap() -> void:
	for child in heatmap_container.get_children():
		child.queue_free()


func _show_group_preview(coord, piece_state: int) -> void:
	var group: Array = CaptureResolverRef.find_group(board, coord, piece_state)
	if group.is_empty():
		return

	var liberty_coords := _collect_liberties(board, group)
	var base_tint := _color_for_state(piece_state)
	var liberty_tint := _liberty_tint(liberty_coords.size(), base_tint)

	for item in group:
		_add_focus_overlay(item, base_tint, 0.18, layout.hex_size - 4.0)

	for liberty in liberty_coords:
		_add_liberty_marker(liberty, liberty_tint)

	preview_summary_changed.emit({
		"type": "group",
		"player": piece_state,
		"liberties": liberty_coords.size(),
	})


func _show_move_preview(coord, is_valid: bool) -> void:
	var preview_board = board.clone()
	var piece_state := HexBoardRef.CellState.BLACK if game_state.current_player == 0 else HexBoardRef.CellState.WHITE
	preview_board.set_cell(coord, piece_state)

	var captured: Array = CaptureResolverRef.resolve(preview_board, piece_state)
	for captured_coord in captured:
		preview_board.set_cell(captured_coord, HexBoardRef.CellState.EMPTY)

	var group: Array = CaptureResolverRef.find_group(preview_board, coord, piece_state)
	if group.is_empty():
		return

	var liberties := _collect_liberties(preview_board, group)
	var base_tint := _color_for_state(piece_state) if is_valid else INVALID_TINT
	var liberty_tint := _liberty_tint(liberties.size(), base_tint)

	for item in group:
		_add_focus_overlay(item, base_tint, 0.22 if is_valid else 0.16, layout.hex_size - 4.0)

	for liberty in liberties:
		_add_liberty_marker(liberty, liberty_tint)

	for captured_coord in captured:
		_add_capture_marker(captured_coord)

	_add_focus_overlay(coord, base_tint, 0.32 if is_valid else 0.22, layout.hex_size - 9.0)
	preview_summary_changed.emit({
		"type": "move",
		"is_valid": is_valid,
		"player": piece_state,
		"liberties": liberties.size(),
		"captures": captured.size(),
	})


func _collect_liberties(source_board, group: Array) -> Array:
	var liberty_map: Dictionary = {}
	var liberties: Array = []

	for coord in group:
		for neighbor in source_board.get_neighbors(coord):
			if source_board.get_cell(neighbor) != HexBoardRef.CellState.EMPTY:
				continue

			var key: String = neighbor.to_key()
			if liberty_map.has(key):
				continue

			liberty_map[key] = true
			liberties.append(neighbor)

	return liberties


func _add_focus_overlay(coord, tint: Color, alpha: float, radius: float) -> void:
	var overlay := Polygon2D.new()
	overlay.polygon = _build_hexagon_points(radius)
	overlay.position = layout.cube_to_pixel(coord)
	overlay.color = Color(tint.r, tint.g, tint.b, alpha)
	preview_container.add_child(overlay)

	var border := Line2D.new()
	border.width = 2.0
	border.default_color = Color(tint.r, tint.g, tint.b, minf(alpha + 0.25, 0.7))
	border.closed = true
	border.joint_mode = Line2D.LINE_JOINT_ROUND
	border.points = _build_hexagon_points(radius + 1.0)
	border.position = overlay.position
	preview_container.add_child(border)


func _add_liberty_marker(coord, tint: Color) -> void:
	var marker := Polygon2D.new()
	marker.polygon = _build_circle_points(layout.hex_size * 0.16, 14)
	marker.position = layout.cube_to_pixel(coord)
	marker.color = Color(tint.r, tint.g, tint.b, 0.90)
	preview_container.add_child(marker)

	var ring := Line2D.new()
	ring.width = 1.5
	ring.default_color = Color(1.0, 1.0, 1.0, 0.75)
	ring.closed = true
	ring.points = _build_circle_points(layout.hex_size * 0.22, 18)
	ring.position = marker.position
	preview_container.add_child(ring)


func _add_capture_marker(coord) -> void:
	var overlay := Polygon2D.new()
	overlay.polygon = _build_hexagon_points(layout.hex_size - 8.0)
	overlay.position = layout.cube_to_pixel(coord)
	overlay.color = Color(CAPTURE_TINT.r, CAPTURE_TINT.g, CAPTURE_TINT.b, 0.34)
	preview_container.add_child(overlay)

	var cross_a := Line2D.new()
	cross_a.width = 2.0
	cross_a.default_color = Color(1.0, 0.95, 0.92, 0.92)
	cross_a.points = PackedVector2Array([
		Vector2(-layout.hex_size * 0.20, -layout.hex_size * 0.20),
		Vector2(layout.hex_size * 0.20, layout.hex_size * 0.20),
	])
	cross_a.position = overlay.position
	preview_container.add_child(cross_a)

	var cross_b := Line2D.new()
	cross_b.width = 2.0
	cross_b.default_color = cross_a.default_color
	cross_b.points = PackedVector2Array([
		Vector2(layout.hex_size * 0.20, -layout.hex_size * 0.20),
		Vector2(-layout.hex_size * 0.20, layout.hex_size * 0.20),
	])
	cross_b.position = overlay.position
	preview_container.add_child(cross_b)


func _color_for_state(piece_state: int) -> Color:
	if piece_state == HexBoardRef.CellState.BLACK:
		return BLACK_TINT
	if piece_state == HexBoardRef.CellState.WHITE:
		return WHITE_TINT
	return INSPECT_TINT


func _liberty_tint(liberty_count: int, base_tint: Color) -> Color:
	if liberty_count <= 1:
		return INVALID_TINT
	if liberty_count == 2:
		return CAPTURE_TINT
	return base_tint


func _build_hexagon_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(6):
		var angle := deg_to_rad(60.0 * float(index))
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _build_circle_points(radius: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(steps):
		var angle := TAU * float(index) / float(steps)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

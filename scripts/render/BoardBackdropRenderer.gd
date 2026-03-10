class_name BoardBackdropRenderer
extends Node2D

var board = null
var layout = null
var board_extent: float = 0.0


func setup(board_model, layout_model) -> void:
	board = board_model
	layout = layout_model
	board_extent = _compute_board_extent()
	queue_redraw()


func _draw() -> void:
	if board == null or layout == null or board_extent <= 0.0:
		return

	draw_circle(Vector2(0, layout.hex_size * 0.9), board_extent * 1.34, Color(0.02, 0.04, 0.07, 0.34))
	draw_circle(Vector2.ZERO, board_extent * 1.26, Color(0.05, 0.09, 0.14, 0.88))
	draw_circle(Vector2.ZERO, board_extent * 0.98, Color(0.10, 0.14, 0.20, 0.44))

	var outer_plate := _build_hexagon(board_extent + layout.hex_size * 1.28)
	var inner_plate := _build_hexagon(board_extent + layout.hex_size * 0.62)
	var inner_ring := _build_hexagon(board_extent + layout.hex_size * 0.18)

	draw_colored_polygon(_offset_points(outer_plate, Vector2(0, layout.hex_size * 0.18)), Color(0.02, 0.03, 0.05, 0.42))
	draw_colored_polygon(outer_plate, Color(0.17, 0.12, 0.07, 0.94))
	draw_colored_polygon(inner_plate, Color(0.28, 0.20, 0.11, 0.92))
	draw_colored_polygon(inner_ring, Color(0.45, 0.33, 0.17, 0.34))

	_draw_loop(outer_plate, Color(0.82, 0.67, 0.35, 0.30), 3.4)
	_draw_loop(inner_plate, Color(0.95, 0.83, 0.58, 0.24), 2.2)
	_draw_loop(inner_ring, Color(1.0, 0.92, 0.74, 0.18), 1.4)

	for corner in _build_hexagon(board_extent + layout.hex_size * 0.92):
		draw_circle(corner * 0.93, layout.hex_size * 0.08, Color(0.96, 0.84, 0.58, 0.32))


func _draw_loop(points: PackedVector2Array, color: Color, width: float) -> void:
	var closed := PackedVector2Array(points)
	if closed.size() > 0:
		closed.append(points[0])
	draw_polyline(closed, color, width, true)


func _build_hexagon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(6):
		var angle := deg_to_rad(60.0 * float(index))
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	for point in points:
		shifted.append(point + offset)
	return shifted


func _compute_board_extent() -> float:
	if board == null or layout == null:
		return 0.0

	var max_distance := 0.0
	for coord in board.all_coords:
		max_distance = maxf(max_distance, layout.cube_to_pixel(coord).length())
	return max_distance + layout.hex_size * 1.1

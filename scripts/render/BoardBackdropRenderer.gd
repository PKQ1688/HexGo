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

	draw_circle(Vector2(0, layout.hex_size * 0.9), board_extent * 1.34, Color(0.86, 0.82, 0.74, 0.30))
	draw_circle(Vector2.ZERO, board_extent * 1.26, Color(0.96, 0.93, 0.86, 0.92))
	draw_circle(Vector2.ZERO, board_extent * 0.98, Color(0.90, 0.86, 0.77, 0.48))

	var outer_plate := _build_hexagon(board_extent + layout.hex_size * 1.28)
	var inner_plate := _build_hexagon(board_extent + layout.hex_size * 0.62)
	var inner_ring := _build_hexagon(board_extent + layout.hex_size * 0.18)

	draw_colored_polygon(_offset_points(outer_plate, Vector2(0, layout.hex_size * 0.18)), Color(0.64, 0.55, 0.40, 0.18))
	draw_colored_polygon(outer_plate, Color(0.82, 0.70, 0.50, 0.94))
	draw_colored_polygon(inner_plate, Color(0.90, 0.81, 0.63, 0.94))
	draw_colored_polygon(inner_ring, Color(0.98, 0.92, 0.78, 0.46))

	_draw_loop(outer_plate, Color(0.66, 0.51, 0.26, 0.34), 3.4)
	_draw_loop(inner_plate, Color(0.80, 0.64, 0.35, 0.28), 2.2)
	_draw_loop(inner_ring, Color(0.92, 0.79, 0.53, 0.22), 1.4)

	for corner in _build_hexagon(board_extent + layout.hex_size * 0.92):
		draw_circle(corner * 0.93, layout.hex_size * 0.08, Color(0.86, 0.68, 0.37, 0.34))


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

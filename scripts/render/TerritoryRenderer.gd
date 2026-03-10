class_name TerritoryRenderer
extends Node2D

const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const TerritoryResolverRef = preload("res://scripts/core/TerritoryResolver.gd")

const BLACK_FILL := Color(0.16, 0.47, 0.88, 0.42)
const WHITE_FILL := Color(0.95, 0.76, 0.24, 0.46)
const BLACK_EDGE := Color(0.62, 0.84, 1.0, 0.82)
const WHITE_EDGE := Color(1.0, 0.95, 0.72, 0.88)
const BLACK_MARK := Color(0.08, 0.10, 0.16, 0.92)
const WHITE_MARK := Color(0.98, 0.98, 0.96, 0.94)

var layout = null
var overlays_by_player := {
	0: {},
	1: {},
}

@onready var overlay_container: Node2D = $Overlays


func setup(board_model, layout_model) -> void:
	layout = layout_model
	sync_from_board(board_model)


func sync_from_board(board_model) -> void:
	var territory_map: Dictionary = TerritoryResolverRef.resolve_all(board_model)
	var black_coords: Array = territory_map.get(HexBoardRef.CellState.BLACK, [])
	var white_coords: Array = territory_map.get(HexBoardRef.CellState.WHITE, [])
	set_player_territory(black_coords, 0)
	set_player_territory(white_coords, 1)


func set_player_territory(coords: Array, player: int) -> void:
	if layout == null:
		return

	var player_nodes: Dictionary = overlays_by_player[player]
	var next_keys: Dictionary = {}
	for coord in coords:
		var key: String = coord.to_key()
		next_keys[key] = true
		if player_nodes.has(key):
			continue
		var overlay := _create_territory_overlay(coord, player)
		overlay_container.add_child(overlay)
		player_nodes[key] = overlay

	for key: String in player_nodes.keys():
		if next_keys.has(key):
			continue
		player_nodes[key].queue_free()
		player_nodes.erase(key)


func _create_territory_overlay(coord, player: int) -> Node2D:
	var container := Node2D.new()
	container.position = layout.cube_to_pixel(coord)

	var fill := Polygon2D.new()
	fill.polygon = _build_hexagon_points(layout.hex_size - 5.0)
	fill.color = BLACK_FILL if player == 0 else WHITE_FILL
	container.add_child(fill)

	var border := Line2D.new()
	border.width = 1.6
	border.default_color = BLACK_EDGE if player == 0 else WHITE_EDGE
	border.closed = true
	border.joint_mode = Line2D.LINE_JOINT_ROUND
	border.points = _build_hexagon_points(layout.hex_size - 3.5)
	container.add_child(border)

	if player == 0:
		var core := Polygon2D.new()
		core.polygon = _build_circle_points(layout.hex_size * 0.16, 18)
		core.color = BLACK_MARK
		container.add_child(core)

		var core_ring := Line2D.new()
		core_ring.width = 1.4
		core_ring.default_color = BLACK_EDGE
		core_ring.closed = true
		core_ring.points = _build_circle_points(layout.hex_size * 0.23, 20)
		container.add_child(core_ring)
	else:
		var ring := Line2D.new()
		ring.width = 2.3
		ring.default_color = WHITE_MARK
		ring.closed = true
		ring.points = _build_circle_points(layout.hex_size * 0.21, 22)
		container.add_child(ring)

		var glow := Polygon2D.new()
		glow.polygon = _build_circle_points(layout.hex_size * 0.10, 14)
		glow.color = Color(1.0, 0.98, 0.90, 0.34)
		container.add_child(glow)

	return container


func _build_hexagon_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(6):
		var angle := deg_to_rad(60.0 * float(index))
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _build_circle_points(radius: float, steps: int = 20) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(steps):
		var angle := TAU * float(index) / float(steps)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

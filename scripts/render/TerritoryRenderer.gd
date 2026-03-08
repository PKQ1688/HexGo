class_name TerritoryRenderer
extends Node2D

const HexBoardRef = preload("res://scripts/core/HexBoard.gd")
const TerritoryResolverRef = preload("res://scripts/core/TerritoryResolver.gd")

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
		var overlay := Polygon2D.new()
		overlay.polygon = _build_hexagon_points(layout.hex_size - 5.0)
		overlay.position = layout.cube_to_pixel(coord)
		overlay.color = Color(0.18, 0.45, 0.95, 0.30) if player == 0 else Color(0.95, 0.72, 0.12, 0.32)
		overlay_container.add_child(overlay)
		player_nodes[key] = overlay

	for key: String in player_nodes.keys():
		if next_keys.has(key):
			continue
		player_nodes[key].queue_free()
		player_nodes.erase(key)


func _build_hexagon_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(6):
		var angle := deg_to_rad(60.0 * float(index))
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

class_name BoardRenderer
extends Node2D

const HexCellScene = preload("res://scenes/HexCell.tscn")

var board = null
var layout = null
var cell_nodes: Dictionary = {}
var hovered_key: String = ""

@onready var cells_container: Node2D = $Cells


func setup(board_model, layout_model) -> void:
	board = board_model
	layout = layout_model
	_rebuild_cells()


func update_hover(coord, is_valid: bool) -> void:
	if hovered_key != "" and cell_nodes.has(hovered_key):
		cell_nodes[hovered_key].set_highlight_state(false, false)
	hovered_key = ""

	if coord == null:
		return

	var key: String = coord.to_key()
	if cell_nodes.has(key):
		cell_nodes[key].set_highlight_state(true, is_valid)
		hovered_key = key


func _rebuild_cells() -> void:
	for child in cells_container.get_children():
		child.queue_free()
	cell_nodes.clear()

	var polygon: PackedVector2Array = _build_hexagon_points(layout.hex_size - 1.5)
	for coord in board.all_coords:
		var cell = HexCellScene.instantiate()
		cells_container.add_child(cell)
		cell.position = layout.cube_to_pixel(coord)
		cell.coord_key = coord.to_key()
		cell.configure(polygon)
		cell_nodes[cell.coord_key] = cell


func _build_hexagon_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(6):
		var angle := deg_to_rad(60.0 * float(index))
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

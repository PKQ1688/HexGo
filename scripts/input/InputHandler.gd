class_name InputHandler
extends Node

signal cell_clicked(coord)
signal cell_hovered(coord)

var layout = null
var board_root: Node2D = null
var game_state = null
var last_hovered_key: String = ""
var input_enabled: bool = true


func setup(layout_model, board_node: Node2D, state) -> void:
	layout = layout_model
	board_root = board_node
	game_state = state
	set_process(true)
	set_process_unhandled_input(true)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled and last_hovered_key != "":
		last_hovered_key = ""
		cell_hovered.emit(null)


func _unhandled_input(event: InputEvent) -> void:
	if layout == null or board_root == null or game_state == null:
		return
	if not input_enabled:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_emit_click(board_root.to_local(event.position))
	elif event is InputEventScreenTouch and event.pressed:
		_emit_click(board_root.to_local(event.position))


func _process(_delta: float) -> void:
	if layout == null or board_root == null or game_state == null:
		return
	if not input_enabled:
		return

	var coord = _coord_from_local(board_root.get_local_mouse_position())
	var next_key: String = "" if coord == null else coord.to_key()
	if next_key == last_hovered_key:
		return

	last_hovered_key = next_key
	cell_hovered.emit(coord)


func _emit_click(local_position: Vector2) -> void:
	cell_clicked.emit(_coord_from_local(local_position))


func _coord_from_local(local_position: Vector2):
	var coord = layout.pixel_to_cube(local_position)
	if not game_state.board.is_valid_coord(coord):
		return null
	return coord

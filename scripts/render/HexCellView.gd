class_name HexCellView
extends Node2D

var coord_key: String = ""


func configure(points: PackedVector2Array) -> void:
	var background: Polygon2D = $Background
	var border: Line2D = $Border
	var highlight: Polygon2D = $Highlight
	background.polygon = points
	highlight.polygon = points

	var border_points := PackedVector2Array(points)
	if points.size() > 0:
		border_points.append(points[0])
	border.points = border_points


func set_highlight_state(is_visible: bool, is_valid: bool) -> void:
	var highlight: Polygon2D = $Highlight
	highlight.visible = is_visible
	if not is_visible:
		return
	highlight.color = Color(0.22, 0.78, 0.43, 0.35) if is_valid else Color(0.86, 0.27, 0.23, 0.35)

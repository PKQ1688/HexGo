class_name HexCellView
extends Node2D

var coord_key: String = ""


func configure(points: PackedVector2Array) -> void:
	var shadow: Polygon2D = $Shadow
	var background: Polygon2D = $Background
	var inner: Polygon2D = $Inner
	var border: Line2D = $Border
	var edge_glow: Line2D = $EdgeGlow
	var highlight: Polygon2D = $Highlight
	shadow.polygon = _scale_points(points, 1.04)
	shadow.position = Vector2(0, 4.5)
	background.polygon = points
	inner.polygon = _scale_points(points, 0.86)
	inner.position = Vector2(0, -1.5)
	highlight.polygon = points

	var border_points := PackedVector2Array(points)
	if points.size() > 0:
		border_points.append(points[0])
	border.points = border_points
	edge_glow.points = _closed_points(_scale_points(points, 0.92))


func set_highlight_state(is_visible: bool, is_valid: bool, is_inspect: bool = false) -> void:
	var highlight: Polygon2D = $Highlight
	highlight.visible = is_visible
	if not is_visible:
		return
	if is_inspect:
		highlight.color = Color(0.74, 0.88, 1.0, 0.28)
		return
	highlight.color = Color(0.26, 0.94, 0.58, 0.34) if is_valid else Color(1.0, 0.36, 0.28, 0.34)


func _scale_points(points: PackedVector2Array, scale_factor: float) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	for point in points:
		scaled.append(point * scale_factor)
	return scaled


func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := PackedVector2Array(points)
	if points.size() > 0:
		closed.append(points[0])
	return closed

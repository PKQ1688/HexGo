class_name SceneBackdrop
extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_on_viewport_resized)
	queue_redraw()


func _draw() -> void:
	var rect := get_rect()
	var size := rect.size
	if size.x <= 0.0 or size.y <= 0.0:
		return

	draw_rect(rect, Color(0.04, 0.06, 0.09, 1.0), true)
	draw_circle(size * Vector2(0.24, 0.18), minf(size.x, size.y) * 0.34, Color(0.10, 0.18, 0.30, 0.30))
	draw_circle(size * Vector2(0.78, 0.22), minf(size.x, size.y) * 0.22, Color(0.18, 0.13, 0.06, 0.20))
	draw_circle(size * Vector2(0.55, 0.78), minf(size.x, size.y) * 0.42, Color(0.08, 0.12, 0.18, 0.42))

	var top_band := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(size.x, 0.0),
		Vector2(size.x, size.y * 0.22),
		Vector2(0.0, size.y * 0.12),
	])
	draw_colored_polygon(top_band, Color(0.07, 0.10, 0.15, 0.55))

	var accent := PackedVector2Array([
		Vector2(size.x * 0.66, size.y * 0.0),
		Vector2(size.x * 1.0, size.y * 0.0),
		Vector2(size.x * 1.0, size.y * 0.16),
		Vector2(size.x * 0.58, size.y * 0.10),
	])
	draw_colored_polygon(accent, Color(0.34, 0.24, 0.10, 0.18))


func _on_viewport_resized() -> void:
	queue_redraw()

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

	draw_rect(rect, Color(0.98, 0.96, 0.92, 1.0), true)
	draw_circle(size * Vector2(0.24, 0.18), minf(size.x, size.y) * 0.34, Color(0.72, 0.82, 0.96, 0.24))
	draw_circle(size * Vector2(0.78, 0.22), minf(size.x, size.y) * 0.22, Color(0.92, 0.79, 0.58, 0.18))
	draw_circle(size * Vector2(0.55, 0.78), minf(size.x, size.y) * 0.42, Color(0.84, 0.88, 0.94, 0.36))

	var top_band := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(size.x, 0.0),
		Vector2(size.x, size.y * 0.22),
		Vector2(0.0, size.y * 0.12),
	])
	draw_colored_polygon(top_band, Color(0.88, 0.90, 0.94, 0.62))

	var accent := PackedVector2Array([
		Vector2(size.x * 0.66, size.y * 0.0),
		Vector2(size.x * 1.0, size.y * 0.0),
		Vector2(size.x * 1.0, size.y * 0.16),
		Vector2(size.x * 0.58, size.y * 0.10),
	])
	draw_colored_polygon(accent, Color(0.83, 0.69, 0.46, 0.20))


func _on_viewport_resized() -> void:
	queue_redraw()

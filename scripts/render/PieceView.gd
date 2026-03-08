class_name PieceView
extends Node2D

@export var radius: float = 20.0


func _ready() -> void:
	var shadow: Polygon2D = $Shadow
	var circle: Polygon2D = $Circle
	var main_polygon := _build_circle(radius)
	circle.polygon = main_polygon

	var shadow_polygon := _build_circle(radius * 1.02)
	shadow.polygon = shadow_polygon
	shadow.position = Vector2(2, 3)


func set_player(player: int) -> void:
	var shadow: Polygon2D = $Shadow
	var circle: Polygon2D = $Circle
	if player == 0:
		circle.color = Color(0.10, 0.10, 0.14)
		shadow.color = Color(0.0, 0.0, 0.0, 0.18)
	else:
		circle.color = Color(0.95, 0.97, 0.99)
		shadow.color = Color(0.0, 0.0, 0.0, 0.12)


func set_dead_marked(is_dead: bool) -> void:
	var circle: Polygon2D = $Circle
	var shadow: Polygon2D = $Shadow
	if is_dead:
		modulate = Color(1.0, 0.72, 0.72, 0.58)
		circle.scale = Vector2(0.88, 0.88)
		shadow.modulate = Color(1.0, 0.4, 0.4, 0.6)
	else:
		modulate = Color(1, 1, 1, 1)
		circle.scale = Vector2.ONE
		shadow.modulate = Color(1, 1, 1, 1)


func play_place_animation() -> void:
	scale = Vector2(0.2, 0.2)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.16)


func play_capture_animation() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.2, 0.2), 0.18)
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(queue_free)


func _build_circle(circle_radius: float, steps: int = 24) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(steps):
		var angle := TAU * float(index) / float(steps)
		points.append(Vector2(cos(angle), sin(angle)) * circle_radius)
	return points

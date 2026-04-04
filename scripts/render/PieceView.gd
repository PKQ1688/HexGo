class_name PieceView
extends Node2D

@export var radius: float = 20.0

var danger_badge: Node2D
var danger_badge_bg: Polygon2D
var danger_badge_mark: Line2D
var danger_badge_dot: Polygon2D


func _ready() -> void:
	var shadow: Polygon2D = $Shadow
	var circle: Polygon2D = $Circle
	var main_polygon := _build_circle(radius)
	circle.polygon = main_polygon

	var shadow_polygon := _build_circle(radius * 1.05)
	shadow.polygon = shadow_polygon
	shadow.position = Vector2(2.5, 4)

	# Gloss highlight overlay for a polished stone look
	var gloss := Polygon2D.new()
	gloss.name = "Gloss"
	add_child(gloss)
	gloss.polygon = _build_circle(radius * 0.44, 14)
	gloss.position = Vector2(-radius * 0.20, -radius * 0.24)
	gloss.color = Color(1.0, 1.0, 1.0, 0.15)

	var dead_ring := Line2D.new()
	dead_ring.name = "DeadRing"
	dead_ring.width = 2.8
	dead_ring.default_color = Color(1.0, 0.45, 0.40, 0.96)
	dead_ring.closed = true
	dead_ring.points = _build_circle(radius * 0.90, 28)
	dead_ring.visible = false
	add_child(dead_ring)

	var dead_cross_a := Line2D.new()
	dead_cross_a.name = "DeadCrossA"
	dead_cross_a.width = 3.0
	dead_cross_a.default_color = Color(1.0, 0.40, 0.36, 0.94)
	dead_cross_a.points = PackedVector2Array([
		Vector2(-radius * 0.52, -radius * 0.52),
		Vector2(radius * 0.52, radius * 0.52),
	])
	dead_cross_a.visible = false
	add_child(dead_cross_a)

	var dead_cross_b := Line2D.new()
	dead_cross_b.name = "DeadCrossB"
	dead_cross_b.width = 3.0
	dead_cross_b.default_color = dead_cross_a.default_color
	dead_cross_b.points = PackedVector2Array([
		Vector2(radius * 0.52, -radius * 0.52),
		Vector2(-radius * 0.52, radius * 0.52),
	])
	dead_cross_b.visible = false
	add_child(dead_cross_b)

	_ensure_danger_badge()
	set_threat_level("")


func set_player(player: int) -> void:
	var shadow: Polygon2D = $Shadow
	var circle: Polygon2D = $Circle
	var gloss = get_node_or_null("Gloss")
	if player == 0:
		circle.color = Color(0.09, 0.09, 0.12)
		shadow.color = Color(0.0, 0.0, 0.0, 0.28)
		if gloss:
			gloss.color = Color(1.0, 1.0, 1.0, 0.12)
	else:
		circle.color = Color(0.97, 0.96, 0.94)
		shadow.color = Color(0.0, 0.0, 0.0, 0.16)
		if gloss:
			gloss.color = Color(1.0, 1.0, 1.0, 0.38)


func set_dead_marked(is_dead: bool) -> void:
	var circle: Polygon2D = $Circle
	var shadow: Polygon2D = $Shadow
	var dead_ring: Line2D = $DeadRing
	var dead_cross_a: Line2D = $DeadCrossA
	var dead_cross_b: Line2D = $DeadCrossB
	if is_dead:
		modulate = Color(1.0, 0.78, 0.78, 0.72)
		circle.scale = Vector2(0.84, 0.84)
		shadow.modulate = Color(1.0, 0.36, 0.36, 0.7)
		dead_ring.visible = true
		dead_cross_a.visible = true
		dead_cross_b.visible = true
	else:
		modulate = Color(1, 1, 1, 1)
		circle.scale = Vector2.ONE
		shadow.modulate = Color(1, 1, 1, 1)
		dead_ring.visible = false
		dead_cross_a.visible = false
		dead_cross_b.visible = false


func set_threat_level(threat_level: String) -> void:
	_ensure_danger_badge()

	var is_warning := threat_level == "WARNING"
	var is_danger := threat_level == "DANGER"
	danger_badge.visible = is_warning or is_danger
	if not danger_badge.visible:
		return

	if is_warning:
		danger_badge_bg.color = Color(0.98, 0.66, 0.16, 0.98)
	elif is_danger:
		danger_badge_bg.color = Color(0.90, 0.25, 0.22, 0.98)


func _ensure_danger_badge() -> void:
	if danger_badge != null:
		return

	danger_badge = Node2D.new()
	danger_badge.name = "DangerBadge"
	danger_badge.position = Vector2(radius * 0.44, -radius * 0.42)
	danger_badge.z_index = 10
	danger_badge.visible = false
	add_child(danger_badge)

	danger_badge_bg = Polygon2D.new()
	danger_badge_bg.name = "Background"
	danger_badge_bg.color = Color(0.98, 0.66, 0.16, 0.98)
	danger_badge_bg.polygon = _build_circle(radius * 0.19, 18)
	danger_badge.add_child(danger_badge_bg)

	danger_badge_mark = Line2D.new()
	danger_badge_mark.name = "Mark"
	danger_badge_mark.width = 2.3
	danger_badge_mark.default_color = Color(1.0, 1.0, 1.0, 0.98)
	danger_badge_mark.points = PackedVector2Array([
		Vector2(0, -radius * 0.10),
		Vector2(0, radius * 0.03),
	])
	danger_badge.add_child(danger_badge_mark)

	danger_badge_dot = Polygon2D.new()
	danger_badge_dot.name = "Dot"
	danger_badge_dot.color = Color(1.0, 1.0, 1.0, 0.98)
	danger_badge_dot.polygon = _build_circle(radius * 0.035, 10)
	danger_badge_dot.position = Vector2(0, radius * 0.09)
	danger_badge.add_child(danger_badge_dot)


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

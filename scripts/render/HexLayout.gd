class_name HexLayout
extends RefCounted

const HexCoordRef = preload("res://scripts/core/HexCoord.gd")

var hex_size: float
var origin: Vector2


func _init(size: float = 36.0, center: Vector2 = Vector2.ZERO) -> void:
	hex_size = size
	origin = center


func cube_to_pixel(coord: HexCoordRef) -> Vector2:
	var pixel_x := hex_size * (1.5 * coord.q)
	var pixel_y := hex_size * ((sqrt(3.0) / 2.0 * coord.q) + (sqrt(3.0) * coord.r))
	return origin + Vector2(pixel_x, pixel_y)


func pixel_to_cube(pixel: Vector2) -> HexCoordRef:
	var local := pixel - origin
	var q_frac := (2.0 / 3.0 * local.x) / hex_size
	var r_frac := ((-1.0 / 3.0 * local.x) + (sqrt(3.0) / 3.0 * local.y)) / hex_size
	var s_frac := -q_frac - r_frac
	return cube_round(q_frac, r_frac, s_frac)


static func cube_round(q_frac: float, r_frac: float, s_frac: float) -> HexCoordRef:
	var rq: int = int(round(q_frac))
	var rr: int = int(round(r_frac))
	var rs: int = int(round(s_frac))

	var dq: float = absf(rq - q_frac)
	var dr: float = absf(rr - r_frac)
	var ds: float = absf(rs - s_frac)

	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	else:
		rs = -rq - rr

	return HexCoordRef.new(rq, rr)

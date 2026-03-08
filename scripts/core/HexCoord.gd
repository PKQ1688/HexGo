class_name HexCoord
extends RefCounted

var q: int
var r: int
var s: int:
	get:
		return -q - r


func _init(q_value: int = 0, r_value: int = 0) -> void:
	q = q_value
	r = r_value


static func directions() -> Array:
	return [
		new(1, 0),
		new(1, -1),
		new(0, -1),
		new(-1, 0),
		new(-1, 1),
		new(0, 1),
	]


static func from_key(key: String):
	var parts := key.split(",")
	if parts.size() != 2:
		return new()
	return new(parts[0].to_int(), parts[1].to_int())


func add(other):
	return new(q + other.q, r + other.r)


func equals(other) -> bool:
	return other != null and q == other.q and r == other.r


func neighbors() -> Array:
	var result: Array = []
	for direction in directions():
		result.append(add(direction))
	return result


func distance(other) -> int:
	return int((abs(q - other.q) + abs(r - other.r) + abs(s - other.s)) / 2)


func duplicated():
	return new(q, r)


func to_key() -> String:
	return "%d,%d" % [q, r]


func _to_string() -> String:
	return to_key()

extends SceneTree

const CaptureResolver = preload("res://scripts/core/CaptureResolver.gd")
const HexBoard = preload("res://scripts/core/HexBoard.gd")
const HexCoord = preload("res://scripts/core/HexCoord.gd")
const HexLayout = preload("res://scripts/render/HexLayout.gd")
const ScoreCalculator = preload("res://scripts/core/ScoreCalculator.gd")
const TerritoryResolver = preload("res://scripts/core/TerritoryResolver.gd")


func _init() -> void:
	_run_tests()
	quit()


func _run_tests() -> void:
	_test_round_trip()
	_test_board_size()
	_test_capture()
	_test_territory()
	_test_boundary_not_territory()
	_test_score()
	print("All core tests passed.")


func _test_round_trip() -> void:
	var layout := HexLayout.new(40.0, Vector2.ZERO)
	var coord := HexCoord.new(2, -1)
	var pixel := layout.cube_to_pixel(coord)
	var back := layout.pixel_to_cube(pixel)
	_assert(back.equals(coord), "Cube/pixel round trip failed.")


func _test_board_size() -> void:
	var board := HexBoard.new()
	board.initialize(3)
	_assert(board.all_coords.size() == 37, "Board size formula failed for radius 3.")


func _test_capture() -> void:
	var board := HexBoard.new()
	board.initialize(2)
	board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.WHITE)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
		HexCoord.new(0, 1),
	]:
		board.set_cell(coord, HexBoard.CellState.BLACK)
	var captured := CaptureResolver.resolve(board, HexBoard.CellState.BLACK)
	_assert(captured.size() == 1 and captured[0].equals(HexCoord.new(0, 0)), "Single stone capture failed.")


func _test_territory() -> void:
	var board := HexBoard.new()
	board.initialize(3)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
		HexCoord.new(0, 1),
	]:
		board.set_cell(coord, HexBoard.CellState.BLACK)
	var region := TerritoryResolver.resolve(board, HexBoard.CellState.BLACK)
	_assert(region.size() == 1 and region[0].equals(HexCoord.new(0, 0)), "Closed territory detection failed.")


func _test_boundary_not_territory() -> void:
	var board := HexBoard.new()
	board.initialize(2)
	board.set_cell(HexCoord.new(0, -1), HexBoard.CellState.BLACK)
	board.set_cell(HexCoord.new(1, -1), HexBoard.CellState.BLACK)
	board.set_cell(HexCoord.new(1, 0), HexBoard.CellState.BLACK)
	var region := TerritoryResolver.resolve(board, HexBoard.CellState.BLACK)
	_assert(region.is_empty(), "Boundary-connected empty region should not become territory.")


func _test_score() -> void:
	var board := HexBoard.new()
	board.initialize(3)
	for coord in [
		HexCoord.new(1, 0),
		HexCoord.new(1, -1),
		HexCoord.new(0, -1),
		HexCoord.new(-1, 0),
		HexCoord.new(-1, 1),
		HexCoord.new(0, 1),
	]:
		board.set_cell(coord, HexBoard.CellState.BLACK)
	board.set_cell(HexCoord.new(2, -2), HexBoard.CellState.WHITE)
	var scores := ScoreCalculator.calculate(board)
	_assert(scores[0] == 7 and scores[1] == 1, "Chinese-style score calculation failed.")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)

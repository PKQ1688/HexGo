# HexGo UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the in-match information hierarchy so HexGo highlights dangerous groups first, reveals tactical detail on hover, and cleanly separates scoring mode from normal play.

**Architecture:** Keep the existing logic/render split. Add one pure core analyzer that reports per-stone liberties and string-based threat levels, then let `GameState` filter that metadata for renderers. Shrink `InfluenceRenderer` from ambient heatmap to hover-only preview, and make HUD/territory visibility phase-aware so scoring mode becomes a distinct state instead of another overlay on top of live play.

**Tech Stack:** Godot 4.3+, GDScript 2.0, existing headless SceneTree test scripts in `tests/`

---

## Scope Check

This spec is still one implementation unit. The work spans core metadata, render state, HUD behavior, and short motion polish, but all of it serves a single user-facing outcome: cleaner in-match readability and stronger product feel without changing rules.

## File Map

### Create

- `scripts/core/ThreatAnalyzer.gd`
- `docs/superpowers/plans/2026-03-29-hexgo-ux-polish.md`

### Modify

- `scripts/core/GameState.gd`
- `scripts/render/PieceRenderer.gd`
- `scripts/render/PieceView.gd`
- `scripts/render/InfluenceRenderer.gd`
- `scripts/render/TerritoryRenderer.gd`
- `scripts/Board.gd`
- `scripts/Main.gd`
- `scripts/ui/HUDController.gd`
- `tests/test_core.gd`
- `tests/test_game_flow.gd`
- `tests/test_smoke.gd`

### Responsibilities

- `scripts/core/ThreatAnalyzer.gd`: pure logic for per-group liberties and threat levels.
- `scripts/core/GameState.gd`: expose current visual metadata in a phase-aware way.
- `scripts/render/PieceRenderer.gd`: synchronize danger markers onto visible stones.
- `scripts/render/PieceView.gd`: draw and animate the corner danger badges.
- `scripts/render/InfluenceRenderer.gd`: remove ambient heatmap and emit hover-only preview summaries.
- `scripts/render/TerritoryRenderer.gd`: show territory only during scoring/game-over states.
- `scripts/Board.gd`: coordinate hover clearing, preview sync, and phase-based renderer toggles.
- `scripts/Main.gd`: wire phase changes, hover summaries, and HUD updates together.
- `scripts/ui/HUDController.gd`: replace long explanatory copy with short, priority-based status text.
- `tests/test_core.gd`: cover threat analysis as pure logic.
- `tests/test_game_flow.gd`: cover phase gating and exposed visual metadata.
- `tests/test_smoke.gd`: keep the main scene booting after the HUD/render changes.

## Repo Rule Note

The repository instructions say not to commit unless the user explicitly asks. This plan therefore ends tasks with verification, not commit checkpoints.

## Test Commands

- Core: ``"/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_core.gd``
- Game flow: ``"/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_game_flow.gd``
- Smoke: ``"/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_smoke.gd``

## Task 1: Add Pure Threat Analysis

**Files:**

- Create: `scripts/core/ThreatAnalyzer.gd`
- Modify: `tests/test_core.gd`
- Test: `tests/test_core.gd`

- [ ] **Step 1: Write the failing core test for threat levels**

  Add a new preload and test in `tests/test_core.gd`:

  ```gdscript
  const ThreatAnalyzer = preload("res://scripts/core/ThreatAnalyzer.gd")


  func _run_tests() -> void:
  	_test_round_trip()
  	_test_board_size()
  	_test_capture()
  	_test_territory()
  	_test_boundary_not_territory()
  	_test_score()
  	_test_threat_levels()
  	print("All core tests passed.")


  func _test_threat_levels() -> void:
  	var board := HexBoard.new()
  	board.initialize(3)
  	board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.BLACK)
  	board.set_cell(HexCoord.new(1, 0), HexBoard.CellState.WHITE)
  	board.set_cell(HexCoord.new(1, -1), HexBoard.CellState.WHITE)
  	board.set_cell(HexCoord.new(0, -1), HexBoard.CellState.WHITE)
  	board.set_cell(HexCoord.new(-1, 0), HexBoard.CellState.WHITE)

  	var threats := ThreatAnalyzer.analyze(board)
  	var center := threats.get("0,0", {})
  	_assert(center.get(ThreatAnalyzer.THREAT_LIBERTIES_KEY, -1) == 2, "Threat analyzer should count liberties per group.")
  	_assert(center.get(ThreatAnalyzer.THREAT_LEVEL_KEY, "") == ThreatAnalyzer.THREAT_LEVEL_WARNING, "Two-liberty group should be warning level.")
  ```

- [ ] **Step 2: Run the core test and confirm it fails**

  Run:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_core.gd
  ```

  Expected: failure mentioning `ThreatAnalyzer` missing or `analyze` not found.

- [ ] **Step 3: Implement the minimal pure analyzer**

  Create `scripts/core/ThreatAnalyzer.gd` as a pure helper around `CaptureResolver`:

  ```gdscript
  class_name ThreatAnalyzer
  extends RefCounted

  const CaptureResolverRef = preload("res://scripts/core/CaptureResolver.gd")
  const HexBoardRef = preload("res://scripts/core/HexBoard.gd")

  const THREAT_LIBERTIES_KEY := "liberties"
  const THREAT_LEVEL_KEY := "threat_level"
  const THREAT_LEVEL_SAFE := "SAFE"
  const THREAT_LEVEL_WARNING := "WARNING"
  const THREAT_LEVEL_DANGER := "DANGER"


  static func analyze(board: HexBoardRef) -> Dictionary:
  	var result: Dictionary = {}
  	var visited: Dictionary = {}

  	for coord in board.all_coords:
  		var state := board.get_cell(coord)
  		if state != HexBoardRef.CellState.BLACK and state != HexBoardRef.CellState.WHITE:
  			continue
  		if visited.has(coord.to_key()):
  			continue

  		var group := CaptureResolverRef.find_group(board, coord, state)
  		var liberties := CaptureResolverRef.get_liberties(board, group)
  		var level := _level_for_liberties(liberties)
  		for item in group:
  			var key := item.to_key()
  			visited[key] = true
  			result[key] = {
  				THREAT_LIBERTIES_KEY: liberties,
  				THREAT_LEVEL_KEY: level,
  			}

  	return result


  static func _level_for_liberties(liberties: int) -> String:
  	if liberties <= 1:
  		return THREAT_LEVEL_DANGER
  	if liberties == 2:
  		return THREAT_LEVEL_WARNING
  	return THREAT_LEVEL_SAFE
  ```

- [ ] **Step 4: Re-run the core test and confirm it passes**

  Run:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_core.gd
  ```

  Expected: `All core tests passed.`

## Task 2: Expose Phase-Aware Threat Metadata Through GameState

**Files:**

- Modify: `scripts/core/GameState.gd`
- Modify: `tests/test_game_flow.gd`
- Test: `tests/test_game_flow.gd`

- [ ] **Step 1: Write the failing game-flow test for visible threat metadata**

  Extend `tests/test_game_flow.gd` with a focused test:

  ```gdscript
  func _run_tests() -> void:
  	_test_basic_turn_and_occupied_rejection()
  	_test_suicide_move_rejected()
  	_test_capture_flow()
  	_test_territory_flow()
  	_test_scoring_phase_and_resume()
  	_test_confirm_score_game_over()
  	_test_visible_threats_hidden_in_scoring()
  	print("All game flow tests passed.")


  func _test_visible_threats_hidden_in_scoring() -> void:
  	_reset_events()
  	var state := _new_state(2)
  	state.board.set_cell(HexCoord.new(0, 0), HexBoard.CellState.BLACK)
  	state.board.set_cell(HexCoord.new(1, 0), HexBoard.CellState.WHITE)
  	state.board.set_cell(HexCoord.new(1, -1), HexBoard.CellState.WHITE)
  	state.board.set_cell(HexCoord.new(0, -1), HexBoard.CellState.WHITE)
  	state.board.set_cell(HexCoord.new(-1, 0), HexBoard.CellState.WHITE)
  	state._update_scores()

  	var waiting_threats := state.get_visible_threats()
  	_assert(waiting_threats.has("0,0"), "Waiting phase should expose danger metadata.")

  	state.phase = GameState.Phase.SCORING
  	var scoring_threats := state.get_visible_threats()
  	_assert(scoring_threats.is_empty(), "Scoring phase should hide danger metadata.")
  	state.free()
  ```

- [ ] **Step 2: Run the game-flow test and confirm it fails**

  Run:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_game_flow.gd
  ```

  Expected: failure mentioning `get_visible_threats` missing.

- [ ] **Step 3: Add the GameState API for renderers**

  Update `scripts/core/GameState.gd`:

  ```gdscript
  const ThreatAnalyzerRef = preload("res://scripts/core/ThreatAnalyzer.gd")


  func get_visible_threats() -> Dictionary:
  	if phase == Phase.SCORING or phase == Phase.GAME_OVER:
  		return {}

  	var raw_threats := ThreatAnalyzerRef.analyze(board)
  	var visible: Dictionary = {}
  	for key in raw_threats.keys():
  		var data: Dictionary = raw_threats[key]
  		if String(data.get(ThreatAnalyzerRef.THREAT_LEVEL_KEY, "")) == ThreatAnalyzerRef.THREAT_LEVEL_SAFE:
  			continue
  		visible[key] = data.duplicate(true)
  	return visible
  ```

  Keep this API read-only and phase-aware so renderers do not need to know scoring rules.

- [ ] **Step 4: Re-run the game-flow test and confirm it passes**

  Run:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_game_flow.gd
  ```

  Expected: `All game flow tests passed.`

## Task 3: Render Danger Badges On Stones

**Files:**

- Modify: `scripts/render/PieceView.gd`
- Modify: `scripts/render/PieceRenderer.gd`
- Modify: `scripts/Board.gd`
- Modify: `scripts/Main.gd`
- Test: `tests/test_smoke.gd`

- [ ] **Step 1: Add the failing smoke assertion for the new marker nodes**

  Strengthen `tests/test_smoke.gd` so it exercises one placed stone:

  ```gdscript
  func _run() -> void:
  	var scene: PackedScene = load("res://scenes/Main.tscn")
  	assert(scene != null, "Failed to load Main.tscn.")
  	var main = scene.instantiate()
  	assert(main != null, "Failed to instantiate Main.tscn.")
  	root.add_child(main)
  	await process_frame

  	main.game_state.setup_game(2)
  	assert(main.game_state.execute_turn(main.game_state.board.all_coords[0]), "Smoke test should place one stone.")
  	var pieces := main.board_view.piece_renderer.pieces_container.get_children()
  	assert(pieces.size() == 1, "Expected one rendered piece after the first move.")
  	assert(pieces[0].get_node_or_null("DangerBadge") != null, "PieceView should build a reusable danger badge node.")
  	print("Smoke scene test passed.")
  	quit()
  ```

- [ ] **Step 2: Run the smoke test and confirm it fails**

  Run:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_smoke.gd
  ```

  Expected: failure mentioning missing `DangerBadge`.

- [ ] **Step 3: Add badge drawing and threat syncing**

  Update `scripts/render/PieceView.gd` with a persistent badge node and setter:

  ```gdscript
  func _ready() -> void:
  	# existing setup...
  	var badge := Polygon2D.new()
  	badge.name = "DangerBadge"
  	badge.polygon = PackedVector2Array([
  		Vector2(0, -4),
  		Vector2(6, 0),
  		Vector2(0, 4),
  		Vector2(-6, 0),
  	])
  	badge.position = Vector2(radius * 0.62, -radius * 0.62)
  	badge.visible = false
  	add_child(badge)


  func set_threat_level(level: String) -> void:
  	var badge: Polygon2D = $DangerBadge
  	match level:
  		"DANGER":
  			badge.color = Color(0.89, 0.34, 0.24, 0.96)
  			badge.scale = Vector2.ONE
  			badge.visible = true
  		"WARNING":
  			badge.color = Color(0.94, 0.60, 0.28, 0.82)
  			badge.scale = Vector2(0.82, 0.82)
  			badge.visible = true
  		_:
  			badge.visible = false
  ```

  Update `scripts/render/PieceRenderer.gd` to remember each stone's current threat level and apply it after sync:

  ```gdscript
  var threat_levels: Dictionary = {}


  func sync_threat_levels(levels: Dictionary) -> void:
  	threat_levels = levels.duplicate(true)
  	for key in piece_nodes.keys():
  		var level := String(threat_levels.get(key, {}).get("threat_level", ""))
  		piece_nodes[key].set_threat_level(level)
  ```

  Wire the new sync call from `scripts/Board.gd` and `scripts/Main.gd` immediately after board state refreshes:

  ```gdscript
  func sync_from_board(board_model, scoring_board = null, marked_dead_keys: Array = [], visible_threats: Dictionary = {}) -> void:
  	update_hover(null, false)
  	piece_renderer.sync_from_board(board_model)
  	piece_renderer.set_dead_stones(marked_dead_keys)
  	piece_renderer.sync_threat_levels(visible_threats)
  	territory_renderer.sync_from_board(scoring_board if scoring_board != null else board_model)
  ```

  ```gdscript
  board_view.sync_from_board(
  	game_state.board,
  	game_state.get_scoring_board(),
  	game_state.get_marked_dead_keys(),
  	game_state.get_visible_threats()
  )
  ```

- [ ] **Step 4: Re-run the smoke test and confirm it passes**

  Run:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_smoke.gd
  ```

  Expected: `Smoke scene test passed.`

## Task 4: Remove Ambient Heatmap And Make Hover Summaries HUD-Driven

**Files:**

- Modify: `scripts/render/InfluenceRenderer.gd`
- Modify: `scripts/ui/HUDController.gd`
- Modify: `scripts/Main.gd`
- Test: `tests/test_smoke.gd`

- [ ] **Step 1: Add a smoke assertion that the scene no longer depends on ambient heatmap nodes**

  Update `tests/test_smoke.gd` to assert the renderer can idle without prebuilt heatmap polygons:

  ```gdscript
  var influence := main.board_view.influence_renderer
  assert(influence.heatmap_container.get_child_count() == 0, "Ambient heatmap should stay empty after boot.")
  ```

- [ ] **Step 2: Run the smoke test and confirm it fails**

  Run:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_smoke.gd
  ```

  Expected: failure because `_rebuild_heatmap()` still populates overlays.

- [ ] **Step 3: Convert InfluenceRenderer to hover-only previews and short summaries**

  Replace ambient heatmap rebuilds with a summary signal:

  ```gdscript
  signal preview_summary_changed(summary)


  func sync_from_board(board_model) -> void:
  	board = board_model
  	clear_preview()
  	preview_summary_changed.emit({})


  func update_focus(coord, is_valid: bool) -> void:
  	clear_preview()
  	if board == null or layout == null or game_state == null or coord == null:
  		preview_summary_changed.emit({})
  		return

  	var cell_state: int = board.get_cell(coord)
  	if cell_state == HexBoardRef.CellState.BLACK or cell_state == HexBoardRef.CellState.WHITE:
  		var summary := _show_group_preview(coord, cell_state)
  		preview_summary_changed.emit(summary)
  		return

  	if cell_state != HexBoardRef.CellState.EMPTY or game_state.is_scoring_phase():
  		preview_summary_changed.emit({})
  		return

  	var summary := _show_move_preview(coord, is_valid)
  	preview_summary_changed.emit(summary)
  ```

  Return compact dictionaries from `_show_group_preview()` and `_show_move_preview()`:

  ```gdscript
  return {
  	"type": "group",
  	"player": piece_state,
  	"liberties": liberty_coords.size(),
  	"group_size": group.size(),
  }
  ```

  ```gdscript
  return {
  	"type": "move",
  	"valid": is_valid,
  	"liberties": liberties.size(),
  	"captured_count": captured.size(),
  }
  ```

  Then add one formatter entry point to `scripts/ui/HUDController.gd`:

  ```gdscript
  var preview_summary: Dictionary = {}


  func set_preview_summary(summary: Dictionary) -> void:
  	preview_summary = summary.duplicate(true)


  func _status_text(current_player: int, phase: int) -> String:
  	if phase == GameStateRef.Phase.SCORING:
  		return "点击整串棋切换死活，再确认结果。"
  	if ai_thinking:
  		return "AI 思考中…"
  	if preview_summary.get("type", "") == "group":
  		return "%s棋一串，剩余 %d 气" % [
  			"黑" if int(preview_summary.get("player", 0)) == 1 else "白",
  			int(preview_summary.get("liberties", 0)),
  		]
  	if preview_summary.get("type", "") == "move":
  		if not bool(preview_summary.get("valid", false)):
  			return "此处不可落子。"
  		return "落子后剩余 %d 气，可提 %d 子" % [
  			int(preview_summary.get("liberties", 0)),
  			int(preview_summary.get("captured_count", 0)),
  		]
  	return "危险角标常驻，细节悬停查看。"
  ```

  Finally, connect `preview_summary_changed` in `scripts/Main.gd` and call `hud.set_preview_summary(summary)` before `_refresh_turn_ui()`.

- [ ] **Step 4: Re-run the smoke test and confirm it passes**

  Run:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_smoke.gd
  ```

  Expected: `Smoke scene test passed.`

## Task 5: Separate Scoring View And Add Short Motion Polish

**Files:**

- Modify: `scripts/render/TerritoryRenderer.gd`
- Modify: `scripts/Board.gd`
- Modify: `scripts/Main.gd`
- Modify: `scripts/render/PieceView.gd`
- Modify: `tests/test_game_flow.gd`
- Test: `tests/test_game_flow.gd`, `tests/test_smoke.gd`

- [ ] **Step 1: Add the failing game-flow test for scoring-only territory visibility**

  Extend `tests/test_game_flow.gd`:

  ```gdscript
  func _test_visible_threats_hidden_in_scoring() -> void:
  	# existing assertions...
  	var territory_play := state.should_show_scoring_overlays()
  	_assert(not territory_play, "Normal play should hide scoring overlays.")

  	state.phase = GameState.Phase.SCORING
  	_assert(state.should_show_scoring_overlays(), "Scoring phase should enable territory overlays.")
  	state.free()
  ```

- [ ] **Step 2: Run the game-flow test and confirm it fails**

  Run:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_game_flow.gd
  ```

  Expected: failure mentioning `should_show_scoring_overlays` missing.

- [ ] **Step 3: Add phase gating for territory and tighten the motion**

  Update `scripts/core/GameState.gd`:

  ```gdscript
  func should_show_scoring_overlays() -> bool:
  	return phase == Phase.SCORING or phase == Phase.GAME_OVER
  ```

  Update `scripts/render/TerritoryRenderer.gd` so it can be toggled without recomputing ownership rules:

  ```gdscript
  func set_overlay_enabled(enabled: bool) -> void:
  	visible = enabled
  ```

  Update `scripts/Board.gd` to receive the phase flag:

  ```gdscript
  func sync_from_board(board_model, scoring_board = null, marked_dead_keys: Array = [], visible_threats: Dictionary = {}, show_scoring_overlays: bool = false) -> void:
  	update_hover(null, false)
  	piece_renderer.sync_from_board(board_model)
  	piece_renderer.set_dead_stones(marked_dead_keys)
  	piece_renderer.sync_threat_levels(visible_threats)
  	territory_renderer.set_overlay_enabled(show_scoring_overlays)
  	if show_scoring_overlays:
  		territory_renderer.sync_from_board(scoring_board if scoring_board != null else board_model)
  ```

  Update `scripts/Main.gd` to pass `game_state.should_show_scoring_overlays()`.

  Tighten `scripts/render/PieceView.gd` motion so it stays short and product-like:

  ```gdscript
  func play_place_animation() -> void:
  	scale = Vector2(0.72, 0.72)
  	modulate.a = 0.0
  	var tween := create_tween()
  	tween.set_parallel(true)
  	tween.tween_property(self, "scale", Vector2.ONE, 0.10)
  	tween.tween_property(self, "modulate:a", 1.0, 0.08)


  func play_capture_animation() -> void:
  	var tween := create_tween()
  	tween.set_parallel(true)
  	tween.tween_property(self, "scale", Vector2(0.58, 0.58), 0.12)
  	tween.tween_property(self, "modulate:a", 0.0, 0.12)
  	tween.chain().tween_callback(queue_free)
  ```

- [ ] **Step 4: Run the focused tests and confirm they pass**

  Run:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_game_flow.gd
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_smoke.gd
  ```

  Expected:

  - `All game flow tests passed.`
  - `Smoke scene test passed.`

## Final Verification

- [ ] Run all three test entries in order:

  ```bash
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_core.gd
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_game_flow.gd
  "/Applications/Godot.app/Contents/MacOS/Godot" --path "/Users/adofe/Desktop/HexGo" --headless -s tests/test_smoke.gd
  ```

- [ ] Do one manual play pass in the editor or desktop build and confirm:

  - normal play only shows 1-liberty and 2-liberty badges
  - hovering stones explains danger
  - hovering empty cells explains move outcomes
  - scoring phase hides danger badges and shows territory/dead-stone state only
  - the board feels calmer than before

## Self-Review

### Spec Coverage

- Constant danger indicators for 1-liberty and 2-liberty groups: Task 1 + Task 2 + Task 3
- Hover-only tactical explanations: Task 4
- Scoring as a separate visual state: Task 5
- Shorter, cleaner presentation feedback: Task 5
- HUD reduction from rule wall to short summaries: Task 4

No spec gaps remain.

### Placeholder Scan

- No `TODO`, `TBD`, or “implement later” placeholders.
- Test commands are explicit.
- File paths are explicit.

### Type Consistency

- Threat metadata uses one dictionary shape from `ThreatAnalyzer` through `GameState` into `PieceRenderer`.
- Phase gating is centralized in `GameState` via `get_visible_threats()` and `should_show_scoring_overlays()`.
- Hover summaries use one `preview_summary` dictionary contract from `InfluenceRenderer` to `HUDController`.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HexGo is a hexagonal grid-based two-player board game (similar to Go) built with **Godot 4.5+** and **GDScript 2.0**. The main entry scene is `res://scenes/Main.tscn`.

## Running & Testing

This is a Godot project — there is no CLI build system.

- **Run the game:** Open in Godot Editor and press Play (F5), or run `godot --path . scenes/Main.tscn`
- **Run tests:** Execute test scenes individually via Godot Editor or:
  ```
  godot --path . --script tests/test_core.gd
  godot --path . --script tests/test_smoke.gd
  godot --path . --script tests/test_game_flow.gd
  godot --path . --script tests/test_ai.gd
  ```
  Test scripts extend `SceneTree` (not Node) so they run headlessly.

## Architecture

The codebase enforces strict layer separation:

### Layer 1: Core Logic (`scripts/core/`)
Pure GDScript with **no Godot node/scene dependencies**. All state lives here.

| File | Role |
|------|------|
| `HexCoord.gd` | Cube coordinates (q,r,s where s=-q-r); pixel↔cube conversion |
| `HexBoard.gd` | Board data model; immutable operations return new states |
| `GameState.gd` | State machine (WAITING → PLACING → RESOLVING_CAPTURE → RESOLVING_TERRITORY → SCORING → GAME_OVER) |
| `CaptureResolver.gd` | BFS flood-fill to find groups with 0 liberties → remove |
| `TerritoryResolver.gd` | BFS flood-fill on empty regions; assigns ownership if surrounded by one color and not touching boundary |
| `ScoreCalculator.gd` | Points = live pieces + controlled territories |
| `TurnSimulator.gd` | Simulates moves for legality checks and AI evaluation |

### Layer 2: Rendering (`scripts/render/`)
Godot nodes that listen to signals from the core layer. Never mutate game state directly.

Key classes: `BoardRenderer`, `PieceRenderer`, `TerritoryRenderer`, `HexLayout` (coordinate converter for rendering).

### Layer 3: Input (`scripts/input/`)
`InputHandler.gd` converts mouse/touch events to `HexCoord` and emits `cell_clicked(coord)`.

### Layer 4: UI (`scripts/ui/`)
`HUDController`, `PassButtonController`, `EndGameController`, `MatchSetupDialog` — all communicate via signals.

### Layer 5: AI (`scripts/ai/`)
- `AIController.gd` — manages timing and strategy dispatch
- Three strategies: `EasyAIStrategy` (random), `MediumAIStrategy` (greedy heuristics), `HardAIStrategy` (minimax)
- `AIHeuristics.gd` — move scoring functions shared across strategies
- `TurnSimulator` is reused by AI for move evaluation

## Core Game Loop

1. `InputHandler` emits `cell_clicked(coord)`
2. `GameState.execute_turn(coord)` validates via `TurnSimulator`, places piece, runs `CaptureResolver`, then `TerritoryResolver`
3. `GameState` emits signals: `piece_placed`, `pieces_captured`, `territory_formed`, `turn_completed`
4. Renderers and UI update in response to signals

## Key Design Rules

- **Signals only** between layers — no direct cross-layer method calls
- **Core layer is pure** — never import Godot scene/node classes in `scripts/core/`
- **Single source of truth** — `GameState` owns all board state; renderers are views only
- **Immutable board ops** — `HexBoard` operations return new board instances

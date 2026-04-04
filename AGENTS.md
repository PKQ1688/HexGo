# Repository Guidelines

## Project Structure & Module Organization
- `scenes/` contains playable scenes; `scenes/UI/` holds HUD and dialog scenes.
- `scripts/core/` contains pure game rules and state management; keep it free of scene/node dependencies.
- `scripts/render/`, `scripts/input/`, `scripts/ui/`, and `scripts/ai/` handle presentation, input, interface flow, and computer opponents.
- `assets/` stores art, `resources/` stores themes and shaders, `tests/` stores headless test scripts, and `docs/superpowers/` stores design and planning notes.
- Treat `.godot/` as generated editor cache. Do not edit it or rely on it for source changes.

## Build, Test, and Development Commands
- `godot --path .` launches the project with `scenes/Main.tscn`.
- `godot --path . --headless -s tests/test_core.gd` runs core rules tests.
- Run `tests/test_smoke.gd`, `tests/test_game_flow.gd`, and `tests/test_ai.gd` the same way for smoke, gameplay flow, and AI coverage.
- There is no separate build system; validate changes with the smallest relevant test script first, then do a quick in-editor playthrough for UI work.

## Coding Style & Naming Conventions
- Target **Godot 4.5+** and **GDScript 2.0**.
- Match the existing style: tabs for indentation, concise functions, and small focused scripts.
- Use PascalCase for scene/script filenames and `class_name`s (`GameState.gd`, `AIController.gd`); use `snake_case` for methods, variables, and signals (`record_pass`, `turn_completed`).
- Preserve the project architecture: core logic stays in `scripts/core/`, while render/UI/input layers react through signals instead of mutating shared state directly.
- No formatter or linter config is checked in, so keep `res://` paths, `.uid` files, and preload aliases consistent with nearby code.

## Testing Guidelines
- Add or update a `tests/test_*.gd` case for every gameplay, scoring, capture, or AI behavior change.
- Prefer extending the closest existing test file before creating a new one.
- Keep tests headless and deterministic, and print a clear success message when the script finishes.

## Commit & Pull Request Guidelines
- Recent commits use short, imperative summaries in English or Chinese, such as `Add HexGo gameplay, AI, and test scaffolding` and `修复 Pass 按钮无响应问题`.
- Keep each commit focused on one concern; avoid mixing gameplay logic, UI polish, and tooling changes.
- Pull requests should include a brief summary, linked issue if any, test commands run, and screenshots or GIFs for visual changes.
- Call out scene or script renames explicitly so reviewers can verify updated `res://` references.

# OpenFootball — Agent Guide

## Dev commands
- **Validate (headless):** `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "<project>" --headless --quit`
- **Run editor:** same exe without flags

## Architecture
- **Autoload:** `FootballConstants` (see `project.godot` [autoload])
- **Entry point:** `main_menu.tscn` → `_on_start` loads `match.tscn` (NOT `match.tscn` directly)
- **All match logic** lives in `match_manager.gd` (controls input, AI, dribbling, goals, camera)
- **Player scripts** live on the CharacterBody3D nodes: `simple_ai.gd` (opponent), `teammate_ai.gd` (our team AI)
- **Player visuals** are a separate presentation layer: each field player gets a `scenes/player_visual.tscn` (`PlayerVisual`) child holding a rigged Mixamo model + AnimationTree. Gameplay (physics/AI) and presentation (model/anim) are kept decoupled.
- **Ball physics** in `ball_controller.gd` (`_integrate_forces` — velocity-matching dribbling, no spring)

## Key quirks
- **InputMap** is set up **programmatically** in `match_manager.gd:_setup_inputs()` — `project.godot` input bindings are unused/overridden. Always edit there, not in `project.godot`.
- **Player movement** uses **direct position manipulation** (`move_toward`), not `velocity`/`move_and_slide()`
- **Dribbling** = velocity matching in `_integrate_forces` (ball matches player velocity + position correction `*30`, clamped to 12)
- **Camera:** sideline broadcast style — `camera_pivot` at X=-40, Y=20, follows ball Z, `look_at(Vector3(0,0,ballZ), UP)`
- **WASD** is camera-relative (uses `camera_pivot.global_transform.basis`)
- **Controlled player** switch: **Q** key (manual), auto-switch to whoever on our team has the ball
- **player_home** gets AI script (`teammate_ai.gd`) in `_ready()` — when not human-controlled, it's AI

## Colors
- Home & teammate: **blue** (`Color(0.1, 0.1, 0.9)`)
- Opponent: **red** (`Color(0.9, 0.1, 0.1)`)
- Applied as a whole-body albedo tint via `PlayerVisual.apply_appearance({"kit_color": ...})` (pilot-grade; not a real kit yet)
- Controlled player indicator: **cyan cone** (CylinderMesh, top_radius=0, unshaded) at Y+2.2

## Field conventions
- Field center at `(0,0,0)`. Z = length (105m), X = width (68m), Y = height
- Goals only on Z axis: Home at Z=-52.5, Away at Z=+52.5
- Players attack toward **-Z** (Home → Away)

## Known file layout
```
scenes/match.tscn      — match scene (no direct load, only via main_menu)
scenes/player_visual.tscn       — rigged model + team-tint wrapper (child of each field player)
scripts/match/match_manager.gd  — all game logic
scripts/ai/simple_ai.gd         — opponent AI (red, chases target/ball, shoots)
scripts/ai/teammate_ai.gd       — teammate AI (blue, positions for pass / chases ball)
scripts/player/player_visual.gd — PlayerVisual: idle/run AnimationTree + apply_appearance tint
scripts/ball/ball_controller.gd — ball physics, dribbling, kick
scripts/camera/match_camera.gd  — camera tracking
scripts/data/football_constants.gd — all game constants (autoloaded)
assets/models/footballer.glb    — Mixamo model + idle/run (built by tools/merge_mixamo.py)
tools/merge_mixamo.py           — Blender headless FBX→glb merge
tests/                          — headless CHECK scripts (godot --headless -s res://tests/<x>.gd)
```

## Asset pipeline (players)
- Players are **rigged Mixamo models**, not procedural capsules. Raw FBX in `assets/models/mixamo_src/` are **gitignored** (public repo — ship only the `.glb`).
- Rebuild the model with Blender 5.1 headless: `tools/merge_mixamo.py` merges character + idle + run into `assets/models/footballer.glb`; then run Godot `--headless --import`.
- Provenance/licenses in `ASSET_CREDITS.md`. Full design in `docs/superpowers/specs/2026-07-08-3d-assets-pipeline-design.md`.

## Constraints
- No test framework/CI/lint — only manual headless validation + `tests/` CHECK scripts; rendered visuals need a human running the game
- **Hybrid art:** pitch/markings/goals/ball still procedural; **players are Mixamo models** (CC0/Mixamo-licensed assets only, per public-repo rules)
- Godot 4.7 only; `rendering_method=mobile`, fallback `gl_compatibility`

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

OpenFootball — a football (soccer) simulation game in Godot 4.7 / GDScript. Arcade rules, FIFA-scale pitch. Windows-only for now. Currently a small-scale prototype (human + AI teammate vs. one AI opponent), not yet 11v11.

**Art is now hybrid, no longer "procedural everything."** The pitch, field markings, goals, grass, and ball are still generated in code, but **players are real rigged Mixamo models** (skeletal idle/run animations) wrapped in a `PlayerVisual` node — the old colored capsules are gone. See *Presentation layer & asset pipeline* below. (OPENCODE.md still calls the players procedural capsules — that's stale.)

## Commands

- **Validate (headless, no window):**
  `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
- **Run the game / open editor:** same exe without `--headless --quit`.

There are **no tests, no lint, and no CI** — the only automated check is that the project loads headless without script errors. Verify gameplay changes by actually running the game, since most logic is physics/timing-dependent and won't surface in a headless load.

## Architecture

**Entry flow:** `main_menu.tscn` (main scene) → Start button loads `match.tscn`. Do **not** treat `match.tscn` as a standalone entry point.

**One brain — `scripts/match/match_manager.gd`** (extends Node3D, root of `match.tscn`). This ~820-line file owns nearly everything: input setup, camera tracking, procedural field markings/goals/grass/boundaries, controlled-player switching, kick/pass, and the entire slide-tackle state machine. When in doubt, the logic is here.

**Nodes are wired up in code, not in the scene.** In `_ready()`, `match_manager` procedurally spawns the away player and teammate as bare `CharacterBody3D`s, then `set_script()`s AI onto them. Even `PlayerHome` and the `Ball` get their scripts attached at runtime via `set_script()`/`preload()`. So `.tscn` files are minimal — grep the manager's `_setup_*` / `_give_*` functions to find where a node actually gets its behavior. Each field player (`PlayerAway`, `PlayerTeammate`, `PlayerHome`) also gets a `scenes/player_visual.tscn` instance added as a child for its rigged model + team-color tint (see next section).

**Scripts attached at runtime:**
- `scripts/ai/simple_ai.gd` — opponent (team_2, **red**): chases ball/target, dribbles toward goal, shoots, can request tackles.
- `scripts/ai/teammate_ai.gd` — used for **both** the teammate **and** `PlayerHome` when it's not the human-controlled player (team_1, **blue**). Positions for a pass / chases ball.
- `scripts/ball/ball_controller.gd` — ball physics + dribbling.
- `scripts/camera/match_camera.gd` — camera.
- `scripts/player/player_controller.gd` — exists but note `PlayerHome` is driven by `match_manager` input + `teammate_ai`, so check what's actually attached before assuming this runs.
- `scripts/player/player_visual.gd` (`class_name PlayerVisual`) — the presentation layer attached to `scenes/player_visual.tscn`. Not an AI/gameplay script; see next section.

**Constants:** `scripts/data/football_constants.gd` is autoloaded as `FootballConstants` (global). Central place for field dimensions, ball/player/AI/tackle tuning. **Caveat:** `match_manager.gd` also hardcodes several values inline (player speed `8.0`, kick power `12.0`, pass power `8.0`, kick range `2.0`) that duplicate or diverge from the constants — when tuning, grep both the constant and the literal.

## Presentation layer & asset pipeline

**Gameplay and presentation are separated on purpose.** The `CharacterBody3D` + its AI/input script + `CollisionShape3D` are the *gameplay* (position, physics, tackle, groups) and are untouched by the visual work. The *visual* is a `scenes/player_visual.tscn` instance added as a child. Never bake animation/model logic into the gameplay scripts.

**`PlayerVisual` (`scripts/player/player_visual.gd`)** — the node script on `player_visual.tscn`, which instances `assets/models/footballer.glb` as a child named `Model`.
- Builds an `AnimationTree` **in code** (`AnimationNodeBlendSpace1D`, idle at 0.0 ↔ run at 1.0). No hand-authored tree resource.
- **Drives the blend from speed it MEASURES itself** off the parent's per-frame `global_position` delta — because players move by direct position manipulation, not `velocity` (so there is no velocity to read).
- Public API (the intended gameplay→visual seam): `set_locomotion(velocity: Vector3)` (override the auto-measured speed), `apply_appearance(cfg: Dictionary)` (reads `cfg["kit_color"]` → whole-body albedo tint), plus `trigger(action)` / `set_flag(flag, on)` — **stubs** for the pilot (kick/slide/fall come later; they only `push_warning` today).
- **Fallback:** if the model or its `idle`/`run` animations are missing, it spawns a plain capsule and warns — gameplay keeps working.
- Exports for visual fit: `model_y_offset` (`-0.5`, drop feet to ground since the body sits at `y=0.5`) and `model_yaw_deg` (`180`, Mixamo models face `+Z` but game-forward is `−Z`).
- **glTF gotcha:** imported animations arrive **unlooped** (`loop_mode = NONE`) and freeze after one cycle; `_build_anim_tree` sets `loop_mode = LOOP_LINEAR` on idle/run at runtime.

**Team color** is a whole-body `albedo_color` tint via `apply_appearance` (pilot-grade, not a real kit yet): team_1 = blue `Color(0.1,0.1,0.9)`, team_2 = red `Color(0.9,0.1,0.1)`.

**Asset build pipeline (Mixamo → Godot):**
1. Raw Mixamo FBX live in `assets/models/mixamo_src/` — **gitignored, never committed** (public/open-source; we ship only the built `.glb`). Character = With Skin / T-pose; animations = Without Skin / In Place.
2. `tools/merge_mixamo.py` runs headless in **Blender 5.1** (`C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`), merging `character.fbx` + `idle.fbx` + `run.fbx` into one `assets/models/footballer.glb`, renaming the clips to `idle`/`run` via NLA tracks. Rebuild:
   `& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python tools/merge_mixamo.py -- "<repo>/assets/models/mixamo_src" "<repo>/assets/models/footballer.glb"`
   After rebuilding the `.glb`, run a Godot `--headless --import` pass before referencing it from scripts/scenes.
3. `footballer.glb` + its `.import` are committed; attribution lives in `ASSET_CREDITS.md`.

**Headless check scripts** live in `tests/` (the project otherwise has no test framework). Each extends `SceneTree`, prints `CHECK PASS`/`CHECK FAIL`, and exits 0/1. Run one with:
`& "<godot exe>" --path "<repo>" --headless -s "res://tests/<name>.gd"`. Existing: `check_footballer_glb.gd` (glb has idle/run), `check_player_visual_locomotion.gd` (`speed_to_blend`), `check_player_visual_appearance.gd` (`tint_tree`). Rendered/animation correctness still needs a human running the game — headless can't see it.

## Conventions that will trip you up

- **InputMap is built programmatically** in `match_manager.gd:_setup_inputs()`, which erases and recreates every action on `_ready()`. The bindings in `project.godot` are overridden and effectively dead. **Always edit `_setup_inputs()`, never `project.godot` input.** Controls: WASD/arrows move, Space = kick/tackle, E = pass, Q = swap controlled player, Esc = pause.
- **Player movement is direct position manipulation** (`move_toward` on `global_position.x/z`), *not* `velocity` + `move_and_slide()`. The exception is the slide tackle, which uses `move_and_collide()`.
- **Dribbling is velocity-matching**, not a spring. In `ball_controller.gd:_integrate_forces`, the ball's velocity is set to the dribbler's velocity plus a clamped position correction (`disp * 30`, capped at 12). The `SPRING_*` constants in `football_constants.gd` are **leftover/unused** by the current implementation — ignore them and OPENCODE.md's spring description.
- **Movement is camera-relative** — input is transformed through `camera_pivot.global_transform.basis`, so "forward" means "away from the camera," not world-Z.
- **Controlled player** auto-switches to whichever team_1 player is dribbling; Q switches manually (with a `_manual_swap_cooldown` to stop the auto-switch from immediately reverting it). A cyan cone indicator marks the controlled player.
- **Team membership drives everything** via groups `team_1` (ours) / `team_2` (opponent); tackled players get a temporary `fallen` group. Use `_same_team()` and group checks, not node identity.

## Field coordinate system (FIFA-scale)

- Center at `(0,0,0)`. **Z = length (105m)**, **X = width (68m)**, Y = height. Half-extents: Z ±52.5, X ±34.
- **Goals are only ever on the Z axis** — Home at Z = −52.5, Away at Z = +52.5. Never place goals along X or Y.
- Our team attacks toward **−Z** (Home → Away).
- Camera is a fixed sideline/broadcast view: pivot parked at X = −40, follows the ball's Z, `look_at` the ball's Z on the centerline.

## Reference docs

- `docs/football_reference.md` — full FIFA rules + game-design reference. Read before working on field markings, goals, or rules mechanics.
- `docs/superpowers/specs/2026-07-08-3d-assets-pipeline-design.md` — the design spec behind the player-model work: Mixamo-for-players / CC0-for-props strategy, gameplay/presentation split, team kits, future roster variety (skin/hair/hairstyle), MakeHuman as the long-term parametric base.
- `docs/superpowers/plans/2026-07-08-mixamo-player-pilot.md` — the executed implementation plan for the current player-visual pilot.
- `ASSET_CREDITS.md` — asset provenance/licenses (Mixamo, future CC0).
- `AGENTS.md` — concise agent guide; kept accurate and current.
- `OPENCODE.md` — broader design doc, but **partly stale**: it describes spring-force dribbling, home=red/away=blue, and capsule players — all wrong in the current code (velocity-matching; home/teammate=blue, opponent=red; players are Mixamo models). Trust the source over OPENCODE.md.

## Status notes

- The slide-tackle code in `match_manager.gd` is under active development and littered with `print("[TACKLE_DEBUG] ...")` statements. Foul detection on hitting an opposing player is currently **commented out** ("disabled for testing") in `_on_tackle_body_entered`. Clean up debug prints before considering tackle work done.

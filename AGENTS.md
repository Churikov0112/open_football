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
- **Player locomotion** is a third component: every field player also gets a `PlayerMotor` child (`player_motor.gd`), spawned AFTER `PlayerVisual` (order matters — it finds its sibling visual once in `_ready()`). It owns all movement physics; callers only call `motor.set_move_intent(dir, speed_scale)`, never write `global_position`/`rotation` directly.
- **Ball physics** in `ball_controller.gd` (`_integrate_forces` — velocity-matching dribbling, no spring)

## Key quirks
- **InputMap** is set up **programmatically** in `match_manager.gd:_setup_inputs()` — `project.godot` input bindings are unused/overridden. Always edit there, not in `project.godot`.
- **Player movement** is **velocity + `move_and_slide()`** via `PlayerMotor` (accel/decel, smoothed turn, smoothed lean/banking, sprint) — NOT direct position manipulation anymore. The slide tackle is still the one exception, moving the tackler via manual `move_and_collide()` while that player's motor is control-locked.
- **Sprint:** hold Shift — human only, no stamina, just a higher `speed_scale` into `set_move_intent`.
- **Collision layers are split three ways** — default layer (pitch + ball, for goal/tackle-`Area3D` detection), player layer (`PLAYER_COLLISION_MASK`, bit 2), boundary-wall layer (`BOUNDARY_COLLISION_LAYER`, bit 3). Players mask in player+boundary but NOT the ball's layer — if a player's mask ever includes the ball's layer, `move_and_slide()` physically snags on the ball (juddery dribbling, spawn-point shove).
- **Dribbling** = velocity matching in `_integrate_forces` (ball matches player velocity + position correction `*30`, clamped to 12)
- **Kick/pass** = commit-action deferred impulse system. `_fire_kick()`/`_pass_ball()` set `_action_player`/`_action_power`/`_kick_action_active=true`, trigger animation (currently `pass` clip for both), defer `ball.kick()` to `PlayerVisual.action_contact` signal. No `set_control_locked()` during kick/pass — `_kick_action_active` flag skips the motor-lock early-return in `_handle_player_input`.
- **Kick charge:** hold Space (max 1s), release fires. PowerBar (green→red gradient) visible during charge. Auto-fire at max charge. Power: 12–25 lerp.
- **Animation timing:** `PlayerVisual.ACTION_TIMING` dict — `kick`: `{contact: 0.35, lock: 0.5, speed: 1.0}`, `pass`: `{contact: 0.2, lock: 0.4, speed: 1.0}`. `action_contact` emitted at contact time, `action_finished` at lock time.
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
scripts/player/player_visual.gd — PlayerVisual: idle/run/sprint AnimationTree + apply_appearance tint + set_lean
scripts/player/player_motor.gd  — PlayerMotor: velocity+inertia locomotion (accel/decel/turn/lean/sprint)
scripts/ball/ball_controller.gd — ball physics, dribbling, kick
scripts/camera/match_camera.gd  — camera tracking
scripts/data/football_constants.gd — all game constants (autoloaded)
assets/models/footballer.glb    — Mixamo model + idle/run/sprint + action clips (built by tools/merge_mixamo.py)
tools/merge_mixamo.py           — Blender headless FBX→glb merge
tests/                          — headless CHECK scripts (godot --headless -s res://tests/<x>.gd)
```

## Asset pipeline (players)
- Players are **rigged Mixamo models**, not procedural capsules. Raw FBX in `assets/models/mixamo_src/` are **gitignored** (public repo — ship only the `.glb`).
- Rebuild the model with Blender 5.1 headless: `tools/merge_mixamo.py` merges the character + every FBX in `assets/models/mixamo_src/` into `assets/models/footballer.glb`; then run Godot `--headless --import`.
- Provenance/licenses in `ASSET_CREDITS.md`. Full design in `docs/superpowers/specs/2026-07-08-3d-assets-pipeline-design.md`.

## Locomotion
- Full design in `docs/superpowers/specs/2026-07-09-living-locomotion-design.md`; executed plan in `docs/superpowers/plans/2026-07-09-living-locomotion.md`.
- Tuning constants: `FootballConstants.LOCO_*` (top/sprint speed, accel, decel, turn rate, bank angle + smoothing, anti-slide fudge, animation-state speed thresholds).
- Out of scope for now (deliberately): foot IK, ragdoll/physics-blending, motion matching.

## Constraints
- No test framework/CI/lint — only manual headless validation + `tests/` CHECK scripts; rendered visuals need a human running the game
- **Hybrid art:** pitch/markings/goals/ball still procedural; **players are Mixamo models** (CC0/Mixamo-licensed assets only, per public-repo rules)
- Godot 4.7 only; `rendering_method=mobile`, fallback `gl_compatibility`

# OpenFootball — Agent Guide

## Dev commands
- **Validate, menu-load only (headless):** `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "<project>" --headless --quit`
- **Validate match scene (headless):** `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "<project>" --headless --quit-after 2 res://scenes/match.tscn`
  Run **both** — plain `--quit` boots `main_menu.tscn` and never loads `match.tscn`, so it never parses `match_manager.gd`/`teammate_ai.gd`/`simple_ai.gd` at all; the scene command is the one that actually exercises those files. The scene command has a known pre-existing error baseline (33× `!is_inside_tree()`, 6× transition-duplicate, 3× `states.has`, 1× `WorldEnvironment3D` — harmless, see `CLAUDE.md`'s *Commands* section) — diff against that, don't expect zero.
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
- **Slide tackle & fall system** (`match_manager.gd`, `TackleState`/`FallState` enums): `_tackle_state`/`_tackle_player` are single match-wide fields, not per-player — always check `controlled_player == _tackle_player` before treating "a tackle is happening" as "my tackle." Two separate hit radii: wide `TackleArea` (1.5m) only reaches the ball now; a much tighter `SLIDE_TACKLE_HIT_RADIUS` (0.9m, polled in `_tackle_slide()`) is what actually knocks a player down, so falls track real capsule contact instead of triggering from a visible gap. Tackle aim uses simple lead-prediction off the target's velocity (target usually = ball, which velocity-matches its dribbler). Knockdowns are not yet fouls (no free kick). Victim fall is **animation-driven** (`fallen_idle` → roll → `standing_up`), not physics ragdoll — `ragdoll_skeleton.gd` and its tests still exist but are dead code, nothing live calls them. Full writeup in `CLAUDE.md`'s *Slide tackle & fall system* section.
- **Sprint:** hold Shift (or right trigger, analog) — human only, no stamina, just a higher `speed_scale` into `set_move_intent`.
- **Passing** (`match_manager.gd` + `scripts/match/pass_system.gd`, `scripts/match/pass_params.gd`): five pass types share the shot's charge bar via `enum ChargeAction { NONE, SHOT, PASS_SHORT, PASS_THROUGH, PASS_LOB, PASS_WALL, PASS_THROUGH_AIR }`. Controls: `D`/gamepad-X = shot, `X`/`A` = short pass, `W`/`Y` = through ball, `A`/`B` = lob, `Q`/`LB` held with short/through = wall-pass/through-air. `Q`/`LB` alone swaps player, but **only when our team doesn't have the ball** — with the ball it's the pass-combo modifier instead. `PassSystem` (`class_name PassSystem extends Object`) is 8 pure `static` functions (`select_target`, `lead_point`, `launch_ground`, `ground_pass_speed`, `launch_lob`, `interception_time`, `scatter_degrees`, `apply_scatter`) — never reads `FootballConstants`, tested by `tests/check_pass_system_math.gd`. **Ground-pass speed is distance-derived, not fixed:** `ground_pass_speed(distance, charge_ratio, ...)` computes `speed = distance / travel_time` where charge lerps `travel_time` (full charge = short time = fast; empty charge = long time = slow) — a pass always reaches its target regardless of charge, charge only changes how fast it arrives (added after playtest found fixed-power passes too weak over distance). `ball.launch(velocity)` is the impulse path for passes (vs. `ball.kick(dir, power)` for shots); `_action_power < 0.0` is the sentinel distinguishing them in `_on_action_contact`. `ball.peek_dribble_direction()` is a read-only twin of `get_dribble_direction()` — use it for anything called every frame (e.g. the telegraph marker); the mutating original races `_integrate_forces()`'s dribble-velocity tracking if called per-frame instead of once at a discrete moment. Receive-assist **unconditionally** steers a human receiver's stick toward an inbound ball (no "steer away = dummy run" carve-out anymore — that made receivers run the wrong way right after a handoff, since the stick was still aimed for the previous player). Give-and-go (`PASS_WALL`) is the one place AI sprints (`giving_run` group, `teammate_ai.gd`'s `begin_give_and_go`); honest interception (`simple_ai.gd`'s `begin_intercept`) uses real corridor geometry + a reaction delay + a miss chance, not omniscience. `teammate_ai.gd`'s `Role.RECEIVING` is live but currently unreachable (only 2 outfield players on our side; control always hands off to the receiver). Full reference: `CLAUDE.md`'s *Passing* section.
- **Collision layers are split three ways** — default layer (pitch + ball, for goal/tackle-`Area3D` detection), player layer (`PLAYER_COLLISION_MASK`, bit 2), boundary-wall layer (`BOUNDARY_COLLISION_LAYER`, bit 3). Players mask in player+boundary but NOT the ball's layer — if a player's mask ever includes the ball's layer, `move_and_slide()` physically snags on the ball (juddery dribbling, spawn-point shove).
- **Dribbling** = velocity matching in `_integrate_forces` (ball matches player velocity + position correction `*30`, clamped to 12)
- **Kick/pass** = commit-action deferred impulse system. `_fire_charge()` (shot) / `_fire_pass()` (all 5 pass types) set `_action_player`/`_action_power`/`_kick_action_active=true`, trigger animation (currently `pass` clip for both), defer `ball.kick()`/`ball.launch()` to `PlayerVisual.action_contact` signal. No `set_control_locked()` during kick/pass — `_kick_action_active` flag skips the motor-lock early-return in `_handle_player_input`. See *Passing* bullet above for the pass-specific details.
- **Shot charge:** hold `D`/gamepad-X (max 0.5s), release fires. PowerBar (green→red gradient) visible during charge. Auto-fire at max charge. Power: 12–25 lerp. Passes reuse the bar with a shorter 0.6s max.
- **Animation timing:** `PlayerVisual.ACTION_TIMING` dict — `kick`: `{contact: 0.35, lock: 0.5, speed: 1.0}`, `pass`: `{contact: 0.2, lock: 0.4, speed: 1.5}`. `action_contact` emitted at contact time, `action_finished` at lock time.
- **Camera:** sideline broadcast style — `camera_pivot` at X=-40, Y=20, follows ball Z, `look_at(Vector3(0,0,ballZ), UP)`
- **Movement** is arrows/left-stick, camera-relative (uses `camera_pivot.global_transform.basis`) — WASD letters are freed for pass/shot actions, see *Passing* bullet above.
- **Controlled player** switch: **Q**/`LB` (manual, only when our team doesn't have the ball — otherwise it's the pass-combo modifier), auto-switch to whoever on our team has the ball
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
scripts/match/pass_system.gd    — PassSystem: 8 pure static pass-math functions (headless-tested)
scripts/match/pass_params.gd    — PassParams: plain data holder for a pass's power/height/lead
scripts/ai/simple_ai.gd         — opponent AI (red, chases target/ball, shoots, honest interception)
scripts/ai/teammate_ai.gd       — teammate AI (blue, positions for pass / chases ball / receives / give-and-go run)
scripts/player/player_visual.gd — PlayerVisual: idle/run/sprint AnimationTree + action/fall one-shots + apply_appearance tint + set_lean
scripts/player/player_motor.gd  — PlayerMotor: velocity+inertia locomotion (accel/decel/turn/lean/sprint)
scripts/player/ragdoll_skeleton.gd — DEAD CODE (physics ragdoll, replaced by animation-driven fall in match_manager.gd; still has passing tests, nothing live calls it)
scripts/ball/ball_controller.gd — ball physics, dribbling, kick
scripts/camera/match_camera.gd  — camera tracking
scripts/data/football_constants.gd — all game constants (autoloaded)
assets/models/footballer.glb    — Mixamo model + locomotion/action/tackle-fall clips (built by tools/merge_mixamo.py)
tools/merge_mixamo.py           — Blender headless FBX→glb merge; IN_PLACE_CLIPS freezes root motion per-clip
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

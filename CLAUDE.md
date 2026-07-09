# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

OpenFootball — a football (soccer) simulation game in Godot 4.7 / GDScript. Arcade rules, FIFA-scale pitch. Windows-only for now. Currently a small-scale prototype (human + AI teammate vs. one AI opponent), not yet 11v11.

**Art is now hybrid, no longer "procedural everything."** The pitch, field markings, goals, grass, and ball are still generated in code, but **players are real rigged Mixamo models** (skeletal idle/run animations) wrapped in a `PlayerVisual` node — the old colored capsules are gone. See *Presentation layer & asset pipeline* below.

## Commands

- **Validate (headless, no window):**
  `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
- **Run the game / open editor:** same exe without `--headless --quit`.

There are **no tests, no lint, and no CI** — the only automated check is that the project loads headless without script errors. Verify gameplay changes by actually running the game, since most logic is physics/timing-dependent and won't surface in a headless load.

## Architecture

**Entry flow:** `main_menu.tscn` (main scene) → Start button loads `match.tscn`. Do **not** treat `match.tscn` as a standalone entry point.

**One brain — `scripts/match/match_manager.gd`** (extends Node3D, root of `match.tscn`). This ~1000-line file owns nearly everything: input setup, camera tracking, procedural field markings/goals/grass/boundaries, controlled-player switching, kick/pass (with charge + deferred impulse system), and the entire slide-tackle state machine. When in doubt, the logic is here.

**Nodes are wired up in code, not in the scene.** In `_ready()`, `match_manager` procedurally spawns the away player and teammate as bare `CharacterBody3D`s, then `set_script()`s AI onto them. Even `PlayerHome` and the `Ball` get their scripts attached at runtime via `set_script()`/`preload()`. So `.tscn` files are minimal — grep the manager's `_setup_*` / `_give_*` functions to find where a node actually gets its behavior. Each field player (`PlayerAway`, `PlayerTeammate`, `PlayerHome`) also gets a `scenes/player_visual.tscn` instance added as a child for its rigged model + team-color tint (see next section).

**Scripts attached at runtime:**
- `scripts/ai/simple_ai.gd` — opponent (team_2, **red**): chases ball/target, dribbles toward goal, shoots, can request tackles.
- `scripts/ai/teammate_ai.gd` — used for **both** the teammate **and** `PlayerHome` when it's not the human-controlled player (team_1, **blue**). Positions for a pass / chases ball.
- `scripts/ball/ball_controller.gd` — ball physics + dribbling.
- `scripts/camera/match_camera.gd` — camera.
- `scripts/player/player_controller.gd` — exists but note `PlayerHome` is driven by `match_manager` input + `teammate_ai`, so check what's actually attached before assuming this runs.
- `scripts/player/player_visual.gd` (`class_name PlayerVisual`) — the presentation layer attached to `scenes/player_visual.tscn`. Not an AI/gameplay script; see next section.
- `scripts/player/player_motor.gd` (`class_name PlayerMotor`) — the locomotion component. Added as a **third child** of every field player's `CharacterBody3D` (alongside `PlayerVisual` and the collision shape), in that order — `PlayerVisual` must exist first, since `PlayerMotor._ready()` finds it by scanning siblings once. Owns all movement physics; see *Locomotion* below.

**Constants:** `scripts/data/football_constants.gd` is autoloaded as `FootballConstants` (global). Central place for field dimensions, ball/player/AI/tackle/locomotion (`LOCO_*`) tuning. **Caveat:** `match_manager.gd` also hardcodes `KICK_CHARGE_MAX_TIME = 1.0`, `KICK_POWER_MIN = 12.0`, `KICK_POWER_MAX = 25.0` locally and kick range `2.0` inline — when tuning, grep both locations. (Player top speed comes from `FootballConstants.LOCO_TOP_SPEED` via `PlayerMotor`.)

## Locomotion (`PlayerMotor`)

**Player movement is velocity + inertia via `move_and_slide()`, not direct position manipulation.** `scripts/player/player_motor.gd` (`class_name PlayerMotor`) is a component node — every field player's `CharacterBody3D` gets one as a child, and it owns 100% of that body's movement physics. Callers (human input in `match_manager.gd`, both AI scripts) never touch `global_position`/`rotation` for movement anymore — they only call `motor.set_move_intent(dir, speed_scale)` with a desired world-space direction, once per frame. The motor internally: integrates velocity toward the desired speed (`LOCO_ACCEL` accelerating, `LOCO_DECEL` decelerating — asymmetric, so releasing input glides rather than snapping to a stop), smooth-turns the body's yaw toward the velocity direction (`LOCO_TURN_ROT`, gated below `LOCO_TURN_MIN_SPEED` so it doesn't spin on the spot), computes a **smoothed** lean/bank angle from lateral acceleration and feeds it to `PlayerVisual.set_lean()` (smoothed via `PlayerMotor.smooth_scalar()` at `LOCO_BANK_SMOOTH` — the raw per-frame value is jumpy because WASD input direction snaps instantly, not analog), calls `move_and_slide()`, then pins `global_position.y` to the spawn height every frame (the field is flat) **except while `fallen`** (so a slide-tackle knockback's vertical pop isn't instantly flattened).
- `set_control_locked(on)` — used during commit-actions (pass/kick) and the tackler's own slide: when locked (or the body is in group `fallen`), velocity snaps to **zero immediately** (not a gradual decel) so the body doesn't keep drifting on residual velocity while something else (a hand-authored animation lock, or the tackle's own `move_and_collide()`) is supposed to own the motion that frame.
- Sprint (**hold Shift**) is just a higher `speed_scale` passed into `set_move_intent` by the human-input path in `match_manager.gd` — AI does not sprint.
- `PlayerMotor.find_on(node)` (static) is the canonical "find my sibling motor" lookup — used by both AI scripts and `match_manager._player_motor()`; don't re-scan `get_children()` by hand.
- **Collision layers — three deliberately separate groups.** Default layer 1 holds the pitch and the ball (kept there so goal/tackle-`Area3D` detection, which checks `body == ball`, isn't disturbed). Field players are on `FootballConstants.PLAYER_COLLISION_MASK` (bit 2) with a `collision_mask` of `PLAYER_COLLISION_MASK | BOUNDARY_COLLISION_LAYER` — **not** layer 1 — so `move_and_slide()` makes them push off each other and off the boundary walls, but never physically collides a player's capsule with the ball (dribbling is handled entirely by `ball_controller.gd`'s velocity-matching, not physics contact). The boundary walls (`_setup_boundaries()`) are on their own `FootballConstants.BOUNDARY_COLLISION_LAYER` (bit 3) precisely so they're invisible to the ball's *layer* but the ball still masks them in (`ball.collision_mask = 1 | BOUNDARY_COLLISION_LAYER`) to physically bounce off them. If you add a new physics body, decide deliberately which of these three groups it needs to see — this is easy to get backwards (see the `78990c8` hotfix commit for what breaks: dribbling stutters and the match-start spawn point shoves the ball and capsule apart if a player's mask ever includes the ball's layer).

## Presentation layer & asset pipeline

**Gameplay and presentation are separated on purpose.** The `CharacterBody3D` + its AI/input script + `CollisionShape3D` are the *gameplay* (position, physics, tackle, groups) and are untouched by the visual work. The *visual* is a `scenes/player_visual.tscn` instance added as a child. Never bake animation/model logic into the gameplay scripts.

**`PlayerVisual` (`scripts/player/player_visual.gd`)** — the node script on `player_visual.tscn`, which instances `assets/models/footballer.glb` as a child named `Model`.
- Builds an `AnimationTree` **in code**: a state machine with **idle / run / sprint** locomotion states (each run/sprint state is its own `AnimationNodeAnimation` → `AnimationNodeTimeScale` sub-tree, not a shared blend space) plus one-shot action states layered in. No hand-authored tree resource.
- **Locomotion speed is fed in by `PlayerMotor`** via `set_locomotion(velocity: Vector3)` every physics frame — `PlayerVisual` no longer measures its own speed off `global_position` delta (that was the old direct-position-movement era). State selection is by speed thresholds (`LOCO_RUN_ANIM_SPEED`, `LOCO_SPRINT_ANIM_SPEED`); within run/sprint, the clip's `TimeScale` is driven by `run_timescale(speed, top_speed, fudge) = (speed/top_speed)*fudge` (`LOCO_RUN_SCALE_FUDGE`) so the animation's stride matches actual movement speed — the anti-foot-slide fix. If `footballer.glb` has no `sprint` clip, the sprint state silently falls back to playing the `run` clip at a higher `TimeScale`.
- Public API (the intended gameplay→visual seam): `set_locomotion(velocity: Vector3)`, `set_lean(deg: float)` (rolls the `Model` node for body-banking — expects an already-smoothed value; `PlayerVisual` itself does not smooth), `apply_appearance(cfg: Dictionary)` (reads `cfg["kit_color"]` → whole-body albedo tint), `trigger(action)` (plays one-shot `pass` clip for both kick and pass — kick's own animation clip is planned), `set_flag(flag, on)`. Timing: `ACTION_TIMING` dict per action (`contact` = when `action_contact` fires, `lock` = when `action_finished` fires). `trigger()` no longer a stub.
- **Fallback:** if the model or its `idle`/`run` animations are missing, it spawns a plain capsule and warns — gameplay keeps working.
- Exports for visual fit: `model_y_offset` (`-0.5`, drop feet to ground since the body sits at `y=0.5`) and `model_yaw_deg` (`180`, Mixamo models face `+Z` but game-forward is `−Z`).
- **glTF gotcha:** imported animations arrive **unlooped** (`loop_mode = NONE`) and freeze after one cycle; `_build_anim_tree` sets `loop_mode = LOOP_LINEAR` on idle/run/sprint at runtime.

**Team color** is a whole-body `albedo_color` tint via `apply_appearance` (pilot-grade, not a real kit yet): team_1 = blue `Color(0.1,0.1,0.9)`, team_2 = red `Color(0.9,0.1,0.1)`.

**Asset build pipeline (Mixamo → Godot):**
1. Raw Mixamo FBX live in `assets/models/mixamo_src/` — **gitignored, never committed** (public/open-source; we ship only the built `.glb`). Character = With Skin / T-pose; animations = Without Skin / In Place.
2. `tools/merge_mixamo.py` runs headless in **Blender 5.1** (`C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`), merging `character.fbx` + all non-character FBX (currently `idle.fbx`, `run.fbx`, `kick.fbx`, `pass.fbx`) into one `assets/models/footballer.glb`, renaming clips to filenames (without `.fbx`) via NLA tracks. The script auto-discovers — just drop a new FBX into `mixamo_src/` and rebuild. Rebuild:
   `& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python tools/merge_mixamo.py -- "<repo>/assets/models/mixamo_src" "<repo>/assets/models/footballer.glb"`
   After rebuilding the `.glb`, run a Godot `--headless --import` pass before referencing it from scripts/scenes.
3. `footballer.glb` + its `.import` are committed; attribution lives in `ASSET_CREDITS.md`.

**Headless check scripts** live in `tests/` (the project otherwise has no test framework). Each extends `SceneTree`, prints `CHECK PASS`/`CHECK FAIL`, and exits 0/1. Run one with:
`& "<godot exe>" --path "<repo>" --headless -s "res://tests/<name>.gd"`. Existing: `check_footballer_glb.gd` (glb has idle/run/sprint clips + any extras like kick, pass), `check_player_visual_locomotion.gd` (`speed_to_blend`, `run_timescale`), `check_player_visual_appearance.gd` (`tint_tree`), `check_player_motor_math.gd` (`PlayerMotor`'s pure static functions: `desired_velocity`, `integrate_velocity`, `smooth_yaw`, `lean_deg`, `smooth_scalar`). Rendered/animation correctness and movement *feel* (accel/turn/banking/sprint) still need a human running the game — headless can only catch logic bugs, not how it looks.

## Conventions that will trip you up

- **InputMap is built programmatically** in `match_manager.gd:_setup_inputs()`, which erases and recreates every action on `_ready()`. The bindings in `project.godot` are overridden and effectively dead. **Always edit `_setup_inputs()`, never `project.godot` input.** Controls: WASD/arrows move, Space = kick (hold to charge 1s, release fires), E = pass, Q = swap controlled player, Shift = hold to sprint (human only, no stamina), Esc = pause.
- **Player movement is `velocity` + `move_and_slide()` via `PlayerMotor`** (see *Locomotion* above) — direct position manipulation is gone for regular locomotion. The slide tackle is the one remaining exception: it still moves the tackler with a manual `move_and_collide()` call in `match_manager.gd`, while the tackler's `PlayerMotor` is control-locked for the duration so the two motion systems don't fight.
- **Dribbling is velocity-matching**, not a spring. In `ball_controller.gd:_integrate_forces`, the ball's velocity is set to the dribbler's velocity plus a clamped position correction (`disp * 30`, capped at 12). The `SPRING_*` constants in `football_constants.gd` are **leftover/unused** by the current implementation — ignore them and OPENCODE.md's spring description.
- **Kick/pass use a deferred-impulse (commit-action) system**, not direct `ball.kick()`. `_fire_kick()`/`_pass_ball()` set `_action_player`/`_action_power`/`_kick_action_active=true`, trigger the animation, and **wait** for `PlayerVisual.action_contact` signal before calling `ball.kick()`. No `set_control_locked()` during kick/pass — the `_kick_action_active` flag skips the motor-lock early-return in `_handle_player_input` instead. When `_kick_action_active` is true, `_handle_player_input` still allows WASD/Shift/Space/E and does NOT early-return for `set_control_locked(true)`.
- **Kick = hold Space** for charge (up to 1s), release fires with power lerped 12–25. PowerBar (green→red gradient) visible during charge. Auto-fires at max charge.
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
- `docs/superpowers/specs/2026-07-09-living-locomotion-design.md` — the design spec behind `PlayerMotor`: why velocity+inertia, the OpenSoccer reference recipe, tuning-constant rationale, and what's deliberately out of scope (foot IK, ragdoll, motion matching — see the "По-взрослому" backlog note in the 3D-assets spec above).
- `docs/superpowers/plans/2026-07-09-living-locomotion.md` — the executed implementation plan for `PlayerMotor`.
- `ASSET_CREDITS.md` — asset provenance/licenses (Mixamo, future CC0).
- `AGENTS.md` — concise agent guide; kept accurate and current.
- `OPENCODE.md` — broader design doc, now updated with kick-charge, deferred-impulse, commit-action system, and fixed capsule/stale references. Still use the source for fine-grained details.

## Status notes

- The slide-tackle code in `match_manager.gd` still has `print("[TACKLE_DEBUG] ...")` statements and foul detection is **commented out** in `_on_tackle_body_entered`. Clean up before considering tackle work done.
- **Kick charge and deferred-impulse pass** implemented. Kick and pass both temporarily use the `pass` animation clip (the dedicated `kick.fbx` is imported but not yet assigned). `PlayerVisual.ACTION_CLIPS["kick"]` is set to `"pass"` — when a proper kick animation is ready, change this to `"kick"` and verify `ACTION_TIMING.kick.contact` matches the clip.

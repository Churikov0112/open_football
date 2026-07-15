# OpenFootball — Agent Guide

## Dev commands
- **Validate, menu-load only (headless):** `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "<project>" --headless --quit`
- **Validate match scene (headless):** `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "<project>" --headless --quit-after 2 res://scenes/match.tscn`
  Run **both** — plain `--quit` boots `main_menu.tscn` and never loads `match.tscn`, so it never parses `match_manager.gd`/`teammate_ai.gd`/`simple_ai.gd`/`keeper_ai.gd` at all; the scene command is the one that actually exercises those files. The scene command has a known pre-existing error baseline (`!is_inside_tree()`, `ACTION_CLIPS` transition-duplicate + `states.has`, `WorldEnvironment3D` — all harmless; counts grew when the keeper added a second `PlayerVisual`, see `CLAUDE.md`'s *Commands* section) — diff by error **category/text**, don't expect zero or exact counts.
- **Run editor:** same exe without flags

## Architecture
- **Autoload:** `FootballConstants` (see `project.godot` [autoload])
- **Entry point:** `main_menu.tscn` → `_on_start` loads `match.tscn` (NOT `match.tscn` directly)
- **All match logic** lives in `match_manager.gd` (controls input, AI, dribbling, goals, camera)
- **Player scripts** live on the CharacterBody3D nodes: `simple_ai.gd` (opponent), `teammate_ai.gd` (our team AI), `keeper_ai.gd` (goalkeeper in the Home goal)
- **Player visuals** are a separate presentation layer: each field player gets a `scenes/player_visual.tscn` (`PlayerVisual`) child holding a rigged Mixamo model + AnimationTree. Gameplay (physics/AI) and presentation (model/anim) are kept decoupled.
- **Player locomotion** is a third component: every field player also gets a `PlayerMotor` child (`player_motor.gd`), spawned AFTER `PlayerVisual` (order matters — it finds its sibling visual once in `_ready()`). It owns all movement physics; callers only call `motor.set_move_intent(dir, speed_scale)`, never write `global_position`/`rotation` directly.
- **Ball physics** in `ball_controller.gd` — `BallState` machine (OPEN/TRAPPED/FLIGHT/CAUGHT), continuous **lead-follow** dribbling (NOT velocity-matching/spring), FLIGHT-gated ball↔player collision. See `CLAUDE.md`'s *Ball model & dribbling* section (source of truth).

## Key quirks
- **InputMap** is set up **programmatically** in `match_manager.gd:_setup_inputs()` — `project.godot` input bindings are unused/overridden. Always edit there, not in `project.godot`.
- **Player movement** is **velocity + `move_and_slide()`** via `PlayerMotor` (accel/decel, smoothed turn, smoothed lean/banking, sprint) — NOT direct position manipulation anymore. The slide tackle is still the one exception, moving the tackler via manual `move_and_collide()` while that player's motor is control-locked.
- **Slide tackle & fall system** (`match_manager.gd`, `TackleState`/`FallState` enums): `_tackle_state`/`_tackle_player` are single match-wide fields, not per-player — always check `controlled_player == _tackle_player` before treating "a tackle is happening" as "my tackle." Two separate hit radii: wide `TackleArea` (1.5m) only reaches the ball now; a much tighter `SLIDE_TACKLE_HIT_RADIUS` (0.9m, polled in `_tackle_slide()`) is what actually knocks a player down, so falls track real capsule contact instead of triggering from a visible gap. Tackle aim uses simple lead-prediction off the target's velocity (target usually = ball, which lead-follows its dribbler). Knockdowns are not yet fouls (no free kick). Victim fall is **animation-driven** (`fallen_idle` → roll → `standing_up`), not physics ragdoll — `ragdoll_skeleton.gd` and its tests still exist but are dead code, nothing live calls them. Full writeup in `CLAUDE.md`'s *Slide tackle & fall system* section.
- **Sprint:** hold Shift (or right trigger, analog) — human only, no stamina, just a higher `speed_scale` into `set_move_intent`.
- **Passing** (`match_manager.gd` + `scripts/match/pass_system.gd`, `scripts/match/pass_params.gd`): five pass types share the shot's charge bar via `enum ChargeAction { NONE, SHOT, PASS_SHORT, PASS_THROUGH, PASS_LOB, PASS_WALL, PASS_THROUGH_AIR }`. Controls: `D`/gamepad-X = shot, `X`/`A` = short pass, `W`/`Y` = through ball, `A`/`B` = lob, `Q`/`LB` held with short/through = wall-pass/through-air. `Q`/`LB` alone swaps player, but **only when our team doesn't have the ball** — with the ball it's the pass-combo modifier instead. `PassSystem` (`class_name PassSystem extends Object`) is 8 pure `static` functions (`select_target`, `lead_point`, `launch_ground`, `ground_pass_speed`, `launch_lob`, `interception_time`, `scatter_degrees`, `apply_scatter`) — never reads `FootballConstants`, tested by `tests/check_pass_system_math.gd`. **Ground-pass speed is distance-derived, not fixed:** `ground_pass_speed(distance, charge_ratio, ...)` computes `speed = distance / travel_time` where charge lerps `travel_time` (full charge = short time = fast; empty charge = long time = slow) — a pass always reaches its target regardless of charge, charge only changes how fast it arrives (added after playtest found fixed-power passes too weak over distance). `ball.launch(velocity)` is the impulse path for passes (vs. `ball.kick(dir, power)` for shots); `_action_power < 0.0` is the sentinel distinguishing them in `_on_action_contact`. `ball.peek_dribble_direction()` is a read-only twin of `get_dribble_direction()` — use it for anything called every frame (e.g. the telegraph marker); the mutating original races `_integrate_forces()`'s dribble-velocity tracking if called per-frame instead of once at a discrete moment. Receive-assist **unconditionally** steers a human receiver's stick toward an inbound ball (no "steer away = dummy run" carve-out anymore — that made receivers run the wrong way right after a handoff, since the stick was still aimed for the previous player). Give-and-go (`PASS_WALL`) is the one place AI sprints (`giving_run` group, `teammate_ai.gd`'s `begin_give_and_go`); honest interception (`simple_ai.gd`'s `begin_intercept`) uses real corridor geometry + a reaction delay + a miss chance, not omniscience. `teammate_ai.gd`'s `Role.RECEIVING` is live but currently unreachable (only 2 outfield players on our side; control always hands off to the receiver). Full reference: `CLAUDE.md`'s *Passing* section.
- **Collision layers are split three ways** — default layer (pitch + ball, for goal/tackle-`Area3D` detection), player layer (`PLAYER_COLLISION_MASK`, bit 2), boundary-wall layer (`BOUNDARY_COLLISION_LAYER`, bit 3). Players mask in player+boundary but NOT the ball's layer. **Ball↔player collision is FLIGHT-gated**: the ball adds the player bit to its mask only while in `FLIGHT` (shot/pass → block/intercept) and drops it on trap/loose (so a dribbled/picked-up ball is transparent to capsules — avoids the juddery-dribbling/spawn-shove bug). `continuous_cd` on the ball.
- **Dribbling** = continuous **lead-follow** in `_integrate_forces` (ball held ahead of the dribbler, distance grows with speed; breaks away past `DRIBBLE_CHASE_DIST` → player auto-chases; stick sets lead direction; sprint adds distance + random imprecision). Full model in `CLAUDE.md`. Old velocity-matching/spring is gone.
- **Ground bounce is MANUAL** in `_integrate_forces` (material `bounce = 0.0`): the solver's restitution vs. the materialless `WorldBoundary` floor was killing the vertical → lobs "landed in a puddle." Now the ball tracks `_prev_vy` and, on ground contact after a descent, reflects vy by `BALL_BOUNCE` (0.6) + bleeds horizontal by `BALL_BOUNCE_FRICTION` (0.9) so it bounces and rolls on with decay; settles below `BALL_BOUNCE_MIN_SPEED`. Skipped for `_flat_flight`. Full model in `CLAUDE.md`.
- **Kick/pass** = commit-action deferred impulse system. `_fire_charge()` (shot) / `_fire_pass()` (all 5 pass types) set `_action_player`/`_action_power`/`_kick_action_active=true`, trigger animation (currently `pass` clip for both), defer `ball.kick()`/`ball.launch()` to `PlayerVisual.action_contact` signal. No `set_control_locked()` during kick/pass — `_kick_action_active` flag skips the motor-lock early-return in `_handle_player_input`. See *Passing* bullet above for the pass-specific details.
- **Shot charge:** hold `D`/gamepad-X (max 0.5s), release fires. PowerBar (green→red gradient) visible during charge. Auto-fire at max charge. The aimed shot is in: `match_manager._fire_shot` + `ShotSystem` do **continuous horizontal aim** (centre when facing straight, near-corner as the stick tilts), a **short-tap ground shot** (`< SHOT_GROUND_CHARGE_MAX` → flat/low, no landing bounce), a **chip** (`SHOT_CHIP`, ballistic lob), and a **curl** (`SHOT_CURL`, Magnus via `ball.launch_curl`). `SHOT_*` constants in `football_constants.gd`. Passes reuse the bar with a shorter 0.6s max.
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
scripts/match/net_sim.gd        — NetSim: pure static goal-net math (box-net builder + Verlet/PBD step, headless-tested)
scripts/match/goal_net.gd       — GoalNet: per-goal net component (procedural mesh, sim, ImmediateMesh line render)
scripts/ai/simple_ai.gd         — opponent AI (red, chases target/ball, shoots, honest interception)
scripts/ai/teammate_ai.gd       — teammate AI (blue, positions for pass / chases ball / receives / give-and-go run)
scripts/ai/keeper_ai.gd         — goalkeeper AI (save loop + ball-in-hands + distribution; math in keeper_logic.gd)
scripts/match/keeper_logic.gd   — KeeperLogic: pure static keeper math (drag-aware intercept, save zones, roll/throw speeds; headless-tested)
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

## Goal net
- Volumetric box goals (front+back frame) with a procedural Verlet cloth net that wobbles on a goal; ball settles in the net, 5s celebration, then reset. Full detail in `CLAUDE.md`'s *Goal net* section; design/plan in `docs/superpowers/{specs/2026-07-12-goal-net-physics-design.md,plans/2026-07-12-goal-net-physics.md}`.
- Math is pure/headless-tested in `net_sim.gd` (`NetSim`, never reads constants); `goal_net.gd` (`GoalNet`) drives+renders it; ball-stop colliders + celebration flow live in `match_manager.gd:_setup_goals()`.
- Tuning: `FootballConstants` `NET_*` section — primary feel dial is `NET_STIFFNESS` (free↔rigid), then `NET_DAMPING`/`NET_SLACK`/`NET_SHAPE_RETURN`/`NET_CONSTRAINT_ITERATIONS`. Test: `tests/check_net_sim.gd`.

## Goalkeeper
- AI keeper in the Home goal (`match_manager._setup_keeper`): line-tracking, shot save (central catch / dive to a corner / tip over the bar), ball-in-hands, distribution. `keeper_ai.gd` drives it; **all geometry/timing math is pure functions in `keeper_logic.gd`** (`class_name KeeperLogic`, never reads `FootballConstants`, headless-tested).
- **Shot prediction is drag-aware** — `KeeperLogic.shot_intercept` integrates the ball's real drag + gravity (a naive `t=dz/vz` line over-estimated height and conceded on-target shots as "over the bar"). Central catches fire a `KEEPER_CATCH_LEAD`/`KEEPER_MISS_LEAD` before arrival (arms up in time) but only stick at the tight `KEEPER_REACH`. High central band (2.0–2.5m) is a per-shot coin-flip (`KEEPER_HIGH_CATCH_CHANCE`) catch-vs-tip.
- Ball in hands = `BallState.CAUGHT`, pinned to the **right-hand bone** (`PlayerVisual.get_hold_attachment`); a caught ball can't score.
- **Distribution: three variants, one wired at a time** (`_hold()`'s exit call selects) — overhand throw (**active**, arced, drag-compensated via `KeeperLogic.drag_horizontal_speed`), placing-ball→field-dribble→field-pass, and low roll / drop-kick. The rest are kept as building blocks for the real game AI.
- Two `ball_controller.gd` fixes it needed: **pending impulse applied at the start of `_integrate_forces`** (so a standstill shot isn't declared flight-ended on frame 1) and a **`KICK_GRACE_MSEC` self-collision exception** (so a point-blank strike isn't blocked by its own striker).
- Constants: `FootballConstants` `KEEPER_*`. Tests: `check_keeper_logic.gd`, `check_keeper_clear.gd`, `check_kick_grace.gd`. Full detail in `CLAUDE.md`'s *Goalkeeper* section. **Currently on debug scaffolding** (`DEBUG_DISABLE_OPPONENT`/`DEBUG_DISABLE_TEAMMATE`, third-person camera, file logging, `[KEEPER]` prints) — strip before merge.

## Penalty (Phase A)
- Press **P** to stage a penalty into the attacked goal. `scripts/match/penalty_controller.gd` (base, one penalty, `SETUP→AIM→STRIKE`, emits `struck`, `release_after_strike`) + pure math in `scripts/match/penalty_logic.gd` (`class_name PenaltyLogic`, never reads `FootballConstants`, headless-tested). Yellow world-space reticle on the goal plane (eases back to center when the stick is released); hold **kick** to charge power (ring = spread grows with power); `combo_modifier`+kick = chip. Direct = `aim + uniform sample in spread disc` (can miss). **Chip: power = landing distance** (short/in/over), horizontal drag-compensated via `KeeperLogic.drag_horizontal_speed`. Direct+chip only.
- Keeper dives **blind** into a random 1-of-5 zone at contact (`keeper_ai.set_penalty_mode`/`begin_penalty_dive`); save = existing geometry (`resolve_save`/`KEEPER_SAVE_ERROR`), so a correct guess never guarantees a save. CENTER stays central and resolves by the existing height reflex.
- After the strike the ball goes **straight back to normal play** (goal→`GoalArea`→`_reset_ball`); no RESOLVE/timeout in the base controller (that's the future shootout layer). `match_manager` gates input/AI/camera via `_penalty_active`.
- **Root-motion run-up (A1):** `penalty_kick_l/_r` kept out of `IN_PLACE_CLIPS`; `PlayerVisual.consume_root_motion()` returns per-frame advance in game meters (raw Hips track × `PEN_ROOT_SCALE`, calibrated by `tools/measure_penalty_runup.gd`); controller pre-places the kicker `PEN_RUNUP_DIST` back and drives the body along `_forward`. Re-run the measure tool if the clips are re-exported. **Gotcha:** `root_motion_track` is set only for the penalty clip inside `trigger()` (global broke `keeper_idle`/dive vertical) and cleared only **after** the return crossfade (`get_fading_from_node()` empty; clearing at `lock` slid the body backward into idle). Kick→idle return is a real crossfade, not `AT_END`.
- Constants: `FootballConstants` `PEN_*`. Tests: `check_penalty_logic.gd`, `check_penalty_flow.gd` (smoke). Phases B (save as keeper) / C (shootout) are spec-only. Interactive feel needs a human run. Full detail in `CLAUDE.md`'s *Penalty* section; spec/plan under `docs/superpowers/`.

## Locomotion
- Full design in `docs/superpowers/specs/2026-07-09-living-locomotion-design.md`; executed plan in `docs/superpowers/plans/2026-07-09-living-locomotion.md`.
- Tuning constants: `FootballConstants.LOCO_*` (top/sprint speed, accel, decel, turn rate, bank angle + smoothing, anti-slide fudge, animation-state speed thresholds).
- Out of scope for now (deliberately): foot IK, ragdoll/physics-blending, motion matching.

## Constraints
- No test framework/CI/lint — only manual headless validation + `tests/` CHECK scripts; rendered visuals need a human running the game
- **Hybrid art:** pitch/markings/goals/ball still procedural; **players are Mixamo models** (CC0/Mixamo-licensed assets only, per public-repo rules)
- Godot 4.7 only; `rendering_method=mobile`, fallback `gl_compatibility`

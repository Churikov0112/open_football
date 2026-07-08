# Physical Tackle — Fall & Ball Pop

## Overview
Enhance the existing slide tackle (spec'd in `2026-07-08-slide-tackle-design.md`) with physical feedback: the tackled player falls over, slides, and the ball pops loose even from glancing/side tackles.

## Changes to Constants (`football_constants.gd`)

| Constant | Old | New | Description |
|---|---|---|---|
| `SLIDE_TACKLE_AREA_RADIUS` | 0.5 | 1.5 | Collision sphere radius — bigger = catches side tackles |
| `SLIDE_TACKLE_BALL_POWER` | 6.0 | 7.0 | Ball launch impulse — harder pop-off feel |
| `SLIDE_TACKLE_FALL_DISTANCE` | — | 2.0 | How far the tackled player is pushed back |
| `SLIDE_TACKLE_FALL_TIME` | — | 1.0 | Seconds the tackled player stays on the ground |

## Collision Detection — Hybrid

Two independent detection paths, both checked in `_tackle_slide()`:

| Target | Mechanism | Notes |
|--------|-----------|-------|
| **Ball** | Area3D (sphere, radius=1.5) | Existing approach, larger radius |
| **Player (opponent)** | `move_and_collide(motion)` | Returns `KinematicCollision3D` with normal & point |

The tackler slides using `move_and_collide(motion)` instead of direct position addition. This applies **only during the slide** — regular player movement (walk/run, AI chase) stays as direct position manipulation (`+= dir * speed * delta`). The Area3D follows the player as before.

If `move_and_collide` hits a wall or boundary, the slide stops (enter recovery immediately).

## Tackle Outcomes

### Clean Tackle (Area3D hits ball, or move_and_collide hits no player)
1. `release_dribble()`
2. Ball kicked in `_tackle_dir` with power 7.0, Y=0.15
3. Tackler enters RECOVERING (1.5s)
4. No player falls — ball-only contact

### Physical Tackle (move_and_collide hits opponent player)
1. Ball pops loose: `release_dribble()`, kicked in `collision_normal` with power 7.0, Y=0.15
2. **Tackled player:**
   - `rotation.x = deg_to_rad(90)` — capsule falls horizontally
   - Pushed back 2m along `collision_normal`
   - Added to group `"fallen"`
   - Stays on ground for `SLIDE_TACKLE_FALL_TIME` (1.0s)
   - After timer: `rotation.x` lerps back to original, removed from `"fallen"`
3. Tackler enters RECOVERING (1.5s)

## State Management

New variables in `match_manager.gd`:
```gdscript
var _tackled_player: CharacterBody3D     # who got tackled
var _tackled_fall_timer: float = 0.0     # countdown
var _tackled_orig_rotation: Vector3       # restore rotation later
```

## Input & AI Lock

Throughout `_tackled_fall_timer > 0`:
- **Human input:** `_handle_player_input()` checks `controlled_player.is_in_group("fallen")` → return
- **AI (`simple_ai.gd`):** `_physics_process()` checks `is_in_group("fallen")` → return early
- **AI (`teammate_ai.gd`):** same check

The `"fallen"` group is temporary — added on tackle, removed when the player gets up.

## Integration Points

All logic lives in `match_manager.gd`:
- `_tackle_slide(delta)` — replace direct position += with `move_and_collide()` + collision handling
- `_physics_process(delta)` — add tackled-player fall timer + rotation lerp
- `_handle_player_input()` — add `"fallen"` guard
- `_poll_ai_tackles()` — unchanged

AI scripts (`simple_ai.gd`, `teammate_ai.gd`) — add `"fallen"` guard at top of `_physics_process`.

## Future (not in scope)

- Models + skeletons + `physical_bones_start_simulation()` for full ragdoll
- Foul detection + referee + cards
- Standing tackle

## ECS-Ready Notes

- Any CharacterBody3D can be tackled — works for any number of players
- Team membership via groups (`"team_1"`, `"team_2"`)
- Fallen state via temporary group (`"fallen"`)

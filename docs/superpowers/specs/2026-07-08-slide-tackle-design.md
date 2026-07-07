# Slide Tackle System

## Overview
Add slide tackle mechanic for defensive play when opponent has the ball.
Uses Area3D collision detection, direct position movement, and foul/free-kick handling.

## Constants (`football_constants.gd`)

| Constant | Value | Description |
|---|---|---|
| `SLIDE_TACKLE_SPEED` | 18.0 | m/s sliding speed |
| `SLIDE_TACKLE_RANGE` | 4.0 | max slide distance |
| `SLIDE_TACKLE_RECOVERY_TIME` | 1.5 | seconds player is down |
| `SLIDE_TACKLE_AREA_RADIUS` | 0.5 | Area3D collision sphere radius |
| `SLIDE_TACKLE_BALL_DIR_Y` | 0.15 | ball launch Y component |
| `SLIDE_TACKLE_BALL_POWER` | 6.0 | ball launch impulse |
| `AI_TACKLE_RANGE` | 2.5 | AI decides to tackle within this dist |
| `AI_TACKLE_COOLDOWN` | 2.0 | seconds between AI tackles |

## Team Groups
- `team_1` — blue/home (human + teammate)
- `team_2` — red/away (opponents)
- Applied in `_setup_away_player()`, `_setup_teammate()`, `player_home`

## Human Input (`match_manager.gd`)
- **Key:** Space (contextual)
- If `ball.dribbler` belongs to `team_2` → execute tackle
- Otherwise (ball is ours, loose, or AI teammate has it) → existing kick/pass logic

## Tackle Execution (`_start_tackle(player)`)
1. Compute `dir = (ball.global_position - player.global_position).normalized()`, zero Y
2. Set `player.tackle_state = TackleState.SLIDING`
3. Store `dir`, `distance_remaining = SLIDE_TACKLE_RANGE`
4. Reparent Area3D to player, place at player feet (Y=0.3), enable monitoring
5. Tilt player capsule: `rotation.x = deg_to_rad(90)` toward slide direction
6. Each `_physics_process`: move player along `dir` at `SLIDE_TACKLE_SPEED`, decrement distance
7. When `distance_remaining <= 0` → transition to RECOVERING

## Collision Detection (Area3D)
`body_entered` callback, first hit only:

| Body | Action |
|---|---|
| `ball` (RigidBody3D) | Clean tackle. `release_dribble()`, `kick(dir_tackle, SLIDE_TACKLE_BALL_POWER)`, mark processed |
| `team_2` player (CharacterBody3D) | Foul. `_tackle_clean = false`, stop player, mark processed |
| `team_1` player | Ignored |

## Foul Handling
- Set `_tackle_clean = false`, enter RECOVERING
- Ball stays at opponent's position
- After recovery: reset ball to foul location, opponent retains possession via `ball.set_dribbler(opponent)`
- Minimal — no whistle animation

## Recovery
- `state = TackleState.RECOVERING`, timer `SLIDE_TACKLE_RECOVERY_TIME`
- Player cannot move, receives no input
- Capsule tilts (rotation.x = 90°) while sliding, lerps back during recovery
- After timer: `state = TackleState.NORMAL`, restore rotation, re-enable input

## AI Tackles (`simple_ai.gd`)
- Add `wants_to_tackle: bool`, `tackle_cooldown: float`
- Skip if human-controlled (`controlled_player == self`)
- If `ball.dribbler` is `team_1` and distance < `AI_TACKLE_RANGE` and cooldown expired → `wants_to_tackle = true`
- `match_manager` polls all `team_2` players each frame: if `wants_to_tackle` → `_start_tackle(opponent)`

## ECS-Ready Notes
- `_start_tackle(player)` takes any CharacterBody3D — works for any number of players
- Team membership via groups, not hardcoded node references

## Future Considerations (not in scope)
- Yellow/red cards
- Advantage rule
- Directional tackle (hold direction + Space)
- Standing tackle
- Referee / whistle animation

# Player Spawn Factory — Phase 3 Step 3a (ActionExecutor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the shared ball-commit/resolution path (shot + pass compute → animate → apply impulse → handoff) out of `match_manager.gd` into a focused `ActionExecutor` companion node, behavior 1:1, so the path becomes a single reusable seam for the (later) `HumanBrain` in Step 3b.

**Architecture:** `ActionExecutor` is a `Node` under the manager (same pattern as `PenaltyController`/`FreeKickController`), created + `setup(manager, ball)`-ed in `_ready`. It owns the commit state (`_action_*`/`_pending_*`/`_pass_rng`) and the resolution functions (`fire_shot`/`fire_pass` + private helpers + `on_action_contact`/`on_action_finished`/`cancel_action`). It calls back into the manager for shared helpers it does NOT own (`_aim_dir`, `_ai_of`, `_player_visual`, `_player_motor`, `_sync_ai_controllers`, `begin_pass_receive`, `controlled_player`, `_manual_swap_cooldown`, `_attack_dir_z`, `field_length`). The manager keeps thin signal-forwarders (`_on_action_contact`/`_on_action_finished`/`_cancel_ball_action` → executor) so the **factory's signal wiring is untouched**, and two getters (`action_player()`/`is_kick_action_active()`) replace the field reads in the input/dribbling paths. The charge-as-timer + queue system (`_start_charge`/`_fire_charge`/`_try_fire_queue`/`_aim_dir`) **stays in the manager** — it is input-specific and moves to `HumanBrain` in Step 3b.

**Tech Stack:** Godot 4.7 / GDScript. Headless `SceneTree` check scripts. Windows / PowerShell.

## Global Constraints

- **Godot exe (console build):** `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`
- **Repo path:** `C:\Users\User\Desktop\projects\OpenFootball`
- **This is a pure 1:1 refactor** — zero intended behavior change. The regression grid staying green is the primary safety net; a human playtest of shot/pass feel is required after (headless can't verify feel).
- **The commit path is FEEL-CRITICAL** (shot/pass). Every moved line is a relocation, NOT a rewrite: the only edits to moved code are mechanical prefix rewrites (`ball`→`_ball`, shared-helper calls→`_manager.`-prefixed, `ChargeAction.`→`MatchManager.ChargeAction.`). Do not "improve" logic while moving it.
- **`ChargeAction` enum stays in the manager** (`MatchManager.ChargeAction`); the executor references it by the qualified name. The mutual `class_name` reference (executor→`MatchManager.ChargeAction`, manager→`ActionExecutor.new()`) parses cleanly in Godot 4.7 — **verified empirically before this plan** (throwaway `CycleA`/`CycleB` scripts loaded with no cyclic-reference error). Executor `action` params are typed `int` (the enum is int-backed) to avoid any typed-cycle risk.
- **Factory signal wiring is UNTOUCHED.** `PlayerFactory` connects `PlayerVisual.action_contact/action_finished` to `manager._on_action_contact/_on_action_finished`. Those stay as thin manager methods that forward to the executor.

### Regression grid (run after every task)

```powershell
$GODOT = "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe"
$REPO  = "C:\Users\User\Desktop\projects\OpenFootball"
# 1) menu load
& $GODOT --path $REPO --headless --quit
# 2) match scene load (diff error categories vs baseline — see below)
& $GODOT --path $REPO --headless --quit-after 2 res://scenes/match.tscn
# 3) headless checks
foreach ($t in @(
  "check_action_executor","check_ball_state","check_free_kick_flow","check_penalty_flow",
  "check_setpiece_goal_freeze","check_penalty_keeper_line","check_keeper_logic",
  "check_player_brain","check_player_factory","check_team_roster","check_player_config"
)) { & $GODOT --path $REPO --headless -s "res://tests/$t.gd"; Write-Host "exit=$LASTEXITCODE $t" }
# 4) flaky keeper cycle — majority PASS
1..3 | % { & $GODOT --path $REPO --headless -s "res://tests/check_keeper_clear.gd"; Write-Host "exit=$LASTEXITCODE keeper_clear $_" }
```

**Match-scene error baseline (command 2)** — diff by error *category/text*, NOT counts. Known-OK: `ERROR: Condition "!is_inside_tree()" is true.`, the `ACTION_CLIPS` duplicate-registration trio (`states.has(p_name)` + two transition-duplicate errors), `ERROR: Cannot get class 'WorldEnvironment3D'.`. Any NEW category = regression.

**Note on class-cache rebuild:** adding `class_name ActionExecutor` / `class_name MatchManager` requires a one-time editor pass to register them before the headless commands see them. After Task 1's edits run once:
`& $GODOT --path $REPO --headless --editor --quit` (rebuilds `.godot/global_script_class_cache.cfg`), then proceed with the grid.

---

## File Structure

- **Create** `scripts/match/action_executor.gd` — `class_name ActionExecutor extends Node`. Owns the ball-commit state + shot/pass resolution + impulse application. One responsibility: "resolve a requested ball action into a physical impulse."
- **Modify** `scripts/match/match_manager.gd` — add `class_name MatchManager`; create/own `_action_executor`; remove the moved functions/state + dead `_start_ball_action`; keep thin forwarders + getters; swap call-sites.
- **Create** `tests/check_action_executor.gd` — headless: drive `fire_pass` + `on_action_contact` on a real match scene, assert impulse applied.
- **Modify** `CLAUDE.md`, `AGENTS.md` — document `ActionExecutor` + the commit-path seam.

### The extraction map (authoritative — used by Task 2)

**Moves to `ActionExecutor` (verbatim body, mechanical prefix rewrites only):**

| Manager symbol (current) | Becomes in executor | Notes |
|---|---|---|
| state `_action_player`,`_action_dir`,`_action_power`,`_kick_action_active`,`_pending_launch`,`_pending_curl`,`_pending_flat` | same names | commit state |
| state `_pass_rng` (+ `randomize()`) | same name; `randomize()` in `setup()` | only fire-path + `_ready` use it (verified) |
| `_fire_shot(...)` | `fire_shot(action: int, player, charge_ratio, facing_override := Vector3.ZERO)` | public |
| `_fire_pass(...)` | `fire_pass(action: int, player, charge_ratio, facing_override := Vector3.ZERO)` | public |
| `_on_action_contact(a, p)` | `on_action_contact(a: String, p: Node)` | public (manager forwards) |
| `_on_action_finished(a, p)` | `on_action_finished(a: String, p: Node)` | public (manager forwards) |
| `_cancel_ball_action(p)` | `cancel_action(p: Node)` | public (manager forwards) |
| `_pass_params(action)` | `_pass_params(action: int)` | private |
| `_maybe_flag_interceptor(...)` | same | private |
| `_ground_launch(...)` | same | private |
| `_target_goal_center()` | same | private; uses `_manager._attack_dir_z`/`_manager.field_length` |
| `_ball_gravity()` | same | private; uses `_ball` |
| `_team_arrays(group, except)` | same | private; only fire-path uses it (verified) |
| `_clear_wall_pass_cooldown()` | same | private coroutine (`get_tree()` OK — executor is a Node) |

**Removed from manager (dead code):** `_start_ball_action(...)` — zero callers project-wide (verified); it references the moved `_action_*` state so it must go.

**Stays in manager, executor calls back via `_manager.`:** `_aim_dir`, `_ai_of`, `_player_visual`, `_player_motor`, `_sync_ai_controllers`, `begin_pass_receive`, `controlled_player` (get+set), `_manual_swap_cooldown` (set), `_attack_dir_z`, `field_length`.

**Prefix-rewrite rules applied to every moved line (Task 2 Step 3):**
- `ball` (the manager's `@onready var ball`) → `_ball`
- `ChargeAction.` → `MatchManager.ChargeAction.`
- bare calls/reads of `_aim_dir(` `_ai_of(` `_player_visual(` `_player_motor(` `_sync_ai_controllers(` `begin_pass_receive(` `controlled_player` `_manual_swap_cooldown` `_attack_dir_z` `field_length` → prefix `_manager.`
- **NOT** rewritten (owned by the executor, stay bare): `_action_*`, `_pending_*`, `_pass_rng`, `_pass_params(`, `_maybe_flag_interceptor(`, `_ground_launch(`, `_target_goal_center(`, `_ball_gravity(`, `_team_arrays(`, `_clear_wall_pass_cooldown(`, and everything on `_ball`/`PassSystem`/`ShotSystem`/`FootballConstants`/`PassParams`.

---

## Task 1: Scaffold — `class_name MatchManager`, empty `ActionExecutor`, wiring (inert)

Adds the class names + creates the executor node, wired but **not yet used** by any path. Behaviorally inert (the manager still runs its own `_fire_shot`/`_fire_pass`/etc.). Safe checkpoint proving the mutual `class_name` reference + node creation load cleanly.

**Files:**
- Create: `scripts/match/action_executor.gd`
- Modify: `scripts/match/match_manager.gd:1` (class_name), `_ready` (create executor)

**Interfaces:**
- Produces: `class_name ActionExecutor extends Node` with `func setup(manager: Node, ball: RigidBody3D) -> void`, `func action_player() -> CharacterBody3D` (returns `null` for now), `func is_kick_action_active() -> bool` (returns `false` for now).
- Produces: `class_name MatchManager` on the match-scene root; `var _action_executor` on the manager.

- [ ] **Step 1: Create the `ActionExecutor` shell**

Create `scripts/match/action_executor.gd`:

```gdscript
class_name ActionExecutor
extends Node
## Резолюция «действия с мячом» → физический импульс. Общий commit-путь удара/паса, вынесенный
## из match_manager (Фаза 3a). Узел-компаньон менеджера (как PenaltyController/FreeKickController):
## владеет состоянием коммита (_action_*/_pending_*/_pass_rng) и звонит назад в _manager за общими
## хелперами (_aim_dir/_ai_of/_player_visual/... — вход человека и заряд остаются в менеджере до 3b).

var _manager: Node
var _ball: RigidBody3D

func setup(manager: Node, ball: RigidBody3D) -> void:
	_manager = manager
	_ball = ball

## Тело, выполняющее действие (управление заблокировано), либо null. Читает менеджер в
## _handle_player_input/_handle_dribbling — раньше это было поле _action_player.
func action_player() -> CharacterBody3D:
	return null

## Идёт ли клип удара (импульс отложен до action_contact, мотор НЕ залочен). Раньше — поле
## _kick_action_active.
func is_kick_action_active() -> bool:
	return false
```

- [ ] **Step 2: Add `class_name MatchManager` to the manager**

In `scripts/match/match_manager.gd`, line 1:

```gdscript
class_name MatchManager
extends Node3D
```
(prepend the `class_name` line above the existing `extends Node3D`).

- [ ] **Step 3: Create the executor in `_ready`**

In `scripts/match/match_manager.gd`, add the field near `_free_kick` (line 26):

```gdscript
var _free_kick                                 # FreeKickController
var _action_executor                           # ActionExecutor
```

In `_ready`, right after the `_free_kick.setup(...)` call (~line 148), add:

```gdscript
	_action_executor = ActionExecutor.new()
	_action_executor.name = "ActionExecutor"
	add_child(_action_executor)
	_action_executor.setup(self, ball)
```

- [ ] **Step 4: Register the class names + run the regression grid**

```powershell
& $GODOT --path $REPO --headless --editor --quit    # rebuild class cache
```
Then run the full regression grid (Global Constraints). `check_action_executor` does not exist yet — expect its line to error/skip; all OTHERS must be green and the match scene must load with only baseline error categories. Confirm `ActionExecutor` + `MatchManager` appear in `.godot/global_script_class_cache.cfg`.

- [ ] **Step 5: Commit**

```powershell
git add scripts/match/action_executor.gd scripts/match/match_manager.gd
git commit -m @'
refactor(phase3a): scaffold ActionExecutor node + class_name MatchManager (inert)

Creates the ActionExecutor companion node (setup + placeholder getters) and adds
class_name MatchManager, wired in _ready but not yet used by any path. Behaviorally
inert — the manager still runs its own commit path. Proves the mutual class_name
reference and node creation load cleanly before the move.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
'@
```

---

## Task 2: Move the commit path into `ActionExecutor` (atomic 1:1 relocation)

The core move. Relocate the commit state + resolution functions into the executor, rewire the manager to call/forward, remove dead `_start_ball_action`. One atomic behavior-preserving relocation, proven by the regression grid + a new `check_action_executor`.

**Files:**
- Modify: `scripts/match/action_executor.gd` (receives the moved bodies)
- Modify: `scripts/match/match_manager.gd` (remove moved code; forwarders; getters; call-sites)
- Create: `tests/check_action_executor.gd`

**Interfaces:**
- Consumes: `ActionExecutor.setup` (Task 1); `MatchManager.ChargeAction` enum; manager helpers `_aim_dir`/`_ai_of`/`_player_visual`/`_player_motor`/`_sync_ai_controllers`/`begin_pass_receive`/`controlled_player`/`_manual_swap_cooldown`/`_attack_dir_z`/`field_length`.
- Produces: `ActionExecutor.fire_shot(action:int, player:CharacterBody3D, charge_ratio:float, facing_override:=Vector3.ZERO)`, `fire_pass(...)` (same signature), `on_action_contact(a:String,p:Node)`, `on_action_finished(a:String,p:Node)`, `cancel_action(p:Node)`, and real `action_player()`/`is_kick_action_active()`.

- [ ] **Step 1: Add the moved state + real getters to the executor**

In `scripts/match/action_executor.gd`, add the state fields after `_ball` and replace the placeholder getters:

```gdscript
var _manager: Node
var _ball: RigidBody3D

# Commit-состояние (перенесено из match_manager): пока идёт клип действия — управление заблокировано,
# импульс применяется по action_contact, разблокировка по action_finished.
var _action_player: CharacterBody3D
var _action_dir: Vector3 = Vector3.ZERO
var _action_power: float = 0.0
var _kick_action_active: bool = false          # true → клип удара; импульс отложен, мотор НЕ залочен
var _pending_launch: Vector3 = Vector3.ZERO
var _pending_curl: Vector3 = Vector3.ZERO
var _pending_flat: bool = false                # true → настильный удар низом (катится без подскока)
var _pass_rng := RandomNumberGenerator.new()

func setup(manager: Node, ball: RigidBody3D) -> void:
	_manager = manager
	_ball = ball
	_pass_rng.randomize()

func action_player() -> CharacterBody3D:
	return _action_player

func is_kick_action_active() -> bool:
	return _kick_action_active
```

- [ ] **Step 2: Cut the moved functions from the manager into the executor**

From `scripts/match/match_manager.gd`, CUT these functions verbatim (whole `func ...` bodies) and PASTE them into `scripts/match/action_executor.gd`:
`_ground_launch`, `_fire_shot`, `_pass_params`, `_team_arrays`, `_maybe_flag_interceptor`, `_ball_gravity`, `_target_goal_center`, `_fire_pass`, `_clear_wall_pass_cooldown`, `_on_action_contact`, `_on_action_finished`, `_cancel_ball_action`.

Then rename the public ones in the executor:
- `func _fire_shot(` → `func fire_shot(` and change its first param `action: ChargeAction` → `action: int`
- `func _fire_pass(` → `func fire_pass(` and change its first param `action: ChargeAction` → `action: int`
- `func _pass_params(action: ChargeAction` → `func _pass_params(action: int`
- `func _on_action_contact(` → `func on_action_contact(`
- `func _on_action_finished(` → `func on_action_finished(`
- `func _cancel_ball_action(` → `func cancel_action(`

Also from the manager, DELETE the now-orphaned state declarations (lines ~60-79): `_action_player`, `_action_dir`, `_action_power`, `_kick_action_active`, `_pending_launch`, `_pending_curl`, `_pending_flat`, `_pass_rng` (and its `_pass_rng.randomize()` in `_ready`, ~line 107), and the dead `_start_ball_action` function (~1699-1716).

- [ ] **Step 3: Apply the prefix-rewrite rules inside the executor**

Apply the *Prefix-rewrite rules* (File Structure section) to every moved line in `action_executor.gd`:
- `ball` → `_ball`
- `ChargeAction.` → `MatchManager.ChargeAction.`
- bare `_aim_dir(`/`_ai_of(`/`_player_visual(`/`_player_motor(`/`_sync_ai_controllers(`/`begin_pass_receive(`/`controlled_player`/`_manual_swap_cooldown`/`_attack_dir_z`/`field_length` → `_manager.`-prefixed

Specific spots to verify (from the original line numbers):
- `fire_shot`: `ball.get_dribble_direction()`→`_ball.get_dribble_direction()`; `_target_goal_center()` stays bare (moved); `_ball_gravity()` stays bare; `ChargeAction.SHOT_CHIP`/`SHOT_CURL`→`MatchManager.ChargeAction.…`; `_player_visual(player)`→`_manager._player_visual(player)`; every other `ball.`→`_ball.`.
- `fire_pass`: `_team_arrays(&"team_1", player)` stays bare (moved); `_aim_dir(player)`→`_manager._aim_dir(player)`; `_maybe_flag_interceptor(...)` stays bare (moved); `controlled_player = receiver`→`_manager.controlled_player = receiver`; `_sync_ai_controllers()`→`_manager._sync_ai_controllers()`; `_manual_swap_cooldown = 30`→`_manager._manual_swap_cooldown = 30`; `_ai_of(receiver)`→`_manager._ai_of(receiver)`; `_ai_of(player)`→`_manager._ai_of(player)`; the receive-assist set (`_receive_active=true; _receiver=receiver; _receive_timer=…`) → **replace those 3 lines with `_manager.begin_pass_receive(receiver)`** (that manager method does exactly the same 3 assignments — 1:1); `_clear_wall_pass_cooldown()` stays bare (moved); `ChargeAction.PASS_*`→`MatchManager.ChargeAction.PASS_*`; `_attack_dir_z`→`_manager._attack_dir_z`; every `ball.`→`_ball.`.
- `_maybe_flag_interceptor`: `_team_arrays(...)` stays bare; `_ai_of(...)`→`_manager._ai_of(...)`; `ball`→`_ball`.
- `_team_arrays`: `get_tree()...` stays (executor is a Node); no manager helper inside.
- `_target_goal_center`: `_attack_dir_z * field_length`→`_manager._attack_dir_z * _manager.field_length`.
- `_ball_gravity`: `ball.gravity_scale`→`_ball.gravity_scale`.
- `on_action_contact` / `on_action_finished` / `cancel_action`: `ball`→`_ball`; `_player_motor(player)`→`_manager._player_motor(player)`; `_player_visual(player)`→`_manager._player_visual(player)`.
- `_clear_wall_pass_cooldown`: `ball`→`_ball`.

Verification greps (must print nothing — every hit would be an un-rewritten manager symbol):
```powershell
Select-String -Path "$REPO\scripts\match\action_executor.gd" -Pattern '(?<![\._\w])ball\b' | Where-Object { $_.Line -notmatch '_ball' }
Select-String -Path "$REPO\scripts\match\action_executor.gd" -Pattern '(?<![\._\w])(controlled_player|_attack_dir_z|field_length|_manual_swap_cooldown)\b' | Where-Object { $_.Line -notmatch '_manager\.' }
Select-String -Path "$REPO\scripts\match\action_executor.gd" -Pattern '(?<![\._\w])(_aim_dir|_ai_of|_player_visual|_player_motor|_sync_ai_controllers|begin_pass_receive)\(' | Where-Object { $_.Line -notmatch '_manager\.' }
Select-String -Path "$REPO\scripts\match\action_executor.gd" -Pattern '(?<![\.\w])ChargeAction\.' | Where-Object { $_.Line -notmatch 'MatchManager\.ChargeAction' }
Select-String -Path "$REPO\scripts\match\action_executor.gd" -Pattern '_receive_active|_receiver\b|_receive_timer'
```
(The last grep must be empty — the receive-assist set became `_manager.begin_pass_receive(receiver)`.)

- [ ] **Step 4: Rewire the manager — forwarders, getters, call-sites**

In `scripts/match/match_manager.gd`:

**4a — thin forwarders** (replace the now-cut `_on_action_contact`/`_on_action_finished`/`_cancel_ball_action` with forwarders; the factory + `_cancel_ball_action`'s caller at ~1956 keep calling these unchanged):
```gdscript
## Момент касания ногой (сигнал PlayerVisual, проводится фабрикой) → в ActionExecutor.
func _on_action_contact(action: String, player: Node) -> void:
	_action_executor.on_action_contact(action, player)

## Действие завершилось (сигнал PlayerVisual) → в ActionExecutor.
func _on_action_finished(action: String, player: Node) -> void:
	_action_executor.on_action_finished(action, player)

## Отменить действие игрока (сбили подкатом на замахе) → в ActionExecutor.
func _cancel_ball_action(player: Node) -> void:
	_action_executor.cancel_action(player)
```

**4b — `_fire_charge` call-sites** (~1321, 1325):
```gdscript
	if action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]:
		var ratio := clampf(_charge_time / KICK_CHARGE_MAX_TIME, 0.0, 1.0)
		_cancel_charge()
		_action_executor.fire_shot(action, player, ratio)
	else:
		var charge_ratio := clampf(_charge_time / FootballConstants.PASS_CHARGE_MAX_TIME, 0.0, 1.0)
		_cancel_charge()
		_action_executor.fire_pass(action, player, charge_ratio)
```

**4c — `_try_fire_queue` call-sites** (~1480, 1482):
```gdscript
	if action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]:
		_action_executor.fire_shot(action, player, eff_ratio, facing.normalized())
	else:
		_action_executor.fire_pass(action, player, eff_ratio, facing.normalized())
```

**4d — getter swaps** — replace the two field reads:
- `_handle_player_input` (~1067): `if _action_player == controlled_player and not _kick_action_active:` → `if _action_executor.action_player() == controlled_player and not _action_executor.is_kick_action_active():`
- `_handle_dribbling` (~1113): `ball.set_dribble_suppressed(_is_charging() or _kick_action_active or not active)` → `ball.set_dribble_suppressed(_is_charging() or _action_executor.is_kick_action_active() or not active)`

Verification greps in the manager (must print nothing — all commit state/functions are gone from the manager):
```powershell
Select-String -Path "$REPO\scripts\match\match_manager.gd" -Pattern '(?<![\.\w])(_action_player|_action_dir|_action_power|_kick_action_active|_pending_launch|_pending_curl|_pending_flat|_pass_rng)\b'
Select-String -Path "$REPO\scripts\match\match_manager.gd" -Pattern 'func (_fire_shot|_fire_pass|_pass_params|_maybe_flag_interceptor|_ground_launch|_target_goal_center|_ball_gravity|_team_arrays|_clear_wall_pass_cooldown|_start_ball_action)\b'
```

- [ ] **Step 5: Write `tests/check_action_executor.gd`**

```gdscript
extends SceneTree
## Фаза 3a: ActionExecutor резолвит запрос действия в импульс мяча. Гоняем на реальной сцене
## (как check_penalty_flow): ставим мяч игроку в ноги, зовём fire_pass, армим коммит, форсим
## контакт анимации (on_action_contact) и проверяем, что мячу придан импульс. Плюс — что геттеры
## action_player()/is_kick_action_active() отражают состояние коммита.

var _mm: Node
var _ax: Node
var _frames := 0
var _phase := 0
var _armed_ok := false

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)
	physics_frame.connect(_tick)

func _fail(m: String) -> void:
	print("CHECK FAIL: ", m); quit(1)

func _tick() -> void:
	_frames += 1
	if _frames < 15:
		return
	var ball := _mm.get_node("Ball") as RigidBody3D
	var player: Node3D = _mm.get(&"controlled_player")
	_ax = _mm.get(&"_action_executor")
	if _ax == null:
		_fail("нет _action_executor"); return
	if player == null:
		_fail("нет controlled_player"); return
	match _phase:
		0:
			# Мяч в ноги игроку, гасим его скорость — чистая точка старта паса.
			ball.global_position = player.global_position + Vector3(0, 0.1, 0)
			ball.linear_velocity = Vector3.ZERO
			# PASS_SHORT = значение enum ChargeAction в менеджере; берём через сам менеджер, чтобы
			# не зависеть от числового значения.
			var pass_short: int = MatchManager.ChargeAction.PASS_SHORT
			_ax.fire_pass(pass_short, player, 0.7)
			# Коммит армирован: action_player выставлен, kick-флаг для паса = true.
			_armed_ok = _ax.action_player() == player and _ax.is_kick_action_active()
			_phase = 1
			return
		1:
			# Форсим контакт анимации → импульс.
			_ax.on_action_contact("pass", player)
			_phase = 2
			_frames = 0
			return
		2:
			if _frames < 3:
				return
			var launched: bool = ball.linear_velocity.length() > 1.0
			print("SMOKE: armed=", _armed_ok, " ball_speed=", ball.linear_velocity.length())
			if _armed_ok and launched:
				print("CHECK PASS: ActionExecutor.fire_pass arms the commit and on_action_contact launches the ball")
				quit(0)
			else:
				_fail("armed=" + str(_armed_ok) + " launched=" + str(launched))
```

- [ ] **Step 6: Rebuild the class cache + run the full regression grid**

```powershell
& $GODOT --path $REPO --headless --editor --quit
```
Then the full grid. Expected: `check_action_executor` PASS; `check_free_kick_flow`/`check_penalty_flow`/`check_ball_state`/`check_setpiece_goal_freeze`/`check_penalty_keeper_line` PASS (they exercise the moved pass/shot/impulse path); match scene loads with only baseline error categories; `check_keeper_clear` majority PASS.

- [ ] **Step 7: Playtest (mandatory — feel-critical)**

Run the game (`& $GODOT --path $REPO`). Confirm 1:1 feel: shot (`D`, all charge levels — ground tap / full / chip / curl), clearance (own half, facing away), the five pass types, one-touch queue (charge before the ball arrives), give-and-go, receive-assist handoff, and interception. Nothing should feel different from before — this is a pure relocation. **Headless cannot verify feel; this step is required.**

- [ ] **Step 8: Commit**

```powershell
git add scripts/match/action_executor.gd scripts/match/match_manager.gd tests/check_action_executor.gd
git commit -m @'
refactor(phase3a): move the ball-commit/resolution path into ActionExecutor

1:1 relocation of the shared commit path (fire_shot/fire_pass + _pass_params/
_maybe_flag_interceptor/_ground_launch/_target_goal_center/_ball_gravity/_team_arrays/
_clear_wall_pass_cooldown + on_action_contact/on_action_finished/cancel_action + the
_action_*/_pending_*/_pass_rng state) out of the ~2260-line match_manager into a focused
ActionExecutor node. Manager keeps thin signal-forwarders (factory wiring untouched) and
two getters (action_player/is_kick_action_active); _fire_charge/_try_fire_queue call the
executor; the charge-as-timer + queue system stays in the manager (moves to HumanBrain in
3b). Dead _start_ball_action removed. Behavior 1:1 (regression grid green + playtest).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
'@
```

---

## Task 3: Docs

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`

- [ ] **Step 1: Update `CLAUDE.md`**

In the *Passing* / architecture area, add that the ball-commit/resolution path now lives in `scripts/match/action_executor.gd` (`class_name ActionExecutor extends Node`): it owns the commit state + `fire_shot`/`fire_pass` + impulse application (`on_action_contact`), created/`setup`-ed by the manager in `_ready`; the manager keeps thin `_on_action_contact`/`_on_action_finished`/`_cancel_ball_action` forwarders (factory wiring untouched) and reads commit state via `_action_executor.action_player()`/`is_kick_action_active()`. Note the charge-as-timer + queue + `_aim_dir` stay in the manager (→ `HumanBrain` in Step 3b). Note `class_name MatchManager` now exists (the enum `MatchManager.ChargeAction` is referenced by the executor). Add `check_action_executor.gd` to the headless-check list. Mark Step 3a done; 3b (`HumanBrain`) still pending.

- [ ] **Step 2: Update `AGENTS.md`**

Mirror: `ActionExecutor` node owns the shot/pass commit path (extracted from `match_manager`); manager forwards the `PlayerVisual` action signals to it; charge/input stays in the manager until 3b. Add `scripts/match/action_executor.gd` to the file-layout list.

- [ ] **Step 3: Run the regression grid + commit**

```powershell
git add CLAUDE.md AGENTS.md
git commit -m @'
docs(phase3a): document ActionExecutor + the extracted commit path

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
'@
```

---

## Self-Review

**Spec coverage (Step 3a in the design spec):**
- "извлечение ActionExecutor (select_target → lead/scatter → launch-вектор → триггер анимации → ожидание action_contact → ball.kick/launch → приём-ассист → передача controlled_player) в отдельный объект `scripts/match/action_executor.gd`" → Task 2 moves exactly this set (`fire_pass` covers select_target/lead/scatter/launch/receive-assist/handoff; `on_action_contact` covers the impulse). ✓
- "Перенос кода, поведение 1:1, все тесты зелёные" → Task 2 is a mechanical relocation (prefix rewrites only) + regression grid + playtest. ✓
- "executor с чистым интерфейсом headless-тестируем напрямую" → `check_action_executor.gd` drives `fire_pass`+`on_action_contact` directly. (Partial isolation — runs against a real scene, like the penalty/free-kick tests; noted honestly.) ✓
- "менеджер худеет" → ~290 lines out (~−12%). ✓
- "путь остаётся один и общий с ИИ" → the AI still requests actions the same way (AI kick is `ball.kick` directly today; the human path now routes through `ActionExecutor`, which is the shared seam 3b/HumanBrain will also use). ✓
- Charge-as-timer stays in the manager (spec: "заряд-как-таймер → в HumanBrain" is 3b, not 3a) → correctly left in place. ✓

**Placeholder scan:** No "TBD"/"handle edge cases". The large relocation uses an explicit function list + prefix-rewrite rules + verification greps (same technique as the Phase-2 keeper conversion) rather than pasting ~290 verbatim lines — concrete and gate-checked, not vague. ✓

**Type consistency:** `ActionExecutor.fire_shot/fire_pass(action: int, …)`, `action_player() -> CharacterBody3D`, `is_kick_action_active() -> bool`, `on_action_contact/on_action_finished/cancel_action` used consistently across the executor, the manager forwarders/call-sites, and the test. `MatchManager.ChargeAction.*` (qualified) used in the executor; manager keeps bare `ChargeAction.*`. `_action_executor` field name consistent Task 1↔2↔test. ✓

**Risk note:** The one non-mechanical edit is the receive-assist collapse (3 direct field assignments → `_manager.begin_pass_receive(receiver)`), justified because `begin_pass_receive` is defined as exactly those three assignments — verified 1:1 in Task 2 Step 3, and gate-checked by the "empty `_receive_*` grep". The feel-critical nature means Task 2 Step 7 (playtest) is non-optional.

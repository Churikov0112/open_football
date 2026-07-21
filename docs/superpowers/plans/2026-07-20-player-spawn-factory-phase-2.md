# Player Spawn Factory — Phase 2 (AI Brains as Components) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the three AI scripts off the player body root (`set_script`) and onto a child `Brain` component attached by `PlayerFactory`, with a stable `Player` root script — a pure refactor with zero visible gameplay change.

**Architecture:** The player body gets a stable root script `player.gd` (`class_name Player extends CharacterBody3D`). Each AI becomes a child `Brain` node (`class_name Brain extends Node`) that reads its body via `_body := get_parent()`. The factory auto-detects a Brain script (`inst is Brain`) and attaches it as a child instead of `set_script`-ing the root. A single manager helper `_ai_of(body) -> Node` resolves "the AI object of this body" (its child brain, or the body itself for legacy/no-AI), so every manager call-site into AI fields/methods is rerouted through one indirection that works identically for legacy-scripted and component bodies. This makes the four conversions (infra, simple_ai, teammate_ai, keeper_ai) independent and each leaves the game runnable and every headless test green.

**Tech Stack:** Godot 4.7, GDScript. Headless `SceneTree` check scripts (no test framework). Windows / PowerShell.

## Global Constraints

- **Godot exe (console build):** `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`
- **Repo path:** `C:\Users\User\Desktop\projects\OpenFootball`
- **Every step must leave the game runnable and all headless tests green.** After each task run the full **regression grid** (below).
- **Zero visible gameplay change** is the only real safety net (pure refactor) — a human playtest ("plays like before") is required after Task 3 and after Task 4.
- **`Brain` subclasses never read `FootballConstants` in `_ready`** — fields are injected by the factory after `add_child`, so `_ready` may only cache `_body := get_parent()`; anything reading injected fields (`ball`, `speed`, `goal_line_z`, …) must run in `_physics_process`/methods, not `_ready`.
- **`ball.global_position` / `target.global_position` / `mark_target.global_position` / `carrier.global_position` / `home_goal.global_position` are NOT the AI's own transform** — only *bare* `global_position` / `global_transform` / `move_and_collide` / `get_children()` / `is_in_group` / `add_to_group` / `remove_from_group` (the ones referring to the body the script used to BE) get rewritten to `_body.…`.
- **Keeper is the riskiest conversion** (save-loop, `move_and_collide` dive, ball catch/attachment, distribution). Run the keeper tests after every keeper edit; `check_keeper_clear.gd` is **known flaky headless (~1-in-5)** — re-run it 3× and treat only a *consistent* failure as a regression.

### Regression grid (run after every task)

Set once per shell:

```powershell
$GODOT = "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe"
$REPO  = "C:\Users\User\Desktop\projects\OpenFootball"
```

Then:

```powershell
# 1) menu load (parses all globally-registered class_name scripts + autoloads)
& $GODOT --path $REPO --headless --quit
# 2) match scene load (exercises match_manager/simple_ai/teammate_ai/keeper_ai)
& $GODOT --path $REPO --headless --quit-after 2 res://scenes/match.tscn
# 3) headless check scripts (each prints CHECK PASS / CHECK FAIL, exits 0/1)
foreach ($t in @(
  "check_player_config","check_team_roster","check_player_factory","check_player_brain",
  "check_free_kick_flow","check_penalty_flow","check_keeper_logic","check_kick_grace","check_ball_state"
)) { & $GODOT --path $REPO --headless -s "res://tests/$t.gd"; Write-Host "exit=$LASTEXITCODE $t" }
# 4) flaky keeper cycle — run 3× and require majority PASS
1..3 | % { & $GODOT --path $REPO --headless -s "res://tests/check_keeper_clear.gd"; Write-Host "exit=$LASTEXITCODE keeper_clear run $_" }
```

**Match-scene error baseline (command 2)** — diff by error *category/text*, NOT exact counts (counts grew with the keeper). Known-OK categories: `ERROR: Condition "!is_inside_tree()" is true.`, the `ACTION_CLIPS` duplicate-registration trio (`Condition "states.has(p_name)" is true` + two transition-duplicate errors), and `ERROR: Cannot get class 'WorldEnvironment3D'.`. Any *new* category = regression.

---

## File Structure

- **Create** `scripts/ai/brain.gd` — `class_name Brain extends Node`. Base component: caches `_body`, exposes `movement_intent()`/`speed_scale()`/`body()`/`set_active()`, and a `_drive()`/`_stop()` helper the field brains use to push intent into the motor. One responsibility: "the movement-brain seam."
- **Create** `scripts/player/player.gd` — `class_name Player extends CharacterBody3D`. Stable body root: identity fields + `brain()` lookup. One responsibility: "the stable player body identity + brain accessor."
- **Modify** `scenes/player.tscn` — root `CharacterBody3D` gains `script = player.gd`.
- **Modify** `scripts/match/player_factory.gd` — brain block: auto-detect `inst is Brain` → attach component (else legacy `set_script`); field injection targets the AI object (brain or body).
- **Modify** `scripts/ai/simple_ai.gd` — `extends CharacterBody3D` → `extends Brain`; `self`→`_body`; motor calls → `_drive`/`_stop`.
- **Modify** `scripts/ai/teammate_ai.gd` — same conversion; `controlled_player == self` → `== _body`.
- **Modify** `scripts/ai/keeper_ai.gd` — `extends CharacterBody3D` → `extends Brain`; `self`→`_body` throughout (rule + checklist + verification grep).
- **Modify** `scripts/match/match_manager.gd` — add `_ai_of()` helper + `_keeper_brain`; reroute AI call-sites; keeper-API sites through `_keeper_brain`.
- **Modify** `scripts/match/free_kick_controller.gd` — `_convert_bodies` `set_script` → attach Brain component; `_keeper_brain` for keeper API.
- **Modify** `scripts/match/penalty_controller.gd` — `_keeper_brain` for keeper API.
- **Create** `tests/check_player_brain.gd` — asserts the `Player`/`Brain` seam.
- **Modify** `tests/check_keeper_clear.gd` — read keeper state via `keeper.brain()`.
- **Modify** `CLAUDE.md`, `AGENTS.md` — document the component-brain architecture.

---

## Task 1: Infrastructure — `Brain` base, `Player` root, factory auto-detect, `_ai_of` rerouting (behavior-neutral)

Introduces every seam and reroutes every manager AI call-site **without converting any AI**. Because all AIs are still `extends CharacterBody3D`, the factory takes the legacy `set_script` path for all of them and `_ai_of()` resolves to the body — so behavior is identical (the regression grid proves it). Keeper API sites are left untouched (keeper is still legacy; `_keeper` stays the body) — they move in Task 4.

**Files:**
- Create: `scripts/ai/brain.gd`
- Create: `scripts/player/player.gd`
- Create: `tests/check_player_brain.gd`
- Modify: `scenes/player.tscn`
- Modify: `scripts/match/player_factory.gd:31-39`
- Modify: `scripts/match/match_manager.gd` (add `_ai_of`; reroute `_set_ai_frozen`, `_poll_ai_tackles`, `_maybe_flag_interceptor`, `_sync_ai_controllers`, `_fire_pass` receiver, `_setup_home_player`)

**Interfaces:**
- Produces: `class_name Brain extends Node` with `func body() -> CharacterBody3D`, `func movement_intent() -> Vector3` (default `Vector3.ZERO`), `func speed_scale() -> float` (default `0.0`), `func set_active(on: bool) -> void`, and protected `func _drive(dir: Vector3, scale: float = 1.0) -> void` / `func _stop() -> void` (used by Task 2/3 field brains). `var _body: CharacterBody3D` cached in `_ready`.
- Produces: `class_name Player extends CharacterBody3D` with `func brain() -> Node` (first child that `is Brain`, else `null`), and plain identity fields `team_group: StringName`, `role: int`.
- Produces: `MatchManager._ai_of(body: Node) -> Node` — returns `body.brain()` if non-null else `body`.
- Consumes: `PlayerMotor.find_on(node)` (existing, scans a node's children for `PlayerMotor`).

- [ ] **Step 1: Write `scripts/ai/brain.gd`**

```gdscript
class_name Brain
extends Node
## Базовый компонент-«мозг» игрока (Фаза 2). Живёт дочерним узлом тела (player.tscn);
## тело своё берёт как _body := get_parent(). Ничего не двигает в _ready — поля (ball и т.п.)
## инъектит фабрика ПОСЛЕ add_child, поэтому _ready кэширует только _body.
## Полевые мозги пушат намерение в мотор через _drive()/_stop(); movement_intent()/speed_scale()
## — читаемый seam для Фазы 3 (человек-мозг), в Фазе 2 их драйв остаётся внутри каждого мозга.

var _body: CharacterBody3D
var _intent: Vector3 = Vector3.ZERO
var _intent_scale: float = 0.0

func _ready() -> void:
	_body = get_parent() as CharacterBody3D

## Тело, к которому прикреплён этот мозг (то, чем скрипт «был» до компонентизации).
func body() -> CharacterBody3D:
	return _body

## Непрерывное состояние движения (seam Фазы 3). В Фазе 2 — последнее, что мозг задал мотору.
func movement_intent() -> Vector3:
	return _intent

func speed_scale() -> float:
	return _intent_scale

## Вкл/выкл мозга — глушим/возвращаем его физпроцесс (заморозка на голе/сет-писе).
func set_active(on: bool) -> void:
	set_physics_process(on)

## Полевой драйв: запомнить намерение (для геттеров) И толкнуть его в PlayerMotor тела.
func _drive(dir: Vector3, scale: float = 1.0) -> void:
	_intent = dir
	_intent_scale = scale if dir.length() > 0.001 else 0.0
	var m := PlayerMotor.find_on(_body)
	if m != null:
		m.set_move_intent(dir, scale)

func _stop() -> void:
	_drive(Vector3.ZERO, 0.0)
```

- [ ] **Step 2: Write `scripts/player/player.gd`**

```gdscript
class_name Player
extends CharacterBody3D
## Стабильный корень тела игрока (Фаза 2). Заменяет прежнюю схему «set_script(ai) на корень».
## Мозг — дочерний Brain-узел (вешает фабрика). Группы team_x/role_x остаются физическим индексом;
## эти поля — удобный геймплей-дубликат (пока необязательны, seam на будущее).

var team_group: StringName = &"team_1"
var role: int = 0   # PlayerConfig.Role.*

## Первый дочерний Brain, либо null (нет ИИ / человек в конечной Фазе 3 / легаси set_script).
func brain() -> Node:
	for c in get_children():
		if c is Brain:
			return c
	return null
```

- [ ] **Step 3: Attach `player.gd` to the `player.tscn` root**

Edit `scenes/player.tscn`. Add an ext_resource for the script and set it on the root node. Bump `load_steps` from `4` to `5`.

```
[gd_scene load_steps=5 format=3]

[ext_resource type="PackedScene" path="res://scenes/player_visual.tscn" id="1"]
[ext_resource type="Script" path="res://scripts/player/player_motor.gd" id="2"]
[ext_resource type="Script" path="res://scripts/player/player.gd" id="3"]

[sub_resource type="CapsuleShape3D" id="1"]
height = 1.5
radius = 0.3

[node name="Player" type="CharacterBody3D"]
script = ExtResource("3")

[node name="PlayerVisual" parent="." instance=ExtResource("1")]

[node name="PlayerMotor" type="Node" parent="."]
script = ExtResource("2")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.25, 0)
shape = SubResource("1")
```

Note: for legacy AI bodies the factory still `set_script`s the root (replacing `player.gd`) — harmless; those bodies just won't have `brain()`, which `_ai_of` handles. For `ai_script = null` bodies (wall/mate/test-factory) the root stays `player.gd` (a passive data holder) — no behavior change.

- [ ] **Step 4: Factory — auto-detect Brain vs legacy; inject fields on the AI object**

In `scripts/match/player_factory.gd`, replace the brain block + field injection (lines 31-39):

Old:
```gdscript
	# мозг (Фаза 1: set_script; Фаза 2 заменит компонентом)
	if config.control_mode == PlayerConfig.ControlMode.AI and config.ai_script != null:
		body.set_script(config.ai_script)
		body.set_physics_process(true)
	# общая ссылка на мяч + пер-ролевые поля
	if team.ball != null:
		body.set(&"ball", team.ball)
	for k in config.extra_fields:
		body.set(k, config.extra_fields[k])
	return body
```

New:
```gdscript
	# мозг (Фаза 2): Brain-скрипт → дочерний компонент; легаси (extends CharacterBody3D) → set_script.
	# Автодетект через `is Brain` не требует правки конфигов при конверсии ИИ по одному.
	var ai_target: Object = body
	if config.control_mode == PlayerConfig.ControlMode.AI and config.ai_script != null:
		var inst: Object = config.ai_script.new()
		if inst is Brain:
			(inst as Node).name = "Brain"
			body.add_child(inst)          # Brain._ready кэширует _body = get_parent()
			ai_target = inst
		else:
			(inst as Node).free()         # легаси: проба-инстанс не нужна, идём через set_script
			body.set_script(config.ai_script)
			body.set_physics_process(true)
			ai_target = body
	# общая ссылка на мяч + пер-ролевые поля — на мозг (компонент) либо тело (легаси)
	if team.ball != null:
		ai_target.set(&"ball", team.ball)
	for k in config.extra_fields:
		ai_target.set(k, config.extra_fields[k])
	return body
```

- [ ] **Step 5: Manager — add `_ai_of()` and reroute AI call-sites**

In `scripts/match/match_manager.gd`, add the helper (place it next to `_player_motor`, ~line 1773):

```gdscript
## «ИИ-объект этого тела»: дочерний Brain-компонент, либо само тело (легаси set_script / без ИИ).
## Единственная точка, где менеджер дотягивается до полей/методов ИИ — работает одинаково для
## компонентных и легаси-тел, поэтому конверсию ИИ можно делать по одному, не ломая менеджер.
func _ai_of(body: Node) -> Node:
	if body != null and body.has_method(&"brain"):
		var b: Node = body.brain()
		if b != null:
			return b
	return body
```

Then reroute, one site at a time:

**5a — `_set_ai_frozen` (line 674):** replace `n.set_physics_process(not on)` with:
```gdscript
		_ai_of(n).set_physics_process(not on)
```

**5b — `_poll_ai_tackles` (lines 2233-2239):** replace body of the loop:
```gdscript
	for node in get_tree().get_nodes_in_group("team_2"):
		if not is_instance_valid(node):
			continue
		var ai := _ai_of(node)
		if "wants_to_tackle" in ai and ai.wants_to_tackle:
			_start_tackle(node)          # подкат берёт ТЕЛО (node), не мозг
			ai.wants_to_tackle = false
```

**5c — `_maybe_flag_interceptor` (lines 1531, 1542-1545):** speed read:
```gdscript
		var speed_variant: Variant = _ai_of(opp_nodes[i]).get(&"speed")
```
and the intercept dispatch:
```gdscript
	var opp: Node3D = opp_nodes[best_i]
	var opp_ai := _ai_of(opp)
	if opp_ai.has_method(&"begin_intercept"):
		var point := from + Vector3(launch_vel.x, 0.0, launch_vel.z).normalized() * (best_time * ball_speed)
		opp_ai.begin_intercept(point)
```

**5d — `_sync_ai_controllers` (lines 962-964):** 
```gdscript
	for n in get_tree().get_nodes_in_group("team_1"):
		var ai := _ai_of(n)
		if &"controlled_player" in ai:
			ai.controlled_player = controlled_player
```

**5e — `_fire_pass` receiver/give-and-go (lines 1660-1668):** 
```gdscript
	if receiver != null and receiver != controlled_player and _ai_of(receiver).has_method(&"begin_receiving"):
		_ai_of(receiver).begin_receiving(launch_vel, params.extra_lead)
	if receiver != null and receiver == controlled_player:
```
(leave the `receiver == controlled_player` branch body unchanged) and the wall branch:
```gdscript
	if params.is_wall and is_instance_valid(player) and _ai_of(player).has_method(&"begin_give_and_go"):
		if receiver != null:
			_ai_of(player).begin_give_and_go(receiver.global_position)
```

**5f — `_setup_home_player` (line 583):** replace `_human_player.set(&"controlled_player", controlled_player)` with:
```gdscript
	_ai_of(_human_player).set(&"controlled_player", controlled_player)
```

- [ ] **Step 6: Write `tests/check_player_brain.gd`**

```gdscript
extends SceneTree
## Seam Фазы 2: player.tscn имеет корень Player с brain(); Brain кэширует _body и отдаёт дефолты;
## set_active переключает физпроцесс. Работа отложена на _process (root не is_inside_tree() в
## _initialize — тот же паттерн, что в check_player_factory.gd).

var _done: bool = false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var ok := true

	var body := preload("res://scenes/player.tscn").instantiate()
	root.add_child(body)
	if not (body is Player):
		ok = false; print("CHECK FAIL: root is not Player")
	if body.brain() != null:
		ok = false; print("CHECK FAIL: brain() should be null before attach")

	var b := Brain.new()
	b.name = "Brain"
	body.add_child(b)                       # _ready → _body = get_parent()
	if body.brain() != b:
		ok = false; print("CHECK FAIL: brain() did not find the child Brain")
	if b.body() != body:
		ok = false; print("CHECK FAIL: Brain._body is not the parent body")
	if b.movement_intent() != Vector3.ZERO:
		ok = false; print("CHECK FAIL: movement_intent default not ZERO")
	if b.speed_scale() != 0.0:
		ok = false; print("CHECK FAIL: speed_scale default not 0")

	b.set_active(true)
	if not b.is_physics_processing():
		ok = false; print("CHECK FAIL: set_active(true) did not enable physics process")
	b.set_active(false)
	if b.is_physics_processing():
		ok = false; print("CHECK FAIL: set_active(false) did not disable physics process")

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true
```

- [ ] **Step 7: Run the regression grid**

Run every command in the Global Constraints grid. Expected: command 1 clean; command 2 shows only baseline error categories (no NEW category); all check scripts `exit=0` (`check_keeper_clear` majority PASS). `check_player_brain` PASS.

- [ ] **Step 8: Commit**

```powershell
git add scripts/ai/brain.gd scripts/player/player.gd scenes/player.tscn scripts/match/player_factory.gd scripts/match/match_manager.gd tests/check_player_brain.gd
git commit -m @'
refactor(phase2): Brain base + Player root + factory auto-detect + _ai_of rerouting

Introduces the component-brain seam with zero behavior change: all AIs are still
extends CharacterBody3D, so the factory takes the legacy set_script path and
_ai_of() resolves to the body. Manager AI call-sites rerouted through _ai_of so
per-AI conversion is independent from here on.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
'@
```

---

## Task 2: Convert `simple_ai.gd` to a Brain component

`simple_ai` (opponent) becomes `extends Brain`. The factory now auto-attaches it as a child for the away player + wall dummies; the manager already routes through `_ai_of`. The free-kick wall branch of `_convert_bodies` must switch from `set_script` to a Brain child (wall bodies use `simple_ai`). `teammate_ai` and `keeper_ai` stay legacy — `_ai_of` bridges the mix.

**Files:**
- Modify: `scripts/ai/simple_ai.gd`
- Modify: `scripts/match/free_kick_controller.gd:495-510` (wall branch of `_convert_bodies`)

**Interfaces:**
- Consumes: `Brain._body`, `Brain._drive()`, `Brain._stop()` (Task 1).
- Produces: `simple_ai` (a `Brain`) with the unchanged public surface the manager/free-kick use: `@export var speed`, `var wants_to_tackle`, `func begin_intercept(point)`, `var ball`, `var home_goal`, `var target_node`, `var mark_target`.

- [ ] **Step 1: Convert `simple_ai.gd` — header, remove `_motor()`**

Line 1: `extends CharacterBody3D` → `extends Brain`.

Remove the `_motor()` helper (lines 26-27):
```gdscript
func _motor() -> PlayerMotor:
	return PlayerMotor.find_on(self)
```
(The base `Brain._drive()`/`_stop()` replace it. `_base_scale()` stays.)

- [ ] **Step 2: Convert `simple_ai.gd` — `self`→`_body`, motor→`_drive`/`_stop`**

Apply these exact edits (bare `global_position` → `_body.global_position`; `is_in_group` → `_body.is_in_group`; `self` in `ball.dribbler == self` → `_body`):

| Line(s) | Old | New |
|---|---|---|
| 44-45 | `var dm := _motor()` / `if dm != null:` / `dm.set_move_intent(Vector3.ZERO)` | `_stop()` (replace all three lines) |
| 51 | `if is_in_group("fallen"):` | `if _body.is_in_group("fallen"):` |
| 59-65 | `var km := _motor()` … `km.set_move_intent(to_center.normalized(), _base_scale() * 0.4)` … `else:` `km.set_move_intent(Vector3.ZERO)` | drop `_motor()`; `var to_center := Vector3(-_body.global_position.x, 0.0, -_body.global_position.z)`; `if to_center.length() > 1.0:` `_drive(to_center.normalized(), _base_scale() * 0.4)` `else:` `_stop()` |
| 75 | `ball.dribbler == self` | `ball.dribbler == _body` |
| 76, 80 | `global_position` | `_body.global_position` |
| 82-84 | `var m := _motor()` / `if m != null:` / `m.set_move_intent(dir.normalized(), _base_scale())` | `_drive(dir.normalized(), _base_scale())` |
| 109 | `global_position.distance_to(target.global_position)` | `_body.global_position.distance_to(target.global_position)` |
| 116 | `ball.dribbler == self` | `ball.dribbler == _body` |
| 125-135 (`_mark`) | bare `global_position` (lines 134, 135) | `_body.global_position` |
| 141, 148, 154 | bare `global_position` | `_body.global_position` |
| 168, 172 | `home_goal.global_position` stays; bare `global_position` (172) | line 172 `global_position` → `_body.global_position` |
| 184-190 (`_move_or_wander`) | `var m := _motor()` / `if m != null:` / `m.set_move_intent(dir, _base_scale() * speed_multiplier)` / `else:` `_wander(...)` | `if dir.length() > 0.1:` `_drive(dir, _base_scale() * speed_multiplier)` `else:` `_wander(delta, speed_multiplier)` |
| 198-203 (`_wander`) | `global_position.z`/`global_position.x`; `var m := _motor()` / `if m != null:` / `m.set_move_intent(wander_dir, _base_scale() * 0.3 * speed_multiplier)` | `_body.global_position.z`/`.x`; `_drive(wander_dir, _base_scale() * 0.3 * speed_multiplier)` |
| 215 | `home_goal.global_position` stays (no change) | — |
| 220 | `ball.global_position` stays (no change) | — |

Verification grep (must return **no bare** occurrences — every hit is `_body.`/`ball.`/`target.`/`mark_target.`/`home_goal.`-prefixed):
```powershell
& $GODOT --version > $null   # sanity
Select-String -Path "$REPO\scripts\ai\simple_ai.gd" -Pattern '(?<![\._a-zA-Z])global_position' | Where-Object { $_.Line -notmatch '_body\.|ball\.|target\.|mark_target\.|home_goal\.' }
Select-String -Path "$REPO\scripts\ai\simple_ai.gd" -Pattern '(?<![\.\w])self\b'
Select-String -Path "$REPO\scripts\ai\simple_ai.gd" -Pattern '_motor\(\)'
```
All three must print nothing.

- [ ] **Step 3: Convert the wall branch of `free_kick_controller._convert_bodies`**

In `scripts/match/free_kick_controller.gd`, replace the wall loop body (lines 507-510) — `set_script` → Brain child:

Old:
```gdscript
		b.set_script(ai_script)
		b.set_physics_process(true)
		b.ball = _ball
		b.home_goal = _manager.get_node_or_null("GoalHome/GoalArea")
```
New:
```gdscript
		var wb := ai_script.new()          # simple_ai теперь Brain-компонент
		wb.name = "Brain"
		b.add_child(wb)
		wb.ball = _ball
		wb.home_goal = _manager.get_node_or_null("GoalHome/GoalArea")
```
(Leave `var ai_script := preload("res://scripts/ai/simple_ai.gd")` at line 496 and the `set_control_locked(false)` above unchanged. The mate branch (teammate_ai, lines 512-523) stays `set_script` for now — converted in Task 3.)

- [ ] **Step 4: Run the regression grid**

Expected all green. `check_free_kick_flow` PASS is the key gate (it exercises `_convert_bodies` → wall bodies become live `simple_ai` brains). `check_player_brain` PASS.

- [ ] **Step 5: Playtest smoke (opponent)**

Run the game (`& $GODOT --path $REPO`). Confirm the AI opponent chases/dribbles/shoots and can slide-tackle exactly as before. (Opponent is disabled only under `DEBUG_DISABLE_OPPONENT`, currently `false`.)

- [ ] **Step 6: Commit**

```powershell
git add scripts/ai/simple_ai.gd scripts/match/free_kick_controller.gd
git commit -m @'
refactor(phase2): convert simple_ai to a Brain component

extends CharacterBody3D -> extends Brain; self->_body; motor calls -> _drive/_stop.
Factory auto-attaches it as a child; free-kick wall bodies convert via add_child
instead of set_script. teammate_ai/keeper_ai remain legacy (bridged by _ai_of).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
'@
```

---

## Task 3: Convert `teammate_ai.gd` to a Brain component

`teammate_ai` drives both the AI teammate and the human's `PlayerHome` body (self-gated on `controlled_player == self`). Converting it makes both those bodies component-brained. The critical edit is `controlled_player == self` → `controlled_player == _body` (comparing the injected body reference to the manager's controlled body). The free-kick mate branch of `_convert_bodies` switches to a Brain child.

**Files:**
- Modify: `scripts/ai/teammate_ai.gd`
- Modify: `scripts/match/free_kick_controller.gd:512-523` (mate branch of `_convert_bodies`)

**Interfaces:**
- Consumes: `Brain._body`, `Brain._drive()`, `Brain._stop()`.
- Produces: `teammate_ai` (a `Brain`) with unchanged public surface: `@export var ball`, `@export var speed`, `@export var controlled_player`, `@export var teammate_home_goal`, `func begin_receiving(pass_dir, lead)`, `func end_receiving()`, `func begin_give_and_go(receiver_pos)`, `enum Role`.

- [ ] **Step 1: Convert `teammate_ai.gd` — header, remove `_motor()`**

Line 1: `extends CharacterBody3D` → `extends Brain`.

Remove `_motor()` (lines 40-41):
```gdscript
func _motor() -> PlayerMotor:
	return PlayerMotor.find_on(self)
```

- [ ] **Step 2: Convert `teammate_ai.gd` — `self`→`_body`, motor→`_drive`/`_stop`, groups→`_body`**

| Line(s) | Old | New |
|---|---|---|
| 34 | `add_to_group("giving_run")` | `_body.add_to_group("giving_run")` |
| 37 | `receiver_pos.x >= global_position.x` | `receiver_pos.x >= _body.global_position.x` |
| 61 | `if is_in_group("fallen"):` | `if _body.is_in_group("fallen"):` |
| 64 | `if is_in_group("giving_run"):` | `if _body.is_in_group("giving_run"):` |
| 66 | `ball.dribbler == self` | `ball.dribbler == _body` |
| 68 | `remove_from_group("giving_run")` | `_body.remove_from_group("giving_run")` |
| 72, 76 | bare `global_position` | `_body.global_position` |
| 78-81 | `var m := _motor()` / `if m != null:` / `m.set_move_intent(dir.normalized(), FootballConstants.LOCO_SPRINT_SPEED / FootballConstants.LOCO_TOP_SPEED)` | `_drive(dir.normalized(), FootballConstants.LOCO_SPRINT_SPEED / FootballConstants.LOCO_TOP_SPEED)` |
| 85 | `if controlled_player == self:` | `if controlled_player == _body:` |
| 105 | `carrier.global_position` stays; note line 105 uses `controlled_player` as fallback carrier — unchanged | — |
| 112, 114 | bare `global_position` | `_body.global_position` |
| 123, 125, 127, 128 | bare `global_position` (123, 127, 128); `PassSystem.receive_point(global_position, …)` (125) | `_body.global_position` |
| 135, 136, 138 | bare `global_position` | `_body.global_position` |
| 143-149 (`_move_or_wander`) | `var m := _motor()` / `if m != null:` / `m.set_move_intent(dir, _base_scale())` / `else:` `_wander(delta)` | `if dir.length() > 0.1:` `_drive(dir, _base_scale())` `else:` `_wander(delta)` |
| 157-162 (`_wander`) | `global_position.z`/`.x`; `var m := _motor()` / `if m != null:` / `m.set_move_intent(wander_dir, _base_scale() * 0.3)` | `_body.global_position.z`/`.x`; `_drive(wander_dir, _base_scale() * 0.3)` |

Note line 106 `var carrier_pos := carrier.global_position` — `carrier` is `ball.dribbler` or `controlled_player` (both external bodies), so **not** rewritten.

Verification grep (must print nothing):
```powershell
Select-String -Path "$REPO\scripts\ai\teammate_ai.gd" -Pattern '(?<![\._a-zA-Z])global_position' | Where-Object { $_.Line -notmatch '_body\.|ball\.|carrier\.|carrier_pos|receiver_pos' }
Select-String -Path "$REPO\scripts\ai\teammate_ai.gd" -Pattern '(?<![\.\w])self\b'
Select-String -Path "$REPO\scripts\ai\teammate_ai.gd" -Pattern '_motor\(\)|is_in_group\(|add_to_group\(|remove_from_group\(' | Where-Object { $_.Line -notmatch '_body\.' }
```

- [ ] **Step 3: Convert the mate branch of `free_kick_controller._convert_bodies`**

Replace lines 520-523:

Old:
```gdscript
		mb.set_script(mate_script)
		mb.set_physics_process(true)
		mb.ball = _ball
		mb.controlled_player = _manager.controlled_player
```
New:
```gdscript
		var mbrain := mate_script.new()      # teammate_ai теперь Brain-компонент
		mbrain.name = "Brain"
		mb.add_child(mbrain)
		mbrain.ball = _ball
		mbrain.controlled_player = _manager.controlled_player
```

- [ ] **Step 4: Run the regression grid**

Expected all green. Key gates: `check_free_kick_flow` (mate bodies become live `teammate_ai` brains), `check_penalty_flow`.

- [ ] **Step 5: Playtest smoke (teammate + control switch + passes)**

Run the game. Temporarily ensure the teammate spawns (`FootballConstants.DEBUG_DISABLE_TEAMMATE` should be `false`). Confirm: the AI teammate positions for passes / chases; passing to the teammate hands control over and the receive-assist run works; switching control (`Q`/`LB` while not possessing) leaves the ex-controlled `PlayerHome` acting as AI again. This is the behavior the `controlled_player == _body` edit protects.

- [ ] **Step 6: Commit**

```powershell
git add scripts/ai/teammate_ai.gd scripts/match/free_kick_controller.gd
git commit -m @'
refactor(phase2): convert teammate_ai to a Brain component

extends Brain; self->_body; controlled_player==self -> ==_body; motor -> _drive/_stop;
group calls via _body. Free-kick mate bodies convert via add_child. Keeper still legacy.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
'@
```

---

## Task 4: Convert `keeper_ai.gd` to a Brain component (riskiest)

The keeper becomes `extends Brain`. Its own transform/`move_and_collide`/`get_children`/catch calls all go through `_body`. Because the keeper is used both as a **body** (freeze keep-active, `n == _keeper` exclusions, ball-contact identity) and as an **API surface** (`goal_line_z`, `set_penalty_mode`, `begin_penalty_dive`, `set_freekick_anchor`, `on_ball_contact`, `_state`), we keep `_keeper` = the **body** and add `_keeper_brain = _keeper.brain()` for the API/state. This is the only task that touches `penalty_controller`, `free_kick_controller` keeper API, and `check_keeper_clear`.

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (extends + `self`→`_body` throughout)
- Modify: `scripts/match/match_manager.gd` (`_keeper_brain`; `_setup_keeper`; 3 keeper-API sites)
- Modify: `scripts/match/penalty_controller.gd` (`_keeper_brain` for API; keep `_keeper` body for exclusion)
- Modify: `scripts/match/free_kick_controller.gd` (`_keeper_brain` for API; keep `_keeper` body for exclusion)
- Modify: `tests/check_keeper_clear.gd` (read `_state` via `keeper.brain()`)

**Interfaces:**
- Consumes: `Brain._body` (Task 1), `Player.brain()` (Task 1).
- Produces: `keeper_ai` (a `Brain`) with unchanged public surface: `var goal_line_z`, `var save_area`, `var hold_point`, `var manager`, `func set_penalty_mode(on)`, `func begin_penalty_dive(zone)`, `func set_freekick_anchor(pos)`, `func clear_freekick_anchor()`, `func on_ball_contact()`, `var _state`.
- Produces: `MatchManager._keeper_brain: Node` (the keeper's Brain; `_keeper` stays the body).

- [ ] **Step 1: Convert `keeper_ai.gd` — header + helpers**

Line 1: `extends CharacterBody3D` → `extends Brain`.

`_motor()` (line 44): `return PlayerMotor.find_on(self)` → `return PlayerMotor.find_on(_body)`.

`_visual()` (line 48): `for c in get_children():` → `for c in _body.get_children():`.

- [ ] **Step 2: Convert `keeper_ai.gd` — every bare body reference to `_body.`**

Rule: prefix bare `global_position`, `global_transform`, `move_and_collide`, and replace `self` in `ball.catch(self, …)` / `ball.set_dribbler(self, …)` / `ball.dribbler == self` with `_body`. Do **not** touch `ball.global_position`, `dec.target`, `target.` etc. Exact sites (from grep):

- `self` → `_body`: lines **92** (`ball.dribbler == self`), **143** (`ball.catch(self, hold_point)`), **253** (`ball.dribbler == self`), **280** (`ball.dribbler == self`), **340** (`ball.catch(self, hold_point)`), **402** (`ball.dribbler == self`), **430** (`ball.catch(self, hold_point)`), **474** (`ball.catch(self, hold_point)`), **548** (`ball.dribbler == self`), **604** (`ball.set_dribbler(self, true)`), **638** (`ball.dribbler != self`), **684** (`ball.dribbler == self`), **714** (`ball.dribbler != self`), **740** (`ball.dribbler == self`), **761** (`ball.dribbler == self`), **849** (`ball.dribbler == self`).
- bare `global_position` → `_body.global_position`: lines **64**, **141** (only the `kpr=`, `y=` bare `global_position` — NOT `ball.global_position`), **152** (`… - global_position.x`), **156**, **174**? (no — line 174 is `ball.global_position.z`; skip), **185** (`ball.global_position.distance_to(global_position)` → the *argument* `global_position`), **187** (the `dx=`, `kpr_x=` bare `global_position`), **200**, **225**, **227**, **255** (`global_position = Vector3(...)`), **284** (`global_position = Vector3(...)`), **330** (`… - global_position.x`), **331** (`Vector3(-global_position.x, …)`), **365** (`dec.target - global_position`), **382** (`target - global_position`), **396** (`global_position.y = _ground_y`), **464** (both `global_position.x` and `global_position.z` args), **628** (`_carry_start = global_position`), **641** (`global_position.distance_to(_carry_start)`), **845** (`… - global_position.x`).
- bare `global_transform` → `_body.global_transform`: line **778** (`var right := global_transform.basis.x`).
- `move_and_collide(...)` → `_body.move_and_collide(...)`: line **393**.

(Lines 135, 179, 186, 201, 411, 420, 426, 476, 652, 745, 746, 855 reference only `ball.global_position` / `dec.target` — leave unchanged.)

Verification grep (must print nothing — every remaining hit is `ball.`/`dec.`/`target.`/`_body.`-qualified):
```powershell
Select-String -Path "$REPO\scripts\ai\keeper_ai.gd" -Pattern '(?<![\._a-zA-Z])global_position' | Where-Object { $_.Line -notmatch '_body\.|ball\.' }
Select-String -Path "$REPO\scripts\ai\keeper_ai.gd" -Pattern '(?<![\._a-zA-Z])global_transform' | Where-Object { $_.Line -notmatch '_body\.' }
Select-String -Path "$REPO\scripts\ai\keeper_ai.gd" -Pattern '(?<![\._a-zA-Z])move_and_collide' | Where-Object { $_.Line -notmatch '_body\.' }
Select-String -Path "$REPO\scripts\ai\keeper_ai.gd" -Pattern '(?<![\.\w])self\b'
Select-String -Path "$REPO\scripts\ai\keeper_ai.gd" -Pattern 'get_children\(\)' | Where-Object { $_.Line -notmatch '_body\.' }
```

- [ ] **Step 3: Run the keeper unit tests (isolate the conversion before wiring the manager)**

```powershell
& $GODOT --path $REPO --headless -s "res://tests/check_keeper_logic.gd"   # pure fns — must PASS
& $GODOT --path $REPO --headless --quit-after 2 res://scenes/match.tscn   # must still load (keeper spawns)
```
`check_keeper_clear` will still read `_keeper._state` via the *manager* path — it's fixed in Step 6; don't gate on it yet. But the match scene must load: the factory now attaches the keeper brain as a child, and `_setup_keeper` still sets `k.goal_line_z` etc. on the **body** — which no longer has those fields. **Expect the match-scene load to surface keeper field errors until Step 4.** Proceed to Step 4 before re-judging.

- [ ] **Step 4: Manager — `_keeper_brain`, `_setup_keeper` field injection, keeper-API sites**

In `scripts/match/match_manager.gd`:

Add the field near `_keeper` (line 42):
```gdscript
var _keeper: CharacterBody3D
var _keeper_brain: Node
```

In `_setup_keeper` (lines 701, 717-722), set the brain fields on the brain (the body add_child stays):
```gdscript
	var k := PlayerFactory.spawn(cfg, _team_away)
	var kb := k.brain()                        # keeper теперь Brain-компонент
	# --- keeper-специфичные узлы (не входят в общий player.tscn) — на ТЕЛО (transform) ---
	var save_area := Area3D.new()
	# … (unchanged: build save_area, k.add_child(save_area); hold_point, k.add_child(hold_point)) …
	# keeper-поля (ball уже проставлен фабрикой) — на МОЗГ
	kb.goal_line_z = goal_line_z
	kb.save_area = save_area
	kb.hold_point = hold_point
	kb.manager = self
	_keeper = k
	_keeper_brain = kb
```

Reroute the 3 keeper-API/state sites:
- Line 864: `_penalty.start_single(controlled_player, _keeper.goal_line_z)` → `_keeper_brain.goal_line_z`.
- Line 872: `_free_kick.start(controlled_player, _keeper.goal_line_z)` → `_keeper_brain.goal_line_z`.
- Lines 2188-2190 (ball contact): keep `body == _keeper` (body identity), but call the method on the brain:
```gdscript
	if body == _keeper and _keeper_brain != null and _keeper_brain.has_method(&"on_ball_contact"):
		# … (unchanged surrounding lines) …
		_keeper_brain.on_ball_contact()
```

Leave `_set_ai_frozen(true, _keeper)` / `_set_ai_frozen(not on, _keeper)` / `_set_ai_frozen(false, _keeper)` and `p == _keeper` (line 1035) as-is — they compare the **body**, which is correct. `_set_ai_frozen`'s keep-active check is body-level (`n == keep_active`); the keeper brain's physics process is what `_ai_of(n)` would toggle for *other* bodies, but the keeper is excluded entirely, so its brain keeps running (as required for the goal-celebration dive-out). ✓

- [ ] **Step 5: Controllers — `_keeper_brain` for API, keep `_keeper` body for exclusions**

`scripts/match/penalty_controller.gd`:
- Add field after `var _keeper: CharacterBody3D` (line 15): `var _keeper_brain: Node`.
- In `setup` (line 43, `_keeper = keeper`), add: `_keeper_brain = keeper.brain() if keeper != null and keeper.has_method(&"brain") else null`.
- Line 88-89: `if _keeper != null and _keeper.has_method(&"set_penalty_mode"):` / `_keeper.set_penalty_mode(true)` → guard/call on `_keeper_brain`:
```gdscript
	if _keeper_brain != null and _keeper_brain.has_method(&"set_penalty_mode"):
		_keeper_brain.set_penalty_mode(true)
```
- Line 222-223: `_keeper.has_method(&"begin_penalty_dive")` / `_keeper.begin_penalty_dive(_struck_zone)` → `_keeper_brain`.
- Leave `n == _keeper` (line 111) as-is (body exclusion).

`scripts/match/free_kick_controller.gd`:
- Add field after `var _keeper: CharacterBody3D` (line 14): `var _keeper_brain: Node`.
- In `setup` (line 50, `_keeper = keeper`), add: `_keeper_brain = keeper.brain() if keeper != null and keeper.has_method(&"brain") else null`.
- Lines 104-108: `_keeper.has_method(&"set_freekick_anchor")` / `_keeper.set_freekick_anchor(kpos)` → `_keeper_brain`.
- Lines 334-335: `_keeper.has_method(&"clear_freekick_anchor")` / `_keeper.clear_freekick_anchor()` → `_keeper_brain`.
- Leave `n == _keeper` (lines 381, 410) as-is (body exclusions).

- [ ] **Step 6: Fix `tests/check_keeper_clear.gd` — read `_state` via the brain**

The test currently does `var keeper = _match_root.get(&"_keeper")` (now the body) then `keeper.get(&"_state")` (state is on the brain) and `ball.dribbler == keeper` (dribbler is the **body**, so this stays correct). Update the two `_state` reads to go through the brain:

Replace both occurrences of:
```gdscript
		var keeper = _match_root.get(&"_keeper")   # …
		var kst = keeper.get(&"_state") if keeper != null else -1
```
with:
```gdscript
		var kbrain = _match_root.get(&"_keeper_brain")   # состояние теперь на дочернем Brain
		var kst = kbrain.get(&"_state") if kbrain != null else -1
```
Leave the final failure check `if ball.is_caught() or ball.dribbler == keeper:` referencing `keeper` (the body) — but note `keeper` is no longer defined in that scope after the edit. Change that line to use the body explicitly:
```gdscript
			var keeper_body = _match_root.get(&"_keeper")
			if ball.is_caught() or ball.dribbler == keeper_body:
```
(so the "still held" guard compares the ball's dribbler to the keeper **body**, which is what `ball.set_dribbler(_body, …)` now sets).

- [ ] **Step 7: Run the full regression grid (keeper focus)**

All green. Run `check_keeper_clear` 3× (flaky) — require majority PASS. Match-scene load (command 2) must be clean of NEW error categories (the keeper field errors from Step 3 are now gone).

- [ ] **Step 8: Playtest (keeper — mandatory)**

Run the game (keeper debug scaffolding is on: 1v1, third-person camera, `[KEEPER]` prints). Confirm 1:1 behavior: holds the line, central catch (scoop/catch/head/top), dives to corners, tips over the bar, catches → holds → overhand-throw distributes, retreats-then-resumes, and does NOT concede its own throw. Press **P** (penalty) and the free-kick key: keeper enters penalty/free-kick sub-modes correctly (this proves the controller `_keeper_brain` rerouting).

- [ ] **Step 9: Commit**

```powershell
git add scripts/ai/keeper_ai.gd scripts/match/match_manager.gd scripts/match/penalty_controller.gd scripts/match/free_kick_controller.gd tests/check_keeper_clear.gd
git commit -m @'
refactor(phase2): convert keeper_ai to a Brain component

extends Brain; self/global_position/global_transform/move_and_collide/get_children ->
_body throughout. Manager keeps _keeper=body (freeze keep-active, n==_keeper exclusions,
ball-contact identity) and adds _keeper_brain=k.brain() for the API/state (goal_line_z,
on_ball_contact, set_penalty_mode, begin_penalty_dive, set_freekick_anchor). Controllers
route keeper API through _keeper_brain; body exclusions unchanged. check_keeper_clear reads
_state via _keeper_brain, dribbler-held guard compares the keeper body.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
'@
```

---

## Task 5: Cleanup + docs

Remove the now-dead legacy `set_script` branch in the factory (no AI is `extends CharacterBody3D` anymore), and document the component-brain architecture.

**Files:**
- Modify: `scripts/match/player_factory.gd` (drop the legacy branch — optional but DRY/YAGNI)
- Modify: `CLAUDE.md`, `AGENTS.md`

- [ ] **Step 1: Simplify the factory brain block (legacy branch now dead)**

All three AIs are Brains, so `inst is Brain` is always true. Replace the Task-1 brain block with the component-only form:

```gdscript
	# мозг (Фаза 2): все ИИ — Brain-компоненты (дочерний узел), никакого set_script на корне.
	var ai_target: Object = body
	if config.control_mode == PlayerConfig.ControlMode.AI and config.ai_script != null:
		var brain: Node = config.ai_script.new()
		brain.name = "Brain"
		body.add_child(brain)              # Brain._ready кэширует _body = get_parent()
		ai_target = brain
	if team.ball != null:
		ai_target.set(&"ball", team.ball)
	for k in config.extra_fields:
		ai_target.set(k, config.extra_fields[k])
	return body
```
(If a future non-Brain script must be supported, restore the auto-detect; YAGNI for now. `_ai_of`'s body fallback stays — it still serves `ai_script = null` / future HUMAN bodies.)

- [ ] **Step 2: Run the regression grid**

All green (this is a no-op behaviorally — every AI already took the component path).

- [ ] **Step 3: Update `CLAUDE.md`**

Under *Presentation layer & asset pipeline* / *Player spawn factory & roster*, revise the "Scripts attached at runtime" and factory description to state: AI is now a **child `Brain` component** (`scripts/ai/brain.gd`, `class_name Brain extends Node`) on a stable `Player` root (`scripts/player/player.gd`, `class_name Player extends CharacterBody3D`), attached by `PlayerFactory` via `add_child` (no more `set_script` on the body). Note: `MatchManager._ai_of(body)` resolves a body to its brain (or itself); `_keeper` is the keeper **body**, `_keeper_brain` its Brain (API/state). Field brains push intent via `Brain._drive()`; per-frame drive still lives inside each brain (the `movement_intent()`/`speed_scale()` getters are the Phase-3 seam, not yet the drive path). Add `check_player_brain.gd` to the headless-check list. Mark Phase 2 done; Phase 3 (HumanBrain + ActionExecutor) still gated.

- [ ] **Step 4: Update `AGENTS.md`**

Mirror the one-paragraph summary: component brains, `Player` root, `_ai_of`/`_keeper_brain`, factory `add_child` attach.

- [ ] **Step 5: Commit**

```powershell
git add scripts/match/player_factory.gd CLAUDE.md AGENTS.md
git commit -m @'
refactor(phase2): drop dead legacy set_script branch; document component brains

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
'@
```

---

## Self-Review

**Spec coverage (Phase 2 section of the design):**
- "stable `player.gd` root with identity fields" → Task 1 Step 2 (`Player` with `team_group`/`role`/`brain()`). Identity-field *migration* of the 46 group reads is explicitly out of scope for Phase 2 (groups stay the physics index; the design keeps them) — the fields exist as the seam, unused reads are not forced. ✓
- "Brain interface (`think`/`movement_intent`/`speed_scale`)" → realized as `movement_intent()`/`speed_scale()` getters + `_drive()`; `think()` is **not** introduced because the lower-risk faithful realization keeps each brain's own `_physics_process` driving the motor (documented deviation in Architecture + Task 5 Step 3). The design's "body loop asks brain for intent" is deferred to Phase 3 (3b), where HumanBrain forces the symmetric contract. ✓ (deviation documented)
- "convert simple_ai/teammate_ai/keeper_ai to child brains reading `_body`" → Tasks 2, 3, 4. ✓
- "control_mode AI=active brain / HUMAN=manager drives" → In Phase 2 the human body keeps its (self-gating) `teammate_ai` brain exactly as today; the "HUMAN = no brain" end-state is Phase 3. This preserves the PlayerHome-acts-as-AI-when-switched behavior (Task 3 Step 5 guards it). ✓ (matches "temporary scaffold until Phase 3")
- "factory attaches brain instead of set_script" → Task 1 Step 4 (auto-detect), Task 5 Step 1 (component-only). ✓
- "wall→AI conversion becomes add/enable component" → Task 2 Step 3 (wall), Task 3 Step 3 (mate). ✓
- "keeper riskiest; run keeper tests after each step" → Task 4 (isolated unit tests at Step 3 before wiring; grid + 3× flaky + mandatory playtest). ✓
- "test check_player_brain.gd" → Task 1 Step 6. ✓
- "all prior tests stay green (esp. keeper set + check_free_kick_flow)" → regression grid every task; `check_free_kick_flow` is the explicit gate for the `_convert_bodies` changes. ✓

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N". Keeper conversion uses an explicit line-by-line checklist + verification greps rather than a 857-line paste (mechanical rename; a paste would be less reviewable and error-prone) — this is concrete, not vague. ✓

**Type consistency:** `_ai_of() -> Node`; `Player.brain() -> Node`; `Brain._body: CharacterBody3D`; `Brain.body()/movement_intent()/speed_scale()/set_active()/_drive()/_stop()` used consistently in Tasks 1-3 and the test. `_keeper: CharacterBody3D` (body) vs `_keeper_brain: Node` (brain) used consistently across manager + both controllers + `check_keeper_clear` (Task 4). Factory `ai_target` naming consistent Task 1 ↔ Task 5. Field brains' public surfaces (`speed`, `wants_to_tackle`, `begin_intercept`, `controlled_player`, `begin_receiving`, `begin_give_and_go`) are preserved (only `extends`/`self` change), so the manager's `_ai_of(...)` calls resolve. ✓

**Risk note:** The one place a bare-token grep could mislead is the keeper's `ball.global_position` vs bare `global_position` — the Task 4 checklist enumerates the exact lines and the verification grep excludes `ball.`/`_body.`, so a missed site fails the grep gate before runtime. ✓

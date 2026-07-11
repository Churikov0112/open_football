# Фаза 1: три удара ногой + прицел в ворота + вынос + кручёный — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Превратить плейсхолдерный удар (по facing, фикс-сила) в три настоящих типа удара ногой — прямой (bullet), кручёный (Magnus), черпачок (chip) — с гибридным прицелом в ворота, промахами и контекстным выносом.

**Architecture:** Новый `scripts/match/shot_system.gd` (`class_name ShotSystem extends Object`) — чистые статик-функции (как `PassSystem`), не читают `FootballConstants`, headless-тестируемы. `match_manager.gd` расширяет `ChargeAction` и диспатчит удары через commit-action (импульс по `action_contact`, через `ball.launch()`/`ball.launch_curl()` — Magnus-физика и API готовы в Фазе 0). Прицел считается в момент выстрела с seed-able RNG (`_pass_rng`).

**Tech Stack:** Godot 4.7 / GDScript. Тесты — headless `SceneTree` (`tests/check_shot_system_math.gd`), плюс две команды валидации.

## Global Constraints

- Godot 4.7 / GDScript. Windows-only.
- **InputMap правится только в `match_manager.gd:_setup_inputs()`** (словарь действий), никогда в `project.godot`.
- **Наша команда (team_1) атакует −Z** — целевые (чужие) ворота: центр `Vector3(0, 0, -field_length)`, полуширина `FootballConstants.GOAL_WIDTH/2 = 3.66`, высота `FootballConstants.GOAL_HEIGHT = 2.44` (`field_length` = поле match_manager = 52.5).
- **Удар идёт через commit-action** (как пас): вычисляем ВЕКТОР скорости, кладём в `_pending_launch` (+ `_pending_curl` для кручёного), ставим `_action_power = -1.0` (сентинел launch), импульс — по сигналу `PlayerVisual.action_contact` в `_on_action_contact`. НЕ `ball.kick(dir,power)` — тот остаётся для фолбэка/подката.
- **`ShotSystem` не читает `FootballConstants`** — все тюнинги параметрами (как `PassSystem`). Тест сидит RNG.
- Команды валидации (обе):
  - `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
  - `& "...console.exe" --path "..." --headless --quit-after 2 res://scenes/match.tscn`
- Baseline ошибок 2-й команды (диффать, не ждать нуля): ~37× `!is_inside_tree()`, ~14× transition-duplicate, ~7× `states.has`, ~1× `WorldEnvironmentND` (счётчики выросли из-за 4 болванок-стенки; см. Фазу 0). Headless-check: `... --headless -s "res://tests/<name>.gd"` → `CHECK PASS`/`FAIL`, exit 0/1.
- **Ощущение удара (сила/дуга/промахи/кручение) headless НЕ ловит** — после Задач 4/5/6/7 обязателен ручной прогон пользователем (стенки/стоящий соперник уже на поле — `DEBUG_DISABLE_OPPONENT`).
- Вратаря нет — прицел в случайную точку створа (заглушка), удары могут мазать. Коммитить часто.

## Зависимости от Фазы 0 (уже готово)

- `ball.launch(velocity)` — импульс готовой скоростью; `ball.launch_curl(velocity, curl)` — то же + Magnus-вектор `_curl` (`_curl.z` = боковая через `left=vel×UP`, `_curl.y` = подъём). `ball.kick(dir,power)` обнуляет `_curl`.
- Magnus в `_integrate_forces` (пока `state==FLIGHT`, `_curl!=0`), затухание `MAGNUS_DECAY`, масштаб `MAGNUS_FORCE`.
- Коллизия мяча с игроками только в полёте → блок стенкой уже работает.
- `_ball_gravity()` в match_manager — реальная гравитация мяча (для баллистики).
- Commit-action: `_action_player`/`_action_power`/`_kick_action_active`/`_pending_launch`, `_on_action_contact` с behind-ball-guard.

## File Structure

- **Create:** `scripts/match/shot_system.gd` — чистые функции прицела/баллистики/кручения/выноса.
- **Create:** `tests/check_shot_system_math.gd` — headless-тест этих функций.
- **Modify:** `scripts/match/match_manager.gd` — `combo_curl` в `_setup_inputs`; `ChargeAction` += `SHOT_CURL/SHOT_CHIP/CLEARANCE`; ввод (E+D/Q+D, контекст удар/вынос); `_fire_charge` диспатч; `_pending_curl` в commit-action.
- **Modify:** `scripts/data/football_constants.gd` — секция SHOOTING (сила/прицел/разброс/кручёный/черпачок/вынос).
- **Reuse:** `PassSystem.launch_lob` (черпачок) — не дублируем баллистику навеса.

---

## Task 1: `ShotSystem` — чистые функции + headless-тест

Ядро Фазы 1: вся математика удара как тестируемые статик-функции. Ничего не рендерит, детерминированно при seeded RNG.

**Files:**
- Create: `scripts/match/shot_system.gd`
- Create: `tests/check_shot_system_math.gd`

**Interfaces:**
- Produces (все `static`, `class_name ShotSystem extends Object`):
  - `wants_clearance(shooter_pos: Vector3, goal_center: Vector3, facing: Vector3, clearance_dist: float, facing_dot_min: float) -> bool`
  - `goal_aim_point(goal_center: Vector3, half_width: float, height: float, side_bias: float, charge_ratio: float, over_lift: float, scatter_m: float, rng: RandomNumberGenerator) -> Vector3`
  - `ballistic_to(from: Vector3, to: Vector3, horizontal_speed: float, gravity: float) -> Vector3`
  - `curl_side(shooter_pos: Vector3, goal_center: Vector3, facing: Vector3) -> float`
  - `curl_vector(side: float, curl_strength: float, lift: float) -> Vector3`
  - `clearance_velocity(aim_dir: Vector3, power: float, lift: float) -> Vector3`
  - `scatter_meters(base_m: float, charge_ratio: float, distance: float, dist_ref: float) -> float`

- [ ] **Step 1: Написать `shot_system.gd`**

```gdscript
class_name ShotSystem
extends Object

## Контекст «удар vs вынос»: далеко от чужих ворот ИЛИ повёрнут не к ним → вынос.
static func wants_clearance(shooter_pos: Vector3, goal_center: Vector3, facing: Vector3,
		clearance_dist: float, facing_dot_min: float) -> bool:
	var to_goal := goal_center - shooter_pos
	to_goal.y = 0.0
	var dist := to_goal.length()
	if dist > clearance_dist:
		return true
	if dist < 0.001:
		return false
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length() < 0.001:
		return false
	return f.normalized().dot(to_goal.normalized()) < facing_dot_min

## Точка прицела в створе. side_bias/charge задают угол/высоту, потом разброс scatter_m (RNG).
## Заряд поднимает точку (сильный удар выше — риск через перекладину на over_lift метров).
static func goal_aim_point(goal_center: Vector3, half_width: float, height: float,
		side_bias: float, charge_ratio: float, over_lift: float, scatter_m: float,
		rng: RandomNumberGenerator) -> Vector3:
	var cr := clampf(charge_ratio, 0.0, 1.0)
	var x := goal_center.x + clampf(side_bias, -1.0, 1.0) * half_width
	var y := lerpf(0.25, height + over_lift, cr)
	x += rng.randf_range(-scatter_m, scatter_m)
	y += rng.randf_range(-scatter_m * 0.6, scatter_m * 0.6)
	return Vector3(x, maxf(y, 0.05), goal_center.z)

## Баллистическая стартовая скорость: горизонталь = horizontal_speed, попадает в точку to
## (по высоте — через компенсацию гравитации за время полёта). Общая для bullet и curl.
static func ballistic_to(from: Vector3, to: Vector3, horizontal_speed: float, gravity: float) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := flat.length()
	if dist < 0.001:
		return Vector3.ZERO
	var hs := maxf(horizontal_speed, 0.001)
	var t := dist / hs
	var vy := (to.y - from.y) / t + 0.5 * gravity * t
	return flat.normalized() * hs + Vector3.UP * vy

## Знак кручения: в какую сторону от прямой «на центр ворот» смотрит игрок — в тот угол крутим.
## +1 / -1 (знак подбирается тюнингом живьём — см. ручную приёмку).
static func curl_side(shooter_pos: Vector3, goal_center: Vector3, facing: Vector3) -> float:
	var straight := goal_center - shooter_pos
	straight.y = 0.0
	var f := Vector3(facing.x, 0.0, facing.z)
	if straight.length() < 0.001 or f.length() < 0.001:
		return 1.0
	var cross := straight.normalized().cross(f.normalized()).y
	return 1.0 if cross >= 0.0 else -1.0

## Вектор _curl для ball.launch_curl: .z — боковая составляющая (через left=vel×UP),
## .y — подъём (дуга). .x не используется движком.
static func curl_vector(side: float, curl_strength: float, lift: float) -> Vector3:
	return Vector3(0.0, lift, side * curl_strength)

## Вынос: мощно по направлению aim_dir (facing/стик) вдаль, с подъёмом lift.
static func clearance_velocity(aim_dir: Vector3, power: float, lift: float) -> Vector3:
	var d := Vector3(aim_dir.x, 0.0, aim_dir.z)
	if d.length() < 0.001:
		return Vector3.ZERO
	return d.normalized() * power + Vector3.UP * lift

## Разброс прицела (м): растёт с зарядом и дистанцией. На максимуме заряда — «велик риск промаха».
static func scatter_meters(base_m: float, charge_ratio: float, distance: float, dist_ref: float) -> float:
	var cr := clampf(charge_ratio, 0.0, 1.0)
	var dist_factor := clampf(distance / maxf(dist_ref, 0.001), 0.5, 1.5)
	return base_m * (0.5 + cr) * dist_factor
```

- [ ] **Step 2: Написать `tests/check_shot_system_math.gd`**

```gdscript
extends SceneTree

# Headless-проверка чистых функций ShotSystem (детерминизм через seeded RNG).

func _initialize() -> void:
	var ok := true
	var g := 20.0  # тестовая гравитация

	# wants_clearance: близко и лицом к воротам → НЕ вынос.
	ok = _expect(not ShotSystem.wants_clearance(Vector3(0,0,0), Vector3(0,0,-20), Vector3(0,0,-1), 30.0, 0.3), "близко+лицом → удар") and ok
	# далеко → вынос.
	ok = _expect(ShotSystem.wants_clearance(Vector3(0,0,0), Vector3(0,0,-40), Vector3(0,0,-1), 30.0, 0.3), "далеко → вынос") and ok
	# спиной к воротам → вынос.
	ok = _expect(ShotSystem.wants_clearance(Vector3(0,0,0), Vector3(0,0,-10), Vector3(0,0,1), 30.0, 0.3), "спиной → вынос") and ok

	# goal_aim_point: side_bias +1 → x у правой штанги; заряд выше → y выше. RNG сидирован.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var pr := ShotSystem.goal_aim_point(Vector3(0,0,-52.5), 3.66, 2.44, 1.0, 0.2, 0.0, 0.0, rng)
	ok = _expect(pr.x > 3.0 and pr.z == -52.5, "side_bias +1 → правый угол створа") and ok
	var pl := ShotSystem.goal_aim_point(Vector3(0,0,-52.5), 3.66, 2.44, -1.0, 0.2, 0.0, 0.0, rng)
	ok = _expect(pl.x < -3.0, "side_bias -1 → левый угол") and ok
	var low := ShotSystem.goal_aim_point(Vector3(0,0,-52.5), 3.66, 2.44, 0.0, 0.0, 0.0, 0.0, rng)
	var high := ShotSystem.goal_aim_point(Vector3(0,0,-52.5), 3.66, 2.44, 0.0, 1.0, 0.0, 0.0, rng)
	ok = _expect(high.y > low.y, "больше заряд → выше точка") and ok

	# ballistic_to: с возвращённой скоростью мяч в точке to в момент t (по геометрии).
	var from := Vector3(0, 0.11, 0)
	var to := Vector3(0, 1.2, -20)
	var v := ShotSystem.ballistic_to(from, to, 18.0, g)
	var flat := Vector3(v.x, 0, v.z)
	var t := 20.0 / 18.0
	var y_at_t := from.y + v.y * t - 0.5 * g * t * t
	ok = _expect(absf(y_at_t - to.y) < 0.05, "ballistic_to попадает по высоте в момент t") and ok
	ok = _expect(absf(flat.length() - 18.0) < 0.01, "горизонтальная скорость == заданной") and ok

	# curl_vector: .z = side*strength, .y = lift.
	var cv := ShotSystem.curl_vector(-1.0, 5.0, 2.0)
	ok = _expect(absf(cv.z + 5.0) < 0.001 and absf(cv.y - 2.0) < 0.001, "curl_vector раскладка") and ok

	# clearance_velocity: направление + подъём.
	var clv := ShotSystem.clearance_velocity(Vector3(1,0,0), 20.0, 5.0)
	ok = _expect(absf(clv.x - 20.0) < 0.01 and absf(clv.y - 5.0) < 0.01, "clearance по X + подъём") and ok

	# scatter_meters: растёт с зарядом.
	ok = _expect(ShotSystem.scatter_meters(1.0, 1.0, 20.0, 20.0) > ShotSystem.scatter_meters(1.0, 0.0, 20.0, 20.0), "разброс растёт с зарядом") and ok

	if ok:
		print("CHECK PASS"); quit(0)
	else:
		print("CHECK FAIL"); quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond
```

- [ ] **Step 3: Запустить тест — убедиться, что проходит**

Run: `& "...console.exe" --path "..." --headless -s "res://tests/check_shot_system_math.gd"`
Expected: `CHECK PASS`. (Если `curl_side` знак не тестируем строго — он тюнится живьём; тест его раскладку не проверяет, только `curl_vector`.)

- [ ] **Step 4: Регресс — обе команды валидации**

Expected: 1-я без ошибок; 2-я = baseline (новый `class_name ShotSystem` парсится глобально обеими).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/shot_system.gd tests/check_shot_system_math.gd
git commit -m "feat(shot): ShotSystem pure functions (aim/ballistic/curl/clearance) + headless test"
```

---

## Task 2: Ввод — combo-модификатор `E`/`RB` для кручёного

**Files:**
- Modify: `scripts/match/match_manager.gd:_setup_inputs()` (словарь действий, ~137–141)

**Interfaces:**
- Produces: действие `&"combo_curl"` (клавиша `E`, кнопка `JOY_BUTTON_RIGHT_SHOULDER`).

- [ ] **Step 1: Добавить действие в словарь `_setup_inputs`**

После строки `&"combo_modifier": {...}` добавить:

```gdscript
		&"combo_curl":      {"keys": [KEY_E],     "buttons": [JOY_BUTTON_RIGHT_SHOULDER], "axes": []},
```

- [ ] **Step 2: Регресс — 2-я команда валидации**

Expected: baseline (ввод пересоздаётся в `_ready`, парс-ошибок нет).

- [ ] **Step 3: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(shot): add combo_curl (E / RB) input action for the curl shot"
```

---

## Task 3: `ChargeAction` расширение + ввод трёх ударов (контекст удар/вынос)

**Files:**
- Modify: `scripts/match/match_manager.gd` — enum `ChargeAction` (~55); ввод удара в `_handle_player_input` (~838).

**Interfaces:**
- Consumes: `combo_modifier`, `combo_curl`, `_is_near_ball`, `_is_our_dribbler`, `_start_charge`.
- Produces: `ChargeAction` со значениями `SHOT_CURL`, `SHOT_CHIP`, `CLEARANCE`; `_start_charge` вызывается с нужным типом по нажатому combo.

- [ ] **Step 1: Расширить enum**

Заменить строку enum (найти `enum ChargeAction { NONE, SHOT, PASS_SHORT, PASS_THROUGH, PASS_LOB, PASS_WALL, PASS_THROUGH_AIR }`):

```gdscript
enum ChargeAction { NONE, SHOT, SHOT_CURL, SHOT_CHIP, CLEARANCE, PASS_SHORT, PASS_THROUGH, PASS_LOB, PASS_WALL, PASS_THROUGH_AIR }
```

- [ ] **Step 2: Ввод — выбрать тип удара по combo при нажатии `kick`**

В `_handle_player_input`, заменить блок нажатия удара:

```gdscript
	if Input.is_action_just_pressed(&"kick"):
		if _is_charging():
			pass  # already charging, ignore
		elif _is_near_ball(controlled_player) and _is_our_dribbler(controlled_player):
			_start_charge(ChargeAction.SHOT, controlled_player)
		else:
			_try_tackle(controlled_player)
```

на:

```gdscript
	if Input.is_action_just_pressed(&"kick"):
		if _is_charging():
			pass  # already charging, ignore
		elif _is_near_ball(controlled_player) and _is_our_dribbler(controlled_player):
			# E+D → кручёный, Q+D → черпачок, иначе прямой удар (контекст удар/вынос решается в _fire_charge).
			var shot_action := ChargeAction.SHOT
			if Input.is_action_pressed(&"combo_curl"):
				shot_action = ChargeAction.SHOT_CURL
			elif Input.is_action_pressed(&"combo_modifier"):
				shot_action = ChargeAction.SHOT_CHIP
			_start_charge(shot_action, controlled_player)
		else:
			_try_tackle(controlled_player)
```

- [ ] **Step 3: Отпускание `kick` фаером для всех трёх ударов**

Заменить условие релиза удара (`_charge_action == ChargeAction.SHOT`):

```gdscript
	if Input.is_action_just_released(&"kick") and _charge_player == controlled_player \
			and _charge_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]:
		_fire_charge()
```

- [ ] **Step 4: `_process` — макс. время заряда для ударов**

Найти в `_process` строку выбора `max_time` (`KICK_CHARGE_MAX_TIME if _charge_action == ChargeAction.SHOT else ...`) и заменить условие на «любой из ударов»:

```gdscript
		var is_shot: bool = _charge_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]
		var max_time := KICK_CHARGE_MAX_TIME if is_shot else FootballConstants.PASS_CHARGE_MAX_TIME
```

Также в том же месте, где `show_target := _is_charging() and _charge_action != ChargeAction.SHOT ...` (маркер цели паса) — исключить все удары, чтобы жёлтый маркер не показывался на ударах:

```gdscript
	var show_target := _is_charging() and not (_charge_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]) and _charge_player == controlled_player
```

- [ ] **Step 5: Регресс — обе команды**

Expected: baseline. (Пока `_fire_charge` для новых типов падает в SHOT-ветку — поведение как у прямого; заряд/релиз работают.)

- [ ] **Step 6: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(shot): ChargeAction SHOT_CURL/SHOT_CHIP/CLEARANCE + combo-driven shot input"
```

---

## Task 4: Прямой удар (bullet) + вынос — прицел в ворота через commit-launch

Переводим прямой удар с `ball.kick(dir,power)` на `ShotSystem` + `ball.launch(velocity)`. Контекст решает удар/вынос.

**Files:**
- Modify: `scripts/data/football_constants.gd` (секция SHOOTING — часть)
- Modify: `scripts/match/match_manager.gd` — `_fire_charge` (SHOT-ветка) → новый `_fire_shot`; `_on_action_contact` (уже поддерживает launch).

**Interfaces:**
- Consumes: `ShotSystem.wants_clearance/goal_aim_point/ballistic_to/clearance_velocity/scatter_meters`, `_ball_gravity`, `_pass_rng`, `ball.launch`.
- Produces: `_fire_shot(action, player, charge_ratio)`; `FootballConstants.SHOT_*` / `CLEARANCE_*`.

- [ ] **Step 1: Константы (секция SHOOTING)**

В `football_constants.gd` (после Magnus-констант или в конце):

```gdscript
# --- Прямой удар / прицел / вынос ---
const SHOT_POWER_MIN := 16.0        # горизонтальная скорость при мин. заряде, м/с
const SHOT_POWER_MAX := 30.0        # при полном заряде
const SHOT_OVER_LIFT := 0.8         # на макс. заряде цель поднимается на height+это (риск через перекладину), м
const SHOT_SCATTER_BASE := 0.9      # базовый разброс прицела, м
const SHOT_SCATTER_DIST_REF := 22.0 # дистанция, на которой разброс базовый, м
const CLEARANCE_ZONE_DIST := 32.0   # дальше этого до чужих ворот → вынос
const CLEARANCE_FACING_DOT := 0.2   # facing·(на ворота) ниже → вынос
const CLEARANCE_POWER := 26.0       # сила выноса, м/с
const CLEARANCE_LIFT := 6.0         # подъём выноса, м/с
```

- [ ] **Step 2: `_fire_shot` и диспатч из `_fire_charge`**

В `_fire_charge`, SHOT-ветку (`if action == ChargeAction.SHOT:` … до `else:`) заменить на диспатч в `_fire_shot` для всех трёх ударов:

```gdscript
	if action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]:
		var ratio := clampf(_charge_time / KICK_CHARGE_MAX_TIME, 0.0, 1.0)
		_cancel_charge()
		_fire_shot(action, player, ratio)
	else:
		var charge_ratio := clampf(_charge_time / FootballConstants.PASS_CHARGE_MAX_TIME, 0.0, 1.0)
		_cancel_charge()
		_fire_pass(action, player, charge_ratio)
```

Добавить функцию `_fire_shot` (рядом с `_fire_pass`). Прямой удар и вынос; кручёный/черпачок — заглушка на прямой пока (Задачи 5–6 их доделают):

```gdscript
## Удар: контекст решает удар в ворота vs вынос; тип (прямой/кручёный/черпачок) — по action.
## Импульс — через commit-action (ball.launch по action_contact), как у паса.
func _fire_shot(action: ChargeAction, player: CharacterBody3D, charge_ratio: float) -> void:
	if not ball.has_method(&"launch"):
		return
	var from: Vector3 = ball.global_position
	var goal_center := Vector3(0.0, 0.0, -field_length)  # чужие ворота (атакуем −Z)
	var half_w: float = FootballConstants.GOAL_WIDTH / 2.0
	var height: float = FootballConstants.GOAL_HEIGHT
	var facing: Vector3 = ball.get_dribble_direction()
	var g := _ball_gravity()
	var launch_vel: Vector3
	var curl := Vector3.ZERO

	if ShotSystem.wants_clearance(from, goal_center, facing,
			FootballConstants.CLEARANCE_ZONE_DIST, FootballConstants.CLEARANCE_FACING_DOT):
		# ВЫНОС: мощно по facing вдаль, без прицела в створ.
		var power := lerpf(FootballConstants.CLEARANCE_POWER, FootballConstants.CLEARANCE_POWER * 1.2, charge_ratio)
		launch_vel = ShotSystem.clearance_velocity(facing, power, FootballConstants.CLEARANCE_LIFT)
	else:
		# УДАР: прицел в створ (гибрид: авто-цель + смещение по facing + разброс).
		var side_bias := ShotSystem.curl_side(from, goal_center, facing)  # знак угла по facing (−1..1 упрощён до ±1)
		var dist := Vector3(goal_center.x - from.x, 0.0, goal_center.z - from.z).length()
		var scatter := ShotSystem.scatter_meters(FootballConstants.SHOT_SCATTER_BASE, charge_ratio,
			dist, FootballConstants.SHOT_SCATTER_DIST_REF)
		var aim := ShotSystem.goal_aim_point(goal_center, half_w, height, side_bias, charge_ratio,
			FootballConstants.SHOT_OVER_LIFT, scatter, _pass_rng)
		var power := lerpf(FootballConstants.SHOT_POWER_MIN, FootballConstants.SHOT_POWER_MAX, charge_ratio)
		launch_vel = ShotSystem.ballistic_to(from, aim, power, g)
		# Кручёный/черпачок доделываются в Задачах 5–6; пока летят как прямой.

	# Commit-action: импульс по action_contact, launch-путь (сентинел _action_power = -1).
	_action_player = player
	_action_dir = launch_vel
	_action_power = -1.0
	_kick_action_active = true
	_pending_launch = launch_vel
	_pending_curl = curl
	var visual := _player_visual(player)
	if visual != null and visual.trigger("kick"):
		return
	ball.launch(launch_vel)
	_action_player = null
	_kick_action_active = false
```

- [ ] **Step 3: `_pending_curl` поле + launch_curl в `_on_action_contact`**

Добавить поле рядом с `_pending_launch`:

```gdscript
var _pending_curl: Vector3 = Vector3.ZERO
```

В `_on_action_contact`, launch-ветку (`if _action_power < 0.0 and ball.has_method(&"launch"):`) заменить, чтобы кручёный шёл через `launch_curl`:

```gdscript
	if _action_power < 0.0 and ball.has_method(&"launch"):
		if _pending_curl.length_squared() > 0.0001 and ball.has_method(&"launch_curl"):
			ball.launch_curl(_pending_launch, _pending_curl)
		else:
			ball.launch(_pending_launch)
```

- [ ] **Step 4: Регресс — обе команды + оба check-скрипта**

Expected: baseline; `check_shot_system_math.gd` и `check_ball_state.gd` → `CHECK PASS`.

- [ ] **Step 5: Ручная приёмка (прямой удар + вынос)**

Запустить игру. Ожидание: (1) удар от центра к −Z воротам летит В створ, слабый — низом, сильный — выше (на максимуме иногда мимо/через перекладину — разброс/подъём); (2) удар издалека или спиной к воротам = вынос (мощно вдаль по facing, без прицела); (3) удар в плотную стенку блокируется (Фаза 0). Подстроить `SHOT_POWER_*`, `SHOT_SCATTER_BASE`, `SHOT_OVER_LIFT`, `CLEARANCE_ZONE_DIST`.

- [ ] **Step 6: Commit**

```bash
git add scripts/data/football_constants.gd scripts/match/match_manager.gd
git commit -m "feat(shot): bullet shot with hybrid goal aim + misses, context-driven clearance (commit-launch)"
```

---

## Task 5: Кручёный удар (Magnus)

**Files:**
- Modify: `scripts/data/football_constants.gd` (SHOOTING — кручёный)
- Modify: `scripts/match/match_manager.gd:_fire_shot` (ветка `SHOT_CURL`)

**Interfaces:**
- Consumes: `ShotSystem.curl_side/curl_vector`, `ball.launch_curl` (через `_pending_curl`).
- Produces: `FootballConstants.CURL_STRENGTH_*`, `CURL_LIFT`.

- [ ] **Step 1: Константы кручёного**

```gdscript
# --- Кручёный ---
const CURL_STRENGTH_MIN := 2.0   # боковая сила кручения при мин. заряде (в единицах _curl.z)
const CURL_STRENGTH_MAX := 6.0   # при полном заряде (сильнее закручивает)
const CURL_LIFT := 1.2           # подъёмная составляющая дуги (_curl.y)
```

- [ ] **Step 2: Ветка SHOT_CURL в `_fire_shot`**

В `_fire_shot`, внутри ветки УДАРА (не выноса), после вычисления `launch_vel`, добавить перед commit-action:

```gdscript
		if action == ChargeAction.SHOT_CURL:
			var side := ShotSystem.curl_side(from, goal_center, facing)
			var strength := lerpf(FootballConstants.CURL_STRENGTH_MIN, FootballConstants.CURL_STRENGTH_MAX, charge_ratio)
			curl = ShotSystem.curl_vector(side, strength, FootballConstants.CURL_LIFT)
```

(`curl` уже кладётся в `_pending_curl` ниже; при ненулевом `_curl` `_on_action_contact` вызовет `launch_curl`.)

- [ ] **Step 3: Регресс — обе команды + check-скрипты**

Expected: baseline; `CHECK PASS`.

- [ ] **Step 4: Ручная приёмка (кручёный)**

Запустить игру. Кручёный (`E`+`D`): мяч должен лететь ДУГОЙ и закручиваться в сторону угла, ближнего к facing. Проверить обе стороны (повернуть игрока влево/вправо от прямой на ворота). **Если крутит НЕ в ту сторону — инвертировать знак в `ShotSystem.curl_side`** (вернуть `-1.0`/`1.0` наоборот). Подстроить `CURL_STRENGTH_*`/`CURL_LIFT` и `MAGNUS_FORCE`/`MAGNUS_DECAY` (Фаза 0) под красивую дугу.

- [ ] **Step 5: Commit**

```bash
git add scripts/data/football_constants.gd scripts/match/match_manager.gd
git commit -m "feat(shot): curl shot via Magnus (side from facing, charge scales curl)"
```

---

## Task 6: Черпачок (chip)

**Files:**
- Modify: `scripts/data/football_constants.gd` (SHOOTING — черпачок)
- Modify: `scripts/match/match_manager.gd:_fire_shot` (ветка `SHOT_CHIP`)

**Interfaces:**
- Consumes: `PassSystem.launch_lob` (переиспользуем баллистику навеса), `ShotSystem.goal_aim_point`.
- Produces: `FootballConstants.CHIP_PEAK_MIN/MAX`.

- [ ] **Step 1: Константы черпачка**

```gdscript
# --- Черпачок (chip) ---
const CHIP_PEAK_MIN := 2.5   # высота параболы при мин. заряде, м
const CHIP_PEAK_MAX := 6.0   # при полном заряде (выше перекидывает)
```

- [ ] **Step 2: Ветка SHOT_CHIP в `_fire_shot`**

В ветке УДАРА, заменить вычисление `launch_vel` так, чтобы для черпачка использовать лоб-баллистику к точке прицела (перекидывающая парабола, высота по заряду):

```gdscript
		if action == ChargeAction.SHOT_CHIP:
			var peak := lerpf(FootballConstants.CHIP_PEAK_MIN, FootballConstants.CHIP_PEAK_MAX, charge_ratio)
			launch_vel = PassSystem.launch_lob(from, aim, peak, g)
		else:
			var power := lerpf(FootballConstants.SHOT_POWER_MIN, FootballConstants.SHOT_POWER_MAX, charge_ratio)
			launch_vel = ShotSystem.ballistic_to(from, aim, power, g)
```

(Т.е. вынести существующий `ballistic_to` в `else`, а для chip — `launch_lob`. `aim` уже посчитан выше. Кручёный использует `ballistic_to` из `else` + добавляет `curl` — порядок: сначала этот if/else по типу, потом отдельный `if SHOT_CURL` из Задачи 5 задаёт `curl`.)

- [ ] **Step 3: Регресс — обе команды + check-скрипты**

Expected: baseline; `CHECK PASS`.

- [ ] **Step 4: Ручная приёмка (черпачок)**

Черпачок (`Q`+`D`): мяч летит высокой параболой (перекидывающей), выше при большем заряде. Проверить, что перекидывает стенку болванок. Подстроить `CHIP_PEAK_*`.

- [ ] **Step 5: Commit**

```bash
git add scripts/data/football_constants.gd scripts/match/match_manager.gd
git commit -m "feat(shot): chip shot (lob ballistic to goal aim, charge scales arc height)"
```

---

## Task 7: Финальная приёмка трёх ударов + очистка временного плейсхолдера

**Files:**
- Modify: `scripts/match/match_manager.gd` (удалить старую SHOT-ветку с `ball.kick`/`dir.y`, если осталась мёртвой)

- [ ] **Step 1: Убедиться, что старый плейсхолдер-путь удара удалён**

Проверить `_fire_charge` — не осталось ли старого кода `ball.kick(dir, power)` для SHOT (он заменён на `_fire_shot`). Временные `KICK_POWER_MIN/MAX = 18/34` из Фазы 0 больше не используются ударом (теперь `SHOT_POWER_*`) — можно оставить как есть или убрать локальные консты, если на них ничего не ссылается (grep `KICK_POWER`).

- [ ] **Step 2: Ручная приёмка всех трёх + выноса вместе**

Прогнать: прямой/кручёный/черпачок/вынос по очереди; разброс на макс. заряде; блок стенкой; кручёный в обе стороны. Зафиксировать финальные значения констант.

- [ ] **Step 3: Регресс — обе команды + оба check-скрипта**

- [ ] **Step 4: Commit**

```bash
git add scripts/match/match_manager.gd scripts/data/football_constants.gd
git commit -m "chore(shot): remove dead placeholder kick path; finalize Phase 1 shot tuning"
```

---

## Self-Review (выполнено автором)

**Spec coverage (S3 «Фаза 1» спека `2026-07-10-shot-system-design.md`):**
- Три траектории (bullet/curl/chip) — Задачи 4/5/6. ✓
- Ввод: `D`/X, `E`+`D`/RB+X, `Q`+`D`/LB+X — Задачи 2/3. ✓
- Гибридный прицел (авто-цель + facing-смещение + разброс) — `ShotSystem.goal_aim_point` + `curl_side`, Задача 4. ✓
- Промахи (разброс растёт с дистанцией/зарядом; подъём на макс. заряде) — `scatter_meters` + `SHOT_OVER_LIFT`. ✓
- Заглушка «случайная точка створа под вратаря» — `goal_aim_point` + `_pass_rng`. ✓
- Контекстный вынос — `wants_clearance` + `clearance_velocity`, Задача 4. ✓
- Кручёный через Magnus (`launch_curl`, `_curl`) — Задача 5 (физика — Фаза 0). ✓
- Черпачок = лоб-баллистика — Задача 6 (переиспользует `PassSystem.launch_lob`). ✓
- Commit-launch (не `kick`), блок стенкой из Фазы 0 — Global Constraints + Задача 4. ✓

**Отклонения/упрощения:** `curl_side`/`goal_aim_point.side_bias` упрощены до ±1 угла (не плавное смещение по стику) — достаточно для «в ближний угол по facing»; плавное смещение — тюнинг позже, если нужно. Точка прицела считается по `get_dribble_direction()` (facing владельца), т.к. движение камеро-относительное и стик = facing.

**Placeholder scan:** реального кода везде хватает; «заглушка на прямой» в Задаче 4 явно доделывается Задачами 5–6 (не висячий TODO).

**Type consistency:** `ShotSystem.*` сигнатуры совпадают между модулем, тестом и вызовами в `_fire_shot`; `_pending_curl: Vector3`, `_action_power = -1.0` сентинел, `launch_curl(velocity, curl)` — согласованы с Фазой 0.

**Открытый момент для ручной приёмки:** знак `curl_side` (сторона кручения) и все `SHOT_*`/`CURL_*`/`CHIP_*`/`CLEARANCE_*` — тюнинг-старт, финализируются пользователем живьём (стенки/соперник уже на поле).

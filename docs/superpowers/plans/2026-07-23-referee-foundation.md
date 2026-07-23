# Referee Foundation (Этап 0, кусок A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать матчу «судью» v1 — отдельный узел, который сам детектит выход мяча за линии, гол и фол подката, определяет тип рестарта и команду-исполнителя, эмитит сигналы и (интерим) ставит мяч на точку с передачей владения, пока настоящие ИИ-стандарты ещё не готовы.

**Architecture:** Три чистых-функциональных файла (`BoundaryLogic`, `RefereeLogic` — `class_name X extends Object`, НИКОГДА не читают `FootballConstants`, тюнинг параметрами, headless-тестируемы как `GoalKickLogic`/`PassSystem`) + узел-компонент `MatchReferee` (`extends Node`, автомат `LIVE`/`DEAD`, компонует чистые функции, эмитит сигналы, интерим detect+award), плюс минимальная проводка в `match_manager.gd` (отодвинуть стены, тикать детект, прокинуть гол/фол/касания). Трекинг касаний — добавка на `ball_controller.gd` (замена чистимого `last_kicker` честным `last_touch`).

**Tech Stack:** Godot 4.7 / GDScript. Headless-тесты — скрипты `tests/check_*.gd` (`extends SceneTree`, печатают `CHECK PASS`/`CHECK FAIL`, `quit(0/1)`).

## Global Constants

- **Пол/размеры** — `field_length`/`field_width` в `match_manager.gd` это ПОЛУ-размеры (`HALF_FIELD_LENGTH = 52.5`, `HALF_FIELD_WIDTH = 34.0`). Ворота на `Z = ±field_length`. Мяч атакует к `−Z` (team_1). `BALL_RADIUS = 0.11`, `GOAL_WIDTH = 7.32`, `GOAL_AREA_DEPTH = 5.5`, `PENALTY_AREA_DEPTH = 16.5`, `PENALTY_AREA_WIDTH = 40.32` (полная → half = 20.16), `CORNER_INSET = 0.5`.
- **Кодировка команд в чистых функциях:** `int` 1 = team_1, 2 = team_2, 0 = неизвестно. Узел маппит в группы `team_1`/`team_2`.
- **Чистые функции НЕ читают `FootballConstants`** — все размеры/пороги приходят параметрами (инвариант проекта; так они headless-тестируемы без автолоада).
- **Тест-раннер:** `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/<name>.gd"` → ожидаем `CHECK PASS` и exit 0.
- **Валидация сцены матча (после проводки в match_manager):** `& "<godot>" --path "<repo>" --headless --quit-after 2 res://scenes/match.tscn`. Известный baseline ошибок (не регрессии): `Condition "!is_inside_tree()" is true`, дубль-регистрация `ACTION_CLIPS` (`states.has(p_name)` + два transition-duplicate), `Cannot get class 'WorldEnvironment3D'`. Диффать по КАТЕГОРИИ текста, не по числу.

---

## File Structure

- **Create** `scripts/match/boundary_logic.gd` — `class_name BoundaryLogic extends Object`. Чистая геометрия: классификация «мяч пересёк линию» (аут/лицевая) + точки рестарта (аут/угловой/удар от ворот).
- **Create** `tests/check_boundary_logic.gd` — headless-тест `BoundaryLogic`.
- **Create** `scripts/match/referee_logic.gd` — `class_name RefereeLogic extends Object`. Чистое разрешение рестарта: `ball_out_restart`, `foul_restart`, `select_taker`, `opposite`, `enum Restart`.
- **Create** `tests/check_referee_logic.gd` — headless-тест `RefereeLogic`.
- **Create** `scripts/match/match_referee.gd` — `class_name MatchReferee extends Node`. Автомат `LIVE`/`DEAD`, детект-тик, сигналы, интерим detect+award.
- **Create** `tests/check_referee_flow.gd` — headless-смоук узла судьи со stub-мячом/менеджером.
- **Modify** `scripts/ball/ball_controller.gd` — `var last_touch: Node3D` + `note_touch()`, запись касаний в `kick`/`launch`/`launch_curl`/`set_dribbler`/`catch`/`note_kicker`.
- **Create** `tests/check_ball_touch.gd` — headless-тест трекинга касаний.
- **Modify** `scripts/data/football_constants.gd` — секция `REFEREE` + константы отступа стен.
- **Modify** `scripts/match/match_manager.gd` — отодвинуть стены на константы; заинстанцировать+`setup` `MatchReferee`; тикать детект в `_physics_process`; писать касание при контакте мяч↔игрок; прокинуть гол и фол подката в судью.

---

## Task 1: Трекинг касаний на мяче (`last_touch`)

**Files:**
- Modify: `scripts/ball/ball_controller.gd` (поле рядом с `last_kicker` на строке 11; методы `kick`/`launch`/`launch_curl`/`set_dribbler`/`catch`/`note_kicker`)
- Test: `tests/check_ball_touch.gd`

**Interfaces:**
- Produces: `ball.last_touch: Node3D` (последний игрок, коснувшийся мяча; НЕ чистится при блоке/старте сет-писа — в отличие от `last_kicker`), `ball.note_touch(node: Node3D) -> void`.

- [ ] **Step 1: Написать падающий тест**

Create `tests/check_ball_touch.gd`:

```gdscript
extends SceneTree
## Headless-проверка трекинга касаний мяча (last_touch). Не чистится при блоке/релизе,
## в отличие от last_kicker. Всё синхронно — методы не зависят от физкадров.

func _initialize() -> void:
	var ok := true
	var ball := RigidBody3D.new()
	ball.set_script(load("res://scripts/ball/ball_controller.gd"))
	root.add_child(ball)
	var a := Node3D.new()
	root.add_child(a)
	var b := Node3D.new()
	root.add_child(b)
	ball._last_release_time = -100000

	ok = _expect(ball.last_touch == null, "старт: last_touch == null") and ok

	# Трап (set_dribbler) записывает касание.
	ball.set_dribbler(a)
	ok = _expect(ball.last_touch == a, "set_dribbler → last_touch = a") and ok

	# Удар записывает бьющего (a — текущий владелец).
	ball.kick(Vector3.FORWARD, 15.0)
	ok = _expect(ball.last_touch == a, "kick → last_touch = a") and ok

	# Блок НЕ чистит last_touch (в отличие от last_kicker/clear).
	ball.block_in_flight()
	ok = _expect(ball.last_touch == a, "block_in_flight не чистит last_touch") and ok

	# clear_last_kicker чистит kicker, но НЕ touch.
	ball.clear_last_kicker()
	ok = _expect(ball.last_kicker == null and ball.last_touch == a, "clear_last_kicker не трогает last_touch") and ok

	# Явное касание другим игроком.
	ball.note_touch(b)
	ok = _expect(ball.last_touch == b, "note_touch(b) → last_touch = b") and ok

	# Ловля вратарём (catch) записывает holder.
	var hold := Node3D.new()
	root.add_child(hold)
	ball.catch(a, hold)
	ok = _expect(ball.last_touch == a, "catch → last_touch = holder") and ok

	if ok:
		print("CHECK PASS: ball_touch")
		quit(0)
	else:
		print("CHECK FAIL: ball_touch")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ball_touch.gd"`
Expected: `CHECK FAIL: ball_touch` (метода `note_touch`/поля `last_touch` ещё нет — либо ошибка «Invalid set/get», либо FAIL на первом же ожидании).

- [ ] **Step 3: Добавить поле и метод**

В `scripts/ball/ball_controller.gd` после строки 11 (`var last_kicker: Node3D`) добавить:

```gdscript
var last_touch: Node3D   # последний коснувшийся мяча (для атрибуции судьи); НЕ чистится при блоке/старте сет-писа, в отличие от last_kicker
```

Добавить метод (рядом с `clear_last_kicker`, после строки 242):

```gdscript
## Записать касание мяча игроком (вход атрибуции судьи: аут/угловой/удар от ворот).
## В отличие от last_kicker (кулдаун удара, намеренно чистится) — last_touch держится до
## следующего реального касания.
func note_touch(node: Node3D) -> void:
	if node != null and is_instance_valid(node):
		last_touch = node
```

- [ ] **Step 4: Проставить `note_touch` во всех точках касания**

В `kick()` (строка 283) после `last_kicker = dribbler`:
```gdscript
	note_touch(dribbler)
```
В `launch()` (строка 298) после `last_kicker = dribbler`:
```gdscript
	note_touch(dribbler)
```
В `launch_curl()` (строка 313) после `last_kicker = dribbler`:
```gdscript
	note_touch(dribbler)
```
В `set_dribbler()` (внутри `if node:` блока, после строки 92 `dribbler = node`):
```gdscript
	note_touch(node)
```
В `catch()` (строка 131) после `dribbler = holder`:
```gdscript
	note_touch(holder)
```
В `note_kicker()` (строка 250) после `last_kicker = node`:
```gdscript
	note_touch(node)
```

- [ ] **Step 5: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ball_touch.gd"`
Expected: `CHECK PASS: ball_touch`, exit 0.

- [ ] **Step 6: Коммит**

```bash
git add scripts/ball/ball_controller.gd tests/check_ball_touch.gd
git commit -m "feat(ball): honest last_touch tracking for referee attribution"
```

---

## Task 2: `BoundaryLogic` — классификация выхода мяча + точки рестарта

**Files:**
- Create: `scripts/match/boundary_logic.gd`
- Test: `tests/check_boundary_logic.gd`

**Interfaces:**
- Produces:
  - `enum BoundaryLogic.Exit { NONE = 0, TOUCHLINE = 1, GOAL_LINE_NEG = 2, GOAL_LINE_POS = 3 }`
  - `BoundaryLogic.classify(ball_pos: Vector3, half_len: float, half_width: float, goal_half_width: float, ball_radius: float) -> int`
  - `BoundaryLogic.throw_in_spot(ball_pos: Vector3, half_width: float, ball_radius: float) -> Vector3`
  - `BoundaryLogic.corner_spot(ball_pos: Vector3, half_len: float, half_width: float, exit: int, inset: float, ball_radius: float) -> Vector3`
  - `BoundaryLogic.goal_kick_spot(exit: int, half_len: float, ga_depth: float, ball_radius: float) -> Vector3`

- [ ] **Step 1: Написать падающий тест**

Create `tests/check_boundary_logic.gd`:

```gdscript
extends SceneTree
## Headless-проверка чистых функций BoundaryLogic (классификация выхода + точки рестарта).
## Поле: half_len=52.5, half_width=34, goal_half_width=3.66, ball_radius=0.11.

const HL := 52.5
const HW := 34.0
const GHW := 3.66
const R := 0.11

func _init() -> void:
	var ok := true
	ok = _check_inside() and ok
	ok = _check_touchline() and ok
	ok = _check_goal_line_wide() and ok
	ok = _check_goal_mouth_not_out() and ok
	ok = _check_throw_spot() and ok
	ok = _check_corner_spot() and ok
	ok = _check_goal_kick_spot() and ok
	if ok:
		print("CHECK PASS: boundary_logic")
		quit(0)
	else:
		print("CHECK FAIL: boundary_logic")
		quit(1)

func _check_inside() -> bool:
	var e := BoundaryLogic.classify(Vector3(10, 0.11, 10), HL, HW, GHW, R)
	if e != BoundaryLogic.Exit.NONE:
		print("  FAIL inside: ", e); return false
	return true

func _check_touchline() -> bool:
	# x=34.5 > 34+0.11 → аут.
	var e := BoundaryLogic.classify(Vector3(34.5, 0.11, 10), HL, HW, GHW, R)
	if e != BoundaryLogic.Exit.TOUCHLINE:
		print("  FAIL touchline: ", e); return false
	return true

func _check_goal_line_wide() -> bool:
	# z=-53 < -(52.5+0.11), |x|=5 > goal_half_width → за лицевой мимо ворот.
	var e := BoundaryLogic.classify(Vector3(5, 0.11, -53.0), HL, HW, GHW, R)
	if e != BoundaryLogic.Exit.GOAL_LINE_NEG:
		print("  FAIL goal_line_neg: ", e); return false
	var e2 := BoundaryLogic.classify(Vector3(-5, 0.11, 53.0), HL, HW, GHW, R)
	if e2 != BoundaryLogic.Exit.GOAL_LINE_POS:
		print("  FAIL goal_line_pos: ", e2); return false
	return true

func _check_goal_mouth_not_out() -> bool:
	# z=-53, |x|=2 < goal_half_width (в створе) → это гол, НЕ аут-за-лицевой → NONE.
	var e := BoundaryLogic.classify(Vector3(2, 0.5, -53.0), HL, HW, GHW, R)
	if e != BoundaryLogic.Exit.NONE:
		print("  FAIL goal_mouth: ", e); return false
	return true

func _check_throw_spot() -> bool:
	# Проекция на ближайшую боковую (x=+34), z сохраняется, y=ball_radius.
	var s := BoundaryLogic.throw_in_spot(Vector3(34.5, 0.5, 12.0), HW, R)
	if not (is_equal_approx(s.x, 34.0) and is_equal_approx(s.z, 12.0) and is_equal_approx(s.y, R)):
		print("  FAIL throw_spot: ", s); return false
	return true

func _check_corner_spot() -> bool:
	# Выход за -Z, x>0 → угловой флаг (+HW-inset, -HL+inset).
	var s := BoundaryLogic.corner_spot(Vector3(5, 0.5, -53.0), HL, HW, BoundaryLogic.Exit.GOAL_LINE_NEG, 0.5, R)
	if not (is_equal_approx(s.x, 33.5) and is_equal_approx(s.z, -52.0) and is_equal_approx(s.y, R)):
		print("  FAIL corner_spot: ", s); return false
	return true

func _check_goal_kick_spot() -> bool:
	# Удар от ворот на -Z: центр линии вратарской (x=0, z=-HL+ga_depth).
	var s := BoundaryLogic.goal_kick_spot(BoundaryLogic.Exit.GOAL_LINE_NEG, HL, 5.5, R)
	if not (is_equal_approx(s.x, 0.0) and is_equal_approx(s.z, -47.0) and is_equal_approx(s.y, R)):
		print("  FAIL goal_kick_spot: ", s); return false
	return true
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_boundary_logic.gd"`
Expected: FAIL/parse error — `BoundaryLogic` ещё не существует.

- [ ] **Step 3: Реализовать `BoundaryLogic`**

Create `scripts/match/boundary_logic.gd`:

```gdscript
class_name BoundaryLogic
extends Object
## Чистая геометрия границ поля. НИКОГДА не читает FootballConstants — тюнинг параметрами.
## Классифицирует выход мяча за линии и даёт точки рестарта.

enum Exit { NONE = 0, TOUCHLINE = 1, GOAL_LINE_NEG = 2, GOAL_LINE_POS = 3 }

## Мяч ПОЛНОСТЬЮ пересёк линию (центр дальше линии на радиус). Аут (боковая) проверяется
## первым; за лицевой засчитывается ТОЛЬКО мимо створа (|x| > goal_half_width) — иначе это
## взятие ворот, не аут. Угловой корнер (за обе линии) отдаём боковой (детерминированно).
static func classify(ball_pos: Vector3, half_len: float, half_width: float, goal_half_width: float, ball_radius: float) -> int:
	if absf(ball_pos.x) > half_width + ball_radius:
		return Exit.TOUCHLINE
	if ball_pos.z < -(half_len + ball_radius) and absf(ball_pos.x) > goal_half_width:
		return Exit.GOAL_LINE_NEG
	if ball_pos.z > half_len + ball_radius and absf(ball_pos.x) > goal_half_width:
		return Exit.GOAL_LINE_POS
	return Exit.NONE

## Точка вброса: проекция на ближайшую боковую линию (x = ±half_width), z сохраняется.
static func throw_in_spot(ball_pos: Vector3, half_width: float, ball_radius: float) -> Vector3:
	var sx := 1.0 if ball_pos.x >= 0.0 else -1.0
	return Vector3(sx * half_width, ball_radius, ball_pos.z)

## Точка углового: ближний угловой флаг на пересечённой лицевой, сдвинут inset внутрь поля.
static func corner_spot(ball_pos: Vector3, half_len: float, half_width: float, exit: int, inset: float, ball_radius: float) -> Vector3:
	var gz := -half_len if exit == Exit.GOAL_LINE_NEG else half_len
	var sx := 1.0 if ball_pos.x >= 0.0 else -1.0
	var sz := 1.0 if gz < 0.0 else -1.0   # inset внутрь поля от лицевой
	return Vector3(sx * (half_width - inset), ball_radius, gz + sz * inset)

## Точка удара от ворот: центр линии вратарской площади на пересечённой лицевой.
static func goal_kick_spot(exit: int, half_len: float, ga_depth: float, ball_radius: float) -> Vector3:
	var gz := -half_len if exit == Exit.GOAL_LINE_NEG else half_len
	var into := 1.0 if gz < 0.0 else -1.0
	return Vector3(0.0, ball_radius, gz + into * ga_depth)
```

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_boundary_logic.gd"`
Expected: `CHECK PASS: boundary_logic`, exit 0.

- [ ] **Step 5: Коммит**

```bash
git add scripts/match/boundary_logic.gd tests/check_boundary_logic.gd
git commit -m "feat(referee): BoundaryLogic — ball-out classification + restart spots"
```

---

## Task 3: `RefereeLogic` — разрешение рестарта и выбор исполнителя

**Files:**
- Create: `scripts/match/referee_logic.gd`
- Test: `tests/check_referee_logic.gd`

**Interfaces:**
- Consumes: `BoundaryLogic.Exit` (Task 2) для значений `exit`.
- Produces:
  - `enum RefereeLogic.Restart { THROW_IN = 0, CORNER = 1, GOAL_KICK = 2, KICKOFF = 3, FREE_KICK = 4, PENALTY = 5 }`
  - `RefereeLogic.opposite(team: int) -> int` (1↔2; 0→1 как защитный дефолт)
  - `RefereeLogic.ball_out_restart(exit: int, last_touch_team: int, team_defending_neg: int) -> Dictionary` → `{ "restart": int, "team": int }` (team = исполняющая команда)
  - `RefereeLogic.foul_restart(foul_pos: Vector3, fouler_team: int, fouled_team: int, half_len: float, team_defending_neg: int, pa_depth: float, pa_half_width: float) -> Dictionary` → `{ "restart": int, "team": int }`
  - `RefereeLogic.select_taker(spot: Vector3, positions: Array) -> int` (индекс ближайшей позиции; `-1` если пусто)

- [ ] **Step 1: Написать падающий тест**

Create `tests/check_referee_logic.gd`:

```gdscript
extends SceneTree
## Headless-проверка RefereeLogic. team_defending_neg=2 (team_2 защищает -Z ворота).

const HL := 52.5
const PA_DEPTH := 16.5
const PA_HW := 20.16
const TDN := 2   # team_defending_neg

func _init() -> void:
	var ok := true
	ok = _check_throw_in() and ok
	ok = _check_corner() and ok
	ok = _check_goal_kick() and ok
	ok = _check_foul_free_kick() and ok
	ok = _check_foul_penalty() and ok
	ok = _check_select_taker() and ok
	if ok:
		print("CHECK PASS: referee_logic")
		quit(0)
	else:
		print("CHECK FAIL: referee_logic")
		quit(1)

func _check_throw_in() -> bool:
	# Аут, последним касался team_1 → вброс исполняет team_2.
	var r := RefereeLogic.ball_out_restart(BoundaryLogic.Exit.TOUCHLINE, 1, TDN)
	if not (r["restart"] == RefereeLogic.Restart.THROW_IN and r["team"] == 2):
		print("  FAIL throw_in: ", r); return false
	return true

func _check_corner() -> bool:
	# За -Z (защищает team_2), последним касался team_2 (защищающийся) → угловой, бьёт team_1.
	var r := RefereeLogic.ball_out_restart(BoundaryLogic.Exit.GOAL_LINE_NEG, 2, TDN)
	if not (r["restart"] == RefereeLogic.Restart.CORNER and r["team"] == 1):
		print("  FAIL corner: ", r); return false
	return true

func _check_goal_kick() -> bool:
	# За -Z, последним касался team_1 (атакующий) → удар от ворот, бьёт team_2 (защита).
	var r := RefereeLogic.ball_out_restart(BoundaryLogic.Exit.GOAL_LINE_NEG, 1, TDN)
	if not (r["restart"] == RefereeLogic.Restart.GOAL_KICK and r["team"] == 2):
		print("  FAIL goal_kick: ", r); return false
	return true

func _check_foul_free_kick() -> bool:
	# team_1 фолит в центре поля против team_2 → штрафной team_2, не пенальти.
	var r := RefereeLogic.foul_restart(Vector3(0, 0, 0), 1, 2, HL, TDN, PA_DEPTH, PA_HW)
	if not (r["restart"] == RefereeLogic.Restart.FREE_KICK and r["team"] == 2):
		print("  FAIL foul_free_kick: ", r); return false
	return true

func _check_foul_penalty() -> bool:
	# team_2 (защищает -Z) фолит в СВОЕЙ штрафной (z=-45, |x|<20.16) против team_1 → пенальти team_1.
	var r := RefereeLogic.foul_restart(Vector3(3, 0, -45.0), 2, 1, HL, TDN, PA_DEPTH, PA_HW)
	if not (r["restart"] == RefereeLogic.Restart.PENALTY and r["team"] == 1):
		print("  FAIL foul_penalty: ", r); return false
	# team_1 (атакующий) фолит в той же штрафной → обычный штрафной team_2, НЕ пенальти.
	var r2 := RefereeLogic.foul_restart(Vector3(3, 0, -45.0), 1, 2, HL, TDN, PA_DEPTH, PA_HW)
	if not (r2["restart"] == RefereeLogic.Restart.FREE_KICK and r2["team"] == 2):
		print("  FAIL foul_penalty_attacker: ", r2); return false
	return true

func _check_select_taker() -> bool:
	var spot := Vector3(10, 0, 10)
	var positions := [Vector3(0, 0, 0), Vector3(9, 0, 9), Vector3(-5, 0, -5)]
	var idx := RefereeLogic.select_taker(spot, positions)
	if idx != 1:
		print("  FAIL select_taker: ", idx); return false
	if RefereeLogic.select_taker(spot, []) != -1:
		print("  FAIL select_taker empty"); return false
	return true
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_referee_logic.gd"`
Expected: FAIL/parse error — `RefereeLogic` ещё не существует.

- [ ] **Step 3: Реализовать `RefereeLogic`**

Create `scripts/match/referee_logic.gd`:

```gdscript
class_name RefereeLogic
extends Object
## Чистое разрешение рестарта. НИКОГДА не читает FootballConstants — тюнинг/размеры параметрами.
## Команды кодируются int: 1 = team_1, 2 = team_2, 0 = неизвестно.

enum Restart { THROW_IN = 0, CORNER = 1, GOAL_KICK = 2, KICKOFF = 3, FREE_KICK = 4, PENALTY = 5 }

## Противоположная команда. 0 (неизвестно) → 1 как защитный дефолт (судья вызывает только при
## валидном last_touch; дефолт лишь чтобы не вернуть 0).
static func opposite(team: int) -> int:
	return 1 if team == 2 else 2 if team == 1 else 1

## Рестарт при выходе мяча за линию. team в результате — ИСПОЛНЯЮЩАЯ команда.
## Аут → команда, противоположная last_touch. За лицевой: если касался защищающийся (чьи это
## ворота) → угловой (бьёт атакующий); если атакующий → удар от ворот (бьёт защита).
static func ball_out_restart(exit: int, last_touch_team: int, team_defending_neg: int) -> Dictionary:
	if exit == BoundaryLogic.Exit.TOUCHLINE:
		return { "restart": Restart.THROW_IN, "team": opposite(last_touch_team) }
	var defender := team_defending_neg if exit == BoundaryLogic.Exit.GOAL_LINE_NEG else opposite(team_defending_neg)
	if last_touch_team == defender:
		return { "restart": Restart.CORNER, "team": opposite(defender) }
	return { "restart": Restart.GOAL_KICK, "team": defender }

## Рестарт при фоле подката. team — исполняющая (пострадавшая) команда. Пенальти — только если
## точка фола внутри штрафной площади, которую ЗАЩИЩАЕТ команда фолившего; иначе штрафной.
static func foul_restart(foul_pos: Vector3, fouler_team: int, fouled_team: int, half_len: float, team_defending_neg: int, pa_depth: float, pa_half_width: float) -> Dictionary:
	var defends_neg := fouler_team == team_defending_neg
	var goal_z := -half_len if defends_neg else half_len
	var into := 1.0 if defends_neg else -1.0
	var rel := (foul_pos.z - goal_z) * into   # 0 на линии ворот фолившего, растёт в поле
	var in_box := absf(foul_pos.x) <= pa_half_width and rel >= 0.0 and rel <= pa_depth
	var restart := Restart.PENALTY if in_box else Restart.FREE_KICK
	return { "restart": restart, "team": fouled_team }

## Индекс ближайшей к spot позиции (кто бьёт = ближайший подходящий). -1 если пусто.
static func select_taker(spot: Vector3, positions: Array) -> int:
	var best := -1
	var best_d := INF
	for i in positions.size():
		var d: float = (positions[i] as Vector3).distance_squared_to(spot)
		if d < best_d:
			best_d = d
			best = i
	return best
```

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_referee_logic.gd"`
Expected: `CHECK PASS: referee_logic`, exit 0.

- [ ] **Step 5: Коммит**

```bash
git add scripts/match/referee_logic.gd tests/check_referee_logic.gd
git commit -m "feat(referee): RefereeLogic — restart resolution + taker selection"
```

---

## Task 4: `MatchReferee` — узел-автомат, сигналы, интерим detect+award

**Files:**
- Create: `scripts/match/match_referee.gd`
- Test: `tests/check_referee_flow.gd`

**Interfaces:**
- Consumes: `BoundaryLogic` (Task 2), `RefereeLogic` (Task 3), `ball.last_touch` (Task 1).
- Produces:
  - `enum MatchReferee.State { LIVE = 0, DEAD = 1 }`
  - signal `restart_awarded(restart_type: int, team: int, spot: Vector3)`
  - signal `foul_called(spot: Vector3, team: int)` (team = фолившая)
  - `MatchReferee.setup(manager: Node, ball: Node, team_defending_neg: int) -> void`
  - `MatchReferee.tick() -> void` (вызывается из `match_manager._physics_process`, когда идёт открытая игра)
  - `MatchReferee.report_goal() -> void` (гол: интерим — только сигнал+лог; сам сброс делает существующий `_reset_ball` менеджера)
  - `MatchReferee.report_tackle_foul(foul_pos: Vector3, fouler: Node, fouled: Node) -> void`
  - `MatchReferee.state() -> int`

**Замечание о `class_name` в тесте (гоча проекта):** переменная тела статически типизирована `Node`, у неё нет `MatchReferee`-членов — объявляй `var ref: MatchReferee = ...` явно, не `:=` (иначе «cannot infer the type», как с `Player.brain()` в Фазе 2).

**Гоча дерева (as-built, всплыла при исполнении):** узлы, добавленные `root.add_child()` в `SceneTree._initialize()`, ещё НЕ «внутри дерева» — `global_position` возвращает identity (0,0,0), и судья видит мяч в центре → NONE. Поэтому создание узлов — в `_initialize`, а действия/проверки (`set_dribbler`/двигать мяч/`tick`/asserts) — в первом `_process(delta) -> bool` (там узлы уже в дереве). Позиции ставить локальным `position` (все узлы — прямые дети root с identity-трансформом, `position == global_position`). Плюс всегда `add_child` ПЕРЕД установкой позиции. Также после нового `class_name`-файла нужен `--headless --import` перед `-s`-тестом (иначе «Identifier not declared»).

- [ ] **Step 1: Написать падающий смоук-тест**

Create `tests/check_referee_flow.gd`:

```gdscript
extends SceneTree
## Headless-смоук MatchReferee: узел на stub-мяче/менеджере. Мяч за боковой при last_touch=team_1
## → эмитит restart_awarded(THROW_IN, team=2, spot на линии) И интерим-заглушка ставит мяч на
## точку + отдаёт владение ближайшему team_2. Проверяем сигнал и репозицию мяча.

var _got := {}

func _initialize() -> void:
	var ok := true

	# Stub-мяч: RigidBody3D с ball_controller (реальный last_touch/set_dribbler).
	var ball := RigidBody3D.new()
	ball.set_script(load("res://scripts/ball/ball_controller.gd"))
	root.add_child(ball)
	ball._last_release_time = -100000

	# Stub-игроки обеих команд (для select_taker и передачи владения).
	var p1 := CharacterBody3D.new()
	p1.add_to_group("team_1")
	p1.global_position = Vector3(0, 0.5, 10)
	root.add_child(p1)
	var p2 := CharacterBody3D.new()
	p2.add_to_group("team_2")
	p2.global_position = Vector3(20, 0.5, 12)
	root.add_child(p2)

	# Stub-менеджер: минимальный API, который читает судья.
	var mgr := _StubManager.new()
	mgr.field_length = 52.5
	mgr.field_width = 34.0
	root.add_child(mgr)

	var ref: MatchReferee = load("res://scripts/match/match_referee.gd").new()
	root.add_child(ref)
	ref.setup(mgr, ball, 2)
	ref.restart_awarded.connect(func(t, tm, sp): _got = {"t": t, "tm": tm, "sp": sp})

	# Мяч касался team_1, ушёл за боковую (+X).
	ball.set_dribbler(p1)   # last_touch = p1 (team_1)
	ball.release_dribble()
	ball.global_position = Vector3(35.0, 0.11, 12.0)

	ok = _expect(ref.state() == MatchReferee.State.LIVE, "старт LIVE") and ok
	ref.tick()

	ok = _expect(_got.has("t"), "restart_awarded эмитнут") and ok
	if _got.has("t"):
		ok = _expect(_got["t"] == RefereeLogic.Restart.THROW_IN, "тип = THROW_IN") and ok
		ok = _expect(_got["tm"] == 2, "исполняет team_2") and ok
		ok = _expect(is_equal_approx((_got["sp"] as Vector3).x, 34.0), "точка на боковой x=34") and ok
	# Интерим-заглушка: мяч поставлен на точку, владение у ближайшего team_2 (p2).
	ok = _expect(ball.dribbler == p2, "владение отдано team_2") and ok
	ok = _expect(ref.state() == MatchReferee.State.LIVE, "после award снова LIVE") and ok

	if ok:
		print("CHECK PASS: referee_flow")
		quit(0)
	else:
		print("CHECK FAIL: referee_flow")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond

# Stub-менеджер: судья читает только эти члены/методы.
class _StubManager extends Node:
	var field_length: float
	var field_width: float
	func is_celebrating() -> bool: return false
	func is_penalty_active() -> bool: return false
	func is_free_kick_active() -> bool: return false
	func is_corner_active() -> bool: return false
	func is_goal_kick_active() -> bool: return false
	func is_throw_in_active() -> bool: return false
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_referee_flow.gd"`
Expected: FAIL/parse error — `MatchReferee` ещё не существует.

- [ ] **Step 3: Реализовать `MatchReferee`**

Create `scripts/match/match_referee.gd`:

```gdscript
class_name MatchReferee
extends Node
## Судья v1 (Этап 0). Автомат LIVE/DEAD. Детектит выход мяча за линии (BoundaryLogic),
## разрешает рестарт (RefereeLogic), эмитит сигналы. Интерим-режим detect+award: пока настоящих
## ИИ-стандартов нет, рестарт разрешается заглушкой — мяч на точку, владение исполняющей команде,
## снова LIVE, без церемонии. Гол/фол пробрасываются извне (менеджером).

signal restart_awarded(restart_type: int, team: int, spot: Vector3)
signal foul_called(spot: Vector3, team: int)

enum State { LIVE = 0, DEAD = 1 }

var _manager: Node
var _ball: Node
var _team_defending_neg: int = 2
var _state: int = State.LIVE

func setup(manager: Node, ball: Node, team_defending_neg: int) -> void:
	_manager = manager
	_ball = ball
	_team_defending_neg = team_defending_neg

func state() -> int:
	return _state

## Тик детекта открытой игры (зовётся из match_manager._physics_process, когда НЕ идёт
## сет-пис/празднование). Только в LIVE, только при валидном last_touch.
func tick() -> void:
	if _state != State.LIVE:
		return
	if _ball == null or not is_instance_valid(_ball):
		return
	if _ball.has_method(&"is_caught") and _ball.is_caught():
		return   # мяч в руках вратаря — не выход за линию
	var lt: Node = _ball.last_touch
	if lt == null or not is_instance_valid(lt):
		return   # некому атрибутировать — не судим (напр. до первого касания)
	var exit := BoundaryLogic.classify(_ball.global_position,
		_manager.field_length, _manager.field_width,
		FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.BALL_RADIUS)
	if exit == BoundaryLogic.Exit.NONE:
		return
	_award_ball_out(exit, lt)

func _award_ball_out(exit: int, last_touch: Node) -> void:
	var lt_team := 1 if last_touch.is_in_group("team_1") else 2
	var res := RefereeLogic.ball_out_restart(exit, lt_team, _team_defending_neg)
	var spot := _spot_for(res["restart"], exit)
	_state = State.DEAD
	restart_awarded.emit(res["restart"], res["team"], spot)
	_interim_award(res["team"], spot)
	_state = State.LIVE

## Точка рестарта по типу и стороне выхода.
func _spot_for(restart: int, exit: int) -> Vector3:
	var hl: float = _manager.field_length
	var hw: float = _manager.field_width
	var r := FootballConstants.BALL_RADIUS
	match restart:
		RefereeLogic.Restart.THROW_IN:
			return BoundaryLogic.throw_in_spot(_ball.global_position, hw, r)
		RefereeLogic.Restart.CORNER:
			return BoundaryLogic.corner_spot(_ball.global_position, hl, hw, exit, FootballConstants.CORNER_INSET, r)
		RefereeLogic.Restart.GOAL_KICK:
			return BoundaryLogic.goal_kick_spot(exit, hl, FootballConstants.GOAL_AREA_DEPTH, r)
		_:
			return Vector3(0.0, r, 0.0)

## Интерим-заглушка: мяч на точку, владение ближайшему полевому исполняющей команды. БЕЗ
## церемонии/камеры. Заменяется настоящими контроллерами в Этапах 1–2.
func _interim_award(team: int, spot: Vector3) -> void:
	if _ball.has_method(&"release_dribble"):
		_ball.release_dribble()
	if _ball.has_method(&"clear_last_kicker"):
		_ball.clear_last_kicker()
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = spot + Vector3(0, FootballConstants.RESET_BALL_Y, 0)
	var group := "team_1" if team == 1 else "team_2"
	var nodes := get_tree().get_nodes_in_group(group)
	var positions: Array = []
	for n in nodes:
		positions.append((n as Node3D).global_position)
	var idx := RefereeLogic.select_taker(spot, positions)
	if idx >= 0 and _ball.has_method(&"set_dribbler"):
		_ball.set_dribbler(nodes[idx], true)

## Гол (зовёт менеджер из goal-area). Интерим: только сигнал/лог — сам кикофф пока = существующий
## _reset_ball менеджера (Этап 1 заменит настоящим кикоффом).
func report_goal() -> void:
	restart_awarded.emit(RefereeLogic.Restart.KICKOFF, 0, Vector3.ZERO)

## Фол подката (зовёт менеджер). Интерим: сигнал foul_called + restart_awarded, без запуска
## контроллера штрафного/пенальти (Этап 2). Заглушку владения НЕ делаем — фол-геометрия и
## расстановка сложнее аута, оставляем настоящему контроллеру.
func report_tackle_foul(foul_pos: Vector3, fouler: Node, fouled: Node) -> void:
	var fouler_team := 1 if fouler.is_in_group("team_1") else 2
	var fouled_team := 1 if fouled.is_in_group("team_1") else 2
	foul_called.emit(foul_pos, fouler_team)
	var res := RefereeLogic.foul_restart(foul_pos, fouler_team, fouled_team,
		_manager.field_length, _team_defending_neg,
		FootballConstants.PENALTY_AREA_DEPTH, FootballConstants.PENALTY_AREA_WIDTH * 0.5)
	restart_awarded.emit(res["restart"], res["team"], foul_pos)
```

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_referee_flow.gd"`
Expected: `CHECK PASS: referee_flow`, exit 0.

- [ ] **Step 5: Коммит**

```bash
git add scripts/match/match_referee.gd tests/check_referee_flow.gd
git commit -m "feat(referee): MatchReferee node — LIVE/DEAD, signals, interim detect+award"
```

---

## Task 5: Отодвинуть границы наружу (константы)

**Files:**
- Modify: `scripts/data/football_constants.gd` (после секции MATCH, ~строка 174)
- Modify: `scripts/match/match_manager.gd:568-583` (`_setup_boundaries`)

**Interfaces:**
- Produces: `FootballConstants.BOUNDARY_MARGIN_Z`, `FootballConstants.BOUNDARY_MARGIN_X`.

- [ ] **Step 1: Добавить константы**

В `scripts/data/football_constants.gd` после строки `const RESET_BALL_Y := 0.5` (строка 173) добавить:

```gdscript

# Отступ стен-границ НАРУЖУ от линий поля: мяч должен успеть ПОЛНОСТЬЮ пересечь линию (для
# детекта аута/лицевой судьёй) до того, как упрётся в стену и отскочит. Было 4.0 (Z) / 2.0 (X).
const BOUNDARY_MARGIN_Z := 8.0
const BOUNDARY_MARGIN_X := 8.0
```

- [ ] **Step 2: Использовать их в `_setup_boundaries`**

В `scripts/match/match_manager.gd` заменить строки 571 и 575:

```gdscript
	var wall_extra := 4.0
```
→
```gdscript
	var wall_extra := FootballConstants.BOUNDARY_MARGIN_Z
```
и
```gdscript
	var side_extra := 2.0
```
→
```gdscript
	var side_extra := FootballConstants.BOUNDARY_MARGIN_X
```

- [ ] **Step 3: Валидация сцены матча**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: сцена грузится; вывод ошибок — только baseline-категории из Global Constants (без НОВЫХ категорий). Стены теперь на ±60.5 (Z) / ±42 (X).

- [ ] **Step 4: Коммит**

```bash
git add scripts/data/football_constants.gd scripts/match/match_manager.gd
git commit -m "feat(field): widen boundary walls to give referee line-cross detection room"
```

---

## Task 6: Проводка судьи в `match_manager` (инстанс, тик, касание, гол)

**Files:**
- Modify: `scripts/match/match_manager.gd` (объявление поля ~строка 15; `_ready` ~строка 161; `_physics_process` ~строка 999; `_on_ball_collision` ~строка 1974; goal-closure ~строка 504)

**Interfaces:**
- Consumes: `MatchReferee` (Task 4), `ball.note_touch` (Task 1).
- Produces: `match_manager._referee: MatchReferee` (доступен другим системам позже).

- [ ] **Step 1: Объявить поле судьи**

В `scripts/match/match_manager.gd` рядом с другими контроллерами (после `var field_width`, строка 16) добавить:

```gdscript
var _referee: MatchReferee
```

- [ ] **Step 2: Заинстанцировать и настроить судью в `_ready`**

В `_ready`, после блока `_action_executor` (после строки 164 `_action_executor.setup(self, ball)`), добавить:

```gdscript
	_referee = MatchReferee.new()
	add_child(_referee)
	# team_defending_neg: команда, защищающая ворота на -Z (там стоит _keeper). Выводим из его
	# группы, чтобы не хардкодить team_1/team_2.
	var tdn := 2 if (_keeper != null and _keeper.is_in_group("team_2")) else 1
	_referee.setup(self, ball, tdn)
```

- [ ] **Step 3: Тикать детект в открытой игре**

В `_physics_process`, заменить блок вокруг строк 999-1000 (`_handle_dribbling()` / `_handle_player_input(delta)` в конце цепочки сет-пис-гейтов). Найти:

```gdscript
	_handle_dribbling()
	_handle_player_input(delta)
```
(строки 999-1000, ветка после всех `_*_active`/`_try_fire_queue` return-ов) и вставить ПЕРЕД `_handle_dribbling()`:

```gdscript
	if _referee != null and not _celebrating:
		_referee.tick()
```

- [ ] **Step 4: Писать касание при контакте мяч↔игрок**

В `_on_ball_collision` (строка 1974), в самом начале функции (перед `clear_curl`-блоком, после сигнатуры) добавить:

```gdscript
	if body is CharacterBody3D and (body.is_in_group("team_1") or body.is_in_group("team_2")) \
			and ball.has_method(&"note_touch"):
		ball.note_touch(body)
```

Это покрывает блок/рикошет/контакт с вратарём (парирование) — во всех случаях касавшийся = `body`.

- [ ] **Step 5: Прокинуть гол в судью**

В goal-closure `_setup_goals` (строка 504-518), внутри `if body == ball and not _celebrating:` блока, после `_celebrating = true` (строка 505) добавить:

```gdscript
		if _referee != null:
			_referee.report_goal()
```

- [ ] **Step 6: Валидация сцены матча**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: сцена грузится; только baseline-категории ошибок, без новых. Судья инстанцируется без ошибок парсинга/nil-доступа.

- [ ] **Step 7: Прогнать все headless-тесты этого плана (регрессия)**

Run последовательно (каждый ожидает `CHECK PASS`, exit 0):
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ball_touch.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_boundary_logic.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_referee_logic.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_referee_flow.gd"
```
Expected: четыре `CHECK PASS`.

- [ ] **Step 8: Ручная проверка в игре (фил — headless не драйвит)**

Запустить игру (Godot без `--headless`). Проверить сценарии:
- Выбить мяч за боковую линию → мяч ставится на боковую, владение переходит к другой команде (интерим-заглушка, без церемонии).
- Пробить мимо ворот за лицевую после своего касания → мяч ставится на линию вратарской (удар от ворот) или в угол (угловой), в зависимости от того, кто касался последним.
- Забить гол → празднование и `_reset_ball` работают как раньше (судья только логирует кикофф-сигнал, поведение не изменилось).

- [ ] **Step 9: Коммит**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(referee): wire MatchReferee into match_manager — tick, touch, goal signal"
```

---

## Self-Review

**Spec coverage (кусок A роадмапа, Этап 0 пп. 1, 2, 4):**
- Отодвинуть границы + детект пересечения линии → Task 5 (стены) + Task 2/4 (детект `classify` + тик).
- Честный трекинг касаний (замена чистимого `last_kicker`) → Task 1.
- `MatchReferee` v1: автомат LIVE/DEAD → Task 4; детект аут/лицевая → Task 2+4; гол → Task 4/6; фол подката → Task 4 (`report_tackle_foul`); две чистые функции разрешения → Task 3 (`ball_out_restart`/`foul_restart` + `select_taker`); сигналы → Task 4; интерим detect+award → Task 4 (`_interim_award`) + Task 6 (тик).
- **Вне скоупа этого плана (в кусок B, отдельный план):** шов `SetPieceIntent`/презентация (Этап 0 п.3), фактический ВЫЗОВ `report_tackle_foul` из tackle-recovery (требует переактивации фол-правила в `_tackle_recover`, где сейчас `_tackle_clean=true` безусловно — это правило-логика штрафного, естественнее в плане куска B/Этапа 2 вместе с ИИ-штрафным). `report_tackle_foul` в этом плане реализован и протестирован как API, но проводка его вызова отложена — отмечено явно, не дыра.

**Placeholder scan:** плейсхолдеров нет — каждый шаг содержит полный код/команду с ожидаемым выводом.

**Type consistency:** `Restart`/`Exit` enum-значения консистентны между Task 2/3/4. `ball_out_restart`/`foul_restart` возвращают `{restart, team}` везде одинаково. `setup(manager, ball, team_defending_neg)` совпадает в Task 4 и Task 6. `select_taker(spot, positions: Array) -> int` — одна сигнатура. `note_touch(node)` — одна сигнатура (Task 1) и один call-site паттерн (Task 6).

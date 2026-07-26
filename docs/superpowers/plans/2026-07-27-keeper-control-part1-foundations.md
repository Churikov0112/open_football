# Управляемый вратарь — План 1: Фундамент — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заложить headless-тестируемый фундамент управляемого вратаря: флаг бэк-паса на мяче, фикс over-rush вратаря (кламп штрафной), чистая математика `KeeperPlayLogic` и шов `KeeperHandsIntent` (Human/AI). Интеграция (HANDS/OUTFIELD-состояния, раздача, управление) — в Плане 2.

**Architecture:** Всё в этом плане — либо чистые функции/данные (тестируются напрямую), либо точечные правки существующих файлов. Ни одно изменение не меняет поведение вратаря в игре (флаг пока не читается, интенты пока не подключены) — КРОМЕ фикса over-rush (Задача 3), у которого есть видимый эффект. Полностью совместимо, сцена грузится на каждом шаге.

**Tech Stack:** Godot 4.7 / GDScript. Тесты — headless `tests/check_*.gd` (extends SceneTree, печатают `CHECK PASS`/`CHECK FAIL`, exit 0/1).

## Global Constraints

- **Нет lint/CI** — валидация только Godot headless. Экзе: `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`.
- **Godot часто стартует >120с** — headless-прогоны в фоне, не чейнить несколько в одну команду.
- **Baseline-категории ошибок сцены** (НЕ регрессии, дифф по категории): `!is_inside_tree()`, `states.has(p_name)`, transition-duplicate, `Cannot get class 'WorldEnvironment3D'`.
- **Чистые `*_logic.gd` НИКОГДА не читают `FootballConstants`** — тюнинг параметрами (как `PassSystem`/`KeeperLogic`/`PenaltyLogic`).
- **Тип-геттер-гочи:** `var x := node.method()` на статически-типизированной переменной, где метода нет в базовом типе, не компилится; в тестах `_mm` типа `Node` — все `_mm.foo()` уже динамические (Variant), это ок.
- Отвечать/комментировать по-русски. Коммиты подписывать `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Файловая структура

- **Modify:** `scripts/ball/ball_controller.gd` — поле `_pass_from_team` + `note_pass_from()` + `pass_from_team()`; снятие флага в `set_dribbler`/`block_in_flight`.
- **Modify:** `scripts/match/action_executor.gd` — `fire_pass()` тегает мяч командой пасующего.
- **Create:** `scripts/match/keeper_play_logic.gd` (`class_name KeeperPlayLogic extends Object`) — чистая математика раздачи/клампа.
- **Modify:** `scripts/ai/keeper_ai.gd` — `_position` клампит цель в штрафную (фикс over-rush) через `KeeperPlayLogic.clamp_to_penalty_area`.
- **Create:** `scripts/match/keeper_hands_intent.gd` (`class_name KeeperHandsIntent`), `human_keeper_hands_intent.gd`, `ai_keeper_hands_intent.gd`.
- **Create tests:** `tests/check_ball_pass_flag.gd`, `tests/check_keeper_play_logic.gd`, `tests/check_keeper_hands_intent.gd`.

---

### Task 1: Флаг бэк-паса на мяче

Мяч помнит, какая команда его **намеренно** отдала пасом; флаг снимается любым касанием/блоком. Пока НИКТО его не читает — это инфраструктура под Задачу-консьюмер в Плане 2. Тестируется в изоляции.

**Files:**
- Modify: `scripts/ball/ball_controller.gd` (поле + методы; снятие в `set_dribbler` ~86, `block_in_flight` ~174)
- Modify: `scripts/match/action_executor.gd` (`fire_pass` ~232, точка `_ball.launch(launch_vel)` ~319)
- Test: `tests/check_ball_pass_flag.gd` (создать)

**Interfaces:**
- Produces: `Ball.note_pass_from(team: StringName) -> void`, `Ball.pass_from_team() -> StringName` (пусто `&""` = нет намеренного паса).
- Consumes: `_ball.launch()` уже вызывается в `fire_pass`; `_manager` для группы пасующего.

- [ ] **Step 1: Написать падающий тест `tests/check_ball_pass_flag.gd`**

```gdscript
extends SceneTree
## Флаг бэк-паса: note_pass_from ставит; set_dribbler и block_in_flight снимают.

func _initialize() -> void:
	var ball = load("res://scenes/ball.tscn").instantiate() if ResourceLoader.exists("res://scenes/ball.tscn") else null
	if ball == null:
		# Мяч создаётся в match.tscn; берём оттуда.
		var mm = load("res://scenes/match.tscn").instantiate()
		root.add_child(mm)
		ball = mm.get_node("Ball")
	_run(ball)

func _run(ball) -> void:
	var ok := true
	if ball.pass_from_team() != &"":
		print("CHECK FAIL: начальный флаг не пуст"); ok = false
	ball.note_pass_from(&"team_1")
	if ball.pass_from_team() != &"team_1":
		print("CHECK FAIL: note_pass_from не поставил"); ok = false
	ball.block_in_flight()
	if ball.pass_from_team() != &"":
		print("CHECK FAIL: block_in_flight не снял флаг"); ok = false
	ball.note_pass_from(&"team_2")
	ball.set_dribbler(null)   # любой трап/касание снимает
	if ball.pass_from_team() != &"":
		print("CHECK FAIL: set_dribbler не снял флаг"); ok = false
	if ok:
		print("CHECK PASS: back-pass flag set/clear")
		quit(0)
	else:
		quit(1)
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `& "...Godot...console.exe" --path "...OpenFootball" --headless -s "res://tests/check_ball_pass_flag.gd"`
Expected: FAIL — `pass_from_team`/`note_pass_from` ещё не существуют (`Invalid call`).

- [ ] **Step 3: Добавить поле и методы в `ball_controller.gd`**

Рядом с другими полями состояния добавить:
```gdscript
var _pass_from_team: StringName = &""   # команда намеренного паса (бэк-пас правило); пусто = нет
```
Рядом с `note_kicker` добавить методы:
```gdscript
## Пометить мяч намеренным пасом команды (для правила бэк-паса вратаря). Ставится в fire_pass.
func note_pass_from(team: StringName) -> void:
	_pass_from_team = team

func pass_from_team() -> StringName:
	return _pass_from_team
```

- [ ] **Step 4: Снимать флаг в `set_dribbler` и `block_in_flight`**

В начале тела `func set_dribbler(node: Node3D, force: bool = false) -> void:` добавить первой строкой:
```gdscript
	_pass_from_team = &""   # любой трап/ловля/дриблинг снимает метку намеренного паса
```
В начале тела `func block_in_flight() -> void:` добавить первой строкой:
```gdscript
	_pass_from_team = &""   # отскок/блок в полёте — НЕ пас (снимаем метку)
```

- [ ] **Step 5: `fire_pass` тегает мяч командой пасующего**

В `scripts/match/action_executor.gd`, в `fire_pass(...)`, прямо перед `_ball.launch(launch_vel)` (строка ~319) добавить:
```gdscript
	if _ball.has_method(&"note_pass_from"):
		_ball.note_pass_from(&"team_1" if player.is_in_group("team_1") else &"team_2")
```

- [ ] **Step 6: Прогнать — убедиться, что проходит**

Run (в фоне): та же команда.
Expected: `CHECK PASS: back-pass flag set/clear`

- [ ] **Step 7: Commit**

```bash
git add scripts/ball/ball_controller.gd scripts/match/action_executor.gd tests/check_ball_pass_flag.gd
git commit -m "feat(ball): флаг намеренного паса (_pass_from_team) для правила бэк-паса вратаря"
```

---

### Task 2: `KeeperPlayLogic` — чистая математика раздачи и клампа

Все геометрические функции раздачи вратаря + кламп штрафной. Чистые (не читают `FootballConstants`), headless-тестируемо. Пока consumer'ов нет (кроме Задачи 3, использующей кламп) — Плана 2.

**Files:**
- Create: `scripts/match/keeper_play_logic.gd`
- Test: `tests/check_keeper_play_logic.gd` (создать)

**Interfaces:**
- Produces:
  - `KeeperPlayLogic.clamp_to_penalty_area(pos: Vector3, goal_line_z: float, into: float, pa_depth: float, pa_half_width: float) -> Vector3`
  - `KeeperPlayLogic.select_hand_target(keeper_pos: Vector3, aim_dir: Vector3, mate_positions: Array, charge: float, near_dist: float, far_dist: float) -> int`
  - `KeeperPlayLogic.clear_center_vector(into: float, speed: float, lift: float) -> Vector3`
  - `KeeperPlayLogic.directed_clear_vector(aim_flat: Vector3, charge: float, min_speed: float, max_speed: float, lift: float) -> Vector3`

- [ ] **Step 1: Написать падающий тест `tests/check_keeper_play_logic.gd`**

```gdscript
extends SceneTree
## KeeperPlayLogic: кламп штрафной, автонаведение руки, векторы выносов.

func _initialize() -> void:
	var ok := true
	# --- clamp_to_penalty_area: точка вне бокса → на границу; внутри → без изменений ---
	# Ворота на -52.5, в поле into=+1, глубина 16.5, полуширина 20.16.
	var inside := KeeperPlayLogic.clamp_to_penalty_area(Vector3(5, 0.5, -50.0), -52.5, 1.0, 16.5, 20.16)
	if not inside.is_equal_approx(Vector3(5, 0.5, -50.0)):
		print("CHECK FAIL: внутренняя точка сдвинута: ", inside); ok = false
	var deep := KeeperPlayLogic.clamp_to_penalty_area(Vector3(0, 0.5, -20.0), -52.5, 1.0, 16.5, 20.16)
	# rel = (-20 - -52.5)*1 = 32.5 > 16.5 → z = -52.5 + 16.5 = -36.0
	if absf(deep.z - (-36.0)) > 0.01:
		print("CHECK FAIL: глубина не заклампилась: ", deep); ok = false
	var wide := KeeperPlayLogic.clamp_to_penalty_area(Vector3(30, 0.5, -50.0), -52.5, 1.0, 16.5, 20.16)
	if absf(wide.x - 20.16) > 0.01:
		print("CHECK FAIL: ширина не заклампилась: ", wide); ok = false

	# --- select_hand_target: низкий заряд → ближний, высокий → дальний ---
	var mates := [Vector3(3, 0.5, -50), Vector3(20, 0.5, -50)]   # ближний [0], дальний [1]
	var aim := Vector3(1, 0, 0)
	var near_pick := KeeperPlayLogic.select_hand_target(Vector3(0, 0.5, -50), aim, mates, 0.0, 5.0, 25.0)
	if near_pick != 0:
		print("CHECK FAIL: низкий заряд не выбрал ближнего: ", near_pick); ok = false
	var far_pick := KeeperPlayLogic.select_hand_target(Vector3(0, 0.5, -50), aim, mates, 1.0, 5.0, 25.0)
	if far_pick != 1:
		print("CHECK FAIL: высокий заряд не выбрал дальнего: ", far_pick); ok = false

	# --- clear_center_vector: горизонталь по into, +лифт ---
	var cc := KeeperPlayLogic.clear_center_vector(1.0, 20.0, 5.0)
	if absf(cc.z - 20.0) > 0.01 or absf(cc.y - 5.0) > 0.01 or absf(cc.x) > 0.01:
		print("CHECK FAIL: clear_center_vector: ", cc); ok = false

	# --- directed_clear_vector: по aim, скорость по заряду, +лифт ---
	var dc := KeeperPlayLogic.directed_clear_vector(Vector3(1, 0, 0), 1.0, 8.0, 24.0, 4.0)
	if absf(dc.x - 24.0) > 0.01 or absf(dc.y - 4.0) > 0.01:
		print("CHECK FAIL: directed_clear_vector: ", dc); ok = false

	if ok:
		print("CHECK PASS: KeeperPlayLogic (clamp/select/clear/directed)")
		quit(0)
	else:
		quit(1)
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `& "...Godot...console.exe" --path "...OpenFootball" --headless -s "res://tests/check_keeper_play_logic.gd"`
Expected: FAIL — `KeeperPlayLogic` не существует.

- [ ] **Step 3: Создать `scripts/match/keeper_play_logic.gd`**

```gdscript
class_name KeeperPlayLogic
extends Object
## Чистая математика раздачи/позиции вратаря. НИКОГДА не читает FootballConstants — тюнинг параметрами.

## Кламп позиции в штрафную площадь. into = знак в поле от линии ворот (+1 если ворота на -Z).
## X ограничивается ±pa_half_width; глубина (rel от линии) — [0, pa_depth].
static func clamp_to_penalty_area(pos: Vector3, goal_line_z: float, into: float, pa_depth: float, pa_half_width: float) -> Vector3:
	var out := pos
	out.x = clampf(pos.x, -pa_half_width, pa_half_width)
	var rel := (pos.z - goal_line_z) * into
	rel = clampf(rel, 0.0, pa_depth)
	out.z = goal_line_z + into * rel
	return out

## Автонаведение руки: индекс своего для раската/броска. Целевой банд дистанции = lerp(near,far,charge);
## скор = совпадение направления с прицелом − близость к банду. -1 если кандидатов нет.
static func select_hand_target(keeper_pos: Vector3, aim_dir: Vector3, mate_positions: Array, charge: float, near_dist: float, far_dist: float) -> int:
	var want := lerpf(near_dist, far_dist, clampf(charge, 0.0, 1.0))
	var best := -1
	var best_score := -INF
	for i in mate_positions.size():
		var to: Vector3 = mate_positions[i] - keeper_pos
		to.y = 0.0
		var d := to.length()
		if d < 0.01:
			continue
		var dir := to / d
		var dot := dir.dot(aim_dir)
		var dist_pen := absf(d - want) / maxf(far_dist, 0.01)
		var score := dot - dist_pen
		if score > best_score:
			best_score = score
			best = i
	return best

## Вынос к центру поля: горизонталь вдоль into (к средней линии), фикс скорость + лифт.
static func clear_center_vector(into: float, speed: float, lift: float) -> Vector3:
	return Vector3(0.0, 0.0, into) * speed + Vector3.UP * lift

## Направленный вынос: горизонталь по aim_flat, скорость по заряду, + лифт. Пустой aim → вперёд (+Z).
static func directed_clear_vector(aim_flat: Vector3, charge: float, min_speed: float, max_speed: float, lift: float) -> Vector3:
	var dir := Vector3(aim_flat.x, 0.0, aim_flat.z)
	if dir.length() < 0.01:
		dir = Vector3(0.0, 0.0, 1.0)
	dir = dir.normalized()
	var speed := lerpf(min_speed, max_speed, clampf(charge, 0.0, 1.0))
	return dir * speed + Vector3.UP * lift
```

- [ ] **Step 4: Прогнать — убедиться, что проходит**

Run (в фоне): та же команда.
Expected: `CHECK PASS: KeeperPlayLogic (clamp/select/clear/directed)`

- [ ] **Step 5: Commit**

```bash
git add scripts/match/keeper_play_logic.gd tests/check_keeper_play_logic.gd
git commit -m "feat(keeper): KeeperPlayLogic — чистая математика раздачи/клампа штрафной"
```

---

### Task 3: Фикс over-rush — кламп цели вратаря в штрафную

AI-вратарь больше не выбегает за штрафную на шальной мяч: цель позиции в `_position` клампится через `KeeperPlayLogic.clamp_to_penalty_area`. Видимый эффект в игре (в отличие от Задач 1/2).

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (`_position`, блок вычисления `target` ~161-179)
- Проверка: baseline-валидация сцены + существующие keeper-тесты.

**Interfaces:**
- Consumes: `KeeperPlayLogic.clamp_to_penalty_area` (Задача 2); `FootballConstants.PENALTY_AREA_DEPTH`, `FootballConstants.PENALTY_AREA_WIDTH`.

- [ ] **Step 1: Заклампить цель позиции в штрафную**

В `scripts/ai/keeper_ai.gd`, в `_position`, сразу ПОСЛЕ блока, вычисляющего `target` (после строки `target.z = goal_line_z + into * 0.5` внутри `if not (ball.is_flight() ...)`), но ДО `var to := target - _body.global_position`, добавить:
```gdscript
	# База: вратарь-ИИ не покидает штрафную (фикс over-rush на шальной мяч рядом с боксом).
	target = KeeperPlayLogic.clamp_to_penalty_area(target, goal_line_z, into,
		FootballConstants.PENALTY_AREA_DEPTH, FootballConstants.PENALTY_AREA_WIDTH * 0.5)
```
(Переменная `into` уже объявлена выше в `_position`.)

- [ ] **Step 2: Baseline-валидация сцены**

Run (в фоне): `& "...Godot...console.exe" --path "...OpenFootball" --headless --quit-after 2 res://scenes/match.tscn 2>&1 | (фильтр baseline)`
Expected: только baseline-категории, новых `SCRIPT ERROR`/`Parse Error` нет.

- [ ] **Step 3: Прогнать keeper-тесты (не сломан сейв)**

Run (в фоне, по одному): `check_keeper_logic.gd`, `check_keeper_clear.gd`, `check_penalty_keeper_line.gd`, `check_two_keepers.gd`.
Expected: `CHECK PASS` (учесть флейки `check_keeper_clear` — гнать 2-3×, см. Global Constraints).

- [ ] **Step 4: Commit**

```bash
git add scripts/ai/keeper_ai.gd
git commit -m "fix(keeper): AI-вратарь не выбегает за штрафную (кламп цели позиции)"
```

---

### Task 4: Шов `KeeperHandsIntent` + Human/AI реализации

Интерфейс «вратарь с мячом в руках» + две реализации. Пока никто не читает (consumer — keeper_ai в Плане 2). Тестируется фейковым сабклассом (Human) и детерминизмом по времени (AI), как `check_keeper_intent.gd`.

**Files:**
- Create: `scripts/match/keeper_hands_intent.gd`, `scripts/match/human_keeper_hands_intent.gd`, `scripts/match/ai_keeper_hands_intent.gd`
- Test: `tests/check_keeper_hands_intent.gd` (создать)

**Interfaces:**
- Produces:
  - `KeeperHandsIntent` c `enum Action { NONE, HAND, CLEAR_CENTER, CLEAR_DIRECTED, DROP }`, методы `move_axis() -> Vector2`, `aim_axis() -> Vector2`, `held_action() -> int`.
  - `HumanKeeperHandsIntent.new(cfg: Dictionary)` — ключи `move_lat`/`move_vert`/`aim_lat`/`aim_vert` (пары действий), `hand`/`clear_center`/`clear_directed`/`drop` (действия-кнопки).
  - `AIKeeperHandsIntent.new(think_time: float)` — после паузы возвращает `CLEAR_CENTER`.

- [ ] **Step 1: Написать падающий тест `tests/check_keeper_hands_intent.gd`**

```gdscript
extends SceneTree
## KeeperHandsIntent: HumanKeeperHandsIntent (фейк-ввод через сабкласс), AIKeeperHandsIntent (тайминг).

# Фейк Human: скриптуем "зажатые" действия и оси без реального Input.
class FakeHuman extends HumanKeeperHandsIntent:
	var held := {}
	var axes := {}
	func _pressed(a: StringName) -> bool:
		return held.get(a, false)
	func _axis(neg: StringName, pos: StringName) -> float:
		return float(axes.get(pos, 0.0)) - float(axes.get(neg, 0.0))

# Фейк AI: подменяем время.
class FakeAI extends AIKeeperHandsIntent:
	var t := 0
	func _now_msec() -> int:
		return t

func _initialize() -> void:
	var ok := true
	var cfg := {
		"move_lat": [&"ml", &"mr"], "move_vert": [&"mu", &"md"],
		"aim_lat": [&"ml", &"mr"], "aim_vert": [&"mu", &"md"],
		"hand": &"k_hand", "clear_center": &"k_cc", "clear_directed": &"k_cd", "drop": &"k_drop",
	}
	var h := FakeHuman.new(cfg)
	if h.held_action() != KeeperHandsIntent.Action.NONE:
		print("CHECK FAIL: пустой held_action не NONE"); ok = false
	h.held = {&"k_hand": true}
	if h.held_action() != KeeperHandsIntent.Action.HAND:
		print("CHECK FAIL: HAND не считался"); ok = false
	h.held = {&"k_drop": true}
	if h.held_action() != KeeperHandsIntent.Action.DROP:
		print("CHECK FAIL: DROP не считался"); ok = false
	h.held = {}
	h.axes = {&"mr": 1.0}
	if absf(h.move_axis().x - 1.0) > 0.01:
		print("CHECK FAIL: move_axis.x != 1: ", h.move_axis()); ok = false

	var a := FakeAI.new(0.5)   # think 0.5с
	a.t = 0
	if a.held_action() != KeeperHandsIntent.Action.NONE:
		print("CHECK FAIL: AI до паузы не NONE"); ok = false
	a.t = 600   # >0.5с
	if a.held_action() != KeeperHandsIntent.Action.CLEAR_CENTER:
		print("CHECK FAIL: AI после паузы не CLEAR_CENTER"); ok = false

	if ok:
		print("CHECK PASS: KeeperHandsIntent (human fake + ai timing)")
		quit(0)
	else:
		quit(1)
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `& "...Godot...console.exe" --path "...OpenFootball" --headless -s "res://tests/check_keeper_hands_intent.gd"`
Expected: FAIL — классы не существуют.

- [ ] **Step 3: Создать базовый `scripts/match/keeper_hands_intent.gd`**

```gdscript
class_name KeeperHandsIntent
extends RefCounted
## Интерфейс «вратарь с мячом в руках»: движение в штрафной + выбор действия раздачи.
## Charge-as-timer владеет consumer (keeper_ai) — интент лишь сообщает зажатую кнопку.

enum Action { NONE, HAND, CLEAR_CENTER, CLEAR_DIRECTED, DROP }

func move_axis() -> Vector2:
	return Vector2.ZERO

func aim_axis() -> Vector2:
	return Vector2.ZERO

func held_action() -> int:
	return Action.NONE
```

- [ ] **Step 4: Создать `scripts/match/human_keeper_hands_intent.gd`**

```gdscript
class_name HumanKeeperHandsIntent
extends KeeperHandsIntent
## Human-реализация: тонкая обёртка над Input, config-driven (как HumanKickerIntent).
## Ввод через переопределяемые _pressed/_axis — headless-тест подменяет.

var _cfg: Dictionary

func _init(cfg: Dictionary) -> void:
	_cfg = cfg

func _pressed(a: StringName) -> bool:
	return Input.is_action_pressed(a)

func _axis(neg: StringName, pos: StringName) -> float:
	return Input.get_axis(neg, pos)

func move_axis() -> Vector2:
	var lat: Array = _cfg.get("move_lat", [])
	var vert: Array = _cfg.get("move_vert", [])
	var x := _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0
	var y := -_axis(vert[0], vert[1]) if vert.size() == 2 else 0.0
	return Vector2(x, y)

func aim_axis() -> Vector2:
	var lat: Array = _cfg.get("aim_lat", [])
	var vert: Array = _cfg.get("aim_vert", [])
	var x := _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0
	var y := -_axis(vert[0], vert[1]) if vert.size() == 2 else 0.0
	return Vector2(x, y)

## Приоритет при одновременном зажатии: HAND → CLEAR_CENTER → CLEAR_DIRECTED → DROP.
func held_action() -> int:
	if _pressed(_cfg.get("hand", &"")):
		return Action.HAND
	if _pressed(_cfg.get("clear_center", &"")):
		return Action.CLEAR_CENTER
	if _pressed(_cfg.get("clear_directed", &"")):
		return Action.CLEAR_DIRECTED
	if _pressed(_cfg.get("drop", &"")):
		return Action.DROP
	return Action.NONE
```
(`_pressed(&"")` вернёт false для незаданной кнопки — Godot `is_action_pressed(&"")` = false; в фейк-тесте `held.get(&"", false)` = false. Безопасно.)

- [ ] **Step 5: Создать `scripts/match/ai_keeper_hands_intent.gd`**

```gdscript
class_name AIKeeperHandsIntent
extends KeeperHandsIntent
## ИИ-реализация v1 (заглушка): пауза «обдумывания», затем всегда вынос к центру (CLEAR_CENTER).
## move/aim = ZERO (не бегает). Апгрейд до полноценного решателя — позже, без правок keeper_ai.
## Время через переопределяемый _now_msec() (headless-тест без sleep).

var _start_msec: int
var _think_time: float

func _init(think_time: float) -> void:
	_think_time = think_time
	_start_msec = _now_msec()

func _now_msec() -> int:
	return Time.get_ticks_msec()

func held_action() -> int:
	if _now_msec() - _start_msec >= int(_think_time * 1000.0):
		return Action.CLEAR_CENTER
	return Action.NONE
```

- [ ] **Step 6: Прогнать — убедиться, что проходит**

Run (в фоне): та же команда.
Expected: `CHECK PASS: KeeperHandsIntent (human fake + ai timing)`

- [ ] **Step 7: Commit**

```bash
git add scripts/match/keeper_hands_intent.gd scripts/match/human_keeper_hands_intent.gd scripts/match/ai_keeper_hands_intent.gd tests/check_keeper_hands_intent.gd
git commit -m "feat(keeper): шов KeeperHandsIntent + Human/AI реализации"
```

---

## Self-Review (автора плана — проверено)

- **Покрытие спека (фундамент):** флаг бэк-паса (T1), `KeeperPlayLogic` clamp/select/clear/directed (T2), фикс over-rush (T3), шов `KeeperHandsIntent`+Human+AI (T4). Интеграция (HANDS/OUTFIELD, раздача-исполнение, 6с, диспетч, управление, InputMap, carry-бленд) — План 2/3, вне этого документа.
- **Плейсхолдеров нет** — весь код приведён.
- **Типы согласованы:** `pass_from_team()->StringName`, `note_pass_from(StringName)`, `KeeperPlayLogic.*` сигнатуры и `KeeperHandsIntent.Action` — используются одинаково в коде и тестах.

## После Плана 1

Следующий — **План 2 (Интеграция)**: HANDS/OUTFIELD-состояния `keeper_ai` (вход при ловле, чтение `KeeperHandsIntent`, движение в штрафной с клампом, исполнение раздачи A/X/B/Y через `KeeperPlayLogic`+существующие блоки, заряд, 6 сек), диспетч `_keeper_hands_dispatch` + передача `controlled_player` + голубой маркер + power-bar, консьюмер флага бэк-паса (приём → OUTFIELD), InputMap. Пишется по as-built после Плана 1. Затем **План 3** — carry-бленд верх/низ (`PlayerVisual.set_carry_pose`, bone-filter + fallback).

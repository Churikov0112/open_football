# Keeper Penalty Side-Step Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** В K-режиме пенальти вратарь до разбега бьющего ездит приставными шагами вдоль линии по стику, на старте разбега X-позиция замораживается, а направление прыжка выбирается стиком на контакте (как сейчас).

**Architecture:** Стик меняет смысл по фазе. Новый `KeeperIntent.step_lateral()` (база 0 → ИИ стоит; Human → stick.x) отдаёт боковое намерение в AIM. `keeper_ai._penalty_hold` интегрирует его в целевую X на линии (вместо жёсткого центра); `freeze_penalty_position()` стопорит на старте разбега. Момент коммита направления (`_struck_zone = dive_zone()` на контакте) НЕ меняется.

**Tech Stack:** Godot 4.7 / GDScript. Headless-тест — `tests/check_*.gd`.

## Global Constraints

- **Родитель уже в репо и работает:** `KeeperIntent`/`HumanKeeperIntent`/`AIKeeperIntent`, K-триггер, `penalty_controller._keeper_intent`, `keeper_ai.set_penalty_mode/_penalty_hold/begin_penalty_dive`.
- **Момент коммита направления НЕ трогать:** `penalty_controller._on_kicker_contact` строка `_struck_zone = _keeper_intent.dive_zone()` остаётся. Меняем только AIM-позиционирование + заморозку X.
- **ИИ-вратарь (P) не должен менять поведение:** `step_lateral()` базовый = 0 → `_penalty_target_x` держится в 0 → центр, как сейчас. `check_penalty_flow.gd` — регрессионная страховка, не трогать.
- **Гочи Godot (из прошлых планов):** после нового `class_name` — `--headless --import` отдельной командой перед `-s`-тестом. Здесь новых `class_name` нет (только методы у существующих) — импорт не обязателен, но безвреден.
- **Тест-раннер:** `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/<name>.gd"` → `CHECK PASS`, exit 0.
- **Валидация сцены:** `& "<godot>" --path "<repo>" --headless --quit-after 2 res://scenes/match.tscn`. Baseline-категории (не регрессии): `Condition "!is_inside_tree()"`, `Condition "states.has(p_name)"`, `Condition "transitions[i]..."`, `Cannot get class 'WorldEnvironment3D'`.

---

## File Structure

- **Modify** `scripts/match/keeper_intent.gd` — `step_lateral()` (база 0).
- **Modify** `scripts/match/human_keeper_intent.gd` — `step_lateral()` → `_axis(aim_lat)`.
- **Modify** `tests/check_keeper_intent.gd` — проверки `step_lateral`.
- **Modify** `scripts/data/football_constants.gd` — `KEEPER_PEN_STEP_SPEED`/`_MARGIN`.
- **Modify** `scripts/ai/keeper_ai.gd` — поля + `set_penalty_step`/`freeze_penalty_position`, интегратор в `_penalty_hold`, сброс в `set_penalty_mode`.
- **Modify** `scripts/match/penalty_controller.gd` — слать step в `_aim_update`, заморозку в `_fire`.

---

## Task 1: `step_lateral()` на KeeperIntent/HumanKeeperIntent + тест

**Files:**
- Modify: `scripts/match/keeper_intent.gd`, `scripts/match/human_keeper_intent.gd`
- Test: `tests/check_keeper_intent.gd`

**Interfaces:**
- Produces: `KeeperIntent.step_lateral() -> float` (база 0.0); `HumanKeeperIntent.step_lateral()` → `stick.x` (боковая ось `aim_lat` через `_axis`).

- [ ] **Step 1: Дополнить тест (падающая проверка step_lateral)**

В `tests/check_keeper_intent.gd`, перед блоком `# База KeeperIntent → CENTER.`, добавить:

```gdscript
	# step_lateral: Human отдаёт боковую ось стика; база = 0.
	f.ax_lat = 0.6
	f.ax_vert = 0.0
	ok = _expect(is_equal_approx(f.step_lateral(), 0.6), "HKI step_lateral = ax_lat") and ok
	ok = _expect(is_equal_approx(KeeperIntent.new().step_lateral(), 0.0), "база step_lateral = 0") and ok

```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_keeper_intent.gd"`
Expected: `CHECK FAIL` (или ошибка «nonexistent function step_lateral»).

- [ ] **Step 3: Добавить `step_lateral()` в базу**

В `scripts/match/keeper_intent.gd` после метода `dive_zone()` добавить:

```gdscript

## Желаемое боковое смещение вратаря по линии в фазе прицеливания (AIM), [-1..1]; 0 = стоять.
## Отдельно от dive_zone: позиционирование телом, а не выбор зоны прыжка.
func step_lateral() -> float:
	return 0.0
```

- [ ] **Step 4: Реализовать `step_lateral()` в `HumanKeeperIntent`**

В `scripts/match/human_keeper_intent.gd` после метода `dive_zone()` добавить:

```gdscript

func step_lateral() -> float:
	var lat: Array = _cfg.get("aim_lat", [])
	return _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0
```

- [ ] **Step 5: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_keeper_intent.gd"`
Expected: `CHECK PASS: keeper_intent`, exit 0.

- [ ] **Step 6: Коммит**

```bash
git add scripts/match/keeper_intent.gd scripts/match/human_keeper_intent.gd tests/check_keeper_intent.gd
git commit -m "feat(penalty): KeeperIntent.step_lateral (AIM lateral positioning intent)"
```

---

## Task 2: `keeper_ai` — приставные шаги вдоль линии + заморозка

**Files:**
- Modify: `scripts/data/football_constants.gd`
- Modify: `scripts/ai/keeper_ai.gd`

**Interfaces:**
- Produces: `keeper_ai.set_penalty_step(lateral: float)`, `keeper_ai.freeze_penalty_position()`; поля `_penalty_step_lateral`/`_penalty_target_x`/`_penalty_frozen`. Константы `FootballConstants.KEEPER_PEN_STEP_SPEED`/`KEEPER_PEN_STEP_MARGIN`.

- [ ] **Step 1: Добавить константы**

В `scripts/data/football_constants.gd`, в KEEPER-секции, после `const KEEPER_THROW_PEAK := 6.0`, добавить:

```gdscript
# Приставные шаги вратаря по линии до разбега бьющего (K-режим пенальти, см. keeper_ai._penalty_hold).
const KEEPER_PEN_STEP_SPEED := 3.0     # скорость бокового дрейфа по линии, м/с
const KEEPER_PEN_STEP_MARGIN := 0.5    # отступ от штанги, дальше не смещаться, м
```

- [ ] **Step 2: Объявить поля в `keeper_ai`**

В `scripts/ai/keeper_ai.gd` после строки `var _pen_struck: bool = false` добавить:

```gdscript
var _penalty_step_lateral: float = 0.0   # последнее боковое намерение от контроллера (AIM)
var _penalty_target_x: float = 0.0       # интегрированная цель X по линии
var _penalty_frozen: bool = false        # X зафиксирован (разбег начался)
```

- [ ] **Step 3: Добавить сеттеры**

В `scripts/ai/keeper_ai.gd` сразу перед `func begin_penalty_dive(zone: int) -> void:` добавить:

```gdscript
## AIM-позиционирование: контроллер каждый кадр шлёт боковое намерение стика (Human) или 0 (ИИ).
func set_penalty_step(lateral: float) -> void:
	_penalty_step_lateral = lateral

## Старт разбега бьющего: фиксируем X вратаря на линии (дальше стик = направление прыжка).
func freeze_penalty_position() -> void:
	_penalty_frozen = true

```

- [ ] **Step 4: Сбросить поля в `set_penalty_mode`**

В `set_penalty_mode`, в блоке `if on:`, после `_pen_struck = false` добавить:

```gdscript
		_penalty_step_lateral = 0.0
		_penalty_target_x = 0.0
		_penalty_frozen = false
```

- [ ] **Step 5: Интегрировать цель X в `_penalty_hold`**

В `_penalty_hold`, заменить блок вычисления цели (сейчас цель X = центр):

```gdscript
	var anchor_z := goal_line_z + into * 0.5
	var to := Vector3(-_body.global_position.x, 0.0, anchor_z - _body.global_position.z)
```
на:
```gdscript
	var anchor_z := goal_line_z + into * 0.5
	# До заморозки: цель X ползёт вбок по стику (приставные шаги), кламп в пределах створа.
	if not _penalty_frozen:
		_penalty_target_x += _penalty_step_lateral * FootballConstants.KEEPER_PEN_STEP_SPEED * delta
		var lim := FootballConstants.GOAL_WIDTH * 0.5 - FootballConstants.KEEPER_PEN_STEP_MARGIN
		_penalty_target_x = clampf(_penalty_target_x, -lim, lim)
	var to := Vector3(_penalty_target_x - _body.global_position.x, 0.0, anchor_z - _body.global_position.z)
```

- [ ] **Step 6: Валидация сцены**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: грузится (exit 0), только baseline-категории. (Поведение пока не изменится — методы ещё не вызываются контроллером.)

- [ ] **Step 7: Коммит**

```bash
git add scripts/data/football_constants.gd scripts/ai/keeper_ai.gd
git commit -m "feat(penalty): keeper side-step along line during AIM + position freeze"
```

---

## Task 3: Проводка в `penalty_controller` (слать step в AIM, замораживать в _fire)

**Files:**
- Modify: `scripts/match/penalty_controller.gd`

**Interfaces:**
- Consumes: `KeeperIntent.step_lateral()` (Task 1), `keeper_ai.set_penalty_step`/`freeze_penalty_position` (Task 2).

- [ ] **Step 1: Слать боковое намерение вратарю каждый AIM-кадр**

В `_aim_update`, сразу после сигнатуры `func _aim_update(delta: float) -> void:` (перед блоком смены ноги), добавить:

```gdscript
	# Позиционирование вратаря телом (K): человек стиком водит вратаря по линии; ИИ step_lateral()=0 → стоит.
	if _keeper_brain != null and _keeper_brain.has_method(&"set_penalty_step"):
		_keeper_brain.set_penalty_step(_keeper_intent.step_lateral())
```

- [ ] **Step 2: Заморозить позицию вратаря на старте разбега**

В `_fire`, после строки `_charging = false` (перед гейтом power_bar), добавить:

```gdscript
	# Старт разбега бьющего: фиксируем X вратаря на линии (дальше стик = направление прыжка, на контакте).
	if _keeper_brain != null and _keeper_brain.has_method(&"freeze_penalty_position"):
		_keeper_brain.freeze_penalty_position()
```

- [ ] **Step 3: Валидация сцены**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: грузится (exit 0), только baseline-категории.

- [ ] **Step 4: Регрессия — тесты**

Run последовательно (каждый ожидает `CHECK PASS`):
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_keeper_intent.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_penalty_flow.gd"
```
Expected: `CHECK PASS: keeper_intent`, `CHECK PASS: penalty flow (launched + released)`.

- [ ] **Step 5: Ручная проверка (фил — headless не драйвит)**

Запустить игру (Godot без `--headless`):
- **K** — до разбега вратарь ездит приставными шагами вдоль линии по стику (влево/вправо/стоп), не заходя за штангу. В момент начала анимации разбега боковое движение стопорится. Во время разбега стик выбирает направление прыжка; на контакте вратарь ныряет в выбранную зону из точки, где замёрз. Прогнать: (а) сместиться влево и нырнуть влево; (б) сместиться влево, но нырнуть вправо (поздняя смена стика во время разбега); (в) остаться в центре, нырнуть в угол.
- **P** (регрессия) — вратарь-ИИ стоит в центре до нырка, как было (`step_lateral()` базовый = 0, тело не смещается).

- [ ] **Step 6: Коммит**

```bash
git add scripts/match/penalty_controller.gd
git commit -m "feat(penalty): controller drives keeper side-step (AIM) + freeze at run-up"
```

---

## Self-Review

**Spec coverage:**
- `KeeperIntent.step_lateral()` (база 0, Human = stick.x) → Task 1.
- Приставные шаги вдоль линии + интегратор `_penalty_target_x` + кламп в створ → Task 2 (`_penalty_hold`).
- Заморозка X на старте разбега → Task 2 (`freeze_penalty_position`) + Task 3 (вызов в `_fire`).
- Сброс полей в `set_penalty_mode` → Task 2 Step 4.
- Проводка (слать step в AIM, замораживать в `_fire`) → Task 3.
- Константы `KEEPER_PEN_STEP_SPEED`/`_MARGIN` → Task 2 Step 1.
- Момент коммита направления (`_struck_zone = dive_zone()` на контакте) — НЕ трогается (подтверждено: ни в одной задаче нет правки `_on_kicker_contact`).
- **Вне скоупа (спек, «Границы»):** ИИ-раскачка (`step_lateral()` у `AIKeeperIntent` не переопределяется — база 0), тюнинг физики нырка, кросс-дайв. Задач нет — верно.

**Placeholder scan:** плейсхолдеров нет. Константы закреплены (3.0, 0.5).

**Type consistency:** `step_lateral() -> float` — база (Task 1), Human (Task 1), потребление `_keeper_intent.step_lateral()` (Task 3). `set_penalty_step(float)`/`freeze_penalty_position()` — определены (Task 2), вызваны через `has_method`-guard (Task 3). `_penalty_target_x`/`_penalty_step_lateral`/`_penalty_frozen` — объявлены (Task 2 Step 2), использованы (Task 2 Step 4/5). `KEEPER_PEN_STEP_SPEED`/`_MARGIN` — Task 2 Step 1 определяет, Step 5 использует.

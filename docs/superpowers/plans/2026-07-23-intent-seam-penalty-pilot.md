# Intent Seam — Penalty Pilot (Этап 0, кусок B, план B1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ввести per-actor шов «источник намерения» (`KickerIntent`) + двухуровневый профиль презентации (`SetPiecePresentation`) и перевести на них **один** контроллер — пенальти — чистым рефактором «поведение человека как было». Доказать паттерн end-to-end до раскатки на остальные 4 (план B2).

**Architecture:** `KickerIntent` (`RefCounted`, база с no-op дефолтами) — интерфейс, который контроллер потребляет вместо прямых `Input.*`. `HumanKickerIntent extends KickerIntent` — конфиг-driven обёртка над `Input` (какие оси/кнопки читать), с латч-логикой «кнопка старта заряда → коммит по её отпусканию»; читает ввод через переопределяемые методы (`_pressed`/`_just_pressed`/`_axis`), поэтому латч-логика headless-тестируема через фейковый сабкласс. `SetPiecePresentation` (`RefCounted`, конструктор `is_local_human`) — `owns_camera()`/`owns_hud()`. Контроллер по умолчанию строит Human-варианты сам (debug-P без изменений); диспетчер судьи подсунет AI/observer в Этапе 2.

**Tech Stack:** Godot 4.7 / GDScript. Headless-тест — `tests/check_*.gd` (`extends SceneTree`, `CHECK PASS`/`FAIL`, `quit(0/1)`).

## Global Constants

- **Инвариант рефактора:** поведение локального человека НЕ меняется ни на пиксель. `HumanKickerIntent` возвращает ровно то, что контроллер читал из `Input` раньше; `SetPiecePresentation(true)` (дефолт) владеет всем → все camera/HUD-вызовы идут как прежде. Приёмка = сцена грузится без новых ошибок + пенальти играется идентично (ручная проверка).
- **Пенальти-ввод как есть (из as-built карты):** прицел `Vector2(get_axis(move_left,move_right), -get_axis(move_forward,move_back))`; нога `foot_left`/`foot_right`; старт заряда `is_action_just_pressed(kick)`, вариант-чип `is_action_pressed(combo_modifier)` в момент старта; коммит `is_action_just_released(kick)` **или** `ratio>=1`.
- **Гоча дерева/классов (из плана A, применять здесь же):** после нового `class_name`-файла нужен `--headless --import` перед `-s`-тестом; узлы, добавленные в `SceneTree._initialize()`, «не в дереве» — но в этом тесте узлы 3D не нужны (тестируем чистый `RefCounted` через фейковый сабкласс синхронно в `_init`).
- **Тест-раннер:** `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/<name>.gd"` → `CHECK PASS`, exit 0.
- **Валидация сцены:** `& "<godot>" --path "<repo>" --headless --quit-after 2 res://scenes/match.tscn`. Baseline-категории ошибок (не регрессии): `Condition "!is_inside_tree()"`, `Condition "states.has(p_name)"`, `Condition "transitions[i]..."`, `Cannot get class 'WorldEnvironment3D'`. Диффать по КАТЕГОРИИ.

---

## File Structure

- **Create** `scripts/match/kicker_intent.gd` — `class_name KickerIntent extends RefCounted`. База-интерфейс (no-op дефолты).
- **Create** `scripts/match/human_kicker_intent.gd` — `class_name HumanKickerIntent extends KickerIntent`. Конфиг-driven обёртка над `Input`, латч-логика, переопределяемые input-обёртки.
- **Create** `scripts/match/set_piece_presentation.gd` — `class_name SetPiecePresentation extends RefCounted`. `owns_camera()`/`owns_hud()`.
- **Create** `tests/check_human_kicker_intent.gd` — headless-тест латч/вариант/нога-логики через фейковый сабкласс.
- **Modify** `scripts/match/penalty_controller.gd` — потреблять `_intent`/`_presentation` вместо прямых `Input.*` и гейтить camera/HUD.

---

## Task 1: Классы шва (`KickerIntent`, `HumanKickerIntent`, `SetPiecePresentation`) + тест

**Files:**
- Create: `scripts/match/kicker_intent.gd`
- Create: `scripts/match/human_kicker_intent.gd`
- Create: `scripts/match/set_piece_presentation.gd`
- Test: `tests/check_human_kicker_intent.gd`

**Interfaces:**
- Produces:
  - `KickerIntent` (база): `aim_axis() -> Vector2`, `foot_switch() -> int`, `charge_start_variant() -> int`, `charge_committed() -> bool`, `modifier_held() -> bool`, `secondary() -> bool` (все no-op дефолты).
  - `HumanKickerIntent.new(cfg: Dictionary)` где cfg-ключи: `aim_lat: Array[StringName]` (2 действия neg/pos), `aim_vert: Array[StringName]` (2, опц.), `foot: Array[StringName]` (2, опц.), `charges: Array` (список `[action: StringName, variant_id: int]`), `modifier: StringName` (опц.), `secondary: StringName` (опц.). Переопределяемые: `_pressed(a)`, `_just_pressed(a)`, `_axis(neg,pos)`.
  - `SetPiecePresentation.new(is_local_human: bool)`: `owns_camera() -> bool`, `owns_hud() -> bool`.

- [ ] **Step 1: Написать падающий тест**

Create `tests/check_human_kicker_intent.gd`:

```gdscript
extends SceneTree
## Headless-проверка латч/вариант/нога-логики HumanKickerIntent через фейковый сабкласс,
## который скриптует ввод (переопределяет _pressed/_just_pressed/_axis). Чистый RefCounted —
## синхронно в _init, узлы не нужны.

class _FakeIntent extends HumanKickerIntent:
	var pressed := {}
	var just := {}
	func _pressed(a: StringName) -> bool: return pressed.get(a, false)
	func _just_pressed(a: StringName) -> bool: return just.get(a, false)
	func _axis(neg: StringName, pos: StringName) -> float:
		return (1.0 if pressed.get(pos, false) else 0.0) - (1.0 if pressed.get(neg, false) else 0.0)

func _init() -> void:
	var ok := true
	var cfg := {
		"aim_lat": [&"move_left", &"move_right"],
		"aim_vert": [&"move_forward", &"move_back"],
		"foot": [&"foot_left", &"foot_right"],
		"charges": [[&"kick", 0], [&"pass_lob", 2]],
		"modifier": &"combo_modifier",
	}
	var f := _FakeIntent.new(cfg)

	# Прицел: право+назад зажаты → x=+1, y=-(back)= -1 (инверсия вертикали).
	f.pressed = {&"move_right": true, &"move_back": true}
	var aim := f.aim_axis()
	ok = _expect(is_equal_approx(aim.x, 1.0) and is_equal_approx(aim.y, -1.0), "aim_axis право+назад") and ok

	# Нога: just_pressed(foot_left) → -1; foot_right → +1; иначе 0.
	f.just = {&"foot_left": true}
	ok = _expect(f.foot_switch() == -1, "foot_switch left = -1") and ok
	f.just = {&"foot_right": true}
	ok = _expect(f.foot_switch() == 1, "foot_switch right = +1") and ok
	f.just = {}
	ok = _expect(f.foot_switch() == 0, "foot_switch none = 0") and ok

	# Старт заряда: just_pressed(kick) → вариант 0, латчит kick.
	f.just = {&"kick": true}
	f.pressed = {&"kick": true}
	ok = _expect(f.charge_start_variant() == 0, "charge_start вариант kick=0") and ok
	# Пока kick зажат — коммита нет.
	f.just = {}
	ok = _expect(f.charge_committed() == false, "нет коммита пока kick зажат") and ok
	# kick отпущен → коммит true (один раз), латч сброшен.
	f.pressed = {}
	ok = _expect(f.charge_committed() == true, "коммит при отпускании kick") and ok
	ok = _expect(f.charge_committed() == false, "коммит только раз (латч сброшен)") and ok

	# Другой вариант: just_pressed(pass_lob) → вариант 2.
	f.just = {&"pass_lob": true}
	f.pressed = {&"pass_lob": true}
	ok = _expect(f.charge_start_variant() == 2, "charge_start вариант pass_lob=2") and ok

	# modifier_held.
	f.pressed = {&"combo_modifier": true}
	ok = _expect(f.modifier_held() == true, "modifier_held true") and ok
	f.pressed = {}
	ok = _expect(f.modifier_held() == false, "modifier_held false") and ok

	# База KickerIntent — no-op дефолты.
	var base := KickerIntent.new()
	ok = _expect(base.charge_start_variant() == -1 and base.charge_committed() == false \
		and base.foot_switch() == 0 and base.aim_axis() == Vector2.ZERO, "база no-op") and ok

	# Презентация: is_local_human → owns всё; иначе ничего.
	var ph := SetPiecePresentation.new(true)
	var po := SetPiecePresentation.new(false)
	ok = _expect(ph.owns_camera() and ph.owns_hud(), "human владеет camera+hud") and ok
	ok = _expect(not po.owns_camera() and not po.owns_hud(), "observer не владеет") and ok

	if ok:
		print("CHECK PASS: human_kicker_intent")
		quit(0)
	else:
		print("CHECK FAIL: human_kicker_intent")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_human_kicker_intent.gd"`
Expected: parse error / FAIL — классов ещё нет.

- [ ] **Step 3: Реализовать `KickerIntent` (база)**

Create `scripts/match/kicker_intent.gd`:

```gdscript
class_name KickerIntent
extends RefCounted
## Источник намерения бьющего в стандарте (per-actor шов). Контроллер потребляет ЭТО вместо
## прямых Input.*. Варианты (charge_start_variant) — enum самого контроллера, поэтому ИИ-реализация
## позже отдаёт id варианта, не зная имён кнопок. База — no-op дефолты.

## Прицел: x = боковой (move_left/right), y = вертикаль/глубина (move_forward/back, инвертирован).
func aim_axis() -> Vector2:
	return Vector2.ZERO

## Смена ноги в этом кадре: -1 левая, +1 правая, 0 нет.
func foot_switch() -> int:
	return 0

## В этом кадре стартовал заряд с выбранным вариантом → id варианта (>=0), иначе -1.
## Реализация латчит стартовую кнопку для последующего коммита.
func charge_start_variant() -> int:
	return -1

## Латченный заряд должен выстрелить в этом кадре (стартовая кнопка отпущена).
func charge_committed() -> bool:
	return false

## Модификатор зажат (чип у пенальти; резерв под wall/air-варианты).
func modifier_held() -> bool:
	return false

## Вторичное действие в этом кадре (corner_call). По умолчанию нет.
func secondary() -> bool:
	return false
```

- [ ] **Step 4: Реализовать `HumanKickerIntent`**

Create `scripts/match/human_kicker_intent.gd`:

```gdscript
class_name HumanKickerIntent
extends KickerIntent
## Human-реализация шва бьющего: тонкая обёртка над Input, конфиг-driven (какие оси/кнопки).
## Ввод читается через переопределяемые _pressed/_just_pressed/_axis — для headless-теста
## (фейковый сабкласс скриптует ввод). Поведение = ровно прежние прямые Input.* контроллера.

var _cfg: Dictionary
var _active: StringName = &""   # латченная стартовая кнопка активного заряда

func _init(cfg: Dictionary) -> void:
	_cfg = cfg

# --- переопределяемый источник ввода (тест подменяет) ---
func _pressed(a: StringName) -> bool:
	return Input.is_action_pressed(a)

func _just_pressed(a: StringName) -> bool:
	return Input.is_action_just_pressed(a)

func _axis(neg: StringName, pos: StringName) -> float:
	return Input.get_axis(neg, pos)

# --- KickerIntent ---
func aim_axis() -> Vector2:
	var lat: Array = _cfg.get("aim_lat", [])
	var vert: Array = _cfg.get("aim_vert", [])
	var x := _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0
	var y := -_axis(vert[0], vert[1]) if vert.size() == 2 else 0.0
	return Vector2(x, y)

func foot_switch() -> int:
	var f: Array = _cfg.get("foot", [])
	if f.size() == 2:
		if _just_pressed(f[0]):
			return -1
		if _just_pressed(f[1]):
			return 1
	return 0

func charge_start_variant() -> int:
	var charges: Array = _cfg.get("charges", [])
	for entry in charges:
		var action: StringName = entry[0]
		if _just_pressed(action):
			_active = action
			return int(entry[1])
	return -1

func charge_committed() -> bool:
	if _active == &"":
		return false
	if not _pressed(_active):
		_active = &""
		return true
	return false

func modifier_held() -> bool:
	var m: StringName = _cfg.get("modifier", &"")
	return _pressed(m) if m != &"" else false

func secondary() -> bool:
	var s: StringName = _cfg.get("secondary", &"")
	return _just_pressed(s) if s != &"" else false
```

- [ ] **Step 5: Реализовать `SetPiecePresentation`**

Create `scripts/match/set_piece_presentation.gd`:

```gdscript
class_name SetPiecePresentation
extends RefCounted
## Двухуровневый профиль презентации стандарта. Уровень 1: участвует ли локальный человек-актёр
## (owns camera + тайминги стандарта). Уровень 2 (состав HUD по роли) добавят фичи, которым он
## нужен. Пилот: только owns_camera/owns_hud. is_local_human=true (дефолт human) → владеет всем;
## observer (ИИ/чужой стандарт) → ничем (камера-броадкаст не трогается, HUD скрыт).

var _local_human: bool

func _init(is_local_human: bool) -> void:
	_local_human = is_local_human

func owns_camera() -> bool:
	return _local_human

func owns_hud() -> bool:
	return _local_human
```

- [ ] **Step 6: Импорт-пасс (регистрация новых `class_name`) + запуск теста**

Run (сначала импорт, затем тест):
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_human_kicker_intent.gd"
```
Expected: `CHECK PASS: human_kicker_intent`, exit 0.

- [ ] **Step 7: Коммит**

```bash
git add scripts/match/kicker_intent.gd scripts/match/human_kicker_intent.gd scripts/match/set_piece_presentation.gd tests/check_human_kicker_intent.gd scripts/match/kicker_intent.gd.uid scripts/match/human_kicker_intent.gd.uid scripts/match/set_piece_presentation.gd.uid .godot/global_script_class_cache.cfg
git commit -m "feat(setpiece): KickerIntent seam + HumanKickerIntent + SetPiecePresentation profile"
```

---

## Task 2: Перевести пенальти-контроллер на шов (рефактор, поведение как было)

**Files:**
- Modify: `scripts/match/penalty_controller.gd`

**Interfaces:**
- Consumes: `KickerIntent`/`HumanKickerIntent`/`SetPiecePresentation` (Task 1).
- Produces: `penalty_controller.start_single(kicker, goal_line_z, intent: KickerIntent = null, presentation: SetPiecePresentation = null)` — опциональные intent/presentation; при null строятся Human-дефолты (debug-P работает без изменений). Диспетчер (Этап 2) передаёт AI/observer.

- [ ] **Step 1: Объявить поля шва**

В `scripts/match/penalty_controller.gd` после строки `var _watch_timer: float = 0.0` (строка 37) добавить:

```gdscript
var _intent: KickerIntent
var _presentation: SetPiecePresentation
```

- [ ] **Step 2: Дефолт презентации в `setup`, добавить `_default_intent`**

В `setup(...)` после `_build_reticle()` (строка 47) добавить:

```gdscript
	_presentation = SetPiecePresentation.new(true)
```

Сразу после функции `setup` (перед `## Старт одиночного пенальти...`, строка 49) добавить:

```gdscript
## Human-дефолт источника намерения пенальти-бьющего (ровно прежние Input-чтения контроллера).
func _default_intent() -> KickerIntent:
	return HumanKickerIntent.new({
		"aim_lat": [&"move_left", &"move_right"],
		"aim_vert": [&"move_forward", &"move_back"],
		"foot": [&"foot_left", &"foot_right"],
		"charges": [[&"kick", 0]],
		"modifier": &"combo_modifier",
	})
```

- [ ] **Step 3: Принять intent/presentation в `start_single`**

Заменить сигнатуру и начало `start_single` (строки 50-58):

```gdscript
func start_single(kicker: CharacterBody3D, goal_line_z: float) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -1.0 if goal_line_z > 0.0 else 1.0
	_foot = FootballConstants.PEN_DEFAULT_FOOT
	release_after_strike = true
	_setup()
```
на:
```gdscript
func start_single(kicker: CharacterBody3D, goal_line_z: float, intent: KickerIntent = null, presentation: SetPiecePresentation = null) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -1.0 if goal_line_z > 0.0 else 1.0
	_foot = FootballConstants.PEN_DEFAULT_FOOT
	release_after_strike = true
	_intent = intent if intent != null else _default_intent()   # свежий intent на каждый пенальти (латч сброшен)
	if presentation != null:
		_presentation = presentation
	_setup()
```

- [ ] **Step 4: Заменить ввод ноги на `_intent.foot_switch()`**

В `_aim_update` заменить блок ноги (строки 145-150):

```gdscript
	if Input.is_action_just_pressed(&"foot_left") and _foot != "penalty_l":
		_foot = "penalty_l"
		_place_kicker()
	elif Input.is_action_just_pressed(&"foot_right") and _foot != "penalty_r":
		_foot = "penalty_r"
		_place_kicker()
```
на:
```gdscript
	var fs := _intent.foot_switch()
	if fs == -1 and _foot != "penalty_l":
		_foot = "penalty_l"
		_place_kicker()
	elif fs == 1 and _foot != "penalty_r":
		_foot = "penalty_r"
		_place_kicker()
```

- [ ] **Step 5: Заменить прицел на `_intent.aim_axis()`**

В `_aim_update` заменить (строки 152-154):

```gdscript
	var aim_stick := Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		-Input.get_axis(&"move_forward", &"move_back"))
```
на:
```gdscript
	var aim_stick := _intent.aim_axis()
```

- [ ] **Step 6: Заменить старт заряда + гейтить power_bar**

В `_aim_update` заменить блок старта заряда и заряд/power-bar (строки 163-176):

```gdscript
	if Input.is_action_just_pressed(&"kick"):
		_charging = true
		_charge = 0.0
		_chip = Input.is_action_pressed(&"combo_modifier")
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.PEN_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or Input.is_action_just_released(&"kick"):
			_fire(ratio)
```
на:
```gdscript
	if _intent.charge_start_variant() >= 0:
		_charging = true
		_charge = 0.0
		_chip = _intent.modifier_held()
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.PEN_CHARGE_MAX_TIME, 0.0, 1.0)
		if _presentation.owns_hud():
			_power_bar.visible = true
			_power_bar.value = ratio
			var fill := _power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _intent.charge_committed():
			_fire(ratio)
```

- [ ] **Step 7: Гейтить скрытие power_bar в `_fire`**

В `_fire` заменить (строка 180):

```gdscript
	_power_bar.visible = false
```
на:
```gdscript
	if _presentation.owns_hud():
		_power_bar.visible = false
```

- [ ] **Step 8: Гейтить камеру и ретикл профилем**

В `_update_camera_pose` заменить начало (строки 267-269):

```gdscript
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
```
на:
```gdscript
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	if not _presentation.owns_camera():
		return
```

В `_update_reticle` заменить (строка 297):

```gdscript
	var show_it := _phase == Phase.AIM and _reticle_visible
```
на:
```gdscript
	var show_it := _phase == Phase.AIM and _reticle_visible and _presentation.owns_hud()
```

- [ ] **Step 9: Валидация сцены матча**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: грузится (exit 0), только baseline-категории ошибок, без новых `SCRIPT ERROR`/`Parse Error`/nil-доступа.

- [ ] **Step 10: Регрессия — тест шва**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_human_kicker_intent.gd"`
Expected: `CHECK PASS: human_kicker_intent`.

- [ ] **Step 11: Ручная проверка «как было» (фил — headless не драйвит)**

Запустить игру (Godot без `--headless`), нажать **P** (пенальти). Убедиться, что ВСЁ идентично прежнему:
- Прицел двигается стиком/стрелками, ретикл ходит по створу, без ввода — плавно возвращается в центр.
- **Q+D** (combo_modifier+kick) — заряжается **чип** (кольцо разброса), обычный **D** — прямой удар.
- Удержание **D** растит power_bar (зелёный→красный), отпускание/полный заряд — выстрел.
- **foot_left/foot_right** переключают ногу (бьющий сдвигается латерально), разбег с нужной ноги.
- Камера — фикс-вид из-за спины бьущего на ворота; после удара держится PEN_WATCH_TIME.
Если что-то отличается от прежнего — рефактор изменил поведение, разобраться до коммита.

- [ ] **Step 12: Коммит**

```bash
git add scripts/match/penalty_controller.gd
git commit -m "refactor(penalty): consume KickerIntent + SetPiecePresentation seam (behavior unchanged)"
```

---

## Self-Review

**Spec coverage (кусок B, пилот-часть):**
- Шов `KickerIntent` (per-actor, ролевой) → Task 1 (`kicker_intent.gd` + `human_kicker_intent.gd`).
- Двухуровневый профиль презентации → Task 1 (`set_piece_presentation.gd`, `owns_camera`/`owns_hud`); уровень «состав HUD по роли» — заглушен под пилот (owns_hud единый), доразовьётся с ролями keeper/wall в Этапе 2, отмечено в комментарии класса.
- Рефактор контроллера: заменить прямые `Input.*` на `_intent.*`, вынести владение камерой/баром в профиль → Task 2 (пенальти).
- **Вне скоупа этого плана (план B2):** остальные 4 контроллера (free kick / corner / goal kick / throw-in) — тот же паттерн, каждый со своим variant-enum и конфигом (у углового ещё `secondary()`=corner_call; у аута нет ноги/lob). `KeeperIntent`/`WallIntent` (дайв-зона/прыжок) — с их фичами в Этапе 2, не здесь. Манагер-side гейт парковки камеры для observer-режима — тоже Этап 2 (пилот human-only, не exercised); в пилоте гейтится только ВЫЗОВ `set_penalty_cam_pose` контроллером.

**Placeholder scan:** плейсхолдеров нет — полный код/команды в каждом шаге.

**Type consistency:** `KickerIntent` методы (`aim_axis`/`foot_switch`/`charge_start_variant`/`charge_committed`/`modifier_held`/`secondary`) идентичны в базе (Task 1 Step 3), Human-реализации (Step 4) и потреблении пенальти (Task 2). `SetPiecePresentation.new(bool)` + `owns_camera`/`owns_hud` — одна форма в Task 1 и Task 2. `start_single(kicker, goal_line_z, intent=null, presentation=null)` — расширение существующей сигнатуры обратносовместимо (старый вызов `start_single(controlled_player, goal_line_z)` из манагера продолжает работать).
```

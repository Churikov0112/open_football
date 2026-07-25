# Раскатка шва «источник намерения» на 4 контроллера стандартов (план B2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Перевести `throw_in`/`goal_kick`/`corner`/`free_kick` контроллеры с прямого чтения `Input.*` на per-actor шов `KickerIntent`/`HumanKickerIntent` + профиль презентации `SetPiecePresentation` — как уже сделано в `penalty_controller.gd`. Поведение локального человека не меняется ни на пиксель.

**Architecture:** Чистый рефактор. Каждый контроллер получает поля `_intent: KickerIntent` и `_presentation: SetPiecePresentation`, метод `_default_intent()` (строит `HumanKickerIntent` с cfg-словарём имён input-действий, эквивалентным прежним прямым `Input.*`), опциональные параметры `intent`/`presentation` в `start(...)`. Прямые `Input.is_action_*`/`Input.get_axis` в `_aim_update`/`_strike_update` заменяются на `_intent.*`. Владение камерой/power_bar гейтится через `_presentation.owns_camera()`/`owns_hud()`. Роль по умолчанию — `KICKER` (человек всегда бьющий сегодня), поэтому оба гейта = `true` → поведение идентично. `match_manager.gd` и `*_logic.gd` НЕ трогаются.

**Tech Stack:** Godot 4.7, GDScript. Существующие глобальные классы `KickerIntent`, `HumanKickerIntent`, `SetPiecePresentation` (в `scripts/match/`). Хедлесс-тесты `tests/check_*.gd` (extends `SceneTree`).

## Global Constraints

- **Godot exe (валидация/тесты):** `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`.
- **Запуск хедлесс-теста:** `& "<exe>" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/<name>.gd"` — печатает `CHECK PASS`/`CHECK FAIL`, код выхода 0/1.
- **Валидация сцены:** `& "<exe>" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`.
- **Godot часто стартует >120 c** — все хедлесс-прогоны запускать через `Bash` с `run_in_background: true` и поллить output-файл; не чейнить несколько прогонов в один вызов.
- **Baseline-категории ошибок сцены (НЕ регрессии), диффать по КАТЕГОРИИ, не по числу:** `ERROR: Condition "!is_inside_tree()" is true.`, `states.has(p_name)`, transition-duplicate, `ERROR: Cannot get class 'WorldEnvironment3D'.`.
- **Новых `class_name`-файлов НЕ создаётся** (только новые тест-скрипты без `class_name` и правки контроллеров) — отдельный `--headless --import` перед `-s` НЕ нужен.
- **`match_manager.gd` НЕ меняется.** Его гейтинг маркера/камеры завязан на флаги `is_*_active()`, а не на роль презентации; для этих 4 контроллеров он не вызывает `kicker_is_local_human()`. Поэтому такой метод в этой фазе НЕ добавляется.
- **Отвечать пользователю по-русски.** Коммиты подписывать `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Эталон шва (образец, уже в репозитории)

`scripts/match/penalty_controller.gd` — референс. Ключевое:
- `_default_intent()` (строки 61-68) строит `HumanKickerIntent.new({...})` с ключами `aim_lat`/`aim_vert`/`foot`/`charges`/`modifier`/`secondary`.
- `start_single(...)` (строка 79): `_intent = intent if intent != null else _default_intent()` — свежий intent на каждый розыгрыш (латч заряда сброшен).
- В `_aim_update` дёргаются `_intent.foot_switch()`, `_intent.aim_axis()`, `_intent.charge_start_variant()`, `_intent.charge_committed()`, `_intent.modifier_held()`.
- power_bar пишется под `if _presentation.owns_hud():` (строки 201-206), камера — под `if not _presentation.owns_camera(): return` (строка 305).

Семантика методов `KickerIntent` (`scripts/match/kicker_intent.gd`):
- `aim_axis() -> Vector2` — x из пары `aim_lat`, y = `-axis` пары `aim_vert` (уже негирован в `HumanKickerIntent`, совпадает с прежним `-Input.get_axis(move_forward, move_back)`).
- `foot_switch() -> int` — `-1` левая / `+1` правая / `0`.
- `charge_start_variant() -> int` — id варианта (`>=0`) в кадре, когда кнопка заряда только что нажата (латчит эту кнопку), иначе `-1`. **Побочный эффект — латч; звать один раз за кадр и только пока заряд не начат** (в блоке `if not _locked:`).
- `charge_committed() -> bool` — латченная кнопка отпущена в этом кадре.
- `secondary() -> bool` — вторичное действие (у углового `corner_call`).

## Структура файлов

**Правятся (контроллеры):**
- `scripts/match/throw_in_controller.gd` — Task 1. Простейший: один вариант заряда, без ноги/вертикали/модификатора/секондари; `setup()` без keeper.
- `scripts/match/goal_kick_controller.gd` — Task 2. Два варианта (ground/lob), нога, heading крутится и в AIM, и в STRIKE (финт до контакта).
- `scripts/match/corner_controller.gd` — Task 3. Два варианта, нога, вертикаль (высота навеса), secondary (`corner_call`), закрутка в AIM+STRIKE.
- `scripts/match/free_kick_controller.gd` — Task 4. Три варианта (shot/ground/lob), OR-заряд (`pass_short` ИЛИ `pass_through` → ground), закрутка в AIM+STRIKE.

**Создаются (тесты):**
- `tests/check_throw_in_intent.gd` — Task 1.
- `tests/check_goal_kick_intent.gd` — Task 2.
- `tests/check_corner_intent.gd` — Task 3.
- `tests/check_free_kick_intent.gd` — Task 4.

**Регрессия (не меняются, прогоняются как есть):** `tests/check_throw_in_flow.gd`, `tests/check_goal_kick_flow.gd`, `tests/check_corner_flow.gd`, `tests/check_free_kick_flow.gd` — они зовут `_fire_charge`/`_fire_shot` НАПРЯМУЮ (минуя шов), эти методы сохраняются, так что тесты остаются валидны без правок.

**Общий приём тестирования шва:** тест грузит `match.tscn`, инжектит скриптованный фейковый `KickerIntent` (внутренний класс теста) через новый параметр `start(..., intent)`, и — вместо прямого вызова `_fire_*` — выставляет поля фейка (`start_variant`, затем `committed`), а `match_manager._physics_process` сам делегирует `update()` → `_aim_update()` читает фейк → заряд → коммит → выстрел. Проверяем: мяч получил импульс, режим снялся. Это доказывает, что автомат реально потребляет шов. До рефактора `start()` не принимает `intent` → тест падает (красный).

---

### Task 1: throw_in — перевод на шов

**Files:**
- Modify: `scripts/match/throw_in_controller.gd`
- Test: `tests/check_throw_in_intent.gd` (create)

**Interfaces:**
- Consumes: `KickerIntent`, `HumanKickerIntent`, `SetPiecePresentation` (существующие глобальные классы). `_start_charge()`, `_fire_charge(ratio)` (существующие методы контроллера).
- Produces: `throw_in_controller.start(intent: KickerIntent = null, presentation: SetPiecePresentation = null)` — новая сигнатура (была `start()`); `_default_intent() -> KickerIntent`; поля `_intent`, `_presentation`.

- [ ] **Step 1: Написать падающий seam-тест**

Create `tests/check_throw_in_intent.gd`:

```gdscript
extends SceneTree
## Seam-тест вброса: контроллер потребляет инжектированный KickerIntent (заряд+коммит через шов),
## а не Input. Драйв — match_manager делегирует update(); фейк-интент скриптует «нажатия».

class FakeKickerIntent extends KickerIntent:
	var start_variant: int = -1     # тест выставит один раз → «кнопка заряда нажата»
	var committed: bool = false     # тест выставит → «кнопка отпущена, выстрел»
	func aim_axis() -> Vector2:
		return Vector2.ZERO
	func charge_start_variant() -> int:
		var v := start_variant
		start_variant = -1          # one-shot, как just_pressed
		return v
	func charge_committed() -> bool:
		return committed

var _mm: Node
var _ti: Node
var _fake: FakeKickerIntent
var _elapsed: float = 0.0
var _state: int = 0
var _max_ball_speed: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.15:
				_ti = _mm.get_node_or_null("ThrowInController")
				if _ti == null:
					print("CHECK FAIL: нет узла ThrowInController"); return true
				_fake = FakeKickerIntent.new()
				_ti.start(_fake)
				if not _mm.is_throw_in_active():
					print("CHECK FAIL: throw-in-режим не включился"); return true
				_state = 1
		1:
			if _elapsed > 0.4:
				_fake.start_variant = 0    # «нажали» кнопку заряда через шов
				_state = 2
		2:
			if _elapsed > 0.6:
				_fake.committed = true     # «отпустили» через шов → выстрел
				_state = 3
		3:
			_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
			if _elapsed > 4.0:
				var released: bool = not _mm.is_throw_in_active()
				var launched: bool = _max_ball_speed > 1.0
				print("SEAM: max_ball_speed=", _max_ball_speed)
				if released and launched:
					print("CHECK PASS: throw_in intent seam (charge+commit через KickerIntent)")
					quit(0)
				else:
					print("CHECK FAIL: released=", str(released), " launched=", str(launched))
					quit(1)
				return true
	if _elapsed > 6.0:
		print("CHECK FAIL: таймаут"); return true
	return false
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run (в фоне, поллить output):
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_throw_in_intent.gd"
```
Expected: НЕ `CHECK PASS` — рантайм-ошибка вида «Too many arguments to `start()`» (сигнатура ещё `start()` без параметров) или таймаут.

- [ ] **Step 3: Реализовать шов в `throw_in_controller.gd`**

Edit 1 — добавить поля. После строки `var _contact_connected := false` (≈27) добавить:
```gdscript
var _intent: KickerIntent
var _presentation: SetPiecePresentation
```

Edit 2 — сигнатура `start()` + инициализация intent/presentation. Заменить заголовок и первые строки:
```gdscript
func start() -> void:
	if _phase != Phase.IDLE:
		return
	_spot = ThrowInLogic.aut_point(_ball.global_position,
```
на:
```gdscript
func start(intent: KickerIntent = null, presentation: SetPiecePresentation = null) -> void:
	if _phase != Phase.IDLE:
		return
	_intent = intent if intent != null else _default_intent()
	_presentation = presentation if presentation != null else SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
	_spot = ThrowInLogic.aut_point(_ball.global_position,
```

Edit 3 — добавить `_default_intent()` сразу перед `func _setup() -> void:`:
```gdscript
## Human-дефолт источника намерения вбрасывающего (ровно прежние Input-чтения контроллера).
func _default_intent() -> KickerIntent:
	return HumanKickerIntent.new({
		"aim_lat": [&"move_left", &"move_right"],
		"charges": [[&"pass_short", 0]],
	})

```

Edit 4 — заменить весь `_aim_update`:
```gdscript
func _aim_update(delta: float) -> void:
	if not _locked:
		var stick_x := Input.get_axis(&"move_left", &"move_right")
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _into, stick_x,
				FootballConstants.THROW_AIM_SPEED, delta, FootballConstants.THROW_AIM_ARC)
		# Тело доворачивается вместе с направлением.
		var tm := PlayerMotor.find_on(_thrower)
		if tm != null:
			tm.set_face_direction(_heading)
		if Input.is_action_just_pressed(&"pass_short"):
			_start_charge()
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.THROW_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or not Input.is_action_pressed(&"pass_short"):
			_fire_charge(ratio)
```
на:
```gdscript
func _aim_update(delta: float) -> void:
	if not _locked:
		var stick_x := _intent.aim_axis().x
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _into, stick_x,
				FootballConstants.THROW_AIM_SPEED, delta, FootballConstants.THROW_AIM_ARC)
		# Тело доворачивается вместе с направлением.
		var tm := PlayerMotor.find_on(_thrower)
		if tm != null:
			tm.set_face_direction(_heading)
		if _intent.charge_start_variant() >= 0:
			_start_charge()
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.THROW_CHARGE_MAX_TIME, 0.0, 1.0)
		if _presentation.owns_hud():
			_power_bar.visible = true
			_power_bar.value = ratio
			var fill := _power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _intent.charge_committed():
			_fire_charge(ratio)
```

Edit 5 — гейт power_bar в `_fire_charge`. Заменить:
```gdscript
func _fire_charge(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	_pending_ratio = ratio
	_begin_strike()
```
на:
```gdscript
func _fire_charge(ratio: float) -> void:
	_charging = false
	if _presentation.owns_hud():
		_power_bar.visible = false
	_pending_ratio = ratio
	_begin_strike()
```

Edit 6 — гейт камеры в `_update_camera_pose`. Заменить:
```gdscript
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	var eye := _spot - _heading * FootballConstants.THROW_CAM_BACK + Vector3(0.0, FootballConstants.THROW_CAM_HEIGHT, 0.0)
```
на:
```gdscript
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	if not _presentation.owns_camera():
		return
	var eye := _spot - _heading * FootballConstants.THROW_CAM_BACK + Vector3(0.0, FootballConstants.THROW_CAM_HEIGHT, 0.0)
```

- [ ] **Step 4: Запустить seam-тест — убедиться, что проходит**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_throw_in_intent.gd"
```
Expected: `CHECK PASS: throw_in intent seam (...)`.

- [ ] **Step 5: Регрессия — прежний flow-тест всё ещё зелёный**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_throw_in_flow.gd"
```
Expected: `CHECK PASS: throw_in flow (launched + released)`.

- [ ] **Step 6: Валидация сцены (baseline-категории)**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: только baseline-категории из Global Constraints; никаких новых текстов ошибок (например про `throw_in_controller`).

- [ ] **Step 7: Коммит**

```bash
git add scripts/match/throw_in_controller.gd tests/check_throw_in_intent.gd
git commit -m "refactor(throw-in): consume KickerIntent/SetPiecePresentation seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: goal_kick — перевод на шов

**Files:**
- Modify: `scripts/match/goal_kick_controller.gd`
- Test: `tests/check_goal_kick_intent.gd` (create)

**Interfaces:**
- Consumes: `KickerIntent`, `HumanKickerIntent`, `SetPiecePresentation`; `_set_foot(f)`, `_start_charge(kind)`, `_fire_charge(ratio)` (существующие).
- Produces: `goal_kick_controller.start(kicker, goal_line_z, intent = null, presentation = null)`; `_default_intent()`; поля `_intent`, `_presentation`. Метод `_charge_released()` УДАЛЯЕТСЯ (его роль берёт `_intent.charge_committed()`).

- [ ] **Step 1: Написать падающий seam-тест**

Create `tests/check_goal_kick_intent.gd`:

```gdscript
extends SceneTree
## Seam-тест удара от ворот: контроллер потребляет инжектированный KickerIntent (ground-заряд +
## коммит через шов). Драйв — match_manager делегирует update(). Бьющий — вратарь.

class FakeKickerIntent extends KickerIntent:
	var start_variant: int = -1
	var committed: bool = false
	func aim_axis() -> Vector2:
		return Vector2.ZERO
	func charge_start_variant() -> int:
		var v := start_variant
		start_variant = -1
		return v
	func charge_committed() -> bool:
		return committed

var _mm: Node
var _gk: Node
var _fake: FakeKickerIntent
var _elapsed: float = 0.0
var _state: int = 0
var _max_ball_speed: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.15:
				_gk = _mm.get_node_or_null("GoalKickController")
				if _gk == null:
					print("CHECK FAIL: нет узла GoalKickController"); return true
				_fake = FakeKickerIntent.new()
				_gk.start(_mm._keeper, _mm._keeper_brain.goal_line_z, _fake)
				if not _mm.is_goal_kick_active():
					print("CHECK FAIL: goal_kick-режим не включился"); return true
				_state = 1
		1:
			if _elapsed > 0.4:
				_fake.start_variant = 0    # 0 = ground
				_state = 2
		2:
			if _elapsed > 0.6:
				_fake.committed = true
				_state = 3
		3:
			_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
			if _elapsed > 4.0:
				var released: bool = not _mm.is_goal_kick_active()
				var launched: bool = _max_ball_speed > 1.0
				print("SEAM: max_ball_speed=", _max_ball_speed)
				if released and launched:
					print("CHECK PASS: goal_kick intent seam (charge+commit через KickerIntent)")
					quit(0)
				else:
					print("CHECK FAIL: released=", str(released), " launched=", str(launched))
					quit(1)
				return true
	if _elapsed > 6.0:
		print("CHECK FAIL: таймаут"); return true
	return false
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_goal_kick_intent.gd"
```
Expected: НЕ `CHECK PASS` — «Too many arguments to `start()`» (сигнатура ещё 2 параметра).

- [ ] **Step 3: Реализовать шов в `goal_kick_controller.gd`**

Edit 1 — поля. После `var _contact_connected := false` (≈36) добавить:
```gdscript
var _intent: KickerIntent
var _presentation: SetPiecePresentation
```

Edit 2 — сигнатура `start()` + init. Заменить:
```gdscript
func start(kicker: CharacterBody3D, goal_line_z: float) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -signf(goal_line_z)   # в поле от линии ворот
	_foot = FootballConstants.GK_DEFAULT_FOOT
	# Соперники бьющей команды (по группе бьющего) — общее правило, без хардкода.
	_opp_group = &"team_2" if kicker.is_in_group("team_1") else &"team_1"
	_setup()
```
на:
```gdscript
func start(kicker: CharacterBody3D, goal_line_z: float, intent: KickerIntent = null, presentation: SetPiecePresentation = null) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -signf(goal_line_z)   # в поле от линии ворот
	_foot = FootballConstants.GK_DEFAULT_FOOT
	_intent = intent if intent != null else _default_intent()
	_presentation = presentation if presentation != null else SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
	# Соперники бьющей команды (по группе бьющего) — общее правило, без хардкода.
	_opp_group = &"team_2" if kicker.is_in_group("team_1") else &"team_1"
	_setup()
```

Edit 3 — добавить `_default_intent()` перед `func _setup() -> void:`:
```gdscript
## Human-дефолт источника намерения бьющего удар от ворот (прежние Input-чтения контроллера).
func _default_intent() -> KickerIntent:
	return HumanKickerIntent.new({
		"aim_lat": [&"move_left", &"move_right"],
		"foot": [&"foot_left", &"foot_right"],
		"charges": [[&"pass_short", 0], [&"pass_lob", 1]],   # 0 = ground, 1 = lob
	})

```

Edit 4 — заменить `_aim_update` целиком:
```gdscript
func _aim_update(delta: float) -> void:
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога определяется выбранным бьющим).
	if Input.is_action_just_pressed(&"foot_left"):
		_set_foot("penalty_l")
	elif Input.is_action_just_pressed(&"foot_right"):
		_set_foot("penalty_r")
	var stick_x := Input.get_axis(&"move_left", &"move_right")
	# Стик крутит направление вылета мяча — и до, и после коммита (доводка/финт).
	if absf(stick_x) > 0.15:
		_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
			FootballConstants.GK_AIM_SPEED, delta, FootballConstants.GK_AIM_ARC)
	if not _locked:
		_cam_heading = _heading   # камера едет за прицелом только до коммита
		if Input.is_action_just_pressed(&"pass_short"):
			_start_charge("ground")
		elif Input.is_action_just_pressed(&"pass_lob"):
			_start_charge("lob")
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.GK_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _charge_released():
			_fire_charge(ratio)
```
на:
```gdscript
func _aim_update(delta: float) -> void:
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога определяется выбранным бьющим).
	var fs := _intent.foot_switch()
	if fs == -1:
		_set_foot("penalty_l")
	elif fs == 1:
		_set_foot("penalty_r")
	var stick_x := _intent.aim_axis().x
	# Стик крутит направление вылета мяча — и до, и после коммита (доводка/финт).
	if absf(stick_x) > 0.15:
		_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
			FootballConstants.GK_AIM_SPEED, delta, FootballConstants.GK_AIM_ARC)
	if not _locked:
		_cam_heading = _heading   # камера едет за прицелом только до коммита
		var v := _intent.charge_start_variant()
		if v == 0:
			_start_charge("ground")
		elif v == 1:
			_start_charge("lob")
	if _charging:
		_charge += delta
		var ratio := clampf(_charge / FootballConstants.GK_CHARGE_MAX_TIME, 0.0, 1.0)
		if _presentation.owns_hud():
			_power_bar.visible = true
			_power_bar.value = ratio
			var fill := _power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _intent.charge_committed():
			_fire_charge(ratio)
```

Edit 5 — удалить метод `_charge_released()` целиком:
```gdscript
func _charge_released() -> bool:
	if _charge_kind == "lob":
		return not Input.is_action_pressed(&"pass_lob")
	return not Input.is_action_pressed(&"pass_short")

```

Edit 6 — гейт power_bar в `_fire_charge`. Заменить:
```gdscript
func _fire_charge(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	_pending_ratio = ratio
	_begin_strike(_charge_kind)
```
на:
```gdscript
func _fire_charge(ratio: float) -> void:
	_charging = false
	if _presentation.owns_hud():
		_power_bar.visible = false
	_pending_ratio = ratio
	_begin_strike(_charge_kind)
```

Edit 7 — заменить чтение Input в `_strike_update`. Заменить:
```gdscript
func _strike_update(delta: float) -> void:
	# Доводка продолжается на разбеге вплоть до контакта.
	var stick_x := Input.get_axis(&"move_left", &"move_right")
	if absf(stick_x) > 0.15:
```
на:
```gdscript
func _strike_update(delta: float) -> void:
	# Доводка продолжается на разбеге вплоть до контакта.
	var stick_x := _intent.aim_axis().x
	if absf(stick_x) > 0.15:
```

Edit 8 — гейт камеры в `_update_camera_pose`. Заменить:
```gdscript
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	var eye := _spot - _cam_heading * FootballConstants.GK_CAM_BACK + Vector3(0.0, FootballConstants.GK_CAM_HEIGHT, 0.0)
```
на:
```gdscript
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	if not _presentation.owns_camera():
		return
	var eye := _spot - _cam_heading * FootballConstants.GK_CAM_BACK + Vector3(0.0, FootballConstants.GK_CAM_HEIGHT, 0.0)
```

- [ ] **Step 4: Запустить seam-тест — убедиться, что проходит**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_goal_kick_intent.gd"
```
Expected: `CHECK PASS: goal_kick intent seam (...)`.

- [ ] **Step 5: Регрессия — прежние тесты зелёные**

Прогнать по очереди (каждый отдельным вызовом):
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_goal_kick_flow.gd"
```
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_goalkick_keeper_mode.gd"
```
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_goal_kick_own_team_clear.gd"
```
Expected: три `CHECK PASS`.

- [ ] **Step 6: Валидация сцены**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: только baseline-категории.

- [ ] **Step 7: Коммит**

```bash
git add scripts/match/goal_kick_controller.gd tests/check_goal_kick_intent.gd
git commit -m "refactor(goal-kick): consume KickerIntent/SetPiecePresentation seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: corner — перевод на шов

**Files:**
- Modify: `scripts/match/corner_controller.gd`
- Test: `tests/check_corner_intent.gd` (create)

**Interfaces:**
- Consumes: `KickerIntent`, `HumanKickerIntent`, `SetPiecePresentation`; `_set_foot(f)`, `_call_short_mate()`, `_drive_short_mate(delta)`, `_start_charge(kind)`, `_fire_charge(ratio)` (существующие). Использует `_intent.secondary()` для `corner_call`.
- Produces: `corner_controller.start(kicker, goal_line_z, intent = null, presentation = null)`; `_default_intent()`; поля `_intent`, `_presentation`. Метод `_charge_released()` УДАЛЯЕТСЯ.

- [ ] **Step 1: Написать падающий seam-тест**

Create `tests/check_corner_intent.gd`:

```gdscript
extends SceneTree
## Seam-тест углового: контроллер потребляет инжектированный KickerIntent — вторичное действие
## (corner_call) зовёт короткого партнёра, lob-заряд + коммит бьют через шов. Драйв — match_manager.

class FakeKickerIntent extends KickerIntent:
	var start_variant: int = -1
	var committed: bool = false
	var secondary_now: bool = false
	func aim_axis() -> Vector2:
		return Vector2.ZERO
	func charge_start_variant() -> int:
		var v := start_variant
		start_variant = -1
		return v
	func charge_committed() -> bool:
		return committed
	func secondary() -> bool:
		var s := secondary_now
		secondary_now = false
		return s

var _mm: Node
var _corner: Node
var _fake: FakeKickerIntent
var _elapsed: float = 0.0
var _state: int = 0
var _max_ball_speed: float = 0.0
var _secondary_ok: bool = false

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.15:
				_corner = _mm.get_node_or_null("CornerController")
				if _corner == null:
					print("CHECK FAIL: нет узла CornerController"); return true
				_fake = FakeKickerIntent.new()
				_corner.start(_mm.controlled_player, _mm._keeper_brain.goal_line_z, _fake)
				if not _mm.is_corner_active():
					print("CHECK FAIL: режим углового не включился"); return true
				_state = 1
		1:
			# Вторичное действие: «нажали» corner_call — короткий партнёр должен быть вызван.
			if _elapsed > 0.4:
				_fake.secondary_now = true
				_state = 2
		2:
			if _elapsed > 0.55:
				_secondary_ok = bool(_corner._short_called)
				_fake.start_variant = 1    # 1 = lob (навес)
				_state = 3
		3:
			if _elapsed > 0.75:
				_fake.committed = true
				_state = 4
		4:
			_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
			if _elapsed > 4.0:
				var released: bool = not _mm.is_corner_active()
				var launched: bool = _max_ball_speed > 1.0
				print("SEAM: max_ball_speed=", _max_ball_speed, " secondary_ok=", str(_secondary_ok))
				if released and launched and _secondary_ok:
					print("CHECK PASS: corner intent seam (secondary + charge+commit через KickerIntent)")
					quit(0)
				else:
					print("CHECK FAIL: released=", str(released), " launched=", str(launched), " secondary_ok=", str(_secondary_ok))
					quit(1)
				return true
	if _elapsed > 6.0:
		print("CHECK FAIL: таймаут"); return true
	return false
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_corner_intent.gd"
```
Expected: НЕ `CHECK PASS` — «Too many arguments to `start()`».

- [ ] **Step 3: Реализовать шов в `corner_controller.gd`**

Edit 1 — поля. После `var _contact_connected := false` (≈37) добавить:
```gdscript
var _intent: KickerIntent
var _presentation: SetPiecePresentation
```

Edit 2 — сигнатура `start()` + init. Заменить:
```gdscript
func start(kicker: CharacterBody3D, goal_line_z: float) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -signf(goal_line_z)
	_side = CornerLogic.side_for_player(kicker.global_position.x)
	_foot = CornerLogic.foot_for_side(_side)
	_setup()
```
на:
```gdscript
func start(kicker: CharacterBody3D, goal_line_z: float, intent: KickerIntent = null, presentation: SetPiecePresentation = null) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -signf(goal_line_z)
	_side = CornerLogic.side_for_player(kicker.global_position.x)
	_foot = CornerLogic.foot_for_side(_side)
	_intent = intent if intent != null else _default_intent()
	_presentation = presentation if presentation != null else SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
	_setup()
```

Edit 3 — добавить `_default_intent()` перед `func _setup() -> void:`:
```gdscript
## Human-дефолт источника намерения бьющего угловой (прежние Input-чтения контроллера).
func _default_intent() -> KickerIntent:
	return HumanKickerIntent.new({
		"aim_lat": [&"move_left", &"move_right"],
		"aim_vert": [&"move_forward", &"move_back"],
		"foot": [&"foot_left", &"foot_right"],
		"charges": [[&"pass_short", 0], [&"pass_lob", 1]],   # 0 = ground, 1 = lob
		"secondary": &"corner_call",
	})

```

Edit 4 — заменить `_aim_update` целиком:
```gdscript
func _aim_update(delta: float) -> void:
	var stick_x := Input.get_axis(&"move_left", &"move_right")
	var stick_y := -Input.get_axis(&"move_forward", &"move_back")
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога от выбранного бьющим).
	if Input.is_action_just_pressed(&"foot_left"):
		_set_foot("penalty_l")
	elif Input.is_action_just_pressed(&"foot_right"):
		_set_foot("penalty_r")
	# RB — позвать ближайшего партнёра на короткую опцию.
	if Input.is_action_just_pressed(&"corner_call"):
		_call_short_mate()
	_drive_short_mate(delta)
	if not _locked:
		# Стик-X крутит heading (камера едет). Стик-Y задаёт высоту навеса (до нажатия B).
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
				FootballConstants.CORNER_AIM_SPEED, delta, FootballConstants.CORNER_AIM_ARC)
		_peak_height = CornerLogic.peak_for_stick_y(stick_y, FootballConstants.CORNER_LOB_PEAK_HEAD,
			FootballConstants.CORNER_LOB_PEAK_STANDARD, FootballConstants.CORNER_LOB_PEAK_SVECHA)
		# A = наземный пас, B = навес.
		if Input.is_action_just_pressed(&"pass_short"):
			_start_charge("ground")
		elif Input.is_action_just_pressed(&"pass_lob"):
			_start_charge("lob")
	if _charging:
		_charge += delta
		if _charge_kind == "lob":
			_curl_accum += stick_x * delta   # закрутка копится только для навеса
		var ratio := clampf(_charge / FootballConstants.CORNER_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _charge_released():
			_fire_charge(ratio)
```
на:
```gdscript
func _aim_update(delta: float) -> void:
	var aim := _intent.aim_axis()
	var stick_x := aim.x
	var stick_y := aim.y
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога от выбранного бьющим).
	var fs := _intent.foot_switch()
	if fs == -1:
		_set_foot("penalty_l")
	elif fs == 1:
		_set_foot("penalty_r")
	# RB — позвать ближайшего партнёра на короткую опцию.
	if _intent.secondary():
		_call_short_mate()
	_drive_short_mate(delta)
	if not _locked:
		# Стик-X крутит heading (камера едет). Стик-Y задаёт высоту навеса (до нажатия B).
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
				FootballConstants.CORNER_AIM_SPEED, delta, FootballConstants.CORNER_AIM_ARC)
		_peak_height = CornerLogic.peak_for_stick_y(stick_y, FootballConstants.CORNER_LOB_PEAK_HEAD,
			FootballConstants.CORNER_LOB_PEAK_STANDARD, FootballConstants.CORNER_LOB_PEAK_SVECHA)
		# A = наземный пас, B = навес.
		var v := _intent.charge_start_variant()
		if v == 0:
			_start_charge("ground")
		elif v == 1:
			_start_charge("lob")
	if _charging:
		_charge += delta
		if _charge_kind == "lob":
			_curl_accum += stick_x * delta   # закрутка копится только для навеса
		var ratio := clampf(_charge / FootballConstants.CORNER_CHARGE_MAX_TIME, 0.0, 1.0)
		if _presentation.owns_hud():
			_power_bar.visible = true
			_power_bar.value = ratio
			var fill := _power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _intent.charge_committed():
			_fire_charge(ratio)
```

Edit 5 — удалить метод `_charge_released()` целиком:
```gdscript
func _charge_released() -> bool:
	if _charge_kind == "lob":
		return not Input.is_action_pressed(&"pass_lob")
	return not Input.is_action_pressed(&"pass_short")

```

Edit 6 — гейт power_bar в `_fire_charge`. Заменить:
```gdscript
func _fire_charge(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	_pending_ratio = ratio
	_begin_strike(_charge_kind)
```
на:
```gdscript
func _fire_charge(ratio: float) -> void:
	_charging = false
	if _presentation.owns_hud():
		_power_bar.visible = false
	_pending_ratio = ratio
	_begin_strike(_charge_kind)
```

Edit 7 — заменить чтение Input в `_strike_update`. Заменить:
```gdscript
func _strike_update(delta: float) -> void:
	if _pending_kind == "lob":
		_curl_accum += Input.get_axis(&"move_left", &"move_right") * delta
```
на:
```gdscript
func _strike_update(delta: float) -> void:
	if _pending_kind == "lob":
		_curl_accum += _intent.aim_axis().x * delta
```

Edit 8 — гейт камеры в `_update_camera_pose`. Заменить:
```gdscript
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	var eye := _spot - _heading * FootballConstants.CORNER_CAM_BACK + Vector3(0.0, FootballConstants.CORNER_CAM_HEIGHT, 0.0)
```
на:
```gdscript
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	if not _presentation.owns_camera():
		return
	var eye := _spot - _heading * FootballConstants.CORNER_CAM_BACK + Vector3(0.0, FootballConstants.CORNER_CAM_HEIGHT, 0.0)
```

- [ ] **Step 4: Запустить seam-тест — убедиться, что проходит**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_corner_intent.gd"
```
Expected: `CHECK PASS: corner intent seam (...)`.

- [ ] **Step 5: Регрессия — прежние тесты зелёные**

```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_corner_flow.gd"
```
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_corner_no_growth.gd"
```
Expected: два `CHECK PASS`.

- [ ] **Step 6: Валидация сцены**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: только baseline-категории.

- [ ] **Step 7: Коммит**

```bash
git add scripts/match/corner_controller.gd tests/check_corner_intent.gd
git commit -m "refactor(corner): consume KickerIntent/SetPiecePresentation seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: free_kick — перевод на шов

**Files:**
- Modify: `scripts/match/free_kick_controller.gd`
- Test: `tests/check_free_kick_intent.gd` (create)

**Interfaces:**
- Consumes: `KickerIntent`, `HumanKickerIntent`, `SetPiecePresentation`; `_place_kicker()`, `_start_charge(kind)`, `_fire_charge(ratio)`, `_fire_shot(ratio)` (существующие).
- Produces: `free_kick_controller.start(kicker, goal_line_z, intent = null, presentation = null)`; `_default_intent()`; поля `_intent`, `_presentation`. Метод `_charge_released()` УДАЛЯЕТСЯ.
- **Заметка о поведении:** прежний код для «ground» держал заряд, пока нажата ЛЮБАЯ из `pass_short`/`pass_through`. Шов латчит одну (ту, что стартовала заряд) — в патологическом сценарии «зажать обе, отпустить стартовую» выстрел произойдёт раньше. Разница незначима (реально жмут одну кнопку) и принята рамкой роадмапа (шов Варианта 1). Обе кнопки по-прежнему СТАРТУЮТ ground (две записи в `charges` с variant id 1).

- [ ] **Step 1: Написать падающий seam-тест**

Create `tests/check_free_kick_intent.gd`:

```gdscript
extends SceneTree
## Seam-тест штрафного: контроллер потребляет инжектированный KickerIntent (shot-заряд + коммит
## через шов). Драйв — match_manager делегирует update(). Удар уходит в WATCH → релиз по таймеру.

class FakeKickerIntent extends KickerIntent:
	var start_variant: int = -1
	var committed: bool = false
	func aim_axis() -> Vector2:
		return Vector2.ZERO
	func charge_start_variant() -> int:
		var v := start_variant
		start_variant = -1
		return v
	func charge_committed() -> bool:
		return committed

var _mm: Node
var _fk: Node
var _fake: FakeKickerIntent
var _elapsed: float = 0.0
var _state: int = 0
var _max_ball_speed: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 0.15:
				_fk = _mm.get_node_or_null("FreeKickController")
				if _fk == null:
					print("CHECK FAIL: нет узла FreeKickController"); return true
				_mm.controlled_player.global_position = Vector3(5.0, 0.5, -35.0)
				_fake = FakeKickerIntent.new()
				_fk.start(_mm.controlled_player, _mm._keeper_brain.goal_line_z, _fake)
				if not _mm.is_free_kick_active():
					print("CHECK FAIL: режим штрафного не включился"); return true
				_state = 1
		1:
			if _elapsed > 0.4:
				_fake.start_variant = 0    # 0 = shot
				_state = 2
		2:
			if _elapsed > 0.6:
				_fake.committed = true
				_state = 3
		3:
			_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
			# Удар → WATCH → релиз по FK_WATCH_TIME; даём широкое окно.
			if _elapsed > 8.0:
				var released: bool = not _mm.is_free_kick_active()
				var launched: bool = _max_ball_speed > 1.0
				print("SEAM: max_ball_speed=", _max_ball_speed)
				if released and launched:
					print("CHECK PASS: free_kick intent seam (charge+commit через KickerIntent)")
					quit(0)
				else:
					print("CHECK FAIL: released=", str(released), " launched=", str(launched))
					quit(1)
				return true
	if _elapsed > 10.0:
		print("CHECK FAIL: таймаут"); return true
	return false
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_intent.gd"
```
Expected: НЕ `CHECK PASS` — «Too many arguments to `start()`».

- [ ] **Step 3: Реализовать шов в `free_kick_controller.gd`**

Edit 1 — поля. После `var _watch_timer: float = 0.0` (≈37) добавить:
```gdscript
var _intent: KickerIntent
var _presentation: SetPiecePresentation
```

Edit 2 — сигнатура `start()` + init. Заменить:
```gdscript
func start(kicker: CharacterBody3D, goal_line_z: float) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_foot = FootballConstants.FK_DEFAULT_FOOT
	_setup()
```
на:
```gdscript
func start(kicker: CharacterBody3D, goal_line_z: float, intent: KickerIntent = null, presentation: SetPiecePresentation = null) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_foot = FootballConstants.FK_DEFAULT_FOOT
	_intent = intent if intent != null else _default_intent()
	_presentation = presentation if presentation != null else SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
	_setup()
```

Edit 3 — добавить `_default_intent()` перед `func _setup() -> void:`:
```gdscript
## Human-дефолт источника намерения бьющего штрафной (прежние Input-чтения контроллера).
func _default_intent() -> KickerIntent:
	return HumanKickerIntent.new({
		"aim_lat": [&"move_left", &"move_right"],
		"foot": [&"foot_left", &"foot_right"],
		# 0 = удар, 1 = наземный пас (обе кнопки), 2 = навес.
		"charges": [[&"kick", 0], [&"pass_short", 1], [&"pass_through", 1], [&"pass_lob", 2]],
	})

```

Edit 4 — заменить `_aim_update` целиком:
```gdscript
func _aim_update(delta: float) -> void:
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога определяется выбранным бьющим).
	if Input.is_action_just_pressed(&"foot_left") and _foot != "penalty_l":
		_foot = "penalty_l"
		_place_kicker()
	elif Input.is_action_just_pressed(&"foot_right") and _foot != "penalty_r":
		_foot = "penalty_r"
		_place_kicker()
	var stick_x := Input.get_axis(&"move_left", &"move_right")
	# До нажатия kick: стик крутит heading (камера едет). После нажатия: heading зафиксирован,
	# боковой ввод копится в закрутку.
	if not _locked:
		if absf(stick_x) > 0.15:
			# Крутим направление вылета (камеру). Бьющего НЕ доворачиваем — он смотрит на мяч
			# (_base_heading), чтобы разбег всегда шёл к мячу.
			_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
				FootballConstants.FK_AIM_SPEED, delta, FootballConstants.FK_AIM_ARC)
		# Старт заряда: удар / наземный пас / навес — все через удержание кнопки (сила растёт).
		if Input.is_action_just_pressed(&"kick"):
			_start_charge("shot")
		elif Input.is_action_just_pressed(&"pass_short") or Input.is_action_just_pressed(&"pass_through"):
			_start_charge("ground")
		elif Input.is_action_just_pressed(&"pass_lob"):
			_start_charge("lob")
	if _charging:
		_charge += delta
		if _charge_kind == "shot":
			_curl_accum += stick_x * delta   # закрутка копится только для удара
		var ratio := clampf(_charge / FootballConstants.FK_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _charge_released():
			_fire_charge(ratio)
```
на:
```gdscript
func _aim_update(delta: float) -> void:
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога определяется выбранным бьющим).
	var fs := _intent.foot_switch()
	if fs == -1 and _foot != "penalty_l":
		_foot = "penalty_l"
		_place_kicker()
	elif fs == 1 and _foot != "penalty_r":
		_foot = "penalty_r"
		_place_kicker()
	var stick_x := _intent.aim_axis().x
	# До нажатия kick: стик крутит heading (камера едет). После нажатия: heading зафиксирован,
	# боковой ввод копится в закрутку.
	if not _locked:
		if absf(stick_x) > 0.15:
			# Крутим направление вылета (камеру). Бьющего НЕ доворачиваем — он смотрит на мяч
			# (_base_heading), чтобы разбег всегда шёл к мячу.
			_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
				FootballConstants.FK_AIM_SPEED, delta, FootballConstants.FK_AIM_ARC)
		# Старт заряда: удар / наземный пас / навес — все через удержание кнопки (сила растёт).
		var v := _intent.charge_start_variant()
		if v == 0:
			_start_charge("shot")
		elif v == 1:
			_start_charge("ground")
		elif v == 2:
			_start_charge("lob")
	if _charging:
		_charge += delta
		if _charge_kind == "shot":
			_curl_accum += stick_x * delta   # закрутка копится только для удара
		var ratio := clampf(_charge / FootballConstants.FK_CHARGE_MAX_TIME, 0.0, 1.0)
		if _presentation.owns_hud():
			_power_bar.visible = true
			_power_bar.value = ratio
			var fill := _power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _intent.charge_committed():
			_fire_charge(ratio)
```

Edit 5 — гейт power_bar в `_fire_charge`. Заменить:
```gdscript
func _fire_charge(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	if _charge_kind == "shot":
```
на:
```gdscript
func _fire_charge(ratio: float) -> void:
	_charging = false
	if _presentation.owns_hud():
		_power_bar.visible = false
	if _charge_kind == "shot":
```

Edit 6 — гейт power_bar в `_fire_shot`. Заменить:
```gdscript
func _fire_shot(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	var vel := FreeKickLogic.launch_velocity(_heading, ratio,
```
на:
```gdscript
func _fire_shot(ratio: float) -> void:
	_charging = false
	if _presentation.owns_hud():
		_power_bar.visible = false
	var vel := FreeKickLogic.launch_velocity(_heading, ratio,
```

Edit 7 — удалить метод `_charge_released()` целиком:
```gdscript
## Кнопка текущего заряжаемого действия отпущена?
func _charge_released() -> bool:
	match _charge_kind:
		"shot":
			return not Input.is_action_pressed(&"kick")
		"lob":
			return not Input.is_action_pressed(&"pass_lob")
		_:
			return not (Input.is_action_pressed(&"pass_short") or Input.is_action_pressed(&"pass_through"))

```

Edit 8 — заменить чтение Input в `_strike_update`. Заменить:
```gdscript
	if _pending_kind == "shot":
		_curl_accum += Input.get_axis(&"move_left", &"move_right") * delta
```
на:
```gdscript
	if _pending_kind == "shot":
		_curl_accum += _intent.aim_axis().x * delta
```

Edit 9 — гейт камеры в `_update_camera_pose`. Заменить:
```gdscript
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	var eye := _spot - _heading * FootballConstants.FK_CAM_BACK + Vector3(0.0, FootballConstants.FK_CAM_HEIGHT, 0.0)
```
на:
```gdscript
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	if not _presentation.owns_camera():
		return
	var eye := _spot - _heading * FootballConstants.FK_CAM_BACK + Vector3(0.0, FootballConstants.FK_CAM_HEIGHT, 0.0)
```

- [ ] **Step 4: Запустить seam-тест — убедиться, что проходит**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_intent.gd"
```
Expected: `CHECK PASS: free_kick intent seam (...)`.

- [ ] **Step 5: Регрессия — прежний flow-тест зелёный**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_flow.gd"
```
Expected: `CHECK PASS: free_kick flow (launch + convert + no accumulation)`.

- [ ] **Step 6: Валидация сцены**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: только baseline-категории.

- [ ] **Step 7: Коммит**

```bash
git add scripts/match/free_kick_controller.gd tests/check_free_kick_intent.gd
git commit -m "refactor(free-kick): consume KickerIntent/SetPiecePresentation seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Финальная проверка (после Task 4)

- [ ] **Прогнать все 4 seam-теста + 4 flow-теста подряд** (каждый отдельным вызовом) — убедиться, что все зелёные (нет взаимной регрессии).
- [ ] **Проверить грепом**, что во всех 4 контроллерах не осталось `Input.` в `_aim_update`/`_strike_update`/`_charge_released` (метод удалён):
```bash
grep -n "Input\." scripts/match/throw_in_controller.gd scripts/match/goal_kick_controller.gd scripts/match/corner_controller.gd scripts/match/free_kick_controller.gd
```
Expected: пусто (ни одного вхождения `Input.` в этих 4 файлах).
- [ ] **Обновить `CLAUDE.md`** (раздел про контроллеры/пенальти-шов): отметить, что все 6 контроллеров стандартов (penalty + эти 4 + будущий kickoff) теперь читают ввод через `KickerIntent`/`SetPiecePresentation`, а не `Input.*`. Закоммитить отдельным `docs:`-коммитом.
- [ ] **Ручная проверка в игре (человек, не headless):** запустить игру, по очереди T/G/C/F — прицел стиком, заряд/варианты, смена ноги, у углового corner_call, у штрафного/углового закрутка — всё как раньше; камера/power_bar на месте. Headless фил не покрывает.

## Self-Review (сверка с рамкой роадмапа)

1. **Покрытие рамки (роадмап §«Шов источника намерения», Этап 0 п.3):** все 4 оставшихся контроллера переведены с `Input.*` на `_intent.*`; владение камерой/баром вынесено в `SetPiecePresentation` (двухуровневый профиль, роль KICKER по умолчанию). `match_manager`/`*_logic.gd` не тронуты. ✔
2. **Плейсхолдеры:** нет — каждый Edit показывает полный до/после-код; тесты приведены целиком. ✔
3. **Согласованность типов/имён:** `_intent: KickerIntent`, `_presentation: SetPiecePresentation`, `_default_intent() -> KickerIntent`, `start(..., intent = null, presentation = null)` — одинаково во всех 4 задачах; методы шва (`aim_axis`/`foot_switch`/`charge_start_variant`/`charge_committed`/`secondary`) совпадают с `scripts/match/kicker_intent.gd`. Variant id согласованы с cfg `charges` в каждом `_default_intent()`. ✔
4. **Поведение «как было»:** роль по умолчанию KICKER → `owns_hud()`/`owns_camera()` = true → power_bar/камера ведут себя идентично; flow-тесты (прямой `_fire_*`) остаются валидны как регрессия. Единственное сознательное микро-отличие — OR-заряд ground у штрафного (латч одной кнопки), задокументировано в Task 4. ✔

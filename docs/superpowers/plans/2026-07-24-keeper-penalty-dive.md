# Keeper Penalty Dive (KeeperIntent) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать пенальти второго актёра под управлением — вратаря: человек стиком выбирает зону нырка (5 зон) вплоть до удара, а бьёт простой ИИ-стаб; запуск по новой тест-клавише K.

**Architecture:** Новый per-actor шов `KeeperIntent` (Human/AI), симметричный `KickerIntent`. Простой `AIKickerIntent` (пауза-обдумывание → фикс-прицел → фикс-заряд). `SetPiecePresentation` из пилота становится ролевым (`Role {NONE, KICKER, KEEPER, WALL}`). `penalty_controller` потребляет `_keeper_intent.dive_zone()` на `action_contact` вместо слепого `random_dive_zone`. Клавиша K в `match_manager` собирает связку AI-бьющий + человек-вратарь.

**Tech Stack:** Godot 4.7 / GDScript. Headless-тесты — `tests/check_*.gd` (`extends SceneTree`, `CHECK PASS`/`FAIL`, `quit(0/1)`).

## Global Constraints

- **Опирается на шов из плана B1** (уже в репо): `KickerIntent`/`HumanKickerIntent` (`scripts/match/kicker_intent.gd`, `human_kicker_intent.gd`), `SetPiecePresentation` (`set_piece_presentation.gd`, СЕЙЧАС бинарный `new(is_local_human: bool)` — этот план его переделывает на ролевой). Пенальти-контроллер уже потребляет `_intent`/`_presentation`.
- **Поведение клавиши P не меняется** — все новые параметры `start_single` опциональны с дефолтами, дающими прежнее поведение. `check_penalty_flow.gd` (зовёт `start_single` с 2 аргументами) — регрессионная страховка, НЕ трогать.
- **Чистые функции (`PenaltyLogic`) не читают `FootballConstants`** — тюнинг параметрами. **ИИ-интенты (`AIKickerIntent`/`AIKeeperIntent`) — это ИИ-скрипты**, читают `FootballConstants` напрямую (как `keeper_ai.gd`).
- **Гочи Godot (из планов A/B):** после нового `class_name`-файла нужен `--headless --import` ОТДЕЛЬНОЙ командой перед `-s`-тестом (не чейнить импорт и тест в одном bash-вызове — гонка flush кэша). `RefCounted`-классы тестируются синхронно в `_init` через фейковый сабкласс, переопределяющий источник ввода/времени.
- **Тест-раннер:** `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/<name>.gd"` → `CHECK PASS`, exit 0.
- **Валидация сцены:** `& "<godot>" --path "<repo>" --headless --quit-after 2 res://scenes/match.tscn`. Baseline-категории (не регрессии): `Condition "!is_inside_tree()"`, `Condition "states.has(p_name)"`, `Condition "transitions[i]..."`, `Cannot get class 'WorldEnvironment3D'`. Диффать по КАТЕГОРИИ текста.
- **Автолоад `FootballConstants` доступен в `-s`-тестах** (Godot грузит автолоады до скрипта). `AIKickerIntent`-тест на это опирается.

---

## File Structure

- **Modify** `scripts/match/penalty_logic.gd` — добавить чистую `stick_to_zone(stick, deadzone) -> int`.
- **Create** `scripts/match/keeper_intent.gd` — `class_name KeeperIntent extends RefCounted`, база (`dive_zone()`).
- **Create** `scripts/match/human_keeper_intent.gd` — `HumanKeeperIntent`, конфиг осей, `_axis` переопределяем.
- **Create** `scripts/match/ai_keeper_intent.gd` — `AIKeeperIntent`, кэш случайного выбора.
- **Modify** `scripts/match/kicker_intent.gd` — добавить дефолты `has_fixed_aim()`/`aim_target()`.
- **Create** `scripts/match/ai_kicker_intent.gd` — `AIKickerIntent extends KickerIntent`, таймер обдумывания/заряда, фикс-прицел, `_now_msec` переопределяем.
- **Modify** `scripts/match/set_piece_presentation.gd` — ролевой (`enum Role`, `owns_camera/owns_hud/owns_keeper_marker`).
- **Modify** `scripts/match/penalty_controller.gd` — `_keeper_intent`, 5-й параметр `start_single`, срез зоны в `_on_kicker_contact`, ветка фикс-прицела, cyan-маркер вратаря.
- **Modify** `scripts/data/football_constants.gd` — `AI_PENALTY_THINK_TIME`/`_CHARGE_RATIO`/`_AIM_SPREAD`.
- **Modify** `scripts/match/match_manager.gd` — action `keeper_dive_debug` (K) + триггер-блок.
- **Create** `tests/check_keeper_intent.gd`, `tests/check_ai_kicker_intent.gd`.
- **Modify** `tests/check_human_kicker_intent.gd` — обновить presentation-проверку под ролевой API.

---

## Task 1: Keeper-side seam (`stick_to_zone` + `KeeperIntent`/`HumanKeeperIntent`/`AIKeeperIntent`)

**Files:**
- Modify: `scripts/match/penalty_logic.gd`
- Create: `scripts/match/keeper_intent.gd`, `scripts/match/human_keeper_intent.gd`, `scripts/match/ai_keeper_intent.gd`
- Test: `tests/check_keeper_intent.gd`

**Interfaces:**
- Consumes: `PenaltyLogic.Zone` (существует: `LOW_L, HIGH_L, LOW_R, HIGH_R, CENTER`), `PenaltyLogic.random_dive_zone(rng)` (существует).
- Produces:
  - `PenaltyLogic.stick_to_zone(stick: Vector2, deadzone: float) -> int`
  - `KeeperIntent.dive_zone() -> int` (база → `Zone.CENTER`)
  - `HumanKeeperIntent.new(cfg: Dictionary)` где cfg: `aim_lat: [neg, pos]`, `aim_vert: [neg, pos]`; `dive_zone()`; переопределяемый `_axis(neg, pos)`.
  - `AIKeeperIntent.new(rng: RandomNumberGenerator)`; `dive_zone()` (кэш).

- [ ] **Step 1: Написать падающий тест**

Create `tests/check_keeper_intent.gd`:

```gdscript
extends SceneTree
## Headless-проверка keeper-шва: stick_to_zone (5 зон + дедзона), HumanKeeperIntent (через
## фейковый сабкласс со скриптованными осями), AIKeeperIntent (детерминизм по сиду). Всё
## синхронно в _init — RefCounted, узлы не нужны.

class _FakeHKI extends HumanKeeperIntent:
	var ax_lat := 0.0   # значение _axis(...move_right)
	var ax_vert := 0.0  # значение _axis(...move_back)
	func _axis(neg: StringName, pos: StringName) -> float:
		if pos == &"move_right": return ax_lat
		if pos == &"move_back": return ax_vert
		return 0.0

func _init() -> void:
	var ok := true

	# stick_to_zone: знаки → зоны, дедзона → CENTER.
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(0, 0), 0.15), PenaltyLogic.Zone.CENTER, "нейтраль→CENTER") and ok
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(0.1, 0.05), 0.15), PenaltyLogic.Zone.CENTER, "в дедзоне→CENTER") and ok
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(-1, 1), 0.15), PenaltyLogic.Zone.HIGH_L, "лево-верх→HIGH_L") and ok
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(-1, -1), 0.15), PenaltyLogic.Zone.LOW_L, "лево-низ→LOW_L") and ok
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(1, 1), 0.15), PenaltyLogic.Zone.HIGH_R, "право-верх→HIGH_R") and ok
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(1, -1), 0.15), PenaltyLogic.Zone.LOW_R, "право-низ→LOW_R") and ok

	# HumanKeeperIntent: конфиг осей → стик → зона.
	var cfg := {"aim_lat": [&"move_left", &"move_right"], "aim_vert": [&"move_forward", &"move_back"]}
	var f := _FakeHKI.new(cfg)
	# ax_lat=+1 (право), ax_vert=-1 → y = -(-1)=+1 (верх) → HIGH_R.
	f.ax_lat = 1.0
	f.ax_vert = -1.0
	ok = _z(f.dive_zone(), PenaltyLogic.Zone.HIGH_R, "HKI право+верх→HIGH_R") and ok
	# нейтраль → CENTER.
	f.ax_lat = 0.0
	f.ax_vert = 0.0
	ok = _z(f.dive_zone(), PenaltyLogic.Zone.CENTER, "HKI нейтраль→CENTER") and ok

	# База KeeperIntent → CENTER.
	ok = _z(KeeperIntent.new().dive_zone(), PenaltyLogic.Zone.CENTER, "база→CENTER") and ok

	# AIKeeperIntent: один выбор по сиду, стабилен между вызовами и в [0,4].
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var ai := AIKeeperIntent.new(rng)
	var z1 := ai.dive_zone()
	var z2 := ai.dive_zone()
	ok = _expect(z1 == z2 and z1 >= 0 and z1 <= 4, "AIKeeper детерминирован в [0,4]") and ok

	if ok:
		print("CHECK PASS: keeper_intent")
		quit(0)
	else:
		print("CHECK FAIL: keeper_intent")
		quit(1)

func _z(got: int, want: int, label: String) -> bool:
	if got != want:
		print("  FAIL: ", label, " got=", got, " want=", want)
		return false
	return true

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_keeper_intent.gd"`
Expected: parse error — `KeeperIntent`/`stick_to_zone` ещё нет.

- [ ] **Step 3: Добавить `stick_to_zone` в `PenaltyLogic`**

В `scripts/match/penalty_logic.gd` после `random_dive_zone` (конец файла) добавить:

```gdscript

## Квадрант стика → зона нырка. stick.x: лево<0/право>0; stick.y: низ<0/верх>0 (уже
## инвертированный aim_axis). Длина ниже deadzone → CENTER.
static func stick_to_zone(stick: Vector2, deadzone: float) -> int:
	if stick.length() < deadzone:
		return Zone.CENTER
	if stick.x < 0.0:
		return Zone.HIGH_L if stick.y > 0.0 else Zone.LOW_L
	return Zone.HIGH_R if stick.y > 0.0 else Zone.LOW_R
```

- [ ] **Step 4: Создать `KeeperIntent` (база)**

Create `scripts/match/keeper_intent.gd`:

```gdscript
class_name KeeperIntent
extends RefCounted
## Источник намерения вратаря в стандарте (per-actor шов, симметричен KickerIntent). Контроллер
## читает dive_zone() ОДИН раз в момент удара (action_contact бьющего) — коммита у вратаря нет,
## момент нырка принадлежит контроллеру. База — no-op (центр).

## Выбранная зона нырка (PenaltyLogic.Zone).
func dive_zone() -> int:
	return PenaltyLogic.Zone.CENTER
```

- [ ] **Step 5: Создать `HumanKeeperIntent`**

Create `scripts/match/human_keeper_intent.gd`:

```gdscript
class_name HumanKeeperIntent
extends KeeperIntent
## Human-вратарь: зона нырка из квадранта стика (крутится вплоть до удара). Конфиг осей;
## ввод через переопределяемый _axis (для headless-теста). Дедзона 0.15 (как порог прицела бьющего).

var _cfg: Dictionary

func _init(cfg: Dictionary) -> void:
	_cfg = cfg

func _axis(neg: StringName, pos: StringName) -> float:
	return Input.get_axis(neg, pos)

func dive_zone() -> int:
	var lat: Array = _cfg.get("aim_lat", [])
	var vert: Array = _cfg.get("aim_vert", [])
	var x := _axis(lat[0], lat[1]) if lat.size() == 2 else 0.0
	var y := -_axis(vert[0], vert[1]) if vert.size() == 2 else 0.0
	return PenaltyLogic.stick_to_zone(Vector2(x, y), 0.15)
```

- [ ] **Step 6: Создать `AIKeeperIntent`**

Create `scripts/match/ai_keeper_intent.gd`:

```gdscript
class_name AIKeeperIntent
extends KeeperIntent
## AI-вратарь: слепой выбор зоны ОДИН раз при создании (кэш) — ровно текущее поведение под P,
## но через шов. dive_zone() всегда возвращает кэш (не переигрывается каждый кадр).

var _zone: int

func _init(rng: RandomNumberGenerator) -> void:
	_zone = PenaltyLogic.random_dive_zone(rng)

func dive_zone() -> int:
	return _zone
```

- [ ] **Step 7: Импорт-пасс (регистрация новых `class_name`)**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import`
Expected: `[ DONE ] update_scripts_classes`, exit 0.

- [ ] **Step 8: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_keeper_intent.gd"`
Expected: `CHECK PASS: keeper_intent`, exit 0.

- [ ] **Step 9: Коммит**

```bash
git add scripts/match/penalty_logic.gd scripts/match/keeper_intent.gd scripts/match/human_keeper_intent.gd scripts/match/ai_keeper_intent.gd tests/check_keeper_intent.gd scripts/match/keeper_intent.gd.uid scripts/match/human_keeper_intent.gd.uid scripts/match/ai_keeper_intent.gd.uid .godot/global_script_class_cache.cfg
git commit -m "feat(penalty): KeeperIntent seam — stick_to_zone + Human/AI keeper intents"
```

---

## Task 2: AI-бьющий стаб (`AIKickerIntent`) + константы

**Files:**
- Modify: `scripts/match/kicker_intent.gd`, `scripts/data/football_constants.gd`
- Create: `scripts/match/ai_kicker_intent.gd`
- Test: `tests/check_ai_kicker_intent.gd`

**Interfaces:**
- Consumes: `KickerIntent` (существует, план B1).
- Produces:
  - `KickerIntent.has_fixed_aim() -> bool` (база → false), `KickerIntent.aim_target() -> Vector2` (база → ZERO).
  - `AIKickerIntent.new(rng)` — `has_fixed_aim()→true`, `aim_target()→фикс-точка в створе`, `charge_start_variant()` (после THINK, один раз 0), `charge_committed()` (после CHARGE_RATIO*MAX), `foot_switch()→0`, `modifier_held()→false`; переопределяемый `_now_msec()`.
  - Константы `FootballConstants.AI_PENALTY_THINK_TIME`, `AI_PENALTY_CHARGE_RATIO`, `AI_PENALTY_AIM_SPREAD`.

- [ ] **Step 1: Добавить константы**

В `scripts/data/football_constants.gd` в секции `PENALTY (Фаза A)`, после `const PEN_WATCH_TIME := 1.5`, добавить:

```gdscript

# ИИ-бьющий пенальти (стаб): пауза обдумывания до заряда, доля заряда, разброс прицела по створу.
const AI_PENALTY_THINK_TIME := 0.8    # с — «думает» перед разбегом
const AI_PENALTY_CHARGE_RATIO := 0.7  # доля заряда (сила удара)
const AI_PENALTY_AIM_SPREAD := 0.7    # 0..1 разброс прицела по полуширине створа
```

- [ ] **Step 2: Написать падающий тест**

Create `tests/check_ai_kicker_intent.gd`:

```gdscript
extends SceneTree
## Headless-проверка AIKickerIntent через фейковый сабкласс с переопределённым _now_msec()
## (скриптуем время без sleep). Опирается на автолоад FootballConstants (доступен в -s).

class _FakeAKI extends AIKickerIntent:
	var t := 0
	func _now_msec() -> int: return t

func _init() -> void:
	var ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var a := _FakeAKI.new(rng)   # _init читает _now_msec()=t=0 → _start_msec=0

	var think_ms := int(FootballConstants.AI_PENALTY_THINK_TIME * 1000.0)
	var charge_ms := int(FootballConstants.AI_PENALTY_CHARGE_RATIO * FootballConstants.PEN_CHARGE_MAX_TIME * 1000.0)

	# До окончания обдумывания заряд не стартует.
	a.t = think_ms - 100
	ok = _expect(a.charge_start_variant() == -1, "до THINK: charge_start = -1") and ok
	# После — стартует один раз (вариант 0), латчит.
	a.t = think_ms + 50
	ok = _expect(a.charge_start_variant() == 0, "после THINK: charge_start = 0") and ok
	ok = _expect(a.charge_start_variant() == -1, "charge_start только раз") and ok
	# Коммит — после CHARGE_RATIO*MAX от старта заряда (старт был на think_ms+50).
	ok = _expect(a.charge_committed() == false, "до заряда: не коммит") and ok
	a.t = think_ms + 50 + charge_ms + 10
	ok = _expect(a.charge_committed() == true, "после заряда: коммит") and ok

	# Фикс-прицел: стабилен и внутри створа.
	ok = _expect(a.has_fixed_aim() == true, "has_fixed_aim true") and ok
	var t1 := a.aim_target()
	var t2 := a.aim_target()
	ok = _expect(t1 == t2, "aim_target стабилен") and ok
	var hw := FootballConstants.GOAL_WIDTH * 0.5 * FootballConstants.AI_PENALTY_AIM_SPREAD
	ok = _expect(absf(t1.x) <= hw + 0.001 and t1.y >= 0.3 - 0.001 and t1.y <= FootballConstants.GOAL_HEIGHT * 0.7 + 0.001, "aim_target в створе") and ok

	# foot/modifier — no-op.
	ok = _expect(a.foot_switch() == 0 and a.modifier_held() == false, "foot/modifier no-op") and ok

	if ok:
		print("CHECK PASS: ai_kicker_intent")
		quit(0)
	else:
		print("CHECK FAIL: ai_kicker_intent")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond
```

- [ ] **Step 3: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ai_kicker_intent.gd"`
Expected: parse error — `AIKickerIntent` ещё нет.

- [ ] **Step 4: Добавить дефолты фикс-прицела в `KickerIntent`**

В `scripts/match/kicker_intent.gd` перед `func secondary()` добавить:

```gdscript
## У источника фиксированная цель прицела (ИИ знает точку сразу)? Human → false (целится стиком).
func has_fixed_aim() -> bool:
	return false

## Фиксированная точка прицела на плоскости ворот (x от центра, y высота). Только при has_fixed_aim().
func aim_target() -> Vector2:
	return Vector2.ZERO

```

- [ ] **Step 5: Создать `AIKickerIntent`**

Create `scripts/match/ai_kicker_intent.gd`:

```gdscript
class_name AIKickerIntent
extends KickerIntent
## Простой ИИ-бьющий пенальти (стаб): пауза обдумывания → фиксированный прицел (случайная точка
## в створе) → фиксированный заряд → удар. ИИ-скрипт (не чистая логика) — читает FootballConstants.
## Время через переопределяемый _now_msec() (для headless-теста без sleep).

var _start_msec: int
var _charge_start_msec: int = -1
var _aim_target_v: Vector2

func _init(rng: RandomNumberGenerator) -> void:
	_start_msec = _now_msec()
	var hw := FootballConstants.GOAL_WIDTH * 0.5 * FootballConstants.AI_PENALTY_AIM_SPREAD
	var tx := rng.randf_range(-hw, hw)
	var ty := rng.randf_range(0.3, FootballConstants.GOAL_HEIGHT * 0.7)
	_aim_target_v = Vector2(tx, ty)

func _now_msec() -> int:
	return Time.get_ticks_msec()

func has_fixed_aim() -> bool:
	return true

func aim_target() -> Vector2:
	return _aim_target_v

func charge_start_variant() -> int:
	if _charge_start_msec >= 0:
		return -1
	if _now_msec() - _start_msec >= int(FootballConstants.AI_PENALTY_THINK_TIME * 1000.0):
		_charge_start_msec = _now_msec()
		return 0
	return -1

func charge_committed() -> bool:
	if _charge_start_msec < 0:
		return false
	return _now_msec() - _charge_start_msec >= int(FootballConstants.AI_PENALTY_CHARGE_RATIO * FootballConstants.PEN_CHARGE_MAX_TIME * 1000.0)

func foot_switch() -> int:
	return 0

func modifier_held() -> bool:
	return false
```

- [ ] **Step 6: Импорт-пасс + запуск теста**

Run (импорт, затем ОТДЕЛЬНОЙ командой тест):
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import
```
затем:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ai_kicker_intent.gd"
```
Expected: `CHECK PASS: ai_kicker_intent`, exit 0.

- [ ] **Step 7: Коммит**

```bash
git add scripts/match/kicker_intent.gd scripts/match/ai_kicker_intent.gd scripts/data/football_constants.gd tests/check_ai_kicker_intent.gd scripts/match/ai_kicker_intent.gd.uid .godot/global_script_class_cache.cfg
git commit -m "feat(penalty): AIKickerIntent stub (think/aim/charge) + fixed-aim seam methods"
```

---

## Task 3: Ролевой `SetPiecePresentation` + обновление вызовов

**Files:**
- Modify: `scripts/match/set_piece_presentation.gd`
- Modify: `scripts/match/penalty_controller.gd` (вызов в `setup`)
- Modify: `tests/check_human_kicker_intent.gd` (presentation-проверка)

**Interfaces:**
- Produces: `SetPiecePresentation.Role { NONE, KICKER, KEEPER, WALL }`; `SetPiecePresentation.new(local_role: int)`; `owns_camera()` (role != NONE), `owns_hud()` (role == KICKER), `owns_keeper_marker()` (role == KEEPER).
- **Breaking:** конструктор теперь берёт `int` (роль), не `bool`. Все вызовы обновляются в этой задаче.

- [ ] **Step 1: Переписать `SetPiecePresentation` на роли**

Заменить весь `scripts/match/set_piece_presentation.gd`:

```gdscript
class_name SetPiecePresentation
extends RefCounted
## Профиль презентации стандарта по РОЛИ локального человека (один факт → вся презентация).
## Камера включается, если человек участвует в любой роли; состав HUD — по роли.
## WALL — задел под штрафной (Этап 2), сейчас не используется.

enum Role { NONE, KICKER, KEEPER, WALL }

var _local_role: int

func _init(local_role: int) -> void:
	_local_role = local_role

func owns_camera() -> bool:
	return _local_role != Role.NONE

func owns_hud() -> bool:
	return _local_role == Role.KICKER   # ретикл/power_bar бьющего

func owns_keeper_marker() -> bool:
	return _local_role == Role.KEEPER
```

- [ ] **Step 2: Обновить вызов в `penalty_controller.setup`**

В `scripts/match/penalty_controller.gd`, в `setup(...)`, заменить:

```gdscript
	_presentation = SetPiecePresentation.new(true)
```
на:
```gdscript
	_presentation = SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
```

- [ ] **Step 3: Обновить presentation-проверку в `check_human_kicker_intent.gd`**

В `tests/check_human_kicker_intent.gd` заменить блок:

```gdscript
	# Презентация: is_local_human → owns всё; иначе ничего.
	var ph := SetPiecePresentation.new(true)
	var po := SetPiecePresentation.new(false)
	ok = _expect(ph.owns_camera() and ph.owns_hud(), "human владеет camera+hud") and ok
	ok = _expect(not po.owns_camera() and not po.owns_hud(), "observer не владеет") and ok
```
на:
```gdscript
	# Презентация по роли: KICKER → камера+HUD, без keeper-маркера; KEEPER → камера+маркер, без HUD; NONE → ничего.
	var pk := SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
	var pkeep := SetPiecePresentation.new(SetPiecePresentation.Role.KEEPER)
	var pn := SetPiecePresentation.new(SetPiecePresentation.Role.NONE)
	ok = _expect(pk.owns_camera() and pk.owns_hud() and not pk.owns_keeper_marker(), "KICKER: камера+HUD") and ok
	ok = _expect(pkeep.owns_camera() and not pkeep.owns_hud() and pkeep.owns_keeper_marker(), "KEEPER: камера+маркер") and ok
	ok = _expect(not pn.owns_camera() and not pn.owns_hud() and not pn.owns_keeper_marker(), "NONE: ничего") and ok
```

- [ ] **Step 4: Импорт-пасс + регрессия теста шва**

Run (импорт, затем тест):
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import
```
затем:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_human_kicker_intent.gd"
```
Expected: `CHECK PASS: human_kicker_intent`.

- [ ] **Step 5: Валидация сцены**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: грузится (exit 0), только baseline-категории ошибок.

- [ ] **Step 6: Коммит**

```bash
git add scripts/match/set_piece_presentation.gd scripts/match/penalty_controller.gd tests/check_human_kicker_intent.gd
git commit -m "refactor(setpiece): SetPiecePresentation role-based (KICKER/KEEPER/WALL)"
```

---

## Task 4: Интеграция в `penalty_controller` (keeper-intent, срез зоны, фикс-прицел, маркер)

**Files:**
- Modify: `scripts/match/penalty_controller.gd`

**Interfaces:**
- Consumes: `KeeperIntent`/`AIKeeperIntent` (Task 1), `KickerIntent.has_fixed_aim/aim_target` (Task 2), `SetPiecePresentation.Role`/`owns_keeper_marker` (Task 3).
- Produces: `start_single(kicker, goal_line_z, intent=null, presentation=null, keeper_intent=null)` — 5-й опциональный параметр; дефолт `AIKeeperIntent.new(_pen_rng)`.

- [ ] **Step 1: Объявить поле keeper-intent**

В `scripts/match/penalty_controller.gd` после строки `var _presentation: SetPiecePresentation` добавить:

```gdscript
var _keeper_intent: KeeperIntent
```

- [ ] **Step 2: Принять keeper_intent в `start_single`**

Заменить сигнатуру и тело присваивания интентов `start_single`:

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
на:
```gdscript
func start_single(kicker: CharacterBody3D, goal_line_z: float, intent: KickerIntent = null, presentation: SetPiecePresentation = null, keeper_intent: KeeperIntent = null) -> void:
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
	_keeper_intent = keeper_intent if keeper_intent != null else AIKeeperIntent.new(_pen_rng)   # дефолт = слепой ИИ (поведение P)
	_setup()
```

- [ ] **Step 3: Убрать слепой срез зоны из `_fire`**

В `_fire(...)` удалить строки (комментарий + присваивание):

```gdscript
	# Зона вратаря выбирается вслепую заранее, коммитим на контакте.
	_struck_zone = PenaltyLogic.random_dive_zone(_pen_rng)
```
(просто удалить обе строки — следующая строка `# Запускаем клип удара (root motion) и ждём action_contact.` остаётся).

- [ ] **Step 4: Срез зоны из keeper-intent в `_on_kicker_contact`**

В `_on_kicker_contact(...)` заменить:

```gdscript
	if _keeper_brain != null and _keeper_brain.has_method(&"begin_penalty_dive"):
		_keeper_brain.begin_penalty_dive(_struck_zone)
```
на:
```gdscript
	_struck_zone = _keeper_intent.dive_zone()   # срез зоны в момент удара (человек-вратарь мог крутить до последнего)
	if _keeper_brain != null and _keeper_brain.has_method(&"begin_penalty_dive"):
		_keeper_brain.begin_penalty_dive(_struck_zone)
```

- [ ] **Step 5: Ветка фиксированного прицела в `_aim_update`**

В `_aim_update(...)` заменить блок прицела:

```gdscript
	# Прицел стиком/стрелками: X = ширина, вверх стика = выше в воротах (инвертируем Y).
	var aim_stick := _intent.aim_axis()
	if aim_stick.length() > 0.15:
		_aim = PenaltyLogic.move_reticle(_aim, aim_stick, FootballConstants.PEN_RETICLE_SPEED, delta,
			FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.GOAL_HEIGHT, FootballConstants.PEN_AIM_OVERHANG)
	else:
		# Нет ввода — метка плавно, но быстро возвращается в центр створа.
		var center := Vector2(0.0, FootballConstants.PEN_RETICLE_START_Y)
		_aim = _aim.lerp(center, clampf(FootballConstants.PEN_RETICLE_RETURN * delta, 0.0, 1.0))
```
на:
```gdscript
	# Прицел: ИИ — фиксированная цель сразу; человек — стик/стрелки (интеграция + возврат к центру).
	if _intent.has_fixed_aim():
		_aim = _intent.aim_target()
	else:
		var aim_stick := _intent.aim_axis()
		if aim_stick.length() > 0.15:
			_aim = PenaltyLogic.move_reticle(_aim, aim_stick, FootballConstants.PEN_RETICLE_SPEED, delta,
				FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.GOAL_HEIGHT, FootballConstants.PEN_AIM_OVERHANG)
		else:
			# Нет ввода — метка плавно, но быстро возвращается в центр створа.
			var center := Vector2(0.0, FootballConstants.PEN_RETICLE_START_Y)
			_aim = _aim.lerp(center, clampf(FootballConstants.PEN_RETICLE_RETURN * delta, 0.0, 1.0))
```

- [ ] **Step 6: Построить cyan-маркер вратаря (в `setup`)**

В `setup(...)`, после строки `_build_reticle()` (перед `_presentation = ...`), добавить:

```gdscript
	_build_keeper_marker()
```

Добавить сам метод рядом с `_build_reticle` (например, сразу после `_build_reticle`-функции):

```gdscript
## Cyan-маркер над вратарём (конус вершиной вниз) — показывается, когда локальный человек играет
## роль вратаря (K-тест). Строится один раз, позиционируется каждый кадр в _update_keeper_marker.
func _build_keeper_marker() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.25
	mesh.height = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.9, 1.0)   # cyan (как маркер управляемого игрока)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mesh.material = mat
	_keeper_marker = MeshInstance3D.new()
	_keeper_marker.name = "KeeperMarker"
	_keeper_marker.mesh = mesh
	_keeper_marker.rotation.z = PI   # вершина вниз (указывает на вратаря)
	_keeper_marker.visible = false
	add_child(_keeper_marker)
```

Объявить поле рядом с `_reticle`:

```gdscript
var _keeper_marker: MeshInstance3D
```

- [ ] **Step 7: Обновлять маркер в `update`**

В `update(...)` после `_update_reticle()` добавить `_update_keeper_marker()`:

```gdscript
	_update_reticle()
	_update_keeper_marker()
	_update_camera_pose()
```

Добавить метод рядом с `_update_reticle`:

```gdscript
## Позиция/видимость cyan-маркера вратаря: над головой _keeper, пока роль локального человека = KEEPER.
func _update_keeper_marker() -> void:
	if _keeper_marker == null:
		return
	var show_it := _phase != Phase.IDLE and _keeper != null and _presentation.owns_keeper_marker()
	_keeper_marker.visible = show_it
	if show_it:
		_keeper_marker.global_position = _keeper.global_position + Vector3(0.0, 2.3, 0.0)
```

- [ ] **Step 8: Валидация сцены**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: грузится (exit 0), только baseline-категории.

- [ ] **Step 9: Регрессия смоук-теста пенальти**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_penalty_flow.gd"`
Expected: `CHECK PASS: penalty flow (launched + released)` (дефолтный `AIKeeperIntent` не ломает старый флоу).

- [ ] **Step 10: Коммит**

```bash
git add scripts/match/penalty_controller.gd
git commit -m "feat(penalty): controller consumes KeeperIntent + fixed-aim + keeper marker"
```

---

## Task 5: Тест-клавиша K (ИИ бьёт, человек — вратарь)

**Files:**
- Modify: `scripts/match/match_manager.gd` (`_setup_inputs` actions-словарь; `_physics_process` после P-блока)

**Interfaces:**
- Consumes: `AIKickerIntent` (Task 2), `SetPiecePresentation.Role` (Task 3), `HumanKeeperIntent` (Task 1), `penalty_controller.start_single(...)` 5-параметровая (Task 4).

- [ ] **Step 1: Добавить action `keeper_dive_debug` (K)**

В `scripts/match/match_manager.gd`, в `_setup_inputs` словаре `actions`, после строки `&"penalty_debug":   {"keys": [KEY_P],     "buttons": [], "axes": []},` добавить:

```gdscript
		&"keeper_dive_debug": {"keys": [KEY_K], "buttons": [], "axes": []},
```

- [ ] **Step 2: Добавить триггер-блок K в `_physics_process`**

В `_physics_process`, сразу после P-блока:

```gdscript
	if Input.is_action_just_pressed(&"penalty_debug") and _keeper != null and not _celebrating:
		_penalty.start_single(controlled_player, _keeper_brain.goal_line_z)
		return
```
добавить:
```gdscript
	# K: ИИ бьёт пенальти, человек управляет вратарём (выбор зоны нырка стиком). Бьющий — то же тело,
	# что бьёт по P (controlled_player), но с AIKickerIntent; презентация — роль KEEPER (камера как у
	# пенальти + cyan-маркер над вратарём, без ретикла/power_bar бьющего).
	if Input.is_action_just_pressed(&"keeper_dive_debug") and _keeper != null and not _celebrating:
		var kicker_rng := RandomNumberGenerator.new()
		kicker_rng.randomize()
		_penalty.start_single(controlled_player, _keeper_brain.goal_line_z,
			AIKickerIntent.new(kicker_rng),
			SetPiecePresentation.new(SetPiecePresentation.Role.KEEPER),
			HumanKeeperIntent.new({"aim_lat": [&"move_left", &"move_right"], "aim_vert": [&"move_forward", &"move_back"]}))
		return
```

- [ ] **Step 3: Валидация сцены**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: грузится (exit 0), только baseline-категории (K-блок парсится без ошибок).

- [ ] **Step 4: Регрессия всех тестов плана**

Run последовательно (каждый ожидает `CHECK PASS`):
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_keeper_intent.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ai_kicker_intent.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_human_kicker_intent.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_penalty_flow.gd"
```
Expected: четыре `CHECK PASS`.

- [ ] **Step 5: Ручная проверка (фил — headless не драйвит)**

Запустить игру (Godot без `--headless`):
- **P** (регрессия) — пенальти как было: человек целится/заряжает/бьёт, вратарь-ИИ ныряет вслепую.
- **K** — ИИ-бьющий выдерживает паузу (~0.8с «обдумывания»), затем разбегается и бьёт в фиксированную точку; **до удара** человек стиком/стрелками выбирает зону нырка (5 зон: лево-верх/низ, право-верх/низ, нейтраль=центр), и вратарь ныряет в **последнюю выбранную** зону в момент удара. Над вратарём виден cyan-маркер. Камера — фикс-вид из-за спины бьющего (как у P). Ретикл и power_bar скрыты (бьёт ИИ). Прогнать несколько раз, меняя зону, — убедиться, что нырок идёт в выбранную сторону.
- Если нырок визуально не дотягивается до мяча при верном угадывании — это отдельная follow-up задача на тюнинг `_begin_save` (вне скоупа этого плана), зафиксировать наблюдение.

- [ ] **Step 6: Коммит**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(penalty): K debug key — AI kicker vs human keeper (dive-zone control)"
```

---

## Self-Review

**Spec coverage:**
- `KeeperIntent`/`HumanKeeperIntent`/`AIKeeperIntent` → Task 1. `stick_to_zone` → Task 1.
- `AIKickerIntent` стаб (think/aim/charge) + `has_fixed_aim`/`aim_target` + константы → Task 2.
- Ролевой `SetPiecePresentation` (Role enum, owns_camera/hud/keeper_marker) → Task 3.
- Контроллер: `_keeper_intent`, 5-й параметр, срез зоны в `_on_kicker_contact`, фикс-прицел, cyan-маркер → Task 4.
- Клавиша K (action + триггер) → Task 5.
- Тесты `check_keeper_intent`, `check_ai_kicker_intent` → Task 1/2; `check_penalty_flow` не тронут (регрессия в Task 4/5); `check_human_kicker_intent` обновлён под ролевой API (Task 3).
- **Вне скоупа (спек, «Границы»):** тюнинг физики нырка (follow-up, Task 5 Step 5 фиксирует наблюдение), полный планировщик AIIntent, роль WALL (только enum-задел), keeper-вид камеры/HUD, диспетчер судьи. Ни одна не требует задачи в этом плане.

**Placeholder scan:** плейсхолдеров нет — полный код/команды в каждом шаге. Числовые константы закреплены (0.8/0.7/0.7).

**Type consistency:** `dive_zone() -> int` (KeeperIntent база, Human, AI, потребление в Task 4) — одна сигнатура. `stick_to_zone(Vector2, float) -> int` — Task 1 определяет, Human использует. `has_fixed_aim()/aim_target()` — база (Task 2), AIKickerIntent override, потребление Task 4. `SetPiecePresentation.new(int)` + `Role` — Task 3 определяет, Task 4 (`owns_keeper_marker`) и Task 5 (`Role.KEEPER`) используют. `start_single(kicker, goal_line_z, intent=null, presentation=null, keeper_intent=null)` — Task 4 определяет, Task 5 вызывает 4-аргументно (kicker, z, AIKicker, presentation, keeper) — совпадает. `_now_msec()` — AIKickerIntent (Task 2), фейк в тесте. `AIKeeperIntent.new(rng)` — Task 1, дефолт в Task 4.

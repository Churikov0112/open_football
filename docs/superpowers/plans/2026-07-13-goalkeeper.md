# Вратарь — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить базового AI-вратаря в атакуемые человеком ворота: позиционирование на линии, сейв (ловля центра / нырок в углы, низ/верх), ввод мяча выносом — чтобы забить стало осмысленно.

**Architecture:** Дом-стиль «чистая математика + физика/презентация поверх». `KeeperLogic` (чистые статические функции, headless-тест) решает «куда и когда», `keeper_ai.gd` (узел на `CharacterBody3D`, машина состояний) оркестрирует `PlayerMotor`/`PlayerVisual`/сейв-`Area3D`, `match_manager` спавнит вратаря. Движение вратаря — физика (нырок = `move_and_collide`-бросок при заблокированном моторе, как подкат); анимации Mixamo с root motion замораживаются в `merge_mixamo.py`, как `tackle`.

**Tech Stack:** Godot 4.7 / GDScript, Blender 5.1 (сборка `footballer.glb`), headless-скрипты `tests/check_*.gd`.

## Global Constraints

- **Godot exe:** `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`
- **Repo:** `C:\Users\User\Desktop\projects\OpenFootball`
- **Ветка:** `feat/goalkeeper` (уже создана, на ней лежит спек).
- **Чистые функции `KeeperLogic` НИКОГДА не читают `FootballConstants`** — весь тюнинг передаётся параметрами (как `PassSystem`/`NetSim`). Иначе headless-тест не изолирован.
- **Движение игроков — только через `PlayerMotor`** (`set_move_intent`), кроме нырка вратаря (свой `move_and_collide` при `set_control_locked(true)` — единственное исключение, как подкат).
- **InputMap не трогаем** (вратарь — AI, без ввода).
- **Команды вратаря:** группа `team_2` (соперник для человека).
- **Ворота человека атакует:** Away (`+field_length`, Z ≈ +52.5). Вратарь defends именно их. (Home на `-Z` атакует AI-соперник — код: `simple_ai.home_goal = GoalHome`.)
- **Headless-валидация после match-задач** (diff против baseline из CLAUDE.md — 4 категории ошибок, НЕ ждать zero):
  `& "<exe>" --path "<repo>" --headless --quit-after 2 res://scenes/match.tscn`
- **Headless-тест:** `& "<exe>" --path "<repo>" --headless -s "res://tests/<name>.gd"` → печатает `CHECK PASS`/`CHECK FAIL`, exit 0/1.
- **Стиль комментариев/языка** — русский, как в существующих файлах.

---

## Файловая структура

| Файл | Ответственность | Действие |
|---|---|---|
| `scripts/match/keeper_logic.gd` | чистая математика вратаря (позиция, пересечение, зоны, тайминг) | Create |
| `tests/check_keeper_logic.gd` | headless-тест `KeeperLogic` | Create |
| `scripts/ai/keeper_ai.gd` | машина состояний вратаря (оркестрация) | Create |
| `scripts/data/football_constants.gd` | секция `KEEPER` | Modify |
| `scripts/ball/ball_controller.gd` | метод `parry()` (отбой) | Modify |
| `tests/check_ball_state.gd` | тест `parry()` | Modify |
| `scripts/player/player_visual.gd` | keeper-oneshot/action клипы + KEEPER-локомоция | Modify |
| `scripts/player/player_motor.gd` | `set_face_direction()` | Modify |
| `tests/check_player_motor_math.gd` | тест `face_yaw` | Modify |
| `scripts/match/match_manager.gd` | спавн вратаря + сейв-`Area3D` | Modify |
| `tools/merge_mixamo.py` | `IN_PLACE_CLIPS` для keeper-клипов | Modify |
| `tests/check_footballer_glb.gd` | keeper-клипы в ожидаемом списке | Modify |
| `assets/models/mixamo_src/keeper_*.fbx` | исходники анимаций (gitignored) | Create (вручную) |
| `assets/models/footballer.glb` | пересобранная модель с keeper-клипами | Rebuild |

---

## Task 1: KeeperLogic — позиционирование, геометрия удара, решение о сейве

**Files:**
- Create: `scripts/match/keeper_logic.gd`
- Test: `tests/check_keeper_logic.gd`

**Interfaces:**
- Produces:
  - `enum SaveAction { NONE, CATCH, CATCH_TOP, DIVE_LOW_L, DIVE_LOW_R, DIVE_HIGH_L, DIVE_HIGH_R }`
  - `line_position(ball_pos: Vector3, goal_line_z: float, goal_half_width: float, narrow_gain: float, max_off_line: float) -> Vector3`
  - `shot_intercept(ball_pos: Vector3, ball_vel: Vector3, goal_line_z: float) -> Vector3`
  - `is_on_target(intercept: Vector3, goal_half_width: float, goal_height: float) -> bool`
  - `save_decision(intercept: Vector3, keeper_pos: Vector3, reach_radius: float, dive_range: float, high_threshold: float) -> Dictionary` (`{"action": int, "target": Vector3}`)

- [ ] **Step 1: Написать падающий тест**

Create `tests/check_keeper_logic.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var ok := true

	# line_position: X следует за мячом (в пределах створа), Z сходит с линии под близкий мяч.
	# Ворота Away на +52.5; в поле = -Z. Мяч на линии (dz=0) → макс. выход off=max_off_line.
	var lp := KeeperLogic.line_position(Vector3(1.0, 0, 40.0), 52.5, 3.66, 0.08, 2.5)
	if not is_equal_approx(lp.x, 1.0):
		print("CHECK FAIL: line_position x → ", lp.x); ok = false
	# dz = |40-52.5| = 12.5 → off = clamp(2.5 - 0.08*12.5, 0, 2.5) = 1.5 → z = 52.5 - 1.5 = 51.0
	if not is_equal_approx(lp.z, 51.0):
		print("CHECK FAIL: line_position z narrow → ", lp.z); ok = false
	# X клампится к полуширине створа.
	var lp2 := KeeperLogic.line_position(Vector3(10.0, 0, 52.5), 52.5, 3.66, 0.08, 2.5)
	if not is_equal_approx(lp2.x, 3.66):
		print("CHECK FAIL: line_position x clamp → ", lp2.x); ok = false

	# shot_intercept: проекция на плоскость z=goal_line_z.
	# Мяч в (0,0.5,40), скорость (2,1,25) → t=(52.5-40)/25=0.5 → point=(1, 1.0, 52.5)
	var si := KeeperLogic.shot_intercept(Vector3(0, 0.5, 40.0), Vector3(2, 1, 25), 52.5)
	if not si.is_equal_approx(Vector3(1.0, 1.0, 52.5)):
		print("CHECK FAIL: shot_intercept → ", si); ok = false
	# Мяч летит ОТ линии (vz<0) → нет пересечения впереди → возвращает позицию мяча.
	var si2 := KeeperLogic.shot_intercept(Vector3(0, 0.5, 40.0), Vector3(0, 0, -10), 52.5)
	if not si2.is_equal_approx(Vector3(0, 0.5, 40.0)):
		print("CHECK FAIL: shot_intercept away → ", si2); ok = false

	# is_on_target: в створе / мимо по ширине и высоте.
	if not KeeperLogic.is_on_target(Vector3(2.0, 1.5, 52.5), 3.66, 2.44):
		print("CHECK FAIL: on_target inside"); ok = false
	if KeeperLogic.is_on_target(Vector3(5.0, 1.5, 52.5), 3.66, 2.44):
		print("CHECK FAIL: on_target wide"); ok = false
	if KeeperLogic.is_on_target(Vector3(0.0, 3.0, 52.5), 3.66, 2.44):
		print("CHECK FAIL: on_target over bar"); ok = false

	# save_decision: 6 зон + NONE. Вратарь на (0,0,52).
	# близко+низко → CATCH
	var d1 := KeeperLogic.save_decision(Vector3(0.5, 0.5, 52.5), Vector3(0, 0, 52), 1.4, 3.66, 1.3)
	if d1.action != KeeperLogic.SaveAction.CATCH:
		print("CHECK FAIL: decision CATCH → ", d1.action); ok = false
	# близко+высоко → CATCH_TOP
	var d2 := KeeperLogic.save_decision(Vector3(0.5, 2.0, 52.5), Vector3(0, 0, 52), 1.4, 3.66, 1.3)
	if d2.action != KeeperLogic.SaveAction.CATCH_TOP:
		print("CHECK FAIL: decision CATCH_TOP → ", d2.action); ok = false
	# нижний угол влево (dx<0) → DIVE_LOW_L
	var d3 := KeeperLogic.save_decision(Vector3(-3.0, 0.5, 52.5), Vector3(0, 0, 52), 1.4, 3.66, 1.3)
	if d3.action != KeeperLogic.SaveAction.DIVE_LOW_L:
		print("CHECK FAIL: decision DIVE_LOW_L → ", d3.action); ok = false
	# верхний угол вправо (dx>0) → DIVE_HIGH_R
	var d4 := KeeperLogic.save_decision(Vector3(3.0, 2.0, 52.5), Vector3(0, 0, 52), 1.4, 3.66, 1.3)
	if d4.action != KeeperLogic.SaveAction.DIVE_HIGH_R:
		print("CHECK FAIL: decision DIVE_HIGH_R → ", d4.action); ok = false
	# за пределами прыжка → NONE
	var d5 := KeeperLogic.save_decision(Vector3(6.0, 0.5, 52.5), Vector3(0, 0, 52), 1.4, 3.66, 1.3)
	if d5.action != KeeperLogic.SaveAction.NONE:
		print("CHECK FAIL: decision NONE → ", d5.action); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_keeper_logic.gd"`
Expected: FAIL — `KeeperLogic` не существует (parser error / class not found).

- [ ] **Step 3: Реализовать `KeeperLogic`**

Create `scripts/match/keeper_logic.gd`:

```gdscript
class_name KeeperLogic
extends Object
## Чистая математика вратаря. НИКОГДА не читает FootballConstants — тюнинг параметрами.

enum SaveAction { NONE, CATCH, CATCH_TOP, DIVE_LOW_L, DIVE_LOW_R, DIVE_HIGH_L, DIVE_HIGH_R }

## Где вратарю стоять: X следует за мячом (клампится к створу), Z сходит с линии в поле
## тем дальше, чем ближе мяч (сужение угла), но не дальше max_off_line.
static func line_position(ball_pos: Vector3, goal_line_z: float, goal_half_width: float, narrow_gain: float, max_off_line: float) -> Vector3:
	var x := clampf(ball_pos.x, -goal_half_width, goal_half_width)
	var dz := absf(ball_pos.z - goal_line_z)
	var off := clampf(max_off_line - narrow_gain * dz, 0.0, max_off_line)
	var into_field := -1.0 if goal_line_z > 0.0 else 1.0
	return Vector3(x, 0.0, goal_line_z + into_field * off)

## Точка пересечения траектории удара с плоскостью линии ворот (z=goal_line_z).
## Если мяч не движется к линии впереди — возвращает позицию мяча (нет пересечения).
static func shot_intercept(ball_pos: Vector3, ball_vel: Vector3, goal_line_z: float) -> Vector3:
	var vz := ball_vel.z
	if absf(vz) < 0.001:
		return ball_pos
	var t := (goal_line_z - ball_pos.z) / vz
	if t < 0.0:
		return ball_pos
	return ball_pos + ball_vel * t

## Попадает ли точка пересечения в створ (по |x| и по высоте).
static func is_on_target(intercept: Vector3, goal_half_width: float, goal_height: float) -> bool:
	return absf(intercept.x) <= goal_half_width and intercept.y <= goal_height and intercept.y >= -0.1

## По геометрии: поймать на месте (центр) / нырнуть (угол, низ или верх) / недосягаемо.
## dx<0 = мяч слева от вратаря (вратарь лицом в поле -Z → его левая рука = -X).
static func save_decision(intercept: Vector3, keeper_pos: Vector3, reach_radius: float, dive_range: float, high_threshold: float) -> Dictionary:
	var dx := intercept.x - keeper_pos.x
	var horiz := absf(dx)
	var high := intercept.y >= high_threshold
	if horiz <= reach_radius:
		return {"action": SaveAction.CATCH_TOP if high else SaveAction.CATCH, "target": intercept}
	if horiz <= dive_range:
		if high:
			return {"action": SaveAction.DIVE_HIGH_L if dx < 0.0 else SaveAction.DIVE_HIGH_R, "target": intercept}
		return {"action": SaveAction.DIVE_LOW_L if dx < 0.0 else SaveAction.DIVE_LOW_R, "target": intercept}
	return {"action": SaveAction.NONE, "target": intercept}
```

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_keeper_logic.gd"`
Expected: `CHECK PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/keeper_logic.gd tests/check_keeper_logic.gd
git commit -m "feat(keeper): KeeperLogic positioning + shot geometry + save zones"
```

---

## Task 2: KeeperLogic — тайминг нырка и разрешение ловля/отбой

**Files:**
- Modify: `scripts/match/keeper_logic.gd`
- Test: `tests/check_keeper_logic.gd` (дописать)

**Interfaces:**
- Consumes: `SaveAction` (Task 1)
- Produces:
  - `time_to_intercept(ball_pos: Vector3, ball_vel: Vector3, intercept: Vector3) -> float`
  - `should_commit_dive(t_to_intercept: float, keeper_pos: Vector3, target: Vector3, dive_speed: float, lead_margin: float) -> bool`
  - `resolve_save(action: int, ball_speed: float, catch_max_speed: float) -> bool` (true=ловля)

- [ ] **Step 1: Дописать падающий тест**

В `tests/check_keeper_logic.gd`, ПЕРЕД строкой `print("CHECK PASS" ...)`, вставить:

```gdscript
	# time_to_intercept: расстояние/скорость.
	# мяч (0,0,40)→(0,0,52.5) при скорости 25 м/с → t=12.5/25=0.5
	var tti := KeeperLogic.time_to_intercept(Vector3(0, 0, 40), Vector3(0, 0, 25), Vector3(0, 0, 52.5))
	if not is_equal_approx(tti, 0.5):
		print("CHECK FAIL: time_to_intercept → ", tti); ok = false
	if KeeperLogic.time_to_intercept(Vector3(0,0,40), Vector3.ZERO, Vector3(0,0,52.5)) != INF:
		print("CHECK FAIL: time_to_intercept still"); ok = false

	# should_commit_dive: рано (мяч далеко по времени) — не прыгаем; в окне — прыгаем.
	# нырок к цели на 3 м при dive_speed=14 → dive_time≈0.214; lead=0.08 → окно≈0.294
	var far := KeeperLogic.should_commit_dive(0.6, Vector3(0,0,52), Vector3(3,0.5,52.5), 14.0, 0.08)
	if far:
		print("CHECK FAIL: commit too early"); ok = false
	var now := KeeperLogic.should_commit_dive(0.25, Vector3(0,0,52), Vector3(3,0.5,52.5), 14.0, 0.08)
	if not now:
		print("CHECK FAIL: commit in window"); ok = false

	# resolve_save: центр всегда ловля, верх-угол всегда отбой, низ-угол по скорости.
	if not KeeperLogic.resolve_save(KeeperLogic.SaveAction.CATCH, 40.0, 18.0):
		print("CHECK FAIL: resolve CATCH always"); ok = false
	if not KeeperLogic.resolve_save(KeeperLogic.SaveAction.CATCH_TOP, 40.0, 18.0):
		print("CHECK FAIL: resolve CATCH_TOP always"); ok = false
	if KeeperLogic.resolve_save(KeeperLogic.SaveAction.DIVE_HIGH_L, 5.0, 18.0):
		print("CHECK FAIL: resolve HIGH always parry"); ok = false
	if not KeeperLogic.resolve_save(KeeperLogic.SaveAction.DIVE_LOW_R, 10.0, 18.0):
		print("CHECK FAIL: resolve LOW slow catch"); ok = false
	if KeeperLogic.resolve_save(KeeperLogic.SaveAction.DIVE_LOW_R, 25.0, 18.0):
		print("CHECK FAIL: resolve LOW fast parry"); ok = false
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_keeper_logic.gd"`
Expected: FAIL — методов `time_to_intercept`/`should_commit_dive`/`resolve_save` нет.

- [ ] **Step 3: Дописать функции в `keeper_logic.gd`**

В конец `scripts/match/keeper_logic.gd`:

```gdscript
## Сколько мячу лететь до точки пересечения (по его скорости). Стоящий мяч → INF.
static func time_to_intercept(ball_pos: Vector3, ball_vel: Vector3, intercept: Vector3) -> float:
	var speed := ball_vel.length()
	if speed < 0.001:
		return INF
	return ball_pos.distance_to(intercept) / speed

## Пора ли стартовать нырок: мячу до точки лететь не дольше, чем нырку до неё доехать
## (расстояние/скорость) + запас на раскрытие позы. Раньше — ждём/подшагиваем.
static func should_commit_dive(t_to_intercept: float, keeper_pos: Vector3, target: Vector3, dive_speed: float, lead_margin: float) -> bool:
	if dive_speed <= 0.0:
		return true
	var dive_time := keeper_pos.distance_to(target) / dive_speed
	return t_to_intercept <= dive_time + lead_margin

## Ловить или отбивать. Центр — всегда ловля; верхний угол — всегда отбой; нижний угол —
## ловля медленного, отбой быстрого. (Диктуется имеющимися анимациями.)
static func resolve_save(action: int, ball_speed: float, catch_max_speed: float) -> bool:
	match action:
		SaveAction.CATCH, SaveAction.CATCH_TOP:
			return true
		SaveAction.DIVE_HIGH_L, SaveAction.DIVE_HIGH_R:
			return false
		SaveAction.DIVE_LOW_L, SaveAction.DIVE_LOW_R:
			return ball_speed <= catch_max_speed
		_:
			return false
```

- [ ] **Step 4: Запустить — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_keeper_logic.gd"`
Expected: `CHECK PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/keeper_logic.gd tests/check_keeper_logic.gd
git commit -m "feat(keeper): KeeperLogic dive timing + catch/parry resolution"
```

---

## Task 3: Константы — секция KEEPER

**Files:**
- Modify: `scripts/data/football_constants.gd` (в конец файла)

**Interfaces:**
- Produces: константы `FootballConstants.KEEPER_*` (значения ниже — тюнинг-старт, подгонятся приёмкой).

- [ ] **Step 1: Добавить секцию в конец `football_constants.gd`**

```gdscript


# ═══════════════════════════════════════════
#  KEEPER (вратарь — тюнинг-старт)
# ═══════════════════════════════════════════

# Позиционирование на линии.
const KEEPER_LINE_NARROW_GAIN := 0.08  # на сколько метров выхода с линии теряется за 1 м удаления мяча
const KEEPER_MAX_OFF_LINE := 2.5       # макс. выход из ворот в поле, м
# Досягаемость / зоны сейва.
const KEEPER_REACH := 1.4              # радиус ловли на месте (центр), м
const KEEPER_DIVE_RANGE := 3.66        # макс. боковой прыжок (до штанги), м
const KEEPER_HIGH_THRESHOLD := 1.3     # выше этой высоты (м) сейв считается «верхним»
# Нырок.
const KEEPER_DIVE_SPEED := 14.0        # горизонтальная скорость броска тела, м/с
const KEEPER_DIVE_LIFT_GAIN := 3.0     # множитель вертикального импульса на 1 м высоты цели (верхний нырок взлетает)
const KEEPER_DIVE_LEAD := 0.08         # запас тайминга старта нырка, с
const KEEPER_REACT := 0.18             # задержка реакции на удар, с
const KEEPER_SAVE_ERROR := 0.5         # разброс точки нырка для побиваемости, м
# Сейв.
const KEEPER_CATCH_MAX_SPEED := 18.0   # ниже этой скорости мяч в нижнем углу ловится, выше — отбивается, м/с
const KEEPER_PARRY_DAMP := 0.3         # доля скорости мяча после отбоя
# Ввод мяча.
const KEEPER_HOLD_TIME := 1.0          # пауза с мячом в руках до выноса, с
const KEEPER_CLEAR_SPEED := 22.0       # горизонтальная скорость выноса (drop kick), м/с
const KEEPER_CLEAR_LIFT := 6.0         # вертикальная скорость выноса, м/с
```

- [ ] **Step 2: Проверить, что автозагрузка парсится (headless boot)**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без новых parser-ошибок про `football_constants.gd`.

- [ ] **Step 3: Commit**

```bash
git add scripts/data/football_constants.gd
git commit -m "feat(keeper): KEEPER tuning constants"
```

---

## Task 4: Ball — метод parry() (отбой в полёте)

**Files:**
- Modify: `scripts/ball/ball_controller.gd` (рядом с `block_in_flight`, ~строка 145)
- Test: `tests/check_ball_state.gd` (дописать)

**Interfaces:**
- Produces: `Ball.parry(direction: Vector3, damp: float) -> void` — гасит скорость ×damp, перенаправляет мяч наружу (по direction, чуть вверх), роняет в `OPEN`, коллизию с игроками off.

- [ ] **Step 1: Дописать падающий тест в `tests/check_ball_state.gd`**

Открыть `tests/check_ball_state.gd`, найти где создаётся тестовый мяч и проверяются переходы. Добавить новый под-тест (адаптировать под фактическую структуру файла — там мяч создаётся как `RigidBody3D` со скриптом `ball_controller.gd` и вызывается `_ready` вручную либо через сцену). Вставить проверку рядом с проверкой `block_in_flight`:

```gdscript
	# parry: гасит скорость и перенаправляет наружу, роняет в OPEN.
	ball.state = ball.BallState.FLIGHT
	ball.linear_velocity = Vector3(0, 0, 20)   # летит в ворота (+Z)
	ball.parry(Vector3(0, 0, -1), 0.3)          # отбой наружу (-Z)
	if ball.state != ball.BallState.OPEN:
		print("CHECK FAIL: parry state → ", ball.state); ok = false
	if ball.linear_velocity.z >= 0.0:
		print("CHECK FAIL: parry not redirected out → ", ball.linear_velocity); ok = false
	if ball.linear_velocity.length() > 20.0 * 0.3 + 6.1:  # damp*speed + up-component margin
		print("CHECK FAIL: parry not damped → ", ball.linear_velocity.length()); ok = false
```

(Если `check_ball_state.gd` использует иной способ доступа к enum/полям — сохранить его стиль; суть проверок та же.)

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ball_state.gd"`
Expected: FAIL — метода `parry` нет.

- [ ] **Step 3: Добавить метод `parry` в `ball_controller.gd`**

После `block_in_flight()` (после строки ~151):

```gdscript

## Вратарский отбой: гасит скорость ×damp, перенаправляет мяч НАРУЖУ (по direction, чуть
## вверх), роняет в OPEN, коллизию с игроками выключает. В отличие от block_in_flight()
## (просто гасит на месте) — задаёт направление отскока от ворот.
func parry(direction: Vector3, damp: float) -> void:
	var speed := linear_velocity.length() * damp
	_curl = Vector3.ZERO
	state = BallState.OPEN
	_set_player_collision(false)
	var out := direction
	out.y = 0.0
	if out.length() < 0.001:
		out = Vector3(0, 0, 1)
	out = out.normalized()
	out.y = 0.5   # немного вверх, чтобы отбитый мяч читался
	linear_velocity = out.normalized() * speed
```

- [ ] **Step 4: Запустить — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ball_state.gd"`
Expected: `CHECK PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/ball/ball_controller.gd tests/check_ball_state.gd
git commit -m "feat(keeper): Ball.parry() directed deflection"
```

---

## Task 5: Asset pipeline — keeper-клипы в footballer.glb + заморозка root motion

**Files:**
- Create (вручную): `assets/models/mixamo_src/keeper_*.fbx` (из `C:\Users\User\Desktop\Mixamo Goalkeeper Animations`, переименовать в snake_case)
- Modify: `tools/merge_mixamo.py` (`IN_PLACE_CLIPS`)
- Modify: `tests/check_footballer_glb.gd` (ожидаемый список клипов)
- Rebuild: `assets/models/footballer.glb`

**Interfaces:**
- Produces: клипы в glb: `keeper_idle`, `keeper_sidestep`, `keeper_body_block_l`, `keeper_body_block_r`, `keeper_diving_save_l`, `keeper_diving_save_r`, `keeper_catch`, `keeper_catch_top`, `keeper_idle_ball`, `keeper_drop_kick`.

**ПРИМЕЧАНИЕ по именам:** чтобы имена стейтов `AnimationTree` совпали с тем, что ждут Task 6/keeper_ai, файлы переименовать в:
`keeper_idle.fbx`, `keeper_sidestep.fbx`, `keeper_body_block_l.fbx`, `keeper_body_block_r.fbx`, `keeper_diving_save_l.fbx`, `keeper_diving_save_r.fbx`, `keeper_catch.fbx`, `keeper_catch_top.fbx`, `keeper_idle_ball.fbx`, `keeper_drop_kick.fbx`.

- [ ] **Step 1: Скопировать и переименовать FBX**

Скопировать из `C:\Users\User\Desktop\Mixamo Goalkeeper Animations` в `assets\models\mixamo_src\` с именами выше. Маппинг: `Goalkeeper Idle`→`keeper_idle`, `Goalkeeper Sidestep`→`keeper_sidestep`, `Goalkeeper Body Block L/R`→`keeper_body_block_l/r`, `Goalkeeper Diving Save L/R`→`keeper_diving_save_l/r`, `Goalkeeper Catch`→`keeper_catch`, `Goalkeeper Catch Top`→`keeper_catch_top`, `Goalkeeper Idle With Ball`→`keeper_idle_ball`, `Goalkeeper Drop Kick`→`keeper_drop_kick`. (Остальные скачанные клипы — на будущее, НЕ копировать в этой итерации.)

PowerShell:
```powershell
$src = "C:\Users\User\Desktop\Mixamo Goalkeeper Animations"
$dst = "C:\Users\User\Desktop\projects\OpenFootball\assets\models\mixamo_src"
Copy-Item "$src\Goalkeeper Idle.fbx"          "$dst\keeper_idle.fbx"
Copy-Item "$src\Goalkeeper Sidestep.fbx"      "$dst\keeper_sidestep.fbx"
Copy-Item "$src\Goalkeeper Body Block L.fbx"  "$dst\keeper_body_block_l.fbx"
Copy-Item "$src\Goalkeeper Body Block R.fbx"  "$dst\keeper_body_block_r.fbx"
Copy-Item "$src\Goalkeeper Diving Save L.fbx" "$dst\keeper_diving_save_l.fbx"
Copy-Item "$src\Goalkeeper Diving Save R.fbx" "$dst\keeper_diving_save_r.fbx"
Copy-Item "$src\Goalkeeper Catch.fbx"         "$dst\keeper_catch.fbx"
Copy-Item "$src\Goalkeeper Catch Top.fbx"     "$dst\keeper_catch_top.fbx"
Copy-Item "$src\Goalkeeper Idle With Ball.fbx" "$dst\keeper_idle_ball.fbx"
Copy-Item "$src\Goalkeeper Drop Kick.fbx"     "$dst\keeper_drop_kick.fbx"
```

- [ ] **Step 2: Добавить keeper-клипы в `IN_PLACE_CLIPS`**

В `tools/merge_mixamo.py`, словарь `IN_PLACE_CLIPS` (строки 65-69) заменить на:

```python
IN_PLACE_CLIPS = {
    "tackle": (0, 2),
    "roll_left": (0, 1, 2),
    "roll_right": (0, 1, 2),
    # --- Вратарь ---
    # Оси Hips.location (Blender-local): 0=латераль, 1=вертикаль(таз), 2=вперёд.
    # Нижние нырки/боковой шаг — морозим горизонтали (0,2), вертикаль(1) живая (таз садится клипом),
    # как tackle: заморозка вертикали → «висит в воздухе». Верхние нырки — морозим ВСЁ (0,1,2):
    # всю дугу (вбок+вверх) двигает физика divevel.y, поза «в прыжке» — в костях. Начальные оси
    # для catch/catch_top/drop_kick — (0,2); подтвердить сэмпл-скриптом (Step 5), при подскоке
    # catch_top перевести в (0,1,2).
    "keeper_body_block_l": (0, 2),
    "keeper_body_block_r": (0, 2),
    "keeper_diving_save_l": (0, 1, 2),
    "keeper_diving_save_r": (0, 1, 2),
    "keeper_catch": (0, 2),
    "keeper_catch_top": (0, 2),
    "keeper_sidestep": (0, 2),
    "keeper_drop_kick": (0, 2),
}
```

(`keeper_idle`/`keeper_idle_ball` — без записи, у них нет travel.)

- [ ] **Step 3: Пересобрать glb (Blender) и переимпортировать (Godot)**

```powershell
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python "C:\Users\User\Desktop\projects\OpenFootball\tools\merge_mixamo.py" -- "C:\Users\User\Desktop\projects\OpenFootball\assets\models\mixamo_src" "C:\Users\User\Desktop\projects\OpenFootball\assets\models\footballer.glb"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import
```
Expected: Blender печатает `MERGE_ANIMS:` со всеми keeper-клипами, `IN_PLACE: заморожена ...` для каждого keeper-клипа из словаря, `MERGE_OK`.

- [ ] **Step 4: Обновить ожидаемый список клипов в `check_footballer_glb.gd`**

Открыть `tests/check_footballer_glb.gd`, найти массив ожидаемых клипов, добавить keeper-клипы (10 имён из Interfaces). Запустить:
Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_footballer_glb.gd"`
Expected: `CHECK PASS` — все keeper-клипы присутствуют.

- [ ] **Step 5: Эмпирически проверить заморозку root motion (разовый скрипт)**

Create `tests/_tmp_check_keeper_freeze.gd` (временный, удалить после):

```gdscript
extends SceneTree
# Разовая проверка: печатает разброс Position3D корневой кости (Hips) по каждому keeper-клипу.
# Замороженные оси должны иметь range≈0. НЕ доверять догадке об оси — смотреть числа.
func _initialize() -> void:
	var scene: PackedScene = load("res://assets/models/footballer.glb")
	var inst := scene.instantiate()
	var ap: AnimationPlayer = _find_ap(inst)
	var clips := ["keeper_body_block_l", "keeper_diving_save_l", "keeper_catch",
		"keeper_catch_top", "keeper_sidestep", "keeper_drop_kick"]
	for name in clips:
		if not ap.has_animation(name):
			print(name, ": НЕТ КЛИПА"); continue
		var anim: Animation = ap.get_animation(name)
		for ti in range(anim.get_track_count()):
			if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
				continue
			var path := str(anim.track_get_path(ti))
			if not path.ends_with(":Hips"):
				continue
			var mn := Vector3(INF, INF, INF)
			var mx := Vector3(-INF, -INF, -INF)
			for ki in range(anim.track_get_key_count(ti)):
				var v: Vector3 = anim.track_get_key_value(ti, ki)
				mn = mn.min(v); mx = mx.max(v)
			print(name, " Hips range = ", (mx - mn))
	quit(0)

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null: return r
	return null
```

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/_tmp_check_keeper_freeze.gd"`
Expected: у `keeper_diving_save_l` все 3 компоненты range≈0 (заморожены). У `keeper_body_block_l`/`keeper_sidestep`/`keeper_catch`/`keeper_drop_kick` — X (0) и Z (2) ≈0, Y (1) может быть >0 (живая вертикаль). Если у `keeper_catch_top` Y заметно растёт (подскок) — добавить его в `(0,1,2)` в Step 2, пересобрать (Step 3), перепроверить. После проверки — удалить временный скрипт: `Remove-Item tests/_tmp_check_keeper_freeze.gd`.

- [ ] **Step 6: Commit**

```bash
git add tools/merge_mixamo.py tests/check_footballer_glb.gd assets/models/footballer.glb assets/models/footballer.glb.import
git commit -m "feat(keeper): add keeper animation clips to footballer.glb (root-motion frozen)"
```

---

## Task 6: PlayerVisual — регистрация keeper one-shot и drop-kick клипов

**Files:**
- Modify: `scripts/player/player_visual.gd` (константы `ONESHOT_CLIPS`, `ACTION_CLIPS`, `ACTION_TIMING`)
- Test: `tests/check_player_visual_fall.gd` (переиспользуем как проверку регистрации one-shot; дописать keeper-клипы)

**Interfaces:**
- Consumes: клипы из glb (Task 5).
- Produces: `PlayerVisual` регистрирует keeper-нырки/ловли/idle_ball как one-shot стейты (`play_oneshot(clip)` работает), а `keeper_drop_kick` — как action (`trigger("keeper_drop_kick")` + сигнал `action_contact`).

- [ ] **Step 1: Дописать падающий тест**

Открыть `tests/check_player_visual_fall.gd` (он строит `PlayerVisual` с моделью и дёргает `play_oneshot`/`has`). Найти, где проверяются one-shot стейты (`tackle`/`roll_left`/…), и добавить проверку keeper-клипов. Пример вставки (адаптировать под фактические имена переменных `pv`/`visual` в файле):

```gdscript
	# Keeper one-shot клипы зарегистрированы.
	for clip in ["keeper_body_block_l", "keeper_diving_save_r", "keeper_catch", "keeper_catch_top", "keeper_idle_ball"]:
		if pv.play_oneshot(StringName(clip)) <= 0.0:
			print("CHECK FAIL: keeper oneshot не зарегистрирован: ", clip); ok = false
	# Keeper drop kick — action (trigger).
	if not pv.has_action("keeper_drop_kick"):
		print("CHECK FAIL: keeper_drop_kick не зарегистрирован как action"); ok = false
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_fall.gd"`
Expected: FAIL — keeper-клипы ещё не в `ONESHOT_CLIPS`/`ACTION_CLIPS`.

- [ ] **Step 3: Добавить keeper-клипы в константы `player_visual.gd`**

`ONESHOT_CLIPS` (строка 31) — расширить:

```gdscript
const ONESHOT_CLIPS := [&"tackle", &"fallen_idle", &"roll_left", &"roll_right", &"standing_up",
	&"keeper_body_block_l", &"keeper_body_block_r", &"keeper_diving_save_l", &"keeper_diving_save_r",
	&"keeper_catch", &"keeper_catch_top", &"keeper_idle_ball"]
```

`ACTION_CLIPS` (строка 19) — добавить ключ:

```gdscript
const ACTION_CLIPS := {
	"kick": "pass",
	"pass": "pass",
	"penalty": "penalty_kick",
	"throw_in": "throw_in",
	"keeper_drop_kick": "keeper_drop_kick",
}
```

`ACTION_TIMING` (строка 36) — добавить запись (contact ≈ момент касания мяча ногой; подгонится приёмкой):

```gdscript
const ACTION_TIMING := {
	"kick": {"contact": 0.35, "lock": 0.5, "speed": 1.0},
	"pass": {"contact": 0.2, "lock": 0.4, "speed": 1.5},
	"keeper_drop_kick": {"contact": 0.5, "lock": 1.0, "speed": 1.0},
}
```

- [ ] **Step 4: Запустить — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_fall.gd"`
Expected: `CHECK PASS`. (Плюс существующие `ACTION_CLIPS`-дубликаты — известный безвредный шум движка, см. CLAUDE.md.)

- [ ] **Step 5: Commit**

```bash
git add scripts/player/player_visual.gd tests/check_player_visual_fall.gd
git commit -m "feat(keeper): register keeper dive/catch oneshots + drop-kick action in PlayerVisual"
```

---

## Task 7: PlayerVisual — KEEPER-стиль локомоции (sidestep вместо бега)

**Files:**
- Modify: `scripts/player/player_visual.gd`
- Test: `tests/check_player_visual_tree.gd` (дописать: keeper-side стейт существует)

**Interfaces:**
- Produces:
  - `PlayerVisual.LOCO_STYLE_NORMAL := 0`, `PlayerVisual.LOCO_STYLE_KEEPER := 1`
  - `set_locomotion_style(style: int) -> void`
  - в стиле KEEPER стейт движения — `keeper_sidestep` (а не run/sprint), спринт-порог не используется.

- [ ] **Step 1: Дописать падающий тест**

В `tests/check_player_visual_tree.gd` (строит дерево и проверяет наличие стейтов) добавить проверку, что при наличии клипа `keeper_sidestep` создан стейт `loco_keeper_side`. Адаптировать под способ доступа к state machine в файле; минимальная проверка через публичный метод — добавить в `PlayerVisual` дебаг-геттер `has_loco_state(name: StringName) -> bool` (см. Step 3) и проверить:

```gdscript
	if not pv.has_loco_state(PlayerVisual.LOCO_KEEPER_SIDE):
		print("CHECK FAIL: нет стейта keeper_sidestep"); ok = false
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_tree.gd"`
Expected: FAIL — стейта/метода нет.

- [ ] **Step 3: Реализовать KEEPER-локомоцию в `player_visual.gd`**

а) Рядом с константами стейтов (после строки 17) добавить:

```gdscript
const LOCO_KEEPER_SIDE := &"loco_keeper_side"
const LOCO_STYLE_NORMAL := 0
const LOCO_STYLE_KEEPER := 1
```

б) Поле стиля (рядом с `_loco`-полями, после строки 57):

```gdscript
var _loco_style: int = LOCO_STYLE_NORMAL
```

в) В `_build_anim_tree`, после блока создания `LOCO_SPRINT` (после строки 108), добавить keeper-side стейт (только если клип есть):

```gdscript
	if ap.has_animation(&"keeper_sidestep"):
		sm.add_node(LOCO_KEEPER_SIDE, _make_speed_state(&"keeper_sidestep"), Vector2(400, 300))
		sm.add_transition(LOCOMOTION, LOCO_KEEPER_SIDE, _make_transition(false))
		sm.add_transition(LOCO_KEEPER_SIDE, LOCOMOTION, _make_transition(false))
		if not LOOP_CLIPS.has(&"keeper_sidestep"):
			ap.get_animation(&"keeper_sidestep").loop_mode = Animation.LOOP_LINEAR
```

г) Публичный сеттер и дебаг-геттер (рядом с `set_locomotion`, после строки 231):

```gdscript
## Стиль локомоции: NORMAL (idle/run/sprint) или KEEPER (idle/keeper_sidestep, без спринта).
func set_locomotion_style(style: int) -> void:
	_loco_style = style

## Есть ли стейт локомоции с таким именем (для тестов).
func has_loco_state(name: StringName) -> bool:
	return _anim_tree != null and _anim_tree.tree_root != null \
		and (_anim_tree.get(&"parameters/sm/playback") != null) and _sm_has(name)

func _sm_has(name: StringName) -> bool:
	var sm := (_anim_tree.tree_root as AnimationNodeBlendTree).get_node(&"sm") as AnimationNodeStateMachine
	return sm != null and sm.has_node(name)
```

д) В `_process`, блок выбора стейта локомоции (строки 204-211), заменить на учёт стиля:

```gdscript
	if _active_action == "" and not _fall_lock and _playback != null:
		var want := LOCOMOTION
		if _loco_style == LOCO_STYLE_KEEPER:
			if speed >= FootballConstants.LOCO_RUN_ANIM_SPEED and _sm_has(LOCO_KEEPER_SIDE):
				want = LOCO_KEEPER_SIDE
		else:
			if speed >= FootballConstants.LOCO_SPRINT_ANIM_SPEED:
				want = LOCO_SPRINT
			elif speed >= FootballConstants.LOCO_RUN_ANIM_SPEED:
				want = LOCO_RUN
		if _playback.get_current_node() != want:
			_playback.travel(want)
```

е) Ниже, где выставляется `parameters/sm/%s/speed/scale` для run/sprint (строки 213-216), добавить keeper-side (после существующих двух):

```gdscript
	if _sm_has(LOCO_KEEPER_SIDE):
		_anim_tree.set("parameters/sm/%s/speed/scale" % LOCO_KEEPER_SIDE,
			PlayerVisual.run_timescale(speed, FootballConstants.LOCO_TOP_SPEED, FootballConstants.LOCO_RUN_SCALE_FUDGE))
```

- [ ] **Step 4: Запустить — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_tree.gd"`
Expected: `CHECK PASS`.

- [ ] **Step 5: Прогнать смежные визуальные тесты (не сломали локомоцию)**

Run каждый: `check_player_visual_locomotion.gd`, `check_player_visual_actions.gd`, `check_player_visual_fall.gd`
Expected: все `CHECK PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/player/player_visual.gd tests/check_player_visual_tree.gd
git commit -m "feat(keeper): PlayerVisual KEEPER locomotion style (sidestep, no sprint)"
```

---

## Task 8: PlayerMotor — режим «смотреть на цель»

**Files:**
- Modify: `scripts/player/player_motor.gd`
- Test: `tests/check_player_motor_math.gd` (дописать)

**Interfaces:**
- Produces:
  - `PlayerMotor.face_yaw(from: Vector3, face_dir: Vector3) -> float` (static, чистая — целевой yaw из направления взгляда)
  - `set_face_direction(dir: Vector3) -> void` — если задано (не ноль), тело доворачивается к этому направлению (мячу) вместо вектора скорости, без гейта по мин. скорости. `Vector3.ZERO` → снова по скорости.

- [ ] **Step 1: Дописать падающий тест в `check_player_motor_math.gd`**

Перед `print("CHECK PASS" ...)`:

```gdscript
	# face_yaw: смотрит на -Z → yaw 0; на +X → yaw -PI/2 (та же формула, что доворот по скорости).
	if not is_equal_approx(PlayerMotor.face_yaw(Vector3.ZERO, Vector3(0, 0, -1)), 0.0):
		print("CHECK FAIL: face_yaw -Z → ", PlayerMotor.face_yaw(Vector3.ZERO, Vector3(0, 0, -1))); ok = false
	if not is_equal_approx(PlayerMotor.face_yaw(Vector3.ZERO, Vector3(1, 0, 0)), -PI / 2.0):
		print("CHECK FAIL: face_yaw +X → ", PlayerMotor.face_yaw(Vector3.ZERO, Vector3(1, 0, 0))); ok = false
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_motor_math.gd"`
Expected: FAIL — `face_yaw` не определён.

- [ ] **Step 3: Реализовать в `player_motor.gd`**

а) Static-функция (рядом с `smooth_yaw`, после строки 20):

```gdscript
## Целевой yaw, чтобы смотреть в направлении face_dir (плоский). Та же конвенция, что доворот
## по скорости: -Z → 0, +X → -PI/2. Пустой dir → 0.
static func face_yaw(_from: Vector3, face_dir: Vector3) -> float:
	var f := Vector3(face_dir.x, 0.0, face_dir.z)
	if f.length() < 0.001:
		return 0.0
	return atan2(-f.x, -f.z)
```

б) Поле (после строки 42):

```gdscript
var _face_dir: Vector3 = Vector3.ZERO
```

в) Сеттер (после `set_control_locked`, строка 64):

```gdscript
## Смотреть на цель (мяч): если dir не ноль — тело доворачивается к нему вместо вектора
## скорости, без гейта по мин. скорости (вратарь всегда лицом к мячу). ZERO → снова по скорости.
func set_face_direction(dir: Vector3) -> void:
	_face_dir = Vector3(dir.x, 0.0, dir.z)
```

г) В `_physics_process`, блок доворота (строки 94-96), заменить на:

```gdscript
	# Доворот тела. Если задано направление взгляда (вратарь) — к нему, всегда. Иначе — к
	# направлению движения (гейт по мин. скорости, чтобы не крутиться на месте).
	if _face_dir.length() > 0.001:
		var fy := PlayerMotor.face_yaw(_body.global_position, _face_dir)
		_body.rotation.y = PlayerMotor.smooth_yaw(_body.rotation.y, fy, FootballConstants.LOCO_TURN_ROT, delta)
	elif speed > FootballConstants.LOCO_TURN_MIN_SPEED:
		var target_yaw := atan2(-new_vel.x, -new_vel.z)
		_body.rotation.y = PlayerMotor.smooth_yaw(_body.rotation.y, target_yaw, FootballConstants.LOCO_TURN_ROT, delta)
```

- [ ] **Step 4: Запустить — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_motor_math.gd"`
Expected: `CHECK PASS`.

- [ ] **Step 5: Прогнать `check_player_motor_locked_gravity.gd` (не сломали вертикаль/локи)**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_motor_locked_gravity.gd"`
Expected: `CHECK PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/player/player_motor.gd tests/check_player_motor_math.gd
git commit -m "feat(keeper): PlayerMotor face-direction mode (face the ball)"
```

---

## Task 9: match_manager — спавн стоящего вратаря + сейв-Area3D

**Files:**
- Modify: `scripts/match/match_manager.gd` (новая функция `_setup_keeper()` + вызов; сохранить в поле `_keeper`)

**Interfaces:**
- Consumes: `PlayerVisual`, `PlayerMotor`, `field_length`, `ball`.
- Produces: узел `CharacterBody3D` "Keeper" в группе `team_2`, с `PlayerVisual`(KEEPER-стиль)/`PlayerMotor`/`CollisionShape3D`/дочерней сейв-`Area3D` ("SaveArea"), стоящий в воротах Away (`+field_length`). Поле `_keeper: CharacterBody3D`. **Без AI-скрипта** — просто стоит (idle).

- [ ] **Step 1: Добавить поле и функцию спавна**

Рядом с полем `_tackle_area` (строка 34) добавить:

```gdscript
var _keeper: CharacterBody3D
```

Добавить функцию (рядом с `_setup_away_player`, ~строка 541):

```gdscript
## Вратарь соперника в атакуемых человеком воротах (Away, +field_length). Пока просто стоит
## (idle) — AI-скрипт навешивается в Task 10.
func _setup_keeper() -> void:
	var k := CharacterBody3D.new()
	k.name = "Keeper"
	var goal_line_z := field_length   # ворота Away на +field_length
	k.global_position = Vector3(0, 0.5, goal_line_z - 0.5)  # чуть в поле от линии
	var visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	k.add_child(visual)
	k.add_child(PlayerMotor.new())
	visual.apply_appearance({"kit_color": Color(0.15, 0.7, 0.15)})  # вратарь — зелёный (отличать от полевых team_2)
	visual.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.5
	shape.radius = 0.3
	col.shape = shape
	col.position = Vector3(0, 0.25, 0)
	k.add_child(col)
	# Сейв-зона: реагирует на мяч (слой 1); keeper_ai решает поймать/отбить.
	var save_area := Area3D.new()
	save_area.name = "SaveArea"
	var sacol := CollisionShape3D.new()
	var sashape := SphereShape3D.new()
	sashape.radius = FootballConstants.KEEPER_REACH
	sacol.shape = sashape
	save_area.add_child(sacol)
	save_area.collision_mask = 1   # только мяч (слой 1)
	k.add_child(save_area)
	add_child(k)
	k.add_to_group("team_2")
	k.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	k.collision_mask = FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
	_keeper = k
```

- [ ] **Step 2: Вызвать `_setup_keeper()`**

Найти, где вызываются `_setup_away_player()` / `_setup_teammate()` в `_ready()` (рядом со строкой 122 и ниже), и добавить после спавна соперника:

```gdscript
	_setup_keeper()
```

- [ ] **Step 3: Проверить match-сцену (headless, diff против baseline)**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: те же 4 категории ошибок из baseline (CLAUDE.md), без НОВЫХ. Вратарь инстанцируется без ошибок.

- [ ] **Step 4: Ручная проверка в игре**

Запустить игру (exe без `--headless`), доиграть до матча. Ожидаемо: зелёный вратарь стоит в дальних (Away, +Z) воротах, лицом в поле, в стойке idle. Не двигается, не падает сквозь газон.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(keeper): spawn standing keeper + save area in attacked goal"
```

---

## Task 10: keeper_ai — состояние POSITION (слежение по линии, лицом к мячу)

**Files:**
- Create: `scripts/ai/keeper_ai.gd`
- Modify: `scripts/match/match_manager.gd` (`_setup_keeper`: навесить скрипт, задать `ball`/`goal_line_z`/`save_area`)

**Interfaces:**
- Consumes: `KeeperLogic.line_position`, `PlayerMotor` (`set_move_intent`/`set_face_direction`/`find_on`), `PlayerVisual.set_locomotion_style`.
- Produces: `keeper_ai.gd` (`extends CharacterBody3D`) с полями `ball: RigidBody3D`, `goal_line_z: float`, `save_area: Area3D`, `enum State`, и состоянием POSITION (следит за мячом по линии, лицом к мячу). Методы для Task 11/12: `_motor()`, `_visual()`, `_base_scale()`, `_to_position()`.

- [ ] **Step 1: Создать `scripts/ai/keeper_ai.gd`**

```gdscript
extends CharacterBody3D
## AI-вратарь: позиционирование на линии + сейв. Движение — через PlayerMotor; нырок (Task 11) —
## свой move_and_collide при заблокированном моторе (как подкат). Математика — в KeeperLogic.

@export var ball: RigidBody3D
var goal_line_z: float = 0.0
var save_area: Area3D

enum State { POSITION, DIVE, RECOVER, HOLD, DISTRIBUTE }
var _state: int = State.POSITION
var _wired: bool = false

func _motor() -> PlayerMotor:
	return PlayerMotor.find_on(self)

func _visual() -> PlayerVisual:
	for c in get_children():
		if c is PlayerVisual:
			return c
	return null

## Скорость перемещения по линии относительно общей максимальной.
func _base_scale() -> float:
	return 1.0

func _to_position() -> void:
	_state = State.POSITION

## Одноразовая проводка: стиль локомоции вратаря (на случай, если спавнер не выставил).
func _ensure_wired() -> void:
	if _wired:
		return
	_wired = true
	var v := _visual()
	if v != null:
		v.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)

func _physics_process(delta: float) -> void:
	if not ball or not is_instance_valid(ball):
		return
	_ensure_wired()
	match _state:
		State.POSITION:
			_position(delta)

## Держим линию: X за мячом, лицом к мячу, лёгкий выход под угол.
func _position(_delta: float) -> void:
	var m := _motor()
	if m == null:
		return
	m.set_face_direction(ball.global_position - global_position)
	var target := KeeperLogic.line_position(
		ball.global_position, goal_line_z, FootballConstants.GOAL_WIDTH * 0.5,
		FootballConstants.KEEPER_LINE_NARROW_GAIN, FootballConstants.KEEPER_MAX_OFF_LINE)
	var to := target - global_position
	to.y = 0.0
	if to.length() > 0.15:
		m.set_move_intent(to.normalized(), _base_scale())
	else:
		m.set_move_intent(Vector3.ZERO)
```

- [ ] **Step 2: Навесить скрипт в `_setup_keeper` (match_manager)**

В `_setup_keeper()` (Task 9), ПЕРЕД `_keeper = k`, вставить:

```gdscript
	k.set_script(preload("res://scripts/ai/keeper_ai.gd"))
	k.set_physics_process(true)
	k.ball = ball
	k.goal_line_z = goal_line_z
	k.save_area = save_area
```

- [ ] **Step 3: Проверить match-сцену (headless)**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: без новых ошибок против baseline; `keeper_ai.gd` парсится (он грузится через match.tscn — см. CLAUDE.md про `--quit-after`).

- [ ] **Step 4: Ручная проверка**

Запустить игру. Ожидаемо: вратарь сдвигается вдоль линии ворот вслед за мячом по X, всегда повёрнут лицом к мячу, при движении играет `keeper_sidestep` (приставные шаги), стоя — idle. При приближении мяча к воротам чуть выходит вперёд.

- [ ] **Step 5: Commit**

```bash
git add scripts/ai/keeper_ai.gd scripts/match/match_manager.gd
git commit -m "feat(keeper): keeper_ai POSITION state (line tracking, face ball)"
```

---

## Task 11: keeper_ai — сейв (детект удара, тайминг, нырок, ловля/отбой) + RECOVER

**Files:**
- Modify: `scripts/ai/keeper_ai.gd`

**Interfaces:**
- Consumes: `KeeperLogic` (`shot_intercept`/`is_on_target`/`save_decision`/`time_to_intercept`/`should_commit_dive`/`resolve_save`), `Ball` (`is_flight`/`linear_velocity`/`set_dribbler`/`parry`), `PlayerMotor.set_control_locked`, `PlayerVisual.play_oneshot`.
- Produces: полный цикл сейва. На успешную ловлю → базовый вынос мяча (заглушка, полноценный drop kick — Task 12). Методы: `_begin_save`, `_dive`, `_recover`, `_to_recover`, `_on_save_area_body`, `_dive_clip`, `_catch_clip`.

- [ ] **Step 1: Добавить поля состояния сейва**

В `keeper_ai.gd`, к полям (после `var _wired`):

```gdscript
var _react_left: float = 0.0
var _reacting: bool = false
var _current_action: int = KeeperLogic.SaveAction.NONE
var _ball_speed_at_save: float = 0.0
var _dive_vel: Vector3 = Vector3.ZERO
var _dive_time_left: float = 0.0
var _state_timer: float = 0.0
```

- [ ] **Step 2: Подключить сейв-зону в `_ensure_wired`**

В `_ensure_wired()`, после блока `if v != null:`, добавить:

```gdscript
	if save_area != null and not save_area.body_entered.is_connected(_on_save_area_body):
		save_area.body_entered.connect(_on_save_area_body)
```

- [ ] **Step 3: Расширить `_physics_process` и `_position` детектом удара**

В `match` добавить ветки:

```gdscript
		State.DIVE:
			_dive(delta)
		State.RECOVER:
			_recover(delta)
```

В конец `_position(...)` добавить детект удара:

```gdscript
	if ball.is_flight():
		var intercept := KeeperLogic.shot_intercept(ball.global_position, ball.linear_velocity, goal_line_z)
		if KeeperLogic.is_on_target(intercept, FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.GOAL_HEIGHT):
			if not _reacting:
				_reacting = true
				_react_left = FootballConstants.KEEPER_REACT
			_react_left -= _delta
			if _react_left <= 0.0:
				var dec := KeeperLogic.save_decision(intercept, global_position,
					FootballConstants.KEEPER_REACH, FootballConstants.KEEPER_DIVE_RANGE,
					FootballConstants.KEEPER_HIGH_THRESHOLD)
				var act: int = dec.action
				if act == KeeperLogic.SaveAction.CATCH or act == KeeperLogic.SaveAction.CATCH_TOP:
					_begin_save(dec, ball.linear_velocity.length())
				elif act != KeeperLogic.SaveAction.NONE:
					var ttoi := KeeperLogic.time_to_intercept(ball.global_position, ball.linear_velocity, intercept)
					if KeeperLogic.should_commit_dive(ttoi, global_position, dec.target,
							FootballConstants.KEEPER_DIVE_SPEED, FootballConstants.KEEPER_DIVE_LEAD):
						_begin_save(dec, ball.linear_velocity.length())
					else:
						# ещё рано — подшагиваем к предсказанному X по линии
						m.set_move_intent(Vector3((intercept.x - global_position.x), 0, 0).normalized(), _base_scale())
		else:
			_reacting = false
	else:
		_reacting = false
```

(Заменить сигнатуру `_position(_delta: float)` на `_position(_delta: float)` уже такова — использовать `_delta` в вызовах выше.)

- [ ] **Step 4: Добавить методы сейва**

В конец `keeper_ai.gd`:

```gdscript
## Старт сейва: центр (CATCH/CATCH_TOP) — на месте (dive_vel≈0); угол — бросок к цели.
func _begin_save(dec: Dictionary, ball_speed: float) -> void:
	_reacting = false
	_current_action = dec.action
	_ball_speed_at_save = ball_speed
	_state = State.DIVE
	var m := _motor()
	if m != null:
		m.set_control_locked(true)   # телом владеет наш move_and_collide (как подкат)
	var vis := _visual()
	var clip := _catch_clip(dec.action) if _is_catch_action(dec.action) else _dive_clip(dec.action)
	var clip_len := 0.0
	if vis != null:
		clip_len = vis.play_oneshot(clip)
	_dive_time_left = maxf(clip_len, 0.4)
	if _is_catch_action(dec.action):
		_dive_vel = Vector3.ZERO   # ловля на месте
	else:
		var target: Vector3 = dec.target
		target.x += randf_range(-1.0, 1.0) * FootballConstants.KEEPER_SAVE_ERROR
		var to := target - global_position
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() < 0.001:
			flat = Vector3(1, 0, 0)
		_dive_vel = flat.normalized() * FootballConstants.KEEPER_DIVE_SPEED
		_dive_vel.y = maxf(0.0, to.y) * FootballConstants.KEEPER_DIVE_LIFT_GAIN

func _dive(delta: float) -> void:
	_dive_vel.y -= FootballConstants.GRAVITY * delta
	move_and_collide(_dive_vel * delta)
	_dive_vel.x *= 0.9
	_dive_vel.z *= 0.9
	_dive_time_left -= delta
	if _dive_time_left <= 0.0:
		_to_recover()

## Контакт сейв-зоны с мячом в полёте: ловим (центр / медленный низ) или отбиваем.
func _on_save_area_body(body: Node) -> void:
	if body != ball or not ball.is_flight():
		return
	if _state != State.DIVE:
		return
	var is_catch := KeeperLogic.resolve_save(_current_action, ball.linear_velocity.length(),
		FootballConstants.KEEPER_CATCH_MAX_SPEED)
	if is_catch:
		ball.set_dribbler(self, true)
		_to_hold()
	else:
		var out := ball.global_position - Vector3(0, 0, goal_line_z)
		out.y = 0.0
		ball.parry(out, FootballConstants.KEEPER_PARRY_DAMP)
		# нырок доиграет и уйдёт в RECOVER

func _to_recover() -> void:
	_state = State.RECOVER
	var vis := _visual()
	var len := 0.0
	if vis != null:
		len = vis.play_oneshot(&"standing_up")
	_state_timer = maxf(len, 0.5)

func _recover(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		var m := _motor()
		if m != null:
			m.set_control_locked(false)
		var vis := _visual()
		if vis != null:
			vis.recover()
		_state = State.POSITION

## HOLD (заглушка Task 11): подержать мяч, затем базовый вынос. Полный drop kick — Task 12.
func _to_hold() -> void:
	_state = State.HOLD
	_state_timer = FootballConstants.KEEPER_HOLD_TIME
	var m := _motor()
	if m != null:
		m.set_control_locked(false)

func _hold(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		# базовый вынос в сторону центра поля (drop-kick анимация — Task 12)
		var out_z := signf(-goal_line_z)
		var vel := Vector3(0, 0, out_z) * FootballConstants.KEEPER_CLEAR_SPEED + Vector3.UP * FootballConstants.KEEPER_CLEAR_LIFT
		if ball.dribbler == self:
			ball.launch(vel)
		_state = State.POSITION

func _is_catch_action(a: int) -> bool:
	return a == KeeperLogic.SaveAction.CATCH or a == KeeperLogic.SaveAction.CATCH_TOP

func _dive_clip(a: int) -> StringName:
	match a:
		KeeperLogic.SaveAction.DIVE_LOW_L: return &"keeper_body_block_l"
		KeeperLogic.SaveAction.DIVE_LOW_R: return &"keeper_body_block_r"
		KeeperLogic.SaveAction.DIVE_HIGH_L: return &"keeper_diving_save_l"
		KeeperLogic.SaveAction.DIVE_HIGH_R: return &"keeper_diving_save_r"
		_: return &"keeper_body_block_r"

func _catch_clip(a: int) -> StringName:
	return &"keeper_catch_top" if a == KeeperLogic.SaveAction.CATCH_TOP else &"keeper_catch"
```

- [ ] **Step 5: Добавить ветку HOLD в `_physics_process`**

В `match` добавить:

```gdscript
		State.HOLD:
			_hold(delta)
```

- [ ] **Step 6: Проверить match-сцену (headless)**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: без новых ошибок против baseline.

- [ ] **Step 7: Ручная проверка (ключевая — сейв ловится глазами)**

Запустить игру. Пробить по воротам: (а) низом по центру → вратарь ловит на месте (`keeper_catch`); (б) низом в угол медленно → нырок `body_block`, ловит; сильно → отбивает; (в) верхом в угол → `diving_save`, всегда отбой; тело реально взлетает по дуге, НЕ висит (проверка заморозки верхнего нырка); (г) точный сильный удар в дальнюю девятку за `KEEPER_DIVE_RANGE` → гол. Нырок стартует с таймингом (не дёргается на старте полёта), после нырка встаёт (`standing_up`) и возвращается на линию.

- [ ] **Step 8: Commit**

```bash
git add scripts/ai/keeper_ai.gd
git commit -m "feat(keeper): keeper_ai save loop (detect, timed dive, catch/parry, recover)"
```

---

## Task 12: keeper_ai — ввод мяча drop kick (анимация + тайминг касания)

**Files:**
- Modify: `scripts/ai/keeper_ai.gd`

**Interfaces:**
- Consumes: `PlayerVisual.trigger("keeper_drop_kick")` + сигнал `action_contact`, `PlayerVisual.play_oneshot(&"keeper_idle_ball")`, `Ball.launch`.
- Produces: DISTRIBUTE-состояние — после HOLD с позой `keeper_idle_ball` вратарь играет `keeper_drop_kick`, а на сигнале `action_contact` выносит мяч в сторону центра поля.

- [ ] **Step 1: Поля и подключение сигнала контакта**

Добавить поле:

```gdscript
var _distribute_fired: bool = false
```

В `_ensure_wired()`, после подключения `save_area`, добавить подключение к своему визуалу:

```gdscript
	if v != null and not v.action_contact.is_connected(_on_visual_contact):
		v.action_contact.connect(_on_visual_contact)
```

- [ ] **Step 2: HOLD → поза с мячом + переход в DISTRIBUTE**

Заменить `_to_hold`/`_hold` (из Task 11) на:

```gdscript
func _to_hold() -> void:
	_state = State.HOLD
	_state_timer = FootballConstants.KEEPER_HOLD_TIME
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
	var vis := _visual()
	if vis != null:
		vis.play_oneshot(&"keeper_idle_ball")   # держит мяч в руках

func _hold(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_to_distribute()

func _to_distribute() -> void:
	_state = State.DISTRIBUTE
	_distribute_fired = false
	var vis := _visual()
	if vis != null:
		vis.recover()                 # выйти из idle_ball one-shot в локомоцию-хаб
		vis.trigger("keeper_drop_kick")

func _distribute(_delta: float) -> void:
	# Ждём сигнала action_contact (см. _on_visual_contact). Страховка: если мяч уже не наш и
	# уже выбит — возврат на линию (на случай пропуска сигнала).
	if _distribute_fired and (ball.dribbler != self):
		_state = State.POSITION

## Момент касания мяча ногой в drop kick → вынос в сторону центра поля.
func _on_visual_contact(action: String) -> void:
	if action != "keeper_drop_kick" or _state != State.DISTRIBUTE or _distribute_fired:
		return
	_distribute_fired = true
	var out_z := signf(-goal_line_z)   # от ворот к центру поля
	var vel := Vector3(0, 0, out_z) * FootballConstants.KEEPER_CLEAR_SPEED + Vector3.UP * FootballConstants.KEEPER_CLEAR_LIFT
	if ball.dribbler == self:
		ball.launch(vel)
	_state = State.POSITION
```

- [ ] **Step 3: Ветка DISTRIBUTE в `_physics_process`**

В `match` добавить:

```gdscript
		State.DISTRIBUTE:
			_distribute(delta)
```

- [ ] **Step 4: Проверить match-сцену (headless)**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: без новых ошибок против baseline.

- [ ] **Step 5: Ручная проверка**

Запустить игру. Поймать мяч вратарём (пас/слабый удар по центру). Ожидаемо: вратарь короткую паузу держит мяч (`keeper_idle_ball`), затем играет `keeper_drop_kick`, и в момент касания мяч вылетает выносом в сторону центра поля (к -Z), после чего вратарь возвращается на линию.

- [ ] **Step 6: Финальный прогон всех keeper-тестов**

Run по очереди: `check_keeper_logic.gd`, `check_ball_state.gd`, `check_footballer_glb.gd`, `check_player_visual_tree.gd`, `check_player_visual_fall.gd`, `check_player_motor_math.gd`
Expected: все `CHECK PASS`.

- [ ] **Step 7: Commit**

```bash
git add scripts/ai/keeper_ai.gd
git commit -m "feat(keeper): keeper_ai drop-kick distribution (idle_ball hold + timed clear)"
```

---

## Self-Review (заполняется автором плана)

**Spec coverage:**
- Позиционирование (line_position, sidestep, лицом к мячу) → Task 1, 7, 8, 10 ✓
- Геометрия удара / в створе → Task 1 ✓
- Решение о сейве (6 зон) → Task 1 ✓
- Тайминг нырка (should_commit_dive) → Task 2, 11 ✓
- Ловля/отбой по зонам (resolve_save) → Task 2, 4 (parry), 11 ✓
- Нырок физикой + заморозка root motion (низ (0,2) / верх (0,1,2)) + эмпирическая верификация → Task 5 ✓
- 4 нырка + 2 ловли + sidestep + idle_ball + drop_kick + getup=standing_up → Task 5, 6, 7 ✓
- Сейв-Area3D flight-gated → Task 9, 11 ✓
- Ввод мяча drop kick к центру → Task 12 ✓
- Один AI-вратарь в воротах Away, team_2 → Task 9 ✓
- Константы KEEPER → Task 3 ✓
- Тест check_keeper_logic.gd → Task 1, 2 ✓

**Осознанно вне плана (спек, раздел «НЕ делаем»):** выходы на прострелы, ввод рукой/катом, игра ногами, пенальти/штрафные, Miss Top, свой вратарь, управление человеком, зеркалирование sidestep, отдельный «mid» нырок.

**Placeholder scan:** заглушка HOLD в Task 11 явно помечена и заменяется в Task 12 (осознанный инкремент, не placeholder). Остальное — конкретный код.

**Type consistency:** `SaveAction` (int), `save_decision`→`{"action","target"}`, `_dive_clip`/`_catch_clip`→`StringName`, `set_locomotion_style(int)`, `set_face_direction(Vector3)` — согласованы между задачами.

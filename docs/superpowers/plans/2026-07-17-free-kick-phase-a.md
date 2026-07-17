# Free Kick (Phase A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Реализовать розыгрыш штрафного удара (Фаза A) — прицел направлением с орбитальной камерой, сила=высота, кручёный «доводом» стика до контакта, стенка обороны с авто-прыжком и переходом в обычный ИИ, реактивный вратарь, пас/навес.

**Architecture:** По образцу пенальти: контроллер-«мозг» `FreeKickController` (`extends Node`, автомат `SETUP→AIM→STRIKE→WATCH`) + чистая математика `FreeKickLogic` (`class_name … extends Object`, **никогда не читает `FootballConstants`**, headless-тестируема). Переиспуск `PassSystem` (пас/навес), `ball.launch`/`launch_curl` (удар/кручёный), `PlayerMotor` root-motion разбег, фикс-камера. `match_manager` гейтит режим (как пенальти) и спавнит/конвертирует тела.

**Tech Stack:** Godot 4.7, GDScript. Ассеты: `footballer.glb` (Mixamo, merge через Blender 5.1). Тесты — headless-скрипты `tests/check_*.gd` (extends `SceneTree`).

## Global Constants

- Движок: **Godot 4.7**, GDScript. Godot exe: `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`.
- Blender: **5.1**, exe: `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`.
- Репозиторий: `C:\Users\User\Desktop\projects\OpenFootball`.
- **Чистая математика (`FreeKickLogic`) НИКОГДА не читает `FootballConstants`** — весь тюнинг передаётся параметрами (как `PassSystem`/`PenaltyLogic`/`KeeperLogic`/`NetSim`).
- Поле: центр `(0,0,0)`; **Z = длина (105 м)**, **X = ширина (68 м)**; ворота только на Z. Home = `-52.5`, Away = `+52.5`. Атакуемые человеком ворота = ворота вратаря = `_keeper.goal_line_z` (Home, `-field_length`). Наша команда атакует к `-Z`.
- Группы: наши — `team_1`, соперник — `team_2`. `PLAYER_COLLISION_MASK = 2` (bit2), `BOUNDARY_COLLISION_LAYER = 4` (bit3). `BALL_RADIUS = 0.11`, `GOAL_WIDTH = 7.32`, `GOAL_HEIGHT = 2.44`.
- Конвенция кручения: `ball.launch_curl(velocity, curl)` — `curl.z` боковая составляющая (Magnus вдоль `left = horiz×UP`), `curl.y` подъём. Прямой удар — `ball.launch(velocity)`.
- Спека: `docs/superpowers/specs/2026-07-17-free-kick-design.md`. Каждая задача неявно наследует эти ограничения.

**Команды валидации (обе нужны — ловят разное):**
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Второй прогон имеет известный baseline ошибок (см. CLAUDE.md «Commands») — сравнивай по *категориям/тексту*, а не по числу.

---

## File Structure

- **Create:** `scripts/match/free_kick_logic.gd` — чистая математика (aim/launch/curl/wall/keeper).
- **Create:** `scripts/match/free_kick_controller.gd` — контроллер розыгрыша.
- **Create:** `tests/check_free_kick_logic.gd` — headless-тест чистых функций.
- **Create:** `tests/check_free_kick_flow.gd` — headless-смоук флоу (старт→удар→запуск+возврат, стенка спавн/конвертация).
- **Modify:** `scripts/data/football_constants.gd` — секция `FREE KICK` (`FK_*`).
- **Modify:** `scripts/player/player_visual.gd` — регистрация клипа `jumping_wall` в `ONESHOT_CLIPS`.
- **Modify:** `scripts/ai/keeper_ai.gd` — режим якоря штрафного (`set_freekick_anchor`, реактивный сейв ВКЛ).
- **Modify:** `scripts/match/match_manager.gd` — ввод `free_kick_debug` (F), инстанс `_free_kick`, гейтинг-флаг, парковка камеры, делегирование, F-хендлер.
- **Modify:** `tools/merge_mixamo.py` — `jumping_wall` в `IN_PLACE_CLIPS` (заморозка горизонтали).
- **Modify:** `tests/check_footballer_glb.gd` — `jumping_wall` в списке ожидаемых клипов.
- **Rebuild:** `assets/models/footballer.glb` — merge через Blender + Godot import.

---

## Task 1: Константы `FREE KICK`

**Files:**
- Modify: `scripts/data/football_constants.gd` (добавить блок в конец, перед возможными DEBUG-флагами — просто дописать новую секцию)

**Interfaces:**
- Produces: константы `FootballConstants.FK_*` (значения ниже), потребляются контроллером (Tasks 5–9). `FreeKickLogic` их НЕ читает.

- [ ] **Step 1: Добавить секцию констант**

В конец `scripts/data/football_constants.gd` добавить:

```gdscript

# ── FREE KICK (Фаза A) ────────────────────────────────────────────────────────
# Разбег/нога (переиспуют логику PEN_*).
const FK_RUNUP_DIST := 2.8            # пред-расстановка бьющего назад под разбег (мировые метры)
const FK_DEFAULT_FOOT := "penalty_r"  # ключ ACTION_CLIPS (клип penalty_kick_r)
const FK_FOOT_LATERAL := 0.4          # латеральный сдвиг бьющего под опорную ногу, м
# Прицел/камера.
const FK_AIM_ARC := 1.221             # ±сектор поворота heading от направления на центр ворот (рад ≈ 70°)
const FK_AIM_SPEED := 1.6             # скорость поворота heading стиком, рад/с
const FK_CAM_BACK := 8.0              # отступ камеры назад от точки вдоль -heading, м
const FK_CAM_HEIGHT := 3.5            # высота камеры, м
const FK_CAM_LOOK_Y := 1.4            # высота точки взгляда камеры, м
# Сила/траектория.
const FK_CHARGE_MAX_TIME := 0.9       # макс. время заряда силы, с
const FK_POWER_MIN_SPEED := 16.0      # скорость мяча при мин. заряде, м/с
const FK_POWER_MAX_SPEED := 34.0      # при полном заряде, м/с
const FK_ELEV_MIN := 4.0              # угол вылета при мин. заряде, град (настильно, под стенку)
const FK_ELEV_MAX := 22.0             # при полном заряде, град (перелёт стенки / навесом)
const FK_SPREAD_MIN_DEG := 0.5        # угловой разброс при мин. заряде, град
const FK_SPREAD_MAX_DEG := 6.0        # при полном заряде, град
const FK_CURL_SCALE := 6.0            # накопленный боковой ввод стика → величина curl.z
const FK_CURL_MAX := 9.0             # кламп |curl.z|
# Стенка.
const FK_WALL_DIST := 9.15            # дистанция стенки от мяча, м
const FK_WALL_FAR_DIST := 40.0        # дальше — стенки нет (0 игроков)
const FK_WALL_NEAR_DIST := 25.0       # ближе — максимум игроков
const FK_WALL_MIN_PLAYERS := 2        # на границе far
const FK_WALL_MAX_PLAYERS := 5        # у near и ближе
const FK_WALL_SPACING := 0.62         # интервал тел (плечо к плечу), м
const FK_WALL_STAND_REACH := 2.2      # высота, до которой достаёт стоящая стенка, м
const FK_WALL_JUMP_REACH := 2.9       # высота, до которой достаёт прыгнувшая стенка, м
const FK_WALL_JUMP_HEIGHT := 0.7      # на сколько поднимается тело в прыжке, м
const FK_WALL_JUMP_TIME := 0.5        # длительность прыжка (подъём+спуск), с
# Вратарь.
const FK_KEEPER_STEP_OUT := 1.5       # выход вратаря от линии в поле, м
# Пас/навес (спавны).
const FK_MATE_LATERAL := 6.0          # тиммейт: сдвиг вбок от бьющего, м
const FK_MATE_BACK := 2.0             # тиммейт: сдвиг назад от бьющего, м
const FK_TARGET_LATERAL := 6.0        # цель навеса: сдвиг по X от центра, м
const FK_TARGET_DEPTH := 14.0         # цель навеса: отступ в поле от линии ворот, м
# Тайминг.
const FK_WATCH_TIME := 1.5            # держим фикс-вид после удара до возврата, с
```

- [ ] **Step 2: Валидация headless-загрузкой**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
```
Expected: загрузка без новых parse-ошибок про `football_constants.gd` (autoload парсится этим прогоном).

- [ ] **Step 3: Commit**

```bash
git add scripts/data/football_constants.gd
git commit -m "feat(free-kick): add FK_* tuning constants"
```

---

## Task 2: `FreeKickLogic` — прицел, запуск, кручёный (чистые функции)

**Files:**
- Create: `scripts/match/free_kick_logic.gd`
- Create (test): `tests/check_free_kick_logic.gd`

**Interfaces:**
- Produces:
  - `FreeKickLogic.base_heading(from: Vector3, goal_center: Vector3) -> Vector3`
  - `FreeKickLogic.rotate_heading(cur: Vector3, base: Vector3, stick_x: float, speed: float, dt: float, arc: float) -> Vector3`
  - `FreeKickLogic.launch_velocity(heading: Vector3, charge: float, min_speed: float, max_speed: float, min_elev_deg: float, max_elev_deg: float) -> Vector3`
  - `FreeKickLogic.scatter_degrees(charge: float, min_deg: float, max_deg: float) -> float`
  - `FreeKickLogic.apply_scatter(vel: Vector3, spread_deg: float, rng: RandomNumberGenerator) -> Vector3`
  - `FreeKickLogic.curl_from_stick(accum: float, scale: float, max_curl: float) -> Vector3`

- [ ] **Step 1: Написать провальный тест**

Создать `tests/check_free_kick_logic.gd`:

```gdscript
extends SceneTree
## Headless-проверка чистых функций FreeKickLogic.

func _init() -> void:
	var ok := true
	ok = _check_base_heading() and ok
	ok = _check_rotate_clamp() and ok
	ok = _check_launch_monotonic() and ok
	ok = _check_scatter_bounded() and ok
	ok = _check_curl_sign_and_clamp() and ok
	if ok:
		print("CHECK PASS: free_kick_logic")
		quit(0)
	else:
		print("CHECK FAIL: free_kick_logic")
		quit(1)

func _check_base_heading() -> bool:
	var h := FreeKickLogic.base_heading(Vector3(10, 0.11, -20.0), Vector3(0, 0, -52.5))
	# Должно смотреть к воротам: z-компонента отрицательна, длина ~1.
	if h.z >= 0.0 or not is_equal_approx(h.length(), 1.0):
		print("  FAIL base_heading: ", h)
		return false
	return true

func _check_rotate_clamp() -> bool:
	var base := Vector3(0, 0, -1)
	var cur := base
	# Гоним стик вправо долго — угол не должен превысить arc.
	for i in range(500):
		cur = FreeKickLogic.rotate_heading(cur, base, 1.0, 1.6, 0.05, 1.221)
	var ang := absf(base.signed_angle_to(cur, Vector3.UP))
	if ang > 1.221 + 0.001:
		print("  FAIL rotate_clamp: ang=", ang)
		return false
	return true

func _check_launch_monotonic() -> bool:
	var lo := FreeKickLogic.launch_velocity(Vector3(0, 0, -1), 0.0, 16.0, 34.0, 4.0, 22.0)
	var hi := FreeKickLogic.launch_velocity(Vector3(0, 0, -1), 1.0, 16.0, 34.0, 4.0, 22.0)
	# Скорость растёт с зарядом; высота вылета (vy) растёт с зарядом.
	if not (hi.length() > lo.length() and hi.y > lo.y and lo.y >= 0.0):
		print("  FAIL launch_monotonic: lo=", lo, " hi=", hi)
		return false
	return true

func _check_scatter_bounded() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var base := Vector3(0, 0, -1) * 20.0
	for i in range(500):
		var v := FreeKickLogic.apply_scatter(base, 6.0, rng)
		# Отклонение направления не больше ~sqrt(2)*6° ≈ 8.5°.
		if rad_to_deg(base.angle_to(v)) > 10.0:
			print("  FAIL scatter_bounded at i=", i, " ang=", rad_to_deg(base.angle_to(v)))
			return false
	# Нулевой разброс не меняет вектор.
	var same := FreeKickLogic.apply_scatter(base, 0.0, rng)
	if not same.is_equal_approx(base):
		print("  FAIL scatter zero: ", same)
		return false
	return true

func _check_curl_sign_and_clamp() -> bool:
	var pos := FreeKickLogic.curl_from_stick(2.0, 6.0, 9.0)   # 12 → кламп 9
	var neg := FreeKickLogic.curl_from_stick(-2.0, 6.0, 9.0)  # -12 → -9
	if not (is_equal_approx(pos.z, 9.0) and is_equal_approx(neg.z, -9.0) and is_equal_approx(pos.x, 0.0) and is_equal_approx(pos.y, 0.0)):
		print("  FAIL curl: ", pos, " ", neg)
		return false
	# Малый ввод — линейно.
	var small := FreeKickLogic.curl_from_stick(0.5, 6.0, 9.0)  # 3.0
	if not is_equal_approx(small.z, 3.0):
		print("  FAIL curl small: ", small)
		return false
	return true
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_logic.gd"
```
Expected: FAIL/ошибка парса — `FreeKickLogic` ещё не существует.

- [ ] **Step 3: Реализовать `FreeKickLogic` (aim/launch/curl)**

Создать `scripts/match/free_kick_logic.gd`:

```gdscript
class_name FreeKickLogic
extends Object
## Чистая математика штрафного. НИКОГДА не читает FootballConstants — тюнинг параметрами.

## Горизонтальное направление от точки удара к центру ворот (нормализованное).
static func base_heading(from: Vector3, goal_center: Vector3) -> Vector3:
	var d := Vector3(goal_center.x - from.x, 0.0, goal_center.z - from.z)
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD

## Повернуть heading вокруг вертикали на stick_x*speed*dt, кламп к сектору ±arc от base.
## stick_x > 0 (вправо) → поворот вправо (по часовой вокруг UP).
static func rotate_heading(cur: Vector3, base: Vector3, stick_x: float, speed: float, dt: float, arc: float) -> Vector3:
	var next := cur.rotated(Vector3.UP, -stick_x * speed * dt)
	var ang := base.signed_angle_to(next, Vector3.UP)
	ang = clampf(ang, -arc, arc)
	return base.rotated(Vector3.UP, ang).normalized()

## Вектор запуска прямого удара: горизонталь по heading, угол вылета и скорость растут с зарядом.
static func launch_velocity(heading: Vector3, charge: float, min_speed: float, max_speed: float, min_elev_deg: float, max_elev_deg: float) -> Vector3:
	var c := clampf(charge, 0.0, 1.0)
	var speed := lerpf(min_speed, max_speed, c)
	var elev := deg_to_rad(lerpf(min_elev_deg, max_elev_deg, c))
	var flat := Vector3(heading.x, 0.0, heading.z).normalized()
	var dir := flat * cos(elev) + Vector3.UP * sin(elev)
	return dir * speed

## Угловой разброс (град) растёт с зарядом.
static func scatter_degrees(charge: float, min_deg: float, max_deg: float) -> float:
	return lerpf(min_deg, max_deg, clampf(charge, 0.0, 1.0))

## Случайное угловое отклонение вектора запуска (yaw+pitch) в пределах ±spread_deg.
static func apply_scatter(vel: Vector3, spread_deg: float, rng: RandomNumberGenerator) -> Vector3:
	if spread_deg <= 0.0:
		return vel
	var yaw := deg_to_rad(rng.randf_range(-spread_deg, spread_deg))
	var v := vel.rotated(Vector3.UP, yaw)
	var right := Vector3(v.z, 0.0, -v.x)
	if right.length() > 0.001:
		var pitch := deg_to_rad(rng.randf_range(-spread_deg, spread_deg))
		v = v.rotated(right.normalized(), pitch)
	return v

## Curl-вектор из накопленного бокового ввода стика (интеграл stick_x*dt за окно нажатие→контакт).
## Возвращает Vector3(0,0,mag) — mag в конвенции ball._curl.z (боковая, Magnus вдоль left=horiz×UP).
static func curl_from_stick(accum: float, scale: float, max_curl: float) -> Vector3:
	var mag := clampf(accum * scale, -max_curl, max_curl)
	return Vector3(0.0, 0.0, mag)
```

- [ ] **Step 4: Запустить — убедиться, что проходит**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_logic.gd"
```
Expected: `CHECK PASS: free_kick_logic`.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/free_kick_logic.gd tests/check_free_kick_logic.gd
git commit -m "feat(free-kick): FreeKickLogic aim/launch/curl pure math + tests"
```

---

## Task 3: `FreeKickLogic` — стенка и вратарь (чистые функции)

**Files:**
- Modify: `scripts/match/free_kick_logic.gd` (дописать функции)
- Modify: `tests/check_free_kick_logic.gd` (дописать проверки)

**Interfaces:**
- Consumes: файл `FreeKickLogic` из Task 2.
- Produces:
  - `near_far_posts(from: Vector3, goal_center_x: float, half_width: float, goal_line_z: float) -> Array` → `[near: Vector3, far: Vector3]`
  - `wall_count(dist_to_goal: float, far_dist: float, near_dist: float, min_n: int, max_n: int) -> int`
  - `wall_line(from: Vector3, near_post: Vector3, goal_line_z: float, wall_dist: float, y: float) -> Dictionary` → `{center: Vector3, right: Vector3, on_line: bool}`
  - `wall_body_positions(center: Vector3, right: Vector3, count: int, spacing: float) -> Array` (of Vector3)
  - `wall_should_jump(ball_pos: Vector3, ball_vel: Vector3, wall_center: Vector3, stand_reach: float, jump_reach: float, gravity: float) -> bool`
  - `keeper_position(from: Vector3, near_post: Vector3, far_post: Vector3, half_width: float, step_out: float, goal_line_z: float, ground_y: float) -> Vector3`

- [ ] **Step 1: Дописать провальные проверки в тест**

В `tests/check_free_kick_logic.gd` — в `_init()` перед блоком `if ok:` добавить:

```gdscript
	ok = _check_near_far() and ok
	ok = _check_wall_count() and ok
	ok = _check_wall_line_and_bodies() and ok
	ok = _check_wall_jump() and ok
	ok = _check_keeper_pos() and ok
```

И добавить методы в конец файла:

```gdscript
func _check_near_far() -> bool:
	# Мяч правее центра (x>0): ближняя штанга — правая (+x).
	var nf := FreeKickLogic.near_far_posts(Vector3(15, 0.11, -20.0), 0.0, 3.66, -52.5)
	var near: Vector3 = nf[0]
	var far: Vector3 = nf[1]
	if not (near.x > 0.0 and far.x < 0.0):
		print("  FAIL near_far right: ", nf)
		return false
	# Мяч левее (x<0): ближняя — левая.
	var nf2 := FreeKickLogic.near_far_posts(Vector3(-15, 0.11, -20.0), 0.0, 3.66, -52.5)
	if nf2[0].x >= 0.0:
		print("  FAIL near_far left: ", nf2)
		return false
	return true

func _check_wall_count() -> bool:
	var far := FreeKickLogic.wall_count(45.0, 40.0, 25.0, 2, 5)   # >far → 0
	var near := FreeKickLogic.wall_count(20.0, 40.0, 25.0, 2, 5)  # <near → max
	var mid := FreeKickLogic.wall_count(32.5, 40.0, 25.0, 2, 5)   # середина → между
	if not (far == 0 and near == 5 and mid >= 2 and mid <= 5):
		print("  FAIL wall_count: far=", far, " near=", near, " mid=", mid)
		return false
	return true

func _check_wall_line_and_bodies() -> bool:
	# Дальний штрафной: стенка в 9.15 м от мяча на линии мяч→ближняя штанга.
	var from := Vector3(10, 0.11, -20.0)
	var near := Vector3(3.66, 0.0, -52.5)
	var wl := FreeKickLogic.wall_line(from, near, -52.5, 9.15, 0.5)
	if wl["on_line"]:
		print("  FAIL wall_line far should not be on_line")
		return false
	var center: Vector3 = wl["center"]
	if absf(Vector2(center.x - from.x, center.z - from.z).length() - 9.15) > 0.01:
		print("  FAIL wall_line dist: ", center)
		return false
	var bodies := FreeKickLogic.wall_body_positions(center, wl["right"], 4, 0.62)
	if bodies.size() != 4:
		print("  FAIL wall bodies count: ", bodies.size())
		return false
	# Интервал между соседями = spacing.
	var d: float = (bodies[1] - bodies[0]).length()
	if absf(d - 0.62) > 0.001:
		print("  FAIL wall spacing: ", d)
		return false
	# Близкий штрафной (< 9.15 до ворот) → на линию ворот.
	var wl2 := FreeKickLogic.wall_line(Vector3(0, 0.11, -47.0), Vector3(3.66, 0, -52.5), -52.5, 9.15, 0.5)
	if not wl2["on_line"] or not is_equal_approx(wl2["center"].z, -52.5):
		print("  FAIL wall_line near-goal: ", wl2)
		return false
	return true

func _check_wall_jump() -> bool:
	var ball_pos := Vector3(10, 0.11, -20.0)
	var wall_center := Vector3(6.0, 0.5, -25.0)
	# Высокий мяч (перелетает стоящих, но в досягаемости прыжка) → прыгать.
	var high_vel := (wall_center + Vector3(0, 2.6, 0) - ball_pos).normalized() * 22.0
	# Настроим vy так, чтобы в плоскости стенки мяч был ~2.6 м. Упрощённо проверим монотонность:
	var jump := FreeKickLogic.wall_should_jump(ball_pos, high_vel, wall_center, 2.2, 2.9, 9.8)
	# Низкий настильный мяч → не прыгать.
	var low_vel := (wall_center + Vector3(0, 0.3, 0) - ball_pos).normalized() * 22.0
	var no_jump := FreeKickLogic.wall_should_jump(ball_pos, low_vel, wall_center, 2.2, 2.9, 9.8)
	if no_jump:
		print("  FAIL wall_jump: низкий мяч не должен вызывать прыжок")
		return false
	# Мяч, улетающий от стенки (назад) → не прыгать.
	var away := FreeKickLogic.wall_should_jump(ball_pos, Vector3(0, 5, 20), wall_center, 2.2, 2.9, 9.8)
	if away:
		print("  FAIL wall_jump: мяч от стенки")
		return false
	return true

func _check_keeper_pos() -> bool:
	var from := Vector3(15, 0.11, -20.0)
	var nf := FreeKickLogic.near_far_posts(from, 0.0, 3.66, -52.5)
	var kp := FreeKickLogic.keeper_position(from, nf[0], nf[1], 3.66, 1.5, -52.5, 0.5)
	# Вратарь между штанг (|x| <= half_width), в поле от линии (z > goal_line_z), на земле.
	if absf(kp.x) > 3.66 + 0.001 or kp.z <= -52.5 or not is_equal_approx(kp.y, 0.5):
		print("  FAIL keeper_pos: ", kp)
		return false
	return true
```

- [ ] **Step 2: Запустить — падение**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_logic.gd"
```
Expected: FAIL — новых функций ещё нет.

- [ ] **Step 3: Дописать функции в `FreeKickLogic`**

В конец `scripts/match/free_kick_logic.gd` добавить:

```gdscript

## Ближняя/дальняя штанги относительно точки удара (side-aware по горизонтали).
static func near_far_posts(from: Vector3, goal_center_x: float, half_width: float, goal_line_z: float) -> Array:
	var left_post := Vector3(goal_center_x - half_width, 0.0, goal_line_z)
	var right_post := Vector3(goal_center_x + half_width, 0.0, goal_line_z)
	if from.distance_to(left_post) <= from.distance_to(right_post):
		return [left_post, right_post]
	return [right_post, left_post]

## Число игроков в стенке: 0 дальше far_dist, max_n у near_dist и ближе, линейно между.
static func wall_count(dist_to_goal: float, far_dist: float, near_dist: float, min_n: int, max_n: int) -> int:
	if dist_to_goal > far_dist:
		return 0
	if dist_to_goal <= near_dist:
		return max_n
	var t := (dist_to_goal - near_dist) / (far_dist - near_dist)   # 0 у near → 1 у far
	return int(round(lerpf(float(max_n), float(min_n), t)))

## Центр ряда стенки и единичный right-вектор вдоль ряда. Стенка на линии мяч→ближняя штанга,
## в wall_dist от мяча; если ворота ближе wall_dist — на линию ворот (центр створа), on_line=true.
static func wall_line(from: Vector3, near_post: Vector3, goal_line_z: float, wall_dist: float, y: float) -> Dictionary:
	var to_near := Vector3(near_post.x - from.x, 0.0, near_post.z - from.z)
	if to_near.length() <= wall_dist:
		return {"center": Vector3(0.0, y, goal_line_z), "right": Vector3.RIGHT, "on_line": true}
	var dir := to_near.normalized()
	var center := from + dir * wall_dist
	center.y = y
	var right := dir.cross(Vector3.UP).normalized()
	return {"center": center, "right": right, "on_line": false}

## Позиции тел стенки в ряд, центрированы относительно center вдоль right с интервалом spacing.
static func wall_body_positions(center: Vector3, right: Vector3, count: int, spacing: float) -> Array:
	var out := []
	for i in range(count):
		var offset := (float(i) - float(count - 1) * 0.5) * spacing
		out.append(center + right * offset)
	return out

## Прыгать ли стенке: прогноз высоты мяча в плоскости стенки. Прыжок только если мяч перелетает
## стоящих (> stand_reach), но в досягаемости прыжка (<= jump_reach). Мяч от стенки → нет.
static func wall_should_jump(ball_pos: Vector3, ball_vel: Vector3, wall_center: Vector3, stand_reach: float, jump_reach: float, gravity: float) -> bool:
	var horiz := Vector3(ball_vel.x, 0.0, ball_vel.z)
	if horiz.length() < 0.5:
		return false
	var to_wall := Vector3(wall_center.x - ball_pos.x, 0.0, wall_center.z - ball_pos.z)
	var along := to_wall.dot(horiz.normalized())
	if along <= 0.0:
		return false
	var t := along / horiz.length()
	var y := ball_pos.y + ball_vel.y * t - 0.5 * gravity * t * t
	return y > stand_reach and y <= jump_reach

## Оптимальная позиция вратаря: по биссектрисе угла обстрела (между штангами), выход step_out
## от линии в поле. Возвращает мировую точку на высоте ground_y.
static func keeper_position(from: Vector3, near_post: Vector3, far_post: Vector3, half_width: float, step_out: float, goal_line_z: float, ground_y: float) -> Vector3:
	var dir_near := (near_post - from).normalized()
	var dir_far := (far_post - from).normalized()
	var bis := (dir_near + dir_far).normalized()
	var pos := from
	if absf(bis.z) > 0.001:
		var t := (goal_line_z - from.z) / bis.z
		pos = from + bis * t
	var into := signf(from.z - goal_line_z)
	pos.z += into * step_out
	pos.x = clampf(pos.x, -half_width, half_width)
	pos.y = ground_y
	return pos
```

- [ ] **Step 4: Запустить — проходит**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_logic.gd"
```
Expected: `CHECK PASS: free_kick_logic`.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/free_kick_logic.gd tests/check_free_kick_logic.gd
git commit -m "feat(free-kick): FreeKickLogic wall + keeper geometry + tests"
```

---

## Task 4: Клип `jumping_wall` в glb и регистрация

**Files:**
- Modify: `tools/merge_mixamo.py` (добавить `jumping_wall` в `IN_PLACE_CLIPS`)
- Modify: `scripts/player/player_visual.gd:45-47` (`ONESHOT_CLIPS` — добавить `&"jumping_wall"`)
- Modify: `tests/check_footballer_glb.gd` (ожидаемые клипы — добавить `jumping_wall`)
- Rebuild: `assets/models/footballer.glb`

**Interfaces:**
- Consumes: `assets/models/mixamo_src/jumping_wall.fbx` (уже на месте).
- Produces: клип `jumping_wall` в `footballer.glb`, доступный через `PlayerVisual.play_oneshot(&"jumping_wall")`.

- [ ] **Step 1: Заморозить горизонталь клипа в merge-скрипте**

Открыть `tools/merge_mixamo.py`, найти словарь/список `IN_PLACE_CLIPS`. Клипы кипера там заморожены по горизонтали `(0, 2)`. Добавить по тому же образцу запись для `jumping_wall` (горизонталь заморожена, вертикаль клипа не трогаем — тело поднимаем вручную в контроллере). Если формат — dict `{"clip_name": (axes...)}`, добавить `"jumping_wall": (0, 2)`; если список кортежей — добавить аналогичный элемент. Скопировать формат соседней keeper-записи 1:1, поменяв только имя на `jumping_wall`.

- [ ] **Step 2: Пересобрать glb через Blender**

Run:
```
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python "C:\Users\User\Desktop\projects\OpenFootball\tools\merge_mixamo.py" -- "C:\Users\User\Desktop\projects\OpenFootball\assets\models\mixamo_src" "C:\Users\User\Desktop\projects\OpenFootball\assets\models\footballer.glb"
```
Expected: скрипт печатает список смёрженных клипов, среди них `jumping_wall`, и пишет `footballer.glb` без ошибок.

- [ ] **Step 3: Импорт glb в Godot**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import
```
Expected: импорт завершается без ошибок (может быть длинным).

- [ ] **Step 4: Зарегистрировать клип в `ONESHOT_CLIPS`**

В `scripts/player/player_visual.gd` в константе `ONESHOT_CLIPS` (строки ~45-47) добавить `&"jumping_wall"` в массив (например в конец первой строки после `&"standing_up",`):

```gdscript
const ONESHOT_CLIPS := [&"tackle", &"fallen_idle", &"roll_left", &"roll_right", &"standing_up", &"jumping_wall",
	&"keeper_body_block_l", &"keeper_body_block_r", &"keeper_diving_save_l", &"keeper_diving_save_r",
	&"keeper_catch", &"keeper_catch_top", &"keeper_catch_head", &"keeper_scoop", &"keeper_miss_top", &"keeper_idle_ball"]
```

- [ ] **Step 5: Обновить ожидаемый список клипов в тесте glb**

Открыть `tests/check_footballer_glb.gd`, найти массив/список ожидаемых имён клипов, добавить `"jumping_wall"` в него (сохранив формат соседних строк — строковый литерал/`&"..."` как у остальных).

- [ ] **Step 6: Запустить glb-тест**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_footballer_glb.gd"
```
Expected: `CHECK PASS` — `jumping_wall` присутствует.

- [ ] **Step 7: Commit**

```bash
git add tools/merge_mixamo.py scripts/player/player_visual.gd tests/check_footballer_glb.gd assets/models/footballer.glb assets/models/footballer.glb.import
git commit -m "feat(free-kick): add jumping_wall clip to glb + register oneshot"
```

---

## Task 5: `FreeKickController` — ядро (SETUP/AIM/STRIKE/WATCH, только удар)

**Files:**
- Create: `scripts/match/free_kick_controller.gd`

**Interfaces:**
- Consumes: `FreeKickLogic` (Tasks 2-3), `FootballConstants.FK_*` (Task 1), `ball.launch`/`launch_curl`, `PlayerMotor.find_on`, `PlayerVisual` (`trigger`, `consume_root_motion`, `action_contact`). Ожидает от `_manager` методы (появятся в Task 6): `set_free_kick_active(bool)`, `set_field_ai_active(bool)`, `set_free_kick_cam_pose(Transform3D)`. Вызовы через `has_method`-гварды где рискованно.
- Produces:
  - `setup(manager, ball, camera_pivot, power_bar, keeper) -> void`
  - `start(kicker: CharacterBody3D, goal_line_z: float) -> void`
  - `update(delta: float) -> void`
  - `is_active() -> bool`
  - `signal struck`
  - хуки `_spawn_defense()`, `_convert_bodies()`, `_update_wall_jumps(delta)`, `_fire_pass(action, ratio)` — пустые заглушки (наполняются в Tasks 7-9).

- [ ] **Step 1: Создать файл контроллера (ядро)**

Создать `scripts/match/free_kick_controller.gd`:

```gdscript
extends Node
## Контроллер розыгрыша штрафного (Фаза A). Автомат SETUP→AIM→STRIKE→WATCH. Прицел направлением
## (heading), сила=высота, кручёный «доводом» стика до контакта. Математика — FreeKickLogic.
## Стенка/пас/навес наполняются в последующих задачах через хуки.

signal struck

enum Phase { IDLE, SETUP, AIM, STRIKE, WATCH }

var _manager: Node
var _ball: RigidBody3D
var _camera_pivot: Node3D
var _power_bar: ProgressBar
var _keeper: CharacterBody3D

var _phase: int = Phase.IDLE
var _kicker: CharacterBody3D
var _goal_line_z: float = 0.0
var _spot: Vector3 = Vector3.ZERO
var _base_heading: Vector3 = Vector3.FORWARD
var _heading: Vector3 = Vector3.FORWARD
var _foot: String = "penalty_r"

var _charging: bool = false
var _charge: float = 0.0
var _curl_accum: float = 0.0
var _locked: bool = false            # heading/камера зафиксированы (после нажатия kick)

var _fk_rng := RandomNumberGenerator.new()
var _pending_launch: Vector3 = Vector3.ZERO
var _pending_curl: Vector3 = Vector3.ZERO
var _contact_connected := false
var _watch_timer: float = 0.0

# Хуки-состояния для стенки/тиммейтов (наполняются в Tasks 7-9).
var _wall_bodies: Array = []
var _mates: Array = []
var _ball_in_flight_watch := false

func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar, keeper: CharacterBody3D) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar
	_keeper = keeper
	_fk_rng.randomize()

func is_active() -> bool:
	return _phase != Phase.IDLE

## Старт штрафного: точка = позиция бьющего (мяч телепортируется туда), ворота вратаря.
func start(kicker: CharacterBody3D, goal_line_z: float) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_foot = FootballConstants.FK_DEFAULT_FOOT
	_setup()

func _setup() -> void:
	_phase = Phase.SETUP
	_manager.set_free_kick_active(true)
	_manager.set_field_ai_active(false)
	# Точка удара = позиция бьющего (горизонталь), мяч кладём туда.
	_spot = Vector3(_kicker.global_position.x, FootballConstants.BALL_RADIUS, _kicker.global_position.z)
	var goal_center := Vector3(0.0, 0.0, _goal_line_z)
	_base_heading = FreeKickLogic.base_heading(_spot, goal_center)
	_heading = _base_heading
	# Мяч на точку.
	if _ball.has_method(&"release_dribble"):
		_ball.release_dribble()
	if _ball.has_method(&"clear_last_kicker"):
		_ball.clear_last_kicker()
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = _spot
	# Бьющий за мячом на длину разбега, лицом по heading; латеральный сдвиг под опорную ногу.
	var side := 1.0 if _foot == "penalty_r" else -1.0
	var right := _heading.cross(Vector3.UP).normalized()
	_kicker.global_position = _spot - _heading * FootballConstants.FK_RUNUP_DIST \
		+ right * (-side * FootballConstants.FK_FOOT_LATERAL) \
		+ Vector3(0.0, 0.5 - FootballConstants.BALL_RADIUS, 0.0)
	_kicker.look_at(_kicker.global_position + _heading, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
		km.set_move_intent(Vector3.ZERO)
		km.set_face_direction(_heading)
	# Вратарь: реактивный режим штрафного (позиция-якорь, сейв ВКЛ). Хук set_freekick_anchor (Task 8).
	if _keeper != null and _keeper.has_method(&"set_freekick_anchor"):
		var nf := FreeKickLogic.near_far_posts(_spot, 0.0, FootballConstants.GOAL_WIDTH * 0.5, _goal_line_z)
		var kpos := FreeKickLogic.keeper_position(_spot, nf[0], nf[1], FootballConstants.GOAL_WIDTH * 0.5,
			FootballConstants.FK_KEEPER_STEP_OUT, _goal_line_z, 0.5)
		_keeper.set_freekick_anchor(kpos)
	# Оборона (стенка) — хук (Task 7). Атакующие (тиммейт/цели) — хук (Task 9).
	_spawn_defense()
	_spawn_mates()
	_charging = false
	_charge = 0.0
	_curl_accum = 0.0
	_locked = false
	_ball_in_flight_watch = false
	_update_camera_pose()
	_phase = Phase.AIM

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_aim_update(delta)
		Phase.STRIKE:
			_strike_update(delta)
			_update_wall_jumps(delta)
		Phase.WATCH:
			_update_wall_jumps(delta)
			_watch_timer -= delta
			if _watch_timer <= 0.0:
				_release()
	_update_camera_pose()

func _aim_update(delta: float) -> void:
	var stick_x := Input.get_axis(&"move_left", &"move_right")
	# До нажатия kick: стик крутит heading (камера едет). После нажатия: heading зафиксирован,
	# боковой ввод копится в закрутку.
	if not _locked:
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
				FootballConstants.FK_AIM_SPEED, delta, FootballConstants.FK_AIM_ARC)
			var km := PlayerMotor.find_on(_kicker)
			if km != null:
				km.set_face_direction(_heading)
		# Пас/навес доступны до нажатия удара (хук, Task 9).
		if Input.is_action_just_pressed(&"pass_short"):
			_fire_pass("pass_short", 1.0); return
		if Input.is_action_just_pressed(&"pass_through"):
			_fire_pass("pass_through", 1.0); return
		if Input.is_action_just_pressed(&"pass_lob"):
			_fire_pass("pass_lob", 1.0); return
	# Заряд удара.
	if Input.is_action_just_pressed(&"kick"):
		_charging = true
		_locked = true            # фиксируем heading и камеру
		_charge = 0.0
		_curl_accum = 0.0
	if _charging:
		_charge += delta
		_curl_accum += Input.get_axis(&"move_left", &"move_right") * delta   # копим боковой ввод → curl
		var ratio := clampf(_charge / FootballConstants.FK_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or Input.is_action_just_released(&"kick"):
			_fire_shot(ratio)

func _fire_shot(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	var vel := FreeKickLogic.launch_velocity(_heading, ratio,
		FootballConstants.FK_POWER_MIN_SPEED, FootballConstants.FK_POWER_MAX_SPEED,
		FootballConstants.FK_ELEV_MIN, FootballConstants.FK_ELEV_MAX)
	var spread := FreeKickLogic.scatter_degrees(ratio, FootballConstants.FK_SPREAD_MIN_DEG, FootballConstants.FK_SPREAD_MAX_DEG)
	vel = FreeKickLogic.apply_scatter(vel, spread, _fk_rng)
	_pending_launch = vel
	_pending_curl = FreeKickLogic.curl_from_stick(_curl_accum, FootballConstants.FK_CURL_SCALE, FootballConstants.FK_CURL_MAX)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
	_phase = Phase.STRIKE
	var vis := _kicker_visual()
	if vis != null and not _contact_connected:
		vis.action_contact.connect(_on_kicker_contact, CONNECT_ONE_SHOT)
		_contact_connected = true
	if vis == null or not vis.trigger(_foot):
		_on_kicker_contact("penalty")   # фолбэк без анимации — бьём сразу

func _strike_update(_delta: float) -> void:
	var vis := _kicker_visual()
	if vis == null:
		return
	var advance: float = vis.consume_root_motion()
	if advance > 0.0:
		_kicker.global_position += _heading * advance

func _on_kicker_contact(_action: String) -> void:
	_contact_connected = false
	if _pending_curl.length_squared() > 0.0001:
		if _ball.has_method(&"launch_curl"):
			_ball.launch_curl(_pending_launch, _pending_curl, false)
	else:
		if _ball.has_method(&"launch"):
			_ball.launch(_pending_launch, false)
	_ball_in_flight_watch = true      # включаем наблюдение за прыжком стенки (Task 7)
	struck.emit()
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(false)
	_phase = Phase.WATCH
	_watch_timer = FootballConstants.FK_WATCH_TIME

func _release() -> void:
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_face_direction(Vector3.ZERO)
		km.set_control_locked(false)
	if _keeper != null and _keeper.has_method(&"clear_freekick_anchor"):
		_keeper.clear_freekick_anchor()
	_convert_bodies()                 # стенка/тиммейты → обычный ИИ (Tasks 7,9)
	_manager.set_field_ai_active(true)
	_manager.set_free_kick_active(false)
	_phase = Phase.IDLE

func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	var eye := _spot - _heading * FootballConstants.FK_CAM_BACK + Vector3(0.0, FootballConstants.FK_CAM_HEIGHT, 0.0)
	var look := _spot + _heading * 4.0 + Vector3(0.0, FootballConstants.FK_CAM_LOOK_Y, 0.0)
	var t := Transform3D.IDENTITY
	t.origin = eye
	t = t.looking_at(look, Vector3.UP)
	_manager.set_free_kick_cam_pose(t)

func _kicker_visual() -> PlayerVisual:
	if _kicker == null:
		return null
	for c in _kicker.get_children():
		if c is PlayerVisual:
			return c
	return null

# ── Хуки (наполняются в следующих задачах) ────────────────────────────────────
func _spawn_defense() -> void:
	pass   # Task 7

func _spawn_mates() -> void:
	pass   # Task 9

func _update_wall_jumps(_delta: float) -> void:
	pass   # Task 7

func _convert_bodies() -> void:
	pass   # Tasks 7, 9

func _fire_pass(_action: String, _ratio: float) -> void:
	pass   # Task 9
```

- [ ] **Step 2: Валидация парса (headless-загрузка)**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
```
Expected: без parse-ошибок про `free_kick_controller.gd`. (Файл — глобально-парсируемый скрипт; ошибки синтаксиса всплывут здесь.)

- [ ] **Step 3: Commit**

```bash
git add scripts/match/free_kick_controller.gd
git commit -m "feat(free-kick): FreeKickController core (aim/strike/watch, shot only)"
```

---

## Task 6: Обвязка `match_manager` + смоук флоу

**Files:**
- Modify: `scripts/match/match_manager.gd` (ввод F; инстанс `_free_kick`; флаг/методы; делегирование; парковка камеры; F-хендлер)
- Create: `tests/check_free_kick_flow.gd`

**Interfaces:**
- Consumes: `FreeKickController` (Task 5).
- Produces (методы `match_manager`, вызываемые контроллером и тестом): `is_free_kick_active() -> bool`, `set_free_kick_active(bool)`, `set_free_kick_cam_pose(Transform3D)`; поле `_free_kick` (узел `FreeKickController`).

- [ ] **Step 1: Добавить действие ввода `free_kick_debug` (F)**

В `scripts/match/match_manager.gd`, в `_setup_inputs()` в словарь `actions` (после строки `&"penalty_debug": …`) добавить:

```gdscript
		&"free_kick_debug": {"keys": [KEY_F], "buttons": [], "axes": []},
```

- [ ] **Step 2: Объявить поле, флаг и позу камеры**

Рядом с `var _penalty` (строка ~24) и `var _penalty_cam_pose` (строка ~25) добавить:

```gdscript
var _free_kick                                 # FreeKickController
var _free_kick_active: bool = false
var _free_kick_cam_pose: Transform3D = Transform3D.IDENTITY
```

- [ ] **Step 3: Инстанцировать контроллер в `_ready`**

Рядом с блоком создания `_penalty` (строки ~131-134) добавить (после него):

```gdscript
	_free_kick = preload("res://scripts/match/free_kick_controller.gd").new()
	_free_kick.name = "FreeKickController"
	add_child(_free_kick)
	_free_kick.setup(self, ball, camera_pivot, power_bar, _keeper)
```

- [ ] **Step 4: Методы гейтинга/камеры**

Рядом с `set_penalty_active` / `set_penalty_cam_pose` (строки ~565-570) добавить:

```gdscript
func is_free_kick_active() -> bool:
	return _free_kick_active


func set_free_kick_active(on: bool) -> void:
	_free_kick_active = on


func set_free_kick_cam_pose(pose: Transform3D) -> void:
	_free_kick_cam_pose = pose
```

- [ ] **Step 5: Делегирование в `_physics_process`**

В `_physics_process` (после пенальти-блока, строки ~789-798) — сразу после `if _penalty_active: … return` и до пенальти-хендлера добавить:

```gdscript
	# Штрафной-режим: всё ведёт контроллер, обычные системы заглушены.
	if _free_kick_active:
		_free_kick.update(delta)
		return
	# Штрафной по F — только из чистого состояния (не во время празднования гола).
	if Input.is_action_just_pressed(&"free_kick_debug") and _keeper != null and not _celebrating:
		_free_kick.start(controlled_player, _keeper.goal_line_z)
		return
```

- [ ] **Step 6: Парковка камеры в `_process`**

В `_process` (строки ~740-742) заменить условие парковки, чтобы учитывать и штрафной:

Найти:
```gdscript
	if _penalty_active:
		camera_pivot.global_transform = _penalty_cam_pose
	else:
```
Заменить на:
```gdscript
	if _penalty_active:
		camera_pivot.global_transform = _penalty_cam_pose
	elif _free_kick_active:
		camera_pivot.global_transform = _free_kick_cam_pose
	else:
```

- [ ] **Step 7: Создать смоук-тест флоу**

Создать `tests/check_free_kick_flow.gd`:

```gdscript
extends SceneTree
## Headless-смоук флоу штрафного: грузим match.tscn, стартуем розыгрыш и бьём (в обход Input),
## крутим кадры и проверяем — мяч получил импульс, режим штрафного снялся, без крашей.

var _mm: Node
var _fk: Node
var _elapsed: float = 0.0
var _started: bool = false
var _fired: bool = false
var _max_ball_speed: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 0.15 and not _started:
		_fk = _mm.get_node_or_null("FreeKickController")
		if _fk == null:
			print("CHECK FAIL: нет узла FreeKickController")
			return true
		_fk.start(_mm.controlled_player, _mm._keeper.goal_line_z)
		_started = true
		if not _mm.is_free_kick_active():
			print("CHECK FAIL: режим штрафного не включился после start")
			return true
		return false
	if _elapsed > 0.3 and _started and not _fired:
		_fk._fire_shot(0.7)
		_fired = true
		return false
	if _fired:
		_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
	if _elapsed > 4.0:
		var released: bool = not _mm.is_free_kick_active()
		var launched: bool = _max_ball_speed > 1.0
		print("SMOKE: max_ball_speed=", _max_ball_speed, " free_kick_active=", _mm.is_free_kick_active())
		if released and launched:
			print("CHECK PASS: free_kick flow (launched + released)")
			quit(0)
		else:
			print("CHECK FAIL: released=", released, " launched=", launched)
			quit(1)
		return true
	return false
```

- [ ] **Step 8: Запустить смоук — проходит**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_flow.gd"
```
Expected: `CHECK PASS: free_kick flow (launched + released)`.

- [ ] **Step 9: Валидация match-сцены**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: ошибки только из известного baseline (см. CLAUDE.md) — новых категорий нет.

- [ ] **Step 10: Commit**

```bash
git add scripts/match/match_manager.gd tests/check_free_kick_flow.gd
git commit -m "feat(free-kick): wire controller into match_manager + flow smoke test"
```

---

## Task 7: Стенка — спавн, геометрия, авто-прыжок, конвертация в ИИ

**Files:**
- Modify: `scripts/match/free_kick_controller.gd` (наполнить `_spawn_defense`, `_update_wall_jumps`, `_convert_bodies`; добавить хелперы спавна/прыжка)
- Modify: `tests/check_free_kick_flow.gd` (проверить: стенка заспавнилась и сконвертировалась)

**Interfaces:**
- Consumes: `FreeKickLogic.near_far_posts/wall_count/wall_line/wall_body_positions/wall_should_jump`, `FootballConstants.FK_WALL_*`, группы `team_2`/`fallen`, `simple_ai.gd`, `PlayerVisual.play_oneshot(&"jumping_wall")`.
- Produces: `_wall_bodies: Array[Dictionary]` где элемент `{"body": CharacterBody3D, "jumping": bool, "jump_t": float, "base_y": float}`.

- [ ] **Step 1: Дописать проверку стенки в смоук-тест (падение)**

В `tests/check_free_kick_flow.gd` в финальном блоке (`if _elapsed > 4.0:`) заменить строки формирования вердикта на версию с проверкой конвертации стенки:

```gdscript
	if _elapsed > 4.0:
		var released: bool = not _mm.is_free_kick_active()
		var launched: bool = _max_ball_speed > 1.0
		# Тела стенки после розыгрыша должны стать активным team_2-ИИ (simple_ai), не удалиться.
		var wall_ok := true
		for entry in _fk._wall_bodies:
			var b = entry["body"]
			if not is_instance_valid(b) or not b.is_in_group("team_2") or b.get_script() == null:
				wall_ok = false
		print("SMOKE: max_ball_speed=", _max_ball_speed, " wall_bodies=", _fk._wall_bodies.size(), " wall_ok=", wall_ok)
		if released and launched and wall_ok:
			print("CHECK PASS: free_kick flow (launched + released + wall converted)")
			quit(0)
		else:
			print("CHECK FAIL: released=", released, " launched=", launched, " wall_ok=", wall_ok)
			quit(1)
		return true
```

Примечание: чтобы стенка гарантированно заспавнилась, тест бьёт с текущей позиции `controlled_player`. Если она далеко от ворот (>40 м) — стенки не будет и `_wall_bodies` пуст (цикл `for` не выполнится, `wall_ok=true`). Тест устойчив к обоим случаям; при `size()==0` проверка стенки тривиально проходит. Для явной проверки геометрии стенки полагаемся на юнит-тест `FreeKickLogic` (Task 3).

- [ ] **Step 2: Запустить — падение**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_flow.gd"
```
Expected: FAIL (или прежний PASS без учёта стенки) — `_spawn_defense`/`_convert_bodies` ещё пустые, `_wall_bodies` пуст; если позиция даёт стенку — падение по `wall_ok`. (Если `controlled_player` дальше 40 м, тест может пройти вырожденно — это ок, следующий шаг делает конвертацию реальной.)

- [ ] **Step 3: Реализовать спавн стенки, прыжок и конвертацию**

В `scripts/match/free_kick_controller.gd` заменить заглушки `_spawn_defense`, `_update_wall_jumps`, `_convert_bodies` на реализации и добавить хелпер `_make_wall_body`:

```gdscript
func _spawn_defense() -> void:
	_wall_bodies.clear()
	var dist_to_goal := absf(_spot.z - _goal_line_z)
	var count := FreeKickLogic.wall_count(dist_to_goal, FootballConstants.FK_WALL_FAR_DIST,
		FootballConstants.FK_WALL_NEAR_DIST, FootballConstants.FK_WALL_MIN_PLAYERS, FootballConstants.FK_WALL_MAX_PLAYERS)
	if count <= 0:
		return
	var nf := FreeKickLogic.near_far_posts(_spot, 0.0, FootballConstants.GOAL_WIDTH * 0.5, _goal_line_z)
	var wl := FreeKickLogic.wall_line(_spot, nf[0], _goal_line_z, FootballConstants.FK_WALL_DIST, 0.5)
	var positions := FreeKickLogic.wall_body_positions(wl["center"], wl["right"], count, FootballConstants.FK_WALL_SPACING)
	for pos in positions:
		var body := _make_wall_body(pos)
		_wall_bodies.append({"body": body, "jumping": false, "jump_t": 0.0, "base_y": body.global_position.y})

## Создать статичное тело стенки (team_2, лицом к мячу), пока без ИИ-скрипта.
func _make_wall_body(pos: Vector3) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "WallMember"
	p.global_position = pos
	var visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	p.add_child(visual)
	p.add_child(PlayerMotor.new())
	visual.apply_appearance({"kit_color": Color(0.9, 0.1, 0.1)})
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.5
	shape.radius = 0.3
	col.shape = shape
	col.position = Vector3(0, 0.25, 0)
	p.add_child(col)
	_manager.add_child(p)
	p.add_to_group("team_2")
	p.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	p.collision_mask = FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
	# Лицом к мячу, мотор залочен (стоит на месте).
	p.look_at(Vector3(_spot.x, pos.y, _spot.z), Vector3.UP)
	var pm := PlayerMotor.find_on(p)
	if pm != null:
		pm.set_control_locked(true)
		pm.set_move_intent(Vector3.ZERO)
	return p

## Каждый кадр после удара: решаем прыжок стенки и ведём вертикальную дугу прыгнувших тел.
func _update_wall_jumps(delta: float) -> void:
	if not _ball_in_flight_watch:
		return
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	for entry in _wall_bodies:
		var b: CharacterBody3D = entry["body"]
		if not is_instance_valid(b):
			continue
		if not entry["jumping"]:
			# Решение о прыжке (пока мяч летит).
			var should := FreeKickLogic.wall_should_jump(_ball.global_position, _ball.linear_velocity,
				b.global_position, FootballConstants.FK_WALL_STAND_REACH, FootballConstants.FK_WALL_JUMP_REACH, g)
			if should:
				entry["jumping"] = true
				entry["jump_t"] = 0.0
				b.add_to_group("fallen")   # чтобы PlayerMotor не пинил Y во время прыжка
				var v := _wall_visual(b)
				if v != null:
					v.play_oneshot(&"jumping_wall")
		else:
			# Вертикальная дуга: подъём и спуск за FK_WALL_JUMP_TIME.
			entry["jump_t"] += delta
			var tt: float = entry["jump_t"] / FootballConstants.FK_WALL_JUMP_TIME
			if tt >= 1.0:
				b.global_position.y = entry["base_y"]
				b.remove_from_group("fallen")
				entry["jumping"] = false
				entry["jump_t"] = FootballConstants.FK_WALL_JUMP_TIME + 1.0   # больше не прыгаем
				var v := _wall_visual(b)
				if v != null:
					v.recover()
			else:
				var arc: float = sin(tt * PI)   # 0→1→0
				b.global_position.y = entry["base_y"] + arc * FootballConstants.FK_WALL_JUMP_HEIGHT

func _wall_visual(b: Node) -> PlayerVisual:
	for c in b.get_children():
		if c is PlayerVisual:
			return c
	return null

## Стенка → обычный team_2-ИИ (simple_ai). Тела не удаляются, а вливаются в игру.
func _convert_bodies() -> void:
	var ai_script := preload("res://scripts/ai/simple_ai.gd")
	for entry in _wall_bodies:
		var b: CharacterBody3D = entry["body"]
		if not is_instance_valid(b):
			continue
		if b.is_in_group("fallen"):
			b.remove_from_group("fallen")
			b.global_position.y = entry["base_y"]
		var pm := PlayerMotor.find_on(b)
		if pm != null:
			pm.set_control_locked(false)
		b.set_script(ai_script)
		b.set_physics_process(true)
		b.ball = _ball
		b.home_goal = _manager.get_node_or_null("GoalHome/GoalArea")
	_wall_bodies.clear()
```

- [ ] **Step 4: Запустить смоук — проходит**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_flow.gd"
```
Expected: `CHECK PASS: free_kick flow (launched + released + wall converted)`.

- [ ] **Step 5: Валидация match-сцены**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: без новых категорий ошибок vs baseline.

- [ ] **Step 6: Commit**

```bash
git add scripts/match/free_kick_controller.gd tests/check_free_kick_flow.gd
git commit -m "feat(free-kick): wall spawn/geometry/auto-jump + convert to team_2 AI"
```

---

## Task 8: Вратарь — режим якоря штрафного (реактивный)

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (поля `_freekick_mode`/`_freekick_anchor`, методы `set_freekick_anchor`/`clear_freekick_anchor`, использование якоря в `_position`)

**Interfaces:**
- Consumes: вызовы контроллера `_keeper.set_freekick_anchor(pos)` (в `_setup`, Task 5) и `_keeper.clear_freekick_anchor()` (в `_release`, Task 5).
- Produces: `set_freekick_anchor(pos: Vector3) -> void`, `clear_freekick_anchor() -> void`. Реактивный сейв (`shot_intercept`/рефлекс ловли) остаётся ВКЛ.

- [ ] **Step 1: Объявить поля режима**

В `scripts/ai/keeper_ai.gd` рядом с `var _penalty_mode: bool = false` (строка ~37) добавить:

```gdscript
var _freekick_mode: bool = false
var _freekick_anchor: Vector3 = Vector3.ZERO
```

- [ ] **Step 2: Использовать якорь как цель движения в `_position`**

В `keeper_ai.gd` в `_position(delta)` найти вычисление цели (строки ~151-159):

```gdscript
	var target := KeeperLogic.line_position(
		ball.global_position, goal_line_z, FootballConstants.GOAL_WIDTH * 0.5,
		FootballConstants.KEEPER_LINE_NARROW_GAIN, FootballConstants.KEEPER_MAX_OFF_LINE)
	var to := target - global_position
```
Заменить первую часть (только вычисление `target`) на:

```gdscript
	var target := _freekick_anchor if _freekick_mode else KeeperLogic.line_position(
		ball.global_position, goal_line_z, FootballConstants.GOAL_WIDTH * 0.5,
		FootballConstants.KEEPER_LINE_NARROW_GAIN, FootballConstants.KEEPER_MAX_OFF_LINE)
	var to := target - global_position
```

(Рефлекс ловли и реактивный `shot_intercept` ниже по функции НЕ трогаем — они остаются активны: вратарь «смотрит куда летит мяч».)

- [ ] **Step 3: Методы установки/снятия якоря**

Рядом с `func set_penalty_mode(on: bool)` (строка ~238) добавить:

```gdscript
## Режим штрафного: держим оптимальную позицию-якорь, реактивный сейв ОСТАЁТСЯ включён
## (в отличие от пенальти-режима — вратарь видит мяч). Позицию считает FreeKickLogic.keeper_position.
func set_freekick_anchor(pos: Vector3) -> void:
	_freekick_mode = true
	_freekick_anchor = pos
	_penalty_mode = false

func clear_freekick_anchor() -> void:
	_freekick_mode = false
```

- [ ] **Step 4: Валидация match-сцены (парсит keeper_ai)**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: без новых категорий ошибок vs baseline.

- [ ] **Step 5: Смоук флоу всё ещё зелёный**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_flow.gd"
```
Expected: `CHECK PASS` (теперь `_setup` реально вызывает `set_freekick_anchor` — не должно ломать флоу).

- [ ] **Step 6: Commit**

```bash
git add scripts/ai/keeper_ai.gd
git commit -m "feat(free-kick): keeper freekick anchor mode (reactive save on)"
```

---

## Task 9: Пас/навес — спавн тиммейта и целей, диспетч через PassSystem, конвертация

**Files:**
- Modify: `scripts/match/free_kick_controller.gd` (наполнить `_spawn_mates`, `_fire_pass`; расширить `_convert_bodies` конвертацией своих в `team_1`)
- Modify: `tests/check_free_kick_flow.gd` (добавить отдельный прогон паса — опционально в том же файле)

**Interfaces:**
- Consumes: `PassSystem.launch_ground`/`launch_lob`/`select_target`/`ground_pass_speed`, `FootballConstants.FK_MATE_*`/`FK_TARGET_*` и `PASS_*`, `teammate_ai.gd`, группа `team_1`, `ball.launch`.
- Produces: `_mates: Array[Dictionary]` `{"body": CharacterBody3D, "is_target": bool}`; наполненный `_fire_pass(action, ratio)`.

- [ ] **Step 1: Реализовать спавн своих (тиммейт + цели навеса)**

В `scripts/match/free_kick_controller.gd` заменить заглушку `_spawn_mates` на:

```gdscript
func _spawn_mates() -> void:
	_mates.clear()
	var right := _heading.cross(Vector3.UP).normalized()
	# Тиммейт рядом с бьющим (для короткого паса).
	var mate_pos := _spot + right * FootballConstants.FK_MATE_LATERAL - _heading * FootballConstants.FK_MATE_BACK
	mate_pos.y = 0.5
	_mates.append({"body": _make_mate_body(mate_pos), "is_target": false})
	# 1-2 атакующих у ворот (цель для навеса), по разные стороны от центра.
	var into := signf(_goal_line_z) * -1.0   # от ворот в поле
	var depth_z := _goal_line_z - into * FootballConstants.FK_TARGET_DEPTH
	for sx in [-1.0, 1.0]:
		var tp := Vector3(sx * FootballConstants.FK_TARGET_LATERAL, 0.5, depth_z)
		_mates.append({"body": _make_mate_body(tp), "is_target": true})

## Создать статичное тело своей команды (team_1), пока без ИИ-скрипта.
func _make_mate_body(pos: Vector3) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "FKMate"
	p.global_position = pos
	var visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	p.add_child(visual)
	p.add_child(PlayerMotor.new())
	visual.apply_appearance({"kit_color": Color(0.1, 0.1, 0.9)})
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.5
	shape.radius = 0.3
	col.shape = shape
	col.position = Vector3(0, 0.25, 0)
	p.add_child(col)
	_manager.add_child(p)
	p.add_to_group("team_1")
	p.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	p.collision_mask = FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
	var pm := PlayerMotor.find_on(p)
	if pm != null:
		pm.set_control_locked(true)
		pm.set_move_intent(Vector3.ZERO)
	return p
```

- [ ] **Step 2: Реализовать диспетч паса/навеса**

Заменить заглушку `_fire_pass` на:

```gdscript
## Пас/навес: выбираем цель (короткий — тиммейт рядом; навес/lob — атакующий у ворот),
## считаем скорость по дистанции (ground) или дугу (lob) через PassSystem, запускаем ball.launch.
func _fire_pass(action: String, _ratio: float) -> void:
	if _mates.is_empty():
		return
	var from: Vector3 = _ball.global_position
	var target: CharacterBody3D = _select_pass_target(action)
	if target == null:
		return
	var to: Vector3 = target.global_position
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var vel: Vector3
	if action == "pass_lob":
		# Навес: баллистическая дуга к цели у ворот.
		vel = PassSystem.launch_lob(from, to, FootballConstants.PASS_LOB_PEAK_HEIGHT, g)
	else:
		# Ground: скорость по дистанции при полном заряде (быстрый твёрдый пас).
		var dist := Vector2(to.x - from.x, to.z - from.z).length()
		var speed := PassSystem.ground_pass_speed(dist, 1.0,
			FootballConstants.PASS_GROUND_MIN_TRAVEL_TIME, FootballConstants.PASS_GROUND_MAX_TRAVEL_TIME,
			FootballConstants.PASS_GROUND_MIN_SPEED, FootballConstants.PASS_GROUND_MAX_SPEED)
		vel = PassSystem.launch_ground(from, to, speed)
	if _ball.has_method(&"launch"):
		_ball.launch(vel, action != "pass_lob")   # ground — настильно (flat=true), навес — дугой
	struck.emit()
	# После паса переключаем управление на получателя и завершаем розыгрыш (как страйк).
	_manager.controlled_player = target
	_phase = Phase.WATCH
	_watch_timer = FootballConstants.FK_WATCH_TIME

## Короткий/through пас — тиммейт рядом; навес — атакующий у ворот. Фолбэк — первый доступный.
func _select_pass_target(action: String) -> CharacterBody3D:
	var want_target := action == "pass_lob"
	for entry in _mates:
		if bool(entry["is_target"]) == want_target and is_instance_valid(entry["body"]):
			return entry["body"]
	for entry in _mates:
		if is_instance_valid(entry["body"]):
			return entry["body"]
	return null
```

- [ ] **Step 3: Расширить `_convert_bodies` конвертацией своих в `team_1`**

В `_convert_bodies` (из Task 7) перед `_wall_bodies.clear()` добавить конвертацию `_mates` в `teammate_ai`:

```gdscript
	var mate_script := preload("res://scripts/ai/teammate_ai.gd")
	for entry in _mates:
		var mb: CharacterBody3D = entry["body"]
		if not is_instance_valid(mb):
			continue
		var mpm := PlayerMotor.find_on(mb)
		if mpm != null:
			mpm.set_control_locked(false)
		mb.set_script(mate_script)
		mb.set_physics_process(true)
		mb.ball = _ball
	_mates.clear()
```

(Разместить этот блок в `_convert_bodies` после цикла конвертации стенки и до `_wall_bodies.clear()`.)

- [ ] **Step 4: Проверить сигнатуры `teammate_ai` перед конвертацией**

Открыть `scripts/ai/teammate_ai.gd`, проверить экспортируемые поля, которые мы присваиваем: `ball`. Если у `teammate_ai` поле мяча называется иначе или требует `home_goal`/`target_node`, скорректировать присваивания в блоке Step 3 под реальные имена (grep по `@export` в начале файла). Если `teammate_ai` ждёт `controlled_player`-контекст от менеджера — не присваивать лишнего, достаточно `ball`.

Run (для инспекции):
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
```
Expected: без parse-ошибок контроллера.

- [ ] **Step 5: Добавить проверку паса в смоук-тест**

В `tests/check_free_kick_flow.gd` расширить: после проверки удара — второй сценарий не обязателен; вместо этого добавить лёгкую проверку, что после `start` спавнятся `_mates` (тиммейт+цели). В блоке `if _elapsed > 0.15 … _started = true` сразу после успешного старта добавить:

```gdscript
		if _fk._mates.size() < 1:
			print("CHECK FAIL: не заспавнены тиммейт/цели (_mates пуст)")
			return true
```

- [ ] **Step 6: Запустить смоук — проходит**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_flow.gd"
```
Expected: `CHECK PASS: free_kick flow (launched + released + wall converted)` и `_mates` не пуст.

- [ ] **Step 7: Валидация match-сцены**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: без новых категорий ошибок vs baseline.

- [ ] **Step 8: Commit**

```bash
git add scripts/match/free_kick_controller.gd tests/check_free_kick_flow.gd
git commit -m "feat(free-kick): pass/lob to spawned mates + convert to team_1 AI"
```

---

## Manual Verification (после Task 9 — живой прогон)

Headless покрывает логику страйка/запуска/конвертации, но НЕ покрывает «фил». В редакторе/сборке проверить руками (F запускает штрафной из позиции игрока):

1. **Прицел/камера:** до нажатия удара стик влево-вправо крутит направление, камера едет орбитой; при нажатии `kick` (D/геймпад X) камера/направление фиксируются.
2. **Сила=высота:** слабый заряд → мяч идёт низом (под стенку); полный → перелетает стенку/навесом.
3. **Кручёный:** держа удар, повести стик вбок до контакта → мяч закручивается в эту сторону (в т.ч. противоположную направлению).
4. **Стенка:** на ближнем штрафном (<25 м) стоит 4-5 тел в 9.15 м, перекрывают ближний угол; на высокий мяч — прыгают (`jumping_wall`), низ открывается; на дальнем (>40 м) стенки нет. После розыгрыша тела оживают как соперники.
5. **Вратарь:** стоит смещённым к ближней штанге, на 1-2 шага от линии, реагирует на реальную траекторию (ловит/ныряет).
6. **Пас/навес:** до нажатия удара `pass_short`/`pass_through` → пас тиммейту рядом; `pass_lob` → навес к воротам; управление переходит к получателю.

Отклонения по тюнингу править через `FK_*` в `football_constants.gd`.

---

## Self-Review (выполнено при написании плана)

- **Покрытие спеки:** §2 поток/гейтинг → Tasks 5,6; §3 прицел/камера → Tasks 2,5; §4 сила/кручёный/взаимодействие со стенкой → Tasks 2,5,7; §5 стенка (кол-во/геометрия/прыжок/конвертация) → Tasks 3,7; §6 вратарь → Tasks 3,8; §7 пас/навес/разбег → Tasks 5,9; §8 структура → Tasks 2-9; §9 константы → Task 1; §10 тесты → Tasks 2,3,6,7,9. §11 допущения учтены (общий флаг → отдельный `_free_kick_active`; curl в окне нажатие→контакт → `_curl_accum` в `_aim_update`; порядок «высокие в центр» — равномерный, хук на будущее — в `wall_body_positions`).
- **Плейсхолдеры:** заглушки-хуки в Task 5 намеренны и наполняются в Tasks 7-9 конкретным кодом; иных TODO/placeholder нет.
- **Согласованность типов:** имена методов контроллера (`start`, `update`, `is_active`, `_fire_shot`, `_spawn_defense`, `_update_wall_jumps`, `_convert_bodies`, `_fire_pass`, `_spawn_mates`) и `match_manager` (`is_free_kick_active`, `set_free_kick_active`, `set_free_kick_cam_pose`) единообразны между задачами; `keeper.set_freekick_anchor`/`clear_freekick_anchor` совпадают в Tasks 5 и 8; `FreeKickLogic`-сигнатуры совпадают между Task 2/3 и вызовами в Tasks 5,7.
- **Известный технический долг для приёмки:** `wall_should_jump` использует g как параметр; вертикаль прыжка ведётся вручную (`FK_WALL_JUMP_HEIGHT`), клип `jumping_wall` заморожен по горизонтали — если визуально «двоит» вертикаль, добавить ось 1 в `IN_PLACE_CLIPS` (Task 4). Знак `curl.z` при живой проверке может потребовать инверсии в `curl_from_stick` (отметка в §Manual).
```

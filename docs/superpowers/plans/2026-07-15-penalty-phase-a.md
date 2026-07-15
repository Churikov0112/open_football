# Пенальти — Фаза A (исполнение за бьющего) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** По кнопке P человек разыгрывает пенальти в атакуемые ворота: фикс-камера, жёлтый прицел с растущим от силы кругом разброса, прямой удар или черпачок, root-motion разбег; вратарь прыгает вслепую в случайную зону теми же клипами/геометрией, что и с игры.

**Architecture:** Базовый `PenaltyController` (Node) разыгрывает ОДИН пенальти (автомат `SETUP→AIM→STRIKE`), испускает сигнал `struck` и при `release_after_strike=true` отдаёт мяч в обычную игру — исход (гол/сейв/промах) разруливают штатные системы. Вся математика — чистые функции `PenaltyLogic`. Root-motion разбег применяется к телу бьющего. Вратарь получает `set_penalty_mode()`/`begin_penalty_dive(zone)`, переиспользуя существующие нырок/центральную ловлю. Фазы B/C — не в этом плане.

**Tech Stack:** Godot 4.7, GDScript. Тесты — headless `SceneTree`-скрипты (`tests/check_*.gd`) для чистых функций + валидация сцены двумя headless-командами + ручная проверка «фила».

## Global Constraints

- Godot **4.7 / GDScript**; Windows.
- Godot exe: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe"`.
- Blender exe (пересборка glb): `& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"`.
- **Чистые классы (`PenaltyLogic`) НИКОГДА не читают `FootballConstants`** — тюнинг только параметрами (как `PassSystem`/`KeeperLogic`/`NetSim`).
- **Весь random — через явный `RandomNumberGenerator`-параметр** (`_pen_rng`), не глобальный `randf()` — иначе тест недетерминирован.
- **InputMap строится в коде** в `match_manager._setup_inputs()`; `project.godot` input мёртв — правим только `_setup_inputs()`.
- **Движение игроков — через `PlayerMotor`**; root-motion разбег — намеренное исключение (мотор залочен, телом владеет контроллер, как `move_and_collide` в подкате).
- Стиль кода: поллинг в `_physics_process` + прямые вызовы + флаги; сигналы — только на тайминг-швах (`action_contact` и один `struck`). Не плодить сигнальную архитектуру.
- Атакуемые ворота (где стоит вратарь): `_keeper.goal_line_z` (= `-field_length`), `into_field = +1`. Точка пенальти: `Vector3(0, BALL_RADIUS, goal_line_z + into_field * PENALTY_SPOT_DIST)`.
- Спек: `docs/superpowers/specs/2026-07-15-penalty-design.md`.

---

## Структура файлов

**Создаём:**
- `scripts/match/penalty_logic.gd` (`class_name PenaltyLogic extends Object`) — чистая математика прицела/разброса/зон.
- `scripts/match/penalty_controller.gd` (`extends Node`) — автомат одного пенальти + HUD-кольцо + страйк.
- `tests/check_penalty_logic.gd` — тест чистых функций.
- `tools/measure_penalty_runup.gd` (headless `SceneTree`) — замер `PEN_RUNUP_DIST`, кадра контакта и пути root-motion трека из glb.

**Правим:**
- `scripts/data/football_constants.gd` — секция `PENALTY`.
- `tools/merge_mixamo.py` — гарантировать, что `penalty_kick_l/_r` НЕ в `IN_PLACE_CLIPS` (сохранить разбег).
- `scripts/player/player_visual.gd` — регистрация `penalty_l`/`penalty_r`, root-motion трек + `consume_root_motion()`.
- `scripts/ai/keeper_ai.gd` — `set_penalty_mode()`, `begin_penalty_dive(zone)`, пенальти-ветка в `_position`.
- `scripts/match/match_manager.gd` — `_penalty_active` + `is_penalty_active()`, action `penalty_debug` (P), гейты ввода/ИИ/камеры, инстанс контроллера, старт по P.
- `CLAUDE.md`, `AGENTS.md` — раздел про пенальти.

---

## Task 1: PenaltyLogic — чистые функции + тест

**Files:**
- Create: `scripts/match/penalty_logic.gd`
- Test: `tests/check_penalty_logic.gd`

**Interfaces:**
- Produces:
  - `enum Zone { LOW_L, HIGH_L, LOW_R, HIGH_R, CENTER }`
  - `static func move_reticle(cur: Vector2, stick: Vector2, speed: float, dt: float, half_width: float, height: float, overhang: float) -> Vector2`
  - `static func spread_radius(charge_ratio: float, min_r: float, max_r: float) -> float`
  - `static func power_speed(charge_ratio: float, min_speed: float, max_speed: float) -> float`
  - `static func sample_in_disc(center: Vector2, radius: float, rng: RandomNumberGenerator) -> Vector2`
  - `static func plane_point_to_world(xy: Vector2, goal_center_x: float, goal_line_z: float) -> Vector3`
  - `static func random_dive_zone(rng: RandomNumberGenerator) -> int`
  - `static func zone_target(zone: int, goal_center_x: float, half_width: float, low_y: float, high_y: float, lateral: float, goal_line_z: float) -> Vector3`

- [ ] **Step 1: Написать реализацию `penalty_logic.gd`**

```gdscript
class_name PenaltyLogic
extends Object
## Чистая математика пенальти. НИКОГДА не читает FootballConstants — тюнинг параметрами.

## Зоны прыжка вратаря (слепой выбор). CENTER = остался в центре.
enum Zone { LOW_L, HIGH_L, LOW_R, HIGH_R, CENTER }

## Сдвиг маркера прицела по плоскости ворот (X = ширина, Y = высота над газоном),
## кламп в рамку + небольшой овершут за штанги/перекладину (можно целиться впритирку/мимо).
static func move_reticle(cur: Vector2, stick: Vector2, speed: float, dt: float, half_width: float, height: float, overhang: float) -> Vector2:
	var next := cur + stick * speed * dt
	next.x = clampf(next.x, -(half_width + overhang), half_width + overhang)
	next.y = clampf(next.y, 0.0, height + overhang)
	return next

## Радиус круга разброса растёт с зарядом силы.
static func spread_radius(charge_ratio: float, min_r: float, max_r: float) -> float:
	return lerpf(min_r, max_r, clampf(charge_ratio, 0.0, 1.0))

## Скорость мяча растёт с зарядом силы.
static func power_speed(charge_ratio: float, min_speed: float, max_speed: float) -> float:
	return lerpf(min_speed, max_speed, clampf(charge_ratio, 0.0, 1.0))

## Равномерный семпл точки внутри диска (радиус через sqrt(u) — иначе центр перегружен).
static func sample_in_disc(center: Vector2, radius: float, rng: RandomNumberGenerator) -> Vector2:
	var ang := rng.randf() * TAU
	var r := radius * sqrt(rng.randf())
	return center + Vector2(cos(ang), sin(ang)) * r

## Точка плоскости ворот (xy) → мир. xy.x — смещение от центра створа, xy.y — высота над газоном.
static func plane_point_to_world(xy: Vector2, goal_center_x: float, goal_line_z: float) -> Vector3:
	return Vector3(goal_center_x + xy.x, xy.y, goal_line_z)

## Случайная зона нырка: 1 из 5 (включая CENTER).
static func random_dive_zone(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, 4)

## Репрезентативная точка зоны на линии ворот (куда целит нырок). L = -X, R = +X
## (согласовано с KeeperLogic.save_decision: dx<0 → левый нырок).
static func zone_target(zone: int, goal_center_x: float, half_width: float, low_y: float, high_y: float, lateral: float, goal_line_z: float) -> Vector3:
	var x := goal_center_x
	var y := low_y
	match zone:
		Zone.LOW_L:
			x = goal_center_x - lateral
			y = low_y
		Zone.HIGH_L:
			x = goal_center_x - lateral
			y = high_y
		Zone.LOW_R:
			x = goal_center_x + lateral
			y = low_y
		Zone.HIGH_R:
			x = goal_center_x + lateral
			y = high_y
		Zone.CENTER:
			x = goal_center_x
			y = low_y
	x = clampf(x, -half_width, half_width)
	return Vector3(x, y, goal_line_z)
```

- [ ] **Step 2: Написать падающий тест `tests/check_penalty_logic.gd`**

```gdscript
extends SceneTree
## Headless-проверка чистых функций PenaltyLogic.

func _init() -> void:
	var ok := true
	ok = _check_spread_monotonic() and ok
	ok = _check_power_monotonic() and ok
	ok = _check_disc_within_radius() and ok
	ok = _check_reticle_clamp() and ok
	ok = _check_zone_coverage() and ok
	ok = _check_zone_target_frame() and ok
	ok = _check_plane_point() and ok
	if ok:
		print("CHECK PASS: penalty_logic")
		quit(0)
	else:
		print("CHECK FAIL: penalty_logic")
		quit(1)

func _check_spread_monotonic() -> bool:
	var a := PenaltyLogic.spread_radius(0.0, 0.15, 1.6)
	var b := PenaltyLogic.spread_radius(1.0, 0.15, 1.6)
	if not (is_equal_approx(a, 0.15) and is_equal_approx(b, 1.6) and b > a):
		print("  FAIL spread_monotonic: ", a, " ", b)
		return false
	return true

func _check_power_monotonic() -> bool:
	var a := PenaltyLogic.power_speed(0.0, 18.0, 34.0)
	var b := PenaltyLogic.power_speed(1.0, 18.0, 34.0)
	if not (is_equal_approx(a, 18.0) and is_equal_approx(b, 34.0)):
		print("  FAIL power_monotonic: ", a, " ", b)
		return false
	return true

func _check_disc_within_radius() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var center := Vector2(1.0, 1.0)
	for i in range(500):
		var p := PenaltyLogic.sample_in_disc(center, 0.8, rng)
		if p.distance_to(center) > 0.8 + 0.0001:
			print("  FAIL disc_within_radius at i=", i, " d=", p.distance_to(center))
			return false
	return true

func _check_reticle_clamp() -> bool:
	# Уводим стиком далеко вправо-вверх — должно клампиться в рамку+овершут.
	var cur := Vector2.ZERO
	for i in range(200):
		cur = PenaltyLogic.move_reticle(cur, Vector2(1, 1), 6.0, 0.1, 3.66, 2.44, 0.6)
	if cur.x > 3.66 + 0.6 + 0.0001 or cur.y > 2.44 + 0.6 + 0.0001:
		print("  FAIL reticle_clamp: ", cur)
		return false
	# Вниз клампится к 0.
	for i in range(200):
		cur = PenaltyLogic.move_reticle(cur, Vector2(0, -1), 6.0, 0.1, 3.66, 2.44, 0.6)
	if cur.y < -0.0001:
		print("  FAIL reticle_clamp low: ", cur)
		return false
	return true

func _check_zone_coverage() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var seen := {}
	for i in range(500):
		seen[PenaltyLogic.random_dive_zone(rng)] = true
	for z in [PenaltyLogic.Zone.LOW_L, PenaltyLogic.Zone.HIGH_L, PenaltyLogic.Zone.LOW_R, PenaltyLogic.Zone.HIGH_R, PenaltyLogic.Zone.CENTER]:
		if not seen.has(z):
			print("  FAIL zone_coverage: не выпала зона ", z)
			return false
	return true

func _check_zone_target_frame() -> bool:
	var t := PenaltyLogic.zone_target(PenaltyLogic.Zone.HIGH_R, 0.0, 3.66, 0.4, 1.9, 2.6, -52.5)
	if absf(t.x) > 3.66 + 0.0001 or t.y != 1.9 or not is_equal_approx(t.z, -52.5):
		print("  FAIL zone_target_frame: ", t)
		return false
	# Левая зона — x отрицательный.
	var l := PenaltyLogic.zone_target(PenaltyLogic.Zone.LOW_L, 0.0, 3.66, 0.4, 1.9, 2.6, -52.5)
	if l.x >= 0.0:
		print("  FAIL zone_target_frame left: ", l)
		return false
	return true

func _check_plane_point() -> bool:
	var w := PenaltyLogic.plane_point_to_world(Vector2(1.5, 1.2), 0.0, -52.5)
	if not (is_equal_approx(w.x, 1.5) and is_equal_approx(w.y, 1.2) and is_equal_approx(w.z, -52.5)):
		print("  FAIL plane_point: ", w)
		return false
	return true
```

- [ ] **Step 3: Запустить тест — убедиться, что падает (файла логики ещё нет / опечатка)**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_penalty_logic.gd"`
Expected: FAIL или ошибка парсинга, если реализация ещё не на месте. (Если Step 1 уже создал файл — тест должен пройти; тогда временно сломай значение в одной функции, убедись в FAIL, верни назад.)

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: та же команда.
Expected: `CHECK PASS: penalty_logic`, exit 0.

- [ ] **Step 5: Коммит**

```bash
git add scripts/match/penalty_logic.gd tests/check_penalty_logic.gd
git commit -m "feat(penalty): PenaltyLogic pure functions + headless test"
```

---

## Task 2: Константы секции PENALTY

**Files:**
- Modify: `scripts/data/football_constants.gd` (добавить в конец, новая секция)

**Interfaces:**
- Produces: константы `PEN_*` (значения — тюнинг-старт; `PEN_RUNUP_DIST` и `PEN_CONTACT_TIME` будут уточнены Task 4).

- [ ] **Step 1: Добавить секцию PENALTY в конец `football_constants.gd`**

```gdscript

# ═══════════════════════════════════════════
#  PENALTY (Фаза A)
# ═══════════════════════════════════════════

# Разбег/анимация (PEN_RUNUP_DIST и PEN_CONTACT_TIME уточняются Task 4 — measure_penalty_runup.gd).
const PEN_RUNUP_DIST := 2.0            # длина разбега (root motion) — предварительно, замерить
const PEN_CONTACT_TIME := 0.9          # кадр контакта клипа penalty_kick_* (сек) — предварительно
const PEN_CLIP_LOCK := 1.3             # общая длительность клипа удара до action_finished (сек)
const PEN_DEFAULT_FOOT := "penalty_r"  # нога по умолчанию (ключ ACTION_CLIPS)

# Прицел / разброс.
const PEN_RETICLE_SPEED := 6.0         # скорость движения маркера по плоскости ворот, м/с
const PEN_RETICLE_START_Y := 1.2       # стартовая высота маркера (центр створа), м
const PEN_AIM_OVERHANG := 0.6          # овершут прицела за штангу/перекладину, м
const PEN_SPREAD_MIN_R := 0.15         # радиус круга разброса при мин. силе, м
const PEN_SPREAD_MAX_R := 1.6          # радиус круга при полной силе, м

# Сила удара.
const PEN_POWER_MIN_SPEED := 18.0      # скорость мяча при мин. заряде, м/с
const PEN_POWER_MAX_SPEED := 34.0      # при полном заряде, м/с
const PEN_CHARGE_MAX_TIME := 0.9       # макс. время заряда силы, с (чуть дольше обычного удара — прицельно)

# Черпачок.
const PEN_CHIP_PEAK_MIN := 2.5         # высота дуги черпачка при мин. заряде, м
const PEN_CHIP_PEAK_MAX := 5.0         # при полном заряде, м

# Зоны нырка вратаря (репрезентативные точки на линии).
const PEN_KEEPER_DIVE_LOW_Y := 0.4     # высота «низового» угла, м
const PEN_KEEPER_DIVE_HIGH_Y := 1.9    # высота «верхнего» угла, м
const PEN_KEEPER_DIVE_LATERAL := 2.6   # боковое смещение угла от центра, м

# Фикс-камера пенальти (за бьющим на ворота).
const PEN_CAM_BACK := 9.0              # отступ камеры назад от точки удара (от ворот), м
const PEN_CAM_HEIGHT := 4.0            # высота камеры, м
const PEN_CAM_LOOK_Y := 1.2           # высота точки, куда смотрит камера в воротах, м
```

- [ ] **Step 2: Проверить, что проект грузится (нет опечаток в константах)**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: грузится без новых ошибок парсинга.

- [ ] **Step 3: Коммит**

```bash
git add scripts/data/football_constants.gd
git commit -m "feat(penalty): PENALTY tuning constants section"
```

---

## Task 3: Сохранить разбег в glb (merge_mixamo.py) + пересборка

**Files:**
- Modify: `tools/merge_mixamo.py` (проверить/поправить `IN_PLACE_CLIPS`)
- Rebuild: `assets/models/footballer.glb`

**Interfaces:**
- Produces: в собранном glb присутствуют клипы `penalty_kick_l`, `penalty_kick_r` с СОХРАНЁННЫМ поступательным перемещением корня (не заморожены).

- [ ] **Step 1: Убедиться, что FBX на месте**

Проверить, что `assets/models/mixamo_src/penalty_kick_l.fbx` и `penalty_kick_r.fbx` лежат в `mixamo_src/` (пользователь добавил). Если нет — остановиться и запросить их.

- [ ] **Step 2: Проверить `IN_PLACE_CLIPS` в `tools/merge_mixamo.py`**

Открыть `tools/merge_mixamo.py`, найти `IN_PLACE_CLIPS`. Убедиться, что `penalty_kick_l`/`penalty_kick_r` (и старый `penalty_kick`, если есть) **НЕ** перечислены там — иначе их разбег заморозится. Если они там есть — удалить эти записи. Если словарь ключей по именам без `.fbx` — проверять по `penalty_kick_l`/`penalty_kick_r`.

- [ ] **Step 3: Пересобрать glb**

Run:
```
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python tools/merge_mixamo.py -- "C:/Users/User/Desktop/projects/OpenFootball/assets/models/mixamo_src" "C:/Users/User/Desktop/projects/OpenFootball/assets/models/footballer.glb"
```
Expected: Blender отрабатывает без ошибок, печатает список клипов, включающий `penalty_kick_l`, `penalty_kick_r`.

- [ ] **Step 4: Импорт-пасс Godot по новому glb**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import`
Expected: импорт без ошибок.

- [ ] **Step 5: Проверить наличие клипов (расширить `tests/check_footballer_glb.gd`)**

Открыть `tests/check_footballer_glb.gd`, в список ожидаемых клипов добавить `penalty_kick_l`, `penalty_kick_r`. Запустить:
Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_footballer_glb.gd"`
Expected: `CHECK PASS` со списком, содержащим оба клипа.

- [ ] **Step 6: Коммит**

```bash
git add tools/merge_mixamo.py assets/models/footballer.glb assets/models/footballer.glb.import tests/check_footballer_glb.gd
git commit -m "feat(penalty): keep run-up root motion for penalty_kick_l/_r in glb build"
```

---

## Task 4: Эмпирический замер разбега, кадра контакта и root-motion трека

**Files:**
- Create: `tools/measure_penalty_runup.gd` (headless `SceneTree`)
- Modify: `scripts/data/football_constants.gd` (обновить `PEN_RUNUP_DIST`, `PEN_CONTACT_TIME` по замеру)

**Interfaces:**
- Consumes: собранный glb (Task 3).
- Produces: реальные значения `PEN_RUNUP_DIST` и путь POSITION_3D-трека корня (печатается для Task 5), обновлённые константы.

- [ ] **Step 1: Написать `tools/measure_penalty_runup.gd`**

```gdscript
extends SceneTree
## Замер разбега (суммарный горизонтальный сдвиг корня) и печать POSITION_3D-треков клипов
## penalty_kick_l/_r из собранного footballer.glb. Root-motion ось Mixamo легко угадать неверно —
## печатаем факт, чтобы Task 5 взял верный путь трека.

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/footballer.glb")
	var root := scene.instantiate()
	var ap := _find_ap(root)
	if ap == null:
		print("CHECK FAIL: нет AnimationPlayer в glb")
		quit(1)
		return
	for clip in ["penalty_kick_l", "penalty_kick_r"]:
		if not ap.has_animation(clip):
			print("  нет клипа ", clip)
			continue
		var anim: Animation = ap.get_animation(clip)
		print("=== ", clip, " length=", anim.length)
		for ti in range(anim.get_track_count()):
			if anim.track_get_type(ti) == Animation.TYPE_POSITION_3D:
				var path := anim.track_get_path(ti)
				var k := anim.track_get_key_count(ti)
				if k < 2:
					continue
				var first: Vector3 = anim.track_get_key_value(ti, 0)
				var last: Vector3 = anim.track_get_key_value(ti, k - 1)
				var flat := Vector2(last.x - first.x, last.z - first.z).length()
				# Печатаем только заметно перемещающиеся треки (корень/бёдра).
				if flat > 0.3:
					print("  TRACK path=", path, " flat_move=", flat, " first=", first, " last=", last)
	print("CHECK DONE: скопируй flat_move корня в PEN_RUNUP_DIST, path — в Task 5")
	quit(0)

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null
```

- [ ] **Step 2: Запустить замер**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tools/measure_penalty_runup.gd"`
Expected: печатает для каждого клипа `length` и один-два POSITION_3D-трека с `flat_move` (это длина разбега) и `path` корневой кости.

- [ ] **Step 3: Обновить константы по факту**

В `football_constants.gd`:
- `PEN_RUNUP_DIST` = максимальный `flat_move` из двух клипов (берём больший — тело должно доехать до мяча; если ноги разные — можно позже развести на два, пока один общий).
- `PEN_CLIP_LOCK` = `length` клипа (округлить вверх).
- `PEN_CONTACT_TIME` = визуально момент удара; стартовое приближение = `length * 0.8` (уточняется ручной приёмкой в Task 9). Записать это значение.
Записать в комментарии рядом реальный `path` root-трека (понадобится в Task 5).

- [ ] **Step 4: Коммит**

```bash
git add tools/measure_penalty_runup.gd scripts/data/football_constants.gd
git commit -m "feat(penalty): measure run-up distance + root-motion track path"
```

---

## Task 5: PlayerVisual — регистрация клипов удара + root motion

**Files:**
- Modify: `scripts/player/player_visual.gd`

**Interfaces:**
- Consumes: root-трек path из Task 4; клипы `penalty_kick_l/_r` в glb.
- Produces:
  - `ACTION_CLIPS` содержит `"penalty_l" -> "penalty_kick_l"`, `"penalty_r" -> "penalty_kick_r"`.
  - `ACTION_TIMING` содержит записи для `"penalty_l"`/`"penalty_r"`.
  - `func consume_root_motion() -> float` — горизонтальное продвижение корня за прошедший кадр (метры), 0 если трека нет/не идёт клип с root motion.

- [ ] **Step 1: Расширить `ACTION_CLIPS` и `ACTION_TIMING`**

В `ACTION_CLIPS` (после `"penalty": "penalty_kick",`) добавить:
```gdscript
	"penalty_l": "penalty_kick_l",
	"penalty_r": "penalty_kick_r",
```
В `ACTION_TIMING` добавить (значения из констант Фазы A — но `ACTION_TIMING` в PlayerVisual не читает FootballConstants; ставим числами, синхронно с Task 4):
```gdscript
	# Пенальти с разбегом (root motion). contact/lock — из замера (Task 4). speed=1.0 (натурально).
	"penalty_l": {"contact": 0.9, "lock": 1.3, "speed": 1.0},
	"penalty_r": {"contact": 0.9, "lock": 1.3, "speed": 1.0},
```
(Если Task 4 дал другие contact/lock — поставить их.)

- [ ] **Step 2: Включить root-motion трек при сборке дерева**

В `_build_anim_tree`, после `_anim_tree.active = true` (и до `_playback.start`), добавить установку root-трека. Путь взять из Task 4 (пример ниже — заменить на реальный `path`):
```gdscript
	# Root motion для клипов удара пенальти (у прочих клипов трек корня заморожен → сдвиг ~0).
	# Путь POSITION_3D-трека корня из tools/measure_penalty_runup.gd (Task 4).
	var rm_path := _find_root_motion_path()
	if rm_path != NodePath():
		_anim_tree.root_motion_track = rm_path
	_rm_last = Vector3.ZERO
```
Добавить поле рядом с другими var:
```gdscript
var _rm_last: Vector3 = Vector3.ZERO
```
И метод поиска трека (по имени кости, устойчиво к скелету):
```gdscript
## Путь POSITION_3D-трека корневой кости (для root motion). Ищем по имени кости "hips"/root
## среди анимаций penalty_*; путь трека одинаков для всех клипов одного скелета.
func _find_root_motion_path() -> NodePath:
	if _ap == null:
		return NodePath()
	for clip in [&"penalty_kick_r", &"penalty_kick_l"]:
		if not _ap.has_animation(clip):
			continue
		var anim := _ap.get_animation(clip)
		for ti in range(anim.get_track_count()):
			if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
				continue
			var p := anim.track_get_path(ti)
			var s := String(p).to_lower()
			if s.contains("hips") or s.ends_with(":root"):
				return p
	return NodePath()
```
(Если Task 4 показал, что корень называется иначе — поправить условие `contains(...)`.)

- [ ] **Step 3: Реализовать `consume_root_motion()`**

Добавить публичный метод:
```gdscript
## Горизонтальное продвижение корня за прошедший кадр (метры). Знак игнорируем — разбег прямой,
## контроллер двигает тело вперёд (к воротам) на эту величину. 0, если трека нет/клип без root motion.
func consume_root_motion() -> float:
	if _anim_tree == null or _anim_tree.root_motion_track == NodePath():
		return 0.0
	var d: Vector3 = _anim_tree.get_root_motion_position()
	return Vector2(d.x, d.z).length()
```

- [ ] **Step 4: Тест — клипы зарегистрированы, consume не падает (headless)**

Создать проверку в существующем `tests/check_player_visual_actions.gd` (или новый минимальный скрипт) — но проще расширить `check_player_visual_actions.gd`: после инстанса визуала проверить `visual.has_action("penalty_l")` и `visual.has_action("penalty_r")` == true, и что `visual.consume_root_motion()` возвращает 0.0 в покое без падения. Добавить эти два assert в существующий тест.

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_actions.gd"`
Expected: `CHECK PASS` (включая новые assert про penalty_l/penalty_r).

- [ ] **Step 5: Коммит**

```bash
git add scripts/player/player_visual.gd tests/check_player_visual_actions.gd
git commit -m "feat(penalty): register penalty_kick_l/_r + root motion consume in PlayerVisual"
```

---

## Task 6: keeper_ai — пенальти-режим и слепой нырок

**Files:**
- Modify: `scripts/ai/keeper_ai.gd`

**Interfaces:**
- Consumes: `PenaltyLogic.Zone`, `PenaltyLogic.zone_target`; существующие `_begin_save`, `_begin_central_catch`, `_begin_miss_top`, `_should_catch_high`, `_catch_radius_hit`, `_heading_at_goal`.
- Produces:
  - `func set_penalty_mode(on: bool) -> void`
  - `func begin_penalty_dive(zone: int) -> void`

- [ ] **Step 1: Добавить поля и методы пенальти-режима**

В начало `keeper_ai.gd` (рядом с другими var) добавить:
```gdscript
var _penalty_mode: bool = false
var _pen_struck: bool = false
```
Добавить методы (например, после `_physics_process` или рядом с `_begin_save`):
```gdscript
## Пенальти-подрежим: держим центр линии, лицом в поле, боковой РЕАКТИВНЫЙ сейв ВЫКЛ. Рефлекс
## центрального мяча (ловля/промах по высоте прилёта) остаётся — им решается центральный удар,
## если вратарь остался в центре.
func set_penalty_mode(on: bool) -> void:
	_penalty_mode = on
	if on:
		_pen_struck = false
		_reacting = false
		_state = State.POSITION
		var m := _motor()
		if m != null:
			m.set_control_locked(false)
		var vis := _visual()
		if vis != null:
			vis.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)

## Слепой нырок пенальти по выбранной зоне. Угловые — существующий _begin_save (клип/контакт/отбой
## как с игры); CENTER — остаёмся в центре, центральный рефлекс в _penalty_hold решит по высоте.
func begin_penalty_dive(zone: int) -> void:
	_pen_struck = true
	if zone == PenaltyLogic.Zone.CENTER:
		return  # остаёмся по центру; исход решит рефлекс, затем авто-сброс _penalty_mode
	_penalty_mode = false
	var action := _pen_zone_to_action(zone)
	if action == KeeperLogic.SaveAction.NONE:
		return
	var target := PenaltyLogic.zone_target(zone, 0.0, FootballConstants.GOAL_WIDTH * 0.5,
		FootballConstants.PEN_KEEPER_DIVE_LOW_Y, FootballConstants.PEN_KEEPER_DIVE_HIGH_Y,
		FootballConstants.PEN_KEEPER_DIVE_LATERAL, goal_line_z)
	# Слепой нырок — реальной ttoi нет (INF): _begin_save держит нырок по длине клипа.
	_begin_save({"action": action, "target": target}, ball.linear_velocity.length(), INF)

func _pen_zone_to_action(zone: int) -> int:
	match zone:
		PenaltyLogic.Zone.LOW_L:
			return KeeperLogic.SaveAction.DIVE_LOW_L
		PenaltyLogic.Zone.LOW_R:
			return KeeperLogic.SaveAction.DIVE_LOW_R
		PenaltyLogic.Zone.HIGH_L:
			return KeeperLogic.SaveAction.DIVE_HIGH_L
		PenaltyLogic.Zone.HIGH_R:
			return KeeperLogic.SaveAction.DIVE_HIGH_R
	return KeeperLogic.SaveAction.NONE
```

- [ ] **Step 2: Ветка пенальти в начале `_position`**

В `_position`, сразу после `if m == null: return`, вставить:
```gdscript
	if _penalty_mode:
		_penalty_hold(delta, m)
		return
```
И добавить метод:
```gdscript
## Держим центр линии лицом в поле; боковой реактивный сейв не запускаем. Рефлекс центрального
## мяча решает ловлю/промах по высоте прилёта (как в обычном _position). После удара, когда угроза
## миновала (пойман/за линией/улетел), авто-снимаем пенальти-режим → обычная игра.
func _penalty_hold(delta: float, m: PlayerMotor) -> void:
	var into := -1.0 if goal_line_z > 0.0 else 1.0
	m.set_face_direction(Vector3(ball.global_position.x - global_position.x, 0.0, into * 4.0))
	var to := Vector3(-global_position.x, 0.0, 0.0)  # к центру створа (x=0)
	if to.length() > 0.15:
		m.set_move_intent(to.normalized(), 1.0)
	else:
		m.set_move_intent(Vector3.ZERO)
	# Рефлекс центрального мяча: по высоте прилёта — scoop/catch/catch_head/catch_top / miss_top.
	if ball.is_flight() and _heading_at_goal() and _catch_radius_hit():
		var by := ball.global_position.y
		if _should_catch_high(by):
			ball.catch(self, hold_point)
			_begin_central_catch(by)
		else:
			_begin_miss_top()
		return
	# Авто-сброс режима после удара, когда мяч уже не угроза.
	if _pen_struck:
		var crossed := (ball.global_position.z - goal_line_z) * into < 0.0
		if ball.is_caught() or crossed or (ball.is_flight() and not _heading_at_goal()):
			_penalty_mode = false
```

- [ ] **Step 3: Валидация match-сцены (headless) — нет новых ошибок парсинга/рантайма**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: набор ошибок совпадает по КАТЕГОРИЯМ с baseline из CLAUDE.md (дубль-регистрация ACTION_CLIPS, `!is_inside_tree()`, `WorldEnvironment3D`) — без новых по `keeper_ai`/`PenaltyLogic`.

- [ ] **Step 4: Коммит**

```bash
git add scripts/ai/keeper_ai.gd
git commit -m "feat(penalty): keeper penalty mode + blind dive by zone"
```

---

## Task 7: match_manager — флаг режима, ввод P, гейты, инстанс контроллера

**Files:**
- Modify: `scripts/match/match_manager.gd`

**Interfaces:**
- Consumes: `PenaltyController` (Task 8) — вызываем `_penalty.start_single(...)` и `_penalty.update(delta)`.
- Produces:
  - `var _penalty_active: bool`
  - `func is_penalty_active() -> bool`
  - action `penalty_debug` (клавиша P)
  - гейты: ввод игрока, полевой ИИ, следящая камера — отключены при `_penalty_active`; фикс-камера пенальти.

- [ ] **Step 1: Поля + геттер**

Рядом с `_celebrating`:
```gdscript
var _penalty_active: bool = false
var _penalty  # PenaltyController
var _penalty_cam_pose: Transform3D = Transform3D.IDENTITY
```
Добавить метод рядом с `is_celebrating()`:
```gdscript
func is_penalty_active() -> bool:
	return _penalty_active
```

- [ ] **Step 2: Action `penalty_debug` (P) в `_setup_inputs`**

В словарь `actions` добавить строку:
```gdscript
		&"penalty_debug":   {"keys": [KEY_P], "buttons": [], "axes": []},
```

- [ ] **Step 3: Инстанс контроллера в `_ready`**

В конец `_ready` (после `_setup_ball_trail()`):
```gdscript
	_penalty = preload("res://scripts/match/penalty_controller.gd").new()
	_penalty.name = "PenaltyController"
	add_child(_penalty)
	_penalty.setup(self, ball, camera_pivot, power_bar, _keeper)
```

- [ ] **Step 4: Делегация в `_physics_process` + старт по P**

В самое начало `_physics_process(delta)` (до `_try_fire_queue`):
```gdscript
	if _penalty_active:
		_penalty.update(delta)
		return
	if Input.is_action_just_pressed(&"penalty_debug"):
		_penalty.start_single(controlled_player, _keeper.goal_line_z)
		return
```

- [ ] **Step 5: Гейт камеры в `_process`**

В `_process`, заменить блок камеры от 3-го лица так, чтобы при `_penalty_active` использовалась фикс-поза от контроллера:
```gdscript
	if _penalty_active:
		camera_pivot.global_transform = _penalty_cam_pose
	else:
		var cam_target: Node3D = controlled_player if (controlled_player and is_instance_valid(controlled_player)) else null
		if cam_target != null:
			... (существующий блок расчёта eye/look_at без изменений) ...
```
Добавить сеттер, которым контроллер задаёт позу:
```gdscript
func set_penalty_cam_pose(pose: Transform3D) -> void:
	_penalty_cam_pose = pose
```
И сеттер флага (контроллер включает/выключает режим):
```gdscript
func set_penalty_active(on: bool) -> void:
	_penalty_active = on
```

- [ ] **Step 6: Гейт полевого ИИ (idle на время пенальти)**

Добавить хелпер, которым контроллер глушит/возвращает полевой ИИ (вратарь НЕ трогаем — он должен нырять):
```gdscript
func set_field_ai_active(on: bool) -> void:
	for p in [player_away, player_teammate]:
		if p != null and is_instance_valid(p):
			p.set_physics_process(on)
```

- [ ] **Step 7: Валидация — проект и match-сцена грузятся**

Run (оба):
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: первая — чисто; вторая — baseline-категории ошибок (контроллер ещё не написан → `preload` в `_ready` может ошибиться, если файла нет; поэтому Task 8 идёт следом и валидируется вместе). Если файла контроллера ещё нет — временно закомментировать блок Step 3/4 до Task 8, затем вернуть. (Проще: сделать Task 8 до финальной валидации Task 7 — они парные.)

- [ ] **Step 8: Коммит**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(penalty): match_manager penalty flag, P trigger, camera/AI gates"
```

---

## Task 8: PenaltyController — автомат, прицел-кольцо, страйк

**Files:**
- Create: `scripts/match/penalty_controller.gd`

**Interfaces:**
- Consumes: `PenaltyLogic`, `ShotSystem.ballistic_to`, `PassSystem.launch_lob`, `PlayerVisual` (`trigger`, `consume_root_motion`, `action_contact`), `PlayerMotor.find_on`, keeper (`set_penalty_mode`, `begin_penalty_dive`), match_manager (`set_penalty_active`, `set_penalty_cam_pose`, `set_field_ai_active`).
- Produces:
  - `signal struck`
  - `func setup(manager, ball, camera_pivot, power_bar, keeper) -> void`
  - `func start_single(kicker: CharacterBody3D, goal_line_z: float) -> void`
  - `func update(delta: float) -> void`
  - `var release_after_strike: bool = true`

- [ ] **Step 1: Написать `scripts/match/penalty_controller.gd`**

```gdscript
extends Node
## Базовый контроллер ОДНОГО пенальти (Фаза A). Автомат SETUP→AIM→STRIKE; на ударе испускает
## `struck` и при release_after_strike отдаёт мяч в обычную игру. Математика — PenaltyLogic.

signal struck

enum Phase { IDLE, SETUP, AIM, STRIKE }

var release_after_strike: bool = true

var _manager: Node
var _ball: RigidBody3D
var _camera_pivot: Node3D
var _power_bar: ProgressBar
var _keeper: CharacterBody3D

var _phase: int = Phase.IDLE
var _kicker: CharacterBody3D
var _goal_line_z: float = 0.0
var _into: float = 1.0
var _spot: Vector3 = Vector3.ZERO

var _aim: Vector2 = Vector2.ZERO            # точка прицела на плоскости ворот (x от центра, y высота)
var _charge: float = 0.0
var _charging: bool = false
var _chip: bool = false
var _reticle_visible: bool = true          # future: скрыть для честной игры за вратаря (Фаза B)

var _pen_rng := RandomNumberGenerator.new()
var _reticle: MeshInstance3D
var _contact_connected := false
var _struck_zone: int = -1

func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar, keeper: CharacterBody3D) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar
	_keeper = keeper
	_pen_rng.randomize()
	_build_reticle()

## Старт одиночного пенальти в атакуемые ворота (goal_line_z вратаря).
func start_single(kicker: CharacterBody3D, goal_line_z: float) -> void:
	if _phase != Phase.IDLE:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -1.0 if goal_line_z > 0.0 else 1.0
	release_after_strike = true
	_setup()

func _setup() -> void:
	_phase = Phase.SETUP
	_manager.set_penalty_active(true)
	_manager.set_field_ai_active(false)
	# Мяч на 11-метровую отметку.
	_spot = Vector3(0.0, FootballConstants.BALL_RADIUS, _goal_line_z + _into * FootballConstants.PENALTY_SPOT_DIST)
	if _ball.has_method(&"release_dribble"):
		_ball.release_dribble()
	if _ball.has_method(&"clear_last_kicker"):
		_ball.clear_last_kicker()
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = _spot
	# Бьющий за мячом по длине разбега, лицом к воротам; в обычном idle.
	var to_goal := Vector3(0.0, 0.0, _into)
	_kicker.global_position = Vector3(0.0, 0.5, _spot.z - _into * FootballConstants.PEN_RUNUP_DIST)
	_kicker.look_at(_kicker.global_position + to_goal, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(false)
		km.set_move_intent(Vector3.ZERO)
	# Вратарь: пенальти-режим (центр, idle, реактивный сейв off).
	if _keeper != null and _keeper.has_method(&"set_penalty_mode"):
		_keeper.set_penalty_mode(true)
	# Прицел в центр створа.
	_aim = Vector2(0.0, FootballConstants.PEN_RETICLE_START_Y)
	_charge = 0.0
	_charging = false
	_chip = false
	_struck_zone = -1
	_update_camera_pose()
	_phase = Phase.AIM

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_aim_update(delta)
		Phase.STRIKE:
			_strike_update(delta)
	_update_reticle()

func _aim_update(delta: float) -> void:
	# Прицел стиком/стрелками (тот же move_*, но берём вектор напрямую).
	var stick := Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_forward", &"move_back"))  # forward = -Y стика; вверх по воротам = +высота
	# move_forward отрицательный по Y → «вверх» стика поднимает прицел: инвертируем Y.
	var aim_stick := Vector2(stick.x, -stick.y)
	_aim = PenaltyLogic.move_reticle(_aim, aim_stick, FootballConstants.PEN_RETICLE_SPEED, delta,
		FootballConstants.GOAL_WIDTH * 0.5, FootballConstants.GOAL_HEIGHT, FootballConstants.PEN_AIM_OVERHANG)
	# Черпачок — combo_modifier + kick (LB+X / Q+D).
	var want_chip := Input.is_action_pressed(&"combo_modifier")
	# Заряд силы: удержание kick.
	if Input.is_action_just_pressed(&"kick"):
		_charging = true
		_charge = 0.0
		_chip = want_chip
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

func _fire(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	var from: Vector3 = _ball.global_position
	# Итоговая точка = прицел + случай внутри круга разброса.
	var spread := PenaltyLogic.spread_radius(ratio, FootballConstants.PEN_SPREAD_MIN_R, FootballConstants.PEN_SPREAD_MAX_R)
	var sampled := PenaltyLogic.sample_in_disc(_aim, spread, _pen_rng)
	var target := PenaltyLogic.plane_point_to_world(sampled, 0.0, _goal_line_z)
	var g := _ball_gravity()
	var launch_vel: Vector3
	if _chip:
		var peak := lerpf(FootballConstants.PEN_CHIP_PEAK_MIN, FootballConstants.PEN_CHIP_PEAK_MAX, ratio)
		launch_vel = PassSystem.launch_lob(from, target, peak, g)
	else:
		var speed := PenaltyLogic.power_speed(ratio, FootballConstants.PEN_POWER_MIN_SPEED, FootballConstants.PEN_POWER_MAX_SPEED)
		launch_vel = ShotSystem.ballistic_to(from, target, speed, g)
	_pending_launch = launch_vel
	# Зона вратаря выбирается вслепую заранее, коммитим на контакте.
	_struck_zone = PenaltyLogic.random_dive_zone(_pen_rng)
	# Запускаем клип удара (root motion) и ждём action_contact.
	var vis := _kicker_visual()
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)  # телом на разбеге владеет root motion (мотор не мешает)
	_phase = Phase.STRIKE
	if vis != null and not _contact_connected:
		vis.action_contact.connect(_on_kicker_contact, CONNECT_ONE_SHOT)
		_contact_connected = true
	if vis == null or not vis.trigger(FootballConstants.PEN_DEFAULT_FOOT):
		_on_kicker_contact("penalty")  # фолбэк без анимации — бьём сразу

var _pending_launch: Vector3 = Vector3.ZERO

func _strike_update(_delta: float) -> void:
	# Root-motion разбег: двигаем тело бьющего вперёд (к воротам) на продвижение корня за кадр.
	var vis := _kicker_visual()
	if vis == null:
		return
	var advance := vis.consume_root_motion()
	if advance > 0.0:
		var fwd := -_kicker.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() > 0.01:
			_kicker.global_position += fwd.normalized() * advance
			_kicker.global_position.y = 0.5

func _on_kicker_contact(_action: String) -> void:
	_contact_connected = false
	# Импульс мяча.
	if _ball.has_method(&"launch"):
		_ball.launch(_pending_launch, false)
	# Вратарь ныряет вслепую.
	if _keeper != null and _keeper.has_method(&"begin_penalty_dive"):
		_keeper.begin_penalty_dive(_struck_zone)
	struck.emit()
	if release_after_strike:
		_release()

## Отдать управление в обычную игру: снять пенальти-режим, вернуть камеру/ИИ, разлочить бьющего.
func _release() -> void:
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(false)
	_manager.set_field_ai_active(true)
	_manager.set_penalty_active(false)
	_phase = Phase.IDLE

func _update_camera_pose() -> void:
	# Фикс-камера за бьущим на ворота.
	var back := _spot.z - _into * FootballConstants.PEN_CAM_BACK
	var eye := Vector3(0.0, FootballConstants.PEN_CAM_HEIGHT, back)
	var look := Vector3(0.0, FootballConstants.PEN_CAM_LOOK_Y, _goal_line_z)
	var t := Transform3D.IDENTITY
	t.origin = eye
	t = t.looking_at(look, Vector3.UP)
	_manager.set_penalty_cam_pose(t)

func _build_reticle() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.28
	mesh.outer_radius = 0.35
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.1)  # жёлтое кольцо
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mesh.material = mat
	_reticle = MeshInstance3D.new()
	_reticle.name = "PenaltyReticle"
	_reticle.mesh = mesh
	_reticle.rotation.x = deg_to_rad(90)  # тор лежит в плоскости ворот (лицом к камере/полю)
	_reticle.visible = false
	add_child(_reticle)

func _update_reticle() -> void:
	if _reticle == null:
		return
	var show := _phase == Phase.AIM and _reticle_visible
	_reticle.visible = show
	if not show:
		return
	_reticle.global_position = PenaltyLogic.plane_point_to_world(_aim, 0.0, _goal_line_z)
	# Радиус кольца = радиус разброса при текущем заряде (масштаб тора по базовому 0.35).
	var ratio := clampf(_charge / FootballConstants.PEN_CHARGE_MAX_TIME, 0.0, 1.0) if _charging else 0.0
	var r := PenaltyLogic.spread_radius(ratio, FootballConstants.PEN_SPREAD_MIN_R, FootballConstants.PEN_SPREAD_MAX_R)
	var s := maxf(0.3, r / 0.35)
	_reticle.scale = Vector3(s, 1.0, s)

func _kicker_visual() -> PlayerVisual:
	if _kicker == null:
		return null
	for c in _kicker.get_children():
		if c is PlayerVisual:
			return c
	return null

func _ball_gravity() -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return g * _ball.gravity_scale
```

> **Примечание для исполнителя:** `looking_at` на `Transform3D` строит ориентацию из `t.origin` на точку `look`. `_pending_launch` объявлен полем внутри скрипта (см. `var _pending_launch` в теле) — при наборе держать одно объявление, не дублировать.

- [ ] **Step 2: Проверить чистую загрузку проекта и match-сцены**

Run (оба):
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: обе грузятся; ошибки только baseline-категорий из CLAUDE.md, без новых по `penalty_controller`.

- [ ] **Step 3: Коммит**

```bash
git add scripts/match/penalty_controller.gd
git commit -m "feat(penalty): PenaltyController state machine + reticle + strike"
```

---

## Task 9: Ручная приёмка «фила» и тюнинг

**Files:**
- Modify (по итогам): `scripts/data/football_constants.gd`, `scripts/player/player_visual.gd` (`ACTION_TIMING` penalty), `scripts/match/penalty_controller.gd`

**Interfaces:**
- Consumes: всё выше.

- [ ] **Step 1: Запустить игру, проверить чек-лист**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball"` (или F5 из редактора). Нажать **P**. Проверить по пунктам:
  1. Мяч встаёт на 11-метровую точку; бьющий за мячом в **idle**; вратарь по центру в **keeper_idle**; камера фикс. за бьющим — видно игрока, мяч и ворота.
  2. Стик/стрелки двигают **жёлтое кольцо** по створу (можно чуть за штангу/перекладину).
  3. Удержание удара (D / X) копит `power_bar`, кольцо **растёт**; отпускание/полный заряд — удар.
  4. Разбег root-motion: бьющий добегает до мяча, стопа встречает мяч на контакте (нет «проезда сквозь мяч» и нет зависания в воздухе).
  5. Вратарь прыгает в случайную сторону (лево/право низ/верх или центр) теми же клипами, что с игры.
  6. Возможен промах (кольцо у штанги + большой круг → мимо/над).
  7. Гол → празднование сетки → мяч в центр поля, обычный ввод возвращается; сейв/промах → мяч живой, игра продолжается.
  8. Черпачок (Q+D / LB+X) — навесной удар с тем же прицелом/зарядом.

- [ ] **Step 2: Тюнинг по наблюдениям**

- Если бьющий проезжает мимо/не доезжает — поправить `PEN_RUNUP_DIST` (Task 4 значение) и/или проверить знак `consume_root_motion` (если тело едет назад — разбег в клипе отрицательный по оси; тогда в `consume_root_motion` вернуть со знаком и в контроллере двигать по знаку).
- Если удар происходит раньше/позже контакта ноги — поправить `contact` в `ACTION_TIMING["penalty_r"]`/`["penalty_l"]` и `PEN_CONTACT_TIME`.
- Разброс/сила/зоны нырка/камера — правкой соответствующих `PEN_*`.

- [ ] **Step 3: Повторный прогон обеих headless-валидаций**

Run (оба):
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: baseline-категории, без новых ошибок.

- [ ] **Step 4: Коммит тюнинга**

```bash
git add -A
git commit -m "tune(penalty): run-up/contact/spread/camera after playtest"
```

---

## Task 10: Документация (CLAUDE.md / AGENTS.md)

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`

- [ ] **Step 1: Добавить раздел «Penalty (Phase A)» в CLAUDE.md**

Кратко описать: `PenaltyController` (базовый, один пенальти, `struck`/`release_after_strike`), `PenaltyLogic` (чистая математика), пенальти-режим вратаря (`set_penalty_mode`/`begin_penalty_dive`, CENTER = рефлекс по высоте), root-motion разбег (`penalty_kick_l/_r` не в `IN_PLACE_CLIPS`, `consume_root_motion`), фикс-камера в `match_manager` (`_penalty_active`), кнопка P (`penalty_debug`), новые `PEN_*` константы, тест `check_penalty_logic.gd`. Отметить Фазы B/C как будущие (шов `release_after_strike`, `_reticle_visible`).

- [ ] **Step 2: Синхронизировать AGENTS.md (краткая строка про пенальти)**

- [ ] **Step 3: Коммит**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "docs(penalty): document Phase A penalty in CLAUDE.md/AGENTS.md"
```

---

## Self-Review (проверка плана против спека)

**Покрытие спека Фазы A:**
- Автомат SETUP→AIM→STRIKE + release-at-strike — Task 8. ✓
- Свободный прицел + разброс от силы + семпл в круге — Task 1 (математика) + Task 8 (HUD/страйк). ✓
- Жёлтое кольцо world-space в плоскости ворот — Task 8 (`_build_reticle` TorusMesh, rotation.x=90). ✓
- Root-motion `penalty_kick_l/_r` (не морозить, применять к телу, замер разбега) — Tasks 3, 4, 5, 8. ✓
- Выбор ноги (`PEN_DEFAULT_FOOT`) — Task 2/5/8. ✓
- Idle-стойка бьющего + keeper_idle вратаря — Task 8 (`_setup`) + Task 6 (`set_penalty_mode`). ✓
- Слепой нырок 5 зон + CENTER=рефлекс по высоте + `resolve_save`/`KEEPER_SAVE_ERROR` — Task 6. ✓
- Фикс-камера как гейт в match_manager — Task 7 + Task 8 (`_update_camera_pose`). ✓
- Ввод: прицел move_*, заряд kick, черпачок combo+kick, триггер P — Task 7 (P) + Task 8. ✓
- Гейты обычных систем (ввод/ИИ/камера) — Task 7. ✓
- Исход обычными системами (гол→центр, сейв/промах→в игре) — release-at-strike (Task 8) + существующий `GoalArea`/`_reset_ball`. ✓
- Константы PENALTY — Task 2. ✓
- Тесты: `check_penalty_logic.gd`, замер разбега, headless-валидация — Tasks 1, 4, 6/8/9. ✓
- `_reticle_visible` флаг (future toggle) — Task 8. ✓

**Вне рамок (по спеку, не в плане):** кручёный на пенальти; классификация/RESOLVE/таймаут (только серия); смена бьющего по ходу (шов ноги/клипа заложен); Фазы B/C. ✓

**Согласованность типов:** `zone: int` из `PenaltyLogic.Zone` — единый во всех задачах; `begin_penalty_dive(zone)`, `random_dive_zone`, `zone_target` совпадают по сигнатурам; `consume_root_motion() -> float` — единый контракт Task 5↔Task 8; `set_penalty_active/set_penalty_cam_pose/set_field_ai_active` — единые Task 7↔Task 8.

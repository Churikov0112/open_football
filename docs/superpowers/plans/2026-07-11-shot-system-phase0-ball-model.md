# Фаза 0: миграция модели мяча (OpenSoccer) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Перевести мяч на модель OpenSoccer — всегда физически сталкивается с игроками, дриблинг импульсный, есть стейт-машина полёта с Magnus-кручением и хук блока — не сломав дриблинг, подкат, пасы и авто-переключение.

**Architecture:** `ball_controller.gd` получает `enum BallState { OPEN, TRAPPED, FLIGHT, CAUGHT }` и поле `_curl`. Публичный API владения (`set_dribbler`/`release_dribble`/`dribbler`) сохраняется как тонкие обёртки над стейт-машиной, чтобы `match_manager`/AI почти не менялись. Дриблинг остаётся самоуправляемым в `_integrate_forces` (мяч сам тянется за владельцем), но математика меняется с жёсткого присваивания скорости на импульсное подталкивание. Столкновение мяча с игроками включается **постоянно** через маску мяча (асимметрично: игрок ходит свободно). Magnus и хук блока живут в `_integrate_forces`/`_on_ball_collision`.

**Tech Stack:** Godot 4.7, GDScript. Тесты — headless `SceneTree`-скрипты в `tests/` (паттерн `check_*.gd`), плюс две команды валидации из CLAUDE.md.

## Global Constraints

- Godot 4.7 / GDScript. Windows-only.
- **InputMap правится только в `match_manager.gd:_setup_inputs()`**, никогда в `project.godot` (Фаза 0 ввод не трогает).
- **Нельзя ломать текущие детекты:** `GoalArea`/`TackleArea` завязаны на `body == ball` и на том, что мяч на **слое 1** — мяч остаётся на слое 1, меняется только его `collision_mask`.
- Команды валидации (обе, ловят разное):
  - `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
  - `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
- Baseline ошибок второй команды (диффать против него, не ждать нуля): ~33× `Condition "!is_inside_tree()" is true`, ~6× transition-duplicate, ~3× `states.has(p_name)`, ~1× `WorldEnvironment3D`.
- Headless-check запускается: `& "<godot exe>" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/<name>.gd"`, печатает `CHECK PASS`/`CHECK FAIL`, exit 0/1.
- **Ощущение дриблинга/удара headless не ловит** — после Задач 3, 4, 5, 6 обязателен ручной прогон игры пользователем (отмечено в шагах как «ручная приёмка»).
- Коммитить часто (после каждой задачи).

## Отклонения от спека (осознанные, для снижения риска)

1. **Без `TrapArea`-нод.** Существующий дистанционный подбор в `_handle_dribbling()` эквивалентен трап-зоне; добавляем лишь гейт по скорости мяча (быстрый летящий мяч не трапится). Меньше нод/проводки.
2. **Дриблинг самоуправляемый** (мяч тянется за владельцем в `_integrate_forces`), без публичного `dribble(dir, speed)`, который звали бы владельцы каждый кадр. Меньше связок в AI/вводе.
3. **Публичный API владения не переименовывается** — `set_dribbler`/`release_dribble`/`dribbler` остаются как обёртки над `state`/`player`. Ноль правок в `simple_ai.gd`/`teammate_ai.gd`.

Если пользователь хочет буквальные `TrapArea`/`dribble()` — это отдельная последующая задача, поведение от этого не меняется.

## File Structure

- **Modify:** `scripts/ball/ball_controller.gd` — стейт-машина, импульсный дриблинг, Magnus, `launch_curl()`, блок остаётся в `match_manager`.
- **Modify:** `scripts/match/match_manager.gd` — гейт скорости в `_handle_dribbling()`, маска/флаги мяча в `_setup_ball()`, блок в `_on_ball_collision()`.
- **Modify:** `scripts/data/football_constants.gd` — новые константы модели мяча.
- **Create:** `tests/check_ball_state.gd` — headless-проверка переходов стейт-машины и `launch_curl()`.
- **Не трогаем:** `simple_ai.gd`, `teammate_ai.gd` (работают через сохранённый API `dribbler`).

---

## Task 1: Стейт-машина мяча + API владения (без смены поведения)

Вводим `BallState`, `state`, `_curl`, `player`, сохраняя текущий velocity-matching в `TRAPPED`. Игра играется идентично; появляется наблюдаемое состояние для тестов и последующих задач.

**Files:**
- Modify: `scripts/ball/ball_controller.gd` (шапка переменных 1–17; `set_dribbler` 60–67; `release_dribble` 70–74; `kick` 109–113; `launch` 119–123)
- Create: `tests/check_ball_state.gd`

**Interfaces:**
- Produces:
  - `enum BallState { OPEN, TRAPPED, FLIGHT, CAUGHT }`
  - `var state: BallState` (начально `OPEN`)
  - `var _curl: Vector3` (начально `Vector3.ZERO`)
  - `func player() -> Node3D` — текущий владелец (== `dribbler`)
  - Сохранённые: `set_dribbler(node)` → `state=TRAPPED`; `release_dribble()` → `state=OPEN`; `kick(dir,power)`/`launch(vel)` → `state=FLIGHT`.

- [ ] **Step 1: Написать падающий тест переходов состояния**

Create `tests/check_ball_state.gd`:

```gdscript
extends SceneTree

# Headless-проверка стейт-машины мяча: переходы OPEN/TRAPPED/FLIGHT и launch_curl().
# Не проверяет физику/ощущение — только наблюдаемое состояние API.

func _init() -> void:
	var ok := true
	var ball := RigidBody3D.new()
	ball.set_script(load("res://scripts/ball/ball_controller.gd"))
	get_root().add_child(ball)

	var stub := Node3D.new()
	get_root().add_child(stub)

	# Старт — OPEN.
	ok = ok and _expect(ball.state == ball.BallState.OPEN, "начальное состояние OPEN")

	# set_dribbler → TRAPPED, player == stub.
	ball.set_dribbler(stub)
	ok = ok and _expect(ball.state == ball.BallState.TRAPPED, "set_dribbler → TRAPPED")
	ok = ok and _expect(ball.player() == stub, "player() == владелец")
	ok = ok and _expect(ball.dribbler == stub, "dribbler-обёртка == владелец")

	# release_dribble → OPEN, player == null.
	ball.release_dribble()
	ok = ok and _expect(ball.state == ball.BallState.OPEN, "release_dribble → OPEN")
	ok = ok and _expect(ball.player() == null, "player() == null после release")

	# kick → FLIGHT.
	ball.set_dribbler(stub)
	ball.kick(Vector3.FORWARD, 15.0)
	ok = ok and _expect(ball.state == ball.BallState.FLIGHT, "kick → FLIGHT")

	if ok:
		print("CHECK PASS")
		quit(0)
	else:
		print("CHECK FAIL")
		quit(1)

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ball_state.gd"`
Expected: `CHECK FAIL` (нет `BallState`/`state`/`player()`), либо ошибка парсинга обращения к `ball.state`.

- [ ] **Step 3: Добавить стейт-машину в `ball_controller.gd`**

В шапке (после строки `extends RigidBody3D` и существующих `@export`), добавить перечисление и поля:

```gdscript
enum BallState { OPEN, TRAPPED, FLIGHT, CAUGHT }
var state: BallState = BallState.OPEN
var _curl: Vector3 = Vector3.ZERO
```

`set_dribbler` — в конце функции (после `_dribbler_prev_pos = ...`) выставить состояние:

```gdscript
func set_dribbler(node: Node3D) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_release_time < _release_cooldown_msec:
		return
	if node and node == last_kicker and now - _last_kick_time < _kick_cooldown_msec:
		return
	dribbler = node
	_dribbler_prev_pos = node.global_position if node else Vector3.ZERO
	state = BallState.TRAPPED if node else BallState.OPEN
```

`release_dribble`:

```gdscript
func release_dribble() -> void:
	if dribbler:
		dribbler = null
		_last_release_time = Time.get_ticks_msec()
	_dribbler_prev_pos = Vector3.ZERO
	state = BallState.OPEN
```

`kick` и `launch` — после `release_dribble()` добавить `state = BallState.FLIGHT`:

```gdscript
func kick(direction: Vector3, power: float) -> void:
	last_kicker = dribbler
	_last_kick_time = Time.get_ticks_msec()
	release_dribble()
	state = BallState.FLIGHT
	_pending_impulse = direction * power


func launch(velocity: Vector3) -> void:
	last_kicker = dribbler
	_last_kick_time = Time.get_ticks_msec()
	release_dribble()
	state = BallState.FLIGHT
	_pending_impulse = velocity * mass
```

Добавить геттер владельца (рядом с `get_dribble_direction`):

```gdscript
## Текущий владелец мяча (нейтральное имя поверх legacy-поля dribbler).
func player() -> Node3D:
	return dribbler
```

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ball_state.gd"`
Expected: `CHECK PASS`.

- [ ] **Step 5: Регресс — обе команды валидации**

Run обе команды из Global Constraints. Expected: первая — без новых ошибок; вторая — совпадает с baseline (никаких новых категорий).

- [ ] **Step 6: Commit**

```bash
git add scripts/ball/ball_controller.gd tests/check_ball_state.gd
git commit -m "feat(ball): add BallState machine + player() over legacy dribbler API"
```

---

## Task 2: Гейт скорости при подборе мяча

Летящий (быстрый) мяч больше нельзя трапнуть — только медленный. Это подготовка к всегда-столкновению: иначе игрок на пути прострела мгновенно «съедал» бы летящий мяч.

**Files:**
- Modify: `scripts/data/football_constants.gd` (секция BALL)
- Modify: `scripts/match/match_manager.gd:_handle_dribbling()` (660–685)

**Interfaces:**
- Consumes: `ball.state`, `ball.linear_velocity` (из Task 1)
- Produces: `FootballConstants.BALL_TRAP_MAX_SPEED: float`

- [ ] **Step 1: Добавить константу порога трапа**

В `scripts/data/football_constants.gd`, в секцию `BALL` (после `const PASS_Y_UP := 0.1`):

```gdscript
const BALL_TRAP_MAX_SPEED := 9.0   # быстрее этого (м/с) мяч не подбирается — он «в полёте»
```

- [ ] **Step 2: Гейтить подбор по скорости**

В `_handle_dribbling()` заменить тело (строки 660–685) так, чтобы подбор (обе ветки — `_receiver` и общая) выполнялся только для достаточно медленного мяча. Заменить блок целиком:

```gdscript
func _handle_dribbling() -> void:
	if not ball.has_method(&"release_dribble"):
		return
	if ball.dribbler:
		var dist: float = ball.dribbler.global_position.distance_to(ball.global_position)
		if dist > 3.0:
			ball.release_dribble()
		return
	# Быстрый (летящий) мяч не подбираем — он «в полёте», ждём пока замедлится/отскочит.
	if ball.linear_velocity.length() > FootballConstants.BALL_TRAP_MAX_SPEED:
		return
	# Пас летит на _receiver — расширенный радиус подбора именно для него.
	if _receive_active and is_instance_valid(_receiver):
		var recv_dist: float = _receiver.global_position.distance_to(ball.global_position)
		if recv_dist < FootballConstants.PASS_RECEIVE_CATCH_RADIUS:
			ball.set_dribbler(_receiver)
			if _receiver.has_method(&"end_receiving"):
				_receiver.end_receiving()
			return
	for p in [player_home, player_teammate, player_away]:
		if not p or not is_instance_valid(p):
			continue
		var dist: float = p.global_position.distance_to(ball.global_position)
		if dist < 1.0:
			ball.set_dribbler(p)
			if p.has_method(&"end_receiving"):
				p.end_receiving()
			return
```

- [ ] **Step 3: Регресс — обе команды валидации + check_ball_state**

Run обе команды валидации и `check_ball_state.gd`. Expected: baseline без новых ошибок; `CHECK PASS`.

- [ ] **Step 4: Ручная приёмка**

Запустить игру (без `--headless`). Ожидание: дриблинг/подбор медленного мяча — как раньше; сильный удар/пас, пролетающий рядом с игроком, НЕ подхватывается мгновенно, пока не замедлится. (Столкновение ещё выключено — мяч пролетает сквозь, это норм для этой задачи.)

- [ ] **Step 5: Commit**

```bash
git add scripts/data/football_constants.gd scripts/match/match_manager.gd
git commit -m "feat(ball): gate ball pickup by speed (fast ball is in-flight, not trappable)"
```

---

## Task 3: Импульсный дриблинг (замена velocity-matching)

Сердце модели OpenSoccer. Ветка `TRAPPED` в `_integrate_forces` перестаёт жёстко присваивать скорость и переходит на импульсное подталкивание к точке впереди владельца. Ощущение станет менее «прилипчивым» — главный тюнинг-проход.

**Files:**
- Modify: `scripts/data/football_constants.gd` (секция DRIBBLING)
- Modify: `scripts/ball/ball_controller.gd:_integrate_forces()` (126–167)

**Interfaces:**
- Consumes: `state == BallState.TRAPPED`, `dribbler`, `_direction_from_delta()` (существует), `FootballConstants`
- Produces: `FootballConstants.DRIBBLE_IMPULSE_GAIN: float`, `FootballConstants.DRIBBLE_MAX_IMPULSE: float`

- [ ] **Step 1: Добавить константы импульсного дриблинга**

В `scripts/data/football_constants.gd`, секция `DRIBBLING` (после `const DRIBBLE_HEIGHT := 0.08`):

```gdscript
const DRIBBLE_IMPULSE_GAIN := 18.0   # сила притяжения мяча к точке впереди владельца (импульс/сек)
const DRIBBLE_MAX_IMPULSE := 14.0    # кламп импульса дриблинга, м/с
```

- [ ] **Step 2: Переписать ветку TRAPPED в `_integrate_forces`**

Заменить функцию `_integrate_forces` (126–167). Ветка владельца теперь импульсная (гасит боковую составляющую и толкает к цели), ветки «нет владельца» и применение `_pending_impulse` сохраняются:

```gdscript
func _integrate_forces(state_body: PhysicsDirectBodyState3D) -> void:
	var vel := state_body.linear_velocity

	if state == BallState.TRAPPED and dribbler and is_instance_valid(dribbler):
		var player_pos := dribbler.global_position
		var dt := state_body.step

		var pos_delta := player_pos - _dribbler_prev_pos
		_dribbler_prev_pos = player_pos
		pos_delta.y = 0.0

		var move_dir := _direction_from_delta(pos_delta)
		var target := player_pos \
			+ move_dir * dribble_forward_distance \
			+ Vector3.UP * dribble_height

		# Импульсное подталкивание к точке впереди владельца (не жёсткое присваивание).
		var to_target := target - state_body.transform.origin
		to_target.y = 0.0
		var impulse := to_target * FootballConstants.DRIBBLE_IMPULSE_GAIN
		impulse = impulse.limit_length(FootballConstants.DRIBBLE_MAX_IMPULSE)
		# Гасим текущую горизонтальную скорость и заменяем её импульсом к цели +
		# базовой скоростью владельца (чтобы мяч ехал вместе с бегущим игроком).
		var player_vel := Vector3.ZERO
		if pos_delta.length_squared() > 0.0001 and dt > 0:
			player_vel = (pos_delta / dt).limit_length(15.0)
		vel.x = player_vel.x + impulse.x
		vel.z = player_vel.z + impulse.z
		vel.y *= air_resistance
	else:
		vel.x *= drag_factor
		vel.z *= drag_factor
		vel.y *= air_resistance

	if _pending_impulse.length_squared() > 0:
		vel += _pending_impulse / mass
		_pending_impulse = Vector3.ZERO

	state_body.linear_velocity = vel
```

(`state` переименован в параметре на `state_body`, чтобы не затенять поле `state`.)

- [ ] **Step 3: Регресс — обе команды + check_ball_state**

Run. Expected: baseline без новых ошибок; `CHECK PASS`.

- [ ] **Step 4: Ручная приёмка (тюнинг ощущения)**

Запустить игру. Ожидание: игрок ведёт мяч; мяч держится впереди, но допускается лёгкая «живость». Если мяч отлетает/отстаёт — подкрутить `DRIBBLE_IMPULSE_GAIN` (выше = прилипчивее) и `DRIBBLE_MAX_IMPULSE`. Зафиксировать ощущаемо-приемлемые значения.

- [ ] **Step 5: Commit**

```bash
git add scripts/data/football_constants.gd scripts/ball/ball_controller.gd
git commit -m "feat(ball): impulse-based trap dribbling (replace velocity-matching)"
```

---

## Task 4: Всегда-столкновение мяча с игроками + continuous_cd + физматериал

Мяч начинает физически сталкиваться с капсулами игроков (асимметрично — игрок не сдвигается). `continuous_cd` защищает быстрые удары от туннелирования.

**Files:**
- Modify: `scripts/ball/ball_controller.gd:_ready()` (20–24)
- Modify: `scripts/match/match_manager.gd:_setup_ball()` (308–314)

**Interfaces:**
- Consumes: `FootballConstants.PLAYER_COLLISION_MASK`, `FootballConstants.BOUNDARY_COLLISION_LAYER`
- Produces: мяч с `collision_mask` включающей слой игроков; `continuous_cd = true`.

- [ ] **Step 1: Включить continuous_cd и настроить физматериал в `_ready`**

В `ball_controller.gd:_ready()` (заменить целиком):

```gdscript
func _ready() -> void:
	_football_texture()
	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = 0.4
	phys_mat.bounce = 0.35
	physics_material_override = phys_mat
	continuous_cd = true
	max_contacts_reported = 2
	contact_monitor = true
```

- [ ] **Step 2: Добавить слой игроков в маску мяча в `_setup_ball`**

В `match_manager.gd:_setup_ball()` заменить строку маски (313):

```gdscript
	# Мяч на слое 1 (гол/подкат-детект), но теперь сталкивается и с питчем (1), и с
	# границами, и с ИГРОКАМИ (bit2) — асимметрично: маску игроков не трогаем, они
	# ходят свободно, а мяч (RigidBody) отскакивает от их капсул.
	ball.collision_mask = 1 | FootballConstants.BOUNDARY_COLLISION_LAYER | FootballConstants.PLAYER_COLLISION_MASK
```

- [ ] **Step 3: Регресс — обе команды + check_ball_state**

Run. Expected: baseline без новых ошибок; `CHECK PASS`.

- [ ] **Step 4: Ручная приёмка**

Запустить игру. Ожидание: (1) дриблинг по-прежнему рабочий (мяч у ног не расталкивает владельца — если трапнутый мяч дёргается о собственную капсулу, поднять `dribble_forward_distance` или ужать капсулу — зафиксировать); (2) сильный удар в стоящего игрока — мяч **отскакивает**, а не пролетает сквозь; (3) спавн матча не расшвыривает мяч и игроков.

- [ ] **Step 5: Commit**

```bash
git add scripts/ball/ball_controller.gd scripts/match/match_manager.gd
git commit -m "feat(ball): always-on ball-vs-player collision + continuous_cd + physmat tune"
```

---

## Task 5: Magnus-кручение + `launch_curl()` + завершение полёта

Мяч в состоянии `FLIGHT` с ненулевым `_curl` подкручивается каждый кадр (боковой+подъёмный импульс с затуханием). Когда мяч замедляется — полёт завершается (`OPEN`), кручение обнуляется. API `launch_curl()` готов для Фазы 1 (кручёный удар).

**Files:**
- Modify: `scripts/data/football_constants.gd` (новая секция SHOOTING — только Magnus-часть)
- Modify: `scripts/ball/ball_controller.gd` (`launch` рядом; `_integrate_forces`; новый `launch_curl`)
- Modify: `tests/check_ball_state.gd` (добавить проверку `launch_curl`)

**Interfaces:**
- Consumes: `state == BallState.FLIGHT`, `_curl`, `FootballConstants`
- Produces:
  - `func launch_curl(velocity: Vector3, curl: Vector3) -> void` — `state=FLIGHT`, задаёт `_curl`, импульс `velocity*mass`.
  - `FootballConstants.MAGNUS_FORCE := 50.0`, `FootballConstants.MAGNUS_DECAY := 0.99`, `FootballConstants.FLIGHT_END_SPEED := 6.0`.

- [ ] **Step 1: Дополнить тест — `launch_curl` задаёт FLIGHT и `_curl`**

В `tests/check_ball_state.gd`, перед блоком `if ok:` добавить:

```gdscript
	# launch_curl → FLIGHT, _curl задан.
	ball.release_dribble()
	ball.launch_curl(Vector3(0, 0, -20), Vector3(0, 0, 3))
	ok = ok and _expect(ball.state == ball.BallState.FLIGHT, "launch_curl → FLIGHT")
	ok = ok and _expect(ball._curl.length() > 0.01, "launch_curl задаёт _curl")
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `... -s "res://tests/check_ball_state.gd"`
Expected: `CHECK FAIL` (нет метода `launch_curl`) либо ошибка парсинга.

- [ ] **Step 3: Добавить константы Magnus**

В `scripts/data/football_constants.gd` — новая секция в конце файла:

```gdscript
# ═══════════════════════════════════════════
#  SHOOTING — модель мяча (Magnus, завершение полёта)
# ═══════════════════════════════════════════

const MAGNUS_FORCE := 50.0        # масштаб бокового/подъёмного импульса кручения в полёте
const MAGNUS_DECAY := 0.99        # затухание _curl за физкадр
const FLIGHT_END_SPEED := 6.0     # ниже этой скорости (м/с) полёт завершается → OPEN
```

- [ ] **Step 4: Добавить `launch_curl` и Magnus в `_integrate_forces`**

Добавить метод рядом с `launch`:

```gdscript
## Запуск с кручением: как launch(), но задаёт _curl (Magnus в _integrate_forces).
## curl — вектор в мировых осях: .z как боковая составляющая (через local-left), .y — подъём.
func launch_curl(velocity: Vector3, curl: Vector3) -> void:
	last_kicker = dribbler
	_last_kick_time = Time.get_ticks_msec()
	release_dribble()
	state = BallState.FLIGHT
	_curl = curl
	_pending_impulse = velocity * mass
```

Важно: `kick()` и `launch()` должны обнулять `_curl` (прямой/низовой удар не крутится). В обе функции добавить `_curl = Vector3.ZERO` после `state = BallState.FLIGHT`.

В `_integrate_forces`, внутри ветки `else` (мяч без владельца), в НАЧАЛЕ ветки добавить обработку полёта — Magnus и завершение. Заменить ветку `else`:

```gdscript
	else:
		if state == BallState.FLIGHT:
			# Magnus: боковой (через left = vel×UP) + подъёмный импульс, с затуханием.
			var horiz := Vector3(vel.x, 0.0, vel.z)
			if _curl.length_squared() > 0.0001 and horiz.length() > 0.5:
				var left := horiz.normalized().cross(Vector3.UP)
				var dt := state_body.step
				vel += (left * _curl.z + Vector3.UP * _curl.y) * dt * FootballConstants.MAGNUS_FORCE
				_curl *= FootballConstants.MAGNUS_DECAY
			# Полёт завершён, когда мяч замедлился — снова подбираемый, кручение сброшено.
			if vel.length() < FootballConstants.FLIGHT_END_SPEED:
				state = BallState.OPEN
				_curl = Vector3.ZERO
		vel.x *= drag_factor
		vel.z *= drag_factor
		vel.y *= air_resistance
```

- [ ] **Step 5: Запустить тест — убедиться, что проходит**

Run: `... -s "res://tests/check_ball_state.gd"`
Expected: `CHECK PASS`.

- [ ] **Step 6: Регресс — обе команды валидации**

Run обе. Expected: baseline без новых ошибок.

- [ ] **Step 7: Ручная приёмка (диагностика кручения — временная)**

Кручёный удар появится в Фазе 1, но физику можно проверить временно: убедиться, что обычный удар (`kick`) летит **прямо** (не крутит — `_curl` обнулён). Полноценную дугу проверим в Фазе 1. Ожидание: прямой удар без бокового ухода; мяч, замедлившись, снова подбирается (переходит в `OPEN`).

- [ ] **Step 8: Commit**

```bash
git add scripts/data/football_constants.gd scripts/ball/ball_controller.gd tests/check_ball_state.gd
git commit -m "feat(ball): Magnus curl in flight + launch_curl() + flight-end to OPEN"
```

---

## Task 6: Хук блока мяча в полёте

Пока мяч в `FLIGHT`, физический контакт с игроком гасит скорость, сбрасывает кручение и переводит мяч в `OPEN` (дальше — обычная борьба за подбор). Хук под вратарский сейв — комментарием на будущее.

**Files:**
- Modify: `scripts/match/match_manager.gd:_on_ball_collision()` (1446–1447 — сейчас тело `pass`)

**Interfaces:**
- Consumes: `ball.state`, `ball.linear_velocity`, `ball.BallState.FLIGHT`, группы `team_1`/`team_2`
- Produces: реакция блока (гашение + `state=OPEN`).

- [ ] **Step 1: Заменить пустое тело `_on_ball_collision`**

Обработчик сейчас (1446–1447):

```gdscript
func _on_ball_collision(body: Node) -> void:
	pass
```

Заменить целиком на ветку блока:

```gdscript
func _on_ball_collision(body: Node) -> void:
	# Блок в полёте: контакт летящего мяча с игроком гасит и роняет мяч в OPEN.
	# (Хук под вратарский сейв — отдельная SaveArea в будущем; пока обычный блок.)
	if ball.state == ball.BallState.FLIGHT and body is CharacterBody3D \
			and (body.is_in_group("team_1") or body.is_in_group("team_2")):
		ball.linear_velocity *= 0.25
		ball._curl = Vector3.ZERO
		ball.state = ball.BallState.OPEN
```

- [ ] **Step 2: Регресс — обе команды + check_ball_state**

Run. Expected: baseline без новых ошибок; `CHECK PASS`.

- [ ] **Step 3: Ручная приёмка**

Запустить игру. Ожидание: удар в стоящего соперника/партнёра — мяч резко гасится и падает рядом (становится подбираемым), а не отскакивает как мячик от стены. Дриблинг/пасы не задеты.

- [ ] **Step 4: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(ball): in-flight block hook (dampen + drop ball to OPEN on player contact)"
```

---

## Self-Review (выполнено автором)

**Spec coverage (S3 «Фаза 0» спека):**
- Стейт-машина `BallState` — Task 1. ✓
- Удаление velocity-matching → импульсный дриблинг — Task 3. ✓
- Всегда-столкновение (маска мяча += игроки, асимметрия), `continuous_cd`, физматериал — Task 4. ✓
- Magnus (`_curl`, затухание), `launch_curl` — Task 5. ✓
- Владение через `state`/`player` — Task 1 (через сохранённый API + геттер `player()`). ✓
- Блок/сейв-хук (`FLIGHT`+игрок → гашение, `OPEN`, без передачи владения) — Task 6. ✓
- `TackleArea`/`GoalArea` не сломаны (мяч на слое 1) — Global Constraints + Task 4. ✓
- Гейт «медленный мяч трапится» — Task 2. ✓
- Риск-лист (ощущение, спавн, перехват) — ручные приёмки Task 3/4 + гейт Task 2. ✓

**Отклонения:** `TrapArea`/`dribble()`/переименование API опущены осознанно (раздел «Отклонения»), поведение эквивалентно.

**Placeholder scan:** явных TODO/«обработать ошибки»/«аналогично Task N» нет — весь код приведён.

**Type consistency:** `BallState`, `state`, `_curl`, `player()`, `launch_curl(velocity, curl)`, `set_dribbler`, `release_dribble` — имена согласованы между задачами и тестом. Параметр `_integrate_forces` переименован в `state_body`, чтобы не затенять поле `state` (учтено в Task 3 и Task 5).

**Открытый момент для ручной приёмки:** значения `DRIBBLE_IMPULSE_GAIN`/`DRIBBLE_MAX_IMPULSE` (Task 3) и `bounce`/`friction` (Task 4) — тюнинг-старт, финализируются пользователем живьём.

# Фаза 2: очередь действий «в одно касание» (удары и пасы) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать возможность заряжать удар/пас, когда мяч ещё НЕ у ног управляемого игрока (летит пасом ИЛИ убежал вперёд в спринт-дриблинге), и бить «в одно касание» в момент, когда игрок дотягивается до мяча — прицел по facing в момент касания, сила = заряд + скорость влетающего мяча.

**Architecture:** Новое состояние очереди в `match_manager.gd` (`_queued_action`/`_queue_player`/`_queue_ratio`/`_queue_timer`) поверх существующего заряда (`_charge_*`). Активируется вводом, когда мяч «наш, но не у ног». Срабатывает в `_physics_process`, когда игрок в радиусе `QUEUE_REACH_RADIUS` от мяча: диспатчит тот же `_fire_shot`/`_fire_pass`, но с явным `facing_override` (игрок ещё не дриблер) и поднятым по скорости мяча `charge_ratio`. Единственная чистая функция — `ShotSystem.one_touch_ratio` (тестируется headless). Авто-подбегание переиспользует уже существующие пути (receive-assist для паса, dribble-chase для своего отрыва).

**Tech Stack:** Godot 4.7 / GDScript. Тесты — headless `SceneTree` (`tests/check_shot_system_math.gd`), плюс две команды валидации.

## Global Constraints

- Godot 4.7 / GDScript. Windows-only.
- **InputMap правится только в `match_manager.gd:_setup_inputs()`** — но в этой фазе НОВЫХ действий ввода не добавляем (используем уже существующие `kick`/`pass_short`/`pass_through`/`pass_lob` + combo).
- **`ShotSystem` не читает `FootballConstants`** — все тюнинги параметрами (как в Фазе 1). Тест сидит RNG.
- **Целевые ворота / половина поля — через `_target_goal_center()` / `_attack_dir_z`** (гибко, half-time-свап). Уже готово в Фазе 1.
- **Диспатч удара/паса — существующие `_fire_shot`/`_fire_pass`** (commit-action, импульс по `action_contact`). Не дублируем логику удара/паса.
- Команды валидации (обе):
  - `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
  - `& "...console.exe" --path "..." --headless --quit-after 2 res://scenes/match.tscn`
- Baseline ошибок 2-й команды (диффать, не ждать нуля): 4 категории — ~41× `!is_inside_tree()`, ~22× transition-duplicate, ~11× `states.has`, ~1× `WorldEnvironmentND`. Headless-check: `... --headless -s "res://tests/<name>.gd"` → `CHECK PASS`/`FAIL`, exit 0/1. После добавления нового `class_name`/скрипта — прогнать `--headless --import`, иначе глобальный класс не зарегистрируется.
- **Ощущение (тайминг очереди, сила от скорости, авто-подбегание) headless НЕ ловит** — после Задач 4/5/6 обязателен ручной прогон пользователем. Стенки болванок и стоящий соперник (`DEBUG_DISABLE_OPPONENT`) уже на поле для теста.

## Зависимости (уже готово)

- Заряд: `_charge_action`/`_charge_time`/`_charge_player`, `_is_charging()`, `_start_charge(action, player)`, `_cancel_charge()`, `_fire_charge()`. Накопление и `power_bar` — в `_process` (гейт `_charge_player == controlled_player`).
- Диспатч: `_fire_shot(action, player, charge_ratio)` и `_fire_pass(action, player, charge_ratio)`; оба читают `ball.get_dribble_direction()` (facing) и `ball.global_position` (from), затем commit-action (`_action_player`/`_action_power`/`_kick_action_active`/`_pending_launch`/`_pending_curl`, импульс по `_on_action_contact`).
- `ChargeAction { NONE, SHOT, SHOT_CURL, SHOT_CHIP, CLEARANCE, PASS_SHORT, PASS_THROUGH, PASS_LOB, PASS_WALL, PASS_THROUGH_AIR }` — combo уже закодирован в значении action (отдельный `_queue_combo` НЕ нужен).
- Владение при отрыве: в спринт-дриблинге `ball.dribbler` остаётся = игрок (владение не теряется до `DRIBBLE_KEEP_DIST=15`), `ball.should_chase()` = true, мяч free-rolls впереди. `ball.player() == controlled_player` истинно всю фазу отрыва.
- Receive-assist: `_receive_active`/`_receiver`/`_receive_timer`, подведение ввода к мячу в `_handle_player_input` (строки ~825-829). Трап получателя — `_handle_dribbling` (радиус `PASS_RECEIVE_CATCH_RADIUS`).
- Стопгэп «мяч за спиной» в `_on_action_contact` (строки ~1251-1259) — гасит удар, если мяч сзади. Для очереди мяч на касании у ног/впереди → гейт проходит; стопгэп оставляем (его снятие для has-ball кейса — вне охвата этой фазы).

## File Structure

- **Modify:** `scripts/match/shot_system.gd` — добавить `one_touch_ratio` (чистая функция).
- **Modify:** `tests/check_shot_system_math.gd` — тест `one_touch_ratio`.
- **Modify:** `scripts/data/football_constants.gd` — секция QUEUE (`QUEUE_BALL_SPEED_GAIN`, `QUEUE_MAX_TIME`, `QUEUE_REACH_RADIUS`).
- **Modify:** `scripts/match/match_manager.gd` — поля очереди; `_can_queue`/`_start_queue_charge`/`_stop_queue_fix_ratio`/`_clear_queue`/`_try_fire_queue`; ввод (press → очередь, release/max → фиксация ratio); диспатч по касанию в `_physics_process`; `facing_override` в `_fire_shot`/`_fire_pass`; UI power_bar вне владения.

---

## Task 1: `ShotSystem.one_touch_ratio` — сила в одно касание (чистая функция + тест)

Сила удара/паса в одно касание = базовый заряд + вклад скорости влетающего мяча, клампится в 0..1 (эффективный `charge_ratio`, который дальше лерпит силу в `_fire_shot`/`_fire_pass`).

**Files:**
- Modify: `scripts/match/shot_system.gd`
- Modify: `tests/check_shot_system_math.gd`

**Interfaces:**
- Produces (static, `class_name ShotSystem`):
  - `one_touch_ratio(base_ratio: float, incoming_speed: float, gain: float) -> float`

- [ ] **Step 1: Написать тест в `tests/check_shot_system_math.gd`**

Добавить перед финальным `if ok:`:

```gdscript
	# one_touch_ratio: база + вклад скорости, кламп в 0..1.
	ok = _expect(absf(ShotSystem.one_touch_ratio(0.2, 0.0, 0.02) - 0.2) < 0.001, "нет скорости → ratio = база") and ok
	ok = _expect(absf(ShotSystem.one_touch_ratio(0.2, 20.0, 0.02) - 0.6) < 0.001, "скорость 20 при gain 0.02 → +0.4") and ok
	ok = _expect(ShotSystem.one_touch_ratio(0.5, 100.0, 0.02) == 1.0, "быстрый мяч → кламп до 1.0") and ok
	ok = _expect(ShotSystem.one_touch_ratio(-0.5, 0.0, 0.02) == 0.0, "кламп снизу до 0.0") and ok
```

- [ ] **Step 2: Прогнать тест — убедиться, что падает**

Run: `& "...console.exe" --path "..." --headless -s "res://tests/check_shot_system_math.gd"`
Expected: `CHECK FAIL` (функции ещё нет — parse error про `one_touch_ratio`).

- [ ] **Step 3: Написать функцию в `scripts/match/shot_system.gd`**

Добавить после `scatter_meters` (в конце файла):

```gdscript

## Эффективная сила удара/паса «в одно касание»: базовый заряд + вклад скорости влетающего
## мяча (быстрый пас/прострел замыкается мощно даже при коротком удержании; «мёртвый» мяч
## требует полного заряда). Результат — charge_ratio в 0..1 для _fire_shot/_fire_pass.
static func one_touch_ratio(base_ratio: float, incoming_speed: float, gain: float) -> float:
	return clampf(base_ratio + gain * maxf(incoming_speed, 0.0), 0.0, 1.0)
```

- [ ] **Step 4: Import + прогнать тест — PASS**

Run: `& "...console.exe" --path "..." --headless --import` затем `... --headless -s "res://tests/check_shot_system_math.gd"`
Expected: `CHECK PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/shot_system.gd scripts/match/shot_system.gd.uid tests/check_shot_system_math.gd
git commit -m "feat(shot): ShotSystem.one_touch_ratio (charge + incoming-ball speed) + test"
```

---

## Task 2: Константы очереди + поля состояния + `_clear_queue()` + отмена

Каркас очереди: поля, единая очистка, автоотмена каждый физкадр. Пока ничего не активирует и не стреляет — только состояние и уборка.

**Files:**
- Modify: `scripts/data/football_constants.gd`
- Modify: `scripts/match/match_manager.gd`

**Interfaces:**
- Produces: поля `_queued_action: ChargeAction`, `_queue_player: CharacterBody3D`, `_queue_ratio: float`, `_queue_timer: float`; `_is_queued() -> bool`; `_clear_queue() -> void`; константы `QUEUE_BALL_SPEED_GAIN`, `QUEUE_MAX_TIME`, `QUEUE_REACH_RADIUS`.

- [ ] **Step 1: Константы (`football_constants.gd`)**

После секции PASSING (в конце файла или рядом с receive-константами) добавить:

```gdscript

# ═══════════════════════════════════════════
#  ACTION QUEUE (Фаза 2 — удар/пас «в одно касание»)
# ═══════════════════════════════════════════
const QUEUE_BALL_SPEED_GAIN := 0.02   # прибавка к charge_ratio за 1 м/с скорости влетающего мяча
const QUEUE_MAX_TIME := 2.5           # сколько (с) отложенное действие ждёт касания до автоотмены
const QUEUE_REACH_RADIUS := 2.0       # игрок в этом радиусе (м) от мяча → «дотянулся» → бьём в одно касание
const QUEUE_CONSIDER_RADIUS := 8.0    # ничейный/летящий мяч в этом радиусе (м) → можно ставить в очередь (борьба)
```

- [ ] **Step 2: Поля состояния (`match_manager.gd`)**

После полей receive-assist (`_receive_timer`, ~строка 76) добавить:

```gdscript

# Очередь действия «в одно касание»: заряжаем удар/пас, пока мяч ещё не у ног (летит пасом
# или убежал вперёд в спринт-дриблинге), бьём в момент, когда игрок дотянулся до мяча.
var _queued_action: ChargeAction = ChargeAction.NONE
var _queue_player: CharacterBody3D
var _queue_ratio: float = 0.0
var _queue_timer: float = 0.0
```

- [ ] **Step 3: `_is_queued()` и `_clear_queue()`**

Рядом с `_is_charging()` (~строка 78) добавить:

```gdscript
func _is_queued() -> bool:
	return _queued_action != ChargeAction.NONE
```

Рядом с `_cancel_charge()` (~строка 1047) добавить:

```gdscript
## Сбросить очередь «в одно касание» (перехват/аут/таймаут/смена игрока/падение).
func _clear_queue() -> void:
	_queued_action = ChargeAction.NONE
	_queue_player = null
	_queue_ratio = 0.0
	_queue_timer = 0.0
```

- [ ] **Step 4: Автоотмена в `_physics_process`**

В `_physics_process`, после блока receive-assist (`if _receive_active:` … ~строка 668-673) добавить. Ключ отмены — **«мяч забрал кто-то другой»** (`ball.dribbler` не null и не наш `_queue_player`: соперник ИЛИ партнёр перехватил/подобрал первым) → удар НЕ выполняем:

```gdscript
	# Очередь «в одно касание»: тикаем таймаут и сбрасываем по невалидности/смене/потере мяча.
	# taken_by_other = мяч успел забрать кто-то другой (соперник ИЛИ партнёр) → мы НЕ добрались
	# первыми → отменяем удар (пользовательское правило спорного мяча).
	if _is_queued():
		_queue_timer -= delta
		var taken_by_other: bool = ball.has_method(&"set_dribbler") and ball.dribbler != null and ball.dribbler != _queue_player
		if _queue_timer <= 0.0 \
				or _queue_player != controlled_player or not is_instance_valid(_queue_player) \
				or _queue_player.is_in_group("fallen") \
				or taken_by_other:
			_clear_queue()
```

- [ ] **Step 5: Сброс очереди при падении игрока**

В `_finish_fall()` (там же, где чистится `giving_run` — grep `giving_run` в `match_manager.gd`) добавить страховку: если упал `_queue_player` — `_clear_queue()`. Найти тело `_finish_fall` и добавить в конце:

```gdscript
	if _queue_player == body:
		_clear_queue()
```

- [ ] **Step 6: Регресс — обе команды**

Expected: baseline (поля/функции добавлены, ничего не активируется — поведение прежнее).

- [ ] **Step 7: Commit**

```bash
git add scripts/data/football_constants.gd scripts/match/match_manager.gd
git commit -m "feat(shot): action-queue state + constants + clear/cancel scaffolding"
```

---

## Task 3: `facing_override` в `_fire_shot` / `_fire_pass`

В одно касание игрок ещё НЕ дриблер, поэтому `ball.get_dribble_direction()` вернёт `Vector3.FORWARD` (заглушка), а не его реальный facing. Даём диспатчу принимать явный facing (facing тела игрока в момент касания). При `Vector3.ZERO` — прежнее поведение (читаем из мяча).

**Files:**
- Modify: `scripts/match/match_manager.gd` — сигнатуры `_fire_shot`/`_fire_pass` и чтение facing внутри.

**Interfaces:**
- Consumes: —
- Produces: `_fire_shot(action, player, charge_ratio, facing_override := Vector3.ZERO)`; `_fire_pass(action, player, charge_ratio, facing_override := Vector3.ZERO)`.

- [ ] **Step 1: `_fire_shot` — параметр и facing**

Заменить сигнатуру и строку чтения facing в `_fire_shot` (~строка 966, 973):

```gdscript
func _fire_shot(action: ChargeAction, player: CharacterBody3D, charge_ratio: float, facing_override: Vector3 = Vector3.ZERO) -> void:
```

и строку `var facing: Vector3 = ball.get_dribble_direction()` заменить на:

```gdscript
	var facing: Vector3 = facing_override if facing_override.length_squared() > 0.0001 else ball.get_dribble_direction()
```

- [ ] **Step 2: `_fire_pass` — параметр и facing**

В `_fire_pass` (~строка 1135) заменить сигнатуру:

```gdscript
func _fire_pass(action: ChargeAction, player: CharacterBody3D, charge_ratio: float, facing_override: Vector3 = Vector3.ZERO) -> void:
```

Найти внутри `_fire_pass` строку `var aim: Vector3 = ball.get_dribble_direction()` (используется для `PassSystem.select_target`) и заменить на:

```gdscript
	var aim: Vector3 = facing_override if facing_override.length_squared() > 0.0001 else ball.get_dribble_direction()
```

- [ ] **Step 3: Регресс — обе команды**

Expected: baseline (все существующие вызовы без 4-го аргумента → `facing_override = ZERO` → прежнее поведение).

- [ ] **Step 4: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(shot): optional facing_override in _fire_shot/_fire_pass (for one-touch, non-dribbler)"
```

---

## Task 4: Активация очереди по вводу (пас летит ИЛИ свой отрыв) + фиксация ratio

Нажатие удара/паса, когда мяч «наш, но не у ног», ставит действие в очередь и запускает заряд. Отпустил (или дошёл до макс.) до касания — фиксируем ratio, ждём касания.

**Files:**
- Modify: `scripts/match/match_manager.gd` — `_can_queue`, `_start_queue_charge`, `_stop_queue_fix_ratio`; ввод в `_handle_player_input`; авто-фикс в `_process`.

**Interfaces:**
- Consumes: `_is_near_ball`, `_is_our_dribbler`, `_receive_active`/`_receiver`, `_start_charge`, `_cancel_charge`, `_is_charging`, `_queue_*`.
- Produces: `_can_queue(player) -> bool`; `_start_queue_charge(action, player)`; `_stop_queue_fix_ratio()`.

- [ ] **Step 1: `_can_queue` — «мяч наш, но не у ног»**

Рядом с `_is_our_dribbler` (~строка 928) добавить:

```gdscript
## Можно ли поставить действие в очередь: мяч НЕ у ног (иначе обычный немедленный заряд) и им
## не владеет кто-то ДРУГОЙ (тогда это территория подката/смены). Источники очереди:
##  - incoming: летит к нам пасом нашей команды (receive-assist),
##  - breakaway: мы дриблер, но мяч убежал вперёд (спринт-отрыв, владение не потеряно),
##  - loose: мяч бесхозный/летящий (dribbler == null) и в разумной близости — СПОРНЫЙ мяч
##    (борьба с соперником). Заряжать можно; удар выполнится, только если добежим первыми
##    (см. отмену taken_by_other и «ближе всех» в _try_fire_queue).
func _can_queue(player_node: CharacterBody3D) -> bool:
	if player_node == null or not is_instance_valid(player_node):
		return false
	if _is_near_ball(player_node):
		return false  # у ног — обычный путь (немедленный заряд), не очередь
	if ball.has_method(&"set_dribbler") and ball.dribbler != null and ball.dribbler != player_node:
		return false  # мячом владеет кто-то другой (соперник/партнёр) → подкат/смена, не очередь
	var incoming: bool = _receive_active and _receiver == player_node
	var breakaway: bool = _is_our_dribbler(player_node)  # дриблер, но не near (проверено выше)
	var loose: bool = (not ball.has_method(&"set_dribbler") or ball.dribbler == null) \
		and player_node.global_position.distance_to(ball.global_position) <= FootballConstants.QUEUE_CONSIDER_RADIUS
	return incoming or breakaway or loose
```

- [ ] **Step 2: `_start_queue_charge` и `_stop_queue_fix_ratio`**

Рядом с `_start_charge` (~строка 939) добавить:

```gdscript
## Начать заряд «в очередь» (мяч ещё не у ног). Копим силу как обычно (power_bar виден),
## но по касанию будем бить в одно касание, а не сразу. Тело НЕ доворачиваем к мячу
## (get_dribble_direction для не-дриблера бессмыслен — прицел возьмём по facing на касании).
func _start_queue_charge(action: ChargeAction, player_node: CharacterBody3D) -> void:
	_charge_action = action
	_charge_time = 0.0
	_charge_player = player_node
	_queued_action = action
	_queue_player = player_node
	_queue_ratio = 0.0
	_queue_timer = FootballConstants.QUEUE_MAX_TIME

## Отпустили кнопку (или дошли до макс.) ДО касания: фиксируем текущий ratio в очереди и
## гасим активный заряд (шкалу), но очередь остаётся ждать касания.
func _stop_queue_fix_ratio() -> void:
	var is_shot: bool = _queued_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]
	var max_time := KICK_CHARGE_MAX_TIME if is_shot else FootballConstants.PASS_CHARGE_MAX_TIME
	_queue_ratio = clampf(_charge_time / max_time, 0.0, 1.0)
	_cancel_charge()
```

- [ ] **Step 3: Ввод удара — ветка очереди**

В `_handle_player_input`, в блоке `if Input.is_action_just_pressed(&"kick"):` (~строка 890) добавить ветку `elif _can_queue(...)` ПЕРЕД `else: _try_tackle`:

```gdscript
	if Input.is_action_just_pressed(&"kick"):
		if _is_charging() or _is_queued():
			pass  # уже заряжаем/в очереди, игнор
		elif _is_near_ball(controlled_player) and _is_our_dribbler(controlled_player):
			var shot_action := ChargeAction.SHOT
			if Input.is_action_pressed(&"combo_curl"):
				shot_action = ChargeAction.SHOT_CURL
			elif Input.is_action_pressed(&"combo_modifier"):
				shot_action = ChargeAction.SHOT_CHIP
			_start_charge(shot_action, controlled_player)
		elif _can_queue(controlled_player):
			var q_action := ChargeAction.SHOT
			if Input.is_action_pressed(&"combo_curl"):
				q_action = ChargeAction.SHOT_CURL
			elif Input.is_action_pressed(&"combo_modifier"):
				q_action = ChargeAction.SHOT_CHIP
			_start_queue_charge(q_action, controlled_player)
		else:
			_try_tackle(controlled_player)
```

- [ ] **Step 4: Отпускание удара — фикс ratio для очереди**

Заменить блок релиза удара (~строка 904):

```gdscript
	if Input.is_action_just_released(&"kick") and _charge_player == controlled_player \
			and _charge_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]:
		if _is_queued():
			_stop_queue_fix_ratio()  # мяч ещё не у ног — фиксируем силу, ждём касания
		else:
			_fire_charge()
```

- [ ] **Step 5: Ввод паса — ветка очереди + фикс ratio**

Заменить блок пасов (~строки 908-920). Логика combo та же, но добавляем ветку очереди, когда мяч не у ног:

```gdscript
	# Пасы: одна кнопка на семейство; combo_modifier в атаке выбирает «спец»-вариант.
	var combo := Input.is_action_pressed(&"combo_modifier")
	if _is_near_ball(controlled_player) and _is_our_dribbler(controlled_player):
		if Input.is_action_just_pressed(&"pass_short"):
			_start_charge(ChargeAction.PASS_WALL if combo else ChargeAction.PASS_SHORT, controlled_player)
		elif Input.is_action_just_pressed(&"pass_through"):
			_start_charge(ChargeAction.PASS_THROUGH_AIR if combo else ChargeAction.PASS_THROUGH, controlled_player)
		elif Input.is_action_just_pressed(&"pass_lob"):
			_start_charge(ChargeAction.PASS_LOB, controlled_player)
	elif not _is_charging() and not _is_queued() and _can_queue(controlled_player):
		if Input.is_action_just_pressed(&"pass_short"):
			_start_queue_charge(ChargeAction.PASS_WALL if combo else ChargeAction.PASS_SHORT, controlled_player)
		elif Input.is_action_just_pressed(&"pass_through"):
			_start_queue_charge(ChargeAction.PASS_THROUGH_AIR if combo else ChargeAction.PASS_THROUGH, controlled_player)
		elif Input.is_action_just_pressed(&"pass_lob"):
			_start_queue_charge(ChargeAction.PASS_LOB, controlled_player)
	for act in [&"pass_short", &"pass_through", &"pass_lob"]:
		if Input.is_action_just_released(act) and _charge_player == controlled_player \
				and _charge_action != ChargeAction.SHOT and _is_charging():
			if _is_queued():
				_stop_queue_fix_ratio()
			else:
				_fire_charge()
			break
```

- [ ] **Step 6: Авто-фикс при достижении макс. заряда (`_process`)**

В `_process`, в блоке накопления заряда (~строки 596-608), заменить авто-файр на максимуме так, чтобы для очереди он ФИКСИРОВАЛ ratio, а не бил в воздух:

```gdscript
	if _is_charging() and _charge_player == controlled_player:
		var is_shot: bool = _charge_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]
		var max_time := KICK_CHARGE_MAX_TIME if is_shot else FootballConstants.PASS_CHARGE_MAX_TIME
		_charge_time += get_process_delta_time()
		if _charge_time >= max_time:
			_charge_time = max_time
			if _is_queued():
				_stop_queue_fix_ratio()  # мяч не у ног — фиксируем силу на макс., ждём касания
			else:
				_fire_charge()
		if _is_charging():
			var ratio := clampf(_charge_time / max_time, 0.0, 1.0)
			power_bar.value = ratio
			var fill := power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
```

- [ ] **Step 7: Регресс — обе команды**

Expected: baseline. (Очередь ставится и фиксируется, но пока НЕ стреляет по касанию — это Задача 5. Проверяем, что парс/загрузка чистые и обычные удары/пасы с мячом у ног работают как раньше.)

- [ ] **Step 8: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(shot): queue shot/pass when ball not at feet (incoming pass or sprint break-away)"
```

---

## Task 5: Срабатывание по касанию — удар/пас «в одно касание»

Когда `_queue_player` дотянулся до мяча (`QUEUE_REACH_RADIUS`), вместо трапа диспатчим отложенное действие: прицел по facing тела в этот момент, сила = `one_touch_ratio(база, скорость_мяча)`.

**Files:**
- Modify: `scripts/match/match_manager.gd` — `_try_fire_queue()`, вызов в `_physics_process` ПЕРЕД `_handle_dribbling()`.

**Interfaces:**
- Consumes: `_queue_*`, `ShotSystem.one_touch_ratio`, `_fire_shot`/`_fire_pass` (с `facing_override`), `FootballConstants.QUEUE_*`.
- Produces: `_try_fire_queue() -> bool` (true = выстрелили/сбросили очередь этим кадром).

- [ ] **Step 1: `_try_fire_queue`**

Добавить рядом с `_clear_queue` (~строка 1047):

```gdscript
## Если отложенное действие в очереди и игрок дотянулся до мяча — бьём в одно касание.
## Прицел по facing тела игрока СЕЙЧАС (он ещё не дриблер), сила = заряд + скорость влёта мяча.
## Возвращает true, если в этом кадре выстрелили (тогда обычный трап/дриблинг пропускаем).
func _try_fire_queue() -> bool:
	if not _is_queued():
		return false
	if _queue_player == null or not is_instance_valid(_queue_player):
		_clear_queue()
		return false
	var d: float = _queue_player.global_position.distance_to(ball.global_position)
	if d > FootballConstants.QUEUE_REACH_RADIUS:
		return false  # ещё не дотянулся — ждём (авто-подбегание ведёт игрока к мячу)
	# «Добрался ПЕРВЫМ»: не бьём, если соперник СТРОГО ближе к мячу (спорный мяч он выиграл или
	# вот-вот затрапит → тогда сработает отмена taken_by_other). Так одно касание проходит только
	# при честной победе в борьбе; иначе ждём/сбрасываемся. Соперники — группа "team_2".
	for opp in get_tree().get_nodes_in_group("team_2"):
		if opp is Node3D and is_instance_valid(opp) \
				and (opp as Node3D).global_position.distance_to(ball.global_position) < d:
			return false
	# Дотянулся первым: диспатчим в одно касание.
	var action := _queued_action
	var player := _queue_player
	var base_ratio := _queue_ratio
	# Всё ещё держим кнопку в момент касания → бьём на ТЕКУЩЕМ заряде (не на зафиксированном).
	if _is_charging() and _charge_player == player and _charge_action == action:
		var is_shot: bool = action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]
		var max_time := KICK_CHARGE_MAX_TIME if is_shot else FootballConstants.PASS_CHARGE_MAX_TIME
		base_ratio = clampf(_charge_time / max_time, 0.0, 1.0)
		_cancel_charge()
	var incoming_speed: float = ball.linear_velocity.length()
	var eff_ratio := ShotSystem.one_touch_ratio(base_ratio, incoming_speed, FootballConstants.QUEUE_BALL_SPEED_GAIN)
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3.FORWARD
	_clear_queue()
	if action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]:
		_fire_shot(action, player, eff_ratio, facing.normalized())
	else:
		_fire_pass(action, player, eff_ratio, facing.normalized())
	return true
```

- [ ] **Step 2: Вызов в `_physics_process` перед дриблингом**

В начале `_physics_process` (~строка 632), ПЕРЕД `_handle_dribbling()`:

```gdscript
func _physics_process(delta: float) -> void:
	# Одно касание: если действие в очереди и игрок дотянулся — бьём вместо трапа/дриблинга.
	if _try_fire_queue():
		_handle_player_input(delta)
		return
	_handle_dribbling()
	_handle_player_input(delta)
```

(Заметка: при выстреле пропускаем `_handle_dribbling()` в этом кадре — иначе тот же тик мог бы затрапить мяч получателем/подобравшим. Ввод обрабатываем, чтобы движение/спринт не зависали.)

- [ ] **Step 3: Регресс — обе команды + check-скрипт**

Expected: baseline; `check_shot_system_math.gd` → `CHECK PASS`.

- [ ] **Step 4: Ручная приёмка (одно касание)**

Запустить игру. Проверить оба источника очереди:
1. **Спринт-отрыв (свой мяч):** разогнаться в спринт-дриблинге (мяч убегает вперёд >2 м), нажать удар/пас — раньше не срабатывало; теперь игрок добегает и бьёт в одно касание по своему мячу.
2. **Пас на нас:** отдать пас на другого нашего игрока (ввод переключится на принимающего), в полёте зажать удар/пас — по касанию бьёт в одно касание (быстрый пас → мощнее даже при коротком заряде).
3. Отпустить кнопку до касания → сила фиксируется; держать до касания → бьёт на текущем заряде.
4. Мяч перехватили/ушёл в аут/таймаут `QUEUE_MAX_TIME` → очередь сбрасывается, нет «фантомного» удара.
5. **Спорный мяч** (нужно временно вернуть `DEBUG_DISABLE_OPPONENT = false`, чтобы соперник двигался): ничейный мяч летит к нам, рядом соперник — заряжаем; если наш игрок добежал ПЕРВЫМ (ближе всех) → удар; если соперник забрал/ближе → удар НЕ выполняется (очередь сброшена). Вернуть `DEBUG_DISABLE_OPPONENT = true` после проверки, если продолжаем тесты стенок.
Подстроить `QUEUE_BALL_SPEED_GAIN` (вклад скорости), `QUEUE_REACH_RADIUS` (когда «дотянулся»), `QUEUE_CONSIDER_RADIUS` (когда ничейный мяч можно ставить в очередь), `QUEUE_MAX_TIME`.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(shot): fire queued shot/pass one-touch on reach (aim by facing, power += ball speed)"
```

---

## Task 6: Авто-подбегание к мячу под очередь + UI (power_bar/маркер вне владения)

Пока действие в очереди, игрок должен бежать к прогнозной точке мяча (не полагаясь на стик). Для паса это уже делает receive-assist; для своего отрыва — dribble-chase. Добираем случай «очередь на свой отрыв, но стик отпущен» и показываем шкалу/маркер вне владения.

**Files:**
- Modify: `scripts/match/match_manager.gd` — `_handle_player_input` (авто-бег к мячу под очередь); `_process` (power_bar/маркер при очереди).

**Interfaces:**
- Consumes: `_is_queued`, `_queue_player`, `ball.linear_velocity`, `FootballConstants.PASS_RECEIVE_PREDICT_WINDOW`.
- Produces: —

- [ ] **Step 1: Авто-бег к мячу, пока действие в очереди**

В `_handle_player_input`, СРАЗУ после вычисления `dir` из стика и блока receive-assist (после строки ~829, до дриблинг-блока ~833), добавить: если действие в очереди на этого игрока — вести к прогнозной точке мяча (перекрывает стик, как receive-assist), но НЕ дублировать, если receive-assist уже ведёт:

```gdscript
	# Очередь «в одно касание»: пока ждём касания, автоматически бежим к мячу (прогноз позиции),
	# чтобы дотянуться. Для паса это уже делает receive-assist выше; здесь покрываем свой отрыв
	# (спринт-дриблинг) и случай отпущенного стика.
	if _is_queued() and _queue_player == controlled_player and is_instance_valid(ball) \
			and not (_receive_active and _receiver == controlled_player):
		var qb := (ball.global_position + ball.linear_velocity * FootballConstants.PASS_RECEIVE_PREDICT_WINDOW) - controlled_player.global_position
		qb.y = 0.0
		if qb.length() > 0.01:
			dir = qb.normalized()
```

- [ ] **Step 2: power_bar и маркер цели видны при очереди (вне владения)**

В `_process`, заменить строку видимости шкалы (~строка 611):

```gdscript
	power_bar.visible = (_is_charging() and _charge_player == controlled_player) or (_is_queued() and _queue_player == controlled_player)
```

И расширить `show_target` (жёлтый маркер цели паса) на очередь-паса (~строка 613): маркер показываем и когда пас в очереди. Заменить на:

```gdscript
	var charging_pass := _is_charging() and not (_charge_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]) and _charge_player == controlled_player
	var queued_pass := _is_queued() and not (_queued_action in [ChargeAction.SHOT, ChargeAction.SHOT_CURL, ChargeAction.SHOT_CHIP]) and _queue_player == controlled_player
	var show_target := charging_pass or queued_pass
	if show_target:
		var tgt_player: CharacterBody3D = _charge_player if charging_pass else _queue_player
		var mates := _team_arrays(&"team_1", tgt_player)
```

(Ниже в теле `if show_target:` заменить `_charge_player.global_position` на `tgt_player.global_position` в вызове `PassSystem.select_target`.)

- [ ] **Step 3: Регресс — обе команды**

Expected: baseline.

- [ ] **Step 4: Ручная приёмка (подбегание + UI)**

Проверить: при очереди игрок сам бежит к мячу (даже если стик отпущен), шкала заряда видна вне владения, для запланированного паса виден жёлтый маркер цели. Спринт-отрыв: нажал удар, отпустил стик — игрок всё равно добегает к своему мячу и бьёт.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(shot): auto-run to ball while queued + power bar / target marker out of possession"
```

---

## Task 7: Финальная приёмка Фазы 2 + регресс

**Files:** —

- [ ] **Step 1: Ручная приёмка всех веток вместе**

Прогнать по очереди, оба источника (свой спринт-отрыв и пас на нас) × все действия:
- три удара (`D`, `E`+`D`, `Q`+`D`) в одно касание;
- пять пасов (`X`, `W`, `A`, `Q`+`X`, `Q`+`W`) в одно касание;
- сила растёт от скорости влетающего мяча (быстрый прострел → мощный первый тайм даже при коротком заряде);
- отмены: перехват/аут/таймаут/смена игрока/падение — без фантомных ударов;
- обычные удары/пасы с мячом У НОГ по-прежнему работают немедленно (не через очередь).

- [ ] **Step 2: Регресс — обе команды + оба check-скрипта**

Run: обе команды валидации; `check_shot_system_math.gd`; `check_ball_state.gd`.
Expected: baseline; оба `CHECK PASS`.

- [ ] **Step 3: Commit (если были финальные правки тюнинга)**

```bash
git add scripts/data/football_constants.gd scripts/match/match_manager.gd
git commit -m "tune(shot): finalize Phase 2 action-queue timing/gain"
```

---

## Self-Review (выполнено автором)

**Spec coverage (S5 «Фаза 2» спека `2026-07-10-shot-system-design.md`):**
- Когда активна (не владеет, мяч летит к нему) — `_can_queue`, ветка `incoming`, Задача 4. ✓
- **Расширение (уточнение пользователя): спринт-отрыв своего мяча** (дриблер, но мяч убежал вперёд) — `_can_queue` ветка `breakaway`, Задачи 4/5. ✓ (за пределами буквы спека, по запросу.)
- **Расширение (уточнение пользователя): спорный мяч** (мяч летит к нам, рядом борется соперник) — заряжать можно всегда (`_can_queue` ветка `loose`, ничейный мяч в радиусе), удар выполняется, ТОЛЬКО если наш игрок добрался первым: отмена `taken_by_other` (мяч забрал другой → сброс) + гард «нет соперника ближе к мячу» в `_try_fire_queue`, Задачи 2/4/5. ✓ (за пределами буквы спека, по запросу.)
- Механика заряда (держишь копит / отпустил фиксирует / держишь на касании бьёт на текущем) — Задачи 4 (release/max фикс) + 5 (`_try_fire_queue` берёт текущий заряд, если ещё держишь). ✓
- Сила = база + `QUEUE_BALL_SPEED_GAIN * incoming_speed`, кламп — `ShotSystem.one_touch_ratio`, Задача 1; применяется в `_try_fire_queue`, Задача 5. ✓
- Поля `_queued_action/_queue_player/_queue_ratio/_queue_timer` — Задача 2. (`_queue_combo` НЕ нужен: combo закодирован в `ChargeAction`.) ✓
- Срабатывание в момент касания вместо трапа — `_try_fire_queue` перед `_handle_dribbling`, Задача 5. ✓
- **Прицел/цель в момент касания** (facing/стик, не постановки) — `facing_override` из facing тела на касании, Задачи 3/5. ✓
- Область: 3 удара + 5 пасов, те же `_fire_charge`/`_fire_pass` пути — Задачи 4/5. ✓
- Отмена каждый физкадр (перехват/аут/таймаут/смена игрока/сбит) — Задача 2 (физпроцесс) + сброс в `_finish_fall`. ✓
- Авто-подбегание (общий механизм, переиспользует receive-assist) — Задача 6 + существующий receive-assist/chase. ✓
- UI: power_bar виден вне владения, жёлтый маркер для запланированного паса — Задача 6. ✓

**Отклонения/упрощения:**
- `_queue_combo` из спека не заводим — combo уже в значении `ChargeAction` (SHOT_CURL/SHOT_CHIP/PASS_WALL/PASS_THROUGH_AIR). Меньше состояния, тот же результат.
- Диспатч по касанию идёт через существующий commit-action (импульс по `action_contact`), а не мгновенно. На касании мяч у ног/впереди → стопгэп «за спиной» проходит. Если на быстром пасе мяч успевает уйти за спину за время анимации — всплывёт на ручной приёмке (Задача 5/7); тогда следующий шаг — мгновенный импульс для очереди (вне охвата этого плана, отдельной правкой).
- Голова (Фаза 3) надстроится над этим же авто-подбеганием и очередью — здесь только «в ноги».

**Placeholder scan:** весь код приведён целиком; «заметки» в Задаче 2 Step 4 явно указывают финальный вид условия (переменную-напоминание `ours` НЕ писать).

**Type consistency:** `_fire_shot`/`_fire_pass` 4-й арг `facing_override: Vector3 = Vector3.ZERO` согласован между Задачей 3 (объявление) и Задачей 5 (вызов с `facing.normalized()`). `one_touch_ratio(base_ratio, incoming_speed, gain)` согласована между модулем (Задача 1), тестом (Задача 1) и вызовом (Задача 5). `ChargeAction` значения — существующие. `QUEUE_BALL_SPEED_GAIN`/`QUEUE_MAX_TIME`/`QUEUE_REACH_RADIUS` — Задача 2, используются в 4/5.

**Открытые моменты для ручной приёмки:** `QUEUE_BALL_SPEED_GAIN` (насколько скорость мяча усиливает удар), `QUEUE_REACH_RADIUS` (когда «дотянулся»), `QUEUE_MAX_TIME` — тюнинг-старт, финализируются живьём.

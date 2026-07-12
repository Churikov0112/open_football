# Пасы + поддержка ИИ-тиммейта: ощущение — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Сделать низовые пасы крепкими (твёрдый пол пейса), заставить принимающего выходить ВПЕРЁД на пас (а не назад к отдавшему), и заставить ИИ-тиммейта предлагать себя под пас, а не бежать в мяч.

**Architecture:** Три связанных изменения. (1) Сила: поднять пол скорости низового паса + лёгкий подъём мяча с газона (константы + новый параметр `up` у чистой `launch_ground`). (2) Приём: новая чистая `PassSystem.receive_point` ведёт скорость мяча вперёд (точка перехвата), спецкейс «мяч прямо в тебя»; вызывается человеком-принимающим и ИИ. (3) Тиммейт: при владении нашей команды держит позицию поддержки (обобщённый `_position_for_pass`), к мячу идёт только на ничейный/как адресат. Модель паса «долетает до цели» СОХРАНЯЕТСЯ (не импульсная OpenSoccer).

**Tech Stack:** Godot 4.7 / GDScript. Тесты — headless `SceneTree` (`tests/check_pass_system_math.gd`), плюс две команды валидации.

## Global Constraints

- Godot 4.7 / GDScript. Windows-only.
- **`PassSystem` не читает `FootballConstants`** — все тюнинги параметрами (как в остальном коде). Тест сидит RNG.
- **Модель низового паса «долетает ровно до цели» СОХРАНЯЕТСЯ** — `ground_pass_speed` (скорость = дистанция/время) не меняем, только поднимаем пол через КОНСТАНТУ. Импульсную OpenSoccer-модель НЕ берём (решение пользователя).
- **Навесы/лобы (`is_air`, `launch_lob`) не трогаем** — проблема только у низовых.
- **Направление паса / авто-выбор цели (`select_target`) вне охвата** (отложено пользователем).
- **`PASS_RECEIVE_PREDICT_WINDOW` НЕ удалять** — используется queue-автобегом Фазы 2 (`match_manager.gd:835`), это другой контекст. Приём получает НОВЫЕ константы.
- **Направление атаки тиммейта** читать через локальный `_attack_dir()` (готовность к half-time-свапу); полная централизация на менеджерский `_attack_dir_z` — отдельная задача, вне охвата.
- Команды валидации (обе):
  - `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
  - `& "...console.exe" --path "..." --headless --quit-after 2 res://scenes/match.tscn`
- Baseline ошибок 2-й команды (диффать, не ждать нуля): 4 категории — ~41× `!is_inside_tree()`, ~22× transition-duplicate, ~11× `states.has`, ~1× `WorldEnvironmentND`. Headless-check: `... --headless -s "res://tests/<name>.gd"` → `CHECK PASS`/`FAIL`, exit 0/1. После правки `class_name`-скрипта — `--headless --import` перед `-s`.
- **Ощущение (крепость паса, выход на пас, поведение тиммейта) headless НЕ ловит** — после Задач 1/3/4 обязателен ручной прогон пользователем.

## File Structure

- **Modify:** `scripts/match/pass_system.gd` — `up`-параметр у `launch_ground`; новая `receive_point`.
- **Modify:** `tests/check_pass_system_math.gd` — тесты `launch_ground(up)` и `receive_point`.
- **Modify:** `scripts/data/football_constants.gd` — PASSING: поднять `PASS_GROUND_MIN_SPEED`/ужать `PASS_GROUND_MAX_TRAVEL_TIME`; новые `PASS_GROUND_LIFT`, `PASS_RECEIVE_LEAD_TIME`, `PASS_RECEIVE_ONLINE_DOT`.
- **Modify:** `scripts/match/match_manager.gd` — вызов `launch_ground` с lift; receive-assist → `receive_point`.
- **Modify:** `scripts/ai/teammate_ai.gd` — `_move_to_receive` → `receive_point`; выбор роли (владение команды → поддержка); `_team_has_ball()`; `_attack_dir()`; `_position_for_pass` от носителя = `ball.dribbler`.

---

## Task 1: Сила паса — твёрдый пол пейса + подъём с газона

Крепкий низовой пас на любой дистанции: поднять нижний порог скорости и ужать «мягкое» время, плюс лёгкий подъём мяча (не «прилипает» к траве). `ground_pass_speed` — только через константу; `launch_ground` получает параметр `up`.

**Files:**
- Modify: `scripts/match/pass_system.gd` (`launch_ground`)
- Modify: `tests/check_pass_system_math.gd`
- Modify: `scripts/data/football_constants.gd`
- Modify: `scripts/match/match_manager.gd` (вызов `launch_ground`)

**Interfaces:**
- Produces: `launch_ground(from, to, power, up := 0.0) -> Vector3` (был `launch_ground(from, to, power)`).
- Produces: `FootballConstants.PASS_GROUND_LIFT`; изменённые `PASS_GROUND_MIN_SPEED`, `PASS_GROUND_MAX_TRAVEL_TIME`.

- [ ] **Step 1: Тест `launch_ground` с `up` (падающий)**

В `tests/check_pass_system_math.gd`, ПОСЛЕ существующего блока `launch_ground` (после строки с `CHECK FAIL: launch_ground direction`), добавить:

```gdscript
	# launch_ground с подъёмом: горизонталь прежней длины power, плюс вертикаль up.
	var lgu := PassSystem.launch_ground(Vector3.ZERO, Vector3(3, 0, 4), 10.0, 1.5)
	if not is_equal_approx(Vector3(lgu.x, 0, lgu.z).length(), 10.0):
		print("CHECK FAIL: launch_ground(up) horizontal magnitude → ", lgu); ok = false
	if not is_equal_approx(lgu.y, 1.5):
		print("CHECK FAIL: launch_ground(up) vertical → ", lgu); ok = false
```

- [ ] **Step 2: Прогнать тест — падает**

Run: `& "...console.exe" --path "..." --headless -s "res://tests/check_pass_system_math.gd"`
Expected: `CHECK FAIL` (у `launch_ground` пока нет 4-го аргумента → parse error про число аргументов).

- [ ] **Step 3: Добавить параметр `up` в `launch_ground`**

В `scripts/match/pass_system.gd` заменить `launch_ground`:

```gdscript
static func launch_ground(from: Vector3, to: Vector3, power: float, up: float = 0.0) -> Vector3:
	var dir := to - from
	dir.y = 0.0
	if dir.length() < 0.001:
		return Vector3.ZERO
	return dir.normalized() * power + Vector3.UP * up
```

- [ ] **Step 4: Import + прогнать тест — PASS**

Run: `& "...console.exe" --path "..." --headless --import` затем `... --headless -s "res://tests/check_pass_system_math.gd"`
Expected: `CHECK PASS` (старый 3-аргументный вызов в тесте по-прежнему работает, `up` по умолчанию 0).

- [ ] **Step 5: Константы (`football_constants.gd`)**

Заменить две строки (значения — тюнинг-старт):

```gdscript
const PASS_GROUND_MAX_TRAVEL_TIME := 0.7   # время полёта при минимальном заряде (мягкий, медленный пас), с
```
(было `0.9`)

```gdscript
const PASS_GROUND_MIN_SPEED := 15.0        # нижний предел скорости мяча низом, м/с (твёрдый пол — короткий пас тоже крепкий)
```
(было `6.0`)

И добавить после `PASS_GROUND_MAX_SPEED`:

```gdscript
const PASS_GROUND_LIFT := 1.5              # лёгкий подъём мяча с газона при низовом пасе, м/с (не прилипает к траве)
```

- [ ] **Step 6: Передать lift в вызов `launch_ground` (`match_manager.gd`)**

Найти (≈строка 1322) `launch_vel = PassSystem.launch_ground(from, aim_point, ground_speed)` и заменить на:

```gdscript
			launch_vel = PassSystem.launch_ground(from, aim_point, ground_speed, FootballConstants.PASS_GROUND_LIFT)
```

- [ ] **Step 7: Регресс — обе команды + check-скрипт**

Expected: baseline; `check_pass_system_math.gd` → `CHECK PASS`.

- [ ] **Step 8: Ручная приёмка (крепость паса)**

Запустить игру. Отдать короткий пас лёгким тапом кнопки: мяч должен уходить **крепко и быстро**, а не вялым накатом; чуть отрывается от газона, но остаётся низовым. Средний/длинный пас — по-прежнему доходит. Подстроить `PASS_GROUND_MIN_SPEED`, `PASS_GROUND_MAX_TRAVEL_TIME`, `PASS_GROUND_LIFT`.

- [ ] **Step 9: Commit**

```bash
git add scripts/match/pass_system.gd tests/check_pass_system_math.gd scripts/data/football_constants.gd scripts/match/match_manager.gd
git commit -m "feat(pass): firm ground-pass floor + slight lift off the grass"
```

---

## Task 2: `PassSystem.receive_point` — вести скорость мяча (чистая функция + тест)

Ядро фикса «из ноги в ногу»: принимающий целится в точку перехвата ПО ХОДУ мяча, а не в текущую позицию. Спецкейс: мяч летит почти прямо в/от принимающего → встречаем на линии (иначе увод вбок).

**Files:**
- Modify: `scripts/match/pass_system.gd`
- Modify: `tests/check_pass_system_math.gd`

**Interfaces:**
- Produces (static, `class_name PassSystem`): `receive_point(receiver_pos: Vector3, ball_pos: Vector3, ball_vel: Vector3, lead_time: float, on_line_dot: float) -> Vector3` — мировая точка, к которой бежать принимающему.

- [ ] **Step 1: Тест `receive_point` (падающий)**

В `tests/check_pass_system_math.gd`, ПЕРЕД финальным `print("CHECK PASS" ...)`, добавить:

```gdscript
	# receive_point: мяч летит почти прямо в принимающего → цель == позиция мяча (встречаем на линии).
	var rp_online := PassSystem.receive_point(Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(0, 0, -5), 0.2, 0.9)
	if not rp_online.is_equal_approx(Vector3(0, 0, 10)):
		print("CHECK FAIL: receive_point on-line → ", rp_online); ok = false
	# мяч идёт вбок мимо → ведём вперёд по скорости на lead_time.
	var rp_side := PassSystem.receive_point(Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(5, 0, 0), 0.2, 0.9)
	if not rp_side.is_equal_approx(Vector3(1.0, 0, 10)):
		print("CHECK FAIL: receive_point side lead → ", rp_side); ok = false
	# нулевая скорость мяча → позиция мяча.
	if not PassSystem.receive_point(Vector3(0, 0, 0), Vector3(3, 0, 7), Vector3.ZERO, 0.2, 0.9).is_equal_approx(Vector3(3, 0, 7)):
		print("CHECK FAIL: receive_point zero vel → ball pos"); ok = false
```

- [ ] **Step 2: Прогнать тест — падает**

Run: `& "...console.exe" --path "..." --headless -s "res://tests/check_pass_system_math.gd"`
Expected: `CHECK FAIL` (parse error: `receive_point` не найдена).

- [ ] **Step 3: Написать `receive_point`**

В `scripts/match/pass_system.gd` добавить (например, после `lead_point`):

```gdscript
## Куда бежать принимающему: точка перехвата ПО ХОДУ мяча (ball_pos + ball_vel*lead_time), а НЕ
## текущая позиция мяча — иначе на медленном мяче принимающий бежит назад к отдавшему («из ноги в
## ногу»). Спецкейс: если мяч летит почти прямо В или ОТ принимающего (|dot| > on_line_dot),
## упреждать вбок незачем — встречаем на линии (возвращаем ball_pos). Пустая скорость → ball_pos.
static func receive_point(receiver_pos: Vector3, ball_pos: Vector3, ball_vel: Vector3,
		lead_time: float, on_line_dot: float) -> Vector3:
	var bv := Vector3(ball_vel.x, 0.0, ball_vel.z)
	if bv.length() < 0.001:
		return ball_pos
	var to_ball := Vector3(ball_pos.x - receiver_pos.x, 0.0, ball_pos.z - receiver_pos.z)
	if to_ball.length() > 0.001 and absf(to_ball.normalized().dot(bv.normalized())) > on_line_dot:
		return ball_pos
	return ball_pos + bv * lead_time
```

- [ ] **Step 4: Import + прогнать тест — PASS**

Run: `& "...console.exe" --path "..." --headless --import` затем `... --headless -s "res://tests/check_pass_system_math.gd"`
Expected: `CHECK PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/pass_system.gd tests/check_pass_system_math.gd
git commit -m "feat(pass): PassSystem.receive_point (lead ball velocity, on-line special case) + test"
```

---

## Task 3: Подключить `receive_point` — человек-принимающий + ИИ-принимающий

Заменить текущий «беги к позиции мяча сейчас» на «беги в точку перехвата». Убирает «из ноги в ногу» вместе с крепким пасом из Задачи 1.

**Files:**
- Modify: `scripts/data/football_constants.gd` (новые receive-константы)
- Modify: `scripts/match/match_manager.gd` (receive-assist)
- Modify: `scripts/ai/teammate_ai.gd` (`_move_to_receive`)

**Interfaces:**
- Consumes: `PassSystem.receive_point`, `FootballConstants.PASS_RECEIVE_LEAD_TIME`, `FootballConstants.PASS_RECEIVE_ONLINE_DOT`.

- [ ] **Step 1: Константы приёма (`football_constants.gd`)**

После `PASS_RECEIVE_PREDICT_WINDOW` (её НЕ трогаем — нужна очереди Фазы 2) добавить:

```gdscript
const PASS_RECEIVE_LEAD_TIME := 0.2        # на сколько сек вперёд по скорости мяча ведём точку приёма (перехват)
const PASS_RECEIVE_ONLINE_DOT := 0.9       # |dot| выше → мяч летит почти в/от нас → встречаем на линии, без упреждения вбок
```

- [ ] **Step 2: Человек-принимающий (`match_manager.gd` receive-assist)**

Найти блок (≈строка 822-826):

```gdscript
	if _receive_active and controlled_player == _receiver and is_instance_valid(ball):
		var db := (ball.global_position + ball.linear_velocity * FootballConstants.PASS_RECEIVE_PREDICT_WINDOW) - controlled_player.global_position
		db.y = 0.0
		if db.length() > 0.01:
			dir = db.normalized()
```

заменить на:

```gdscript
	if _receive_active and controlled_player == _receiver and is_instance_valid(ball):
		var rp := PassSystem.receive_point(controlled_player.global_position, ball.global_position,
			ball.linear_velocity, FootballConstants.PASS_RECEIVE_LEAD_TIME, FootballConstants.PASS_RECEIVE_ONLINE_DOT)
		var db := rp - controlled_player.global_position
		db.y = 0.0
		if db.length() > 0.01:
			dir = db.normalized()
```

- [ ] **Step 3: ИИ-принимающий (`teammate_ai.gd` `_move_to_receive`)**

Найти в `_move_to_receive` ветку `else` (в ноги):

```gdscript
	else:
		var predicted := ball.global_position + ball.linear_velocity * FootballConstants.PASS_RECEIVE_PREDICT_WINDOW
		target = predicted
```

заменить на:

```gdscript
	else:
		target = PassSystem.receive_point(global_position, ball.global_position, ball.linear_velocity,
			FootballConstants.PASS_RECEIVE_LEAD_TIME, FootballConstants.PASS_RECEIVE_ONLINE_DOT)
```

- [ ] **Step 4: Регресс — обе команды**

Expected: baseline. (Приём теперь ведёт скорость мяча; queue-автобег Фазы 2 не затронут — он использует свою `PASS_RECEIVE_PREDICT_WINDOW`.)

- [ ] **Step 5: Ручная приёмка (нет «из ноги в ногу»)**

Запустить игру. Отдать пас на тиммейта (управление переключится на принимающего): принимающий должен выходить **вперёд на мяч** (в точку перехвата), а НЕ бежать назад к отдавшему. Нет встречи «из ноги в ногу» вплотную. Подстроить `PASS_RECEIVE_LEAD_TIME` (больше → дальше вперёд встречает), `PASS_RECEIVE_ONLINE_DOT`.

- [ ] **Step 6: Commit**

```bash
git add scripts/data/football_constants.gd scripts/match/match_manager.gd scripts/ai/teammate_ai.gd
git commit -m "feat(pass): receiver runs onto the pass (lead ball velocity) for human + AI, fixes foot-to-foot"
```

---

## Task 4: ИИ-тиммейт предлагает себя под пас (не бежит в мяч)

При владении нашей команды тиммейт держит позицию поддержки, а не гонит в мяч. К мячу — только на ничейный/как адресат.

**Files:**
- Modify: `scripts/ai/teammate_ai.gd`

**Interfaces:**
- Produces: `_team_has_ball() -> bool`; `_attack_dir() -> Vector3`.
- Consumes: `ball.dribbler`, group `team_1`.

- [ ] **Step 1: `_attack_dir()` и `_team_has_ball()`**

В `scripts/ai/teammate_ai.gd` добавить (например, рядом с `_base_scale`):

```gdscript
## Направление атаки нашей команды (team_1 атакует −Z в 1-м тайме). Одно место — готово к
## half-time-свапу (полная централизация на менеджерский _attack_dir_z — отдельная задача).
func _attack_dir() -> Vector3:
	return Vector3(0, 0, -1)

## Владеет ли мячом НАША команда (кто-то из team_1 — дриблер): тогда предлагаем себя под пас,
## а не бежим в мяч.
func _team_has_ball() -> bool:
	return ball.has_method(&"set_dribbler") and ball.dribbler != null and ball.dribbler.is_in_group("team_1")
```

- [ ] **Step 2: Выбор роли — владение команды → поддержка**

В `_physics_process` найти:

```gdscript
	var has_dribbler: bool = ball.has_method(&"set_dribbler") and ball.dribbler

	match _role:
		Role.RECEIVING:
			_move_to_receive(delta)
			return
		_:
			if has_dribbler and ball.dribbler == controlled_player:
				_position_for_pass(delta)
			else:
				_chase_ball(delta)
```

заменить на (убираем неиспользуемый `has_dribbler`, условие — «наша команда владеет»):

```gdscript
	match _role:
		Role.RECEIVING:
			_move_to_receive(delta)
			return
		_:
			if _team_has_ball():
				_position_for_pass(delta)
			else:
				_chase_ball(delta)
```

- [ ] **Step 3: `_position_for_pass` — от носителя `ball.dribbler` + `_attack_dir()`**

Заменить тело `_position_for_pass`:

```gdscript
func _position_for_pass(delta: float) -> void:
	# Носитель — фактический дриблер нашей команды (человек или второй игрок), не обязательно
	# управляемый. Встаём впереди носителя по атаке + сбоку на пас-дистанции — предлагаем себя
	# (сам оффсет и есть расстановка: не липнем к носителю).
	var carrier_pos := ball.dribbler.global_position if _team_has_ball() else global_position
	var side_sign := 1.0 if carrier_pos.x < 0 else -1.0
	var target := carrier_pos + _attack_dir() * 10.0 + Vector3(side_sign * 6.0, 0, 0)

	target.x = clamp(target.x, -field_width + 4, field_width - 4)
	target.z = clamp(target.z, -field_length + 4, field_length - 4)
	target.y = global_position.y

	var dir := (target - global_position).normalized()
	dir.y = 0.0
	_move_or_wander(dir, delta)
```

- [ ] **Step 4: `begin_give_and_go`/gng-рывок через `_attack_dir()`**

В блоке `is_in_group("giving_run")` (в `_physics_process`) найти `var attack := Vector3(0, 0, -1)  # атакуем к −Z` и заменить на:

```gdscript
			var attack := _attack_dir()  # атакуем к −Z (через хелпер — готово к half-time)
```

- [ ] **Step 5: Регресс — обе команды**

Expected: baseline.

- [ ] **Step 6: Ручная приёмка (тиммейт предлагает себя)**

Запустить игру. Ведя мяч человеком, смотреть на тиммейта: он должен **держаться впереди/сбоку** на пас-дистанции и предлагать себя, а НЕ бежать в мяч/к тебе. Отпустить/потерять мяч (ничейный) → тиммейт снова идёт за мячом (борьба не сломана). Подстроить оффсеты (`10.0`/`6.0`) при желании.

- [ ] **Step 7: Commit**

```bash
git add scripts/ai/teammate_ai.gd
git commit -m "feat(ai): teammate offers a pass (support position) instead of chasing the ball"
```

---

## Task 5: Финальная приёмка + регресс

**Files:** —

- [ ] **Step 1: Ручная приёмка всех трёх вместе**

Прогнать связкой: веду мяч → тиммейт предлагает себя впереди → отдаю короткий пас (крепкий, не вялый) → тиммейт выходит вперёд на мяч (не назад, без «из ноги в ногу») → принимает и ведёт. Проверить также средний/длинный пас и ничейный мяч (тиммейт борется). При активном сопернике (временно `DEBUG_DISABLE_OPPONENT = false`) — перехваты не сломаны.

- [ ] **Step 2: Регресс — обе команды + оба check-скрипта**

Run: обе команды валидации; `check_pass_system_math.gd`; `check_ball_state.gd`.
Expected: baseline; оба `CHECK PASS`.

- [ ] **Step 3: Commit (если были финальные правки тюнинга)**

```bash
git add scripts/data/football_constants.gd scripts/ai/teammate_ai.gd
git commit -m "tune(pass): finalize pass feel + teammate support"
```

---

## Self-Review (выполнено автором)

**Spec coverage (спек `2026-07-11-pass-and-teammate-feel-design.md`):**
- Сила паса — твёрдый пол (`PASS_GROUND_MIN_SPEED` 6→15, `PASS_GROUND_MAX_TRAVEL_TIME` 0.9→0.7) + подъём (`launch_ground` `up`, `PASS_GROUND_LIFT`); навесы не тронуты — Задача 1. ✓
- Приём — `receive_point` (ведёт скорость мяча, спецкейс on-line, нулевая скорость → ball_pos) — Задача 2; подключён человеку и ИИ — Задача 3. ✓
- ИИ-тиммейт — поддержка при владении команды (`_team_has_ball` → `_position_for_pass`), к мячу только на ничейный/как адресат; `_attack_dir()` для готовности к half-time — Задача 4. ✓
- Модель «пас долетает до цели» сохранена (только пол через константу) — Global Constraints + Задача 1. ✓
- `PASS_RECEIVE_PREDICT_WINDOW` не удалена (queue Фазы 2) — Global Constraints + Задача 3 Step 1. ✓
- Headless-тесты (`receive_point`, `launch_ground` с `up`) — Задачи 1/2. ✓

**Отклонения/упрощения:**
- «Расстановка» тиммейта реализована фиксированным оффсетом (впереди 10м + сбоку 6м ≈ 11.6м от носителя) — этого достаточно для 1 тиммейта, отдельная min-separation-константа не нужна (YAGNI).
- Носитель в `_position_for_pass` = `ball.dribbler` (обобщение с `controlled_player`); в 2-игроковом сетапе это почти всегда человек, но корректно и для второго игрока.
- Направление паса/`select_target` — вне охвата (отложено пользователем).

**Placeholder scan:** весь код приведён целиком; значения констант помечены «тюнинг-старт», финализируются на ручной приёмке.

**Type consistency:** `launch_ground(from, to, power, up := 0.0)` — сигнатура согласована между модулем (Задача 1 Step 3), тестом (Задача 1 Step 1) и вызовом (Задача 1 Step 6). `receive_point(receiver_pos, ball_pos, ball_vel, lead_time, on_line_dot)` — согласована между модулем (Задача 2), тестом (Задача 2) и вызовами (Задача 3, человек+ИИ). `_team_has_ball()`/`_attack_dir()` — Задача 4, используются там же. Константы `PASS_GROUND_LIFT`/`PASS_RECEIVE_LEAD_TIME`/`PASS_RECEIVE_ONLINE_DOT` — определены (Задачи 1/3), используются в вызовах.

**Открытые моменты для ручной приёмки:** `PASS_GROUND_MIN_SPEED`, `PASS_GROUND_MAX_TRAVEL_TIME`, `PASS_GROUND_LIFT`, `PASS_RECEIVE_LEAD_TIME`, `PASS_RECEIVE_ONLINE_DOT`, оффсеты поддержки — тюнинг-старт, финализируются живьём.

# Второй вратарь (team_1) + обобщение singleton `_keeper` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить вратаря team_1 в ворота Away (+Z) и заменить singleton `_keeper`/`_keeper_brain` на per-goal резолв, чтобы каждый стандарт находил вратаря нужных ворот.

**Architecture:** `keeper_ai.gd` уже сторона-агностичен (всё из `goal_line_z`). Обобщаем `_setup_keeper()` до `(team, goal_line_z, kit_color)`, спавним двух вратарей, добавляем хелпер `_keeper_at(goal_line_z)` (резолв защищающей команды по `attack_z_sign`). Заморозка/сброс/подбор/контакт переводим на группу `role_gk`; контроллеры резолвят своего вратаря в `start()`; singleton удаляется. Рефактор инкрементальный — на каждом шаге сцена компилится и грузится.

**Tech Stack:** Godot 4.7 / GDScript. Тесты — headless `tests/check_*.gd` (extends SceneTree, печатают `CHECK PASS`/`CHECK FAIL`, exit 0/1).

## Global Constraints

- **Нет lint/CI** — валидация только Godot headless. Экзе: `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`.
- **Godot часто стартует >120с** — headless-прогоны запускать в фоне, не чейнить несколько в одну команду.
- **Baseline-категории ошибок сцены** (НЕ регрессии, дифф по категории, не по числу): `!is_inside_tree()`, `states.has(p_name)`, transition-duplicate, `Cannot get class 'WorldEnvironment3D'`.
- **`keeper_ai.gd` НЕ трогаем** — он уже сторона-агностичен.
- **Отвечать/комментировать по-русски.** Коммиты подписывать `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Тип-геттер-гочи (CLAUDE.md):** `var x := body.brain()` на переменной статического типа `CharacterBody3D` НЕ компилится («cannot infer type»). Присваивание в явно типизированную переменную (`_keeper_brain = body.brain() if ...`) — компилится (так уже сделано в контроллерах). В тестах для локалов использовать явный тип: `var k: Node = _mm._keeper_at(...)`.

## Файловая структура

- **Modify:** `scripts/match/match_manager.gd` — `_setup_keeper` (обобщить), `_keeper_at` (создать), спавн двух вратарей, `_set_ai_frozen`, `_handle_dribbling`, `_reset_ball`, ball-contact, referee tdn, дебаг-клавиши, удаление полей `_keeper`/`_keeper_brain`.
- **Modify:** `scripts/match/penalty_controller.gd`, `free_kick_controller.gd`, `corner_controller.gd`, `goal_kick_controller.gd` — убрать `keeper` из `setup()`, резолвить вратаря в `start()`.
- **Create:** `tests/check_two_keepers.gd` — спавн обоих вратарей, `_keeper_at`, freeze/reset пропускают вратарей.

---

### Task 1: Два вратаря + хелпер `_keeper_at`

Обобщить `_setup_keeper`, заспавнить team_1-вратаря, добавить резолв. Singleton `_keeper`/`_keeper_brain` пока СОХРАНЯЕМ (наполняем из team_2-вратаря) — обратная совместимость, чтобы остальные 27 ссылок не сломались до Задач 2–3.

**Files:**
- Modify: `scripts/match/match_manager.gd` (`_setup_keeper` ~789–827, вызов ~140, новый `_keeper_at`)
- Test: `tests/check_two_keepers.gd` (создать)

**Interfaces:**
- Produces: `MatchManager._keeper_at(goal_line_z: float) -> CharacterBody3D` — вратарь защищающей команды; `MatchManager._setup_keeper(team: Team, goal_line_z: float, kit_color: Color) -> CharacterBody3D`.
- Consumes: `Team.keeper() -> CharacterBody3D`, `Team.attack_z_sign: float`, `Team.team_group: StringName` (существуют).

- [ ] **Step 1: Написать падающий тест `tests/check_two_keepers.gd`**

```gdscript
extends SceneTree
## Headless: оба вратаря спавнятся у своих ворот; _keeper_at резолвит защищающую команду;
## группа role_gk содержит ровно двоих. (Задача 2 дополнит freeze/reset-проверками.)

var _mm: Node
var _elapsed: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < 0.3:
		return false   # ждём _ready + спавн
	var gks := _mm.get_tree().get_nodes_in_group("role_gk")
	if gks.size() != 2:
		print("CHECK FAIL: role_gk = ", gks.size(), " (ожидалось 2)"); quit(1); return true
	var fl: float = _mm.field_length
	var k_home: Node = _mm._keeper_at(-fl)   # ворота Home (-Z) защищает team_2
	var k_away: Node = _mm._keeper_at(fl)    # ворота Away (+Z) защищает team_1
	if k_home == null or k_away == null:
		print("CHECK FAIL: _keeper_at вернул null (home=", k_home, " away=", k_away, ")"); quit(1); return true
	if not k_home.is_in_group("team_2"):
		print("CHECK FAIL: вратарь у -Z не team_2"); quit(1); return true
	if not k_away.is_in_group("team_1"):
		print("CHECK FAIL: вратарь у +Z не team_1"); quit(1); return true
	if k_home.global_position.z > 0.0 or k_away.global_position.z < 0.0:
		print("CHECK FAIL: вратари не у своих ворот (z_home=", k_home.global_position.z,
			" z_away=", k_away.global_position.z, ")"); quit(1); return true
	print("CHECK PASS: two keepers (spawn + _keeper_at)")
	quit(0)
	return true
```

- [ ] **Step 2: Прогнать тест — убедиться, что падает**

Run (в фоне): `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_two_keepers.gd"`
Expected: FAIL — `_keeper_at` ещё не существует (ошибка «Invalid call ... _keeper_at») либо `role_gk = 1`.

- [ ] **Step 3: Обобщить `_setup_keeper` — принимать `(team, goal_line_z, kit_color)`, вернуть тело**

В `scripts/match/match_manager.gd` заменить сигнатуру и первые строки `_setup_keeper` (было `func _setup_keeper() -> void:` с локальным `var goal_line_z := -field_length` и хардкодом team_2/зелёного):

```gdscript
## Вратарь team в воротах у goal_line_z (сторона-агностичен: keeper_ai всё выводит из goal_line_z).
func _setup_keeper(team: Team, goal_line_z: float, kit_color: Color) -> CharacterBody3D:
	var into_field := 1.0 if goal_line_z < 0.0 else -1.0
	var cfg := PlayerConfig.new()
	cfg.team_group = team.team_group
	cfg.role = PlayerConfig.Role.GK
	cfg.kit_color = kit_color
	cfg.spawn_pos = Vector3(0, 0.5, goal_line_z + into_field * 0.5)
	cfg.display_name = "Keeper_" + str(team.team_group)
	cfg.ai_script = preload("res://scripts/ai/keeper_ai.gd")
	cfg.connect_action_signals = false        # keeper_ai сам коннектит visual.action_contact
	cfg.locomotion_style = PlayerVisual.LOCO_STYLE_KEEPER
	var k := PlayerFactory.spawn(cfg, team)
```

Затем в конце тела `_setup_keeper` заменить `_keeper = k` / `_keeper_brain = kb` на возврат тела:

```gdscript
	kb.goal_line_z = goal_line_z
	kb.save_area = save_area
	kb.hold_point = hold_point
	kb.manager = self
	return k
```

(Средняя часть — создание `SaveArea`/`HoldPoint`/`var kb: Node = k.brain()` — БЕЗ изменений.)

- [ ] **Step 4: Заспавнить обоих вратарей; singleton наполнить из team_2**

Заменить вызов `_setup_keeper()` (строка ~140) на:

```gdscript
	_keeper = _setup_keeper(_team_away, -field_length, Color(0.15, 0.7, 0.15))   # team_2, зелёный (как было)
	_keeper_brain = _keeper.brain()
	_setup_keeper(_team_home, field_length, Color(0.85, 0.55, 0.1))              # team_1, оранжевый (новый)
```

(Поля `var _keeper`/`var _keeper_brain` пока НЕ удаляем — их снимет Задача 3.)

- [ ] **Step 5: Добавить хелпер `_keeper_at`**

Рядом с `_setup_keeper` в `scripts/match/match_manager.gd` добавить:

```gdscript
## Вратарь команды, ЗАЩИЩАЮЩЕЙ ворота у goal_line_z. Защищающая команда — та, чей
## attack_z_sign == -signf(goal_line_z) (team_1 атакует -Z → защищает +Z; team_2 наоборот).
## Без хардкода стороны/команды. null, если у нужной команды нет вратаря.
func _keeper_at(goal_line_z: float) -> CharacterBody3D:
	var want_sign := -signf(goal_line_z)
	if is_equal_approx(_team_home.attack_z_sign, want_sign):
		return _team_home.keeper()
	if is_equal_approx(_team_away.attack_z_sign, want_sign):
		return _team_away.keeper()
	return null
```

- [ ] **Step 6: Прогнать тест — убедиться, что проходит**

Run (в фоне): `& "...Godot...console.exe" --path "...OpenFootball" --headless -s "res://tests/check_two_keepers.gd"`
Expected: `CHECK PASS: two keepers (spawn + _keeper_at)`

- [ ] **Step 7: Baseline-валидация сцены (два вратаря не сломали загрузку)**

Run (в фоне): `& "...Godot...console.exe" --path "...OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: только baseline-категории ошибок (см. Global Constraints). Новых `SCRIPT ERROR`/`Parse Error` нет. (Счётчик `states.has`/transition вырастет — теперь ДВА `PlayerVisual`-вратаря; это ожидаемо, дифф по категории.)

- [ ] **Step 8: Commit**

```bash
git add scripts/match/match_manager.gd tests/check_two_keepers.gd tests/check_two_keepers.gd.uid
git commit -m "feat(keeper): спавн двух вратарей + _keeper_at резолв (singleton пока жив)"
```

---

### Task 2: Заморозка / подбор / сброс / контакт — по группе `role_gk`

Перевести per-frame и событийные пути с `== _keeper` на группу `role_gk`, чтобы ОБА вратаря самоуправлялись. Это снимает ссылки на `_keeper` в строках 535, 750, 1251, 2077–2079, 2147.

**Files:**
- Modify: `scripts/match/match_manager.gd` (`_set_ai_frozen` ~769, вызовы ~535/750/2147, `_handle_dribbling` ~1251, `_reset_ball` ~2100, ball-contact ~2077)
- Test: `tests/check_two_keepers.gd` (дополнить)

**Interfaces:**
- Consumes: `MatchManager._keeper_at`, группа `role_gk` (из Задачи 1).
- Produces: `MatchManager._set_ai_frozen(on: bool) -> void` (без параметра `keep_active`).

- [ ] **Step 1: Дополнить тест — freeze и reset пропускают ОБОИХ вратарей**

В `tests/check_two_keepers.gd` заменить финальный блок (`print("CHECK PASS: two keepers...")` … `quit(0)`) на две новые проверки перед PASS:

```gdscript
	# --- Задача 2: заморозка ИИ НЕ трогает вратарей ---
	_mm._set_ai_frozen(true)
	if not _mm._ai_of(k_home).is_physics_processing():
		print("CHECK FAIL: заморозка вырубила team_2-вратаря"); quit(1); return true
	if not _mm._ai_of(k_away).is_physics_processing():
		print("CHECK FAIL: заморозка вырубила team_1-вратаря"); quit(1); return true
	_mm._set_ai_frozen(false)

	# --- Задача 2: _reset_ball НЕ телепортит вратарей (players() включает team_1-вратаря) ---
	var moved := Vector3(5.0, 0.5, 40.0)
	k_away.global_position = moved
	_mm._reset_ball()
	if k_away.global_position.distance_to(moved) > 0.1:
		print("CHECK FAIL: _reset_ball сдвинул team_1-вратаря с ", moved,
			" на ", k_away.global_position); quit(1); return true

	print("CHECK PASS: two keepers + freeze/reset skip role_gk")
	quit(0)
	return true
```

- [ ] **Step 2: Прогнать тест — убедиться, что падает**

Run (в фоне): `& "...Godot...console.exe" --path "...OpenFootball" --headless -s "res://tests/check_two_keepers.gd"`
Expected: FAIL — либо `_set_ai_frozen(true)` вырубает вратаря (пока сигнатура с `keep_active=null` и исключает лишь одного), либо `_reset_ball` телепортит team_1-вратаря (через `players()`).

- [ ] **Step 3: `_set_ai_frozen` — пропускать `role_gk`, убрать параметр `keep_active`**

В `scripts/match/match_manager.gd` заменить сигнатуру и цикл `_set_ai_frozen`:

```gdscript
func _set_ai_frozen(on: bool) -> void:
	var bodies := get_tree().get_nodes_in_group("team_1")
	bodies += get_tree().get_nodes_in_group("team_2")
	for n in bodies:
		if not is_instance_valid(n) or n.is_in_group("role_gk"):
			continue   # вратари (role_gk) НИКОГДА не трогаем — сами управляют своим локом/мотором
		if on and n == controlled_player:
			continue
		_ai_of(n).set_physics_process(not on)
		var m := PlayerMotor.find_on(n)
		if m != null:
			m.set_control_locked(on)
			if on:
				m.set_move_intent(Vector3.ZERO)
		if on:
			for c in n.get_children():
				if c is PlayerVisual:
					c.cancel_action()
					c.recover()
					break
```

- [ ] **Step 4: Обновить вызовы `_set_ai_frozen` (убрать `_keeper`-аргумент)**

Три вызова:
- строка ~535: `_set_ai_frozen(true, _keeper)` → `_set_ai_frozen(true)`
- строка ~750: `_set_ai_frozen(not on, _keeper)` → `_set_ai_frozen(not on)`
- строка ~2147: `_set_ai_frozen(false, _keeper)` → `_set_ai_frozen(false)`

- [ ] **Step 5: `_handle_dribbling` подбор — пропускать `role_gk`**

В `scripts/match/match_manager.gd` строка ~1251, в цикле подбора бесхозного мяча:

```gdscript
	for p in pickers:
		if not is_instance_valid(p) or p.is_in_group("role_gk"):
			continue
```

(было `or p == _keeper`.)

- [ ] **Step 6: `_reset_ball` — исключить обоих вратарей**

В `scripts/match/match_manager.gd` строка ~2100 заменить перебор:

```gdscript
	# Вратари (role_gk) НЕ сбрасываются — держат свои позиции через keeper_ai. outfield() их исключает.
	for body in _team_home.outfield() + _team_away.outfield():
		if is_instance_valid(body):
			body.global_position = body.get_meta(&"home_pos", body.global_position)
```

(было `_team_home.players() + _team_away.outfield()` — `players()` включал team_1-вратаря.)

- [ ] **Step 7: Ball-contact — диспетч на коснувшегося вратаря по группе**

В `scripts/match/match_manager.gd` строки ~2077–2079 заменить:

```gdscript
	if body.is_in_group("role_gk") and body.has_method(&"brain"):
		var kb: Node = body.brain()
		if kb != null and kb.has_method(&"on_ball_contact"):
			kb.on_ball_contact()
```

(было `if body == _keeper and _keeper_brain != null and _keeper_brain.has_method(&"on_ball_contact"): _keeper_brain.on_ball_contact()`.)

- [ ] **Step 8: Прогнать тест — убедиться, что проходит**

Run (в фоне): `& "...Godot...console.exe" --path "...OpenFootball" --headless -s "res://tests/check_two_keepers.gd"`
Expected: `CHECK PASS: two keepers + freeze/reset skip role_gk`

- [ ] **Step 9: Commit**

```bash
git add scripts/match/match_manager.gd tests/check_two_keepers.gd
git commit -m "refactor(keeper): freeze/подбор/сброс/контакт по группе role_gk (оба вратаря)"
```

---

### Task 3: Контроллеры резолвят вратаря в `start()`; удалить singleton

Убрать `keeper` из `setup()` четырёх контроллеров, резолвить нужного вратаря в `start()`, обновить referee tdn и дебаг-клавиши, удалить поля `_keeper`/`_keeper_brain` менеджера. После этой задачи singleton больше нет.

**Files:**
- Modify: `scripts/match/penalty_controller.gd` (~43 setup, ~71 start_single), `free_kick_controller.gd` (~48 setup, ~61 start), `corner_controller.gd` (~50 setup, ~63 start), `goal_kick_controller.gd` (~40 setup, ~52 start)
- Modify: `scripts/match/match_manager.gd` (setup-вызовы ~149–161, tdn ~179, дебаг-клавиши ~1027–1064, удалить поля ~59–60, убрать `_keeper=` из `_ready`)

**Interfaces:**
- Consumes: `MatchManager._keeper_at(goal_line_z)` (Задача 1); `Player.brain() -> Node`.
- Produces: контроллеры `setup(manager, ball, camera_pivot, power_bar)` (без `keeper`).

- [ ] **Step 1: penalty_controller — убрать `keeper` из setup, резолвить в start_single**

`scripts/match/penalty_controller.gd`, `setup` (строка 43): убрать последний параметр и две строки кеша.
```gdscript
func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar
```
(Удалить строки `_keeper = keeper` и `_keeper_brain = keeper.brain() if ...`.)

В `start_single`, сразу после `_goal_line_z = goal_line_z` (строка 75), вставить:
```gdscript
	_keeper = _manager._keeper_at(goal_line_z)
	_keeper_brain = _keeper.brain() if _keeper != null and _keeper.has_method(&"brain") else null
```

- [ ] **Step 2: free_kick_controller — то же**

`scripts/match/free_kick_controller.gd`, `setup` (строка 48): убрать `keeper`-параметр и кеш (как в Step 1).
В `start`, после `_goal_line_z = goal_line_z` (строка 65), вставить тот же резолв:
```gdscript
	_keeper = _manager._keeper_at(goal_line_z)
	_keeper_brain = _keeper.brain() if _keeper != null and _keeper.has_method(&"brain") else null
```

- [ ] **Step 3: corner_controller — то же**

`scripts/match/corner_controller.gd`, `setup` (строка 50): убрать `keeper`-параметр и кеш.
В `start`, после `_goal_line_z = goal_line_z` (строка 67), вставить тот же резолв:
```gdscript
	_keeper = _manager._keeper_at(goal_line_z)
	_keeper_brain = _keeper.brain() if _keeper != null and _keeper.has_method(&"brain") else null
```

- [ ] **Step 4: goal_kick_controller — вратарь = сам бьющий (kicker)**

`scripts/match/goal_kick_controller.gd`, `setup` (строка 40): убрать `keeper`-параметр и кеш.
В `start`, сразу после `_kicker = kicker` (строка 55), вставить (здесь бьющий И ЕСТЬ вратарь):
```gdscript
	_keeper = kicker
	_keeper_brain = kicker.brain() if kicker != null and kicker.has_method(&"brain") else null
```

- [ ] **Step 5: Обновить setup-вызовы менеджера (убрать `_keeper`-аргумент)**

`scripts/match/match_manager.gd`, строки 149/153/157/161 — убрать последний аргумент `_keeper`:
```gdscript
	_penalty.setup(self, ball, camera_pivot, power_bar)
	...
	_free_kick.setup(self, ball, camera_pivot, power_bar)
	...
	_corner.setup(self, ball, camera_pivot, power_bar)
	...
	_goal_kick.setup(self, ball, camera_pivot, power_bar)
```

- [ ] **Step 6: referee tdn — из ростера, не из `_keeper`**

`scripts/match/match_manager.gd`, строки 177–179 — заменить:
```gdscript
	# team_defending_neg: команда, защищающая ворота на -Z = та, чей attack_z_sign > 0
	# (team_2 при текущей расстановке). Выводим из ростера, без singleton-вратаря.
	var tdn := 2 if _team_away.attack_z_sign > 0.0 else 1
	_referee.setup(self, ball, tdn)
```

- [ ] **Step 7: Дебаг-клавиши — цель через `_keeper_at(-field_length)`**

`scripts/match/match_manager.gd`, блок ~1027–1064. Заменить проверки `_keeper != null` и цель `_keeper_brain.goal_line_z` / `_keeper` на резолв team_2-вратаря (−Z), как было по смыслу:

- penalty (P), строки 1027–1028:
```gdscript
	if Input.is_action_just_pressed(&"penalty_debug") and _keeper_at(-field_length) != null and not _celebrating:
		_penalty.start_single(controlled_player, -field_length)
		return
```
- keeper-dive (K), строки 1033–1039:
```gdscript
	if Input.is_action_just_pressed(&"keeper_dive_debug") and _keeper_at(-field_length) != null and not _celebrating:
		var kicker_rng := RandomNumberGenerator.new()
		kicker_rng.randomize()
		_penalty.start_single(controlled_player, -field_length,
			AIKickerIntent.new(kicker_rng),
			SetPiecePresentation.new(SetPiecePresentation.Role.KEEPER),
			HumanKeeperIntent.new({"aim_lat": [&"move_left", &"move_right"], "aim_vert": [&"move_forward", &"move_back"]}))
		return
```
- free_kick (F), строки 1046–1047:
```gdscript
	if Input.is_action_just_pressed(&"free_kick_debug") and _keeper_at(-field_length) != null and not _celebrating:
		_free_kick.start(controlled_player, -field_length)
		return
```
- corner (C), строки 1054–1055:
```gdscript
	if Input.is_action_just_pressed(&"corner_debug") and _keeper_at(-field_length) != null and not _celebrating:
		_corner.start(controlled_player, -field_length)
		return
```
- goal_kick (G), строки 1063–1064 (бьющий = team_2-вратарь):
```gdscript
	if Input.is_action_just_pressed(&"goal_kick_debug") and _keeper_at(-field_length) != null and not _celebrating:
		_goal_kick.start(_keeper_at(-field_length), -field_length)
		return
```

- [ ] **Step 8: Удалить поля singleton + присвоение в `_ready`**

`scripts/match/match_manager.gd`:
- Удалить строки 59–60: `var _keeper: CharacterBody3D` и `var _keeper_brain: Node`.
- В `_ready` (Задача 1 Step 4) убрать присвоение singleton — оставить только спавн:
```gdscript
	_setup_keeper(_team_away, -field_length, Color(0.15, 0.7, 0.15))
	_setup_keeper(_team_home, field_length, Color(0.85, 0.55, 0.1))
```

- [ ] **Step 9: Grep-проверка — ни одной ссылки на `_keeper`/`_keeper_brain` в менеджере**

Run: `grep -n "_keeper\b\|_keeper_brain" scripts/match/match_manager.gd`
Expected: пусто (все ссылки заменены; `_keeper_at`/`_setup_keeper`/`_keeper_marker` в контроллерах — другие символы, тут их нет).

- [ ] **Step 10: Прогнать ключевые headless-тесты**

Run (каждый в фоне, по одному):
- `check_two_keepers.gd` → `CHECK PASS`
- `check_penalty_flow.gd` → `CHECK PASS` (резолвит `_keeper_at(-field_length)` в start_single)
- `check_goal_kick_flow.gd` → `CHECK PASS`
- `check_penalty_keeper_line.gd` → `CHECK PASS`
- `check_setpiece_goal_freeze.gd` → `CHECK PASS`

Команда: `& "...Godot...console.exe" --path "...OpenFootball" --headless -s "res://tests/<имя>.gd"`
Expected: все `CHECK PASS`. Если тест конструирует контроллер напрямую и звал `setup(..., keeper)` — обновить его вызов (убрать аргумент).

- [ ] **Step 11: Baseline-валидация сцены**

Run (в фоне): `& "...Godot...console.exe" --path "...OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: только baseline-категории. Новых `SCRIPT ERROR`/`Parse Error` нет.

- [ ] **Step 12: Commit**

```bash
git add scripts/match/match_manager.gd scripts/match/penalty_controller.gd scripts/match/free_kick_controller.gd scripts/match/corner_controller.gd scripts/match/goal_kick_controller.gd
git commit -m "refactor(keeper): контроллеры резолвят вратаря в start(); удалить singleton _keeper"
```

---

## Self-Review (заполняется автором плана — уже проверено)

- **Покрытие спека:** спавн двух вратарей (T1), `_keeper_at` (T1), referee tdn (T3), контроллеры-резолв (T3), freeze/подбор/сброс/контакт по `role_gk` (T2), удаление singleton (T3), тест `check_two_keepers` (T1+T2), baseline (T1/T3). Non-goals (ИИ-удар, авто-диспетч) — не затронуты. ✓
- **Плейсхолдеров нет** — весь код приведён.
- **Типы согласованы:** `_keeper_at(...) -> CharacterBody3D`, `_setup_keeper(...) -> CharacterBody3D`, `_set_ai_frozen(on)` — используются одинаково во всех задачах и тесте.

## Замечания по фичу (только человек за игрой)

- team_1-вратарь реально тащит атаки team_2-ИИ, корректно ловит/выбивает у ворот Away, не мешает человеку — headless не драйвит рендер/физику приземления.
- Два вратаря визуально различимы (зелёный −Z / оранжевый +Z).

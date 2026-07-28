# Управляемый вратарь — План 2: HANDS-ядро + OUTFIELD — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Сделать вратаря управляемым актёром: при ловле мяча управление переходит человеку (team_1), вратарь бегает с мячом в штрафной и сам вводит мяч в игру (рука A / вынос к центру X / направленный вынос B / дроп-к-ногам Y → полевой режим), с таймером 6 секунд и правилом бэк-паса. Всё через шов `KeeperHandsIntent` (Human=Input, AI=заглушка), диспетч в одном месте.

**Architecture:** Расширяем `keeper_ai.State` двумя режимами. **HANDS** (мяч в руках): `keeper_ai` — единственный владелец тела, читает `KeeperHandsIntent` каждый кадр (движение в штрафной + раздача), заменяет авто `HOLD→THROWING`. **OUTFIELD** (мяч в ногах): `keeper_ai` глушит свою логику early-return (как `_goalkick_mode`), менеджер ведёт тело как обычного `controlled_player` (переиспользуем весь полевой дриблинг/пас/удар). Источник намерения и презентация выбираются диспетчером `MatchManager._keeper_hands_dispatch(keeper)` — единственное место, где хардкодится «team_1 = локальный человек». Вся математика раздачи — чистые функции `KeeperPlayLogic` (готовы в Плане 1) + переиспользование `PassSystem`/`KeeperLogic`. Флаг бэк-паса `ball._pass_from_team` (готов в Плане 1) читается в точках ловли.

**Tech Stack:** Godot 4.7 / GDScript. Тесты — headless `tests/check_*.gd` (extends SceneTree, печатают `CHECK PASS`/`CHECK FAIL`, exit 0/1). Flow-тесты гоняют реальный `match.tscn` с фейковым `KeeperHandsIntent`-сабклассом (как intent-seam тесты сет-писов).

## Global Constraints

- **Нет lint/CI** — валидация только Godot headless. Экзе: `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`.
- **Godot часто стартует >120с** — headless-прогоны в фоне с `timeout 120`, не чейнить несколько тяжёлых прогонов в одну команду.
- **Новый `class_name` не виден до `--import`** — после создания файла с `class_name` (в этом плане новых `class_name` нет — все классы созданы в Плане 1) прогнать `--headless --import` до тестов. Новые `.uid` и `.godot/global_script_class_cache.cfg` коммитить вместе (они отслеживаются в репо).
- **Baseline-категории ошибок сцены** (НЕ регрессии, дифф по КАТЕГОРИИ/тексту, не по счётчику): `!is_inside_tree()`, `states.has(p_name)`, transition-duplicate (`transitions[i].from == ...`), `Cannot get class 'WorldEnvironment3D'`.
- **Чистые `*_logic.gd` НИКОГДА не читают `FootballConstants`** — тюнинг параметрами (`KeeperPlayLogic`/`PassSystem`/`KeeperLogic` уже такие).
- **Тип-геттер-гоча:** `var x := node.method()` на статически-типизированной переменной, где метода нет в статическом типе (`_manager: Node`, `_body: CharacterBody3D` без `brain()` в статическом типе), НЕ компилится («cannot infer the type»). Объявлять явным типом: `var x: PlayerVisual = _manager._player_visual(...)`. В `keeper_ai` тело — `_body` (тип `CharacterBody3D` по `Brain._body`); менеджер — `manager` (тип `Node`), все `manager.foo()` динамические (Variant) — это ок.
- **`keeper_ai` тело читается через `_body`** (кэш `Brain._body := get_parent()`), НИКОГДА через `self`/`global_position` (это укажет на `Brain`-узел, не тело). Движение — через `_motor()` (`PlayerMotor.find_on(_body)`).
- **Флейки headless** (см. CLAUDE.md): launch-зависимые flow-тесты (ждут `action_contact` фиксированный бюджет кадров) intermittently дают `launched=false`. Гонять 2–3×; регрессию подтверждать диффом против baseline (откатить правку, прогнать заново), а не одним фейлом.
- Отвечать/комментировать по-русски. Коммиты подписывать `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## As-built (проверено разведкой перед планом — на что опираемся)

- **В `match_manager` НЕТ полей `_keeper`/`_keeper_brain`** (дизайн «без singleton-вратаря»). Вратарь берётся через `_keeper_at(goal_line_z) -> CharacterBody3D` (строки ~826–835) или `_team_home.keeper()`/`_team_away.keeper()`. Мозг — `body.brain()` live.
- **`on_ball_contact` wiring** (`_on_ball_collision`, ~2085–2089): гейт `body.is_in_group("role_gk") and body.has_method("brain")` → `body.brain().on_ball_contact()`. НЕ `n == _keeper`.
- **Оба вратаря спавнятся** (team_1 и team_2, `_setup_keeper` строки ~138–139). Управляемый человеком — **team_1**.
- **Авто-свап `controlled_player`** (`_physics_process` ~1104–1110): на любого team_1-дриблера, БЕЗ исключения `role_gk`. Значит team_1-вратарь при ловле (`ball.dribbler == keeper`, group team_1) уже сейчас авто-становится `controlled_player`. `_manual_swap_cooldown` защищает от отскока.
- **Голубой маркер** — `_controlled_marker: Polygon2D` (не 3D-конус), позиционируется над `controlled_player` в `_process` (~990–996), цвет `Color(0.3,0.6,1.0)`. Скрывается для `_goal_kick_active`/`_throw_in_active`/penalty-AI (~987). Для управляемого вратаря скрывать НЕ надо — keeper становится `controlled_player`, маркер над ним появляется сам.
- **`power_bar: ProgressBar`** (`$HUD/PowerBar`). Менеджерский блок заряда (`_process` ~1000–1020) гейтится `not _penalty_active and ... and _is_charging() and _charge_player == controlled_player`. Вратарский заряд идёт в `keeper_ai` — менеджерский блок его НЕ покажет; нужен отдельный путь (Задача 5).
- **`_handle_player_input(delta)`** (~1269): двигает `controlled_player` мотором (camera-relative, sprint на ~1373–1378: `motor.set_move_intent(dir, sprint_scale)`). НЕТ гейта `role_gk` — если `controlled_player`=keeper, менеджер будет двигать его. Ранние-return: `fallen`, tackle, null, `_action_executor` гейт (~1286).
- **`_handle_dribbling`** исключает `role_gk` из ПОДБОРА бесхозного мяча (~1259–1260), но НЕ из ведения своего (`ball.dribbler == keeper` ветка ~1232 работает). Значит OUTFIELD-вратарь с мячом у ног ведётся полевым путём без правок дриблинга.
- **`_set_ai_frozen`** (~768–787): `role_gk` пропускается всегда (вратарь сам владеет локом). `controlled_player` пропускается только на заморозке.
- **`_ai_of(body)`** (~1664): `body.brain()` или тело.
- **`_sync_ai_controllers()`** (~1182): ставит `ai.controlled_player` всем team_1 с этим полем. **`assign_controlled_player(body)`** (~736): `controlled_player=body` + `_sync_ai_controllers()`. **`begin_pass_receive(receiver)`** (~723): `_receive_active=true`,`_receiver`,`_receive_timer`.
- **Диспетч intent+presentation (образец, `penalty_controller`)**: поле `_intent: KickerIntent`/`_presentation: SetPiecePresentation`; `_default_intent()` → `HumanKickerIntent.new({cfg})`; `_presentation = SetPiecePresentation.new(Role.KICKER)` в setup, override если передан; чтение — `owns_hud()`/`owns_camera()`. `SetPiecePresentation`: `Role{NONE,KICKER,KEEPER,WALL}`, `owns_hud()==Role.KICKER`, `owns_camera()==Role!=NONE`.
- **`keeper_ai` точки ловли, ведущие сейчас в `_to_hold()`→HOLD→авто-`_to_overhand_throw()`**: `_dive()` (пойман в нырке, ~471–474), `_catching()` (~920–922), а также `_to_hold` из `_hold`-цепочки. Вход в HANDS = перенаправить эти точки в новый `_enter_hands()` вместо `_to_hold()`.
- **`keeper_ai._on_visual_contact(action)`** (~790): диспетчер `action_contact` по клипам раздачи; ранний-return при `_goalkick_mode`. Сюда добавятся HANDS-клипы.
- **Существующие блоки раздачи для переиспользования**: `_do_overhand_throw()` (дуга к центру, `KEEPER_THROW_PEAK/DISTANCE`, ~613), `_do_pass_roll()` (раскат низом, `KeeperLogic.roll_speed`, `launch(flat=true)`, ~809), `_do_clear()` (drop-kick, `KEEPER_CLEAR_SPEED/LIFT`, ~828).

## Файловая структура

- **Modify:** `scripts/data/football_constants.gd` — новые `KEEPER_*` константы (KEEPER-секция).
- **Modify:** `scripts/match/match_manager.gd` — InputMap-действия (`_setup_inputs`); `_keeper_hands_dispatch()`; хелперы `keeper_handoff_control()`/`_keeper_hands_owns_hud`; HANDS-заряд power-bar в `_process`; гейт «не двигать вратаря-в-руках» в `_handle_player_input`.
- **Modify:** `scripts/ai/keeper_ai.gd` — `State.HANDS`/`State.OUTFIELD`; `_enter_hands()`/`_hands()`; раздача-обёртки A/X/B/Y; 6 сек; `is_hands_active()`/`hands_charge_ratio()`; OUTFIELD-глушение; бэк-пас консьюмер в точках ловли; перенаправление `_to_hold`-точек.
- **Use as-is (Плана 1):** `scripts/match/keeper_play_logic.gd`, `scripts/match/keeper_hands_intent.gd`, `human_keeper_hands_intent.gd`, `ai_keeper_hands_intent.gd`, `scripts/match/set_piece_presentation.gd`.
- **Create tests:** `tests/check_keeper_control_constants.gd`, `tests/check_keeper_hands_dispatch.gd`, `tests/check_keeper_hands_flow.gd`, `tests/check_keeper_six_second.gd`, `tests/check_keeper_backpass_outfield.gd`.

---

### Task 1: Новые KEEPER-константы + InputMap-действия вратаря

Константы тюнинга HANDS-раздачи и 6 сек + четыре InputMap-действия (пад A/X/B/Y + клавиатурные дубли), на которые сошлётся `HumanKeeperHandsIntent`-cfg (Задача 2). Мелко, фундамент, независимо проверяемо.

**Files:**
- Modify: `scripts/data/football_constants.gd` (KEEPER-секция, после `KEEPER_THROW_PEAK` ~443)
- Modify: `scripts/match/match_manager.gd` (`_setup_inputs`, словарь `actions` ~251–276)
- Test: `tests/check_keeper_control_constants.gd` (создать)

**Interfaces:**
- Produces: константы `KEEPER_DIST_CHARGE_MAX`, `KEEPER_HAND_THROW_CHARGE`, `KEEPER_HAND_ROLL_DIST`, `KEEPER_HAND_THROW_DIST`, `KEEPER_HANDS_MOVE_SPEED`, `KEEPER_SIX_SECOND_TIME`, `AI_KEEPER_THINK_TIME`; InputMap-действия `keeper_hand`, `keeper_clear_center`, `keeper_clear_directed`, `keeper_drop`.

- [ ] **Step 1: Написать падающий тест `tests/check_keeper_control_constants.gd`**

```gdscript
extends SceneTree
## Новые KEEPER-константы существуют и в разумных диапазонах.

func _initialize() -> void:
	var ok := true
	var checks := {
		"KEEPER_DIST_CHARGE_MAX": [0.2, 3.0],
		"KEEPER_HAND_THROW_CHARGE": [0.05, 1.0],
		"KEEPER_HAND_ROLL_DIST": [3.0, 25.0],
		"KEEPER_HAND_THROW_DIST": [10.0, 60.0],
		"KEEPER_HANDS_MOVE_SPEED": [0.3, 1.0],
		"KEEPER_SIX_SECOND_TIME": [5.0, 8.0],
		"AI_KEEPER_THINK_TIME": [0.0, 3.0],
	}
	for name in checks:
		if not (name in FootballConstants):
			print("CHECK FAIL: нет константы ", name); ok = false; continue
		var v: float = FootballConstants.get(name)
		var lo: float = checks[name][0]
		var hi: float = checks[name][1]
		if v < lo or v > hi:
			print("CHECK FAIL: ", name, "=", v, " вне [", lo, ",", hi, "]"); ok = false
	# Порог тап↔удержание < максимума заряда (иначе бросок недостижим).
	if FootballConstants.KEEPER_HAND_THROW_CHARGE >= FootballConstants.KEEPER_DIST_CHARGE_MAX:
		print("CHECK FAIL: THROW_CHARGE >= DIST_CHARGE_MAX"); ok = false
	# Банд броска дальше банда раската.
	if FootballConstants.KEEPER_HAND_THROW_DIST <= FootballConstants.KEEPER_HAND_ROLL_DIST:
		print("CHECK FAIL: THROW_DIST <= ROLL_DIST"); ok = false
	if ok:
		print("CHECK PASS: keeper control constants")
		quit(0)
	else:
		quit(1)
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `& "...Godot...console.exe" --path "...OpenFootball" --headless -s "res://tests/check_keeper_control_constants.gd"`
Expected: FAIL — констант ещё нет.

- [ ] **Step 3: Добавить константы в `football_constants.gd`**

После строки `const KEEPER_THROW_PEAK := 6.0 ...` (~443) добавить:
```gdscript

# Управляемый вратарь — HANDS-раздача (План 2).
const KEEPER_DIST_CHARGE_MAX := 0.7    # макс. время заряда дистанции (A/B), с
const KEEPER_HAND_THROW_CHARGE := 0.2  # заряд A < этого = тап (раскат низом), >= = удержание (бросок верхом), с
const KEEPER_HAND_ROLL_DIST := 12.0    # дальность раската низом рукой (тап A), м
const KEEPER_HAND_THROW_DIST := 30.0   # дальность броска верхом (удержание A) при полном заряде, м
const KEEPER_HANDS_MOVE_SPEED := 0.6   # доля LOCO_TOP_SPEED при беге с мячом в руках (медленнее полевого)
const KEEPER_SIX_SECOND_TIME := 6.0    # макс. удержание мяча в руках до принудительного выноса, с
const AI_KEEPER_THINK_TIME := 0.8      # пауза «обдумывания» ИИ-вратаря до выноса к центру, с
```

- [ ] **Step 4: Добавить InputMap-действия в `_setup_inputs`**

В словарь `actions` (`match_manager.gd` ~251–276), после строки `&"keeper_dive_debug": {...}` (~265) добавить:
```gdscript
		&"keeper_hand":          {"keys": [KEY_H], "buttons": [JOY_BUTTON_A], "axes": []},
		&"keeper_clear_center":  {"keys": [KEY_J], "buttons": [JOY_BUTTON_X], "axes": []},
		&"keeper_clear_directed":{"keys": [KEY_B], "buttons": [JOY_BUTTON_B], "axes": []},
		&"keeper_drop":          {"keys": [KEY_N], "buttons": [JOY_BUTTON_Y], "axes": []},
```
(Пад-кнопки A/X/B/Y — как в спеке; клавиши H/J/B/N — из свободных, дубли к паду. Дубли клавиш/кнопок между действиями движок допускает.)

- [ ] **Step 5: Прогнать — убедиться, что проходит**

Run (в фоне): та же команда, что в Step 2.
Expected: `CHECK PASS: keeper control constants`

- [ ] **Step 6: Baseline-валидация сцены (InputMap не сломал загрузку)**

Run (в фоне): `& "...Godot..." --path "...OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: в логе строка `Inputs setup OK`; только baseline-категории ошибок, новых `SCRIPT ERROR`/`Parse Error` нет.

- [ ] **Step 7: Commit**

```bash
git add scripts/data/football_constants.gd scripts/match/match_manager.gd tests/check_keeper_control_constants.gd
git commit -m "feat(keeper): KEEPER-константы HANDS-раздачи + InputMap-действия вратаря"
```

---

### Task 2: Диспетч `_keeper_hands_dispatch` + presentation + хелпер передачи управления

Единственное место хардкода «team_1 = локальный человек»: по вратарю возвращает `{intent, presentation}`. Плюс хелпер `keeper_handoff_control(point)` — передать управление ближайшему полевому team_1 (как приём паса), переиспущенный всеми раздачами. Пока НИКТО не зовёт (consumer — Задачи 3+). Юнит-тестируемо в изоляции.

**Files:**
- Modify: `scripts/match/match_manager.gd` (добавить методы; рядом с `assign_controlled_player` ~736 и `_ai_of` ~1664)
- Test: `tests/check_keeper_hands_dispatch.gd` (создать)

**Interfaces:**
- Consumes: `HumanKeeperHandsIntent`, `AIKeeperHandsIntent`, `SetPiecePresentation` (План 1); `assign_controlled_player`, `begin_pass_receive` (as-built).
- Produces:
  - `MatchManager._keeper_hands_dispatch(keeper: Node) -> Dictionary` — ключи `intent: KeeperHandsIntent`, `presentation: SetPiecePresentation`, `take_control: bool`.
  - `MatchManager.keeper_handoff_control(point: Vector3) -> void`.

- [ ] **Step 1: Написать падающий тест `tests/check_keeper_hands_dispatch.gd`**

```gdscript
extends SceneTree
## Диспетч вратарской раздачи: team_1 → Human+KICKER+take_control; team_2 → AI+NONE.
## Хелпер handoff передаёт управление ближайшему полевому team_1.

func _initialize() -> void:
	var mm = load("res://scenes/match.tscn").instantiate()
	root.add_child(mm)
	# Дать сцене осесть один физкадр не обязательно для чистого диспетча — тела уже заспавнены в _ready.
	call_deferred("_run", mm)

func _run(mm) -> void:
	var ok := true
	var k1 = mm._team_home.keeper()   # team_1
	var k2 = mm._team_away.keeper()   # team_2
	if k1 == null or k2 == null:
		print("CHECK FAIL: вратари не заспавнены"); quit(1); return

	var d1: Dictionary = mm._keeper_hands_dispatch(k1)
	if not (d1.intent is HumanKeeperHandsIntent):
		print("CHECK FAIL: team_1 не Human intent: ", d1.intent); ok = false
	if not d1.presentation.owns_hud():
		print("CHECK FAIL: team_1 presentation не владеет HUD"); ok = false
	if not d1.take_control:
		print("CHECK FAIL: team_1 take_control не true"); ok = false

	var d2: Dictionary = mm._keeper_hands_dispatch(k2)
	if not (d2.intent is AIKeeperHandsIntent):
		print("CHECK FAIL: team_2 не AI intent: ", d2.intent); ok = false
	if d2.presentation.owns_hud():
		print("CHECK FAIL: team_2 presentation ошибочно владеет HUD"); ok = false
	if d2.take_control:
		print("CHECK FAIL: team_2 take_control ошибочно true"); ok = false

	# handoff: ставим искусственную точку у одного из team_1 полевых, проверяем захват управления.
	var field1: Array = []
	for n in mm.get_tree().get_nodes_in_group("team_1"):
		if not n.is_in_group("role_gk"):
			field1.append(n)
	if field1.is_empty():
		print("CHECK FAIL: нет полевых team_1"); quit(1); return
	var target = field1[0]
	mm.keeper_handoff_control(target.global_position)
	if mm.controlled_player != target:
		print("CHECK FAIL: handoff не передал управление ближайшему: ", mm.controlled_player); ok = false

	if ok:
		print("CHECK PASS: keeper hands dispatch + handoff")
		quit(0)
	else:
		quit(1)
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `& "...Godot..." --path "...OpenFootball" --headless -s "res://tests/check_keeper_hands_dispatch.gd"`
Expected: FAIL — `_keeper_hands_dispatch`/`keeper_handoff_control` не существуют (`Invalid call`).

- [ ] **Step 3: Добавить диспетч и хелпер в `match_manager.gd`**

Рядом с `assign_controlled_player` (~736) добавить:
```gdscript
## Источник намерения + профиль презентации для вратаря в HANDS. ЕДИНСТВЕННОЕ место хардкода
## «team_1 = локальный человек»: swappable под ИИ-соперника/мультиплеер без правок keeper_ai.
## take_control=true → менеджер отдаёт управление вратарю (голубой маркер над ним, HUD-заряд).
func _keeper_hands_dispatch(keeper: Node) -> Dictionary:
	var is_local_human: bool = keeper != null and keeper.is_in_group("team_1")
	if is_local_human:
		var cfg := {
			"move_lat": [&"move_left", &"move_right"],
			"move_vert": [&"move_forward", &"move_back"],
			"aim_lat": [&"move_left", &"move_right"],
			"aim_vert": [&"move_forward", &"move_back"],
			"hand": &"keeper_hand",
			"clear_center": &"keeper_clear_center",
			"clear_directed": &"keeper_clear_directed",
			"drop": &"keeper_drop",
		}
		return {
			"intent": HumanKeeperHandsIntent.new(cfg),
			"presentation": SetPiecePresentation.new(SetPiecePresentation.Role.KICKER),
			"take_control": true,
		}
	return {
		"intent": AIKeeperHandsIntent.new(FootballConstants.AI_KEEPER_THINK_TIME),
		"presentation": SetPiecePresentation.new(SetPiecePresentation.Role.NONE),
		"take_control": false,
	}


## Передать управление ближайшему ПОЛЕВОМУ team_1 к точке (приземление выноса / позиция адресата),
## как приём паса: assign + begin_pass_receive (принимающий бежит на мяч). Вратарей исключаем.
func keeper_handoff_control(point: Vector3) -> void:
	var best: CharacterBody3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("team_1"):
		if not is_instance_valid(n) or n.is_in_group("role_gk"):
			continue
		var d: float = n.global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = n
	if best != null:
		assign_controlled_player(best)
		begin_pass_receive(best)
		_manual_swap_cooldown = 30
```

- [ ] **Step 4: Прогнать — убедиться, что проходит**

Run (в фоне, 2–3× при флейке загрузки сцены): та же команда, что в Step 2.
Expected: `CHECK PASS: keeper hands dispatch + handoff`

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_manager.gd tests/check_keeper_hands_dispatch.gd
git commit -m "feat(keeper): диспетч _keeper_hands_dispatch + presentation + keeper_handoff_control"
```

---

### Task 3: Вход в HANDS при ловле + движение в штрафной + гейт менеджера

`keeper_ai` получает `State.HANDS`: при ловле (вместо авто-`_to_hold`→throw) вратарь входит в HANDS, зовёт диспетч, читает `KeeperHandsIntent` — движение в штрафной (кламп) + держит мяч (idle_ball). Раздача пока НЕ реализована (кнопки no-op) — только вход, движение, `is_hands_active()`. Менеджер перестаёт двигать вратаря-в-руках (гейт), чтобы два владельца не дрались.

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (enum `State`; поля HANDS; `_enter_hands`/`_hands`; `is_hands_active`; перенаправить точки ловли; `match` в `_physics_process`)
- Modify: `scripts/match/match_manager.gd` (`_handle_player_input`: гейт role_gk-in-hands)
- Test: `tests/check_keeper_hands_flow.gd` (создать — на этой задаче проверяет только вход+движение; расширяется в Задачах 5–8)

**Interfaces:**
- Consumes: `_keeper_hands_dispatch` (Задача 2); `KeeperPlayLogic.clamp_to_penalty_area` (План 1); `KeeperHandsIntent.move_axis`.
- Produces: `keeper_ai.is_hands_active() -> bool`; `State.HANDS`; `_enter_hands()`.

- [ ] **Step 1: Написать падающий flow-тест `tests/check_keeper_hands_flow.gd`**

```gdscript
extends SceneTree
## Управляемый вратарь HANDS: ловля → HANDS (фейк-интент), движение в штрафной по move_axis.
## Фейк-интент скриптует KeeperHandsIntent без реального Input (как intent-seam тесты сет-писов).

class FakeHandsIntent extends KeeperHandsIntent:
	var mv := Vector2.ZERO
	var act := KeeperHandsIntent.Action.NONE
	func move_axis() -> Vector2: return mv
	func aim_axis() -> Vector2: return mv
	func held_action() -> int: return act

var _mm: Node
var _keeper: Node
var _brain: Node
var _fake: FakeHandsIntent
var _frames := 0
var _entered := false
var _start_pos := Vector3.ZERO

func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate()
	root.add_child(_mm)
	_fake = FakeHandsIntent.new()
	physics_frame.connect(_tick)

func _tick() -> void:
	_frames += 1
	if _frames == 5:
		_keeper = _mm._team_home.keeper()
		_brain = _keeper.brain()
		# Инжектируем фейк-интент: keeper_ai возьмёт его вместо диспетча (см. _enter_hands override-хук).
		_brain._hands_intent_override = _fake
		# Ставим мяч в руки вратаря и запускаем HANDS напрямую (минуя всю сейв-цепочку).
		_mm.ball.catch(_keeper, _brain.hold_point)
		_brain._enter_hands()
		return
	if _frames == 8:
		if not _brain.is_hands_active():
			print("CHECK FAIL: не вошёл в HANDS"); quit(1); return
		_entered = true
		_start_pos = _keeper.global_position
		_fake.mv = Vector2(1.0, 0.0)   # движение вбок (в штрафной)
		return
	if _frames == 40:
		var moved := _keeper.global_position.distance_to(_start_pos)
		if not _entered:
			print("CHECK FAIL: HANDS не активировался"); quit(1); return
		if moved < 0.3:
			print("CHECK FAIL: вратарь не двигался в HANDS по move_axis (moved=", moved, ")"); quit(1); return
		# Кламп: остался в штрафной по X (|x| <= полуширина).
		if absf(_keeper.global_position.x) > FootballConstants.PENALTY_AREA_WIDTH * 0.5 + 0.5:
			print("CHECK FAIL: вратарь вышел за штрафную по X: ", _keeper.global_position); quit(1); return
		print("CHECK PASS: keeper enters HANDS + moves in box")
		quit(0)
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `& "...Godot..." --path "...OpenFootball" --headless -s "res://tests/check_keeper_hands_flow.gd"`
Expected: FAIL — `_enter_hands`/`is_hands_active`/`_hands_intent_override` не существуют.

- [ ] **Step 3: Расширить enum и добавить поля HANDS в `keeper_ai.gd`**

Заменить строку enum (`~12`):
```gdscript
enum State { POSITION, DIVE, CATCHING, HOLD, DISTRIBUTE, PLACING, CARRY, FIELD_PASS, THROWING, HANDS, OUTFIELD }
```
Рядом с полями раздачи (после `_high_roll` ~34) добавить:
```gdscript
# HANDS-режим (мяч в руках, управляемый актёр — План 2).
var _hands_intent: KeeperHandsIntent = null
var _hands_presentation: SetPiecePresentation = null
var _hands_intent_override: KeeperHandsIntent = null   # тест инжектит фейк-интент, минуя диспетч
var _hands_take_control: bool = false
var _hands_timer: float = 0.0            # обратный отсчёт 6 секунд
var _hands_charging: bool = false
var _hands_charge: float = 0.0
var _hands_charge_action: int = KeeperHandsIntent.Action.NONE
```

- [ ] **Step 4: Добавить `_enter_hands`, `_hands`, `is_hands_active`, `hands_charge_ratio` в `keeper_ai.gd`**

Добавить (например после `_to_hold`/`_hold` ~580). Раздача A/X/B/Y пока — заглушки-комментарии (реализуются в Задачах 5–8); в этой задаче любое `held_action != NONE` просто игнорируется, кроме логирования:
```gdscript
## Мяч пойман → HANDS: спрашиваем менеджера, кто ведёт (диспетч), берём мяч в руки, стартуем 6 сек.
## Заменяет авто-цепочку _to_hold→_hold→_to_overhand_throw для управляемого вратаря.
func _enter_hands() -> void:
	_state = State.HANDS
	_hands_timer = FootballConstants.KEEPER_SIX_SECOND_TIME
	_hands_charging = false
	_hands_charge = 0.0
	_pass_through = false
	# Источник намерения + презентация: тест инжектит override; иначе диспетч менеджера.
	if _hands_intent_override != null:
		_hands_intent = _hands_intent_override
		_hands_presentation = SetPiecePresentation.new(SetPiecePresentation.Role.KICKER)
		_hands_take_control = true
	elif manager != null and manager.has_method(&"_keeper_hands_dispatch"):
		var d: Dictionary = manager._keeper_hands_dispatch(_body)
		_hands_intent = d.get("intent", null)
		_hands_presentation = d.get("presentation", null)
		_hands_take_control = d.get("take_control", false)
	# Управление человеку: keeper становится controlled_player (голубой маркер над ним сам появится).
	if _hands_take_control and manager != null and manager.has_method(&"assign_controlled_player"):
		manager.assign_controlled_player(_body)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)   # человек/ИИ теперь ДВИГАЕТ вратаря в штрафной (не вкопанно)
	var vis := _visual()
	if vis != null:
		vis.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)
		vis.play_oneshot(&"keeper_idle_ball")   # поза удержания (carry-бленд бега — План 3)


## Вратарь сейчас владеет мячом в руках (HANDS)? Менеджер использует, чтобы НЕ двигать его своим
## полевым вводом (в HANDS телом владеет keeper_ai через KeeperHandsIntent).
func is_hands_active() -> bool:
	return _state == State.HANDS


## Текущий заряд дистанции (A/B) как доля [0..1], либо -1 если не заряжает. Менеджер рисует power-bar.
func hands_charge_ratio() -> float:
	if not _hands_charging:
		return -1.0
	return clampf(_hands_charge / FootballConstants.KEEPER_DIST_CHARGE_MAX, 0.0, 1.0)


func _hands(delta: float) -> void:
	_hands_timer -= delta
	var m := _motor()
	if m == null or _hands_intent == null:
		return
	# Движение в штрафной по move_axis, преобразованному камера-относительно НЕ нужно: вратарь и
	# камера на одной стороне; берём оси мира (x=боковое, y=вглубь поля). Кламп цели в штрафную.
	var mv := _hands_intent.move_axis()
	if mv.length() > 0.15:
		var into := -1.0 if goal_line_z > 0.0 else 1.0
		var world_dir := Vector3(mv.x, 0.0, -mv.y * into)   # стик «вверх» = вглубь поля (into)
		# Предиктивный кламп: не даём цели-намерению вывести за штрафную.
		var next_pos := _body.global_position + world_dir.normalized() * 1.0
		var clamped := KeeperPlayLogic.clamp_to_penalty_area(next_pos, goal_line_z, into,
			FootballConstants.PENALTY_AREA_DEPTH, FootballConstants.PENALTY_AREA_WIDTH * 0.5)
		var allow := clamped - _body.global_position
		allow.y = 0.0
		if allow.length() > 0.05:
			m.set_move_intent(allow.normalized(), FootballConstants.KEEPER_HANDS_MOVE_SPEED)
		else:
			m.set_move_intent(Vector3.ZERO)
		m.set_face_direction(world_dir)
	else:
		m.set_move_intent(Vector3.ZERO)
	# Жёсткий кламп позиции (страховка от инерции мотора за пределы штрафной).
	var into2 := -1.0 if goal_line_z > 0.0 else 1.0
	var boxed := KeeperPlayLogic.clamp_to_penalty_area(_body.global_position, goal_line_z, into2,
		FootballConstants.PENALTY_AREA_DEPTH, FootballConstants.PENALTY_AREA_WIDTH * 0.5)
	_body.global_position.x = boxed.x
	_body.global_position.z = boxed.z
	# Раздача A/X/B/Y — Задачи 5–8. 6 секунд — Задача 8. Пока действия игнорируются.
```

- [ ] **Step 5: Подключить `HANDS` в `match` и перенаправить точки ловли**

В `_physics_process` `match _state:` (после `State.THROWING:` ветки ~126) добавить:
```gdscript
		State.HANDS:
			_hands(delta)
		State.OUTFIELD:
			pass   # телом в OUTFIELD владеет менеджер (полевой путь); Задача 9
```
Перенаправить три точки ловли с `_to_hold()` на `_enter_hands()`:
- в `_dive()` (~471–474): заменить `_to_hold()` на `_enter_hands()`.
- в `_catching()` (~922): заменить `_to_hold()` на `_enter_hands()`.
- в `_hold(delta)` (~574–579): тело `_hold` сейчас после таймера зовёт `_to_overhand_throw()`. Оставить `_to_hold`/`_hold` как есть — они больше не достигаются из точек ловли (перенаправлены), но НЕ удаляем (fallback/совместимость). *Ничего не менять в `_to_hold`/`_hold`.*

(Так авто-цепочка HOLD→throw сохранена как мёртвый код для справки, а живой путь ловли идёт в HANDS.)

- [ ] **Step 6: Гейт менеджера — не двигать вратаря-в-руках**

В `_handle_player_input` (`match_manager.gd`), сразу после блока `if not controlled_player: return` (~1284–1285) и ПЕРЕД `_action_executor`-гейтом (~1286), добавить:
```gdscript
	# Вратарь с мячом в руках (HANDS) сам ведёт своё тело через KeeperHandsIntent — менеджер его
	# НЕ двигает (иначе два владельца тела дерутся). В OUTFIELD (мяч в ногах) keeper_ai заглушён,
	# и вратарь ведётся обычным полевым путём ниже — тогда этот гейт НЕ срабатывает.
	if controlled_player.is_in_group("role_gk"):
		var kb: Node = _ai_of(controlled_player)
		if kb.has_method(&"is_hands_active") and kb.is_hands_active():
			return
```

- [ ] **Step 7: Прогнать flow-тест — убедиться, что проходит**

Run (в фоне, 2–3× при флейке): `& "...Godot..." --path "...OpenFootball" --headless -s "res://tests/check_keeper_hands_flow.gd"`
Expected: `CHECK PASS: keeper enters HANDS + moves in box`

- [ ] **Step 8: Baseline-валидация сцены**

Run (в фоне): `& "...Godot..." --path "...OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: только baseline-категории; новых `SCRIPT ERROR`/`Parse Error` нет.

- [ ] **Step 9: Commit**

```bash
git add scripts/ai/keeper_ai.gd scripts/match/match_manager.gd tests/check_keeper_hands_flow.gd
git commit -m "feat(keeper): State.HANDS — вход при ловле, движение в штрафной, гейт менеджера"
```

---

### Task 4: Заряд-таймер A/B + power-bar (owns_hud)

Charge-as-timer в `keeper_ai`: пока зажаты заряжаемые действия (HAND/CLEAR_DIRECTED) — копим `_hands_charge`; отпущены — фиксируем ratio под выпуск (сам выпуск — Задачи 5/7). Power-bar рисует менеджер, только если человек владеет HUD.

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (`_hands`: логика заряда)
- Modify: `scripts/match/match_manager.gd` (`_process`: HANDS-заряд power-bar)
- Test: расширить `tests/check_keeper_hands_flow.gd` (добавить проверку: удержание HAND копит `hands_charge_ratio` > 0)

**Interfaces:**
- Consumes: `KeeperHandsIntent.held_action`; `hands_charge_ratio()` (Задача 3).
- Produces: `_hands_charging`/`_hands_charge`/`_hands_charge_action` наполняются; менеджер показывает power-bar на вратарском заряде.

- [ ] **Step 1: Расширить flow-тест — проверка накопления заряда**

В `check_keeper_hands_flow.gd`, в `_tick()` вставить перед финальным `_frames == 40`-блоком новую ветку (и сдвинуть финал на 60):
```gdscript
	if _frames == 45:
		_fake.mv = Vector2.ZERO
		_fake.act = KeeperHandsIntent.Action.HAND   # зажали «рука» — заряжается
		return
	if _frames == 55:
		if _brain.hands_charge_ratio() <= 0.0:
			print("CHECK FAIL: заряд A не копится (ratio=", _brain.hands_charge_ratio(), ")"); quit(1); return
		_fake.act = KeeperHandsIntent.Action.NONE   # отпустили (выпуск — Задача 5; тут не проверяем гол)
		return
```
Изменить финальный порог `if _frames == 40:` → `if _frames == 60:` (и внутри — прежние проверки движения; их выполнить на кадре 40 отдельной веткой, оставив финал под 60). Итог: кадр 40 — проверка движения/клампа (без `quit`); кадр 60 — `quit(0)` с `CHECK PASS`.

*(Точное разбиение: раздели существующую `_frames == 40`-ветку — перенеси проверки `moved`/кламп в новую ветку `if _frames == 40:` без `quit`, а `print("CHECK PASS...")`/`quit(0)` перенеси в `if _frames == 60:`.)*

- [ ] **Step 2: Прогнать — убедиться, что падает (заряд не копится)**

Run (в фоне): `check_keeper_hands_flow.gd`.
Expected: FAIL — `hands_charge_ratio` всегда -1 (заряд ещё не реализован).

- [ ] **Step 3: Реализовать заряд в `_hands`**

В `keeper_ai._hands(delta)`, заменить финальный комментарий `# Раздача A/X/B/Y — Задачи 5–8...` на:
```gdscript
	# Заряд-как-таймер: HAND и CLEAR_DIRECTED заряжаемые; CLEAR_CENTER/DROP — мгновенные.
	var act := _hands_intent.held_action()
	var chargeable: bool = act == KeeperHandsIntent.Action.HAND or act == KeeperHandsIntent.Action.CLEAR_DIRECTED
	if chargeable:
		_hands_charging = true
		_hands_charge_action = act
		_hands_charge = minf(_hands_charge + delta, FootballConstants.KEEPER_DIST_CHARGE_MAX)
	elif _hands_charging:
		# Отпустили заряжаемую → выпуск по накопленному заряду (Задачи 5/7 реализуют _fire_hands).
		var ratio := clampf(_hands_charge / FootballConstants.KEEPER_DIST_CHARGE_MAX, 0.0, 1.0)
		_hands_charging = false
		_fire_hands(_hands_charge_action, ratio)
		return
	elif act == KeeperHandsIntent.Action.CLEAR_CENTER:
		_fire_hands(act, 0.0)
		return
	elif act == KeeperHandsIntent.Action.DROP:
		_fire_hands(act, 0.0)
		return
```
И добавить временную заглушку `_fire_hands` (реальные ветки — Задачи 5–8):
```gdscript
## Выпуск вратарской раздачи по действию. Ветки A/X/B/Y наполняются в Задачах 5–8.
func _fire_hands(action: int, ratio: float) -> void:
	print("[KEEPER] _fire_hands action=", action, " ratio=", ratio, " (stub)")
	# Задачи 5–8 заменят это на реальную раздачу. Пока просто возвращаемся в POSITION,
	# чтобы не зависнуть (мяч всё ещё в руках — временно; полноценный выпуск позже).
	_state = State.POSITION
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
```

- [ ] **Step 4: Power-bar менеджера на вратарском заряде**

В `match_manager._process()`, ПОСЛЕ существующего блока заряда (~1020, после строки, где `power_bar.visible = ...`) добавить отдельный HANDS-блок:
```gdscript
	# Вратарский HANDS-заряд (A/B): power-bar рисует менеджер, ТОЛЬКО если человек владеет HUD
	# (presentation KICKER). keeper_ai держит сам заряд; менеджер лишь визуализирует ratio.
	if controlled_player != null and controlled_player.is_in_group("role_gk"):
		var kb: Node = _ai_of(controlled_player)
		if kb.has_method(&"is_hands_active") and kb.is_hands_active() and kb.has_method(&"hands_charge_ratio"):
			var r: float = kb.hands_charge_ratio()
			if r >= 0.0:
				power_bar.visible = true
				power_bar.value = r
				var fill := power_bar.get_theme_stylebox("fill")
				if fill:
					fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, r * r)
			elif not _is_charging():
				power_bar.visible = false
```
(Гейт `controlled_player.is_in_group("role_gk")` гарантирует, что для ИИ-вратаря — который не `controlled_player` — бар не рисуется, ровно как «только если владеет HUD».)

- [ ] **Step 5: Прогнать — убедиться, что проходит**

Run (в фоне, 2–3×): `check_keeper_hands_flow.gd`.
Expected: `CHECK PASS: keeper enters HANDS + moves in box` (теперь и с проверкой заряда).

- [ ] **Step 6: Commit**

```bash
git add scripts/ai/keeper_ai.gd scripts/match/match_manager.gd tests/check_keeper_hands_flow.gd
git commit -m "feat(keeper): HANDS charge-as-timer (A/B) + power-bar на владении HUD"
```

---

### Task 5: Раздача A — рука (тап=раскат низом / удержание=бросок верхом)

`_fire_hands(HAND, ratio)`: автонаведение team_1-своего (`select_hand_target`), тап (`ratio*max < THROW_CHARGE`) → раскат низом к ближнему, удержание → бросок верхом к дальнему. Мяч приклеен к руке до выпуска по `action_contact` клипа; переиспользуем математику `_do_pass_roll`/`_do_overhand_throw`. Управление уходит адресату.

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (`_fire_hands` — ветка HAND; клип+contact; выпуск; handoff)
- Test: расширить `check_keeper_hands_flow.gd` (HAND-тап → мяч покидает руки + управление ушло)

**Interfaces:**
- Consumes: `KeeperPlayLogic.select_hand_target`; `KeeperLogic.roll_speed`, `KeeperLogic.drag_horizontal_speed`, `PassSystem.launch_lob`; `ball.launch`, `ball.launch(flat=true)`; `manager.keeper_handoff_control`.
- Produces: рабочая раздача рукой; `_do_hand_release()`.

- [ ] **Step 1: Расширить flow-тест — HAND-тап выпускает мяч + передаёт управление**

Добавить в `check_keeper_hands_flow.gd` новую независимую подпроверку (проще — отдельный тест-файл, но для DRY продолжаем этот): после кадра 55 (отпустили HAND в Задаче 4) на кадре 90 проверить, что мяч больше не в руках вратаря и `controlled_player` не вратарь:
```gdscript
	if _frames == 90:
		if _mm.ball.dribbler == _keeper or _mm.ball.is_caught():
			print("CHECK FAIL: мяч всё ещё в руках после раздачи A"); quit(1); return
		if _mm.controlled_player == _keeper:
			print("CHECK FAIL: управление не ушло с вратаря после раздачи A"); quit(1); return
		print("CHECK PASS: keeper hands: enter+move+charge+hand-release")
		quit(0)
		return
```
Убрать прежний `quit(0)` с кадра 60 (оставить там только не-фатальные проверки/лог), финал перенести на кадр 90. Для гарантии выпуска на кадре 55 вместо `NONE` слать короткий тап: установить `_fake.act = HAND` на кадре 50 и `_fake.act = NONE` на 52 (тап < THROW_CHARGE), чтобы пошёл раскат.

*(Если `action_contact` клипа `keeper_pass` не успевает за бюджет кадров — тест флейкнет `launched=false`; гонять 2–3× и сверять с baseline, см. Global Constraints.)*

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `check_keeper_hands_flow.gd`.
Expected: FAIL — мяч остаётся в руках (`_fire_hands` HAND-ветка ещё заглушка → `_state=POSITION`, мяч не выпущен).

- [ ] **Step 3: Реализовать ветку HAND в `_fire_hands` + `_do_hand_release`**

В `keeper_ai._fire_hands(action, ratio)` заменить тело заглушки на диспетчер по действию:
```gdscript
func _fire_hands(action: int, ratio: float) -> void:
	match action:
		KeeperHandsIntent.Action.HAND:
			_begin_hand(ratio)
		# CLEAR_CENTER — Задача 6; CLEAR_DIRECTED — Задача 7; DROP — Задача 9.
		_:
			print("[KEEPER] _fire_hands unhandled action=", action)
```
Добавить (переиспользуя select_hand_target + существующие клипы/math):
```gdscript
var _hand_is_throw: bool = false        # true → бросок верхом (удержание), false → раскат низом (тап)
var _hand_target_pos: Vector3 = Vector3.ZERO   # точка адресата для handoff

## Раздача рукой: тап (заряд < порога) = раскат низом ближнему; удержание = бросок верхом дальнему.
## Автонаведение по прицелу среди team_1-своих; банд дистанции растёт с зарядом.
func _begin_hand(ratio: float) -> void:
	var charge_time := ratio * FootballConstants.KEEPER_DIST_CHARGE_MAX
	_hand_is_throw = charge_time >= FootballConstants.KEEPER_HAND_THROW_CHARGE
	# Кандидаты — свои полевые (та же команда, что и вратарь), исключая себя и второго вратаря.
	# Прицел — по aim_axis. (my_group выводим из группы тела, не из хардкода team_1.)
	var my_group := &"team_1" if _body.is_in_group("team_1") else &"team_2"
	var mates: Array = []
	for n in _body.get_tree().get_nodes_in_group(my_group):
		if n == _body or not is_instance_valid(n) or n.is_in_group("role_gk"):
			continue
		mates.append(n)
	var mate_pos: Array = []
	for n in mates:
		mate_pos.append(n.global_position)
	var aim := _hands_intent.aim_axis()
	var into := signf(-goal_line_z)
	var aim_dir := Vector3(aim.x, 0.0, -aim.y * into)
	if aim_dir.length() < 0.01:
		aim_dir = Vector3(0.0, 0.0, into)   # нет прицела → в поле
	aim_dir = aim_dir.normalized()
	var idx := KeeperPlayLogic.select_hand_target(_body.global_position, aim_dir, mate_pos, ratio,
		FootballConstants.KEEPER_HAND_ROLL_DIST, FootballConstants.KEEPER_HAND_THROW_DIST)
	if idx >= 0:
		_hand_target_pos = mate_pos[idx]
	else:
		# Фолбэк: точка по прицелу на дистанцию по банду (раскат/бросок).
		var dist := FootballConstants.KEEPER_HAND_THROW_DIST if _hand_is_throw else FootballConstants.KEEPER_HAND_ROLL_DIST
		_hand_target_pos = _body.global_position + aim_dir * dist
	_state = State.THROWING
	_distribute_fired = false
	_state_timer = 1.3
	var m := _motor()
	if m != null:
		m.set_control_locked(true)
	var vis := _visual()
	var clip := &"keeper_overhand_throw" if _hand_is_throw else &"keeper_pass"
	if vis == null or not vis.trigger(clip):
		_do_hand_release()   # фолбэк без анимации


## Выпуск по action_contact клипа руки: бросок верхом (дуга) или раскат низом (flat), к _hand_target_pos.
func _do_hand_release() -> void:
	if _distribute_fired:
		return
	_distribute_fired = true
	if ball.dribbler == _body or ball.is_caught():
		var from := _body.global_position
		var flat_to := Vector3(_hand_target_pos.x, from.y, _hand_target_pos.z)
		var dist := Vector3(flat_to.x - from.x, 0.0, flat_to.z - from.z).length()
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		if _hand_is_throw:
			# Бросок верхом: дуга через launch_lob-стиль (как _do_overhand_throw), драг-поправка.
			var g := _ball_gravity()
			var vy := sqrt(2.0 * g * FootballConstants.KEEPER_THROW_PEAK)
			var flight_t := 2.0 * vy / g
			var dir := Vector3(flat_to.x - from.x, 0.0, flat_to.z - from.z)
			dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, signf(-goal_line_z))
			var hspeed := KeeperLogic.drag_horizontal_speed(dist, flight_t, ball.drag_factor, dt)
			ball.launch(dir * hspeed + Vector3.UP * vy)
		else:
			# Раскат низом: мяч с руки на газон, катится к цели (flat), скорость из драга.
			var speed := KeeperLogic.roll_speed(maxf(dist, 1.0), ball.drag_factor, dt)
			var dir := Vector3(flat_to.x - from.x, 0.0, flat_to.z - from.z)
			dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, signf(-goal_line_z))
			var bp := ball.global_position
			ball.global_position = Vector3(bp.x, FootballConstants.BALL_RADIUS + 0.02, bp.z)
			ball.launch(dir * speed, true)
	# Управление адресату (как приём паса).
	if manager != null and manager.has_method(&"keeper_handoff_control"):
		manager.keeper_handoff_control(_hand_target_pos)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
	_state = State.POSITION
```
**Убрать** ошибочный placeholder-цикл `for n in _body.get_tree().get_nodes_in_group(_body.get_groups_team())` целиком (он был показан для наглядности, что метода `get_groups_team` НЕТ — используем `my_group`-сбор ниже). В финальном коде оставить только `my_group`-ветку.

- [ ] **Step 4: Подключить `_do_hand_release` к `action_contact`**

В `keeper_ai._on_visual_contact(action)` (~790), добавить перед последней веткой `keeper_pass`:
```gdscript
	if _state == State.THROWING and not _distribute_fired \
			and (action == "keeper_overhand_throw" or action == "keeper_pass"):
		# HANDS-раздача рукой (План 2) переиспользует те же клипы, что авто-throw/roll.
		if _hand_target_pos != Vector3.ZERO:
			_do_hand_release()
			return
```
(Гейт `_hand_target_pos != Vector3.ZERO` отличает HANDS-раздачу от авто-`_do_overhand_throw`/`_do_pass_roll`, которые `_hand_target_pos` не ставят. Сбрасывать `_hand_target_pos = Vector3.ZERO` в `_do_hand_release` в конце — добавить строкой перед `_state = State.POSITION`.)

- [ ] **Step 5: Прогнать flow-тест — убедиться, что проходит**

Run (в фоне, 2–3×): `check_keeper_hands_flow.gd`.
Expected: `CHECK PASS: keeper hands: enter+move+charge+hand-release`

- [ ] **Step 6: Commit**

```bash
git add scripts/ai/keeper_ai.gd tests/check_keeper_hands_flow.gd
git commit -m "feat(keeper): HANDS раздача A — раскат низом / бросок верхом + передача управления"
```

---

### Task 6: Раздача X — вынос ногой к центру (мгновенно, фикс-сильно)

`_fire_hands(CLEAR_CENTER, _)`: без заряда, drop-kick к центру поля на фикс `KEEPER_CLEAR_SPEED/LIFT` через `KeeperPlayLogic.clear_center_vector`. Управление — ближайшему team_1 у точки приземления.

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (`_fire_hands` — ветка CLEAR_CENTER; `_do_center_clear`)
- Test: расширить `check_keeper_hands_flow.gd` ИЛИ отдельная быстрая проверка — здесь достаточно вызвать `_fire_hands(CLEAR_CENTER,0)` напрямую и проверить, что мяч улетел от ворот.

**Interfaces:**
- Consumes: `KeeperPlayLogic.clear_center_vector`; `ball.launch`.
- Produces: рабочий вынос к центру.

- [ ] **Step 1: Написать под-проверку (в flow-тесте отдельная ветка сценария 2)**

Проще — добавить в `check_keeper_hands_flow.gd` второй прогон невозможен в одном SceneTree; вместо этого — новый минимальный тест `tests/check_keeper_clear_center.gd`:
```gdscript
extends SceneTree
## Вынос вратаря к центру (X/CLEAR_CENTER): мяч улетает от ворот вглубь поля.
class FakeHandsIntent extends KeeperHandsIntent:
	func held_action() -> int: return KeeperHandsIntent.Action.CLEAR_CENTER
var _mm; var _k; var _b; var _f := 0; var _fired := false; var _z0 := 0.0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 5:
		_k = _mm._team_home.keeper(); _b = _k.brain()
		_b._hands_intent_override = FakeHandsIntent.new()
		_mm.ball.catch(_k, _b.hold_point); _b._enter_hands()
		return
	if _f == 8:
		_z0 = _mm.ball.global_position.z; _fired = true
		return
	if _f == 60 and _fired:
		var into := signf(-_b.goal_line_z)   # от ворот в поле
		var progressed := (_mm.ball.global_position.z - _z0) * into
		if _mm.ball.dribbler == _k or _mm.ball.is_caught():
			print("CHECK FAIL: мяч не вынесен (в руках)"); quit(1); return
		if progressed < 3.0:
			print("CHECK FAIL: мяч не улетел от ворот к центру (progressed=", progressed, ")"); quit(1); return
		print("CHECK PASS: keeper center clear (X)"); quit(0); return
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `check_keeper_clear_center.gd`.
Expected: FAIL — CLEAR_CENTER ещё не выносит (заглушка `_fire_hands` → `_state=POSITION`, мяч в руках).

- [ ] **Step 3: Реализовать ветку CLEAR_CENTER**

В `_fire_hands` `match`-блоке добавить ветку:
```gdscript
		KeeperHandsIntent.Action.CLEAR_CENTER:
			_do_center_clear()
```
Добавить:
```gdscript
## Вынос ногой к центру поля (drop-kick), фикс-сильно. Управление — ближайшему team_1 у приземления.
func _do_center_clear() -> void:
	var into := signf(-goal_line_z)
	var vel := KeeperPlayLogic.clear_center_vector(into, FootballConstants.KEEPER_CLEAR_SPEED,
		FootballConstants.KEEPER_CLEAR_LIFT)
	var from := _body.global_position
	if ball.dribbler == _body or ball.is_caught():
		var bp := ball.global_position
		ball.global_position = Vector3(bp.x, FootballConstants.BALL_RADIUS + 0.3, bp.z)
		ball.launch(vel)
	# Точка приземления (грубо): по дальности выноса вдоль into.
	var land := from + Vector3(0.0, 0.0, into) * FootballConstants.KEEPER_THROW_DISTANCE
	if manager != null and manager.has_method(&"keeper_handoff_control"):
		manager.keeper_handoff_control(land)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
	var vis := _visual()
	if vis != null:
		vis.trigger("keeper_drop_kick")   # визуал выноса (мяч уже запущен — клип косметический)
	_state = State.POSITION
```

- [ ] **Step 4: Прогнать — убедиться, что проходит**

Run (в фоне, 2–3×): `check_keeper_clear_center.gd`.
Expected: `CHECK PASS: keeper center clear (X)`

- [ ] **Step 5: Commit**

```bash
git add scripts/ai/keeper_ai.gd tests/check_keeper_clear_center.gd
git commit -m "feat(keeper): HANDS раздача X — вынос ногой к центру"
```

---

### Task 7: Раздача B — направленный вынос по стику (заряд = дальность)

`_fire_hands(CLEAR_DIRECTED, ratio)`: drop-kick по прицелу `aim_axis`, скорость по заряду через `KeeperPlayLogic.directed_clear_vector` (min→max от `KEEPER_CLEAR_SPEED`). Управление — ближайшему team_1 у приземления.

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (`_fire_hands` — ветка CLEAR_DIRECTED; `_do_directed_clear`)
- Test: `tests/check_keeper_clear_directed.gd` (создать — аналогично Задаче 6, но с боковым прицелом → мяч уходит вбок+вперёд)

**Interfaces:**
- Consumes: `KeeperPlayLogic.directed_clear_vector`; `KeeperHandsIntent.aim_axis`; `ball.launch`.
- Produces: рабочий направленный вынос.

- [ ] **Step 1: Написать падающий тест `tests/check_keeper_clear_directed.gd`**

```gdscript
extends SceneTree
## Направленный вынос вратаря (B/CLEAR_DIRECTED) по стику: мяч уходит в сторону прицела + вперёд.
class FakeHandsIntent extends KeeperHandsIntent:
	var a := Vector2(1.0, 0.5)   # прицел: вбок(+x) и вглубь(+y)
	func aim_axis() -> Vector2: return a
	func held_action() -> int: return KeeperHandsIntent.Action.CLEAR_DIRECTED
var _mm; var _k; var _b; var _f := 0; var _fired := false; var _x0 := 0.0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 5:
		_k = _mm._team_home.keeper(); _b = _k.brain()
		_b._hands_intent_override = FakeHandsIntent.new()
		_mm.ball.catch(_k, _b.hold_point); _b._enter_hands()
		return
	if _f == 10:
		# держим B ещё пару кадров — зарядка; затем отпустим, чтобы пошёл выпуск (Задача 4 charge).
		_x0 = _mm.ball.global_position.x; _fired = true
		return
	if _f == 14:
		_b._hands_intent_override.a = Vector2(1.0, 0.5)
		# отпустить: сменить held_action на NONE — переопределяем через новый фейк без действия.
		_b._hands_intent_override = _NoAct.new()
		return
	if _f == 70 and _fired:
		if _mm.ball.dribbler == _k or _mm.ball.is_caught():
			print("CHECK FAIL: мяч не вынесен направленно (в руках)"); quit(1); return
		if _mm.ball.global_position.x - _x0 < 1.0:
			print("CHECK FAIL: мяч не ушёл вбок по прицелу (dx=", _mm.ball.global_position.x - _x0, ")"); quit(1); return
		print("CHECK PASS: keeper directed clear (B)"); quit(0); return
class _NoAct extends KeeperHandsIntent:
	func held_action() -> int: return KeeperHandsIntent.Action.NONE
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `check_keeper_clear_directed.gd`.
Expected: FAIL — CLEAR_DIRECTED не выносит.

- [ ] **Step 3: Реализовать ветку CLEAR_DIRECTED**

В `_fire_hands` `match`-блоке добавить:
```gdscript
		KeeperHandsIntent.Action.CLEAR_DIRECTED:
			_do_directed_clear(ratio)
```
Добавить:
```gdscript
## Направленный вынос ногой по прицелу; скорость по заряду (min = CLEAR_SPEED*0.6, max = CLEAR_SPEED*1.4).
func _do_directed_clear(ratio: float) -> void:
	var aim := _hands_intent.aim_axis() if _hands_intent != null else Vector2.ZERO
	var into := signf(-goal_line_z)
	var aim_flat := Vector3(aim.x, 0.0, -aim.y * into)
	if aim_flat.length() < 0.01:
		aim_flat = Vector3(0.0, 0.0, into)
	var vmin := FootballConstants.KEEPER_CLEAR_SPEED * 0.6
	var vmax := FootballConstants.KEEPER_CLEAR_SPEED * 1.4
	var vel := KeeperPlayLogic.directed_clear_vector(aim_flat, ratio, vmin, vmax,
		FootballConstants.KEEPER_CLEAR_LIFT)
	var from := _body.global_position
	if ball.dribbler == _body or ball.is_caught():
		var bp := ball.global_position
		ball.global_position = Vector3(bp.x, FootballConstants.BALL_RADIUS + 0.3, bp.z)
		ball.launch(vel)
	var flat := Vector3(vel.x, 0.0, vel.z)
	var land := from + flat.normalized() * FootballConstants.KEEPER_THROW_DISTANCE
	if manager != null and manager.has_method(&"keeper_handoff_control"):
		manager.keeper_handoff_control(land)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)
	var vis := _visual()
	if vis != null:
		vis.trigger("keeper_drop_kick")
	_state = State.POSITION
```

- [ ] **Step 4: Прогнать — убедиться, что проходит**

Run (в фоне, 2–3×): `check_keeper_clear_directed.gd`.
Expected: `CHECK PASS: keeper directed clear (B)`

- [ ] **Step 5: Commit**

```bash
git add scripts/ai/keeper_ai.gd tests/check_keeper_clear_directed.gd
git commit -m "feat(keeper): HANDS раздача B — направленный вынос по стику, дальность по заряду"
```

---

### Task 8: Правило 6 секунд

В HANDS `_hands_timer` истекает за `KEEPER_SIX_SECOND_TIME` → принудительный вынос к центру (как CLEAR_CENTER) + управление уходит. Для человека и ИИ одинаково.

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (`_hands`: проверка `_hands_timer <= 0`)
- Test: `tests/check_keeper_six_second.gd` (создать)

**Interfaces:**
- Consumes: `_do_center_clear` (Задача 6).
- Produces: авто-вынос по таймауту.

- [ ] **Step 1: Написать падающий тест `tests/check_keeper_six_second.gd`**

```gdscript
extends SceneTree
## Правило 6 секунд: вратарь с «пустым» интентом (ничего не жмёт) через KEEPER_SIX_SECOND_TIME
## сам выносит мяч (к центру) и управление уходит.
class Idle extends KeeperHandsIntent:
	func move_axis() -> Vector2: return Vector2.ZERO
	func held_action() -> int: return KeeperHandsIntent.Action.NONE
var _mm; var _k; var _b; var _f := 0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 5:
		_k = _mm._team_home.keeper(); _b = _k.brain()
		_b._hands_intent_override = Idle.new()
		_mm.ball.catch(_k, _b.hold_point); _b._enter_hands()
		return
	# 6 сек * 60 фпс = 360 физкадров; ждём с запасом.
	if _f == 5 + 360 + 40:
		if _b.is_hands_active():
			print("CHECK FAIL: через 6с всё ещё HANDS"); quit(1); return
		if _mm.ball.dribbler == _k or _mm.ball.is_caught():
			print("CHECK FAIL: через 6с мяч всё ещё в руках"); quit(1); return
		print("CHECK PASS: keeper six-second rule"); quit(0); return
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `check_keeper_six_second.gd`.
Expected: FAIL — вратарь держит мяч бесконечно (таймаут не реализован).

- [ ] **Step 3: Реализовать таймаут в `_hands`**

В `keeper_ai._hands(delta)`, сразу после `_hands_timer -= delta` (начало функции), добавить:
```gdscript
	if _hands_timer <= 0.0:
		# Правило 6 секунд: принудительный вынос к центру + управление уходит (как CLEAR_CENTER).
		print("[KEEPER] 6-second rule → forced center clear")
		_do_center_clear()
		return
```

- [ ] **Step 4: Прогнать — убедиться, что проходит**

Run (в фоне, 2–3×): `check_keeper_six_second.gd`.
Expected: `CHECK PASS: keeper six-second rule`

- [ ] **Step 5: Commit**

```bash
git add scripts/ai/keeper_ai.gd tests/check_keeper_six_second.gd
git commit -m "feat(keeper): правило 6 секунд — принудительный вынос по таймауту HANDS"
```

---

### Task 9: OUTFIELD-режим — дроп Y → вратарь как полевой + возврат в AI

`_fire_hands(DROP, _)`: мяч роняется к ногам (`set_dribbler(keeper, force=true)`, без клипа), вратарь → `State.OUTFIELD`. В OUTFIELD `keeper_ai._physics_process` early-return (как `_goalkick_mode`) — телом владеет менеджер (полевой дриблинг/пас/удар, `controlled_player`=keeper, клампа НЕТ). Возврат в AI-режим (POSITION), когда мяч потерян/отдан (`ball.dribbler != keeper` и не пойман).

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (`_fire_hands` — ветка DROP; `_enter_outfield`; `_physics_process` early-return в OUTFIELD + детект потери мяча; локомоция стиль NORMAL)
- Test: `tests/check_keeper_hands_flow.gd` расширить ИЛИ отдельный `tests/check_keeper_outfield.gd` (создать)

**Interfaces:**
- Consumes: `ball.set_dribbler(keeper, true)`; `manager` (assign остаётся keeper — уже controlled_player).
- Produces: `State.OUTFIELD`; возврат в POSITION при потере мяча.

- [ ] **Step 1: Написать падающий тест `tests/check_keeper_outfield.gd`**

```gdscript
extends SceneTree
## OUTFIELD: дроп Y → мяч у ног вратаря (dribbler==keeper), keeper_ai заглушён; отобрать мяч →
## возврат в POSITION (AI-режим).
class DropOnce extends KeeperHandsIntent:
	var fired := false
	func held_action() -> int:
		if fired: return KeeperHandsIntent.Action.NONE
		fired = true
		return KeeperHandsIntent.Action.DROP
var _mm; var _k; var _b; var _f := 0; var _dropped := false
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 5:
		_k = _mm._team_home.keeper(); _b = _k.brain()
		_b._hands_intent_override = DropOnce.new()
		_mm.ball.catch(_k, _b.hold_point); _b._enter_hands()
		return
	if _f == 20:
		# После дропа: мяч у ног вратаря, состояние OUTFIELD.
		if _mm.ball.dribbler != _k:
			print("CHECK FAIL: после Y мяч не у ног вратаря"); quit(1); return
		if _b._state != _b.State.OUTFIELD:
			print("CHECK FAIL: не в OUTFIELD после Y (state=", _b._state, ")"); quit(1); return
		_dropped = true
		# Отбираем мяч (эмулируем потерю): release_dribble.
		_mm.ball.release_dribble()
		return
	if _f == 50 and _dropped:
		if _b._state != _b.State.POSITION:
			print("CHECK FAIL: не вернулся в POSITION после потери мяча (state=", _b._state, ")"); quit(1); return
		print("CHECK PASS: keeper outfield drop + return to AI"); quit(0); return
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `check_keeper_outfield.gd`.
Expected: FAIL — DROP не реализован (заглушка → POSITION, мяч не у ног).

- [ ] **Step 3: Реализовать DROP + OUTFIELD в `keeper_ai.gd`**

В `_fire_hands` `match`-блоке добавить:
```gdscript
		KeeperHandsIntent.Action.DROP:
			_enter_outfield()
```
Добавить:
```gdscript
## Дроп Y: мяч из рук к ногам (force — мимо кулдаунов, БЕЗ клипа placing_ball), вратарь → OUTFIELD.
## controlled_player уже = keeper (взят в _enter_hands) — менеджер поведёт его как полевого.
func _enter_outfield() -> void:
	_state = State.OUTFIELD
	var bp := ball.global_position
	ball.global_position = Vector3(bp.x, FootballConstants.BALL_RADIUS + 0.02, bp.z)
	ball.set_dribbler(_body, true)
	var m := _motor()
	if m != null:
		m.set_control_locked(false)   # менеджерский полевой ввод теперь двигает вратаря
	var vis := _visual()
	if vis != null:
		vis.recover()   # выйти из idle_ball one-shot
		vis.set_locomotion_style(PlayerVisual.LOCO_STYLE_NORMAL)
```
В `_physics_process`, сразу после `if _goalkick_mode: return` (~89–90), добавить OUTFIELD-глушение + детект потери:
```gdscript
	# OUTFIELD: телом владеет менеджер (полевой путь). keeper_ai молчит, пока мяч у ног вратаря.
	# Мяч потерян/отдан (не у ног и не пойман) → возврат в AI-режим (держим линию).
	if _state == State.OUTFIELD:
		var mine: bool = ball.dribbler == _body or (ball.has_method(&"is_caught") and ball.is_caught() and ball.dribbler == _body)
		if not mine:
			_state = State.POSITION
			var vis2 := _visual()
			if vis2 != null:
				vis2.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)
		return
```
(Этот блок — ПЕРЕД `match _state`, чтобы OUTFIELD не попадал в `match` (там ветка `State.OUTFIELD: pass`, оставленная в Задаче 3 как страховка — можно оставить, она недостижима из-за early-return).)

- [ ] **Step 4: Прогнать — убедиться, что проходит**

Run (в фоне, 2–3×): `check_keeper_outfield.gd`.
Expected: `CHECK PASS: keeper outfield drop + return to AI`

- [ ] **Step 5: Baseline-валидация сцены**

Run (в фоне): `& "...Godot..." --path "...OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: только baseline-категории.

- [ ] **Step 6: Commit**

```bash
git add scripts/ai/keeper_ai.gd tests/check_keeper_outfield.gd
git commit -m "feat(keeper): OUTFIELD — дроп Y → вратарь как полевой, возврат в AI при потере мяча"
```

---

### Task 10: Консьюмер флага бэк-паса — приём намеренного паса своего → OUTFIELD (не руки)

Флаг `ball._pass_from_team` (План 1) читается в точках ловли: если мяч — намеренный пас СВОЕЙ команды, вратарь руками брать НЕ может → трапит у ног (`set_dribbler(force=true)`) и уходит в OUTFIELD вместо ловли руками. Пусто/чужая команда → обычная ловля.

**Files:**
- Modify: `scripts/ai/keeper_ai.gd` (`on_ball_contact`, `_position`-рефлекс, `_penalty_hold`-рефлекс, `_catching`-захват, `_dive`-контакт — единый guard-хелпер `_is_own_backpass()`)
- Test: `tests/check_keeper_backpass_outfield.gd` (создать)

**Interfaces:**
- Consumes: `ball.pass_from_team()` (План 1); `_enter_outfield` (Задача 9).
- Produces: `_is_own_backpass() -> bool`; ветвление ловли.

- [ ] **Step 1: Написать падающий тест `tests/check_keeper_backpass_outfield.gd`**

```gdscript
extends SceneTree
## Бэк-пас: мяч, ПОМЕЧЕННЫЙ намеренным пасом своей команды, вратарь берёт НЕ руками, а в ноги
## (dribbler==keeper, НЕ is_caught) → OUTFIELD. Медленный мяч в зоне трапа у вратаря.
var _mm; var _k; var _b; var _f := 0
func _initialize() -> void:
	_mm = load("res://scenes/match.tscn").instantiate(); root.add_child(_mm)
	physics_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 8:
		_k = _mm._team_home.keeper(); _b = _k.brain()
		# Кладём медленный мяч у ног вратаря и помечаем его пасом СВОЕЙ (team_1) команды.
		var kp := _k.global_position
		_mm.ball.global_position = Vector3(kp.x, FootballConstants.BALL_RADIUS + 0.02, kp.z + signf(-_b.goal_line_z) * 0.4)
		_mm.ball.linear_velocity = Vector3(0, 0, signf(-_b.goal_line_z) * -1.0)  # тихо катится во вратаря
		_mm.ball.set_dribbler(null)             # OPEN
		_mm.ball.note_pass_from(&"team_1")      # намеренный пас своего
		_mm.ball.state = _mm.ball.BallState.FLIGHT   # эмулируем «летящий» для рефлекса
		_b.on_ball_contact()
		return
	if _f == 20:
		if _mm.ball.is_caught():
			print("CHECK FAIL: вратарь взял бэк-пас РУКАМИ"); quit(1); return
		if _mm.ball.dribbler != _k:
			print("CHECK FAIL: вратарь не трапнул бэк-пас в ноги (dribbler=", _mm.ball.dribbler, ")"); quit(1); return
		if _b._state != _b.State.OUTFIELD:
			print("CHECK FAIL: не в OUTFIELD после бэк-паса (state=", _b._state, ")"); quit(1); return
		print("CHECK PASS: keeper backpass → outfield (no hands)"); quit(0); return
```

- [ ] **Step 2: Прогнать — убедиться, что падает**

Run (в фоне): `check_keeper_backpass_outfield.gd`.
Expected: FAIL — вратарь ловит руками (`is_caught`), `_is_own_backpass` не существует.

- [ ] **Step 3: Добавить guard-хелпер и трап-в-ноги**

В `keeper_ai.gd` добавить:
```gdscript
## Мяч — намеренный пас СВОЕЙ команды (бэк-пас)? Тогда руками брать нельзя (правило футбола).
func _is_own_backpass() -> bool:
	if not (ball.has_method(&"pass_from_team")):
		return false
	var pf: StringName = ball.pass_from_team()
	if pf == &"":
		return false
	var my_group := &"team_1" if _body.is_in_group("team_1") else &"team_2"
	return pf == my_group


## Трап бэк-паса В НОГИ (не в руки) → OUTFIELD. Зовётся из точек ловли, когда _is_own_backpass().
func _trap_backpass() -> void:
	var bp := ball.global_position
	ball.global_position = Vector3(bp.x, FootballConstants.BALL_RADIUS + 0.02, bp.z)
	ball.set_dribbler(_body, true)   # снимет и флаг _pass_from_team (set_dribbler в Плане 1)
	_enter_outfield()
```

- [ ] **Step 4: Вставить guard в точки ловли**

В `on_ball_contact()` (~479), сразу после ранних-return (`_pass_through`/celebrating гейты, ~485–488) и ПЕРЕД проверкой высоты/ловлей, добавить:
```gdscript
	if _is_own_backpass():
		_trap_backpass()
		return
```
В `_position` рефлексе ловли (~147), ВНУТРИ `if ball.is_flight() and _heading_at_goal() and _catch_radius_hit():`, первой строкой:
```gdscript
		if _is_own_backpass():
			_trap_backpass()
			return
```
Аналогично в `_penalty_hold` рефлексе (~406) и в `_catching` захвате (~918, внутри `if ball.is_flight() and _catch_radius_hit():`) — первой строкой того же вида guard `if _is_own_backpass(): _trap_backpass(); return`. В `_dive` контакте (`_resolve_dive_contact`, ~539) — в начале: `if _is_own_backpass(): _trap_backpass(); return`.

(Единый паттерн: в любой точке, где мяч вот-вот прилипнет к рукам, сперва проверяем бэк-пас и уходим в ноги.)

- [ ] **Step 5: Прогнать — убедиться, что проходит**

Run (в фоне, 2–3×): `check_keeper_backpass_outfield.gd`.
Expected: `CHECK PASS: keeper backpass → outfield (no hands)`

- [ ] **Step 6: Регресс — обычная ловля не сломана**

Run (в фоне, 2–3×): `check_keeper_clear.gd` (полный цикл ловли — учесть известную флейку, гнать до PASS или сверить с baseline), `check_keeper_hands_flow.gd`.
Expected: обычный (не помеченный) удар по-прежнему ловится руками; guard срабатывает только на флаг.

- [ ] **Step 7: Baseline-валидация сцены**

Run (в фоне): `& "...Godot..." --path "...OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: только baseline-категории.

- [ ] **Step 8: Commit**

```bash
git add scripts/ai/keeper_ai.gd tests/check_keeper_backpass_outfield.gd
git commit -m "feat(keeper): консьюмер бэк-паса — намеренный пас своего вратарь берёт в ноги → OUTFIELD"
```

---

## Self-Review (автора плана — проверено)

**1. Покрытие спека (Фазы 2+4):**
- Шов `KeeperHandsIntent` (+Human/AI) — готов в Плане 1; диспетч T2.
- Вход в HANDS при ловле — T3. Движение в штрафной + кламп — T3. Заряд — T4. Power-bar (owns_hud) — T4.
- Раздача A (рука: раскат/бросок, `select_hand_target`, автонаведение) — T5. X (вынос центр) — T6. B (направленный) — T7. Y (дроп → OUTFIELD) — T9.
- 6 сек — T8. Диспетч + передача управления (`keeper_handoff_control`) — T2/T5–T8. InputMap — T1. Константы — T1.
- OUTFIELD (Y-дроп + бэк-пас → полевой, возврат в AI) — T9/T10. Консьюмер флага бэк-паса — T10.
- **Вне этого плана (по замыслу Плана 1/спека):** carry-бленд верх/низ (`PlayerVisual.set_carry_pose`) — **План 3** (визуал, работает без него: мяч приклеен к руке, бег обычной анимацией). Off-line выход вратаря — отдельный будущий спек. Полноценный решатель `AIKeeperHandsIntent` — v1 заглушка (T2 использует существующую).

**2. Плейсхолдер-скан:** Плейсхолдеров нет — весь код приведён. `_fire_hands` в T4 — намеренная функциональная заглушка (печатает + возвращает в POSITION), заменяется `match`-диспетчером в T5 и наполняется ветками T5–T9 (явно оговорено). Сбор кандидатов в T5 — по `my_group` (выведенной из группы тела), без хардкода team_1.

**3. Тип-согласованность:** `_keeper_hands_dispatch -> Dictionary{intent,presentation,take_control}` (T2) — те же ключи читаются в `_enter_hands` (T3). `is_hands_active()`/`hands_charge_ratio()` (T3/T4) — те же имена в менеджерских гейтах (T3 Step 6, T4 Step 4). `_fire_hands(action, ratio)` (T4) — те же ветки A/X/B/Y наполняются T5–T9 через `match action`. `keeper_handoff_control(point)` (T2) — тот же вызов в T5/T6/T7. `_enter_outfield` (T9) — тот же вызов в `_trap_backpass` (T10). `KeeperPlayLogic.*`/`KeeperLogic.*`/`PassSystem.*` сигнатуры — как в Плане 1 / as-built.

**4. Риски исполнения (не блокеры, отмечены в шагах):**
- Launch-зависимые flow-тесты флейки (ждут `action_contact`) — гнать 2–3×, сверять с baseline (Global Constraints).
- `_body.get_tree()` доступен (тело в дереве); `_hands_intent_override` — тест-хук (в проде null → диспетч). Оба намеренны.
- Клип `keeper_drop_kick`/`keeper_pass`/`keeper_overhand_throw` существуют в glb (см. CLAUDE.md список). Тайминги `action_contact` — из существующего `ACTION_TIMING`; при отсутствии контакта — фолбэк по `_state_timer` (как у авто-раздачи).

## После Плана 2

- **План 3 — carry-бленд верх/низ** (`PlayerVisual.set_carry_pose`, `AnimationNodeBlend2` + bone-filter, mixamo-fallback «бег с коробкой»). Визуал бега вратаря с мячом в руках. Список костей верха — эмпирически по glb.
- **Фичи вне спека:** off-line выход вратаря (отдельный спек); полноценный решатель `AIKeeperHandsIntent` (ИИ сам бегает/выбирает раздачу — апгрейд без правок `keeper_ai`); второй human-вратарь / сетевой remote (шов+диспетч готовы, источники не добавлены).
- **Ручной плейтест (headless не покрывает):** ощущение движения вратаря в штрафной, заряд A тап↔удержание, направленность B, авто-наведение A на партнёра, 6-секундный таймер по ощущению, дроп Y → выбегание полевым, бэк-пас (ногой отдать вратарю → он не берёт руками). Камера/бленд бега — визуально.

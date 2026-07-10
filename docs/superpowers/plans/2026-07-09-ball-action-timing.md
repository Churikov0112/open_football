# Ball-Action Timing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Убрать рассинхрон «касание ↔ вылет мяча» и длинный замах у паса/удара, перенеся тайминг действия в `PlayerVisual` (сигналы `action_contact`/`action_finished`), а `match_manager` заставив реагировать на сигналы.

**Architecture:** `PlayerVisual` оборачивает существующий `AnimationNodeStateMachine` в `AnimationNodeBlendTree` с узлом `AnimationNodeTimeScale` (единый рычаг скорости проигрывания действия). Покадровый драйвер в `PlayerVisual._process` отсчитывает реальные секунды и шлёт `action_contact` (момент касания → геймплей бьёт мяч) и `action_finished` (конец → снять блокировку). `match_manager` подписывается на эти сигналы у визуала каждого игрока при спавне, хранит `(dir, power)` и применяет импульс/снимает блок по сигналам; покадровый `_tick_ball_action` и угаданная доля `0.45` удаляются.

**Tech Stack:** Godot 4.7 / GDScript (статическая типизация). Headless-проверки — скрипты `extends SceneTree` в `tests/`.

## Global Constraints

- **Godot exe (headless):** `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`
- **Ветка работы:** `feat/ball-action-timing` (уже создана; здесь же лежит незакоммиченная работа этапа 3 — коммитим только файлы своей задачи).
- **Стиль GDScript:** статическая типизация (`: Type`), `func _ready() -> void`, `&"StringName"` для имён параметров/узлов/сигналов. Соблюдать.
- **«Тест» = headless-скрипт** (`--headless -s res://tests/<check>.gd`), печатает `CHECK PASS`/`CHECK FAIL`, выходит с кодом 0/1. Рендер/анимацию headless не видит — точная синхронность «нога↔мяч» проверяется визуальной приёмкой пользователем.
- **Вне области (не трогать):** удары ИИ (`simple_ai._kick_towards_goal`) остаются мгновенными; инерция/тиры/защита мяча; вся локомоция.
- **Headless-загрузка без ошибок** после каждой задачи:
  `& "<godot>" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit` — без `SCRIPT ERROR`/`Parse Error`.

## File Structure

- `scripts/player/player_visual.gd` — презентация. Задачи 1–2: обёртка дерева TimeScale + драйвер тайминга и сигналы.
- `scripts/match/match_manager.gd` — геймплей. Задача 3: реакция на сигналы, удаление покадрового таймера, отмена при сбитии.
- `tests/check_player_visual_tree.gd` — новый (Задача 1): дерево перестроено, пути параметров рабочие.
- `tests/check_player_visual_action_timing.gd` — новый (Задача 2): сигналы приходят по таймингу; отмена подавляет касание.

---

### Task 1: `PlayerVisual` — обёртка StateMachine в BlendTree с TimeScale

Готовит рычаг скорости и стабильные пути параметров под задачу 2. Локомоция и one-shot действия продолжают работать; добавляется настраиваемый `parameters/TimeScale/scale`.

**Files:**
- Modify: `scripts/player/player_visual.gd` (`_build_anim_tree` хвост; `_process` путь бленда)
- Create: `tests/check_player_visual_tree.gd`

**Interfaces:**
- Consumes: существующий `AnimationNodeStateMachine sm` из `_build_anim_tree`.
- Produces: `AnimationTree` с именем `"AnimTree"`, `tree_root = AnimationNodeBlendTree`; параметры `parameters/sm/playback`, `parameters/sm/locomotion/blend_position`, `parameters/TimeScale/scale`. `_playback` берётся из `parameters/sm/playback`.

- [ ] **Step 1: Написать headless-проверку дерева**

Create `tests/check_player_visual_tree.gd`:

```gdscript
extends SceneTree

# add_child в _initialize не запускает _ready синхронно (дерево не крутит кадры),
# поэтому инстансим здесь, а проверяем в _process по is_node_ready().
var _inst: Node

func _initialize() -> void:
	var scene := load("res://scenes/player_visual.tscn") as PackedScene
	if scene == null:
		print("CHECK FAIL: не загрузилась scenes/player_visual.tscn")
		quit(1)
		return
	_inst = scene.instantiate()
	root.add_child(_inst)

func _process(_delta: float) -> bool:
	if _inst == null or not _inst.is_node_ready():
		return false
	var ok := true
	var at := _inst.get_node_or_null(^"AnimTree")
	if at == null:
		print("CHECK FAIL: нет узла AnimTree")
		print("CHECK FAIL"); quit(1); return true
	# playback существует по новому пути (значит StateMachine внутри BlendTree подключён)
	if at.get(&"parameters/sm/playback") == null:
		print("CHECK FAIL: нет parameters/sm/playback")
		ok = false
	# TimeScale-параметр читается/пишется
	at.set(&"parameters/TimeScale/scale", 2.0)
	if not is_equal_approx(at.get(&"parameters/TimeScale/scale"), 2.0):
		print("CHECK FAIL: parameters/TimeScale/scale не выставился, got=", at.get(&"parameters/TimeScale/scale"))
		ok = false
	# one-shot стейты по-прежнему резолвятся
	if not _inst.has_action("pass"):
		print("CHECK FAIL: has_action('pass') == false после перестройки дерева")
		ok = false
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true
```

- [ ] **Step 2: Запустить проверку — убедиться, что падает**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_tree.gd"
```
Expected: `CHECK FAIL` (узла `AnimTree` ещё нет — сейчас AnimationTree без имени и корень — StateMachine).

- [ ] **Step 3: Перестроить хвост `_build_anim_tree`**

В `scripts/player/player_visual.gd` заменить блок (сейчас начинается с `_ap = ap` и заканчивается `_playback.start(LOCOMOTION)`):

```gdscript
	_ap = ap
	_anim_tree = AnimationTree.new()
	_anim_tree.tree_root = sm
	add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(ap)
	_anim_tree.active = true
	_playback = _anim_tree.get(&"parameters/playback")
	if _playback != null:
		_playback.start(LOCOMOTION)
```

на:

```gdscript
	# Оборачиваем StateMachine в BlendTree с TimeScale — единый рычаг скорости проигрывания
	# действий (сжать замах, сохранив синхрон «нога↔мяч»). Локомоция идёт при scale=1.0.
	var bt := AnimationNodeBlendTree.new()
	bt.add_node(&"sm", sm, Vector2(200, 100))
	var ts := AnimationNodeTimeScale.new()
	bt.add_node(&"TimeScale", ts, Vector2(500, 100))
	bt.connect_node(&"TimeScale", 0, &"sm")
	bt.connect_node(&"output", 0, &"TimeScale")

	_ap = ap
	_anim_tree = AnimationTree.new()
	_anim_tree.name = "AnimTree"
	_anim_tree.tree_root = bt
	add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(ap)
	_anim_tree.active = true
	_anim_tree.set(&"parameters/TimeScale/scale", 1.0)
	_playback = _anim_tree.get(&"parameters/sm/playback")
	if _playback != null:
		_playback.start(LOCOMOTION)
```

- [ ] **Step 4: Обновить путь бленда в `_process`**

В `scripts/player/player_visual.gd`, в `_process`, заменить строку:

```gdscript
	_anim_tree.set(&"parameters/locomotion/blend_position", _blend)
```

на:

```gdscript
	_anim_tree.set(&"parameters/sm/locomotion/blend_position", _blend)
```

- [ ] **Step 5: Запустить проверку — убедиться, что проходит**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_tree.gd"
```
Expected: `CHECK PASS`, код 0.

- [ ] **Step 6: Регрессия — старые проверки и загрузка**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_actions.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
```
Expected: `check_player_visual_actions` → `CHECK PASS`; загрузка без `SCRIPT ERROR`/`Parse Error`.

- [ ] **Step 7: Commit**

```bash
git add scripts/player/player_visual.gd tests/check_player_visual_tree.gd tests/check_player_visual_tree.gd.uid
git commit -m "feat(PlayerVisual): wrap StateMachine in BlendTree+TimeScale for action speed"
```
(`.uid` создаётся Godot при импорте; если его нет — не указывать.)

---

### Task 2: `PlayerVisual` — драйвер тайминга и сигналы действия

Добавляет `action_contact`/`action_finished`, конфиг `ACTION_TIMING`, покадровый драйвер и отмену. `trigger()` начинает возвращать `bool` (успех старта).

**Files:**
- Modify: `scripts/player/player_visual.gd`
- Create: `tests/check_player_visual_action_timing.gd`

**Interfaces:**
- Consumes: `parameters/TimeScale/scale`, `_playback` (Task 1); `_resolve_action`, `action_length`, `LOCOMOTION`.
- Produces:
  - `signal action_contact(action: String)`, `signal action_finished(action: String)`.
  - `func trigger(action: String) -> bool` (было `-> void`).
  - `func cancel_action() -> void`.
  - `const ACTION_TIMING := { "pass": {"contact": 0.2, "lock": 0.4, "speed": 1.5} }`.

- [ ] **Step 1: Написать headless-проверку тайминга**

Create `tests/check_player_visual_action_timing.gd`:

```gdscript
extends SceneTree

# Проверяем: (A) нормальный путь — trigger('pass') → сигнал contact, затем finished;
# (B) отмена — trigger + cancel_action → contact НЕ приходит, finished не обязателен.
var _inst: Node
var _log: Array = []
var _phase := 0
var _pt := 0.0  # накопленное реальное время текущей фазы (не зависит от fps)

func _initialize() -> void:
	var scene := load("res://scenes/player_visual.tscn") as PackedScene
	_inst = scene.instantiate()
	root.add_child(_inst)

func _process(delta: float) -> bool:
	if _inst == null or not _inst.is_node_ready():
		return false
	_pt += delta
	if _phase == 0:
		_inst.action_contact.connect(func(a: String) -> void: _log.append("contact:" + a))
		_inst.action_finished.connect(func(a: String) -> void: _log.append("finished:" + a))
		var started: bool = _inst.trigger("pass")
		if not started:
			print("CHECK FAIL: trigger('pass') вернул false")
			quit(1); return true
		_phase = 1; _pt = 0.0
		return false
	if _phase == 1:
		if "finished:pass" in _log:
			var ok := true
			if not ("contact:pass" in _log):
				print("CHECK FAIL: не пришёл contact"); ok = false
			elif _log.find("contact:pass") > _log.find("finished:pass"):
				print("CHECK FAIL: finished раньше contact, log=", _log); ok = false
			if not ok:
				print("CHECK FAIL"); quit(1); return true
			print("CHECK: нормальный путь ", _log)
			_log.clear(); _phase = 2; _pt = 0.0
			_inst.trigger("pass")
			_inst.cancel_action()
			return false
		if _pt > 2.0:
			print("CHECK FAIL: finished не пришёл за 2с, log=", _log)
			quit(1); return true
		return false
	if _phase == 2:
		if _pt > 1.0:
			if "contact:pass" in _log:
				print("CHECK FAIL: после cancel пришёл contact, log=", _log)
				quit(1); return true
			print("CHECK: отмена подавила contact ", _log)
			print("CHECK PASS")
			quit(0); return true
		return false
	return false
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_action_timing.gd"
```
Expected: ошибка/FAIL — сигналов `action_contact`/`action_finished` и `cancel_action` ещё нет; `trigger` не запускает драйвер.

- [ ] **Step 3: Добавить сигналы, конфиг и переменные драйвера**

В `scripts/player/player_visual.gd` сразу после строки `extends Node3D` (перед первым `const`) добавить сигналы:

```gdscript

## Момент касания мячом ногой (геймплей в этот миг придаёт импульс мячу).
signal action_contact(action: String)
## Действие завершилось — управление можно вернуть.
signal action_finished(action: String)
```

Затем после блока `const LOOP_CLIPS := [...]` добавить конфиг:

```gdscript
## Тайминг действия (реальные секунды): contact — до касания; lock — общая длительность
## до action_finished; speed — множитель скорости проигрывания (сжать замах, сохранив синхрон).
## Тюнится визуальной приёмкой. Действия без записи → contact=0, lock=длина_клипа, speed=1.
const ACTION_TIMING := {
	"pass": {"contact": 0.2, "lock": 0.4, "speed": 1.5},
}
```

Затем в блоке переменных (после `var _ap: AnimationPlayer`) добавить:

```gdscript
var _active_action: String = ""   # выполняемое действие ("" = нет)
var _action_elapsed: float = 0.0  # прошло реальных секунд с старта действия
var _action_contact_at: float = 0.0
var _action_lock_at: float = 0.0
var _action_contact_done: bool = false
```

- [ ] **Step 4: Переписать `trigger()` (теперь `-> bool` + запуск драйвера)**

Заменить существующую функцию `trigger` целиком:

```gdscript
## Разовое действие (kick/pass/header/…): travel в one-shot стейт, авто-возврат в локомоцию.
## Принимает семантическое имя (см. ACTION_CLIPS) либо прямое имя клипа.
func trigger(action: String) -> void:
	if _playback == null:
		push_warning("PlayerVisual.trigger('%s'): AnimationTree не готов (фолбэк-капсула?)" % action)
		return
	var state := _resolve_action(action)
	if state == "":
		push_warning("PlayerVisual.trigger('%s'): нет клипа под это действие" % action)
		return
	_playback.travel(StringName(state))
```

на:

```gdscript
## Разовое действие (kick/pass/header/…): travel в one-shot стейт + запуск таймингового
## драйвера (сигналы action_contact/action_finished). Возвращает true, если действие
## стартовало (иначе — фолбэк/нет клипа, геймплей делает импульс сам).
func trigger(action: String) -> bool:
	if _playback == null:
		push_warning("PlayerVisual.trigger('%s'): AnimationTree не готов (фолбэк-капсула?)" % action)
		return false
	var state := _resolve_action(action)
	if state == "":
		push_warning("PlayerVisual.trigger('%s'): нет клипа под это действие" % action)
		return false
	_playback.travel(StringName(state))
	var contact := 0.0
	var lock := action_length(action)
	var speed := 1.0
	if ACTION_TIMING.has(action):
		var t: Dictionary = ACTION_TIMING[action]
		contact = float(t.get("contact", 0.0))
		lock = float(t.get("lock", lock))
		speed = float(t.get("speed", 1.0))
	if lock <= 0.0:
		lock = 0.5
	_set_action_speed(speed)
	_active_action = action
	_action_elapsed = 0.0
	_action_contact_at = contact
	_action_lock_at = lock
	_action_contact_done = false
	return true

## Отменить текущее действие без сигнала касания (напр., игрока сбили на замахе).
func cancel_action() -> void:
	if _active_action == "":
		return
	_active_action = ""
	_set_action_speed(1.0)
	if _playback != null:
		_playback.travel(LOCOMOTION)

## Скорость проигрывания действия через TimeScale-узел BlendTree.
func _set_action_speed(s: float) -> void:
	if _anim_tree != null:
		_anim_tree.set(&"parameters/TimeScale/scale", s)
```

- [ ] **Step 5: Добавить драйвер в `_process`**

В `scripts/player/player_visual.gd`, в конец функции `_process` (после строки `_anim_tree.set(&"parameters/sm/locomotion/blend_position", _blend)`) добавить:

```gdscript
	if _active_action != "":
		_action_elapsed += delta
		if not _action_contact_done and _action_elapsed >= _action_contact_at:
			_action_contact_done = true
			action_contact.emit(_active_action)
		if _action_elapsed >= _action_lock_at:
			var done := _active_action
			_active_action = ""
			_set_action_speed(1.0)
			action_finished.emit(done)
```

- [ ] **Step 6: Запустить проверку тайминга — должна пройти**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_action_timing.gd"
```
Expected: `CHECK PASS`, код 0.

- [ ] **Step 7: Регрессия — прочие проверки и загрузка**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_tree.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_actions.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
```
Expected: оба `CHECK PASS`; загрузка без `SCRIPT ERROR`/`Parse Error`. (Задача 3 обновит вызывающий код `match_manager`, где `trigger` теперь возвращает `bool` — до неё старый вызов `visual.trigger(action)` как statement валиден.)

- [ ] **Step 8: Commit**

```bash
git add scripts/player/player_visual.gd tests/check_player_visual_action_timing.gd tests/check_player_visual_action_timing.gd.uid
git commit -m "feat(PlayerVisual): action timing driver with contact/finished signals"
```

---

### Task 3: `match_manager` — реакция на сигналы, отмена при сбитии

Убирает угаданную долю и покадровый `_tick_ball_action`; подписывает визуал каждого игрока на сигналы при спавне; применяет импульс по `action_contact`, снимает блокировку по `action_finished`; отменяет действие при сбитии подкатом.

**Files:**
- Modify: `scripts/match/match_manager.gd`

**Interfaces:**
- Consumes: `PlayerVisual.action_contact`, `action_finished`, `trigger() -> bool`, `cancel_action()` (Task 2); `_player_visual()`.
- Produces: обработчики `_on_action_contact(action, player)`, `_on_action_finished(action, player)`, `_cancel_ball_action(player)`; `_start_ball_action` без покадрового таймера.

- [ ] **Step 1: Заменить commit-переменные**

В `scripts/match/match_manager.gd` заменить блок (сейчас строки ~34–43):

```gdscript
# Commit-действие с мячом (пас/удар): на время клипа управление игроком заблокировано,
# импульс мячу применяется в момент касания ногой, а не сразу по нажатию.
const BALL_ACTION_CONTACT_FRAC := 0.45  # доля клипа до касания мячом (тюнится по фидбеку)
const BALL_ACTION_FALLBACK_LEN := 0.7   # длительность, если длину клипа получить не удалось
var _action_player: CharacterBody3D     # кто выполняет действие (управление заблокировано)
var _action_lock_timer: float = 0.0     # оставшееся время блокировки управления
var _action_contact_timer: float = 0.0  # оставшееся время до касания (импульса)
var _action_fired: bool = true          # импульс уже применён?
var _action_dir: Vector3 = Vector3.ZERO
var _action_power: float = 0.0
```

на:

```gdscript
# Commit-действие с мячом (пас/удар): пока идёт клип, управление игроком заблокировано.
# Тайминг живёт в PlayerVisual — импульс применяется по сигналу action_contact,
# блокировка снимается по action_finished.
var _action_player: CharacterBody3D     # кто выполняет действие (управление заблокировано)
var _action_dir: Vector3 = Vector3.ZERO
var _action_power: float = 0.0
```

- [ ] **Step 2: Убрать покадровый тик из `_physics_process`**

Заменить:

```gdscript
func _physics_process(delta: float) -> void:
	_handle_dribbling()
	_tick_ball_action(delta)
	_handle_player_input(delta)
```

на:

```gdscript
func _physics_process(delta: float) -> void:
	_handle_dribbling()
	_handle_player_input(delta)
```

- [ ] **Step 3: Упростить гейт блокировки в `_handle_player_input`**

Заменить:

```gdscript
	# Управление перехвачено commit-действием (пас/удар): ни движения, ни нового действия.
	if _action_player == controlled_player and _action_lock_timer > 0.0:
		return
```

на:

```gdscript
	# Управление перехвачено commit-действием (пас/удар): ни движения, ни нового действия.
	if _action_player == controlled_player:
		return
```

- [ ] **Step 4: Переписать `_start_ball_action` и `_tick_ball_action` → обработчики сигналов**

Заменить обе функции `_start_ball_action` и `_tick_ball_action` целиком (сейчас идут подряд, от `## Начать commit-действие…` до конца `_tick_ball_action`) на:

```gdscript
## Начать commit-действие с мячом: развернуть игрока, проиграть анимацию, заблокировать
## управление. Импульс мячу и снятие блокировки — по сигналам визуала (contact/finished).
## Если визуала/клипа нет (фолбэк) — импульс сразу, без блокировки.
func _start_ball_action(player_node: CharacterBody3D, dir: Vector3, power: float, action: String) -> void:
	if _action_player != null:
		return  # уже идёт действие — игнорируем повторный ввод
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		player_node.rotation.y = atan2(-flat.x, -flat.z)
	var visual := _player_visual(player_node)
	if visual != null and visual.trigger(action):
		_action_player = player_node
		_action_dir = dir
		_action_power = power
	else:
		if ball.has_method(&"kick"):
			ball.kick(dir, power)  # фолбэк без анимации: бьём сразу


## Момент касания ногой: придать импульс мячу.
func _on_action_contact(_action: String, player: Node) -> void:
	if player == _action_player and ball.has_method(&"kick"):
		ball.kick(_action_dir, _action_power)


## Действие завершилось: вернуть управление.
func _on_action_finished(_action: String, player: Node) -> void:
	if player == _action_player:
		_action_player = null


## Отменить действие игрока (сбили подкатом на замахе): без импульса, вернуть управление.
func _cancel_ball_action(player: Node) -> void:
	if _action_player != player:
		return
	_action_player = null
	var visual := _player_visual(player)
	if visual != null:
		visual.cancel_action()
```

- [ ] **Step 5: Подписать визуал на сигналы при спавне (3 точки)**

В `scripts/match/match_manager.gd` — в трёх местах, где создаётся визуал, добавить подключение сигналов сразу после `apply_appearance(...)`.

В `_ready()` (домашний игрок), после `home_visual.apply_appearance({"kit_color": Color(0.1, 0.1, 0.9)})`:

```gdscript
	home_visual.action_contact.connect(_on_action_contact.bind(player_home))
	home_visual.action_finished.connect(_on_action_finished.bind(player_home))
```

В `_setup_away_player()`, после `visual.apply_appearance({"kit_color": Color(0.9, 0.1, 0.1)})`:

```gdscript
	visual.action_contact.connect(_on_action_contact.bind(new_player))
	visual.action_finished.connect(_on_action_finished.bind(new_player))
```

В `_setup_teammate()`, после `visual.apply_appearance({"kit_color": Color(0.1, 0.1, 0.9)})`:

```gdscript
	visual.action_contact.connect(_on_action_contact.bind(new_player))
	visual.action_finished.connect(_on_action_finished.bind(new_player))
```

- [ ] **Step 6: Отмена действия при сбитии подкатом**

В обработчике попадания подката, после строки `body.add_to_group("fallen")` (сейчас строка ~761), добавить:

```gdscript
	_cancel_ball_action(body)
```

- [ ] **Step 7: Проверить headless-загрузку**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
```
Expected: без `SCRIPT ERROR`/`Parse Error` (в частности, `trigger(action)` теперь используется как `bool`-выражение в `_start_ball_action`).

- [ ] **Step 8: Прогнать все headless-проверки**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_tree.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_action_timing.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_actions.gd"
```
Expected: три `CHECK PASS`.

- [ ] **Step 9: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(match): drive ball impulse/lock from PlayerVisual action signals"
```

- [ ] **Step 10: Визуальная приёмка (пользователь)**

Передать пользователю:

> Запусти игру (F5 → Start). Подведи игрока к мячу:
> 1. **Space/E** — мяч улетает **в момент касания ногой** (не раньше/позже)?
> 2. Замах у паса **короткий**, соперник не успевает отобрать?
> 3. Во время действия WASD **игнорируется**?
> 4. Если по бьющему проходит **подкат** во время замаха — мяч **не** вылетает?
>
> Тюнинг (если тайминг/скорость не идеальны) — три числа в `ACTION_TIMING["pass"]` в
> `scripts/player/player_visual.gd`: `contact` (когда вылетает мяч), `lock` (длительность
> блокировки), `speed` (скорость замаха). Скажи, что подкрутить.

---

## Self-Review

**Spec coverage** (против `2026-07-09-ball-action-timing-design.md`):
- Тайминг в `PlayerVisual`, геймплей реагирует сигналами → Task 2 (сигналы+драйвер), Task 3 (подписка/обработчики). ✅
- Убрать угаданную `0.45` и покадровый `_tick_ball_action` → Task 3 Step 1–2, 4. ✅
- Короткий замах через тюнинг (`contact`/`lock`/`speed` в одном месте) → Task 2 `ACTION_TIMING`; рычаг `speed` через TimeScale → Task 1. ✅
- Отмена действия при сбитии → Task 3 Step 4 (`_cancel_ball_action`) + Step 6 (вызов после `fallen`). ✅
- Фолбэк (нет визуала/клипа) без залипания блокировки → Task 3 Step 4 (`trigger()->bool`, иначе `ball.kick` сразу). ✅
- Тестирование headless + визуальная приёмка → Tasks 1–3 тесты + Task 3 Step 10. ✅
- Вне области (ИИ-удары, инерция, локомоция) — не трогаются. ✅

**Placeholder scan:** плейсхолдеров нет — весь GDScript приведён целиком, тесты полные.

**Type consistency:** `trigger(action: String) -> bool`, `cancel_action() -> void`, `_set_action_speed(s: float)`, сигналы `action_contact(action: String)`/`action_finished(action: String)`, обработчики `_on_action_contact(_action, player)`/`_on_action_finished(_action, player)`/`_cancel_ball_action(player)`, параметры `parameters/sm/playback`, `parameters/sm/locomotion/blend_position`, `parameters/TimeScale/scale`, узел `AnimTree` — согласованы между Tasks 1–3.

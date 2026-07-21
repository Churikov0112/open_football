# Corner Kick (Фаза A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Розыгрыш углового удара по образцу penalty/free-kick: отдельный контроллер-автомат `SETUP→AIM→STRIKE`, навес верхом (лоб с ручной закруткой и регулируемой высотой) или короткий наземный пас подбежавшему партнёру; активация по клавише **C**, сторона — по ближайшему углу.

**Architecture:** Новый `CornerController` (`extends Node`, узел в `match.tscn` как penalty/free-kick) + чистая математика `CornerLogic` (`class_name ... extends Object`, не читает `FootballConstants`). Переиспользуем готовые чистые функции `FreeKickLogic`/`PassSystem`/`KeeperLogic` и root-motion клипы `penalty_l`/`penalty_r`. Плюс общая (временная) механика переключения ноги L/R в трёх сет-пис-контроллерах.

**Tech Stack:** Godot 4.7, GDScript. Headless-тесты `tests/check_*.gd` (extends SceneTree, печатают `CHECK PASS`/`FAIL`, exit 0/1).

## Global Constraints

- **Отвечать пользователю по-русски** (код/идентификаторы/команды не переводим).
- **Чистая математика (`*Logic`) НИКОГДА не читает `FootballConstants`** — весь тюнинг передаётся параметрами. Так функции headless-тестируемы без автолоада.
- **ИИ — это child-`Brain`-компонент**, а не `set_script` на теле. Спавн-тела конвертируются в ИИ через `ai_script.new()` → `add_child`.
- **Ввод строится в коде** в `match_manager._setup_inputs()` — `project.godot` мёртв. Всегда править `_setup_inputs()`.
- **`_manager` типизирован как `Node`** в контроллере: `var x := _manager.some_method()` НЕ компилируется («cannot infer the type»). Использовать явный тип (`var x: PlayerVisual = ...`) или вызов без присваивания. То же с `keeper.brain()` — `var kb: Node = keeper.brain()`.
- **Порядок при передаче управления получателю:** `_manager.assign_controlled_player(receiver)` вызывать **ДО** `_release()`/конверта тел (конверт читает `controlled_player`).
- **Валидация проекта** (обе нужны — ловят разное):
  - `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
  - `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
  - Известный baseline второй команды (НЕ регресс): `ERROR: Condition "!is_inside_tree()" is true.`, дубль-регистрация `ACTION_CLIPS` (`states.has(p_name)` + два transition-дубля, ×кол-во `PlayerVisual`), `ERROR: Cannot get class 'WorldEnvironment3D'.`. Диффать по **категориям/тексту** ошибок, не по счётчику.
- **Запуск одного headless-теста:** `& "<godot exe>" --path "<repo>" --headless -s "res://tests/<name>.gd"`.

---

## Файловая структура

- **Create** `scripts/match/corner_logic.gd` — чистая угловая математика (`class_name CornerLogic extends Object`).
- **Create** `scripts/match/corner_controller.gd` — автомат углового (`extends Node`).
- **Create** `tests/check_corner_logic.gd` — юнит-тест чистых функций.
- **Create** `tests/check_corner_flow.gd` — headless-смоук флоу (навес).
- **Modify** `scripts/data/football_constants.gd` — секция `CORNER`.
- **Modify** `scripts/match/match_manager.gd` — ввод, создание контроллера, гейтинг `_physics_process`/`_process`, активация, поля/методы.
- **Modify** `scripts/match/penalty_controller.gd` — переключение ноги L/R (временное).
- **Modify** `scripts/match/free_kick_controller.gd` — переключение ноги L/R (временное).

---

## Task 1: `CornerLogic` — чистая угловая математика

**Files:**
- Create: `scripts/match/corner_logic.gd`
- Test: `tests/check_corner_logic.gd`

**Interfaces:**
- Consumes: ничего (чистые статические функции).
- Produces:
  - `CornerLogic.side_for_player(player_x: float) -> float` — `+1.0`/`-1.0` (знак X; при `x==0` → `+1.0`).
  - `CornerLogic.corner_spot(side: float, half_width: float, goal_line_z: float, inset: float, ball_radius: float) -> Vector3` — точка мяча в углу.
  - `CornerLogic.foot_for_side(side: float) -> String` — `"penalty_l"` для `side>0`, иначе `"penalty_r"`.
  - `CornerLogic.peak_for_stick_y(stick_y: float, peak_head: float, peak_standard: float, peak_svecha: float) -> float` — высота дуги от стика Y (вверх=+1→head, 0→standard, вниз=-1→svecha).
  - `CornerLogic.box_target_positions(goal_line_z: float, into: float, lateral: float, depth: float, y: float) -> Array` — 2 позиции целей в штрафной (`[Vector3, Vector3]`).
  - `CornerLogic.short_option_pos(spot: Vector3, side: float, into: float, dist: float, y: float) -> Vector3` — позиция короткой опции (партнёр вглубь поля вдоль линии).

- [ ] **Step 1: Написать падающий тест `tests/check_corner_logic.gd`**

```gdscript
extends SceneTree
## Headless-проверка чистых функций CornerLogic.

func _init() -> void:
	var ok := true
	ok = _check_side() and ok
	ok = _check_spot() and ok
	ok = _check_foot() and ok
	ok = _check_peak() and ok
	ok = _check_targets() and ok
	ok = _check_short() and ok
	if ok:
		print("CHECK PASS: corner_logic")
		quit(0)
	else:
		print("CHECK FAIL: corner_logic")
		quit(1)

func _check_side() -> bool:
	if not (is_equal_approx(CornerLogic.side_for_player(20.0), 1.0)
			and is_equal_approx(CornerLogic.side_for_player(-5.0), -1.0)
			and is_equal_approx(CornerLogic.side_for_player(0.0), 1.0)):
		print("  FAIL side")
		return false
	return true

func _check_spot() -> bool:
	# Правый угол атакуемой линии Home (z=-52.5): x чуть меньше 34, z чуть больше -52.5 (в поле), y=BALL_RADIUS.
	var s := CornerLogic.corner_spot(1.0, 34.0, -52.5, 0.5, 0.11)
	if not (is_equal_approx(s.x, 33.5) and is_equal_approx(s.z, -52.0) and is_equal_approx(s.y, 0.11)):
		print("  FAIL spot: ", s)
		return false
	var l := CornerLogic.corner_spot(-1.0, 34.0, -52.5, 0.5, 0.11)
	if not (is_equal_approx(l.x, -33.5) and is_equal_approx(l.z, -52.0)):
		print("  FAIL spot left: ", l)
		return false
	return true

func _check_foot() -> bool:
	if CornerLogic.foot_for_side(1.0) != "penalty_l" or CornerLogic.foot_for_side(-1.0) != "penalty_r":
		print("  FAIL foot")
		return false
	return true

func _check_peak() -> bool:
	var head := CornerLogic.peak_for_stick_y(1.0, 4.0, 7.0, 12.0)
	var mid := CornerLogic.peak_for_stick_y(0.0, 4.0, 7.0, 12.0)
	var sv := CornerLogic.peak_for_stick_y(-1.0, 4.0, 7.0, 12.0)
	if not (is_equal_approx(head, 4.0) and is_equal_approx(mid, 7.0) and is_equal_approx(sv, 12.0)):
		print("  FAIL peak endpoints: ", head, " ", mid, " ", sv)
		return false
	# Монотонность: чем ниже стик, тем выше дуга.
	if not (head < mid and mid < sv):
		print("  FAIL peak monotonic")
		return false
	return true

func _check_targets() -> bool:
	var t := CornerLogic.box_target_positions(-52.5, 1.0, 6.0, 11.0, 0.5)
	if t.size() != 2:
		print("  FAIL targets size")
		return false
	# Обе цели в поле от линии (z = -52.5 + 1*11 = -41.5), по разные стороны от центра.
	var a: Vector3 = t[0]
	var b: Vector3 = t[1]
	if not (is_equal_approx(a.z, -41.5) and is_equal_approx(b.z, -41.5) and a.x < 0.0 and b.x > 0.0):
		print("  FAIL targets pos: ", a, " ", b)
		return false
	return true

func _check_short() -> bool:
	# Короткая опция: вглубь поля от угла (z сдвинут на into*dist), x ближе к центру.
	var spot := CornerLogic.corner_spot(1.0, 34.0, -52.5, 0.5, 0.11)
	var p := CornerLogic.short_option_pos(spot, 1.0, 1.0, 7.0, 0.5)
	if not (p.z > spot.z and absf(p.x) < absf(spot.x) and is_equal_approx(p.y, 0.5)):
		print("  FAIL short: ", p)
		return false
	return true
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_corner_logic.gd"`
Expected: FAIL (парсер не находит класс `CornerLogic` — ошибка загрузки).

- [ ] **Step 3: Написать `scripts/match/corner_logic.gd`**

```gdscript
class_name CornerLogic
extends Object
## Чистая математика углового. НИКОГДА не читает FootballConstants — тюнинг параметрами.

## Сторона углового по X игрока в момент активации: +1 (правый угол) / -1 (левый).
static func side_for_player(player_x: float) -> float:
	return -1.0 if player_x < 0.0 else 1.0

## Точка мяча в углу: чуть внутрь поля от точного угла (на inset по обеим осям), y на радиусе мяча.
## into = в поле от лицевой линии (-signf(goal_line_z)); goal_line_z<0 → into=+1.
static func corner_spot(side: float, half_width: float, goal_line_z: float, inset: float, ball_radius: float) -> Vector3:
	var into := -signf(goal_line_z)
	return Vector3(side * (half_width - inset), ball_radius, goal_line_z + into * inset)

## «Открытой» ногой в поле: правый угол → левая нога, левый угол → правая. Ключ ACTION_CLIPS.
static func foot_for_side(side: float) -> String:
	return "penalty_l" if side > 0.0 else "penalty_r"

## Высота дуги навеса по стику Y ∈ [-1,1]: вверх(+1)=head (низкая/быстрая), 0=standard, вниз(-1)=svecha (высокая/долгая).
static func peak_for_stick_y(stick_y: float, peak_head: float, peak_standard: float, peak_svecha: float) -> float:
	var y := clampf(stick_y, -1.0, 1.0)
	if y >= 0.0:
		return lerpf(peak_standard, peak_head, y)
	return lerpf(peak_standard, peak_svecha, -y)

## 2 позиции целей в штрафной (ближняя/дальняя зона по X), на глубине depth в поле от линии.
static func box_target_positions(goal_line_z: float, into: float, lateral: float, depth: float, y: float) -> Array:
	var z := goal_line_z + into * depth
	return [Vector3(-lateral, y, z), Vector3(lateral, y, z)]

## Позиция короткой опции: вглубь поля вдоль линии (на dist по Z в поле), ближе к центру по X.
static func short_option_pos(spot: Vector3, side: float, into: float, dist: float, y: float) -> Vector3:
	return Vector3(spot.x - side * 2.0, y, spot.z + into * dist)
```

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_corner_logic.gd"`
Expected: `CHECK PASS: corner_logic`, exit 0.

- [ ] **Step 5: Коммит**

```bash
git add scripts/match/corner_logic.gd tests/check_corner_logic.gd
git commit -m "feat(corner): add CornerLogic pure math + headless test"
```

---

## Task 2: Константы секции `CORNER`

**Files:**
- Modify: `scripts/data/football_constants.gd` (добавить блок в конец файла)

**Interfaces:**
- Consumes: ничего.
- Produces (константы `FootballConstants.*`): `CORNER_INSET`, `CORNER_AIM_ARC`, `CORNER_AIM_SPEED`, `CORNER_CHARGE_MAX_TIME`, `CORNER_PASS_MIN_SPEED`, `CORNER_PASS_MAX_SPEED`, `CORNER_LOB_PEAK_HEAD`, `CORNER_LOB_PEAK_STANDARD`, `CORNER_LOB_PEAK_SVECHA`, `CORNER_LOB_MIN_DIST`, `CORNER_LOB_MAX_DIST`, `CORNER_CURL_SCALE`, `CORNER_CURL_MAX`, `CORNER_TARGET_LATERAL`, `CORNER_TARGET_DEPTH`, `CORNER_SHORT_DIST`, `CORNER_FOOT_LATERAL`, `CORNER_RUNUP_DIST`, `CORNER_CAM_BACK`, `CORNER_CAM_HEIGHT`, `CORNER_CAM_LOOK_Y`. (Root-motion разбег переиспользует `PEN_ROOT_SCALE`.)

- [ ] **Step 1: Добавить блок констант в конец `scripts/data/football_constants.gd`**

```gdscript

# ═══════════════════════════════════════════
#  CORNER (Фаза A)
# ═══════════════════════════════════════════

# Геометрия/разбег. Разбег — клипы penalty_l/penalty_r с root-motion, масштаб PEN_ROOT_SCALE.
const CORNER_INSET := 0.5             # мяч на столько внутрь поля от точного угла, м
const CORNER_RUNUP_DIST := 2.8        # пред-расстановка бьющего назад под разбег (мировые метры)
const CORNER_FOOT_LATERAL := 0.4      # латеральный сдвиг бьющего под опорную ногу, м
# Прицел/камера.
const CORNER_AIM_ARC := 1.4           # ±сектор поворота heading от базового (рад)
const CORNER_AIM_SPEED := 1.6         # скорость поворота heading стиком, рад/с
const CORNER_CAM_BACK := 8.0          # отступ камеры назад от угла вдоль -heading, м
const CORNER_CAM_HEIGHT := 4.0        # высота камеры, м
const CORNER_CAM_LOOK_Y := 2.0        # высота точки взгляда камеры, м
# Заряд/сила.
const CORNER_CHARGE_MAX_TIME := 0.9   # макс. время заряда (A/B), с
const CORNER_PASS_MIN_SPEED := 12.0   # скорость наземного паса A при мин. заряде, м/с
const CORNER_PASS_MAX_SPEED := 30.0   # при полном заряде, м/с
# Навес B: высота дуги по стику Y (все три садятся в одну точку, отличается время полёта).
const CORNER_LOB_PEAK_HEAD := 4.0     # стик вверх — низкая быстрая (на уровень головы), м
const CORNER_LOB_PEAK_STANDARD := 7.0 # нейтраль — стандарт, м
const CORNER_LOB_PEAK_SVECHA := 12.0  # стик вниз — «свеча» (высокая, летит дольше всех), м
const CORNER_LOB_MIN_DIST := 12.0     # дальность приземления навеса без цели, мин. заряд, м
const CORNER_LOB_MAX_DIST := 40.0     # без цели, полный заряд, м
const CORNER_CURL_SCALE := 7.0        # накопленный боковой ввод стика → величина curl.z
const CORNER_CURL_MAX := 3.5          # кламп |curl.z|
# Спавны.
const CORNER_TARGET_LATERAL := 6.0    # цели навеса: сдвиг по X от центра, м
const CORNER_TARGET_DEPTH := 11.0     # цели навеса: отступ в поле от линии ворот, м
const CORNER_SHORT_DIST := 7.0        # короткая опция: партнёр вглубь поля вдоль линии, м
```

- [ ] **Step 2: Проверить парс headless-загрузкой**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: загрузка без новых ошибок парсинга (`football_constants.gd` — автолоад, парсится всегда).

- [ ] **Step 3: Коммит**

```bash
git add scripts/data/football_constants.gd
git commit -m "feat(corner): add CORNER tuning constants"
```

---

## Task 3: `CornerController` + интеграция в `match_manager`

**Files:**
- Create: `scripts/match/corner_controller.gd`
- Modify: `scripts/match/match_manager.gd` (ввод, поля/методы, создание, гейтинг, активация, камера)
- Test: `tests/check_corner_flow.gd`

**Interfaces:**
- Consumes: `CornerLogic.*` (Task 1), `FootballConstants.CORNER_*` (Task 2), `FreeKickLogic.base_heading/rotate_heading/curl_from_stick`, `PassSystem.launch_ground/launch_lob`, `KeeperLogic.drag_horizontal_speed`, `PlayerFactory.spawn`, `PlayerMotor.find_on`, `PlayerConfig`, ball `launch/launch_curl/is_flight/release_dribble/clear_last_kicker`, `PlayerVisual.trigger/consume_root_motion/cancel_action/recover`, менеджер `assign_controlled_player/begin_pass_receive/set_field_ai_active/is_celebrating/set_corner_active/set_corner_cam_pose/controlled_player/_team_home/_team_away/_keeper_brain`.
- Produces:
  - `CornerController.setup(manager, ball, camera_pivot, power_bar, keeper) -> void`
  - `CornerController.is_active() -> bool`
  - `CornerController.start(kicker: CharacterBody3D, goal_line_z: float) -> void`
  - `CornerController.update(delta: float) -> void`
  - `CornerController._start_charge(kind: String) -> void` / `._fire_charge(ratio: float) -> void` (используются тестом).
  - `MatchManager.is_corner_active() -> bool`, `.set_corner_active(on: bool) -> void`, `.set_corner_cam_pose(pose: Transform3D) -> void`.

- [ ] **Step 1: Написать падающий смоук-тест `tests/check_corner_flow.gd`**

```gdscript
extends SceneTree
## Headless smoke-тест флоу углового: грузим match.tscn, стартуем розыгрыш и навешиваем (в обход
## Input), крутим кадры — мяч получил импульс, режим углового снялся, без крашей. Интерактив
## (прицел/камера/анимация) headless не покрывает.

var _mm: Node
var _corner: Node
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
		_corner = _mm.get_node_or_null("CornerController")
		if _corner == null:
			print("CHECK FAIL: нет узла CornerController")
			return true
		_corner.start(_mm.controlled_player, _mm._keeper_brain.goal_line_z)
		_started = true
		if not _mm.is_corner_active():
			print("CHECK FAIL: режим углового не включился после start")
			return true
		return false
	# Имитируем навес B на 70% заряда (минуем Input).
	if _elapsed > 0.3 and _started and not _fired:
		_corner._start_charge("lob")
		_corner._fire_charge(0.7)
		_fired = true
		return false
	if _fired:
		_max_ball_speed = maxf(_max_ball_speed, _mm.ball.linear_velocity.length())
	if _elapsed > 4.0:
		var released: bool = not _mm.is_corner_active()
		var launched: bool = _max_ball_speed > 1.0
		print("SMOKE: max_ball_speed=", _max_ball_speed, " corner_active=", _mm.is_corner_active())
		if released and launched:
			print("CHECK PASS: corner flow (launched + released)")
			quit(0)
		else:
			print("CHECK FAIL: released=", released, " launched=", launched)
			quit(1)
		return true
	return false
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_corner_flow.gd"`
Expected: `CHECK FAIL: нет узла CornerController`.

- [ ] **Step 3: Создать `scripts/match/corner_controller.gd`**

```gdscript
extends Node
## Контроллер розыгрыша углового (Фаза A). Автомат SETUP→AIM→STRIKE. Прицел heading (стик-X),
## высота навеса (стик-Y до нажатия B), заряд (A наземный пас / B навес), закрутка стиком на
## разбеге. Математика — CornerLogic + переиспользуемые FreeKickLogic/PassSystem/KeeperLogic.

signal struck

enum Phase { IDLE, SETUP, AIM, STRIKE }

var _manager: Node
var _ball: RigidBody3D
var _camera_pivot: Node3D
var _power_bar: ProgressBar
var _keeper: CharacterBody3D
var _keeper_brain: Node

var _phase: int = Phase.IDLE
var _kicker: CharacterBody3D
var _goal_line_z: float = 0.0
var _into: float = 1.0
var _side: float = 1.0
var _spot: Vector3 = Vector3.ZERO
var _base_heading: Vector3 = Vector3.FORWARD
var _heading: Vector3 = Vector3.FORWARD
var _foot: String = "penalty_r"
var _peak_height: float = 7.0        # высота дуги навеса (стик-Y), фиксируется при нажатии B

var _charging: bool = false
var _charge: float = 0.0
var _charge_kind: String = ""        # "ground" (A) / "lob" (B)
var _curl_accum: float = 0.0
var _locked: bool = false

var _pending_kind: String = ""
var _pending_ratio: float = 1.0
var _contact_connected := false

var _cn_rng := RandomNumberGenerator.new()
var _spawned: Array = []             # [{body, team_group}]
var _short_mate: CharacterBody3D     # партнёр под короткую опцию (RB)
var _short_called: bool = false
var _short_target: Vector3 = Vector3.ZERO

func setup(manager: Node, ball: RigidBody3D, camera_pivot: Node3D, power_bar: ProgressBar, keeper: CharacterBody3D) -> void:
	_manager = manager
	_ball = ball
	_camera_pivot = camera_pivot
	_power_bar = power_bar
	_keeper = keeper
	_keeper_brain = keeper.brain() if keeper != null and keeper.has_method(&"brain") else null
	_cn_rng.randomize()

func is_active() -> bool:
	return _phase != Phase.IDLE

## Старт углового: сторона по X игрока в момент вызова; ворота вратаря (goal_line_z).
func start(kicker: CharacterBody3D, goal_line_z: float) -> void:
	if _phase != Phase.IDLE or kicker == null:
		return
	_kicker = kicker
	_goal_line_z = goal_line_z
	_into = -signf(goal_line_z)
	_side = CornerLogic.side_for_player(kicker.global_position.x)
	_foot = CornerLogic.foot_for_side(_side)
	_setup()

func _setup() -> void:
	_phase = Phase.SETUP
	_cleanup_spawned()
	_manager.set_corner_active(true)
	_manager.set_field_ai_active(false)
	_spot = CornerLogic.corner_spot(_side, FootballConstants.HALF_FIELD_WIDTH, _goal_line_z,
		FootballConstants.CORNER_INSET, FootballConstants.BALL_RADIUS)
	var goal_center := Vector3(0.0, 0.0, _goal_line_z)
	_base_heading = FreeKickLogic.base_heading(_spot, goal_center)
	_heading = _base_heading
	# Мяч в угол.
	if _ball.has_method(&"release_dribble"):
		_ball.release_dribble()
	if _ball.has_method(&"clear_last_kicker"):
		_ball.clear_last_kicker()
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = _spot
	_place_kicker()
	# Бьющий в чистый idle.
	var kvis := _kicker_visual()
	if kvis != null:
		kvis.cancel_action()
		kvis.recover()
	# Вратарь: якорь у створа (реактивная ловля/дайв уже работают).
	if _keeper_brain != null and _keeper_brain.has_method(&"set_freekick_anchor"):
		_keeper_brain.set_freekick_anchor(Vector3(0.0, 0.5, _goal_line_z + _into * FootballConstants.FK_KEEPER_STEP_OUT))
	_spawn_targets()
	_spawn_defenders()
	_peak_height = FootballConstants.CORNER_LOB_PEAK_STANDARD
	_charging = false
	_charge = 0.0
	_curl_accum = 0.0
	_locked = false
	_short_called = false
	_update_camera_pose()
	_phase = Phase.AIM

## Расстановка бьющего за мячом вдоль -base_heading, латеральный сдвиг под опорную ногу.
func _place_kicker() -> void:
	var side_sign := 1.0 if _foot == "penalty_r" else -1.0
	var right := _base_heading.cross(Vector3.UP).normalized()
	_kicker.global_position = _spot - _base_heading * FootballConstants.CORNER_RUNUP_DIST \
		+ right * (-side_sign * FootballConstants.CORNER_FOOT_LATERAL) \
		+ Vector3(0.0, 0.5 - FootballConstants.BALL_RADIUS, 0.0)
	_kicker.look_at(_kicker.global_position + _base_heading, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
		km.set_move_intent(Vector3.ZERO)
		km.set_face_direction(_base_heading)

func update(delta: float) -> void:
	match _phase:
		Phase.AIM:
			_aim_update(delta)
		Phase.STRIKE:
			_strike_update(delta)
	_update_camera_pose()

func _aim_update(delta: float) -> void:
	var stick_x := Input.get_axis(&"move_left", &"move_right")
	var stick_y := -Input.get_axis(&"move_forward", &"move_back")
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога от выбранного бьющего).
	if Input.is_action_just_pressed(&"foot_left"):
		_set_foot("penalty_l")
	elif Input.is_action_just_pressed(&"foot_right"):
		_set_foot("penalty_r")
	# RB — позвать ближайшего партнёра на короткую опцию.
	if Input.is_action_just_pressed(&"corner_call"):
		_call_short_mate()
	_drive_short_mate(delta)
	if not _locked:
		# Стик-X крутит heading (камера едет). Стик-Y задаёт высоту навеса (до нажатия B).
		if absf(stick_x) > 0.15:
			_heading = FreeKickLogic.rotate_heading(_heading, _base_heading, stick_x,
				FootballConstants.CORNER_AIM_SPEED, delta, FootballConstants.CORNER_AIM_ARC)
		_peak_height = CornerLogic.peak_for_stick_y(stick_y, FootballConstants.CORNER_LOB_PEAK_HEAD,
			FootballConstants.CORNER_LOB_PEAK_STANDARD, FootballConstants.CORNER_LOB_PEAK_SVECHA)
		# A = наземный пас, B = навес.
		if Input.is_action_just_pressed(&"pass_short"):
			_start_charge("ground")
		elif Input.is_action_just_pressed(&"pass_lob"):
			_start_charge("lob")
	if _charging:
		_charge += delta
		if _charge_kind == "lob":
			_curl_accum += stick_x * delta   # закрутка копится только для навеса
		var ratio := clampf(_charge / FootballConstants.CORNER_CHARGE_MAX_TIME, 0.0, 1.0)
		_power_bar.visible = true
		_power_bar.value = ratio
		var fill := _power_bar.get_theme_stylebox("fill")
		if fill:
			fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
		if ratio >= 1.0 or _charge_released():
			_fire_charge(ratio)

func _set_foot(f: String) -> void:
	if f == _foot:
		return
	_foot = f
	_place_kicker()

func _charge_released() -> bool:
	if _charge_kind == "lob":
		return not Input.is_action_pressed(&"pass_lob")
	return not Input.is_action_pressed(&"pass_short")

func _start_charge(kind: String) -> void:
	_charging = true
	_locked = true
	_charge = 0.0
	_curl_accum = 0.0
	_charge_kind = kind

func _fire_charge(ratio: float) -> void:
	_charging = false
	_power_bar.visible = false
	_pending_ratio = ratio
	_begin_strike(_charge_kind)

## Запуск разбега: лочим мотор, играем клип ноги, ждём action_contact.
func _begin_strike(kind: String) -> void:
	_pending_kind = kind
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
	_phase = Phase.STRIKE
	var vis := _kicker_visual()
	if vis != null and not _contact_connected:
		vis.action_contact.connect(_on_kicker_contact, CONNECT_ONE_SHOT)
		_contact_connected = true
	if vis == null or not vis.trigger(_foot):
		_on_kicker_contact("penalty")   # фолбэк без анимации

func _strike_update(delta: float) -> void:
	if _pending_kind == "lob":
		_curl_accum += Input.get_axis(&"move_left", &"move_right") * delta
	var vis := _kicker_visual()
	if vis == null:
		return
	var advance: float = vis.consume_root_motion()
	if advance > 0.0:
		_kicker.global_position += _base_heading * advance

func _on_kicker_contact(_action: String) -> void:
	_contact_connected = false
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var from: Vector3 = _ball.global_position
	var flat := Vector3(_heading.x, 0.0, _heading.z).normalized()
	var receiver: CharacterBody3D = _select_receiver()
	if _pending_kind == "ground":
		# Короткий наземный пас; сила = скорость (заряд).
		var speed := lerpf(FootballConstants.CORNER_PASS_MIN_SPEED, FootballConstants.CORNER_PASS_MAX_SPEED, _pending_ratio)
		var vel := PassSystem.launch_ground(from, from + flat, speed)
		if _ball.has_method(&"launch"):
			_ball.launch(vel, true)
	else:
		# Навес: точка приземления = позиция цели (или heading × дальность заряда, если цели нет).
		var land: Vector3
		if is_instance_valid(receiver):
			land = Vector3(receiver.global_position.x, FootballConstants.BALL_RADIUS, receiver.global_position.z)
		else:
			var land_dist := lerpf(FootballConstants.CORNER_LOB_MIN_DIST, FootballConstants.CORNER_LOB_MAX_DIST, _pending_ratio)
			land = from + flat * land_dist
			land.y = FootballConstants.BALL_RADIUS
		var to_land := Vector3(land.x - from.x, 0.0, land.z - from.z)
		var land_dist2 := to_land.length()
		var land_dir := to_land.normalized() if land_dist2 > 0.001 else flat
		# launch_lob не учитывает драг → берём вертикаль из неё, горизонталь с поправкой на драг.
		var lob := PassSystem.launch_lob(from, land, _peak_height, g)
		var vy: float = lob.y
		var flight_t: float = (2.0 * vy / g) if g > 0.01 else 0.0
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		var hspeed := KeeperLogic.drag_horizontal_speed(land_dist2, flight_t, _ball.drag_factor, dt)
		var vel := land_dir * hspeed + Vector3.UP * vy
		var curl := FreeKickLogic.curl_from_stick(_curl_accum, FootballConstants.CORNER_CURL_SCALE, FootballConstants.CORNER_CURL_MAX)
		if curl.length_squared() > 0.0001 and _ball.has_method(&"launch_curl"):
			_ball.launch_curl(vel, curl, false)
		elif _ball.has_method(&"launch"):
			_ball.launch(vel, false)
	struck.emit()
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(false)
	# Управление получателю ДО _release()/конверта тел (та же причина, что в FK).
	if is_instance_valid(receiver) and _manager.has_method(&"assign_controlled_player"):
		_manager.assign_controlled_player(receiver)
	_release()
	if is_instance_valid(receiver) and _manager.has_method(&"begin_pass_receive"):
		_manager.begin_pass_receive(receiver)

## Тиммейт-получатель: лучший по совпадению направления от мяча с heading (dot, порог).
func _select_receiver() -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_dot := 0.2
	var from: Vector3 = _ball.global_position
	var h := Vector3(_heading.x, 0.0, _heading.z).normalized()
	var candidates: Array = []
	for entry in _spawned:
		if entry["team_group"] == &"team_1":
			candidates.append(entry["body"])
	if is_instance_valid(_short_mate):
		candidates.append(_short_mate)
	for b in candidates:
		if not is_instance_valid(b):
			continue
		var d := Vector3(b.global_position.x - from.x, 0.0, b.global_position.z - from.z)
		if d.length() < 0.1:
			continue
		var dt := d.normalized().dot(h)
		if dt > best_dot:
			best_dot = dt
			best = b
	return best

# ── RB короткая опция ─────────────────────────────────────────────────────────
func _call_short_mate() -> void:
	if _short_called or not is_instance_valid(_short_mate):
		return
	_short_called = true
	_short_target = CornerLogic.short_option_pos(_spot, _side, _into, FootballConstants.CORNER_SHORT_DIST, 0.5)
	var pm := PlayerMotor.find_on(_short_mate)
	if pm != null:
		pm.set_control_locked(false)

func _drive_short_mate(_delta: float) -> void:
	if not _short_called or not is_instance_valid(_short_mate):
		return
	var pm := PlayerMotor.find_on(_short_mate)
	if pm == null:
		return
	var d := _short_target - _short_mate.global_position
	d.y = 0.0
	if d.length() > 0.8:
		pm.set_move_intent(d.normalized(), 1.0)
	else:
		pm.set_move_intent(Vector3.ZERO)

# ── Спавны ─────────────────────────────────────────────────────────────────────
func _spawn_targets() -> void:
	var positions := CornerLogic.box_target_positions(_goal_line_z, _into,
		FootballConstants.CORNER_TARGET_LATERAL, FootballConstants.CORNER_TARGET_DEPTH, 0.5)
	for pos in positions:
		_spawned.append({"body": _make_body(&"team_1", Color(0.1, 0.1, 0.9), pos), "team_group": &"team_1"})
	# Короткая опция — отдельное тело team_1 рядом с углом (стоит, пока не позвали RB).
	var short_pos := _spot - _base_heading * 3.0 + _base_heading.cross(Vector3.UP).normalized() * 4.0
	short_pos.y = 0.5
	_short_mate = _make_body(&"team_1", Color(0.1, 0.1, 0.9), short_pos)
	_spawned.append({"body": _short_mate, "team_group": &"team_1"})

func _spawn_defenders() -> void:
	var into := _into
	for sx in [-1.0, 1.0]:
		var pos := Vector3(sx * FootballConstants.CORNER_TARGET_LATERAL * 0.7, 0.5,
			_goal_line_z + into * (FootballConstants.CORNER_TARGET_DEPTH - 3.0))
		_spawned.append({"body": _make_body(&"team_2", Color(0.9, 0.1, 0.1), pos), "team_group": &"team_2"})

func _make_body(team_group: StringName, color: Color, pos: Vector3) -> CharacterBody3D:
	var cfg := PlayerConfig.new()
	cfg.team_group = team_group
	cfg.role = PlayerConfig.Role.FWD if team_group == &"team_1" else PlayerConfig.Role.DEF
	cfg.kit_color = color
	cfg.spawn_pos = pos
	cfg.display_name = "CornerBody"
	cfg.control_mode = PlayerConfig.ControlMode.AI
	cfg.ai_script = null                 # без ИИ до _convert_bodies
	cfg.connect_action_signals = true
	var team_node: Node3D = _manager._team_home if team_group == &"team_1" else _manager._team_away
	var p := PlayerFactory.spawn(cfg, team_node)
	p.add_to_group("corner_spawned")
	var pm := PlayerMotor.find_on(p)
	if pm != null:
		pm.set_control_locked(true)
		pm.set_move_intent(Vector3.ZERO)
	return p

func _cleanup_spawned() -> void:
	for n in _manager.get_tree().get_nodes_in_group("corner_spawned"):
		if is_instance_valid(n) and n != _kicker:
			n.queue_free()
	_spawned.clear()
	_short_mate = null

func _convert_bodies() -> void:
	var simple := preload("res://scripts/ai/simple_ai.gd")
	var mate := preload("res://scripts/ai/teammate_ai.gd")
	for entry in _spawned:
		var b: CharacterBody3D = entry["body"]
		if not is_instance_valid(b):
			continue
		var pm := PlayerMotor.find_on(b)
		if pm != null:
			pm.set_control_locked(false)
		var brain: Node
		if entry["team_group"] == &"team_2":
			brain = simple.new()
			brain.name = "Brain"
			b.add_child(brain)
			brain.ball = _ball
			brain.home_goal = _manager.get_node_or_null("GoalHome/GoalArea")
		else:
			brain = mate.new()
			brain.name = "Brain"
			b.add_child(brain)
			brain.ball = _ball
			brain.controlled_player = _manager.controlled_player

func _release() -> void:
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_face_direction(Vector3.ZERO)
		km.set_control_locked(false)
	if _keeper_brain != null and _keeper_brain.has_method(&"clear_freekick_anchor"):
		_keeper_brain.clear_freekick_anchor()
	_convert_bodies()
	# Гол с углового: не размораживаем поле-ИИ (заморозку празднования снимет _celebrate_then_reset).
	if _manager.is_celebrating():
		_manager.set_field_ai_active(false)
	else:
		_manager.set_field_ai_active(true)
	_manager.set_corner_active(false)
	_phase = Phase.IDLE

## Фикс-камера от 3-го лица за бьющим (за углом, смотрит по heading). Держится только до контакта —
## на _release() _corner_active сбрасывается и обычная камера возвращается сама.
func _update_camera_pose() -> void:
	if _phase == Phase.IDLE:
		return
	var eye := _spot - _heading * FootballConstants.CORNER_CAM_BACK + Vector3(0.0, FootballConstants.CORNER_CAM_HEIGHT, 0.0)
	var look := _spot + _heading * 4.0 + Vector3(0.0, FootballConstants.CORNER_CAM_LOOK_Y, 0.0)
	var t := Transform3D.IDENTITY
	t.origin = eye
	t = t.looking_at(look, Vector3.UP)
	_manager.set_corner_cam_pose(t)

func _kicker_visual() -> PlayerVisual:
	if _kicker == null:
		return null
	for c in _kicker.get_children():
		if c is PlayerVisual:
			return c
	return null
```

- [ ] **Step 4: Добавить input-действия в `match_manager._setup_inputs()`**

В словаре `actions` (после строки `&"free_kick_debug": ...`) добавить:

```gdscript
		&"corner_debug":    {"keys": [KEY_C],     "buttons": [], "axes": []},
		&"corner_call":     {"keys": [KEY_T],     "buttons": [JOY_BUTTON_RIGHT_SHOULDER], "axes": []},
		&"foot_left":       {"keys": [KEY_L],     "buttons": [], "axes": []},
		&"foot_right":      {"keys": [KEY_R],     "buttons": [], "axes": []},
```

(`corner_call` делит RB с `combo_curl` — оба независимы, `corner_call` читается только в фазе AIM углового, обычный ввод в это время заглушён. `KEY_T` — для теста с клавиатуры.)

- [ ] **Step 5: Добавить поля и методы `_corner*` в `match_manager.gd`**

Рядом с полями `_free_kick*` (около строки 27-30) добавить:

```gdscript
var _corner                                    # CornerController
var _corner_active: bool = false
var _corner_cam_pose: Transform3D = Transform3D.IDENTITY
```

Рядом с `set_free_kick_cam_pose` (около строки 610) добавить методы:

```gdscript
func is_corner_active() -> bool:
	return _corner_active


func set_corner_active(on: bool) -> void:
	_corner_active = on


func set_corner_cam_pose(pose: Transform3D) -> void:
	_corner_cam_pose = pose
```

- [ ] **Step 6: Создать контроллер в `match_manager._ready()`**

После блока создания `_free_kick` (строки 136-139) добавить:

```gdscript
	_corner = preload("res://scripts/match/corner_controller.gd").new()
	_corner.name = "CornerController"
	add_child(_corner)
	_corner.setup(self, ball, camera_pivot, power_bar, _keeper)
```

- [ ] **Step 7: Гейтинг в `match_manager._physics_process()`**

После блока штрафного (строки 883-889, перед `_try_fire_queue`) добавить:

```gdscript
	# Угловой-режим: всё ведёт контроллер, обычные системы заглушены.
	if _corner_active:
		_corner.update(delta)
		return
	# Угловой по C — только из чистого состояния (не во время празднования гола).
	if Input.is_action_just_pressed(&"corner_debug") and _keeper != null and not _celebrating:
		_corner.start(controlled_player, _keeper_brain.goal_line_z)
		return
```

- [ ] **Step 8: Камера в `match_manager._process()`**

В цепочке `if _penalty_active: ... elif _free_kick_active: ...` (строки 814-817) добавить ветку после `_free_kick_active`:

```gdscript
	elif _corner_active:
		camera_pivot.global_transform = _corner_cam_pose
```

И в условии заряда (строка 848) добавить `_corner_active`:

```gdscript
	if not _penalty_active and not _free_kick_active and not _corner_active:
```

- [ ] **Step 9: Проверить парс + загрузку match-сцены**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: без новых категорий ошибок сверх baseline (см. Global Constraints). `Inputs setup OK` печатается.

- [ ] **Step 10: Запустить смоук-тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_corner_flow.gd"`
Expected: `CHECK PASS: corner flow (launched + released)`, exit 0.

- [ ] **Step 11: Коммит**

```bash
git add scripts/match/corner_controller.gd scripts/match/match_manager.gd tests/check_corner_flow.gd
git commit -m "feat(corner): add CornerController + match_manager wiring + flow smoke test"
```

---

## Task 4: Переключение ноги L/R в penalty/free-kick (временное)

**Files:**
- Modify: `scripts/match/penalty_controller.gd`
- Modify: `scripts/match/free_kick_controller.gd`

**Interfaces:**
- Consumes: input-действия `foot_left`/`foot_right` (добавлены в Task 3 Step 4).
- Produces: в фазе AIM обоих контроллеров L/R меняют `_foot` (`penalty_l`↔`penalty_r`) с перестановкой бьющего. (В угловом это уже сделано в Task 3.)

- [ ] **Step 1: Penalty — вынести расстановку бьющего в `_place_kicker()`**

В `penalty_controller.gd`, в `_setup()` заменить блок расстановки (строки ~76-88, от `var side := ...` до `km.set_face_direction(_forward)`) на вызов:

```gdscript
	_place_kicker()
```

И добавить новый метод (рядом с `_setup`):

```gdscript
## Расстановка бьющего за мячом лицом к воротам, латеральный сдвиг под опорную ногу.
func _place_kicker() -> void:
	var side := -_into if _foot == "penalty_r" else _into
	_kicker.global_position = _spot - _forward * FootballConstants.PEN_RUNUP_DIST \
		+ Vector3(side * FootballConstants.PEN_FOOT_LATERAL, 0.5 - FootballConstants.BALL_RADIUS, 0.0)
	_kicker.look_at(_kicker.global_position + _forward, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
		km.set_move_intent(Vector3.ZERO)
		km.set_face_direction(_forward)
```

- [ ] **Step 2: Penalty — обработать L/R в `_aim_update()`**

В `penalty_controller.gd._aim_update()`, в самом начале (перед строкой `var aim_stick := ...`) добавить:

```gdscript
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога определяется выбранным бьющим).
	if Input.is_action_just_pressed(&"foot_left") and _foot != "penalty_l":
		_foot = "penalty_l"
		_place_kicker()
	elif Input.is_action_just_pressed(&"foot_right") and _foot != "penalty_r":
		_foot = "penalty_r"
		_place_kicker()
```

- [ ] **Step 3: Проверить penalty-флоу (регресс)**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_penalty_flow.gd"`
Expected: `CHECK PASS: penalty flow (launched + released)`.

- [ ] **Step 4: Free-kick — вынести расстановку бьющего в `_place_kicker()`**

В `free_kick_controller.gd._setup()` заменить блок расстановки (строки ~87-98, от `var side := ...` до `km.set_face_direction(_base_heading)`) на:

```gdscript
	_place_kicker()
```

И добавить метод:

```gdscript
## Расстановка бьющего за мячом на разбег, лицом по base_heading, сдвиг под опорную ногу.
func _place_kicker() -> void:
	var side := 1.0 if _foot == "penalty_r" else -1.0
	var right := _base_heading.cross(Vector3.UP).normalized()
	_kicker.global_position = _spot - _base_heading * FootballConstants.FK_RUNUP_DIST \
		+ right * (-side * FootballConstants.FK_FOOT_LATERAL) \
		+ Vector3(0.0, 0.5 - FootballConstants.BALL_RADIUS, 0.0)
	_kicker.look_at(_kicker.global_position + _base_heading, Vector3.UP)
	var km := PlayerMotor.find_on(_kicker)
	if km != null:
		km.set_control_locked(true)
		km.set_move_intent(Vector3.ZERO)
		km.set_face_direction(_base_heading)
```

- [ ] **Step 5: Free-kick — обработать L/R в `_aim_update()`**

В `free_kick_controller.gd._aim_update()`, в начале (перед `var stick_x := ...`) добавить:

```gdscript
	# Переключение ноги L/R (ВРЕМЕННО — в будущем нога определяется выбранным бьющим).
	if Input.is_action_just_pressed(&"foot_left") and _foot != "penalty_l":
		_foot = "penalty_l"
		_place_kicker()
	elif Input.is_action_just_pressed(&"foot_right") and _foot != "penalty_r":
		_foot = "penalty_r"
		_place_kicker()
```

- [ ] **Step 6: Проверить free-kick-флоу (регресс) + общую загрузку**

Run:
```
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_free_kick_flow.gd"
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn
```
Expected: `check_free_kick_flow` → `CHECK PASS`; match-сцена без новых категорий ошибок.

- [ ] **Step 7: Коммит**

```bash
git add scripts/match/penalty_controller.gd scripts/match/free_kick_controller.gd
git commit -m "feat(setpiece): temporary L/R foot toggle in penalty/free-kick AIM"
```

---

## Manual verification (человек за игрой — headless не покрывает)

После Task 3-4 запустить игру (`Godot_v4.7-stable_win64.exe` без `--headless`), из матча:
- Нажать **C** у разных углов — угловой стартует с ближней стороны, мяч в углу, камера за бьющим.
- **Стик Y** до нажатия B меняет высоту дуги (голова / стандарт / свеча — все в одну точку).
- **B** (удержание) — навес; **стик X** на разбеге закручивает; проверить инсвинг/аутсвинг.
- **L/R** — бьющий меняет ногу и переставляется на другую сторону от мяча (и в penalty/FK тоже).
- **RB** — партнёр выбегает к углу; развернуть камеру на него и **A** — короткий пас ему; управление уходит получателю.
- На контакте камера сразу возвращается к обычной игровой (1/3).
- Гол с углового — празднование без бега ИИ, затем сброс.

---

## Self-Review (выполнено при написании плана)

- **Покрытие спеки:** автомат (Task 3), ввод A/B/стик-Y/L/R/RB (Task 3), геометрия/нога/высота (Task 1), спавн/очистка/конверт (Task 3), разрешение навес/пас с драг-поправкой и закруткой (Task 3), вратарь-якорь (Task 3 `_setup`), камера-до-контакта (Task 3), интеграция+активация (Task 3), L/R в penalty/FK (Task 4), константы (Task 2), тесты logic+flow+регресс (Task 1/3/4). ✓
- **Плейсхолдеров нет** — весь код приведён целиком.
- **Согласованность типов/имён:** `CornerLogic.*` сигнатуры в Task 1 совпадают с вызовами в Task 3; `set_corner_active/is_corner_active/set_corner_cam_pose` определены (Task 3 Step 5) и вызываются (контроллер + `_process`/`_physics_process`); `_place_kicker` определён до использования в каждом контроллере; `_foot` значения `"penalty_l"/"penalty_r"` едины во всех трёх контроллерах.
- **Скоуп:** одна фича (розыгрыш углового) + минимальная общая правка (L/R) — один план.

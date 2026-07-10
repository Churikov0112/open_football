# Living Locomotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Мигрировать локомоцию всех полевых игроков с прямой манипуляции позицией на модель velocity+inertia (рецепт OpenSoccer), добавив сглаживание разворота, banking, анти-слайд стоп, hold-спринт и взаимные коллизии игроков.

**Architecture:** Новый компонент `PlayerMotor` (child-нода на каждом `CharacterBody3D`) владеет физикой движения: интеграция скорости через `move_and_slide()`, доворот тела, banking, кормит соседний `PlayerVisual`. Внешний код (ввод человека в `match_manager`, ИИ-скрипты) больше не двигает позицию — только передаёт «намерение» через `set_move_intent(dir, speed_scale)`. `PlayerVisual` перестраивается на idle/run/sprint со скоростью клипа, привязанной к реальной.

**Tech Stack:** Godot 4.7 / GDScript. Без сторонних плагинов. Автолоад `FootballConstants`.

## Global Constraints

- **Движок:** Godot 4.7 stable, GDScript. Exe: `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`.
- **Валидация загрузки (headless):** `& "<godot exe>" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit` — должно пройти без ошибок скриптов.
- **Headless-тест:** `& "<godot exe>" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/<name>.gd"` — тест `extends SceneTree`, печатает `CHECK PASS`/`CHECK FAIL`, выходит 0/1.
- **InputMap ТОЛЬКО в `match_manager.gd:_setup_inputs()`** — никогда не править input в `project.godot` (он перезатирается на `_ready()`).
- **Ветка:** `feat/living-locomotion` (уже создана; спек закоммичен).
- **Разделение gameplay/presentation:** физика движения и коллайдер — на `CharacterBody3D`; всё визуальное (наклон модели, скорость клипа) — в `PlayerVisual`. Не смешивать.
- **Тюнинг-числа — стартовые**, финал подбирается живым прогоном; фил/banking/анти-слайд headless не проверяется (только загрузка + чистая математика).
- **Команды через группы** `team_1`/`team_2`, временная `fallen`. Проверять группами, не идентичностью узла.
- Спек: [docs/superpowers/specs/2026-07-09-living-locomotion-design.md](../specs/2026-07-09-living-locomotion-design.md).

---

## File Structure

- **Create** `scripts/player/player_motor.gd` (`class_name PlayerMotor`) — компонент движения: статическая математика + нода-интегратор.
- **Create** `tests/check_player_motor_math.gd` — headless-тест чистой математики motor.
- **Modify** `scripts/data/football_constants.gd` — константы `LOCO_*` + слой коллизий игроков.
- **Modify** `scripts/player/player_visual.gd` — локомоция idle/run/sprint, анти-слайд `TimeScale`, `set_lean`, статик `run_timescale`.
- **Modify** `tests/check_player_visual_locomotion.gd` — добавить проверку `run_timescale`.
- **Modify** `scripts/match/match_manager.gd` — монтаж motor на 3 игроков, ввод человека через motor, действие `sprint`, control-lock на commit-действиях/такле, слой коллизий.
- **Modify** `scripts/ai/simple_ai.gd`, `scripts/ai/teammate_ai.gd` — кормить motor намерением вместо записи позиции.

---

## Task 1: `PlayerMotor` — чистая математика + константы

**Files:**
- Modify: `scripts/data/football_constants.gd` (секция PLAYER)
- Create: `scripts/player/player_motor.gd`
- Test: `tests/check_player_motor_math.gd`

**Interfaces:**
- Consumes: ничего (первая задача).
- Produces (статические, чистые — используются нодой в Task 3 и `PlayerVisual` в Task 2):
  - `PlayerMotor.desired_velocity(dir: Vector3, top_speed: float, speed_scale: float) -> Vector3`
  - `PlayerMotor.integrate_velocity(current: Vector3, desired: Vector3, accel: float, decel: float, delta: float) -> Vector3`
  - `PlayerMotor.smooth_yaw(current_yaw: float, target_yaw: float, turn_rot: float, delta: float) -> float`
  - `PlayerMotor.lean_deg(lateral_norm: float, speed_ramp: float, max_bank_deg: float) -> float`
  - Константы `FootballConstants.LOCO_*` и `PLAYER_COLLISION_MASK`.

- [ ] **Step 1: Добавить константы локомоции**

В `scripts/data/football_constants.gd` в секцию `# PLAYER` (после строки `const PLAYER_START_Z := 0.0`) добавить:

```gdscript
# --- Living locomotion (velocity+inertia, рецепт OpenSoccer; тюнинг-старт) ---
const LOCO_TOP_SPEED := 8.0          # обычная максимальная скорость, м/с
const LOCO_SPRINT_SPEED := 12.0      # максимальная при спринте (≈1.5×)
const LOCO_ACCEL := 25.0             # разгон, м/с² (≈0.32 с до полной)
const LOCO_DECEL := 20.0             # торможение, м/с² (мягче разгона → глайд)
const LOCO_TURN_ROT := 18.0          # темп доворота тела, 1/с
const LOCO_TURN_MIN_SPEED := 1.0     # ниже этой скорости не доворачиваемся
const LOCO_MAX_BANK_DEG := 20.0      # макс. крен корпуса в повороте, градусы
const LOCO_RUN_SCALE_FUDGE := 1.33   # анти-слайд: scale = (speed/top)*fudge
const LOCO_RUN_ANIM_SPEED := 1.5     # порог входа в стейт run, м/с
const LOCO_SPRINT_ANIM_SPEED := 9.0  # порог входа в стейт sprint, м/с
const PLAYER_COLLISION_MASK := 2     # слой полевых игроков (bit2): бьются только друг о друга
```

- [ ] **Step 2: Написать падающий тест математики**

Создать `tests/check_player_motor_math.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var ok := true

	# desired_velocity: нормализует и масштабирует
	var dv := PlayerMotor.desired_velocity(Vector3(1, 0, 0), 8.0, 1.5)
	if not dv.is_equal_approx(Vector3(12, 0, 0)):
		print("CHECK FAIL: desired_velocity sprint → ", dv); ok = false
	if not PlayerMotor.desired_velocity(Vector3.ZERO, 8.0, 1.0).is_equal_approx(Vector3.ZERO):
		print("CHECK FAIL: desired_velocity zero"); ok = false

	# integrate_velocity: разгон из покоя темпом accel
	var acc := PlayerMotor.integrate_velocity(Vector3.ZERO, Vector3(8, 0, 0), 25.0, 20.0, 0.1)
	if not is_equal_approx(acc.length(), 2.5):
		print("CHECK FAIL: accel step → ", acc.length()); ok = false
	# торможение к нулю темпом decel
	var dec := PlayerMotor.integrate_velocity(Vector3(8, 0, 0), Vector3.ZERO, 25.0, 20.0, 0.1)
	if not is_equal_approx(dec.length(), 6.0):
		print("CHECK FAIL: decel step → ", dec.length()); ok = false

	# smooth_yaw: при turn_rot*delta ≥ 1 доходит до цели
	if not is_equal_approx(PlayerMotor.smooth_yaw(0.0, PI, 18.0, 0.1), PI):
		print("CHECK FAIL: smooth_yaw full"); ok = false

	# lean_deg: линейно, клампится
	if not is_equal_approx(PlayerMotor.lean_deg(1.0, 1.0, 20.0), 20.0):
		print("CHECK FAIL: lean_deg max"); ok = false
	if not is_equal_approx(PlayerMotor.lean_deg(0.5, 0.5, 20.0), 5.0):
		print("CHECK FAIL: lean_deg mid"); ok = false
	if not is_equal_approx(PlayerMotor.lean_deg(2.0, 3.0, 20.0), 20.0):
		print("CHECK FAIL: lean_deg clamp"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Step 3: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_motor_math.gd"`
Expected: FAIL — `PlayerMotor` ещё не существует (ошибка «Identifier PlayerMotor not declared» / parse error), exit ≠ 0.

- [ ] **Step 4: Написать `PlayerMotor` со статической математикой**

Создать `scripts/player/player_motor.gd`:

```gdscript
class_name PlayerMotor
extends Node

## Желаемая скорость из намерения. Плоский dir нормализуется; пустой → ноль.
static func desired_velocity(dir: Vector3, top_speed: float, speed_scale: float) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.1:
		return Vector3.ZERO
	return flat.normalized() * top_speed * speed_scale

## Интеграция скорости: разгон темпом accel, торможение (desired≈0) темпом decel.
static func integrate_velocity(current: Vector3, desired: Vector3, accel: float, decel: float, delta: float) -> Vector3:
	var rate := accel if desired.length() > 0.1 else decel
	var v := current.move_toward(desired, rate * delta)
	v.y = 0.0
	return v

## Сглаженный доворот угла (рыскание) к цели.
static func smooth_yaw(current_yaw: float, target_yaw: float, turn_rot: float, delta: float) -> float:
	return lerp_angle(current_yaw, target_yaw, clampf(turn_rot * delta, 0.0, 1.0))

## Крен корпуса (градусы) от нормированного бокового ускорения и разгона по скорости.
static func lean_deg(lateral_norm: float, speed_ramp: float, max_bank_deg: float) -> float:
	return clampf(lateral_norm, -1.0, 1.0) * max_bank_deg * clampf(speed_ramp, 0.0, 1.0)
```

- [ ] **Step 5: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_motor_math.gd"`
Expected: печатает `CHECK PASS`, exit 0.

- [ ] **Step 6: Коммит**

```bash
git add scripts/data/football_constants.gd scripts/player/player_motor.gd tests/check_player_motor_math.gd
git commit -m "feat(loco): PlayerMotor static math + locomotion constants"
```

---

## Task 2: `PlayerVisual` — idle/run/sprint, анти-слайд, `set_lean`

**Files:**
- Modify: `scripts/player/player_visual.gd`
- Test: `tests/check_player_visual_locomotion.gd`

**Interfaces:**
- Consumes: `FootballConstants.LOCO_TOP_SPEED`, `LOCO_SPRINT_SPEED`, `LOCO_RUN_SCALE_FUDGE`, `LOCO_RUN_ANIM_SPEED`, `LOCO_SPRINT_ANIM_SPEED` (Task 1).
- Produces (используются нодой motor в Task 3):
  - `PlayerVisual.run_timescale(speed: float, top_speed: float, fudge: float) -> float` (static)
  - `func set_lean(deg: float) -> void`
  - `func set_locomotion(velocity: Vector3) -> void` (уже существует — motor будет звать каждый кадр)

- [ ] **Step 1: Написать падающий тест `run_timescale`**

В `tests/check_player_visual_locomotion.gd` перед строкой `print("CHECK PASS" if ok else "CHECK FAIL")` вставить:

```gdscript
	# анти-слайд: scale = (speed/top)*fudge, с нижним клампом 0.1
	if not is_equal_approx(PlayerVisual.run_timescale(8.0, 8.0, 1.33), 1.33):
		print("CHECK FAIL: run_timescale full → ", PlayerVisual.run_timescale(8.0, 8.0, 1.33)); ok = false
	if not is_equal_approx(PlayerVisual.run_timescale(4.0, 8.0, 1.33), 0.665):
		print("CHECK FAIL: run_timescale half → ", PlayerVisual.run_timescale(4.0, 8.0, 1.33)); ok = false
	if not is_equal_approx(PlayerVisual.run_timescale(0.0, 8.0, 1.33), 0.1):
		print("CHECK FAIL: run_timescale clamp → ", PlayerVisual.run_timescale(0.0, 8.0, 1.33)); ok = false
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_locomotion.gd"`
Expected: FAIL — `run_timescale` ещё нет (parse error / method not found).

- [ ] **Step 3: Добавить статик `run_timescale` и `set_lean`, расширить `LOOP_CLIPS`, добавить константы стейтов**

В `scripts/player/player_visual.gd`:

3a. Заменить строку `const LOCOMOTION := &"locomotion"` на:

```gdscript
## Имена стейтов локомоции в StateMachine (LOCOMOTION = idle-хаб, из него travel в остальные).
const LOCOMOTION := &"loco_idle"
const LOCO_RUN := &"loco_run"
const LOCO_SPRINT := &"loco_sprint"
```

3b. Заменить `const LOOP_CLIPS := [&"idle", &"run", &"fallen_idle"]` на:

```gdscript
const LOOP_CLIPS := [&"idle", &"run", &"sprint", &"fallen_idle"]
```

3c. Сразу после статика `speed_to_blend` (перед `func _ready`) добавить:

```gdscript
## Анти-слайд: множитель скорости клипа бега/спринта = (speed/top)*fudge (клампится снизу).
static func run_timescale(speed: float, top_speed: float, fudge: float) -> float:
	if top_speed <= 0.0:
		return 1.0
	return maxf(0.1, (speed / top_speed) * fudge)

## Наклон корпуса (banking): крен узла Model по локальной оси Z. deg тюнится по знаку живьём.
func set_lean(deg: float) -> void:
	if _model == null:
		return
	_model.rotation.z = deg_to_rad(deg)
```

- [ ] **Step 4: Перестроить `_build_anim_tree` на idle/run/sprint со скоростью клипа**

Заменить в `_build_anim_tree` блок построения локомоции и StateMachine (от комментария `# glTF-анимации...` до строки `sm.add_node(LOCOMOTION, loco, Vector2(400, 100))` включительно, а также цикл добавления action-стейтов оставить как есть) — то есть заменить участок, создающий `idle_node/run_node/loco` и `sm.add_node(LOCOMOTION, loco, ...)`, на:

```gdscript
	# glTF-анимации приходят незациклёнными (loop_mode=NONE). Локомоцию/лежание зацикливаем;
	# one-shot (удары/падение/вставание) оставляем незациклёнными — иначе не сработает
	# авто-возврат по AT_END.
	for anim_name in LOOP_CLIPS:
		if ap.has_animation(anim_name):
			ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

	# StateMachine: idle-хаб + run/sprint (скорость клипа привязана к реальной) + one-shot действия.
	var sm := AnimationNodeStateMachine.new()
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"idle"
	sm.add_node(LOCOMOTION, idle_node, Vector2(400, 60))
	sm.add_node(LOCO_RUN, _make_speed_state(&"run"), Vector2(400, 140))
	var sprint_clip: StringName = &"sprint" if ap.has_animation(&"sprint") else &"run"
	sm.add_node(LOCO_SPRINT, _make_speed_state(sprint_clip), Vector2(400, 220))
	# звёздчатые переходы: idle ↔ run, idle ↔ sprint (хаб = idle, travel строит путь через него)
	for st in [LOCO_RUN, LOCO_SPRINT]:
		sm.add_transition(LOCOMOTION, st, _make_transition(false))
		sm.add_transition(st, LOCOMOTION, _make_transition(false))
```

Существующий далее цикл `for action in ACTION_CLIPS:` и обёртка в `AnimationNodeBlendTree` с `TimeScale` — **оставить без изменений** (он уже добавляет action-стейты и стартует `_playback.start(LOCOMOTION)`).

Затем добавить новый приватный хелпер (например, сразу после `_build_anim_tree`):

```gdscript
## Стейт локомоции со скоростью клипа: Animation("clip") → TimeScale("speed") → output.
func _make_speed_state(clip: StringName) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var anim := AnimationNodeAnimation.new()
	anim.animation = clip
	bt.add_node(&"clip", anim, Vector2(100, 100))
	var ts := AnimationNodeTimeScale.new()
	bt.add_node(&"speed", ts, Vector2(300, 100))
	bt.connect_node(&"speed", 0, &"clip")
	bt.connect_node(&"output", 0, &"speed")
	return bt
```

- [ ] **Step 5: Переписать выбор стейта локомоции и анти-слайд в `_process`**

В `_process` заменить блок, начинающийся с `var target := speed_to_blend(speed)` и заканчивающийся `_anim_tree.set(&"parameters/sm/locomotion/blend_position", _blend)` на:

```gdscript
	# Выбор стейта локомоции по порогам скорости (пока не идёт action).
	if _active_action == "" and _playback != null:
		var want := LOCOMOTION
		if speed >= FootballConstants.LOCO_SPRINT_ANIM_SPEED:
			want = LOCO_SPRINT
		elif speed >= FootballConstants.LOCO_RUN_ANIM_SPEED:
			want = LOCO_RUN
		if _playback.get_current_node() != want:
			_playback.travel(want)
	# Анти-слайд: скорость клипов run/sprint по реальной скорости.
	_anim_tree.set("parameters/sm/%s/speed/scale" % LOCO_RUN,
		PlayerVisual.run_timescale(speed, FootballConstants.LOCO_TOP_SPEED, FootballConstants.LOCO_RUN_SCALE_FUDGE))
	_anim_tree.set("parameters/sm/%s/speed/scale" % LOCO_SPRINT,
		PlayerVisual.run_timescale(speed, FootballConstants.LOCO_SPRINT_SPEED, FootballConstants.LOCO_RUN_SCALE_FUDGE))
```

(Поле `_blend` и константы `RUN_SPEED_FULL`/`BLEND_SMOOTH` больше не используются в `_process`, но **оставить их объявления** — `speed_to_blend` и его тест на них опираются.)

- [ ] **Step 6: Запустить тест локомоции — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_locomotion.gd"`
Expected: `CHECK PASS`, exit 0.

- [ ] **Step 7: Проверить загрузку проекта headless**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без ошибок скриптов (проект грузится, matches закрывается).

- [ ] **Step 8: Коммит**

```bash
git add scripts/player/player_visual.gd tests/check_player_visual_locomotion.gd
git commit -m "feat(loco): PlayerVisual idle/run/sprint states + speed-synced anti-slide + set_lean"
```

---

## Task 3: `PlayerMotor` — нода-интегратор (движение + разворот + banking)

**Files:**
- Modify: `scripts/player/player_motor.gd`

**Interfaces:**
- Consumes: статики `PlayerMotor.*` (Task 1); `PlayerVisual.set_locomotion`, `PlayerVisual.set_lean` (Task 2); `FootballConstants.LOCO_*` (Task 1).
- Produces (инстанс-API, зовётся `match_manager` (Task 4) и ИИ (Task 5)):
  - `func set_move_intent(dir: Vector3, speed_scale: float = 1.0) -> void`
  - `func set_control_locked(on: bool) -> void`

- [ ] **Step 1: Добавить инстанс-поля и `_ready`**

В `scripts/player/player_motor.gd` после блока статических функций добавить:

```gdscript
var _intent_dir: Vector3 = Vector3.ZERO
var _intent_scale: float = 1.0
var _locked: bool = false
var _ground_y: float = 0.5
var _body: CharacterBody3D
var _visual: PlayerVisual

func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_warning("PlayerMotor: родитель не CharacterBody3D — motor выключен")
		set_physics_process(false)
		return
	_ground_y = _body.global_position.y
	for c in _body.get_children():
		if c is PlayerVisual:
			_visual = c
			break

## Передать намерение движения (мировой dir, нормализуется внутри). Зовётся каждый кадр.
func set_move_intent(dir: Vector3, speed_scale: float = 1.0) -> void:
	_intent_dir = dir
	_intent_scale = speed_scale

## Заблокировать управление (commit-действие / такл): скорость гаснет до 0, ввод игнорится.
func set_control_locked(on: bool) -> void:
	_locked = on
```

- [ ] **Step 2: Реализовать `_physics_process` (интеграция, разворот, banking, кормёжка визуала)**

Добавить в `scripts/player/player_motor.gd`:

```gdscript
func _physics_process(delta: float) -> void:
	if _body == null or delta <= 0.0:
		return

	# Намерение: ноль, если заблокированы или сбиты (fallen).
	var desired := Vector3.ZERO
	if not _locked and not _body.is_in_group("fallen"):
		desired = PlayerMotor.desired_velocity(_intent_dir, FootballConstants.LOCO_TOP_SPEED, _intent_scale)

	var prev := _body.velocity
	var new_vel := PlayerMotor.integrate_velocity(prev, desired, FootballConstants.LOCO_ACCEL, FootballConstants.LOCO_DECEL, delta)
	var speed := new_vel.length()

	# Доворот тела к направлению движения (тело остаётся вертикальным).
	if speed > FootballConstants.LOCO_TURN_MIN_SPEED:
		var target_yaw := atan2(-new_vel.x, -new_vel.z)
		_body.rotation.y = PlayerMotor.smooth_yaw(_body.rotation.y, target_yaw, FootballConstants.LOCO_TURN_ROT, delta)

	# Banking: боковая компонента ускорения относительно направления взгляда.
	var accel_vec := (new_vel - prev) / delta
	var right := _body.global_transform.basis.x
	var lateral := right.dot(accel_vec) / FootballConstants.LOCO_ACCEL
	var ramp := speed / (0.5 * FootballConstants.LOCO_TOP_SPEED)

	_body.velocity = new_vel
	_body.move_and_slide()
	_body.global_position.y = _ground_y  # поле плоское — пиннинг высоты

	if _visual != null:
		_visual.set_locomotion(new_vel)
		_visual.set_lean(PlayerMotor.lean_deg(lateral, ramp, FootballConstants.LOCO_MAX_BANK_DEG))
```

- [ ] **Step 3: Проверить загрузку проекта headless**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без ошибок скриптов. (Нода ещё нигде не смонтирована — проверяем только компиляцию.)

- [ ] **Step 4: Коммит**

```bash
git add scripts/player/player_motor.gd
git commit -m "feat(loco): PlayerMotor node — velocity integration, turn smoothing, banking"
```

---

## Task 4: Монтаж motor + ввод человека + спринт + control-lock (`match_manager`)

**Files:**
- Modify: `scripts/match/match_manager.gd`

**Interfaces:**
- Consumes: `PlayerMotor` (Task 3), `FootballConstants.LOCO_*` (Task 1).
- Produces: у каждого полевого `CharacterBody3D` есть дочерняя нода `PlayerMotor`; хелпер `func _player_motor(player_node: Node) -> PlayerMotor`.

- [ ] **Step 1: Добавить действие `sprint` в `_setup_inputs`**

В `scripts/match/match_manager.gd`, в словарь `input_actions` (внутри `_setup_inputs`) добавить строку после `&"swap_player": [KEY_Q],`:

```gdscript
		&"sprint": [KEY_SHIFT],
```

- [ ] **Step 2: Смонтировать `PlayerMotor` на всех троих игроков**

2a. В `_ready`, сразу после `player_home.add_child(home_visual)` (перед `home_visual.apply_appearance(...)`) добавить:

```gdscript
	player_home.add_child(PlayerMotor.new())
```

2b. В `_setup_away_player`, после `new_player.add_child(visual)` добавить:

```gdscript
	new_player.add_child(PlayerMotor.new())
```

2c. В `_setup_teammate`, после `new_player.add_child(visual)` добавить:

```gdscript
	new_player.add_child(PlayerMotor.new())
```

- [ ] **Step 3: Добавить хелпер `_player_motor`**

Сразу после функции `_player_visual` (после её `return null`) добавить:

```gdscript
## Найти дочерний PlayerMotor у игрового узла (добавляется ребёнком при спавне).
func _player_motor(player_node: Node) -> PlayerMotor:
	if player_node == null:
		return null
	for c in player_node.get_children():
		if c is PlayerMotor:
			return c
	return null
```

- [ ] **Step 4: Перевести ввод человека на motor (убрать move_toward по позиции)**

В `_handle_player_input` заменить блок:

```gdscript
		if dir.length() > 0.1:
			var speed := 8.0
			controlled_player.global_position.x = move_toward(controlled_player.global_position.x,
				controlled_player.global_position.x + dir.x * speed * delta, speed * delta)
			controlled_player.global_position.z = move_toward(controlled_player.global_position.z,
				controlled_player.global_position.z + dir.z * speed * delta, speed * delta)
			var target_angle := atan2(-dir.x, -dir.z)
			controlled_player.rotation.y = lerp_angle(controlled_player.rotation.y, target_angle, 10.0 * delta)
```

на:

```gdscript
		var sprint_scale := 1.0
		if Input.is_action_pressed(&"sprint"):
			sprint_scale = FootballConstants.LOCO_SPRINT_SPEED / FootballConstants.LOCO_TOP_SPEED
		var motor := _player_motor(controlled_player)
		if motor != null:
			motor.set_move_intent(dir, sprint_scale)  # dir == ZERO при отсутствии ввода → торможение
```

(`dir` вычисляется выше по функции и уже равен `Vector3.ZERO` при отсутствии ввода — намерение передаём безусловно, чтобы работало торможение.)

- [ ] **Step 5: Wire control-lock на commit-действиях**

5a. В `_start_ball_action`, внутри `if visual != null and visual.trigger(action):` после `_action_player = player_node` добавить:

```gdscript
		var lock_motor := _player_motor(player_node)
		if lock_motor != null:
			lock_motor.set_control_locked(true)
```

5b. В `_on_action_finished`, внутри `if player == _action_player:` (перед/после `_action_player = null`) добавить снятие блокировки:

```gdscript
		var motor := _player_motor(player)
		if motor != null:
			motor.set_control_locked(false)
```

5c. В `_cancel_ball_action`, после `_action_player = null` добавить:

```gdscript
	var motor := _player_motor(player)
	if motor != null:
		motor.set_control_locked(false)
```

- [ ] **Step 6: Wire control-lock на слайд-такле (motor уступает физике такла)**

6a. В `_start_tackle`, в самом начале тела функции (после сигнатуры) добавить:

```gdscript
	var tackler_motor := _player_motor(player)
	if tackler_motor != null:
		tackler_motor.set_control_locked(true)
```

6b. В `_tackle_enter_recovery` — найти, где такл завершается и игрок возвращается в норму. В конце `_tackle_recover` (там, где `_tackle_state` возвращается в `TackleState.NORMAL`) снять блокировку у `_tackle_player`:

```gdscript
	var motor := _player_motor(_tackle_player)
	if motor != null:
		motor.set_control_locked(false)
```

(Если в `_tackle_recover` несколько точек выхода — снять блокировку там, где `_tackle_state = TackleState.NORMAL`. Прочитать функцию перед правкой: `scripts/match/match_manager.gd:810`.)

- [ ] **Step 7: Проверить загрузку проекта headless**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без ошибок скриптов.

- [ ] **Step 8: Ручная проверка (человек)**

Запустить игру (тот же exe без `--headless --quit`), из `main_menu` → Start. Проверить:
- Управляемый игрок **плавно разгоняется и тормозит** (не мгновенно), при отпускании клавиш — короткий глайд.
- Тело **плавно доворачивает** к направлению, не снапает.
- **Shift** ускоряет до спринта, отпускание возвращает к обычной.
- Пас/удар (E/Space) блокируют движение на время клипа, затем управление возвращается.
- Подкат по-прежнему работает.

Отметить в заметках, что число `sprint`/`accel`/`decel`/`turn` подбирается тут живьём.

- [ ] **Step 9: Коммит**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(loco): drive human input via PlayerMotor, add hold-sprint, control-lock on actions/tackle"
```

---

## Task 5: Миграция ИИ на motor (simple_ai, teammate_ai)

**Files:**
- Modify: `scripts/ai/simple_ai.gd`
- Modify: `scripts/ai/teammate_ai.gd`

**Interfaces:**
- Consumes: `PlayerMotor.set_move_intent` (Task 3, нода уже смонтирована в Task 4), `FootballConstants.LOCO_TOP_SPEED` (Task 1).
- Produces: ИИ больше не пишут `global_position`/`rotation` — только намерение в motor.

- [ ] **Step 1: `simple_ai` — хелпер motor + перевод `_move_or_wander`/`_wander`**

В `scripts/ai/simple_ai.gd`:

1a. После объявлений переменных (после `var tackle_cooldown: float = 0.0`) добавить:

```gdscript
func _motor() -> PlayerMotor:
	for c in get_children():
		if c is PlayerMotor:
			return c
	return null

## Скорость этого ИИ относительно общей максимальной — сохраняет прежний относительный темп.
func _base_scale() -> float:
	return speed / FootballConstants.LOCO_TOP_SPEED
```

1b. Заменить `_move_or_wander` целиком на:

```gdscript
func _move_or_wander(dir: Vector3, delta: float, speed_multiplier: float = 1.0) -> void:
	if dir.length() > 0.1:
		var m := _motor()
		if m != null:
			m.set_move_intent(dir, _base_scale() * speed_multiplier)
	else:
		_wander(delta, speed_multiplier)
```

1c. Заменить `_wander` целиком на:

```gdscript
func _wander(delta: float, speed_multiplier: float = 1.0) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(0.5, 1.5)
	# Gentle sinusoidal movement for a natural idling look
	var wander_x := sin(Time.get_ticks_msec() * 0.001 + global_position.z) * 0.5
	var wander_z := cos(Time.get_ticks_msec() * 0.001 + global_position.x) * 0.5
	var wander_dir := Vector3(wander_x, 0, wander_z).normalized()
	var m := _motor()
	if m != null:
		m.set_move_intent(wander_dir, _base_scale() * 0.3 * speed_multiplier)
```

- [ ] **Step 2: `teammate_ai` — хелпер motor + перевод `_move_or_wander`/`_wander`**

В `scripts/ai/teammate_ai.gd`:

2a. После `var _wander_timer: float = 0.0` добавить:

```gdscript
func _motor() -> PlayerMotor:
	for c in get_children():
		if c is PlayerMotor:
			return c
	return null

func _base_scale() -> float:
	return speed / FootballConstants.LOCO_TOP_SPEED
```

2b. Заменить `_move_or_wander` целиком на:

```gdscript
func _move_or_wander(dir: Vector3, delta: float) -> void:
	if dir.length() > 0.1:
		var m := _motor()
		if m != null:
			m.set_move_intent(dir, _base_scale())
	else:
		_wander(delta)
```

2c. Заменить `_wander` целиком на:

```gdscript
func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(0.5, 1.5)
	# Gentle sinusoidal movement for a natural idling look
	var wander_x := sin(Time.get_ticks_msec() * 0.001 + global_position.z) * 0.5
	var wander_z := cos(Time.get_ticks_msec() * 0.001 + global_position.x) * 0.5
	var wander_dir := Vector3(wander_x, 0, wander_z).normalized()
	var m := _motor()
	if m != null:
		m.set_move_intent(wander_dir, _base_scale() * 0.3)
```

- [ ] **Step 3: Проверить загрузку проекта headless**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без ошибок скриптов.

- [ ] **Step 4: Ручная проверка (ИИ)**

Запустить игру. Проверить:
- Соперник (team_2, красный) и тиммейт (team_1, синий) двигаются **плавно** (разгон/торможение/доворот), не снапают и не телепортируются.
- ИИ чуть медленнее управляемого игрока (сохранён относительный темп), дриблинг/пас/удар ИИ работают.
- Сбитый подкатом игрок (`fallen`) не «уезжает» под старым намерением.

- [ ] **Step 5: Коммит**

```bash
git add scripts/ai/simple_ai.gd scripts/ai/teammate_ai.gd
git commit -m "feat(loco): drive simple_ai and teammate_ai movement via PlayerMotor intent"
```

---

## Task 6: Взаимные коллизии игроков

**Files:**
- Modify: `scripts/match/match_manager.gd`

**Interfaces:**
- Consumes: `FootballConstants.PLAYER_COLLISION_MASK` (Task 1).
- Produces: полевые игроки на общем слое коллизий, бьются друг о друга через `move_and_slide` (Task 3).

- [ ] **Step 1: Задать слой/маску коллизий игрокам**

Цель: игроки сталкиваются **только друг с другом** (не с мячом — чтобы не толкать его физически, дриблинг ведёт `ball_controller`). Слой `2` (значение `PLAYER_COLLISION_MASK`), маска = тот же слой.

1a. В `_ready`, после `player_home.add_to_group("team_1")` добавить:

```gdscript
	player_home.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	player_home.collision_mask = FootballConstants.PLAYER_COLLISION_MASK
```

1b. В `_setup_away_player`, после `new_player.add_to_group("team_2")` добавить:

```gdscript
	new_player.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	new_player.collision_mask = FootballConstants.PLAYER_COLLISION_MASK
```

1c. В `_setup_teammate`, после `new_player.add_to_group("team_1")` добавить:

```gdscript
	new_player.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	new_player.collision_mask = FootballConstants.PLAYER_COLLISION_MASK
```

- [ ] **Step 2: Проверить загрузку проекта headless**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без ошибок скриптов.

- [ ] **Step 3: Ручная проверка + фолбэк**

Запустить игру. Проверить:
- Двое игроков **не проходят сквозь друг друга** — упираются и обтекают (без залипания/дрожания).
- Мяч **не расталкивается** телом игрока при беге рядом; дриблинг/пас/удар не сломаны.
- Толкотня у мяча не ломает такл/дриблинг.

**Фолбэк (если толкотня ломает геймплей):** временно снять взаимные коллизии — задать `collision_mask = 0` всем троим (слой оставить), тогда `move_and_slide` не расталкивает игроков. Записать решение в заметки; финальный баланс — живой приёмкой.

- [ ] **Step 4: Коммит**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(loco): field players collide via shared collision layer"
```

---

## Self-Review

**1. Покрытие спека:**
- Компонент `PlayerMotor` (архитектура) → Task 1 (математика) + Task 3 (нода). ✅
- Модель velocity+inertia + константы → Task 1 + Task 3. ✅
- Разворот + banking → Task 3 (`smooth_yaw`, `lean_deg`, кормёжка `set_lean`) + Task 2 (`set_lean`). ✅
- Анти-слайд idle/run/sprint → Task 2. ✅
- Спринт (hold Shift, без стамины, фолбэк на run) → Task 2 (стейт+фолбэк) + Task 4 (ввод). ✅
- Взаимодействия: дриблинг читает реальную velocity (motor задаёт `_body.velocity` → `ball_controller` видит её; коллизии с мячом исключены в Task 6) ✅; commit-lock → Task 4 Step 5 ✅; такл уступает → Task 4 Step 6 ✅; камера не тронута ✅.
- Коллизии игроков (по образцу OpenSoccer + фолбэк) → Task 6. ✅
- Миграция ИИ (человек + оба ИИ — «полная миграция») → Task 4 + Task 5. ✅
- Тесты headless → Task 1, Task 2; загрузка проекта после каждой задачи. ✅
- Вне рамок (foot IK, ragdoll, motion matching, стамина, walk-клип, спринт ИИ) — не включено. ✅

**2. Плейсхолдеры:** нет TBD/TODO; весь код приведён целиком.

**3. Согласованность типов/имён:** `set_move_intent(dir, speed_scale)`, `set_control_locked(on)`, `run_timescale(speed, top, fudge)`, `lean_deg`, `smooth_yaw`, `desired_velocity`, `integrate_velocity`, `_player_motor`, `PLAYER_COLLISION_MASK`, стейты `loco_idle/loco_run/loco_sprint`, пути `parameters/sm/loco_run/speed/scale` — совпадают между задачами. ✅

**Заметка про AnimationTree (риск):** пути параметров `parameters/sm/<state>/speed/scale` предполагают, что StateMachine-нода в BlendTree называется `sm`, а стейт содержит TimeScale-ноду `speed` (зеркало OpenSoccer `parameters/StateMachine/sprint/RunSpeed/scale`). Если Godot 4.7 сериализует путь иначе — свериться в редакторе (Inspector у AnimationTree) и поправить строки в `_process` Task 2 Step 5. Это единственное место, требующее возможной живой сверки.

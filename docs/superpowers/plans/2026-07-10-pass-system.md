# Pass System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build five arcade pass types (short ground, through ground, lob, through-air, give-and-go) with a charge bar, auto-aim target selection, a hybrid success model (deterministic corridor interception + accuracy scatter), receive-assist control handoff, gamepad support, and a keyboard remap.

**Architecture:** Heavy pass math lives in pure static functions (`PassSystem`, headless-testable like `PlayerMotor`). `match_manager.gd` orchestrates: input, a generalized charge state machine, commit-action firing, control handoff, corridor detection, and the telegraph indicator. `teammate_ai.gd` gains an explicit `Role` enum for receiving and the give-and-go run. Ball ballistics use a new `ball.launch(velocity)`.

**Tech Stack:** Godot 4.7, GDScript (static typing mandatory). No external libraries. Headless check scripts (`extends SceneTree`) as the only automated test harness.

## Global Constraints

- Engine: Godot 4.7 stable. Validate headless with:
  `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
- Run a check script with:
  `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/<name>.gd"`
- All variables, parameters, and return values MUST be statically typed.
- Input is built in code in `match_manager._setup_inputs()`. NEVER edit `project.godot` input — it is dead (overridden every `_ready()`).
- Constants live in `scripts/data/football_constants.gd` (autoload `FootballConstants`) with a `PASS_*` prefix. Pure `PassSystem` static functions receive tuning as parameters — they NEVER read `FootballConstants` (keeps `check_pass_system_math.gd` autoload-free).
- Team membership is by groups `team_1` (ours, blue) / `team_2` (opponent, red). Use group checks, not node identity.
- Field: Z = length (±52.5), X = width (±34). Our team attacks toward **−Z**. Goals only on Z.
- Player movement is `PlayerMotor.set_move_intent(dir, speed_scale)` — never touch `global_position`/`rotation` for locomotion. AI does not sprint (give-and-go is the one deliberate exception, Task 17).
- Commit git after every task. Branch: `feat/pass`.
- Spec: [`docs/superpowers/specs/2026-07-10-pass-system-design.md`](../specs/2026-07-10-pass-system-design.md).

**Plan-level simplification vs. spec:** the spec mentions an aggregate `PassSolution` + `resolve_pass()`. This plan omits them — with one opponent the aggregation is trivial, so `match_manager` composes the `PassSystem` helpers directly (fewer transient types, YAGNI). `PassParams` is kept as a plain data holder (built by `match_manager`, not a constant-reading factory) to avoid autoload access from a `RefCounted`.

---

### Task 1: Pass tuning constants

**Files:**
- Modify: `scripts/data/football_constants.gd` (append a new section before the CAMERA section)

**Interfaces:**
- Produces: `FootballConstants.PASS_*` and `FootballConstants.AI_INTERCEPT_*` constants used by every later task.

- [ ] **Step 1: Add the constants block**

Append this section to `scripts/data/football_constants.gd` (after the `TACKLE FALL / GRAVITY` section, before `CAMERA`):

```gdscript
# ═══════════════════════════════════════════
#  PASSING (тюнинг-старт)
# ═══════════════════════════════════════════

# Базовая скорость мяча (м/с) по типам паса. launch_ground/launch_lob получают её параметром.
const PASS_SHORT_POWER := 10.0        # короткий пас низом, в ноги
const PASS_THROUGH_POWER := 13.0      # пас на ход низом
const PASS_LOB_PEAK_HEIGHT := 3.0     # высота дуги навеса, м
const PASS_THROUGH_AIR_PEAK_HEIGHT := 2.5  # высота дуги верхового паса на ход

# Заряд множит базовую силу/высоту в диапазоне [MIN..MAX] по доле заряда.
const PASS_CHARGE_MAX_TIME := 0.6
const PASS_POWER_CHARGE_MIN := 0.7    # доля силы при мгновенном отпускании
const PASS_POWER_CHARGE_MAX := 1.6    # доля силы при полном заряде

# Авто-наводка.
const PASS_LEAD_GAIN := 0.25          # упреждение цели по её скорости (сек)
const PASS_THROUGH_EXTRA_LEAD := 2.0  # доп. вынос точки «на ход» вперёд по скорости цели, м
const PASS_DOT_BIAS := 0.15           # штраф за дистанцию в score выбора цели (0 → чистый dot)
const PASS_MAX_RANGE := 45.0          # дальше цель не рассматривается, м

# Коридор перехвата.
const PASS_CORRIDOR_HALF_WIDTH := 1.2 # полуширина коридора у точки паса, м
const PASS_CORRIDOR_SPREAD := 0.06    # прирост полуширины на метр вдоль паса

# Разброс точности.
const PASS_SPREAD_BASE := 12.0        # макс. разброс угла, градусы (при assist=0, дальней дистанции)
const PASS_SPREAD_DIST_REF := 25.0    # дистанция, на которой разброс достигает базового
const PASS_ASSIST := 0.75             # 0..1 «лёгкость»: 1 → почти без разброса

# Receive-assist (доводка принимающего к мячу).
const PASS_RECEIVE_PREDICT_WINDOW := 0.16  # на сколько сек вперёд предсказываем позицию мяча
const PASS_RECEIVE_DOT_THRESHOLD := 0.4    # порог dot(стик, к_мячу) для защёлкивания
const PASS_RECEIVE_MAX_TIME := 2.0         # страховочный таймаут фазы приёма, сек

# Give-and-go («стенка»).
const PASS_WALL_WINDOW := 3.0         # окно возврата, сек
const PASS_WALL_RUN_FORWARD := 10.0   # вынос рывка отдавшего вперёд по атаке, м
const PASS_WALL_RUN_LATERAL := 6.0    # вынос рывка в сторону, м

# Активный перехват ИИ-соперника (честный, не читерский).
const AI_INTERCEPT_REACT := 0.3       # задержка реакции соперника на пас, сек
const AI_INTERCEPT_CHANCE := 0.8      # шанс среагировать (иначе «зевает»)
```

- [ ] **Step 2: Verify headless load**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: exits with no script/parse errors (may print the known `PlayerVisual` duplicate-registration errors from other systems — those are pre-existing and unrelated).

- [ ] **Step 3: Commit**

```bash
git add scripts/data/football_constants.gd
git commit -m "feat(pass): add PASS_* and AI_INTERCEPT_* tuning constants"
```

---

### Task 2: `ball.launch(velocity)` + restitution

**Files:**
- Modify: `scripts/ball/ball_controller.gd` (add `launch`, set a physics material in `_ready` or setup)

**Interfaces:**
- Consumes: existing `_pending_impulse`, `mass`, `last_kicker`, `release_dribble()`.
- Produces: `ball.launch(velocity: Vector3) -> void` — sets ball velocity directly to `velocity` (as an impulse, mass-compensated), used by all pass firing.

- [ ] **Step 1: Add the `launch` method**

Add after `kick()` in `scripts/ball/ball_controller.gd`:

```gdscript
## Задать мячу готовую стартовую скорость (в отличие от kick(), где power — импульс, а dir
## не нормализован). velocity — уже посчитанная баллистика (PassSystem.launch_ground/launch_lob).
## Импульс = velocity*mass, т.к. _integrate_forces применяет vel += _pending_impulse/mass.
func launch(velocity: Vector3) -> void:
	last_kicker = dribbler
	_last_kick_time = Time.get_ticks_msec()
	release_dribble()
	_pending_impulse = velocity * mass
```

- [ ] **Step 2: Add a light restitution so lobs read on landing**

Find where the ball's `RigidBody3D` is configured (its `_ready`/setup in `ball_controller.gd`). Add:

```gdscript
	var phys_mat := PhysicsMaterial.new()
	phys_mat.bounce = 0.4
	physics_material_override = phys_mat
```

If `ball_controller.gd` has no `_ready`, add one containing just the three lines above. (Verify by reading the file's top before editing; place it alongside existing property init.)

- [ ] **Step 3: Verify headless load**

Run the headless `--quit` command from Task 1 Step 2. Expected: no new errors.

- [ ] **Step 4: Commit**

```bash
git add scripts/ball/ball_controller.gd
git commit -m "feat(pass): add ball.launch(velocity) and landing restitution"
```

---

### Task 3: `PassParams` data holder + `PassType` enum

**Files:**
- Create: `scripts/match/pass_params.gd`

**Interfaces:**
- Produces: `class_name PassParams extends RefCounted` with `enum PassType { SHORT_GROUND, THROUGH_GROUND, LOB, WALL, THROUGH_AIR }` and fields `power: float`, `peak_height: float`, `extra_lead: float`, `is_air: bool`, `is_wall: bool`. Referenced elsewhere as `PassParams.PassType.LOB`.

- [ ] **Step 1: Create the file**

```gdscript
class_name PassParams
extends RefCounted

## Тип паса. Пять значений, но по механике всего два семейства: «в точку мяча»
## (SHORT_GROUND/LOB) и «на ход» (THROUGH_GROUND/THROUGH_AIR). WALL — короткий пас + режим
## give-and-go у отдавшего. Тип задаёт только параметры ниже, не отдельный код-путь.
enum PassType { SHORT_GROUND, THROUGH_GROUND, LOB, WALL, THROUGH_AIR }

var power: float = 0.0          # базовая скорость мяча, м/с (для низовых)
var peak_height: float = 0.0    # высота дуги, м (0 → низом)
var extra_lead: float = 0.0     # доп. вынос точки «на ход», м
var is_air: bool = false        # верхом (баллистика) vs низом
var is_wall: bool = false       # запускать give-and-go у отдавшего
```

- [ ] **Step 2: Verify headless load**

Run the headless `--quit` command. Expected: no new errors (the class registers).

- [ ] **Step 3: Commit**

```bash
git add scripts/match/pass_params.gd
git commit -m "feat(pass): add PassParams data holder and PassType enum"
```

---

### Task 4: `PassSystem.select_target`

**Files:**
- Create: `scripts/match/pass_system.gd`
- Create: `tests/check_pass_system_math.gd`

**Interfaces:**
- Produces: `PassSystem.select_target(passer_pos, aim_dir, mate_positions: PackedVector3Array, mate_velocities: PackedVector3Array, lead_gain, dot_bias, max_range) -> int` — index of the best pass target in the `mate_*` arrays, or `-1` if none in range.

- [ ] **Step 1: Write the failing test**

Create `tests/check_pass_system_math.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var ok := true

	# select_target: партнёр строго по aim_dir побеждает партнёра сбоку.
	var mates_pos := PackedVector3Array([Vector3(10, 0, 0), Vector3(0, 0, 10)])
	var mates_vel := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var idx := PassSystem.select_target(Vector3.ZERO, Vector3(1, 0, 0), mates_pos, mates_vel, 0.0, 0.0, 45.0)
	if idx != 0:
		print("CHECK FAIL: select_target aligned → ", idx); ok = false
	# пустой список → -1
	if PassSystem.select_target(Vector3.ZERO, Vector3(1, 0, 0), PackedVector3Array(), PackedVector3Array(), 0.0, 0.0, 45.0) != -1:
		print("CHECK FAIL: select_target empty"); ok = false
	# все дальше max_range → -1
	var far := PackedVector3Array([Vector3(100, 0, 0)])
	if PassSystem.select_target(Vector3.ZERO, Vector3(1, 0, 0), far, PackedVector3Array([Vector3.ZERO]), 0.0, 0.0, 45.0) != -1:
		print("CHECK FAIL: select_target out of range"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_pass_system_math.gd"`
Expected: FAIL (parse error — `PassSystem` not defined).

- [ ] **Step 3: Write minimal implementation**

Create `scripts/match/pass_system.gd`:

```gdscript
class_name PassSystem
extends Object

## Выбор цели паса: партнёр, лучше всего совпадающий с направлением прицела (стика), с
## упреждением по скорости и штрафом за дистанцию. Возвращает индекс в mate_* или -1.
## Все данные — POD; узлы держит вызывающий (индекс → узел).
static func select_target(passer_pos: Vector3, aim_dir: Vector3,
		mate_positions: PackedVector3Array, mate_velocities: PackedVector3Array,
		lead_gain: float, dot_bias: float, max_range: float) -> int:
	var aim := aim_dir
	aim.y = 0.0
	if aim.length() < 0.001:
		return -1
	aim = aim.normalized()
	var best_idx := -1
	var best_score := -1000.0
	for i in range(mate_positions.size()):
		var predicted: Vector3 = mate_positions[i] + mate_velocities[i] * lead_gain
		var diff := predicted - passer_pos
		diff.y = 0.0
		var dist := diff.length()
		if dist > max_range or dist < 0.001:
			continue
		var score := diff.normalized().dot(aim) - dot_bias * (dist / max_range)
		if score > best_score:
			best_score = score
			best_idx = i
	return best_idx
```

- [ ] **Step 4: Run test to verify it passes**

Run the check command from Step 2. Expected: `CHECK PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/pass_system.gd tests/check_pass_system_math.gd
git commit -m "feat(pass): PassSystem.select_target + headless test"
```

---

### Task 5: `PassSystem.lead_point`

**Files:**
- Modify: `scripts/match/pass_system.gd`
- Modify: `tests/check_pass_system_math.gd`

**Interfaces:**
- Produces: `PassSystem.lead_point(target_pos, target_vel, passer_pos, ball_speed, extra_lead) -> Vector3` — the aim point ahead of a moving target.

- [ ] **Step 1: Write the failing test**

Insert before the final `print(...)` in `_initialize()` of `tests/check_pass_system_math.gd`:

```gdscript
	# lead_point: движущуюся цель ведём по её скорости на время полёта мяча.
	var lp := PassSystem.lead_point(Vector3(10, 0, 0), Vector3(0, 0, 5), Vector3.ZERO, 15.0, 0.0)
	if not lp.is_equal_approx(Vector3(10, 0, 10.0 / 15.0 * 5.0)):
		print("CHECK FAIL: lead_point moving → ", lp); ok = false
	# стоящая цель → точка == позиции цели
	if not PassSystem.lead_point(Vector3(8, 0, 0), Vector3.ZERO, Vector3.ZERO, 12.0, 3.0).is_equal_approx(Vector3(8, 0, 0)):
		print("CHECK FAIL: lead_point static"); ok = false
```

- [ ] **Step 2: Run test to verify it fails**

Run the check command. Expected: FAIL (`lead_point` not defined / parse error).

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/match/pass_system.gd`:

```gdscript
## Точка упреждения: куда бить, чтобы прийти к движущейся цели. Время полёта = дистанция /
## скорость мяча; плюс доп. вынос вперёд по скорости цели (для паса «на ход»). Стоящая цель
## (vel≈0) → точка == позиции цели (extra_lead игнорируется, некуда вести).
static func lead_point(target_pos: Vector3, target_vel: Vector3, passer_pos: Vector3,
		ball_speed: float, extra_lead: float) -> Vector3:
	var flat_to := target_pos - passer_pos
	flat_to.y = 0.0
	var travel := flat_to.length() / maxf(ball_speed, 0.001)
	var point := target_pos + target_vel * travel
	var vflat := target_vel
	vflat.y = 0.0
	if vflat.length() > 0.001:
		point += vflat.normalized() * extra_lead
	point.y = target_pos.y
	return point
```

- [ ] **Step 4: Run test to verify it passes**

Run the check command. Expected: `CHECK PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/pass_system.gd tests/check_pass_system_math.gd
git commit -m "feat(pass): PassSystem.lead_point + test"
```

---

### Task 6: `PassSystem.launch_ground` + `launch_lob`

**Files:**
- Modify: `scripts/match/pass_system.gd`
- Modify: `tests/check_pass_system_math.gd`

**Interfaces:**
- Produces:
  - `PassSystem.launch_ground(from, to, power) -> Vector3` — flat launch velocity of magnitude `power`.
  - `PassSystem.launch_lob(from, to, peak_height, gravity) -> Vector3` — ballistic launch velocity (with `+Y`) that lands at `to` peaking at `peak_height`.

- [ ] **Step 1: Write the failing test**

Insert before the final `print(...)`:

```gdscript
	# launch_ground: плоский вектор к цели длиной power.
	var lg := PassSystem.launch_ground(Vector3.ZERO, Vector3(3, 0, 4), 10.0)
	if not is_equal_approx(lg.length(), 10.0) or not is_zero_approx(lg.y):
		print("CHECK FAIL: launch_ground magnitude/flat → ", lg); ok = false
	if not is_equal_approx(lg.normalized().dot(Vector3(3, 0, 4).normalized()), 1.0):
		print("CHECK FAIL: launch_ground direction"); ok = false

	# launch_lob: ре-симуляция дуги приземляет мяч ≈ в to, пик ≈ peak_height.
	var g := 20.0
	var v0 := PassSystem.launch_lob(Vector3.ZERO, Vector3(12, 0, 0), 3.0, g)
	var p := Vector3.ZERO
	var v := v0
	var dt := 1.0 / 240.0
	var peak := 0.0
	for _i in range(4000):
		v.y -= g * dt
		p += v * dt
		peak = maxf(peak, p.y)
		if p.y <= 0.0 and v.y < 0.0:
			break
	if absf(p.x - 12.0) > 0.3 or absf(p.z) > 0.3:
		print("CHECK FAIL: launch_lob landing → ", p); ok = false
	if absf(peak - 3.0) > 0.2:
		print("CHECK FAIL: launch_lob peak → ", peak); ok = false
```

- [ ] **Step 2: Run test to verify it fails**

Run the check command. Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/match/pass_system.gd`:

```gdscript
## Низовой пас: плоская скорость к цели, величиной power (м/с).
static func launch_ground(from: Vector3, to: Vector3, power: float) -> Vector3:
	var dir := to - from
	dir.y = 0.0
	if dir.length() < 0.001:
		return Vector3.ZERO
	return dir.normalized() * power

## Навес/верховой пас: баллистическая стартовая скорость, приземляющая мяч в to с пиком
## peak_height, под гравитацию gravity. Старт и приземление на одной высоте (плоское поле):
## v_y = sqrt(2*g*h); полное время полёта T = 2*v_y/g; горизонталь = flat/T.
static func launch_lob(from: Vector3, to: Vector3, peak_height: float, gravity: float) -> Vector3:
	var vy := sqrt(2.0 * gravity * maxf(peak_height, 0.001))
	var flight := 2.0 * vy / gravity
	var flat := to - from
	flat.y = 0.0
	var horizontal := flat / maxf(flight, 0.001)
	return Vector3(horizontal.x, vy, horizontal.z)
```

- [ ] **Step 4: Run test to verify it passes**

Run the check command. Expected: `CHECK PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/pass_system.gd tests/check_pass_system_math.gd
git commit -m "feat(pass): PassSystem.launch_ground/launch_lob + ballistics test"
```

---

### Task 7: `PassSystem.interception_time`

**Files:**
- Modify: `scripts/match/pass_system.gd`
- Modify: `tests/check_pass_system_math.gd`

**Interfaces:**
- Produces: `PassSystem.interception_time(pass_from, pass_to, ball_speed, opp_pos, opp_speed, corridor_half_width, corridor_spread) -> float` — time (s) at which the opponent can reach the pass lane, or `INF` if it cannot (outside the widening corridor, behind the pass, or too slow).

- [ ] **Step 1: Write the failing test**

Insert before the final `print(...)`:

```gdscript
	# interception_time: соперник на линии паса и близко → конечное время.
	var t_hit := PassSystem.interception_time(Vector3.ZERO, Vector3(20, 0, 0), 15.0, Vector3(10, 0, 0.2), 6.0, 1.2, 0.06)
	if is_inf(t_hit) or t_hit <= 0.0:
		print("CHECK FAIL: interception on-line finite → ", t_hit); ok = false
	# соперник далеко вбок → INF (вне коридора).
	if not is_inf(PassSystem.interception_time(Vector3.ZERO, Vector3(20, 0, 0), 15.0, Vector3(10, 0, 8.0), 6.0, 1.2, 0.06)):
		print("CHECK FAIL: interception off-corridor INF"); ok = false
	# соперник позади точки паса → INF.
	if not is_inf(PassSystem.interception_time(Vector3.ZERO, Vector3(20, 0, 0), 15.0, Vector3(-5, 0, 0), 6.0, 1.2, 0.06)):
		print("CHECK FAIL: interception behind INF"); ok = false
```

- [ ] **Step 2: Run test to verify it fails**

Run the check command. Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/match/pass_system.gd`:

```gdscript
## Успеет ли соперник перехватить пас в коридоре. Проецируем соперника на луч паса:
## along — вдоль (0..длина), across — поперёк. Коридор расширяется с дистанцией
## (half + along*spread). Соперник перехватывает, если внутри коридора И добегает до линии
## не позже мяча. Возврат — время перехвата (сек) или INF.
static func interception_time(pass_from: Vector3, pass_to: Vector3, ball_speed: float,
		opp_pos: Vector3, opp_speed: float, corridor_half_width: float, corridor_spread: float) -> float:
	var line := pass_to - pass_from
	line.y = 0.0
	var length := line.length()
	if length < 0.001:
		return INF
	var dir := line / length
	var rel := opp_pos - pass_from
	rel.y = 0.0
	var along := rel.dot(dir)
	if along < 0.0 or along > length:
		return INF
	var closest := pass_from + dir * along
	var across := (opp_pos - closest)
	across.y = 0.0
	var across_dist := across.length()
	var half := corridor_half_width + along * corridor_spread
	if across_dist > half:
		return INF
	var ball_time := along / maxf(ball_speed, 0.001)
	var opp_time := across_dist / maxf(opp_speed, 0.001)
	if opp_time <= ball_time:
		return ball_time
	return INF
```

- [ ] **Step 4: Run test to verify it passes**

Run the check command. Expected: `CHECK PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/pass_system.gd tests/check_pass_system_math.gd
git commit -m "feat(pass): PassSystem.interception_time corridor + test"
```

---

### Task 8: `PassSystem.scatter_degrees` + `apply_scatter`

**Files:**
- Modify: `scripts/match/pass_system.gd`
- Modify: `tests/check_pass_system_math.gd`

**Interfaces:**
- Produces:
  - `PassSystem.scatter_degrees(spread_base, assist, distance, distance_ref) -> float` — max scatter angle (deg), grows with distance, shrinks with assist.
  - `PassSystem.apply_scatter(flat_dir, spread_deg, rng: RandomNumberGenerator) -> Vector3` — `flat_dir` rotated around Y by a random angle in `±spread_deg`.

- [ ] **Step 1: Write the failing test**

Insert before the final `print(...)`:

```gdscript
	# scatter_degrees: дальше → больше разброс; assist=1 → ноль.
	if PassSystem.scatter_degrees(12.0, 0.0, 30.0, 25.0) <= PassSystem.scatter_degrees(12.0, 0.0, 5.0, 25.0):
		print("CHECK FAIL: scatter grows with distance"); ok = false
	if not is_zero_approx(PassSystem.scatter_degrees(12.0, 1.0, 30.0, 25.0)):
		print("CHECK FAIL: scatter zero at assist=1"); ok = false

	# apply_scatter: детерминизм по seed.
	var rng_a := RandomNumberGenerator.new(); rng_a.seed = 42
	var rng_b := RandomNumberGenerator.new(); rng_b.seed = 42
	var sa := PassSystem.apply_scatter(Vector3(1, 0, 0), 10.0, rng_a)
	var sb := PassSystem.apply_scatter(Vector3(1, 0, 0), 10.0, rng_b)
	if not sa.is_equal_approx(sb):
		print("CHECK FAIL: apply_scatter deterministic → ", sa, sb); ok = false
	# нулевой разброс → вектор не меняется.
	var rng_c := RandomNumberGenerator.new(); rng_c.seed = 1
	if not PassSystem.apply_scatter(Vector3(1, 0, 0), 0.0, rng_c).is_equal_approx(Vector3(1, 0, 0)):
		print("CHECK FAIL: apply_scatter zero spread"); ok = false
```

- [ ] **Step 2: Run test to verify it fails**

Run the check command. Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/match/pass_system.gd`:

```gdscript
## Максимальный угол разброса (градусы): растёт с дистанцией, гасится «лёгкостью» assist.
static func scatter_degrees(spread_base: float, assist: float, distance: float, distance_ref: float) -> float:
	var dist_factor := clampf(distance / maxf(distance_ref, 0.001), 0.2, 1.5)
	return spread_base * (1.0 - clampf(assist, 0.0, 1.0)) * dist_factor

## Повернуть плоское направление вокруг оси Y на случайный угол в пределах ±spread_deg.
## RNG передаётся снаружи → детерминизм в тестах (seed).
static func apply_scatter(flat_dir: Vector3, spread_deg: float, rng: RandomNumberGenerator) -> Vector3:
	if spread_deg <= 0.0:
		return flat_dir
	var angle := deg_to_rad(rng.randf_range(-spread_deg, spread_deg))
	return flat_dir.rotated(Vector3.UP, angle)
```

- [ ] **Step 4: Run test to verify it passes**

Run the check command. Expected: `CHECK PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/pass_system.gd tests/check_pass_system_math.gd
git commit -m "feat(pass): PassSystem scatter_degrees/apply_scatter + test"
```

---

### Task 9: Input overhaul — keyboard remap + gamepad in `_setup_inputs`

**Files:**
- Modify: `scripts/match/match_manager.gd` — replace the body of `_setup_inputs()` ([`match_manager.gd:113`](../../../scripts/match/match_manager.gd))

**Interfaces:**
- Produces: input actions `move_left/right/forward/back`, `sprint`, `kick`, `pass_short`, `pass_through`, `pass_lob`, `combo_modifier`, `pause`, each with keyboard + joypad events. Removes old `pass`, `swap_player` letter-move bindings.

- [ ] **Step 1: Replace `_setup_inputs()`**

Replace the whole function with:

```gdscript
func _setup_inputs() -> void:
	# Строим ввод в коде (project.godot мёртв). Движение — стрелки + левый стик; буквы WASD
	# освобождены под действия. Каждый action может иметь и клавиши, и джойпад-события.
	# key_events: клавиши. joy_buttons: кнопки геймпада. joy_axes: [оси] как [axis, value].
	var actions := {
		&"move_left":       {"keys": [KEY_LEFT],  "buttons": [], "axes": [[JOY_AXIS_LEFT_X, -1.0]]},
		&"move_right":      {"keys": [KEY_RIGHT], "buttons": [], "axes": [[JOY_AXIS_LEFT_X, 1.0]]},
		&"move_forward":    {"keys": [KEY_UP],    "buttons": [], "axes": [[JOY_AXIS_LEFT_Y, -1.0]]},
		&"move_back":       {"keys": [KEY_DOWN],  "buttons": [], "axes": [[JOY_AXIS_LEFT_Y, 1.0]]},
		&"sprint":          {"keys": [KEY_SHIFT], "buttons": [], "axes": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]},
		&"kick":            {"keys": [KEY_D],     "buttons": [JOY_BUTTON_X], "axes": []},
		&"pass_short":      {"keys": [KEY_X],     "buttons": [JOY_BUTTON_A], "axes": []},
		&"pass_through":    {"keys": [KEY_W],     "buttons": [JOY_BUTTON_Y], "axes": []},
		&"pass_lob":        {"keys": [KEY_A],     "buttons": [JOY_BUTTON_B], "axes": []},
		&"combo_modifier":  {"keys": [KEY_Q],     "buttons": [JOY_BUTTON_LEFT_SHOULDER], "axes": []},
		&"pause":           {"keys": [KEY_ESCAPE],"buttons": [JOY_BUTTON_START], "axes": []},
	}
	for action in actions:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action)
		InputMap.action_set_deadzone(action, 0.2)
		for keycode in actions[action]["keys"]:
			var ek := InputEventKey.new()
			ek.keycode = keycode
			InputMap.action_add_event(action, ek)
		for btn in actions[action]["buttons"]:
			var eb := InputEventJoypadButton.new()
			eb.button_index = btn
			InputMap.action_add_event(action, eb)
		for ax in actions[action]["axes"]:
			var em := InputEventJoypadMotion.new()
			em.axis = ax[0]
			em.axis_value = ax[1]
			InputMap.action_add_event(action, em)
	print("Inputs setup OK")
```

- [ ] **Step 2: Verify headless load**

Run the headless `--quit` command. Expected: no errors; prints `Inputs setup OK`.

- [ ] **Step 3: Manual smoke test (keyboard)**

Run the game (same exe, no `--headless --quit`), start a match. NOTE: passing/kick dispatch is rewired in later tasks — at this point verify only that **movement now responds to arrow keys** and that WASD letters no longer move the player. Old `E`/`Space`/`Q`-swap behavior is expected to be broken here; that is fixed in Tasks 10–12.

- [ ] **Step 4: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(pass): remap inputs (arrows+stick move, gamepad, combo modifier)"
```

---

### Task 10: Movement via `get_vector`, analog sprint, context-sensitive swap

**Files:**
- Modify: `scripts/match/match_manager.gd` — movement block in `_handle_player_input` ([`match_manager.gd:626-643`](../../../scripts/match/match_manager.gd)); swap block in `_physics_process` ([`match_manager.gd:506-509`](../../../scripts/match/match_manager.gd))

**Interfaces:**
- Consumes: new input actions from Task 9.
- Produces: analog movement/sprint; `combo_modifier` acts as player-swap when our team does NOT possess the ball.

- [ ] **Step 1: Replace the movement/sprint computation**

In `_handle_player_input`, replace the block that builds `input_dir`, `dir`, and `sprint_scale` (currently lines ~626-643, from `var input_dir := Vector2(` through the `motor.set_move_intent(dir, sprint_scale)` call) with:

```gdscript
	var input_vec := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var cam_basis := camera_pivot.global_transform.basis
	var cam_forward := -cam_basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()
	var cam_right := cam_basis.x
	cam_right.y = 0
	cam_right = cam_right.normalized()
	var dir := (cam_forward * -input_vec.y + cam_right * input_vec.x)
	if dir.length() > 1.0:
		dir = dir.normalized()
	# Аналоговый спринт: сила триггера (или 1.0 с клавиши Shift) лерпит speed_scale.
	var sprint_strength := Input.get_action_strength(&"sprint")
	var sprint_scale := lerpf(1.0, FootballConstants.LOCO_SPRINT_SPEED / FootballConstants.LOCO_TOP_SPEED, sprint_strength)
	var motor := _player_motor(controlled_player)
	if motor != null:
		motor.set_move_intent(dir, sprint_scale)
```

(Note: `input_vec` keeps analog magnitude from the stick; `dir` is intentionally NOT force-normalized so a half-tilted stick walks. `set_move_intent` handles direction+scale.)

- [ ] **Step 2: Replace the swap block**

In `_physics_process`, replace the swap block (currently lines ~506-509):

```gdscript
	# Смена игрока — только в защите (мяч не у нас). В атаке combo_modifier = модификатор паса.
	if Input.is_action_just_pressed(&"combo_modifier") and not _we_possess():
		controlled_player = player_teammate if controlled_player == player_home else player_home
		_sync_ai_controllers()
		_manual_swap_cooldown = 10
```

- [ ] **Step 3: Add the possession helper**

Add near the other small helpers (e.g. after `_is_our_dribbler`, ~line 669):

```gdscript
## Владеет ли наша команда мячом сейчас (для контекст-зависимого combo_modifier).
func _we_possess() -> bool:
	if not (ball.has_method(&"set_dribbler") and ball.dribbler):
		return false
	return ball.dribbler == player_home or ball.dribbler == player_teammate
```

- [ ] **Step 4: Verify headless load + manual**

Run the headless `--quit` command (expect no errors). Then run the game: movement works on arrows AND a gamepad left stick (analog); holding Shift / RT sprints; when the opponent has the ball, tapping Q / LB switches controlled player.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(pass): analog move+sprint, context-sensitive player swap"
```

---

### Task 11: Generalize charge to `enum ChargeAction`

**Files:**
- Modify: `scripts/match/match_manager.gd` — charge fields ([`:53-60`](../../../scripts/match/match_manager.gd)), `_process` charge block ([`:473-488`](../../../scripts/match/match_manager.gd)), `_start_kick_charge`/`_fire_kick`/`_cancel_kick_charge` ([`:671-712`](../../../scripts/match/match_manager.gd)), kick dispatch in `_handle_player_input` ([`:645-655`](../../../scripts/match/match_manager.gd))

**Interfaces:**
- Produces: `enum ChargeAction { NONE, SHOT, PASS_SHORT, PASS_THROUGH, PASS_LOB, PASS_WALL, PASS_THROUGH_AIR }`; fields `_charge_action`, `_charge_time`, `_charge_player`; helper `_is_charging() -> bool`. Kick continues to work through `ChargeAction.SHOT`.

- [ ] **Step 1: Replace the charge fields**

Replace the block (`var _kick_charging` … `const KICK_POWER_MAX`) at ~lines 53-60 with:

```gdscript
# Обобщённый заряд: одно действие заряжается за раз (удар ИЛИ один из пасов).
enum ChargeAction { NONE, SHOT, PASS_SHORT, PASS_THROUGH, PASS_LOB, PASS_WALL, PASS_THROUGH_AIR }
var _charge_action: ChargeAction = ChargeAction.NONE
var _charge_time: float = 0.0
var _charge_player: CharacterBody3D
const KICK_CHARGE_MAX_TIME: float = 0.5
const KICK_POWER_MIN: float = 12.0
const KICK_POWER_MAX: float = 25.0

func _is_charging() -> bool:
	return _charge_action != ChargeAction.NONE
```

- [ ] **Step 2: Rewrite the `_process` charge block**

Replace the charge block in `_process` (lines ~473-488) with:

```gdscript
	# Заряд: копим, пока держим кнопку заряжаемого действия.
	if _is_charging() and _charge_player == controlled_player:
		var max_time := KICK_CHARGE_MAX_TIME if _charge_action == ChargeAction.SHOT else FootballConstants.PASS_CHARGE_MAX_TIME
		_charge_time += get_process_delta_time()
		if _charge_time >= max_time:
			_charge_time = max_time
			_fire_charge()
		if _is_charging():
			var ratio := clampf(_charge_time / max_time, 0.0, 1.0)
			power_bar.value = ratio
			var fill := power_bar.get_theme_stylebox("fill")
			if fill:
				fill.bg_color = Color.GREEN_YELLOW.lerp(Color.RED, ratio * ratio)
	elif _is_charging():
		_cancel_charge()
	power_bar.visible = _is_charging() and _charge_player == controlled_player
```

- [ ] **Step 3: Rewrite kick charge start/fire/cancel**

Replace `_start_kick_charge`, `_fire_kick`, `_cancel_kick_charge` (lines ~671-712) with the generalized versions. `_fire_charge()` dispatches by `_charge_action`; the SHOT branch reproduces the old kick behavior:

```gdscript
func _start_charge(action: ChargeAction, player_node: CharacterBody3D) -> void:
	_charge_action = action
	_charge_time = 0.0
	_charge_player = player_node
	var dir: Vector3 = ball.get_dribble_direction()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		player_node.rotation.y = atan2(-flat.x, -flat.z)

func _fire_charge() -> void:
	if not _is_charging() or not _charge_player or not is_instance_valid(_charge_player):
		_cancel_charge()
		return
	var action := _charge_action
	var player := _charge_player
	if action == ChargeAction.SHOT:
		var ratio := clampf(_charge_time / KICK_CHARGE_MAX_TIME, 0.0, 1.0)
		var power := lerpf(KICK_POWER_MIN, KICK_POWER_MAX, ratio)
		var dir: Vector3 = ball.get_dribble_direction()
		dir.y = lerpf(0.05, 0.5, ratio)
		_cancel_charge()
		_action_player = player
		_action_dir = dir
		_action_power = power
		_kick_action_active = true
		var visual := _player_visual(player)
		if visual != null and visual.trigger("kick"):
			return
		ball.kick(dir, power)
		_action_player = null
		_kick_action_active = false
	else:
		var charge_ratio := clampf(_charge_time / FootballConstants.PASS_CHARGE_MAX_TIME, 0.0, 1.0)
		_cancel_charge()
		_fire_pass(action, player, charge_ratio)

func _cancel_charge() -> void:
	_charge_action = ChargeAction.NONE
	_charge_time = 0.0
	_charge_player = null
	power_bar.visible = false
```

- [ ] **Step 4: Rewire kick dispatch in `_handle_player_input`**

Replace the kick charge block (lines ~645-655, `if Input.is_action_just_pressed(&"kick")` … `_fire_kick()`) with:

```gdscript
	if Input.is_action_just_pressed(&"kick"):
		if _is_charging():
			pass
		elif _is_near_ball(controlled_player) and _is_our_dribbler(controlled_player):
			_start_charge(ChargeAction.SHOT, controlled_player)
		else:
			_try_tackle(controlled_player)
	if Input.is_action_just_released(&"kick") and _charge_action == ChargeAction.SHOT and _charge_player == controlled_player:
		_fire_charge()
```

Also DELETE the old pass dispatch lines (`if Input.is_action_just_pressed(&"pass"): _pass_ball(controlled_player)` at ~657-658) — pass is re-added in Task 12. Leave `_pass_ball` defined for now (unused); it is removed in Task 12.

- [ ] **Step 5: Add a stub `_fire_pass` so the file parses**

Add a temporary stub (fully implemented in Task 12):

```gdscript
func _fire_pass(_action: ChargeAction, _player: CharacterBody3D, _charge_ratio: float) -> void:
	pass  # реализуется в Task 12
```

- [ ] **Step 6: Verify headless load + manual**

Run the headless `--quit` command (no errors). Run the game: holding `D` / gamepad `X` while dribbling charges the power bar (green→red) and releasing fires a shot exactly as before; `D` without the ball still triggers a tackle.

- [ ] **Step 7: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "refactor(pass): generalize charge into ChargeAction enum (kick intact)"
```

---

### Task 12: Fire a short ground pass end-to-end

**Files:**
- Modify: `scripts/match/match_manager.gd` — implement `_fire_pass`, add `_pass_charge_dispatch`, add roster/params helpers; delete old `_pass_ball` ([`:715-735`](../../../scripts/match/match_manager.gd))

**Interfaces:**
- Consumes: `PassSystem.select_target/lead_point/launch_ground`, `PassParams`, `ball.launch`, existing commit-action (`_action_player`, `action_contact`).
- Produces: `_fire_pass(action, player, charge_ratio)`, `_pass_params(action) -> PassParams`, `_team_arrays(group) -> Dictionary`, control handoff to the receiver.

- [ ] **Step 1: Add pass-button dispatch in `_handle_player_input`**

Add after the kick block (from Task 11 Step 4), before the function ends:

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
	for act in [&"pass_short", &"pass_through", &"pass_lob"]:
		if Input.is_action_just_released(act) and _is_charging() and _charge_action != ChargeAction.SHOT and _charge_player == controlled_player:
			_fire_charge()
			break
```

- [ ] **Step 2: Add `_pass_params`**

Add this helper (builds `PassParams` from `FootballConstants` — done in the orchestrator, not in a static factory):

```gdscript
## Собрать параметры паса по заряжаемому действию. Заряд множит базовую силу.
func _pass_params(action: ChargeAction, charge_ratio: float) -> PassParams:
	var p := PassParams.new()
	var mult := lerpf(FootballConstants.PASS_POWER_CHARGE_MIN, FootballConstants.PASS_POWER_CHARGE_MAX, charge_ratio)
	match action:
		ChargeAction.PASS_SHORT:
			p.power = FootballConstants.PASS_SHORT_POWER * mult
		ChargeAction.PASS_WALL:
			p.power = FootballConstants.PASS_SHORT_POWER * mult
			p.is_wall = true
		ChargeAction.PASS_THROUGH:
			p.power = FootballConstants.PASS_THROUGH_POWER * mult
			p.extra_lead = FootballConstants.PASS_THROUGH_EXTRA_LEAD
		ChargeAction.PASS_LOB:
			p.peak_height = FootballConstants.PASS_LOB_PEAK_HEIGHT * mult
			p.is_air = true
		ChargeAction.PASS_THROUGH_AIR:
			p.peak_height = FootballConstants.PASS_THROUGH_AIR_PEAK_HEIGHT * mult
			p.extra_lead = FootballConstants.PASS_THROUGH_EXTRA_LEAD
			p.is_air = true
		_:
			p.power = FootballConstants.PASS_SHORT_POWER * mult
	return p
```

- [ ] **Step 3: Add roster gathering helper**

```gdscript
## Позиции/скорости/узлы группы в параллельных массивах (индекс общий). Исключает except_node.
func _team_arrays(group: StringName, except_node: Node) -> Dictionary:
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var nodes: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(group):
		if n == except_node or not (n is CharacterBody3D) or not is_instance_valid(n):
			continue
		positions.append(n.global_position)
		velocities.append(n.velocity)
		nodes.append(n)
	return {"pos": positions, "vel": velocities, "nodes": nodes}
```

- [ ] **Step 4: Implement `_fire_pass` (replace the Task 11 stub)**

```gdscript
## Выполнить пас: выбрать цель по прицелу, посчитать траекторию, применить импульс через
## commit-action (как удар), передать управление принимающему сразу.
func _fire_pass(action: ChargeAction, player: CharacterBody3D, charge_ratio: float) -> void:
	if not ball.has_method(&"launch"):
		return
	var params := _pass_params(action, charge_ratio)
	var mates := _team_arrays(&"team_1", player)
	var mate_pos: PackedVector3Array = mates["pos"]
	var mate_vel: PackedVector3Array = mates["vel"]
	var mate_nodes: Array = mates["nodes"]
	var aim := ball.get_dribble_direction()
	var idx := PassSystem.select_target(player.global_position, aim, mate_pos, mate_vel,
		FootballConstants.PASS_LEAD_GAIN, FootballConstants.PASS_DOT_BIAS, FootballConstants.PASS_MAX_RANGE)
	# Точка прицела: в ноги (короткий/навес) или на ход (through). Нет цели → по направлению прицела.
	var from := ball.global_position
	var aim_point: Vector3
	var receiver: CharacterBody3D = null
	var ball_speed := params.power if not params.is_air else FootballConstants.PASS_THROUGH_POWER
	if idx >= 0:
		receiver = mate_nodes[idx]
		if params.extra_lead > 0.0:
			aim_point = PassSystem.lead_point(mate_pos[idx], mate_vel[idx], from, ball_speed, params.extra_lead)
		else:
			aim_point = mate_pos[idx]
	else:
		var flat := Vector3(aim.x, 0.0, aim.z).normalized()
		aim_point = from + flat * 12.0
	# Разброс точности.
	var flat_dir := (aim_point - from)
	flat_dir.y = 0.0
	var spread := PassSystem.scatter_degrees(FootballConstants.PASS_SPREAD_BASE, FootballConstants.PASS_ASSIST,
		flat_dir.length(), FootballConstants.PASS_SPREAD_DIST_REF)
	flat_dir = PassSystem.apply_scatter(flat_dir, spread, _pass_rng)
	aim_point = from + flat_dir + Vector3(0.0, aim_point.y - from.y, 0.0)
	# Баллистика.
	var launch_vel: Vector3
	if params.is_air:
		var g := _ball_gravity()
		launch_vel = PassSystem.launch_lob(from, aim_point, params.peak_height, g)
	else:
		launch_vel = PassSystem.launch_ground(from, aim_point, params.power)
	# Commit-action: импульс по action_contact, без блокировки мотора (как kick).
	_action_player = player
	_action_dir = launch_vel  # для пасов _action_dir несёт готовую скорость (см. _on_action_contact)
	_action_power = -1.0       # маркер «это launch, а не kick»
	_kick_action_active = true
	_pending_launch = launch_vel
	# Передать управление принимающему сразу.
	if receiver != null:
		controlled_player = receiver
		_sync_ai_controllers()
		_manual_swap_cooldown = 30
	var visual := _player_visual(player)
	if visual != null and visual.trigger("pass"):
		return
	ball.launch(launch_vel)
	_action_player = null
	_kick_action_active = false
```

- [ ] **Step 5: Add supporting fields + gravity helper + contact handling**

Add fields near the other pass fields:

```gdscript
var _pass_rng := RandomNumberGenerator.new()
var _pending_launch: Vector3 = Vector3.ZERO
```

Add helper:

```gdscript
## Реальная гравитация мяча (RigidBody под движковую гравитацию, НЕ FootballConstants.GRAVITY).
func _ball_gravity() -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return g * ball.gravity_scale
```

In `_ready()` (after other setup), seed the RNG:

```gdscript
	_pass_rng.randomize()
```

Update `_on_action_contact` (line ~761) to apply a launch when `_action_power < 0`:

```gdscript
func _on_action_contact(_action: String, player: Node) -> void:
	if player != _action_player:
		return
	if _action_power < 0.0 and ball.has_method(&"launch"):
		ball.launch(_pending_launch)
	elif ball.has_method(&"kick"):
		ball.kick(_action_dir, _action_power)
```

- [ ] **Step 6: Delete the old `_pass_ball`**

Remove the entire `_pass_ball` function (lines ~715-735) — it is superseded.

- [ ] **Step 7: Verify headless load + manual**

Run the headless `--quit` command (no errors). Run the game: dribble, tap `X` / gamepad `A` → ball goes to the teammate (charge the bar by holding for more power), and control switches to the receiver.

- [ ] **Step 8: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(pass): short ground pass end-to-end (target, scatter, handoff)"
```

---

### Task 13: Wire remaining pass types (through, lob, through-air, wall)

**Files:**
- Modify: `scripts/match/match_manager.gd` (already dispatched in Task 12 Step 1; this task verifies each type produces the right trajectory)

**Interfaces:**
- Consumes: `_fire_pass` + `_pass_params` from Task 12 (already handle all `ChargeAction` cases).

- [ ] **Step 1: Confirm dispatch covers all types**

Re-read the pass dispatch (Task 12 Step 1) and `_pass_params` (Task 12 Step 2). Verify: `pass_through` → `PASS_THROUGH` (or `PASS_THROUGH_AIR` with combo), `pass_lob` → `PASS_LOB`, `pass_short`+combo → `PASS_WALL`. No code change expected; if a branch is missing, add it to match Task 12.

- [ ] **Step 2: Verify headless load**

Run the headless `--quit` command. Expected: no errors.

- [ ] **Step 3: Manual test each type**

Run the game and confirm:
- `W` / `Y`: through ground pass leads ahead of a moving teammate (rolls into space, not to feet).
- `A` / `B`: lob arcs over the ground and lands near the teammate.
- `Q+W` / `LB+Y`: through-air — lofted and led ahead.
- `Q+X` / `LB+A`: wall pass fires as a short pass (the give-and-go run behavior is added in Task 17; here just confirm it passes and hands off).

Tune `PASS_*` magnitudes in `football_constants.gd` if a trajectory over/undershoots (arc height, power).

- [ ] **Step 4: Commit**

```bash
git add scripts/match/match_manager.gd scripts/data/football_constants.gd
git commit -m "feat(pass): verify+tune through/lob/through-air/wall trajectories"
```

---

### Task 14: Fix teammate support direction + add `Role` enum with RECEIVING

**Files:**
- Modify: `scripts/ai/teammate_ai.gd` — add `Role`, fix `_position_for_pass` sign ([`teammate_ai.gd:47`](../../../scripts/ai/teammate_ai.gd)), add RECEIVING

**Interfaces:**
- Produces: `enum Role { SUPPORT, RECEIVING, CHASING }`, fields `_role`, `_pass_dir`, `_pass_lead`; method `begin_receiving(pass_dir: Vector3, lead: float) -> void`; method `end_receiving() -> void`.

- [ ] **Step 1: Add role state and API**

Add near the top of `teammate_ai.gd` (after existing vars):

```gdscript
enum Role { SUPPORT, RECEIVING, CHASING }
var _role: Role = Role.SUPPORT
var _pass_dir: Vector3 = Vector3.ZERO
var _pass_lead: float = 0.0

## Менеджер зовёт это на партнёре, которому летит пас: перейти в режим выхода на приём.
func begin_receiving(pass_dir: Vector3, lead: float) -> void:
	_role = Role.RECEIVING
	_pass_dir = pass_dir
	_pass_lead = lead

func end_receiving() -> void:
	if _role == Role.RECEIVING:
		_role = Role.SUPPORT
```

- [ ] **Step 2: Route behavior by role and fix the support direction bug**

Replace the tail of `_physics_process` (the `if has_dribbler and ball.dribbler == controlled_player: _position_for_pass(delta); return` / `_chase_ball(delta)` block, lines ~33-39) with:

```gdscript
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

In `_position_for_pass`, fix the sign — we attack toward **−Z**, so support runs ahead at `−Z`, not `+Z`. Replace the `target` line (line ~47):

```gdscript
	var target := carrier_pos + Vector3(0, 0, -10.0) + Vector3(side_sign * 6.0, 0, 0)
```

- [ ] **Step 3: Add the receive movement**

Add:

```gdscript
## Выход на приём: в ноги — к предсказанной точке мяча; на ход — вперёд по вектору паса.
func _move_to_receive(delta: float) -> void:
	var target: Vector3
	if _pass_lead > 0.0:
		target = global_position + _pass_dir.normalized() * _pass_lead
	else:
		var predicted := ball.global_position + ball.linear_velocity * FootballConstants.PASS_RECEIVE_PREDICT_WINDOW
		target = predicted
	target.y = global_position.y
	var dir := (target - global_position)
	dir.y = 0.0
	# Приём завершён, когда мяч у нас — вернёт менеджер через end_receiving(); тут просто бежим.
	_move_or_wander(dir.normalized(), delta)
```

- [ ] **Step 4: Trigger RECEIVING from the pass firing**

In `match_manager._fire_pass` (Task 12 Step 4), after setting `controlled_player = receiver`, tell the OTHER receiving mate... actually the human takes the receiver; the AI partner only needs RECEIVING when it is NOT the controlled player. Add, right after `if receiver != null:` block in `_fire_pass`:

```gdscript
	if receiver != null and receiver != controlled_player and receiver.has_method(&"begin_receiving"):
		receiver.begin_receiving(launch_vel, params.extra_lead)
```

(When the human controls the receiver, receive-assist in Task 16 handles it instead.)

- [ ] **Step 5: Reset role on pickup**

In `match_manager._handle_dribbling` (line ~590), when a `team_1` node becomes dribbler, clear its receiving role. After `ball.set_dribbler(p)` in that function, add:

```gdscript
			if p.has_method(&"end_receiving"):
				p.end_receiving()
```

- [ ] **Step 6: Verify headless load + manual**

Run the headless `--quit` command. Run the game: the AI teammate now positions AHEAD (toward the opponent goal, −Z) when you dribble, and actively runs to meet a pass aimed at it.

- [ ] **Step 7: Commit**

```bash
git add scripts/ai/teammate_ai.gd scripts/match/match_manager.gd
git commit -m "feat(pass): teammate Role enum, receiving, fix support direction sign"
```

---

### Task 15: Receive-assist for the human receiver

**Files:**
- Modify: `scripts/match/match_manager.gd` — `_handle_player_input` movement block (from Task 10), add receive-phase fields + helper

**Interfaces:**
- Consumes: `PASS_RECEIVE_*` constants.
- Produces: receive-assist that snaps/steers the human receiver toward the incoming ball; fields `_receive_active`, `_receiver`, `_receive_timer`.

- [ ] **Step 1: Add receive-phase fields**

Add near the pass fields:

```gdscript
var _receive_active: bool = false
var _receiver: CharacterBody3D
var _receive_timer: float = 0.0
```

- [ ] **Step 2: Start the phase when the human is the receiver**

In `_fire_pass` (Task 12), after the `controlled_player = receiver` handoff block, add:

```gdscript
	if receiver != null and receiver == controlled_player:
		_receive_active = true
		_receiver = receiver
		_receive_timer = FootballConstants.PASS_RECEIVE_MAX_TIME
```

- [ ] **Step 3: Apply receive-assist to the human's movement**

In `_handle_player_input`, right AFTER computing `dir` (from Task 10 Step 1) and BEFORE `motor.set_move_intent(dir, sprint_scale)`, insert:

```gdscript
	if _receive_active and controlled_player == _receiver and is_instance_valid(ball):
		var db := (ball.global_position + ball.linear_velocity * FootballConstants.PASS_RECEIVE_PREDICT_WINDOW) - controlled_player.global_position
		db.y = 0.0
		var stick := dir
		if stick.length() < 0.1:
			dir = db.normalized()          # стик не трогают → бежим к мячу сами
		elif db.normalized().dot(stick.normalized()) > FootballConstants.PASS_RECEIVE_DOT_THRESHOLD:
			dir = db.normalized()          # примерно к мячу → защёлка точно на мяч
		# иначе (стик прочь) — оставляем dir = stick (осознанный dummy-run)
```

- [ ] **Step 4: Tick and end the phase**

In `_physics_process`, add near the other per-frame updates (e.g. after `_process_fall(delta)`):

```gdscript
	if _receive_active:
		_receive_timer -= delta
		var caught: bool = ball.has_method(&"set_dribbler") and ball.dribbler == _receiver
		if caught or _receive_timer <= 0.0 or _receiver != controlled_player or not is_instance_valid(_receiver):
			_receive_active = false
			_receiver = null
```

- [ ] **Step 5: Verify headless load + manual**

Run the headless `--quit` command. Run the game: pass to your other player; after the handoff, holding the stick ROUGHLY toward the ball makes the receiver run precisely onto it; releasing the stick auto-runs to the ball; steering hard away keeps manual control.

- [ ] **Step 6: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(pass): receive-assist snap/auto-run for the human receiver"
```

---

### Task 16: Give-and-go run (WALL pass)

**Files:**
- Modify: `scripts/ai/teammate_ai.gd` — give-and-go run behavior + timer
- Modify: `scripts/match/match_manager.gd` — trigger on WALL pass, clear cooldown, clear on fall

**Interfaces:**
- Produces: `teammate_ai.begin_give_and_go(receiver_pos: Vector3) -> void`; group `giving_run`; timer that reverts to `SUPPORT` after `PASS_WALL_WINDOW`.

- [ ] **Step 1: Add give-and-go state to teammate_ai**

Add fields + API:

```gdscript
var _gng_timer: float = 0.0
var _gng_lateral_sign: float = 1.0

## Отдавший «стенку» переходит в атакующий рывок (спринт вперёд-в-сторону от принимающего),
## предлагая себя под возврат в течение PASS_WALL_WINDOW секунд.
func begin_give_and_go(receiver_pos: Vector3) -> void:
	add_to_group("giving_run")
	_gng_timer = FootballConstants.PASS_WALL_WINDOW
	# сторона рывка — противоположная принимающему (разводим фланги)
	_gng_lateral_sign = -1.0 if receiver_pos.x >= global_position.x else 1.0
```

- [ ] **Step 2: Drive the run and time it out**

At the very top of `_physics_process`, after the `fallen` early-return, add give-and-go handling:

```gdscript
	if is_in_group("giving_run"):
		_gng_timer -= delta
		var got_ball := ball.has_method(&"set_dribbler") and ball.dribbler == self
		if _gng_timer <= 0.0 or got_ball or _role == Role.RECEIVING:
			remove_from_group("giving_run")
			_role = Role.SUPPORT
		else:
			var attack := Vector3(0, 0, -1)  # атакуем к −Z
			var target := global_position + attack * FootballConstants.PASS_WALL_RUN_FORWARD \
				+ Vector3(_gng_lateral_sign * FootballConstants.PASS_WALL_RUN_LATERAL, 0, 0)
			target.x = clamp(target.x, -field_width + 4, field_width - 4)
			target.z = clamp(target.z, -field_length + 4, field_length - 4)
			var dir := (target - global_position)
			dir.y = 0.0
			var m := _motor()
			if m != null:
				# Единственное исключение из «ИИ не спринтует» — телеграфируемый рывок.
				m.set_move_intent(dir.normalized(), FootballConstants.LOCO_SPRINT_SPEED / FootballConstants.LOCO_TOP_SPEED)
			return
```

Add `var field_width: float = FootballConstants.HALF_FIELD_WIDTH` to teammate_ai's fields if not already present (it has `field_length` already; check line ~9 — it defines both; if only one, add the missing).

- [ ] **Step 3: Trigger from a WALL pass**

In `match_manager._fire_pass`, after the receiver handoff, add:

```gdscript
	if params.is_wall and is_instance_valid(player) and player.has_method(&"begin_give_and_go"):
		if receiver != null:
			player.begin_give_and_go(receiver.global_position)
		if ball.has_method(&"clear_last_kicker"):
			# позволяем отдавшему принять возврат раньше, чем истечёт _kick_cooldown_msec
			await get_tree().create_timer(0.4).timeout
			if is_instance_valid(ball):
				ball.clear_last_kicker()
```

(The `await` defers `clear_last_kicker` so the passer becomes re-eligible to receive shortly after the give-and-go, bypassing `_kick_cooldown_msec = 1500`.)

- [ ] **Step 4: Clear the run on a fall**

In `match_manager._finish_fall` (search for the function that removes the `fallen` group at the end of the fall chain), add after the fallen group is removed:

```gdscript
	if _fall_player and _fall_player.is_in_group("giving_run"):
		_fall_player.remove_from_group("giving_run")
```

- [ ] **Step 5: Verify headless load + manual**

Run the headless `--quit` command. Run the game: `Q+X` / `LB+A` — control goes to the receiver, and the passer sprints forward-and-wide for ~3s; pass it straight back and the passer can receive it (no 1.5s cooldown block). If the passer doesn't get it back in 3s, it returns to normal support.

- [ ] **Step 6: Commit**

```bash
git add scripts/ai/teammate_ai.gd scripts/match/match_manager.gd
git commit -m "feat(pass): give-and-go run (sprint, 3s window, cooldown bypass)"
```

---

### Task 17: Honest active interception by the opponent

**Files:**
- Modify: `scripts/match/match_manager.gd` — detect corridor at pass time, flag the opponent
- Modify: `scripts/ai/simple_ai.gd` — react to an incoming pass with delay + chance, chase the intercept point

**Interfaces:**
- Produces: `simple_ai.begin_intercept(point: Vector3) -> void`; opponent runs to `point` after a reaction delay, with a miss chance.

- [ ] **Step 1: Add intercept API to simple_ai**

Add fields + API to `simple_ai.gd`:

```gdscript
var _intercepting: bool = false
var _intercept_point: Vector3 = Vector3.ZERO
var _intercept_react_left: float = 0.0

## Менеджер зовёт это, если геометрия коридора дала перехват (с учётом шанса «зевка»).
## Соперник реагирует не мгновенно (задержка), затем бежит к точке пересечения.
func begin_intercept(point: Vector3) -> void:
	_intercepting = true
	_intercept_point = point
	_intercept_react_left = FootballConstants.AI_INTERCEPT_REACT
```

- [ ] **Step 2: Drive the intercept run**

At the top of `_physics_process` in `simple_ai.gd`, after the `fallen` and `wants_to_tackle` early-returns, add:

```gdscript
	if _intercepting:
		_intercept_react_left -= delta
		if _intercept_react_left > 0.0:
			return  # задержка реакции — фора игроку
		var caught := ball.has_method(&"set_dribbler") and ball.dribbler == self
		var arrived := global_position.distance_to(_intercept_point) < 1.0
		if caught or arrived:
			_intercepting = false
		else:
			var dir := (_intercept_point - global_position)
			dir.y = 0.0
			var m := _motor()
			if m != null:
				m.set_move_intent(dir.normalized(), _base_scale())
			return
```

- [ ] **Step 3: Run corridor detection at pass time**

In `match_manager._fire_pass`, after `launch_vel` is computed and before the commit-action block, add:

```gdscript
	_maybe_flag_interceptor(from, aim_point, launch_vel)
```

Add the method:

```gdscript
## Геометрия решает «можно ли перехватить»; шанс решает, среагирует ли соперник (не читерски-
## идеально). Если да — соперник бежит к точке пересечения (визуальный, честный перехват).
func _maybe_flag_interceptor(from: Vector3, to: Vector3, launch_vel: Vector3) -> void:
	var ball_speed := Vector3(launch_vel.x, 0.0, launch_vel.z).length()
	var opps := _team_arrays(&"team_2", null)
	var opp_pos: PackedVector3Array = opps["pos"]
	var opp_nodes: Array = opps["nodes"]
	var best_time := INF
	var best_i := -1
	for i in range(opp_pos.size()):
		var t := PassSystem.interception_time(from, to, ball_speed, opp_pos[i],
			FootballConstants.AI_SPEED, FootballConstants.PASS_CORRIDOR_HALF_WIDTH, FootballConstants.PASS_CORRIDOR_SPREAD)
		if t < best_time:
			best_time = t
			best_i = i
	if best_i < 0:
		return
	if _pass_rng.randf() > FootballConstants.AI_INTERCEPT_CHANCE:
		return  # соперник «зевнул»
	var opp: Node3D = opp_nodes[best_i]
	if opp.has_method(&"begin_intercept"):
		var point := from + Vector3(launch_vel.x, 0.0, launch_vel.z).normalized() * (best_time * ball_speed)
		opp.begin_intercept(point)
```

- [ ] **Step 4: Verify headless load + manual**

Run the headless `--quit` command. Run the game: pass across an opponent standing in the lane — sometimes the opponent breaks toward the ball (after a brief reaction beat) and picks it off; sometimes it lets it through (miss chance). Passing around the opponent completes reliably. Tune `PASS_CORRIDOR_*`, `AI_INTERCEPT_*` for fairness.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_manager.gd scripts/ai/simple_ai.gd
git commit -m "feat(pass): honest active interception (corridor + reaction + chance)"
```

---

### Task 18: Telegraph the auto-selected target during charge

**Files:**
- Modify: `scripts/match/match_manager.gd` — a second indicator, updated while a pass is charging

**Interfaces:**
- Consumes: `PassSystem.select_target`, `_team_arrays`.
- Produces: `_target_indicator` (a `MeshInstance3D`) shown over the current auto-target while a pass charges.

- [ ] **Step 1: Create the target indicator**

Add a setup method (mirror `_setup_controlled_indicator`, different color) and call it from `_ready()`:

```gdscript
func _setup_target_indicator() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.2
	mesh.height = 0.4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.2)  # жёлтый — цель паса
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	_target_indicator = mi
```

Add the field `var _target_indicator: MeshInstance3D` and, in `_ready()`, call `_setup_target_indicator()`.

- [ ] **Step 2: Update it while a pass charges**

In `_process`, after the charge block, add:

```gdscript
	var show_target := _is_charging() and _charge_action != ChargeAction.SHOT and _charge_player == controlled_player
	if show_target:
		var mates := _team_arrays(&"team_1", _charge_player)
		var mate_pos: PackedVector3Array = mates["pos"]
		var mate_vel: PackedVector3Array = mates["vel"]
		var mate_nodes: Array = mates["nodes"]
		var aim := ball.get_dribble_direction()
		var idx := PassSystem.select_target(_charge_player.global_position, aim, mate_pos, mate_vel,
			FootballConstants.PASS_LEAD_GAIN, FootballConstants.PASS_DOT_BIAS, FootballConstants.PASS_MAX_RANGE)
		if idx >= 0:
			var tgt: Node3D = mate_nodes[idx]
			_target_indicator.global_position = tgt.global_position + Vector3(0, 2.6, 0)
			_target_indicator.visible = true
		else:
			_target_indicator.visible = false
	else:
		_target_indicator.visible = false
```

- [ ] **Step 3: Verify headless load + manual**

Run the headless `--quit` command. Run the game: hold a pass button — a yellow marker appears over the auto-selected teammate and jumps between teammates as you swing the stick; releasing passes to the marked one.

- [ ] **Step 4: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(pass): telegraph auto-target with a marker during charge"
```

---

### Task 19: Full-run verification pass + docs

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md` (document the pass system, controls, `PassSystem`, new constants)

**Interfaces:** none (documentation + final verification).

- [ ] **Step 1: Run the math test suite**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_pass_system_math.gd"`
Expected: `CHECK PASS`, exit 0.

- [ ] **Step 2: Full manual playthrough checklist**

Run the game and confirm, ticking each: short pass, through pass (leads runner), lob (arcs), through-air, give-and-go (passer sprints + return), receive-assist (stick-hint auto-run), interception (opponent sometimes picks off lane passes), telegraph marker, gamepad parity (stick move, analog sprint, all face buttons + LB combos), context swap (Q/LB switches only on defense). Tune `FootballConstants.PASS_*` / `AI_INTERCEPT_*` as needed and commit tuning separately.

- [ ] **Step 3: Update docs**

In `CLAUDE.md` add a "Passing" section: control table, `PassSystem` (pure static, headless-tested via `check_pass_system_math.gd`), `PassParams`, `ChargeAction`, `ball.launch()`, receive-assist, give-and-go (`giving_run` group, the one AI-sprint exception), honest interception, `PASS_*`/`AI_INTERCEPT_*` constants, and the input remap (arrows/stick move, context-sensitive Q/LB). Mirror the essentials in `AGENTS.md`.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "docs: document the pass system, controls, and PassSystem"
```

---

## Self-Review

**Spec coverage:** control remap + gamepad (Tasks 9–10), five pass types (12–13), charge bar (11), auto-aim target (4, 12), lead/through (5, 12), lob ballistics (6, 12), hybrid success = corridor + scatter (7, 8, 17), receive-assist (15), teammate receiving (14), give-and-go (16), honest interception (17), telegraph (18), `ball.launch` + gravity + restitution (2, 12), constants (1), teammate direction bug (14), headless tests (4–8), docs (19). All spec sections map to a task.

**Intentional deviations (flagged):** `PassSolution`/`resolve_pass` omitted — orchestrator composes helpers (YAGNI, one opponent). `PassParams` built by `match_manager._pass_params`, not a constant-reading factory — avoids autoload access from `RefCounted` and keeps the headless test autoload-free. `interception_time` takes `pass_to` (not `pass_vel`) for a cleaner length; documented in Task 7.

**Type consistency:** `PassSystem` signatures are defined once (Tasks 4–8) and consumed with matching argument types in `_fire_pass`/`_maybe_flag_interceptor` (Tasks 12, 17). `PassParams` fields (`power`, `peak_height`, `extra_lead`, `is_air`, `is_wall`) are set in `_pass_params` (12) and read in `_fire_pass` (12). `ChargeAction` values are defined in Task 11 and dispatched in Tasks 11–12. `begin_receiving`/`end_receiving` (14), `begin_give_and_go` (16), `begin_intercept` (17) names match between caller (`match_manager`) and callee (`teammate_ai`/`simple_ai`).

**Known integration caveats for the implementer:** several edits target a ~1000-line file by function name + approximate line — re-read the anchor before editing (line numbers drift as tasks land). The `_action_power < 0.0` marker distinguishes launch-passes from kicks in `_on_action_contact`; keep it consistent. `_action_player` is a single match-wide field — a very fast give-and-go return could be swallowed by an in-flight action; verify live (Task 16) and, if it bites, snap `_action_player = null` earlier in `_on_action_finished`.

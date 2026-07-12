# Объёмные ворота с физичной сеткой — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить плоские ворота на объёмный box-каркас с процедурной сеткой, которая физично колышется (Verlet spring-mass) при голе; мяч влетает, гаснет в сетке, 5 секунд празднования, затем сброс.

**Architecture:** Чистая математика симуляции (генерация решётки + шаг Verlet) вынесена в `NetSim` (`class_name NetSim extends Object`, статические функции, не читает `FootballConstants`) и покрыта headless-тестом — как `PassSystem`/`PlayerMotor`. Компонент `GoalNet` (extends MeshInstance3D) строит сетку через `NetSim`, симулирует и рендерит линии через `ImmediateMesh`. Каркас, коллайдеры-стопперы и поток гола добавляются в `match_manager.gd`.

**Tech Stack:** Godot 4.7, GDScript. Тесты — headless-скрипты `extends SceneTree`, печатают `CHECK PASS`/`CHECK FAIL`, exit 0/1.

## Global Constraints

- **Godot 4.7 / GDScript**, только Windows. Типизированный GDScript (как в существующих файлах).
- **Ответ всегда на русском** (пользовательское правило); код/идентификаторы — без изменений.
- **`NetSim` — чистые статические функции, НЕ читает `FootballConstants`** (вся тюнинговка приходит параметрами), иначе headless-тест сломается. Аналог `PassSystem`.
- **InputMap правится только в `_setup_inputs()`** — эта фича его не трогает.
- **Координаты (см. CLAUDE.md):** Z — длина (105 м), X — ширина (68 м), ворота на Z = ±52.5. Home (Z=−52.5) → сетка уходит в −Z; Away (Z=+52.5) → в +Z. Граничная стена на |Z|=56.5 (места под 1.5 м глубины хватает).
- **Валидация headless — ДВЕ команды** (ловят разное; см. CLAUDE.md):
  - menu-load: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
  - match-scene: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
  - **Известный baseline второй команды** (не ждать нуля ошибок, диффать против него): ~33× `Condition "!is_inside_tree()" is true`, ~6× transition-duplicate, ~3× `states.has(p_name)` (дубликат kick/pass в `PlayerVisual`), ~1× `Cannot get class 'WorldEnvironment3D'`.
- **Запуск check-скрипта:** `& "<godot exe>" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/<name>.gd"`.
- **Feel/визуал headless не проверяется** — колыхание сетки и стоп мяча проверяются только ручным прогоном.

---

## File Structure

**Новые:**
- `scripts/match/net_sim.gd` (`class_name NetSim`) — чистая математика: `build_box_net`, `integrate` + приватные хелперы.
- `scripts/match/goal_net.gd` (`extends MeshInstance3D`) — компонент: инициализация из `FootballConstants`, симуляция, рендер `ImmediateMesh`, `start_sim`/`stop_sim`.
- `tests/check_net_sim.gd` — headless-тест `NetSim`.

**Правки:**
- `scripts/data/football_constants.gd` — новая секция `NET_*` (Task 3, step 1).
- `scripts/match/match_manager.gd` — `_setup_goals()` (задний каркас, коллайдеры, спавн `GoalNet`), поток гола (`_celebrating` + таймер), новые хелперы.

---

## Task 1: `NetSim.build_box_net` — процедурная топология сетки (чистая)

**Files:**
- Create: `scripts/match/net_sim.gd`
- Test: `tests/check_net_sim.gd`

**Interfaces:**
- Produces: `NetSim.build_box_net(width: float, height: float, depth: float, w_div: int, h_div: int, d_div: int) -> Dictionary`. Возвращает словарь с ключами: `pos`/`rest`/`prev`/`normal` (`PackedVector3Array`), `pinned` (`PackedByteArray`, 1 = закреплён на каркасе), `edges` (`PackedInt32Array`, пары индексов), `rest_len` (`PackedFloat32Array`, по ребру). 4 независимые панели (задняя, верх, левая, правая; низ открыт); граница каждой панели (внешнее кольцо узлов) закреплена (совпадает с прутом каркаса), интерьер свободен.

- [ ] **Step 1: Написать провальный тест топологии**

Создать `tests/check_net_sim.gd`:

```gdscript
extends SceneTree

const NetSim = preload("res://scripts/match/net_sim.gd")

var _ok := true

func _init() -> void:
	_test_topology()
	if _ok:
		print("CHECK PASS")
		quit(0)
	else:
		print("CHECK FAIL")
		quit(1)

func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: ", msg)
	else:
		_ok = false
		print("  FAIL: ", msg)

func _test_topology() -> void:
	var net := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	# узлы: back (5*4=20) + top (5*3=15) + left (3*4=12) + right (3*4=12) = 59
	_expect(net["pos"].size() == 59, "node count == 59 (got %d)" % net["pos"].size())
	_expect(net["rest"].size() == 59, "rest parallel to pos")
	_expect(net["prev"].size() == 59, "prev parallel to pos")
	_expect(net["normal"].size() == 59, "normal parallel to pos")
	_expect(net["pinned"].size() == 59, "pinned parallel to pos")
	# свободные (интерьерные) узлы: sum (u_div-1)*(v_div-1) = back 3*2 + top 3*1 + left 1*2 + right 1*2 = 13
	var free := 0
	for v in net["pinned"]:
		if v == 0:
			free += 1
	_expect(free == 13, "free interior nodes == 13 (got %d)" % free)
	# rest_len совпадает с реальной длиной ребра
	var e := net["edges"].size() / 2
	_expect(e == net["rest_len"].size(), "one rest_len per edge")
	var bad := 0
	for k in range(e):
		var a: int = net["edges"][k * 2]
		var b: int = net["edges"][k * 2 + 1]
		if absf(net["pos"][a].distance_to(net["pos"][b]) - net["rest_len"][k]) > 0.0001:
			bad += 1
	_expect(bad == 0, "rest_len == actual edge length")
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_net_sim.gd"`
Expected: FAIL / ошибка «Could not load script `net_sim.gd`» или `build_box_net` не найдена (файл ещё не создан).

- [ ] **Step 3: Реализовать `build_box_net` и хелперы**

Создать `scripts/match/net_sim.gd`:

```gdscript
class_name NetSim
extends Object

# Строит объёмную сетку ворот из 4 независимых панелей (задняя, верх, левая,
# правая; низ открыт). Каждая панель — прямоугольная решётка; её внешнее кольцо
# узлов закреплено (лежит на пруте каркаса), интерьер свободен и колышется.
# Чистая функция: НЕ читает FootballConstants.
static func build_box_net(width: float, height: float, depth: float,
		w_div: int, h_div: int, d_div: int) -> Dictionary:
	var net := {
		"pos": PackedVector3Array(),
		"rest": PackedVector3Array(),
		"prev": PackedVector3Array(),
		"normal": PackedVector3Array(),
		"pinned": PackedByteArray(),
		"edges": PackedInt32Array(),
		"rest_len": PackedFloat32Array(),
	}
	var hw := width * 0.5
	# Задняя панель: плоскость z=depth, u=x по ширине, v=y по высоте, нормаль +z.
	_add_panel(net, w_div, h_div, Vector3(0, 0, 1),
		func(su: float, sv: float) -> Vector3:
			return Vector3(lerpf(-hw, hw, su), lerpf(0.0, height, sv), depth))
	# Верхняя панель: плоскость y=height, u=x по ширине, v=z по глубине, нормаль +y.
	_add_panel(net, w_div, d_div, Vector3(0, 1, 0),
		func(su: float, sv: float) -> Vector3:
			return Vector3(lerpf(-hw, hw, su), height, lerpf(0.0, depth, sv)))
	# Левая панель: плоскость x=-hw, u=z по глубине, v=y по высоте, нормаль -x.
	_add_panel(net, d_div, h_div, Vector3(-1, 0, 0),
		func(su: float, sv: float) -> Vector3:
			return Vector3(-hw, lerpf(0.0, height, sv), lerpf(0.0, depth, su)))
	# Правая панель: плоскость x=hw, u=z по глубине, v=y по высоте, нормаль +x.
	_add_panel(net, d_div, h_div, Vector3(1, 0, 0),
		func(su: float, sv: float) -> Vector3:
			return Vector3(hw, lerpf(0.0, height, sv), lerpf(0.0, depth, su)))
	return net

# Добавляет одну панель-решётку (u_div×v_div ячеек) в net. point(su,sv) даёт
# позицию узла по нормализованным координатам su,sv ∈ [0,1]. Узлы на границе
# решётки закрепляются (pinned=1).
static func _add_panel(net: Dictionary, u_div: int, v_div: int, normal: Vector3,
		point: Callable) -> void:
	var base: int = net["pos"].size()
	var cols := u_div + 1
	var rows := v_div + 1
	for j in range(rows):
		for i in range(cols):
			var p: Vector3 = point.call(float(i) / float(u_div), float(j) / float(v_div))
			net["pos"].append(p)
			net["rest"].append(p)
			net["prev"].append(p)
			net["normal"].append(normal)
			var on_edge := (i == 0 or i == u_div or j == 0 or j == v_div)
			net["pinned"].append(1 if on_edge else 0)
	# Структурные пружины: к правому и верхнему соседу.
	for j in range(rows):
		for i in range(cols):
			var idx := base + j * cols + i
			if i < cols - 1:
				_add_edge(net, idx, idx + 1)
			if j < rows - 1:
				_add_edge(net, idx, idx + cols)

static func _add_edge(net: Dictionary, a: int, b: int) -> void:
	net["edges"].append(a)
	net["edges"].append(b)
	net["rest_len"].append(net["pos"][a].distance_to(net["pos"][b]))
```

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_net_sim.gd"`
Expected: печатает `CHECK PASS`, exit 0.

- [ ] **Step 5: Коммит**

```bash
git add scripts/match/net_sim.gd tests/check_net_sim.gd
git commit -m "feat(net): procedural box-net topology builder (NetSim.build_box_net)"
```

---

## Task 2: `NetSim.integrate` — шаг Verlet-симуляции (чистая)

**Files:**
- Modify: `scripts/match/net_sim.gd`
- Test: `tests/check_net_sim.gd`

**Interfaces:**
- Consumes: словарь от `build_box_net`.
- Produces: `NetSim.integrate(net: Dictionary, ball_pos: Vector3, ball_speed: float, p: Dictionary, dt: float) -> void`. Мутирует `net["pos"]`/`net["prev"]` на месте (один шаг Verlet). `ball_pos` — в ЛОКАЛЬНОМ пространстве сетки. `p` — словарь тюнинга с ключами `gravity`, `damping`, `stiffness`, `shape_return`, `ball_radius`, `ball_vel_scale`, `ball_force` (float). Закреплённые узлы (`pinned==1`) не двигаются. Толчок мяча — по близости к `ball_pos` вдоль `normal`, масштаб `1 + ball_speed*ball_vel_scale`.

- [ ] **Step 1: Добавить провальный тест интеграции**

Добавить в `tests/check_net_sim.gd` — вызвать `_test_integrate()` из `_init()` (перед печатью результата) и дописать методы:

```gdscript
# ...в _init() добавить строку после _test_topology():
#	_test_integrate()

func _first_free(net: Dictionary) -> int:
	for i in range(net["pinned"].size()):
		if net["pinned"][i] == 0:
			return i
	return -1

func _test_integrate() -> void:
	# Гравитация: свободный узел проседает ниже rest; закреплённые не двигаются.
	var net := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	var free := _first_free(net)
	_expect(free >= 0, "has a free node")
	var rest_y: float = net["rest"][free].y
	# Запомним позицию любого закреплённого узла.
	var pin_idx := 0
	var pin_before: Vector3 = net["pos"][pin_idx]
	_expect(net["pinned"][pin_idx] == 1, "node 0 is pinned (panel corner)")
	var gp := {
		"gravity": 50.0, "damping": 0.9, "stiffness": 0.0, "shape_return": 0.0,
		"ball_radius": 1.0, "ball_vel_scale": 0.0, "ball_force": 0.0,
	}
	for _s in range(30):
		NetSim.integrate(net, Vector3(0, -1000, 0), 0.0, gp, 0.1)
	_expect(net["pos"][free].y < rest_y - 0.01, "free node sags under gravity")
	_expect(net["pos"][pin_idx].distance_to(pin_before) < 0.0001, "pinned node did not move")

	# Толчок мяча: узел у мяча смещается наружу вдоль нормали (+z для задней панели).
	var net2 := NetSim.build_box_net(7.32, 2.44, 1.5, 4, 3, 2)
	var f2 := _first_free(net2)
	var rest_z: float = net2["rest"][f2].z
	# Мяч чуть «внутри» узла (со стороны поля), в радиусе влияния.
	var ball_local: Vector3 = net2["rest"][f2] - Vector3(0, 0, 0.1)
	var bp := {
		"gravity": 0.0, "damping": 0.9, "stiffness": 0.0, "shape_return": 0.0,
		"ball_radius": 1.0, "ball_vel_scale": 0.5, "ball_force": 100.0,
	}
	for _s2 in range(5):
		NetSim.integrate(net2, ball_local, 5.0, bp, 0.1)
	_expect(net2["pos"][f2].z > rest_z + 0.001, "ball pushes near node outward (+z)")
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_net_sim.gd"`
Expected: FAIL с ошибкой, что метод `integrate` не найден (ещё не реализован).

- [ ] **Step 3: Реализовать `integrate`**

Добавить в `scripts/match/net_sim.gd`:

```gdscript
# Один шаг полу-неявного Verlet. Мутирует net["pos"]/net["prev"]. Силы —
# ускорения; интегрируется как pos += (pos-prev)*damping + force*dt*dt.
static func integrate(net: Dictionary, ball_pos: Vector3, ball_speed: float,
		p: Dictionary, dt: float) -> void:
	var pos: PackedVector3Array = net["pos"]
	var prev: PackedVector3Array = net["prev"]
	var rest: PackedVector3Array = net["rest"]
	var pinned: PackedByteArray = net["pinned"]
	var normal: PackedVector3Array = net["normal"]
	var edges: PackedInt32Array = net["edges"]
	var rest_len: PackedFloat32Array = net["rest_len"]
	var n := pos.size()

	var gravity: float = p["gravity"]
	var damping: float = p["damping"]
	var stiffness: float = p["stiffness"]
	var shape_return: float = p["shape_return"]
	var radius: float = p["ball_radius"]
	var vel_scale: float = p["ball_vel_scale"]
	var ball_force: float = p["ball_force"]

	var force := PackedVector3Array()
	force.resize(n)
	# Узловые силы: гравитация, возврат к форме, толчок мяча.
	for i in range(n):
		if pinned[i] == 1:
			continue
		var f := Vector3(0.0, -gravity, 0.0)
		f += (rest[i] - pos[i]) * shape_return
		var d := pos[i] - ball_pos
		var prox := 1.0 - smoothstep(radius, radius * 1.15, d.length())
		if prox > 0.0:
			f += normal[i] * prox * (1.0 + ball_speed * vel_scale) * ball_force
		force[i] = f
	# Пружины по рёбрам (симметрично на оба конца).
	var e := edges.size() / 2
	for k in range(e):
		var a: int = edges[k * 2]
		var b: int = edges[k * 2 + 1]
		var sv := pos[a] - pos[b]
		var length := sv.length()
		if length > 0.00001:
			var sf := -sv * (stiffness * (1.0 - rest_len[k] / length))
			if pinned[a] == 0:
				force[a] = force[a] + sf
			if pinned[b] == 0:
				force[b] = force[b] - sf
	# Verlet-шаг.
	var dt2 := dt * dt
	for i in range(n):
		if pinned[i] == 1:
			prev[i] = pos[i]
			continue
		var temp := pos[i]
		pos[i] = pos[i] + (pos[i] - prev[i]) * damping + force[i] * dt2
		prev[i] = temp
	net["pos"] = pos
	net["prev"] = prev
```

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_net_sim.gd"`
Expected: печатает `CHECK PASS`, exit 0.

- [ ] **Step 5: Коммит**

```bash
git add scripts/match/net_sim.gd tests/check_net_sim.gd
git commit -m "feat(net): Verlet integration step (NetSim.integrate) + tests"
```

---

## Task 3: Константы `NET_*` + задний каркас ворот

**Files:**
- Modify: `scripts/data/football_constants.gd` (добавить секцию `NET_*`)
- Modify: `scripts/match/match_manager.gd` (`_setup_goals()` — задний каркас)

**Interfaces:**
- Produces: константы `FootballConstants.NET_DEPTH`, `NET_WIDTH_DIV`, `NET_HEIGHT_DIV`, `NET_DEPTH_DIV`, `NET_GRAVITY`, `NET_DAMPING`, `NET_SPRING_STIFFNESS`, `NET_SHAPE_RETURN`, `NET_SIM_STEP`, `NET_BALL_RADIUS`, `NET_BALL_VEL_SCALE`, `NET_BALL_FORCE`, `NET_BOUNCE`, `NET_FRICTION`, `NET_CELEBRATION_TIME`. Используются в Tasks 4–6.
- Задний каркас: 2 задние штанги + задняя перекладина на глубине `NET_DEPTH` за линией, знак глубины `ds = -1` (Home) / `+1` (Away).

- [ ] **Step 1: Добавить секцию констант**

В конец `scripts/data/football_constants.gd` добавить (значения — стартовые, тюнингуются вручную; `GOAL_DEPTH=2.0` выше — легаси, не используется геометрией, оставляем как есть):

```gdscript

# ═══════════════════════════════════════════
#  GOAL NET — объёмная сетка + Verlet-колыхание
# ═══════════════════════════════════════════

const NET_DEPTH := 1.5             # глубина коробки ворот за линией (м)
const NET_WIDTH_DIV := 8           # ячеек решётки по ширине ворот
const NET_HEIGHT_DIV := 6          # ячеек по высоте
const NET_DEPTH_DIV := 3           # ячеек по глубине

const NET_GRAVITY := 9.8           # ускорение провисания сетки (м/с²)
const NET_DAMPING := 0.98          # затухание скорости узла за шаг Verlet
const NET_SPRING_STIFFNESS := 400.0 # жёсткость структурных пружин
const NET_SHAPE_RETURN := 40.0     # тяга узла обратно к исходной форме
const NET_SIM_STEP := 0.016        # dt шага симуляции (с)
const NET_BALL_RADIUS := 0.6       # радиус влияния мяча на узлы (м)
const NET_BALL_VEL_SCALE := 0.3    # добавка к толчку от скорости мяча
const NET_BALL_FORCE := 120.0      # базовая сила толчка мяча по нормали

const NET_BOUNCE := 0.15           # упругость коллайдеров-стопперов сетки
const NET_FRICTION := 1.0          # трение стопперов (гасит мяч в сетке)
const NET_CELEBRATION_TIME := 5.0  # пауза празднования до сброса мяча (с)
```

- [ ] **Step 2: Добавить задний каркас в `_setup_goals()`**

В `scripts/match/match_manager.gd`, в цикле `for g in goal_positions:` (после блока с `crossbar`, перед созданием `area` — т.е. после строки `goal_group.add_child(crossbar)`), вставить:

```gdscript
		# Объёмный box: задний каркас на глубине NET_DEPTH за линией ворот.
		var ds: float = -1.0 if g.side == "Home" else 1.0
		var net_z: float = ds * FootballConstants.NET_DEPTH
		var post_left_back := _make_post(-3.66, 0, net_z)
		goal_group.add_child(post_left_back)
		var post_right_back := _make_post(3.66, 0, net_z)
		goal_group.add_child(post_right_back)
		var crossbar_back := _make_crossbar(0, 2.44, net_z)
		goal_group.add_child(crossbar_back)
```

Примечание: `_make_post(x, y, z)` игнорирует переданный `y` (внутри фиксирует `1.22`), `z` использует — задняя штанга встанет как передняя, но со смещением по глубине. `_make_crossbar(x, y, z)` использует `y` и `z` — задняя перекладина встанет на `y=2.44`, `z=net_z`.

- [ ] **Step 3: Валидация headless (обе команды)**

Run (menu-load): `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без новых ошибок парсинга.

Run (match-scene): `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: набор ошибок совпадает с baseline из Global Constraints (никаких новых категорий).

- [ ] **Step 4: Коммит**

```bash
git add scripts/data/football_constants.gd scripts/match/match_manager.gd
git commit -m "feat(goal): NET_* constants + volumetric back frame (posts + crossbar)"
```

---

## Task 4: Компонент `GoalNet` — генерация, симуляция, рендер

**Files:**
- Create: `scripts/match/goal_net.gd`
- Modify: `scripts/match/match_manager.gd` (`_setup_goals()` — спавн `GoalNet`; поле `_goal_nets`)

**Interfaces:**
- Consumes: `NetSim.build_box_net`, `NetSim.integrate`, константы `NET_*`.
- Produces: узел `GoalNet` (extends MeshInstance3D) с методами `initialize(ball_ref: RigidBody3D) -> void`, `start_sim() -> void`, `stop_sim() -> void`. Строит сетку в ЛОКАЛЬНОМ пространстве (устье при z=0, глубина в +z локально); ориентация под сторону задаётся `rotation.y` снаружи. `match_manager._goal_nets: Dictionary` хранит узлы по ключу стороны (`"Home"`/`"Away"`).

- [ ] **Step 1: Создать `scripts/match/goal_net.gd`**

```gdscript
extends MeshInstance3D
## Объёмная сетка ворот: процедурная решётка узлов-масс (NetSim), Verlet-колыхание
## при голе, рендер линиями через ImmediateMesh. Строится в локальном пространстве
## (устье при z=0, глубина уходит в локальный +z); ориентацию под сторону поля
## задаёт rotation.y снаружи (PI для Home, 0 для Away).

const NetSim = preload("res://scripts/match/net_sim.gd")

var ball: RigidBody3D
var _net: Dictionary
var _params: Dictionary
var _sim := false
var _im: ImmediateMesh
var _mat: StandardMaterial3D

func initialize(ball_ref: RigidBody3D) -> void:
	ball = ball_ref
	var C := FootballConstants
	_net = NetSim.build_box_net(C.GOAL_WIDTH, C.GOAL_HEIGHT, C.NET_DEPTH,
		C.NET_WIDTH_DIV, C.NET_HEIGHT_DIV, C.NET_DEPTH_DIV)
	_params = {
		"gravity": C.NET_GRAVITY,
		"damping": C.NET_DAMPING,
		"stiffness": C.NET_SPRING_STIFFNESS,
		"shape_return": C.NET_SHAPE_RETURN,
		"ball_radius": C.NET_BALL_RADIUS,
		"ball_vel_scale": C.NET_BALL_VEL_SCALE,
		"ball_force": C.NET_BALL_FORCE,
	}
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1, 1, 1, 0.55)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_im = ImmediateMesh.new()
	mesh = _im
	material_override = _mat
	set_physics_process(false)
	_redraw()

func start_sim() -> void:
	_sim = true
	set_physics_process(true)

func stop_sim() -> void:
	_sim = false
	set_physics_process(false)
	var rest: PackedVector3Array = _net["rest"]
	_net["pos"] = rest.duplicate()
	_net["prev"] = rest.duplicate()
	_redraw()

func _physics_process(_delta: float) -> void:
	if not _sim or ball == null or not is_instance_valid(ball):
		return
	var ball_local := to_local(ball.global_position)
	var ball_speed := ball.linear_velocity.length()
	NetSim.integrate(_net, ball_local, ball_speed, _params, FootballConstants.NET_SIM_STEP)
	_redraw()

func _redraw() -> void:
	var pos: PackedVector3Array = _net["pos"]
	var edges: PackedInt32Array = _net["edges"]
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	var e := edges.size() / 2
	for k in range(e):
		_im.surface_add_vertex(pos[edges[k * 2]])
		_im.surface_add_vertex(pos[edges[k * 2 + 1]])
	_im.surface_end()
```

- [ ] **Step 2: Объявить поле `_goal_nets` в `match_manager.gd`**

Рядом с другими полями состояния (например, после `var _controlled_marker` / `var _match_camera`, ~строка 20) добавить:

```gdscript
var _goal_nets: Dictionary = {}
```

- [ ] **Step 3: Спавнить `GoalNet` в `_setup_goals()`**

В цикле `for g in goal_positions:`, после блока заднего каркаса (Task 3, step 2), добавить:

```gdscript
		# Сетка-колыхание (компонент GoalNet) на этих воротах.
		var goal_net = preload("res://scripts/match/goal_net.gd").new()
		goal_net.name = "GoalNet"
		goal_group.add_child(goal_net)
		goal_net.rotation.y = PI if g.side == "Home" else 0.0
		goal_net.initialize(ball)
		_goal_nets[g.side] = goal_net
```

- [ ] **Step 4: Валидация headless (обе команды)**

Run (menu-load): `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без новых ошибок парсинга (`goal_net.gd` компилируется).

Run (match-scene): `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: набор ошибок совпадает с baseline (сетка строится и рисуется без падений; `_physics_process` выключен, пока нет гола).

- [ ] **Step 5: Коммит**

```bash
git add scripts/match/goal_net.gd scripts/match/match_manager.gd
git commit -m "feat(goal): GoalNet component (procedural net, Verlet sim, ImmediateMesh render)"
```

---

## Task 5: Коллайдеры-стопперы сетки (мяч тормозит и гаснет в объёме)

**Files:**
- Modify: `scripts/match/match_manager.gd` (`_setup_goals()` — коллайдеры; хелпер `_make_net_collider`)

**Interfaces:**
- Consumes: `NET_DEPTH`, `NET_BOUNCE`, `NET_FRICTION`, `GOAL_WIDTH`, `GOAL_HEIGHT`, `BOUNDARY_COLLISION_LAYER`.
- Produces: 4 `StaticBody3D` (задняя/верх/лево/право) на `BOUNDARY_COLLISION_LAYER` внутри `goal_group`, с `PhysicsMaterial` (низкий bounce, высокое трение). Мяч всегда маскирует этот слой (`ball.collision_mask = 1 | BOUNDARY_COLLISION_LAYER`), поэтому физически тормозит о сетку. Низ открыт (мяч оседает на газон, слой 1).

- [ ] **Step 1: Добавить хелпер `_make_net_collider`**

В `scripts/match/match_manager.gd` рядом с `_make_post`/`_make_crossbar` добавить:

```gdscript
func _make_net_collider(local_pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = FootballConstants.BOUNDARY_COLLISION_LAYER
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.bounce = FootballConstants.NET_BOUNCE
	pm.friction = FootballConstants.NET_FRICTION
	body.physics_material_override = pm
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = local_pos
	return body
```

- [ ] **Step 2: Добавить коллайдеры в `_setup_goals()`**

В цикле `for g in goal_positions:`, после спавна `GoalNet` (Task 4, step 3), добавить (использует `ds` из Task 3, объявленный выше в том же теле цикла):

```gdscript
		# Стопперы: мяч влетает в открытый перёд, тормозит о заднюю/боковые/верхнюю сетку.
		var w := FootballConstants.GOAL_WIDTH
		var h := FootballConstants.GOAL_HEIGHT
		var nd := FootballConstants.NET_DEPTH
		var t := 0.1
		goal_group.add_child(_make_net_collider(Vector3(0, h * 0.5, ds * nd), Vector3(w, h, t)))          # задняя
		goal_group.add_child(_make_net_collider(Vector3(0, h, ds * nd * 0.5), Vector3(w, t, nd)))          # верх
		goal_group.add_child(_make_net_collider(Vector3(-w * 0.5, h * 0.5, ds * nd * 0.5), Vector3(t, h, nd)))  # лево
		goal_group.add_child(_make_net_collider(Vector3(w * 0.5, h * 0.5, ds * nd * 0.5), Vector3(t, h, nd)))   # право
```

- [ ] **Step 3: Валидация headless (обе команды)**

Run (menu-load): `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без новых ошибок.

Run (match-scene): `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: набор ошибок совпадает с baseline.

- [ ] **Step 4: Коммит**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(goal): net collider walls so the ball stops inside the net volume"
```

---

## Task 6: Поток гола — 5с празднования + запуск/остановка колыхания

**Files:**
- Modify: `scripts/match/match_manager.gd` (обработчик `body_entered` в `_setup_goals()`; поле `_celebrating`; хелпер `_celebrate_then_reset`)

**Interfaces:**
- Consumes: `_goal_nets` (Task 4), `GoalNet.start_sim`/`stop_sim`, `NET_CELEBRATION_TIME`, существующий `_reset_ball()`.
- Produces: при пересечении линии — счёт++, запуск колыхания сетки этих ворот, таймер 5с, затем `_reset_ball()` + `stop_sim()`. Флаг `_celebrating` защищает от повторного `body_entered`, пока мяч в зоне. Игроки/камера не замораживаются.

- [ ] **Step 1: Объявить поле `_celebrating`**

Рядом с `_goal_nets` (Task 4, step 2) добавить:

```gdscript
var _celebrating: bool = false
```

- [ ] **Step 2: Заменить обработчик `body_entered`**

В `_setup_goals()` заменить существующий блок:

```gdscript
		area.body_entered.connect(func(body: Node):
			if body == ball:
				if g.side == "Home":
					away_score += 1
				else:
					home_score += 1
				score_label.text = "%d : %d" % [home_score, away_score]
				_reset_ball()
		)
```

на:

```gdscript
		area.body_entered.connect(func(body: Node):
			if body == ball and not _celebrating:
				_celebrating = true
				if g.side == "Home":
					away_score += 1
				else:
					home_score += 1
				score_label.text = "%d : %d" % [home_score, away_score]
				var net = _goal_nets.get(g.side)
				if net:
					net.start_sim()
				_celebrate_then_reset(net)
		)
```

- [ ] **Step 3: Добавить хелпер `_celebrate_then_reset`**

Рядом с `_reset_ball()` (~строка 1900) добавить:

```gdscript
## Пауза празднования: мяч гаснет в сетке (колыхание идёт), через
## NET_CELEBRATION_TIME сброс мяча и остановка симуляции. Не await-им игроков —
## по решению ничего не замораживаем. Не await-ит вызывающий (fire-and-forget).
func _celebrate_then_reset(net) -> void:
	await get_tree().create_timer(FootballConstants.NET_CELEBRATION_TIME).timeout
	_reset_ball()
	if net and is_instance_valid(net):
		net.stop_sim()
	_celebrating = false
```

- [ ] **Step 4: Валидация headless (обе команды)**

Run (menu-load): `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без новых ошибок.

Run (match-scene): `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
Expected: набор ошибок совпадает с baseline.

- [ ] **Step 5: Ручной прогон (визуальная проверка — обязательно)**

Запустить игру (тот же exe без `--headless`), забить в каждые ворота и проверить:
- мяч влетает в открытый перёд коробки и **тормозит/гаснет** в сетке (не пролетает до стены, не отскакивает как от кирпича);
- **сетка колышется** в момент удара и затухает;
- через ~5 с мяч и игроки сбрасываются в стартовые позиции, сетка возвращается к исходной форме;
- проверить **обе стороны** (Home и Away) — ориентация сетки и знак глубины верны с обеих сторон;
- при необходимости подстроить `NET_*` в `football_constants.gd` (жёсткость/затухание/сила толчка/bounce/трение) и повторить.

- [ ] **Step 6: Коммит**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(goal): 5s goal celebration with net wobble, then reset"
```

---

## Self-Review (заполнено автором плана)

**Покрытие спека:**
- Объёмный box-каркас → Task 3 (задний каркас) + существующий передний.
- Verlet spring-mass (= `Nettest.gd`), процедурно + чистый тест → Tasks 1, 2 (`NetSim`), Task 4 (`GoalNet`).
- Рендер линиями через `ImmediateMesh` → Task 4.
- Физический стоп мяча (коллайдеры граней) → Task 5.
- Поток гола: счёт при пересечении, старт симуляции, 5с, reset, ничего не замораживаем → Task 6.
- Секция констант `NET_*` → Task 3, step 1.
- Тесты: `tests/check_net_sim.gd` (Tasks 1–2), обе headless-команды (Tasks 3–6), ручной прогон (Task 6).
- Вне скоупа (idle-ветер, шейдер, per-node коллизия, реплей/тряска/звук, наклонная сетка) — не запланировано, как в спеке.

**Скан плейсхолдеров:** нет TBD/TODO; весь код приведён целиком.

**Согласованность типов/имён:** `build_box_net`/`integrate` — одинаковые сигнатуры в Tasks 1/2 и в `GoalNet` (Task 4). `_goal_nets` (Task 4) читается в Task 6. `ds` объявлен в Task 3 и используется в Tasks 4-упоминание/5 в том же теле цикла. `initialize`/`start_sim`/`stop_sim` совпадают между `goal_net.gd` и вызовами в `match_manager`. Ключи словаря `_params` совпадают с ключами, читаемыми в `integrate`.

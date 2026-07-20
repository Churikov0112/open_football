# Player Spawn Factory — Фаза 1 (фабрика + ростер) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить 7 копипаст-мест спавна игрока одной сценой + фабрикой + узлом-ростером `Team`, и перевести обращения по имени (`player_home`/`player_teammate`/`player_away`) на запросы к `Team`/группам — без изменения игрового поведения.

**Architecture:** Данные игрока (`PlayerConfig`) отделены от тела; единственный шов создания — `PlayerFactory.spawn(config, team)`, который инстанцирует `scenes/player.tscn`, красит, вешает слои/группы/роль, регистрирует в `Team`-узле (авторитетный ростер) и навешивает ИИ-скрипт через `set_script` (Фаза 1; компонентный мозг — Фаза 2). Группы Godot (`team_1`/`team_2` + `role_*`) остаются физическим индексом, `Team` — игровым источником истины.

**Tech Stack:** Godot 4.7, GDScript. Тесты — headless `SceneTree`-скрипты `tests/check_*.gd` (печатают `CHECK PASS`/`CHECK FAIL`, выходят 0/1) + два валидирующих headless-прогона.

## Global Constraints

- **Godot exe:** `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`
- **Repo:** `C:\Users\User\Desktop\projects\OpenFootball`
- **Запуск headless-теста (PowerShell):**
  `& "<exe>" --path "<repo>" --headless -s "res://tests/<name>.gd"`
  (в Git Bash — тот же вызов без `&`).
- **Регрессионная сетка** (после КАЖДОЙ задачи, меняющей рантайм-код — команды ниже все должны печатать `CHECK PASS` / завершаться без НОВЫХ ошибок относительно baseline из CLAUDE.md):
  1. `& "<exe>" --path "<repo>" --headless --quit` (парс всех `class_name`/autoload)
  2. `& "<exe>" --path "<repo>" --headless --quit-after 2 res://scenes/match.tscn` (грузит match.tscn — единственный, кто парсит match-only скрипты; сверять по КАТЕГОРИИ ошибки, не по счётчику — см. CLAUDE.md *Commands*)
  3. `& "<exe>" --path "<repo>" --headless -s "res://tests/check_free_kick_flow.gd"` → `CHECK PASS`
  4. `& "<exe>" --path "<repo>" --headless -s "res://tests/check_penalty_flow.gd"` → `CHECK PASS`
  5. `& "<exe>" --path "<repo>" --headless -s "res://tests/check_keeper_clear.gd"` → `CHECK PASS`
- **Регистрация нового `class_name`:** после создания файла с `class_name` прогнать один раз
  `& "<exe>" --path "<repo>" --headless --editor --quit` (иначе класс не попадёт в `global_script_class_cache.cfg` и другие скрипты его не увидят).
- **Стиль коммитов:** `feat(...)`/`refactor(...)`/`test(...)`/`docs(...)`, тело осмысленное, в конце
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Ветка:** `feat/corner` (текущая). НЕ мержить в master в рамках плана.
- **Поведение не меняется.** Это чистый рефактор: каждая задача оставляет игру запускаемой и регрессионную сетку зелёной. `.uid`-файлы Godot генерирует сам — не коммитить их (следуя текущей конвенции репо).

## File Structure

**Создаются:**
- `scripts/match/player_config.gd` — `class_name PlayerConfig extends RefCounted`: дата-холдер входа фабрики + статик `role_group`.
- `scripts/match/team.gd` — `class_name Team extends Node`: узел-ростер, игроки — дети; `add_player`/`remove_player`/`players`/`by_role`/`keeper`/`outfield`.
- `scripts/match/player_factory.gd` — `class_name PlayerFactory extends Object`: статик `spawn(config, team)`.
- `scenes/player.tscn` — `CharacterBody3D` (без скрипта) + дети `PlayerVisual` → `PlayerMotor` → `CollisionShape3D` (капсула).
- `tests/check_player_config.gd`, `tests/check_team_roster.gd`, `tests/check_player_factory.gd`.

**Модифицируются:**
- `scripts/match/match_manager.gd` — строит два `Team`-узла; спавны через фабрику; чтения по имени → запросы; удаление именованных переменных и `@onready $PlayerHome`.
- `scripts/match/free_kick_controller.gd` — `_make_wall_body`/`_make_mate_body` через фабрику.
- `scenes/match.tscn` — удаление узла `PlayerHome` (+ его `Mesh`/`CollisionShape`).
- `CLAUDE.md`, `AGENTS.md` — секция про фабрику/ростер.

---

### Task 1: `PlayerConfig` — дата-холдер входа фабрики

**Files:**
- Create: `scripts/match/player_config.gd`
- Test: `tests/check_player_config.gd`

**Interfaces:**
- Produces:
  - `class_name PlayerConfig extends RefCounted`
  - enums `Role { GK, DEF, MID, FWD }`, `Control { AI, HUMAN, REMOTE }`
  - поля: `team_group: StringName`, `role: int`, `kit_color: Color`, `spawn_pos: Vector3`, `control_mode: int`, `ai_script: Script`, `display_name: String`, `connect_action_signals: bool`, `locomotion_style: int`, `extra_fields: Dictionary`
  - `static func role_group(role: int) -> StringName`

- [ ] **Step 1: Write the failing test**

Create `tests/check_player_config.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var ok := true
	var c := PlayerConfig.new()
	# defaults
	if c.team_group != &"team_1": ok = false; print("CHECK FAIL: default team_group")
	if c.role != PlayerConfig.Role.MID: ok = false; print("CHECK FAIL: default role")
	if c.control_mode != PlayerConfig.Control.AI: ok = false; print("CHECK FAIL: default control")
	if not c.connect_action_signals: ok = false; print("CHECK FAIL: default connect_action_signals")
	if c.locomotion_style != -1: ok = false; print("CHECK FAIL: default locomotion_style")
	# role_group mapping
	if PlayerConfig.role_group(PlayerConfig.Role.GK) != &"role_gk": ok = false; print("CHECK FAIL: role_gk")
	if PlayerConfig.role_group(PlayerConfig.Role.DEF) != &"role_def": ok = false; print("CHECK FAIL: role_def")
	if PlayerConfig.role_group(PlayerConfig.Role.MID) != &"role_mid": ok = false; print("CHECK FAIL: role_mid")
	if PlayerConfig.role_group(PlayerConfig.Role.FWD) != &"role_fwd": ok = false; print("CHECK FAIL: role_fwd")
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& "<exe>" --path "<repo>" --headless -s "res://tests/check_player_config.gd"`
Expected: FAIL (parse error / `Identifier "PlayerConfig" not declared` — класс ещё не создан).

- [ ] **Step 3: Write the implementation**

Create `scripts/match/player_config.gd`:

```gdscript
class_name PlayerConfig
extends RefCounted
## Вход PlayerFactory.spawn(). Тонкий дата-холдер (эмбрион будущего SquadMember);
## FootballConstants НЕ читает — значения кладёт вызывающий.

enum Role { GK, DEF, MID, FWD }
enum Control { AI, HUMAN, REMOTE }   # REMOTE — заглушка на будущее

var team_group: StringName = &"team_1"
var role: int = Role.MID
var kit_color: Color = Color.WHITE
var spawn_pos: Vector3 = Vector3.ZERO
var control_mode: int = Control.AI
var ai_script: Script = null                 # мозг, когда control_mode == AI (Фаза 1: set_script)
var display_name: String = "Player"
var connect_action_signals: bool = true      # keeper self-connects → false
var locomotion_style: int = -1               # PlayerVisual.LOCO_STYLE_*; -1 = не трогать
var extra_fields: Dictionary = {}            # применяются к телу через set() после set_script

static func role_group(role_id: int) -> StringName:
	match role_id:
		Role.GK: return &"role_gk"
		Role.DEF: return &"role_def"
		Role.MID: return &"role_mid"
		Role.FWD: return &"role_fwd"
	return &"role_mid"
```

- [ ] **Step 4: Register the class**

Run: `& "<exe>" --path "<repo>" --headless --editor --quit`
Expected: завершается без ошибок; `PlayerConfig` попадает в кэш классов.

- [ ] **Step 5: Run test to verify it passes**

Run: `& "<exe>" --path "<repo>" --headless -s "res://tests/check_player_config.gd"`
Expected: `CHECK PASS`

- [ ] **Step 6: Commit**

```bash
git add scripts/match/player_config.gd tests/check_player_config.gd
git commit -m "feat(refactor): add PlayerConfig data holder for spawn factory

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `Team` — узел-ростер

**Files:**
- Create: `scripts/match/team.gd`
- Test: `tests/check_team_roster.gd`

**Interfaces:**
- Consumes: `PlayerConfig.role_group`, `PlayerConfig.Role`
- Produces:
  - `class_name Team extends Node`
  - поля: `team_group: StringName`, `attack_z_sign: float`, `kit_color: Color`, `id: StringName`, `manager: Node`, `ball: Node`
  - `add_player(body: CharacterBody3D, role: int) -> void` — reparent под себя, группы `team_group` + `role_*`, `set_meta("role", role)`, добавление в упорядоченный список (без дублей)
  - `remove_player(body: CharacterBody3D) -> void` — из списка + снятие групп
  - `players() -> Array` (упорядоченный, только валидные), `by_role(role) -> Array`, `keeper() -> CharacterBody3D` (или null), `outfield() -> Array`

- [ ] **Step 1: Write the failing test**

Create `tests/check_team_roster.gd`:

```gdscript
extends SceneTree
## Ростер Team: регистрация/группы/запросы, headless (тела — голые CharacterBody3D).

func _make_body(nm: String) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	b.name = nm
	return b

func _initialize() -> void:
	var ok := true
	var team := Team.new()
	team.team_group = &"team_1"
	root.add_child(team)

	var gk := _make_body("GK")
	var d1 := _make_body("D1")
	var f1 := _make_body("F1")
	team.add_player(gk, PlayerConfig.Role.GK)
	team.add_player(d1, PlayerConfig.Role.DEF)
	team.add_player(f1, PlayerConfig.Role.FWD)

	# reparent под Team
	if gk.get_parent() != team: ok = false; print("CHECK FAIL: gk not child of team")
	# группы: команда + роль
	if not gk.is_in_group("team_1"): ok = false; print("CHECK FAIL: gk missing team group")
	if not gk.is_in_group("role_gk"): ok = false; print("CHECK FAIL: gk missing role group")
	if not d1.is_in_group("role_def"): ok = false; print("CHECK FAIL: d1 missing role group")
	# упорядоченный players()
	var ps := team.players()
	if ps.size() != 3: ok = false; print("CHECK FAIL: players size ", ps.size())
	if ps[0] != gk or ps[1] != d1 or ps[2] != f1: ok = false; print("CHECK FAIL: players order")
	# by_role / keeper / outfield
	if team.by_role(PlayerConfig.Role.FWD).size() != 1 or team.by_role(PlayerConfig.Role.FWD)[0] != f1:
		ok = false; print("CHECK FAIL: by_role FWD")
	if team.keeper() != gk: ok = false; print("CHECK FAIL: keeper()")
	if team.outfield().size() != 2: ok = false; print("CHECK FAIL: outfield size")
	if team.outfield().has(gk): ok = false; print("CHECK FAIL: keeper in outfield")
	# no dup add
	team.add_player(gk, PlayerConfig.Role.GK)
	if team.players().size() != 3: ok = false; print("CHECK FAIL: dup add grew roster")
	# remove
	team.remove_player(d1)
	if team.players().size() != 2 or team.players().has(d1): ok = false; print("CHECK FAIL: remove_player")
	if d1.is_in_group("team_1"): ok = false; print("CHECK FAIL: remove kept team group")
	# invalid pruned
	f1.free()
	if team.players().size() != 1: ok = false; print("CHECK FAIL: freed body not pruned")

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& "<exe>" --path "<repo>" --headless -s "res://tests/check_team_roster.gd"`
Expected: FAIL (`Identifier "Team" not declared`).

- [ ] **Step 3: Write the implementation**

Create `scripts/match/team.gd`:

```gdscript
class_name Team
extends Node
## Узел-ростер: игроки — дети этого узла. Авторитетный игровой источник состава/роли/кита/
## стороны. Группы Godot (team_x + role_x) фабрика ставит параллельно как физический индекс.

var team_group: StringName = &"team_1"
var attack_z_sign: float = -1.0            # -1: атакуем −Z (наша); +1: соперник
var kit_color: Color = Color.WHITE
var id: StringName = &"home"
var manager: Node = null
var ball: Node = null

var _players: Array[CharacterBody3D] = []

func add_player(body: CharacterBody3D, role: int) -> void:
	if body.get_parent() != self:
		if body.get_parent() != null:
			body.get_parent().remove_child(body)
		add_child(body)
	body.add_to_group(team_group)
	body.add_to_group(PlayerConfig.role_group(role))
	body.set_meta(&"role", role)
	if not _players.has(body):
		_players.append(body)

func remove_player(body: CharacterBody3D) -> void:
	_players.erase(body)
	if is_instance_valid(body):
		body.remove_from_group(team_group)
		body.remove_from_group(PlayerConfig.role_group(int(body.get_meta(&"role", PlayerConfig.Role.MID))))

func players() -> Array:
	_players = _players.filter(func(b): return is_instance_valid(b))
	return _players

func by_role(role: int) -> Array:
	return players().filter(func(b): return int(b.get_meta(&"role", -1)) == role)

func keeper() -> CharacterBody3D:
	var gks := by_role(PlayerConfig.Role.GK)
	return gks[0] if gks.size() > 0 else null

func outfield() -> Array:
	return players().filter(func(b): return int(b.get_meta(&"role", -1)) != PlayerConfig.Role.GK)
```

- [ ] **Step 4: Register the class**

Run: `& "<exe>" --path "<repo>" --headless --editor --quit`
Expected: без ошибок.

- [ ] **Step 5: Run test to verify it passes**

Run: `& "<exe>" --path "<repo>" --headless -s "res://tests/check_team_roster.gd"`
Expected: `CHECK PASS`

- [ ] **Step 6: Commit**

```bash
git add scripts/match/team.gd tests/check_team_roster.gd
git commit -m "feat(refactor): add Team roster node (players as children, group + role index)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `scenes/player.tscn` — сцена тела игрока

**Files:**
- Create: `scenes/player.tscn`

**Interfaces:**
- Produces: `res://scenes/player.tscn` — корень `CharacterBody3D` (без скрипта); дети в порядке `PlayerVisual` (инстанс `player_visual.tscn`) → `PlayerMotor` → `CollisionShape3D` (`CapsuleShape3D` h=1.5 r=0.3, `position.y=0.25`).

- [ ] **Step 1: Create the scene file**

Create `scenes/player.tscn` (пути UID можно не указывать — Godot допишет `.uid` сам; используем `path`-ссылки):

```
[gd_scene load_steps=4 format=3]

[ext_resource type="PackedScene" path="res://scenes/player_visual.tscn" id="1"]
[ext_resource type="Script" path="res://scripts/player/player_motor.gd" id="2"]

[sub_resource type="CapsuleShape3D" id="1"]
height = 1.5
radius = 0.3

[node name="Player" type="CharacterBody3D"]

[node name="PlayerVisual" parent="." instance=ExtResource("1")]

[node name="PlayerMotor" type="Node" parent="."]
script = ExtResource("2")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.25, 0)
shape = SubResource("1")
```

Примечание: `PlayerMotor` — `Node` со скриптом `player_motor.gd` (в текущем коде он создаётся как `PlayerMotor.new()`, т.е. базовый тип узла берётся из `class_name PlayerMotor extends Node`; проверить первую строку `player_motor.gd` и при необходимости заменить `type="Node"` на фактический базовый тип). `PlayerVisual` инстанс — как в текущих сайтах (`preload("res://scenes/player_visual.tscn").instantiate()`).

- [ ] **Step 2: Import the scene**

Run: `& "<exe>" --path "<repo>" --headless --import`
Expected: импорт без ошибок; `scenes/player.tscn.uid` сгенерирован (не коммитить `.uid`).

- [ ] **Step 3: Verify it instantiates with correct child order (headless)**

Create a throwaway check inline OR verify in Task 4's factory test. Minimal manual verification:

Run: `& "<exe>" --path "<repo>" --headless --quit`
Expected: без НОВЫХ ошибок парса (сцена валидна; полноценная проверка порядка детей — в Task 4).

- [ ] **Step 4: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat(refactor): add player.tscn (body + visual/motor/collision, fixed child order)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `PlayerFactory.spawn` — единственный шов создания

**Files:**
- Create: `scripts/match/player_factory.gd`
- Test: `tests/check_player_factory.gd`

**Interfaces:**
- Consumes: `PlayerConfig`, `Team`, `FootballConstants.PLAYER_COLLISION_MASK`, `FootballConstants.BOUNDARY_COLLISION_LAYER`, `PlayerVisual`
- Produces:
  - `class_name PlayerFactory extends Object`
  - `static func spawn(config: PlayerConfig, team: Team) -> CharacterBody3D`
  - `static func find_visual(body: Node) -> PlayerVisual`

Последовательность внутри `spawn` (важно: 1:1 порядок текущих сайтов — kit до входа в дерево; `set_script` ПОСЛЕ добавления в дерево; поля — после `set_script`):
instantiate → name → layers → kit → `team.add_player` (вход в дерево, `_ready` детей) → position → (опц.) `locomotion_style` → (опц.) коннект `action_contact/finished` на `team.manager` → (если AI и `ai_script`) `set_script` + `set_physics_process(true)` → (если `team.ball`) `body.set("ball", ...)` → `set_meta("home_pos", spawn_pos)` → `extra_fields` через `set()`.

- [ ] **Step 1: Write the failing test**

Create `tests/check_player_factory.gd`:

```gdscript
extends SceneTree
## PlayerFactory.spawn: сборка тела через player.tscn, регистрация в Team, слои/группы/роль/
## порядок детей/home_pos. Без ai_script (control_mode AI + ai_script=null → set_script пропущен),
## без manager (connect_action_signals=false) — изоляция от полного матча.

func _initialize() -> void:
	var ok := true
	var team := Team.new()
	team.team_group = &"team_2"
	root.add_child(team)

	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_2"
	cfg.role = PlayerConfig.Role.FWD
	cfg.kit_color = Color(0.9, 0.1, 0.1)
	cfg.spawn_pos = Vector3(3, 0.5, -7)
	cfg.display_name = "TestFwd"
	cfg.connect_action_signals = false
	cfg.ai_script = null   # AI, но без скрипта → set_script пропускается

	var body := PlayerFactory.spawn(cfg, team)

	if body == null: ok = false; print("CHECK FAIL: null body")
	if body.name != "TestFwd": ok = false; print("CHECK FAIL: name")
	if body.get_parent() != team: ok = false; print("CHECK FAIL: not child of team")
	if not body.is_in_group("team_2"): ok = false; print("CHECK FAIL: team group")
	if not body.is_in_group("role_fwd"): ok = false; print("CHECK FAIL: role group")
	if int(body.get_meta(&"role", -1)) != PlayerConfig.Role.FWD: ok = false; print("CHECK FAIL: role meta")
	if body.collision_layer != FootballConstants.PLAYER_COLLISION_MASK: ok = false; print("CHECK FAIL: layer")
	var want_mask := FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
	if body.collision_mask != want_mask: ok = false; print("CHECK FAIL: mask")
	if body.global_position.distance_to(Vector3(3, 0.5, -7)) > 0.001: ok = false; print("CHECK FAIL: position")
	if body.get_meta(&"home_pos", Vector3.INF) != Vector3(3, 0.5, -7): ok = false; print("CHECK FAIL: home_pos meta")
	# порядок детей: PlayerVisual раньше PlayerMotor
	var kids := body.get_children()
	var vi := -1
	var mi := -1
	for i in kids.size():
		if kids[i] is PlayerVisual and vi < 0: vi = i
		if kids[i].get_class() == "CharacterBody3D": pass
		if kids[i] is PlayerMotor and mi < 0: mi = i
	if vi < 0: ok = false; print("CHECK FAIL: no PlayerVisual child")
	if mi < 0: ok = false; print("CHECK FAIL: no PlayerMotor child")
	if vi >= 0 and mi >= 0 and not (vi < mi): ok = false; print("CHECK FAIL: visual not before motor")
	# find_visual
	if PlayerFactory.find_visual(body) == null: ok = false; print("CHECK FAIL: find_visual")

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& "<exe>" --path "<repo>" --headless -s "res://tests/check_player_factory.gd"`
Expected: FAIL (`Identifier "PlayerFactory" not declared`).

- [ ] **Step 3: Write the implementation**

Create `scripts/match/player_factory.gd`:

```gdscript
class_name PlayerFactory
extends Object
## Единственный шов создания игрока. Инстанцирует player.tscn, красит, вешает слои/группы/роль,
## регистрирует в Team, навешивает ИИ-скрипт (Фаза 1: set_script). Повторяет 1:1 порядок операций
## прежних 7 копипаст-сайтов: kit до входа в дерево, set_script ПОСЛЕ add_child, поля после set_script.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

static func spawn(config: PlayerConfig, team: Team) -> CharacterBody3D:
	var body: CharacterBody3D = PLAYER_SCENE.instantiate()
	body.name = config.display_name
	body.collision_layer = FootballConstants.PLAYER_COLLISION_MASK
	body.collision_mask = FootballConstants.PLAYER_COLLISION_MASK | FootballConstants.BOUNDARY_COLLISION_LAYER
	var visual := find_visual(body)
	if visual != null:
		visual.apply_appearance({"kit_color": config.kit_color})
	# регистрация в ростер + группы (вход в дерево → _ready детей: motor находит visual-сиблинга)
	team.add_player(body, config.role)
	body.global_position = config.spawn_pos
	body.set_meta(&"home_pos", config.spawn_pos)
	if config.locomotion_style >= 0 and visual != null:
		visual.set_locomotion_style(config.locomotion_style)
	# сигналы удара/паса на менеджер (вратарь self-connect'ит → connect_action_signals=false)
	if config.connect_action_signals and team.manager != null and visual != null:
		visual.action_contact.connect(team.manager._on_action_contact.bind(body))
		visual.action_finished.connect(team.manager._on_action_finished.bind(body))
	# мозг (Фаза 1: set_script; Фаза 2 заменит компонентом)
	if config.control_mode == PlayerConfig.Control.AI and config.ai_script != null:
		body.set_script(config.ai_script)
		body.set_physics_process(true)
	# общая ссылка на мяч + пер-ролевые поля
	if team.ball != null:
		body.set(&"ball", team.ball)
	for k in config.extra_fields:
		body.set(k, config.extra_fields[k])
	return body

static func find_visual(body: Node) -> PlayerVisual:
	for c in body.get_children():
		if c is PlayerVisual:
			return c
	return null
```

- [ ] **Step 4: Register the class**

Run: `& "<exe>" --path "<repo>" --headless --editor --quit`
Expected: без ошибок.

- [ ] **Step 5: Run test to verify it passes**

Run: `& "<exe>" --path "<repo>" --headless -s "res://tests/check_player_factory.gd"`
Expected: `CHECK PASS`

- [ ] **Step 6: Commit**

```bash
git add scripts/match/player_factory.gd tests/check_player_factory.gd
git commit -m "feat(refactor): add PlayerFactory.spawn — single player construction seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Построить два `Team`-узла + спавн соперника через фабрику

**Files:**
- Modify: `scripts/match/match_manager.gd` (`_ready` ~104-142; `_setup_away_player` ~716-746)

**Interfaces:**
- Consumes: `PlayerFactory.spawn`, `Team`, `PlayerConfig`
- Produces: поля `var _team_home: Team`, `var _team_away: Team` на менеджере; `player_away` остаётся алиасом (= результат фабрики).

Стратегия: строим `Team`-узлы В начале `_ready` (до спавнов). `_setup_away_player` переписываем на фабрику, сохраняя `player_away = <body>` и текущие поля (`home_goal`) через `extra_fields`. Debug-болванки (`_spawn_wall_dummies`) пока НЕ трогаем (Task 7).

- [ ] **Step 1: Add Team fields and build nodes in `_ready`**

В `match_manager.gd` добавить поля рядом с `player_teammate` (после строки 12):

```gdscript
var _team_home: Team
var _team_away: Team
```

В `_ready`, СРАЗУ после `_setup_goals()` (строка 112) и ПЕРЕД `_setup_away_player()`, вставить:

```gdscript
	_team_home = Team.new()
	_team_home.name = "TeamHome"
	_team_home.team_group = &"team_1"
	_team_home.attack_z_sign = _attack_dir_z
	_team_home.kit_color = Color(0.1, 0.1, 0.9)
	_team_home.id = &"home"
	_team_home.manager = self
	_team_home.ball = ball
	add_child(_team_home)
	_team_away = Team.new()
	_team_away.name = "TeamAway"
	_team_away.team_group = &"team_2"
	_team_away.attack_z_sign = -_attack_dir_z
	_team_away.kit_color = Color(0.9, 0.1, 0.1)
	_team_away.id = &"away"
	_team_away.manager = self
	_team_away.ball = ball
	add_child(_team_away)
```

- [ ] **Step 2: Rewrite `_setup_away_player` to use the factory**

Заменить тело `_setup_away_player` (716-746) на:

```gdscript
func _setup_away_player() -> void:
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_2"
	cfg.role = PlayerConfig.Role.FWD
	cfg.kit_color = Color(0.9, 0.1, 0.1)
	cfg.spawn_pos = Vector3(20, 0.5, 0)
	cfg.display_name = "PlayerAway"
	cfg.ai_script = preload("res://scripts/ai/simple_ai.gd")
	cfg.connect_action_signals = true
	cfg.extra_fields = {
		&"home_goal": ($GoalHome/GoalArea if has_node("GoalHome/GoalArea") else null),
	}
	var new_player := PlayerFactory.spawn(cfg, _team_away)
	player_away = new_player
	# Тестовая стенка из бездействующих соперников — только при DEBUG_DISABLE_OPPONENT.
	if FootballConstants.DEBUG_DISABLE_OPPONENT:
		_spawn_wall_dummies()
```

- [ ] **Step 3: Run the regression grid**

Run all five Global-Constraints regression commands.
Expected: команды 3–5 → `CHECK PASS`; команды 1–2 без НОВЫХ категорий ошибок относительно baseline. Соперник (`PlayerAway`) в игре ведёт себя как раньше.

- [ ] **Step 4: Playtest sanity (manual, briefly)**

Запустить игру (exe без `--headless`), убедиться: соперник спавнится, красный, гоняется за мячом как раньше. (Если недоступно — полагаться на регрессионную сетку + следующий плейтест-гейт.)

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "refactor(spawn): build Team nodes; spawn away player via PlayerFactory

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Спавн игрока-человека через фабрику + удаление `$PlayerHome`

**Files:**
- Modify: `scripts/match/match_manager.gd` (заголовок ~4; `_ready` ~114-130; `_give_ai_to_player_home` ~555-562)
- Modify: `scenes/match.tscn` (удалить узел `PlayerHome`)

**Interfaces:**
- Consumes: `PlayerFactory.spawn`
- Produces: `var _human_player: CharacterBody3D` (удерживаемый синглтон «тело по умолчанию под человеком»); `player_home` остаётся алиасом (= `_human_player`) до Task 10.

Текущий `player_home` = `@onready $PlayerHome` (узел сцены). Меняем на `var` + спавн фабрикой. Скрипт — `teammate_ai` (как `_give_ai_to_player_home`): игрок-человек это team_1-тело с `teammate_ai`, которое уступает ручному вводу, когда `controlled_player == self`.

- [ ] **Step 1: Change the `player_home` declaration**

В `match_manager.gd` заменить строку 4:

```gdscript
@onready var player_home: CharacterBody3D = $PlayerHome
```

на:

```gdscript
var player_home: CharacterBody3D          # алиас на _human_player (удаляется в конце рефактора)
var _human_player: CharacterBody3D        # тело, которым по умолчанию управляет человек
```

- [ ] **Step 2: Replace the `player_home` setup block in `_ready`**

Удалить блок 114-126 (от `controlled_player = player_home` до строки `home_visual.action_finished.connect(...)`) и `_give_ai_to_player_home()` (строка 130). Заменить блок 114-126 на вызов нового хелпера ПОСЛЕ построения Team-узлов и ПОСЛЕ `_setup_away_player()` (порядок как сейчас — home ставился после away):

Вместо старого блока в `_ready` (там, где был `controlled_player = player_home` … `_setup_teammate()`), вставить:

```gdscript
	_setup_home_player()
	_setup_teammate()
	_setup_keeper()
	_setup_boundaries()
	_setup_controlled_indicator()
```

(строку `_give_ai_to_player_home()` убрать — её роль теперь в `_setup_home_player`; строку `_setup_controlled_indicator()` не дублировать, если она уже ниже — оставить один вызов на прежнем месте.)

Заменить тело `_give_ai_to_player_home` (555-562) на новый `_setup_home_player`:

```gdscript
func _setup_home_player() -> void:
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_1"
	cfg.role = PlayerConfig.Role.MID
	cfg.kit_color = Color(0.1, 0.1, 0.9)
	cfg.spawn_pos = Vector3(0, 0.5, 0)
	cfg.display_name = "PlayerHome"
	cfg.ai_script = preload("res://scripts/ai/teammate_ai.gd")
	cfg.connect_action_signals = true
	cfg.extra_fields = {
		&"speed": 7.0,
		&"teammate_home_goal": ($GoalAway/GoalArea if has_node("GoalAway/GoalArea") else null),
	}
	_human_player = PlayerFactory.spawn(cfg, _team_home)
	player_home = _human_player
	controlled_player = _human_player
	_human_player.set(&"controlled_player", controlled_player)
```

- [ ] **Step 3: Remove `$PlayerHome` from `scenes/match.tscn`**

Удалить узлы `PlayerHome` и его детей (`Mesh`, `CollisionShape`) — строки 86-94 в `scenes/match.tscn`. Также убрать теперь-неиспользуемые `SubResource(7)` (CapsuleShape3D) и `SubResource(8)`/`SubResource(9)` (материал/меш капсулы) **только если** на них больше нет ссылок (проверить grep по файлу; `SubResource(7)` использовался лишь `PlayerHome/CollisionShape`). Уменьшить `load_steps` в шапке соответственно.

- [ ] **Step 4: Reimport and run the regression grid**

Run: `& "<exe>" --path "<repo>" --headless --import`
Затем все пять регрессионных команд.
Expected: команды 3–5 → `CHECK PASS`; 1–2 без новых категорий ошибок. `PlayerAway`/keeper/teammate спавнятся; `PlayerHome` теперь фабричный.

- [ ] **Step 5: Playtest sanity**

Запустить игру: игрок-человек (синий) спавнится в центре, управляется стиком, авто-переключение/дриблинг/удар работают как раньше.

- [ ] **Step 6: Commit**

```bash
git add scripts/match/match_manager.gd scenes/match.tscn
git commit -m "refactor(spawn): spawn human player via factory; drop \$PlayerHome scene node

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Спавн тиммейта, вратаря и debug-болванок через фабрику

**Files:**
- Modify: `scripts/match/match_manager.gd` (`_setup_teammate` ~788-820; `_setup_keeper` ~668-713; `_make_dummy_opponent` ~763-785)

**Interfaces:**
- Consumes: `PlayerFactory.spawn`
- Produces: `player_teammate` остаётся алиасом; keeper (`_keeper`) — фабричный + keeper-специфичные `SaveArea`/`HoldPoint` создаются пост-спавн.

- [ ] **Step 1: Rewrite `_setup_teammate`**

Заменить тело `_setup_teammate` (788-820) на:

```gdscript
func _setup_teammate() -> void:
	if FootballConstants.DEBUG_DISABLE_TEAMMATE:
		return   # ВРЕМЕННО: тиммейт отключён (тест вратаря) → player_teammate остаётся null
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_1"
	cfg.role = PlayerConfig.Role.MID
	cfg.kit_color = Color(0.1, 0.1, 0.9)
	cfg.spawn_pos = Vector3(10, 0.5, 5)
	cfg.display_name = "PlayerTeammate"
	cfg.ai_script = preload("res://scripts/ai/teammate_ai.gd")
	cfg.connect_action_signals = true
	cfg.extra_fields = {
		&"controlled_player": controlled_player,
		&"teammate_home_goal": ($GoalAway/GoalArea if has_node("GoalAway/GoalArea") else null),
	}
	var new_player := PlayerFactory.spawn(cfg, _team_home)
	player_teammate = new_player
	# DEBUG: соперник опекает именно этого тиммейта (спавнится после соперника).
	if FootballConstants.DEBUG_MARK_TEAMMATE and player_away and is_instance_valid(player_away):
		player_away.set(&"mark_target", new_player)
```

- [ ] **Step 2: Rewrite `_make_dummy_opponent`**

Заменить тело `_make_dummy_opponent` (763-785) на:

```gdscript
func _make_dummy_opponent(pos: Vector3) -> void:
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_2"
	cfg.role = PlayerConfig.Role.DEF
	cfg.kit_color = Color(0.9, 0.1, 0.1)
	cfg.spawn_pos = pos
	cfg.display_name = "WallDummy"
	cfg.ai_script = preload("res://scripts/ai/simple_ai.gd")
	cfg.connect_action_signals = true
	cfg.extra_fields = {
		&"home_goal": ($GoalHome/GoalArea if has_node("GoalHome/GoalArea") else null),
	}
	PlayerFactory.spawn(cfg, _team_away)
```

(Раньше болванки НЕ коннектили `action_contact` — теперь коннектят; это строго корректнее и безопасно, болванки только debug-only при `DEBUG_DISABLE_OPPONENT`. Поведение стоящей болванки не меняется.)

- [ ] **Step 3: Rewrite `_setup_keeper` (factory for the common body, keeper extras post-spawn)**

Заменить тело `_setup_keeper` (668-713) на:

```gdscript
func _setup_keeper() -> void:
	var goal_line_z := -field_length   # ворота Home на -field_length
	var into_field := 1.0 if goal_line_z < 0.0 else -1.0
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_2"
	cfg.role = PlayerConfig.Role.GK
	cfg.kit_color = Color(0.15, 0.7, 0.15)   # вратарь — зелёный
	cfg.spawn_pos = Vector3(0, 0.5, goal_line_z + into_field * 0.5)
	cfg.display_name = "Keeper"
	cfg.ai_script = preload("res://scripts/ai/keeper_ai.gd")
	cfg.connect_action_signals = false        # keeper_ai сам коннектит visual.action_contact
	cfg.locomotion_style = PlayerVisual.LOCO_STYLE_KEEPER
	var k := PlayerFactory.spawn(cfg, _team_away)
	# --- keeper-специфичные узлы (не входят в общий player.tscn) ---
	var save_area := Area3D.new()
	save_area.name = "SaveArea"
	var sacol := CollisionShape3D.new()
	var sashape := SphereShape3D.new()
	sashape.radius = FootballConstants.KEEPER_REACH
	sacol.shape = sashape
	sacol.position = Vector3(0, FootballConstants.KEEPER_SAVE_AREA_Y, 0)
	save_area.add_child(sacol)
	save_area.collision_mask = 1   # только мяч (слой 1)
	k.add_child(save_area)
	var hold_point := Node3D.new()
	hold_point.name = "HoldPoint"
	hold_point.position = Vector3(0, 1.0, -0.45)
	k.add_child(hold_point)
	# keeper-поля (ball уже проставлен фабрикой)
	k.goal_line_z = goal_line_z
	k.save_area = save_area
	k.hold_point = hold_point
	k.manager = self
	_keeper = k
```

- [ ] **Step 4: Run the regression grid**

Run all five regression commands.
Expected: 3–5 → `CHECK PASS` (особенно `check_keeper_clear` — весь цикл вратаря); 1–2 без новых категорий ошибок.

- [ ] **Step 5: Playtest sanity**

Запустить игру: вратарь в воротах Home, сейвит/ловит/выбивает как раньше; тиммейт (если включён) позиционируется.

- [ ] **Step 6: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "refactor(spawn): route teammate, keeper, dummies through PlayerFactory

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Спавн тел стенки/целей штрафного через фабрику

**Files:**
- Modify: `scripts/match/free_kick_controller.gd` (`_make_wall_body` ~429-460; `_make_mate_body` ~551-579; `_convert_bodies` ~505-533 — сверить)

**Interfaces:**
- Consumes: `PlayerFactory.spawn`, `Team` (через `_manager._team_home`/`_team_away`)
- Produces: `_make_wall_body`/`_make_mate_body` возвращают тело фабрики; группа `fk_spawned` сохраняется как маркер временного тела.

Замечание: контроллер обращается к менеджеру как `_manager`. Team-узлы доступны как `_manager._team_home`/`_manager._team_away`. Wall — team_2, mate — team_1. Роль временная: wall → `DEF`, mate → `FWD` (для целей навеса) — на поведение не влияет (роль тут только тег). `connect_action_signals=true` (как в текущем коде, где сигналы коннектились вручную). Специфика стенки/цели (look_at, control-lock мотора, `fk_spawned`) — пост-спавн.

- [ ] **Step 1: Rewrite `_make_wall_body`**

Заменить тело `_make_wall_body` (429-460) на:

```gdscript
func _make_wall_body(pos: Vector3) -> CharacterBody3D:
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_2"
	cfg.role = PlayerConfig.Role.DEF
	cfg.kit_color = Color(0.9, 0.1, 0.1)
	cfg.spawn_pos = pos
	cfg.display_name = "WallMember"
	cfg.control_mode = PlayerConfig.Control.AI
	cfg.ai_script = null                 # пока без ИИ — стоит на месте; _convert_bodies даст simple_ai
	cfg.connect_action_signals = true    # полноценный игрок: сигналы удара/паса как у штатных
	var p := PlayerFactory.spawn(cfg, _manager._team_away)
	p.add_to_group("fk_spawned")
	# лицом к мячу, мотор залочен (стоит на месте)
	p.look_at(Vector3(_spot.x, pos.y, _spot.z), Vector3.UP)
	var pm := PlayerMotor.find_on(p)
	if pm != null:
		pm.set_control_locked(true)
		pm.set_move_intent(Vector3.ZERO)
	return p
```

- [ ] **Step 2: Rewrite `_make_mate_body`**

Заменить тело `_make_mate_body` (551-579) на:

```gdscript
func _make_mate_body(pos: Vector3) -> CharacterBody3D:
	var cfg := PlayerConfig.new()
	cfg.team_group = &"team_1"
	cfg.role = PlayerConfig.Role.FWD
	cfg.kit_color = Color(0.1, 0.1, 0.9)
	cfg.spawn_pos = pos
	cfg.display_name = "FKMate"
	cfg.control_mode = PlayerConfig.Control.AI
	cfg.ai_script = null                 # без ИИ до _convert_bodies (даст teammate_ai)
	cfg.connect_action_signals = true
	var p := PlayerFactory.spawn(cfg, _manager._team_home)
	p.add_to_group("fk_spawned")
	var pm := PlayerMotor.find_on(p)
	if pm != null:
		pm.set_control_locked(true)
		pm.set_move_intent(Vector3.ZERO)
	return p
```

- [ ] **Step 3: Verify `_convert_bodies` still works**

Прочитать `_convert_bodies` (505-533). Оно делает `b.set_script(ai_script); b.set_physics_process(true); b.ball = _ball; b.home_goal = ...` — это ПОСЛЕ фабрики валидно (тело фабричное, но `ai_script` был null → скрипт навешивается здесь впервые). Убедиться, что `_cleanup_spawned` (деспавн `fk_spawned`, кроме kicker) не задевает Team-ростер некорректно — тело в `_team_away._players`/`_team_home._players` останется висеть после `queue_free`; но `Team.players()` фильтрует невалидные, так что осиротевших ссылок не будет. Изменений кода на этом шаге нет — только проверка чтением.

- [ ] **Step 4: Run the regression grid**

Run all five regression commands, с особым вниманием к `check_free_kick_flow` (два штрафных подряд, отсутствие накопления тел через `fk_spawned`).
Expected: все `CHECK PASS`; 1–2 без новых категорий.

- [ ] **Step 5: Playtest sanity**

Запустить игру, нажать `F`: стенка спавнится (красные, лицом к мячу), после удара конвертируется в ИИ; пас/навес на своих работает; второй штрафной не плодит тел.

- [ ] **Step 6: Commit**

```bash
git add scripts/match/free_kick_controller.gd
git commit -m "refactor(spawn): route free-kick wall/mate bodies through PlayerFactory

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Перевод чтений по имени на запросы к ростеру/группам

**Files:**
- Modify: `scripts/match/match_manager.gd` (`player_away.target_node` ~931-937; `_sync_ai_controllers` ~980-989; `_reset_ball` ~2217-2234)

**Interfaces:**
- Consumes: `_team_home`/`_team_away`, `_human_player`, группы
- Produces: логика больше не читает `player_home`/`player_teammate` по имени в этих трёх местах.

- [ ] **Step 1: Convert the opponent `target_node` block**

Заменить блок 930-937:

```gdscript
	# Set opponent's target_node to whoever on our team is dribbling
	if player_away:
		if ball.has_method(&"set_dribbler") and ball.dribbler:
			var db: Node3D = ball.dribbler
			if db == player_home or db == player_teammate:
				player_away.target_node = db
		else:
			player_away.target_node = null
```

на (по группе, а не по именам — так же ловит фабрично-заспавненные team_1-тела):

```gdscript
	# Соперник целится в того из НАШЕЙ команды, кто дриблит (по группе, не по именам).
	if player_away:
		if ball.has_method(&"set_dribbler") and ball.dribbler and ball.dribbler.is_in_group("team_1"):
			player_away.target_node = ball.dribbler
		else:
			player_away.target_node = null
```

- [ ] **Step 2: Simplify `_sync_ai_controllers` to pure group iteration**

Заменить тело `_sync_ai_controllers` (980-989) на:

```gdscript
func _sync_ai_controllers() -> void:
	# Все team_1 с полем controlled_player (включая фабричных home/teammate и заспавненных
	# штрафным) синхронизируются, чтобы управляемое тело пропускало свой ИИ (гейт self==controlled).
	for n in get_tree().get_nodes_in_group("team_1"):
		if &"controlled_player" in n:
			n.controlled_player = controlled_player
```

- [ ] **Step 3: Convert `_reset_ball` to roster iteration**

Заменить блок 2226-2234 (`# Reset players ...` до `_sync_ai_controllers()`):

```gdscript
	# Reset players to their starting positions
	player_home.global_position = Vector3(0, 0.5, 0)
	if player_teammate:
		player_teammate.global_position = Vector3(10, 0.5, 5)
	if player_away:
		player_away.global_position = Vector3(20, 0.5, 0)

	controlled_player = player_home
	_sync_ai_controllers()
```

на (по ростеру, позиция каждого — из meta `home_pos`, проставленного фабрикой):

```gdscript
	# Возврат игроков на стартовые позиции — по ростеру обеих команд (home_pos из фабрики).
	for body in _team_home.players() + _team_away.players():
		if is_instance_valid(body):
			body.global_position = body.get_meta(&"home_pos", body.global_position)

	controlled_player = _human_player
	_sync_ai_controllers()
```

- [ ] **Step 4: Run the regression grid**

Run all five regression commands.
Expected: все `CHECK PASS`; 1–2 без новых категорий.

- [ ] **Step 5: Playtest sanity**

Запустить игру, забить/сбросить мяч (или дождаться авто-сброса) — игроки возвращаются на стартовые позиции, управление на человеке, соперник целится корректно.

- [ ] **Step 6: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "refactor(roster): convert target_node / sync / reset_ball to Team+group queries

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: Удаление именованных синглтонов-алиасов

**Files:**
- Modify: `scripts/match/match_manager.gd` (объявления `player_home`/`player_teammate`/`player_away`; все оставшиеся присваивания/чтения)

**Interfaces:**
- Produces: в `match_manager.gd` больше нет `player_home`/`player_teammate`/`player_away`. Остаются: `_human_player` (дефолтное тело человека), `controlled_player`, `_keeper`, `_team_home`/`_team_away`.

Замечание: перед удалением сделать grep, чтобы найти ВСЕ оставшиеся упоминания — часть могла остаться в местах, не покрытых Task 9 (напр. `player_away.set(&"mark_target", ...)` в `_setup_teammate`, проверки `if player_away`). Их перевести на локальные ссылки или `_team_*`-запросы.

- [ ] **Step 1: Enumerate remaining references**

Run: `grep -n "player_home\|player_teammate\|player_away" scripts/match/match_manager.gd`
Составить список. Ожидаемые оставшиеся точки после Task 5–9:
- объявления (строки ~11-12 + строка `var player_home ...`),
- `_setup_away_player`: `player_away = new_player`,
- `_setup_home_player`: `player_home = _human_player`,
- `_setup_teammate`: `player_teammate = new_player`, `if ... and player_away ...`, `player_away.set(&"mark_target", ...)`,
- блок `target_node` (Task 9 оставил `if player_away:` и `player_away.target_node`).

- [ ] **Step 2: Replace `player_away` usages with a helper/local**

Добавить хелпер:

```gdscript
## Соперник-полевой по умолчанию (первый не-вратарь team_2). До 11×11 их немного.
func _away_outfielder() -> CharacterBody3D:
	for b in _team_away.outfield():
		return b
	return null
```

В `_setup_teammate` заменить `player_away`-блок на:

```gdscript
	# DEBUG: соперник опекает этого тиммейта.
	if FootballConstants.DEBUG_MARK_TEAMMATE:
		var opp := _away_outfielder()
		if opp != null and is_instance_valid(opp):
			opp.set(&"mark_target", new_player)
```

В блоке `target_node` (Task 9) заменить `player_away` на локальную:

```gdscript
	# Соперник целится в того из НАШЕЙ команды, кто дриблит (по группе, не по именам).
	var opp := _away_outfielder()
	if opp != null:
		if ball.has_method(&"set_dribbler") and ball.dribbler and ball.dribbler.is_in_group("team_1"):
			opp.target_node = ball.dribbler
		else:
			opp.target_node = null
```

В `_setup_away_player` убрать строку `player_away = new_player` (тело регистрируется в `_team_away` фабрикой; `_away_outfielder()` его найдёт). Оставить `var new_player := PlayerFactory.spawn(...)` без присваивания в поле, или переименовать в `PlayerFactory.spawn(...)` без переменной, если `new_player` дальше не нужен (нужен для `DEBUG_MARK_TEAMMATE`? нет — там теперь `_away_outfielder`). Убрать переменную.

- [ ] **Step 3: Replace `player_teammate` usages**

`player_teammate` используется в: `_setup_teammate` (присваивание), `_sync_ai_controllers` (уже убрано в Task 9). Иных чтений нет (проверить grep из Step 1). Убрать присваивание `player_teammate = new_player` и объявление `var player_teammate`. `new_player` в `_setup_teammate` остаётся локальной (нужна для `mark_target`).

- [ ] **Step 4: Replace `player_home` usages**

`player_home` используется в: `_setup_home_player` (`player_home = _human_player`). Убрать это присваивание и объявление `var player_home`. Все прежние чтения `player_home` (reset/controlled) уже переведены на `_human_player` в Task 6/9.

- [ ] **Step 5: Remove the declarations**

Удалить строки объявлений `var player_away`, `var player_teammate` (11-12) и `var player_home ...` (из Task 6). Оставить `var _human_player`.

- [ ] **Step 6: Verify no references remain**

Run: `grep -n "player_home\|player_teammate\|player_away" scripts/match/match_manager.gd`
Expected: пусто (0 совпадений).

- [ ] **Step 7: Run the regression grid**

Run all five regression commands.
Expected: все `CHECK PASS`; 1–2 без новых категорий.

- [ ] **Step 8: Playtest sanity**

Полный проход: движение/дриблинг/удар/пас/тэкл, штрафной (`F`), пенальти (`P`), гол+сброс, вратарь. Всё как раньше.

- [ ] **Step 9: Commit**

```bash
git add scripts/match/match_manager.gd
git commit -m "refactor(roster): drop named player singletons (home/teammate/away)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: Документация (CLAUDE.md + AGENTS.md)

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`

**Interfaces:** нет (документация).

- [ ] **Step 1: Add a "Player spawn factory & roster" section to CLAUDE.md**

Вставить новую секцию (рядом с *Presentation layer & asset pipeline*), кратко фиксирующую как-построено:

```markdown
## Player spawn factory & roster (Phase 1)

Players are spawned through ONE seam — `PlayerFactory.spawn(config, team)`
(`scripts/match/player_factory.gd`, static) — which instantiates `scenes/player.tscn`
(CharacterBody3D + PlayerVisual → PlayerMotor → CollisionShape3D, fixed child order),
tints the kit, sets collision layers, registers the body into a `Team` node
(`scripts/match/team.gd`) as its child, adds physics groups (`team_1`/`team_2` +
`role_gk`/`role_def`/`role_mid`/`role_fwd`), stores `role` + `home_pos` meta, connects
`action_contact/finished` to the manager (skipped for the keeper — `keeper_ai` self-connects),
and attaches the AI via `set_script` (Phase 1; a Brain component replaces this in Phase 2).
Input to the factory is `PlayerConfig` (`scripts/match/player_config.gd`, RefCounted).

`Team` is the authoritative gameplay roster (`players()`/`by_role()`/`keeper()`/`outfield()`);
Godot groups remain the physics index. Two Team nodes under the manager: `_team_home`
(team_1) / `_team_away` (team_2). The manager keeps `_human_player` (default controlled body)
and `controlled_player`; the old `player_home`/`player_teammate`/`player_away` singletons are
GONE — query `_team_*` / groups instead. Keeper-specific nodes (SaveArea/HoldPoint) are created
by `_setup_keeper` AFTER the factory call. Free-kick wall/mate bodies (`free_kick_controller.gd`)
also go through the factory (`ai_script=null` until `_convert_bodies` attaches the real AI).

Tests: `check_player_config.gd`, `check_team_roster.gd`, `check_player_factory.gd`.
Phase 2 (AI brains as components) and Phase 3 (HumanBrain + ActionExecutor) are separate plans —
see `docs/superpowers/specs/2026-07-19-player-spawn-factory-design.md`.
```

- [ ] **Step 2: Update AGENTS.md**

Добавить в `AGENTS.md` 1-2 строки: спавн игроков — через `PlayerFactory.spawn(config, team)`, ростер — `Team`-узлы (`_team_home`/`_team_away`), именованных `player_home/teammate/away` больше нет.

- [ ] **Step 3: Verify docs match code**

Прочитать обе секции, сверить имена (`PlayerFactory`, `Team`, `PlayerConfig`, `_team_home`, `_human_player`) с фактическим кодом.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "docs(refactor): document player spawn factory + roster (Phase 1)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (против `2026-07-19-player-spawn-factory-design.md`, раздел «Фаза 1»):**
- `PlayerConfig` → Task 1. `player.tscn` → Task 3. `PlayerFactory` → Task 4. `Team` → Task 2. ✓
- Идентичность в группах + `role_*` → Task 2/4 (группы + meta). ✓
- Вратарь: SaveArea/HoldPoint пост-спавн → Task 7. ✓
- Роутинг 46 чтений → Task 9 (target_node/sync/reset) + Task 10 (удаление синглтонов; прочие чтения — pickup/`_we_possess`/`_team_arrays`/auto-switch/combo-swap — УЖЕ по группам, изменений не требуют, подтверждено чтением кода). ✓
- Удаление `$PlayerHome` → Task 6. ✓
- Free-kick wall/mate через фабрику → Task 8. ✓
- Удаление именованных переменных → Task 10. ✓
- DEBUG-флаги работают → сохранены в Task 5/7. ✓
- Тесты Фазы 1 (`check_player_factory`, `check_team_roster`) → Task 1/2/4. ✓
- Обновление CLAUDE.md/AGENTS.md → Task 11. ✓

**Placeholder scan:** без TBD/«add error handling»/«similar to Task N» — код приведён полностью в каждом шаге. ✓

**Type consistency:** `PlayerFactory.spawn(config, team)`, `PlayerFactory.find_visual(body)`, `PlayerMotor.find_on(p)` (существующий статик, см. CLAUDE.md *Locomotion*), `Team.add_player/players/by_role/keeper/outfield`, `PlayerConfig.role_group`, `PlayerConfig.Role.*`/`Control.*`, поля `extra_fields`/`connect_action_signals`/`locomotion_style`/`spawn_pos` — согласованы между Task 1/2/4 и потребителями 5–10. ✓

**Открытые допущения, проверяемые на исполнении (не блокеры):**
- `player.tscn`: базовый тип узла `PlayerMotor` — сверить первую строку `player_motor.gd` (`extends ...`) и при расхождении с `type="Node"` поправить (Task 3, Step 1 note).
- `scenes/match.tscn`: удаляемые `SubResource` капсулы — удалять только при отсутствии др. ссылок (Task 6, Step 3).
- `_ready`: точное место вставки `_setup_home_player()`/порядок `_setup_*` — сохранить прежний порядок (away → home → teammate → keeper → boundaries), не задвоить `_setup_controlled_indicator()` (Task 6, Step 2).

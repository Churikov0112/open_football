# Mixamo Player Pilot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить капсулу away-игрока на риггованную модель Mixamo с анимациями idle/run и цветом команды (тинт), не трогая геймплей-логику.

**Architecture:** Отдельный узел `PlayerVisual` (сцена + скрипт) инстансится как ребёнок существующего `CharacterBody3D` вместо капсулы. Он сам измеряет скорость по смещению позиции родителя и блендит idle↔run через построенный в коде `AnimationTree` (`AnimationNodeBlendSpace1D`). Геймплей-скрипты (`simple_ai.gd`, `match_manager.gd`) НЕ переписываются — только точка спавна визуала. Модель приходит как единый `.glb`, собранный headless-скриптом Blender из FBX-файлов Mixamo.

**Tech Stack:** Godot 4.7 / GDScript; Blender 5.1 (headless Python, FBX→glb merge); Mixamo (источник модели и анимаций).

## Global Constraints

- **Godot exe (headless-проверки):** `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`
- **Blender exe (merge):** `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`
- **Проект public/open-source:** сырые FBX Mixamo НЕ коммитить (только `.glb` — игровая форма). Происхождение фиксировать в `ASSET_CREDITS.md`.
- **Не трогать геймплей-логику:** движение (`move_toward` по `global_position`), физика, подкат, группы `team_1`/`team_2`/`fallen` остаются как есть. Меняется только визуальный слой.
- **Модель на пилоте — Mixamo + тинт всего тела** (не «настоящий кит»). team_1 = синий, team_2 = красный.
- **Стиль GDScript проекта:** статическая типизация (`: Type`), `func _ready() -> void`, `preload("res://...")`, `&"StringName"` для имён действий/узлов. Соблюдать.
- **Тестового фреймворка нет.** «Тест» = headless-скрипт Godot (`--headless -s res://tests/<check>.gd`), печатающий `CHECK PASS`/`CHECK FAIL` и выходящий с кодом 0/1; для рендера/анимации — визуальная приёмка пользователем (Claude не видит картинку).

---

### Task 1: Получить ассеты Mixamo (совместно с пользователем)

Скачивание с Mixamo — ручной шаг пользователя (нужен вход в Adobe-аккаунт). Claude готовит папку и `.gitignore`, даёт точную инструкцию, затем проверяет наличие файлов.

**Files:**
- Create: `assets/models/mixamo_src/` (папка для сырых FBX, в git не попадает)
- Modify: `.gitignore` (добавить игнор сырых FBX)

**Interfaces:**
- Produces: три файла `assets/models/mixamo_src/character.fbx`, `idle.fbx`, `run.fbx` — вход для Task 2.

- [ ] **Step 1: Создать папку под сырые ассеты**

```bash
mkdir -p "C:\Users\User\Desktop\projects\OpenFootball\assets\models\mixamo_src"
```

- [ ] **Step 2: Добавить игнор сырых FBX в `.gitignore`**

Дописать в конец `.gitignore`:

```gitignore
# Raw Mixamo FBX — не распространяем (public/open-source); коммитим только собранный .glb
assets/models/mixamo_src/
```

- [ ] **Step 3: Инструкция пользователю — что скачать на mixamo.com**

Передать пользователю дословно:

> 1. Зайти на https://www.mixamo.com (вход через Adobe ID, бесплатно).
> 2. **Модель:** выбрать персонажа (вкладка Characters) → справа **Download** → Format **FBX Binary (.fbx)**, Pose **T-pose** → сохранить как `character.fbx`.
> 3. **Idle:** в поиске анимаций набрать `idle` → выбрать нейтральную стойку → поставить галочку **In Place** → **Download** → FBX Binary, **Without Skin**, Frames per Second 30 → сохранить как `idle.fbx`.
> 4. **Run:** поиск `run` → выбрать бег → галочка **In Place** → **Download** → FBX Binary, **Without Skin**, 30 FPS → сохранить как `run.fbx`.
> 5. Положить все три файла в `assets/models/mixamo_src/`.
>
> Важно: модель — With Skin/T-pose; анимации — Without Skin + In Place (движение по полю делает игровой код, анимация «на месте»).

- [ ] **Step 4: Проверить, что файлы на месте**

Run:
```bash
ls -la "C:\Users\User\Desktop\projects\OpenFootball\assets\models\mixamo_src"
```
Expected: три файла `character.fbx`, `idle.fbx`, `run.fbx` присутствуют, размер > 0.

- [ ] **Step 5: Commit (только `.gitignore`)**

```bash
git add .gitignore
git commit -m "chore: ignore raw Mixamo FBX sources (ship only .glb)"
```

---

### Task 2: Собрать `footballer.glb` из FBX через Blender (headless)

**Files:**
- Create: `tools/merge_mixamo.py` (Blender-скрипт)
- Create: `assets/models/footballer.glb` (результат, коммитится)
- Create: `tests/check_footballer_glb.gd` (headless-проверка содержимого glb)
- Create: `ASSET_CREDITS.md` (атрибуция)

**Interfaces:**
- Consumes: `assets/models/mixamo_src/{character,idle,run}.fbx` (Task 1).
- Produces: `res://assets/models/footballer.glb` — PackedScene со `Skeleton3D` + `MeshInstance3D` + `AnimationPlayer`, где `get_animation_list()` содержит `"idle"` и `"run"`.

- [ ] **Step 1: Написать Blender-скрипт слияния**

Create `tools/merge_mixamo.py`:

```python
import bpy
import sys
import os

# Аргументы после "--": <src_dir> <out_glb>
argv = sys.argv[sys.argv.index("--") + 1:]
src_dir = argv[0]
out_path = argv[1]

# Чистая пустая сцена
bpy.ops.wm.read_factory_settings(use_empty=True)

# 1) Импорт персонажа со скином (T-pose)
bpy.ops.import_scene.fbx(filepath=os.path.join(src_dir, "character.fbx"),
                         automatic_bone_orientation=True)
main_arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
if main_arm.animation_data is None:
    main_arm.animation_data_create()
# убрать возможный T-pose action, чтобы не экспортировался лишний клип
main_arm.animation_data.action = None

# 2) Импорт анимаций, перенос экшенов на главный армейчер через NLA-треки
anim_files = {"idle": "idle.fbx", "run": "run.fbx"}
for anim_name, fname in anim_files.items():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(src_dir, fname),
                             automatic_bone_orientation=True)
    new_objs = [o for o in bpy.data.objects if o not in before]
    imp_arm = next(o for o in new_objs if o.type == 'ARMATURE')
    act = imp_arm.animation_data.action
    act.name = anim_name
    start = int(act.frame_range[0])
    track = main_arm.animation_data.nla_tracks.new()
    track.name = anim_name
    track.strips.new(anim_name, start, act)
    # удалить импортированные объекты (армейчер+меши), сам экшен остаётся в NLA
    for o in new_objs:
        bpy.data.objects.remove(o, do_unlink=True)

# 3) Экспорт единого glb: каждый NLA-трек → отдельная анимация с его именем
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    export_animation_mode='NLA_TRACKS',
    export_animations=True,
)
print("MERGE_OK")
```

- [ ] **Step 2: Запустить merge**

Run:
```bash
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python "C:\Users\User\Desktop\projects\OpenFootball\tools\merge_mixamo.py" -- "C:\Users\User\Desktop\projects\OpenFootball\assets\models\mixamo_src" "C:\Users\User\Desktop\projects\OpenFootball\assets\models\footballer.glb"
```
Expected: в выводе есть `MERGE_OK`, файл `assets/models/footballer.glb` создан (размер > 0).

Если ошибка `import_scene.fbx` (нет FBX-аддона): включить его —
`& "...blender.exe" --background --python-expr "import addon_utils; addon_utils.enable('io_scene_fbx')"` — затем повторить Step 2.

- [ ] **Step 3: Написать headless-проверку содержимого glb**

Create `tests/check_footballer_glb.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var ok := true
	var path := "res://assets/models/footballer.glb"
	if not ResourceLoader.exists(path):
		push_error("CHECK FAIL: нет ресурса " + path)
		quit(1)
		return
	var packed: PackedScene = load(path)
	var inst: Node = packed.instantiate()
	var ap := _find_anim_player(inst)
	if ap == null:
		print("CHECK FAIL: AnimationPlayer не найден в glb")
		ok = false
	else:
		var anims := ap.get_animation_list()
		print("CHECK: анимации в glb = ", anims)
		for want in ["idle", "run"]:
			if not ap.has_animation(want):
				print("CHECK FAIL: нет анимации '" + want + "'")
				ok = false
	inst.free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null
```

- [ ] **Step 4: Запустить проверку**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_footballer_glb.gd"
```
Expected: строка `CHECK PASS`, код выхода 0. Если имена анимаций отличаются от `idle`/`run` — запомнить фактические (понадобятся в Task 3) и/или поправить имена в `merge_mixamo.py` (NLA-трек = имя анимации) и пересобрать.

- [ ] **Step 5: Завести атрибуцию**

Create `ASSET_CREDITS.md`:

```markdown
# Asset Credits

| Asset | Source | Author | License | Notes |
|---|---|---|---|---|
| assets/models/footballer.glb | Adobe Mixamo | Adobe | Mixamo (royalty-free) | Модель + idle/run, собрано в игровую форму .glb; сырые FBX не распространяются |
```

- [ ] **Step 6: Commit**

```bash
git add tools/merge_mixamo.py assets/models/footballer.glb tests/check_footballer_glb.gd ASSET_CREDITS.md
git commit -m "feat: build footballer.glb from Mixamo FBX via Blender merge"
```

---

### Task 3: `PlayerVisual` — локомоция (idle↔run по скорости) + фолбэк

**Files:**
- Create: `scripts/player/player_visual.gd`
- Create: `scenes/player_visual.tscn`
- Create: `tests/check_player_visual_locomotion.gd`

**Interfaces:**
- Consumes: `res://assets/models/footballer.glb` (Task 2).
- Produces:
  - `class_name PlayerVisual` (extends Node3D).
  - `static func speed_to_blend(speed: float) -> float` — м/с → [0.0..1.0] позиция бленда.
  - `set_locomotion(velocity: Vector3) -> void`, `trigger(action: String) -> void`, `set_flag(flag: String, on: bool) -> void` — публичный API (в Task 3 реально работает только авто-локомоция; остальные — заготовки для будущих этапов).
  - экспорт-параметры `model_y_offset: float`, `model_yaw_deg: float` для визуальной подгонки.

- [ ] **Step 1: Написать `speed_to_blend` + скелет `PlayerVisual` со сборкой AnimationTree в коде**

Create `scripts/player/player_visual.gd`:

```gdscript
class_name PlayerVisual
extends Node3D

## Порог скорости (м/с), при котором бленд = полный бег (1.0).
const RUN_SPEED_FULL := 5.0
## Сглаживание бленда, 1/сек.
const BLEND_SMOOTH := 10.0

@export var model_y_offset: float = 0.0
@export var model_yaw_deg: float = 0.0

var _anim_tree: AnimationTree
var _model: Node3D
var _last_pos: Vector3
var _blend: float = 0.0
var _explicit_speed: float = -1.0  # >=0 → использовать вместо авто-замера

## Чистое отображение скорости (м/с) в позицию бленда [0..1].
static func speed_to_blend(speed: float) -> float:
	return clampf(speed / RUN_SPEED_FULL, 0.0, 1.0)

func _ready() -> void:
	_model = get_node_or_null(^"Model") as Node3D
	if _model == null:
		_use_fallback("нет узла Model")
		return
	_model.position.y = model_y_offset
	_model.rotation.y = deg_to_rad(model_yaw_deg)
	var ap := _find_anim_player(_model)
	if ap == null or not (ap.has_animation(&"idle") and ap.has_animation(&"run")):
		_use_fallback("нет AnimationPlayer с idle/run")
		return
	_build_anim_tree(ap)
	_last_pos = global_position

func _build_anim_tree(ap: AnimationPlayer) -> void:
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"idle"
	var run_node := AnimationNodeAnimation.new()
	run_node.animation = &"run"
	var bs := AnimationNodeBlendSpace1D.new()
	bs.add_blend_point(idle_node, 0.0)
	bs.add_blend_point(run_node, 1.0)
	_anim_tree = AnimationTree.new()
	_anim_tree.tree_root = bs
	add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(ap)
	_anim_tree.active = true

func _process(delta: float) -> void:
	if _anim_tree == null or delta <= 0.0:
		return
	var speed: float
	if _explicit_speed >= 0.0:
		speed = _explicit_speed
	else:
		var d := global_position - _last_pos
		d.y = 0.0
		speed = d.length() / delta
	_last_pos = global_position
	var target := speed_to_blend(speed)
	_blend = lerpf(_blend, target, clampf(BLEND_SMOOTH * delta, 0.0, 1.0))
	_anim_tree.set(&"parameters/blend_position", _blend)

## Явно задать скорость (для будущих геймплей-вызовов). Vector3.ZERO → снова авто-замер.
func set_locomotion(velocity: Vector3) -> void:
	_explicit_speed = Vector3(velocity.x, 0.0, velocity.z).length()

## Заготовка под one-shot (kick/header) — реализуется на этапе полного набора анимаций.
func trigger(action: String) -> void:
	push_warning("PlayerVisual.trigger('%s') ещё не реализован (пилот: только idle/run)" % action)

## Заготовка под длящиеся состояния (sliding/fallen) — будущий этап.
func set_flag(flag: String, on: bool) -> void:
	push_warning("PlayerVisual.set_flag('%s', %s) ещё не реализован" % [flag, str(on)])

func _use_fallback(reason: String) -> void:
	push_warning("PlayerVisual фолбэк-капсула: " + reason)
	var mesh := CapsuleMesh.new()
	mesh.height = 1.5
	mesh.radius = 0.3
	var mi := MeshInstance3D.new()
	mi.name = "FallbackCapsule"
	mi.mesh = mesh
	add_child(mi)

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null
```

- [ ] **Step 2: Собрать сцену `player_visual.tscn` (инстанс модели как ребёнок `Model`)**

Create `scenes/player_visual.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/player/player_visual.gd" id="1"]
[ext_resource type="PackedScene" path="res://assets/models/footballer.glb" id="2"]

[node name="PlayerVisual" type="Node3D"]
script = ExtResource("1")

[node name="Model" parent="." instance=ExtResource("2")]
```

- [ ] **Step 3: Написать headless-проверку `speed_to_blend`**

Create `tests/check_player_visual_locomotion.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var ok := true
	# idle при нуле
	if not is_equal_approx(PlayerVisual.speed_to_blend(0.0), 0.0):
		print("CHECK FAIL: speed 0 → ", PlayerVisual.speed_to_blend(0.0))
		ok = false
	# полный бег на/выше порога
	if not is_equal_approx(PlayerVisual.speed_to_blend(5.0), 1.0):
		print("CHECK FAIL: speed 5 → ", PlayerVisual.speed_to_blend(5.0))
		ok = false
	if not is_equal_approx(PlayerVisual.speed_to_blend(9.0), 1.0):
		print("CHECK FAIL: speed 9 (клампинг) → ", PlayerVisual.speed_to_blend(9.0))
		ok = false
	# середина
	if not is_equal_approx(PlayerVisual.speed_to_blend(2.5), 0.5):
		print("CHECK FAIL: speed 2.5 → ", PlayerVisual.speed_to_blend(2.5))
		ok = false
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Step 4: Запустить проверку**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_locomotion.gd"
```
Expected: `CHECK PASS`, код выхода 0.

- [ ] **Step 5: Проверить, что проект грузится headless без ошибок**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
```
Expected: завершается без `SCRIPT ERROR` / `Parse Error` в выводе.

- [ ] **Step 6: Commit**

```bash
git add scripts/player/player_visual.gd scenes/player_visual.tscn tests/check_player_visual_locomotion.gd
git commit -m "feat: PlayerVisual node — idle/run blend by measured speed, with capsule fallback"
```

---

### Task 4: `apply_appearance` — тинт цвета команды

**Files:**
- Modify: `scripts/player/player_visual.gd`
- Create: `tests/check_player_visual_appearance.gd`

**Interfaces:**
- Consumes: `PlayerVisual` (Task 3).
- Produces:
  - `apply_appearance(cfg: Dictionary) -> void` — читает `cfg["kit_color"]` (Color) и тинтит все меши.
  - `static func tint_tree(root: Node, color: Color) -> int` — рекурсивно ставит `material_override` (unshaded-free StandardMaterial3D с `albedo_color = color`) на каждый `MeshInstance3D`; возвращает число обработанных мешей.

- [ ] **Step 1: Написать статический `tint_tree` и `apply_appearance`**

В `scripts/player/player_visual.gd` добавить (после `set_flag`):

```gdscript
## Применить внешность при спавне. Пилот использует только "kit_color".
func apply_appearance(cfg: Dictionary) -> void:
	if cfg.has("kit_color"):
		var root: Node = _model if _model != null else self
		var n := PlayerVisual.tint_tree(root, cfg["kit_color"] as Color)
		if n == 0:
			push_warning("apply_appearance: не найдено мешей для тинта")

## Рекурсивно затинтить все MeshInstance3D под root. Возвращает число мешей.
static func tint_tree(root: Node, color: Color) -> int:
	var count := 0
	if root is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		(root as MeshInstance3D).material_override = mat
		count += 1
	for c in root.get_children():
		count += tint_tree(c, color)
	return count
```

- [ ] **Step 2: Написать headless-проверку тинта**

Create `tests/check_player_visual_appearance.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var ok := true
	# синтетическое дерево: Node3D → MeshInstance3D(x2, вложенные)
	var root := Node3D.new()
	var m1 := MeshInstance3D.new()
	m1.mesh = BoxMesh.new()
	var m2 := MeshInstance3D.new()
	m2.mesh = BoxMesh.new()
	root.add_child(m1)
	m1.add_child(m2)
	var col := Color(0.9, 0.1, 0.1)
	var n := PlayerVisual.tint_tree(root, col)
	if n != 2:
		print("CHECK FAIL: ожидали 2 меша, получили ", n)
		ok = false
	var mat := m1.material_override as StandardMaterial3D
	if mat == null or not mat.albedo_color.is_equal_approx(col):
		print("CHECK FAIL: albedo m1 = ", mat.albedo_color if mat else "нет материала")
		ok = false
	var mat2 := m2.material_override as StandardMaterial3D
	if mat2 == null or not mat2.albedo_color.is_equal_approx(col):
		print("CHECK FAIL: albedo m2 не выставлен")
		ok = false
	root.free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Step 3: Запустить проверку**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_visual_appearance.gd"
```
Expected: `CHECK PASS`, код выхода 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/player/player_visual.gd tests/check_player_visual_appearance.gd
git commit -m "feat: PlayerVisual.apply_appearance — whole-body kit color tint"
```

---

### Task 5: Встроить визуал в away-игрока (замена капсулы) + красный тинт

**Files:**
- Modify: `scripts/match/match_manager.gd` (`_setup_away_player`, строки ~341–349)

**Interfaces:**
- Consumes: `scenes/player_visual.tscn` (Task 3), `apply_appearance` (Task 4).
- Produces: away-игрок (`team_2`) визуализируется моделью Mixamo, затинтованной в красный; коллизия/скрипт/группы не тронуты.

- [ ] **Step 1: Заменить создание капсулы на инстанс `PlayerVisual`**

В `scripts/match/match_manager.gd`, в `_setup_away_player()` заменить блок создания меша-капсулы:

```gdscript
	var mesh := CapsuleMesh.new()
	mesh.height = 1.5
	mesh.radius = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.1, 0.1)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	new_player.add_child(mi)
```

на:

```gdscript
	var visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	new_player.add_child(visual)
	visual.apply_appearance({"kit_color": Color(0.9, 0.1, 0.1)})
```

(Блок `CollisionShape3D`, `add_to_group("team_2")`, `set_script(...)` — оставить без изменений.)

- [ ] **Step 2: Проверить headless-загрузку проекта**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
```
Expected: без `SCRIPT ERROR` / `Parse Error`.

- [ ] **Step 3: Визуальная приёмка (пользователь запускает игру)**

Передать пользователю:

> Запусти игру (открыть проект в Godot 4.7 → F5, главная сцена `main_menu.tscn` → Start).
> Смотри на красного away-игрока и ответь / пришли скриншот:
> 1. Модель стоит на земле (не висит/не утоплена)? Если нет — насколько и куда сдвинута.
> 2. Размер адекватный (примерно с человека ~1.8 м, не гигант/не муравей)?
> 3. Когда игрок бежит за мячом — проигрывается бег; когда стоит — idle?
> 4. Модель повёрнута лицом по движению (не спиной/боком)?
> 5. Красный цвет применился?

- [ ] **Step 4: Подгонка по фидбеку (при необходимости)**

По ответам пользователя выставить в `scenes/player_visual.tscn` на узле `PlayerVisual`:
- **висит/утоплен** → `model_y_offset` (напр. `-0.75`, чтобы ступни встали на землю относительно центра капсулы на `y=0.5`);
- **смотрит не туда** → `model_yaw_deg` (обычно `180.0`, если модель смотрит спиной);
- **гигант/муравей** → в Import-доке `footballer.glb` выставить import scale (Mixamo часто ×100 → scale `0.01`), переимпортировать.

Изменить значения экспорт-параметров прямо в `.tscn`:

```
[node name="PlayerVisual" type="Node3D"]
script = ExtResource("1")
model_y_offset = -0.75
model_yaw_deg = 180.0
```

Повторять Step 3 ↔ Step 4, пока картинка не устроит.

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_manager.gd scenes/player_visual.tscn
git commit -m "feat: away player uses Mixamo PlayerVisual (red kit) instead of capsule"
```

---

### Task 6: Раскрасить обе команды (teammate + PlayerHome в синий)

Завершает требование «синий/красный»: заменить оставшиеся капсулы team_1 на `PlayerVisual` с синим тинтом.

**Files:**
- Modify: `scripts/match/match_manager.gd` (`_setup_teammate`, строки ~370–378)
- Modify: `scenes/player.tscn` (визуал `PlayerHome`) ИЛИ `scripts/match/match_manager.gd` (`_ready`, добавить визуал для `player_home`)

**Interfaces:**
- Consumes: `scenes/player_visual.tscn`, `apply_appearance` (Tasks 3–4).
- Produces: teammate и PlayerHome (`team_1`) — модели Mixamo, синий тинт.

- [ ] **Step 1: Заменить капсулу teammate на `PlayerVisual` (синий)**

В `_setup_teammate()` заменить блок капсулы:

```gdscript
	var mesh := CapsuleMesh.new()
	mesh.height = 1.5
	mesh.radius = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.9)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	new_player.add_child(mi)
```

на:

```gdscript
	var visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	new_player.add_child(visual)
	visual.apply_appearance({"kit_color": Color(0.1, 0.1, 0.9)})
```

- [ ] **Step 2: Определить, как визуализируется `PlayerHome`**

Run:
```bash
grep -n "MeshInstance\|CapsuleMesh\|PlayerHome" "C:\Users\User\Desktop\projects\OpenFootball\scenes\player.tscn"
```
Expected: увидеть, есть ли у `player.tscn` меш-капсула. Если да — Step 3a; если `PlayerHome` без визуала в сцене — Step 3b.

- [ ] **Step 3a: Если у `player.tscn` есть капсула — добавить синий `PlayerVisual` в `_ready` match_manager**

В `scripts/match/match_manager.gd`, `_ready()`, сразу после `player_home.add_to_group("team_1")` (строка ~45) добавить:

```gdscript
	var home_visual: PlayerVisual = preload("res://scenes/player_visual.tscn").instantiate()
	player_home.add_child(home_visual)
	home_visual.apply_appearance({"kit_color": Color(0.1, 0.1, 0.9)})
```

Затем в `scenes/player.tscn` скрыть/удалить старую капсулу-меш (выставить у её `MeshInstance3D` `visible = false`), чтобы не было двойного визуала.

- [ ] **Step 3b: Если у `PlayerHome` нет собственного визуала — та же вставка в `_ready` (без правки `player.tscn`)**

Добавить тот же блок из Step 3a в `_ready()` после `player_home.add_to_group("team_1")`.

- [ ] **Step 4: Проверить headless-загрузку**

Run:
```bash
& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit
```
Expected: без `SCRIPT ERROR` / `Parse Error`.

- [ ] **Step 5: Визуальная приёмка (пользователь)**

Передать пользователю:

> Запусти игру. Убедись: обе команды — модели (не капсулы), team_1 (ты + напарник) синие, team_2 (соперник) красный, у каждого нет второй «призрачной» капсулы. Пришли скриншот при сомнениях.

- [ ] **Step 6: Commit**

```bash
git add scripts/match/match_manager.gd scenes/player.tscn
git commit -m "feat: both teams use Mixamo PlayerVisual (team_1 blue, team_2 red)"
```

---

## Self-Review

**Spec coverage** (против `2026-07-08-3d-assets-pipeline-design.md`):
- Игроки через Mixamo, `.glb` в репо, сырые FBX игнорятся → Tasks 1–2, `.gitignore`, `ASSET_CREDITS.md`. ✅
- Разделение геймплей/презентация, `PlayerVisual` отдельным узлом → Tasks 3, 5, 6. ✅
- Гибридный интерфейс `set_locomotion/trigger/set_flag/apply_appearance` → Tasks 3–4 (для пилота реально работают авто-локомоция + `apply_appearance`; `trigger`/`set_flag` — типизированные заготовки, будущие этапы 3 плана спеки). ✅
- Пайплайн Mixamo→glb→Godot + грабли (масштаб ×100, ориентация, in-place) → Task 2 + Task 5 Step 4. ✅
- Тинт команды синий/красный → Tasks 5–6. ✅
- Фолбэк-капсула при сбое модели → Task 3 (`_use_fallback`). ✅
- Разделение труда (Mixamo/визуальная приёмка — пользователь; код — Claude) → Task 1 Step 3, Task 5 Step 3, Task 6 Step 5. ✅
- Этап пилота из спеки (idle+run, один away, затем обе команды) → полностью. ✅

Не в скоупе пилота (осознанно, будущие этапы спеки): sprint/kick/slide/fall анимации, шейдер-маска настоящих китов, вариативность кожа/волосы/причёски, CC0-реквизит, 11v11.

**Placeholder scan:** плейсхолдеров нет — весь GDScript/Python/tscn приведён целиком; `trigger`/`set_flag` намеренно заглушки с `push_warning` (описано явно, не TODO).

**Type consistency:** `PlayerVisual`, `speed_to_blend`, `tint_tree`, `apply_appearance(cfg: Dictionary)`, `model_y_offset`, `model_yaw_deg`, имена анимаций `idle`/`run`, путь `res://assets/models/footballer.glb`, `res://scenes/player_visual.tscn` — согласованы между Tasks 2–6.

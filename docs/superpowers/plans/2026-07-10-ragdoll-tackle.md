# Physical Ragdoll Tackle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Подкат сбивает соперника физичным `PhysicalBone3D`-ragdoll'ом, после чего проигрывается авторская цепочка «на живот → 2 переката от подкатчика → `standing_up` → `idle`»; локомоция переезжает на настоящий пол-коллайдер.

**Architecture:** Гибрид физика→анимация. `RagdollSkeleton` (новый класс) строит физскелет кодом по `Skeleton3D`. `PlayerVisual` владеет им и даёт seam-API падения/вставания. `match_manager` оркеструет конечный автомат падения жертвы и переводит подкатчика на клип `tackle`. `PlayerMotor` меняет ручной пин Y на гравитацию + `floor_snap` над статическим полом.

**Tech Stack:** Godot 4.7 stable / GDScript. Blender 5.1 (headless) для пересборки glb. Без сторонних плагинов. Автолоад `FootballConstants`.

## Global Constraints

- **Движок:** Godot 4.7 stable, GDScript. Exe: `C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe`.
- **Blender:** `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`.
- **Валидация загрузки (headless):** `& "<godot exe>" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit` — без ошибок скриптов. **После каждой задачи.**
- **Headless-тест:** `& "<godot exe>" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/<name>.gd"` — `extends SceneTree`, печатает `CHECK PASS`/`CHECK FAIL`, выходит 0/1.
- **Rebuild glb:** `& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python tools/merge_mixamo.py -- "C:/Users/User/Desktop/projects/OpenFootball/assets/models/mixamo_src" "C:/Users/User/Desktop/projects/OpenFootball/assets/models/footballer.glb"`, затем импорт: `& "<godot exe>" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import`.
- **InputMap ТОЛЬКО в `match_manager.gd:_setup_inputs()`** — не править input в `project.godot`.
- **Ветка:** `feat/living-locomotion`.
- **Слои коллизий (существующие):** layer 1 = пич+мяч; `PLAYER_COLLISION_MASK := 2`; `BOUNDARY_COLLISION_LAYER := 4`. Новый `RAGDOLL_COLLISION_LAYER := 8`. Пол — на слое 1.
- **Разделение gameplay/presentation:** физика тела/коллайдер — на `CharacterBody3D`; скелет/анимации/ragdoll — в `PlayerVisual`/`RagdollSkeleton`. Не смешивать.
- **Тюнинг-числа — стартовые**, финал подбирается живым прогоном; фил/стабильность ragdoll headless не проверяется (только загрузка + чистая математика + структура).
- Спек: [docs/superpowers/specs/2026-07-09-ragdoll-tackle-design.md](../specs/2026-07-09-ragdoll-tackle-design.md).

---

## File Structure

- **Modify** `tools/merge_mixamo.py` — заморозка горизонтали Hips для `IN_PLACE_CLIPS`.
- **Create** `tests/check_tackle_in_place.gd` — нет дрейфа Hips у `tackle`/`roll_left`/`roll_right`.
- **Modify** `tests/check_footballer_glb.gd` — проверка наличия `roll_left`/`roll_right`.
- **Modify** `assets/models/footballer.glb` (+ `.import`) — пересборка.
- **Modify** `scripts/data/football_constants.gd` — новые константы `GRAVITY`, `RAGDOLL_*`, `ROLL_DISTANCE`, `PRONE_BLEND_TIME`, `RAGDOLL_COLLISION_LAYER`; удаление `SLIDE_TACKLE_FALL_DISTANCE`/`SLIDE_TACKLE_FALL_TIME` (в Task 6).
- **Modify** `scripts/player/player_motor.gd` — гравитация + floor_snap вместо пина Y; статик `gravity_step`.
- **Modify** `tests/check_player_motor_math.gd` — тест `gravity_step`.
- **Modify** `scripts/match/match_manager.gd` — пол-коллайдер (Task 2); конечный автомат падения жертвы + подкатчик на клип `tackle` + чистка (Tasks 5–6).
- **Create** `scripts/player/ragdoll_skeleton.gd` (`class_name RagdollSkeleton`) — строитель физскелета.
- **Create** `tests/check_ragdoll_build.gd` — структура физскелета.
- **Modify** `scripts/player/player_visual.gd` — API ragdoll/вставания + one-shot стейты `tackle`/`roll_left`/`roll_right`/`standing_up`.

---

## Task 1: In-place конвертация клипов + пересборка glb

**Files:**
- Modify: `tools/merge_mixamo.py`
- Create: `tests/check_tackle_in_place.gd`
- Modify: `tests/check_footballer_glb.gd`
- Modify: `assets/models/footballer.glb` (+ `.import`) — через rebuild

**Interfaces:**
- Consumes: FBX в `assets/models/mixamo_src/` (`tackle.fbx`, `roll_left.fbx`, `roll_right.fbx` — с root motion).
- Produces: `footballer.glb` с in-place клипами `tackle`/`roll_left`/`roll_right` (нет горизонтального дрейфа Hips), плюс `roll_left`/`roll_right` присутствуют.

- [ ] **Step 1: Написать падающий тест in-place**

Создать `tests/check_tackle_in_place.gd`:

```gdscript
extends SceneTree

# Проверяет, что у клипов из IN_PLACE_CLIPS горизонтальная позиция Hips (X,Z) почти
# не меняется вдоль клипа — т.е. root motion убран (клип in-place).
func _initialize() -> void:
	var ok := true
	var scene: PackedScene = load("res://assets/models/footballer.glb")
	if scene == null:
		print("CHECK FAIL: не загрузился footballer.glb"); quit(1); return
	var root := scene.instantiate()
	var ap := _find_ap(root)
	if ap == null:
		print("CHECK FAIL: нет AnimationPlayer в glb"); quit(1); return

	var eps := 0.05  # метры в единицах модели; дрейф больше — значит root motion остался
	for clip in ["tackle", "roll_left", "roll_right"]:
		if not ap.has_animation(clip):
			print("CHECK FAIL: нет клипа ", clip); ok = false; continue
		var anim := ap.get_animation(clip)
		var ti := _hips_position_track(anim)
		if ti < 0:
			print("CHECK FAIL: нет position-трека Hips в ", clip); ok = false; continue
		var min_x := INF; var max_x := -INF; var min_z := INF; var max_z := -INF
		for k in anim.track_get_key_count(ti):
			var v: Vector3 = anim.track_get_key_value(ti, k)
			min_x = minf(min_x, v.x); max_x = maxf(max_x, v.x)
			min_z = minf(min_z, v.z); max_z = maxf(max_z, v.z)
		var drift_x := max_x - min_x
		var drift_z := max_z - min_z
		if drift_x > eps or drift_z > eps:
			print("CHECK FAIL: ", clip, " дрейф Hips X=", drift_x, " Z=", drift_z); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null

func _hips_position_track(anim: Animation) -> int:
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D \
			and String(anim.track_get_path(t)).to_lower().contains("hips"):
			return t
	return -1
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_tackle_in_place.gd"`
Expected: FAIL — у `tackle`/`roll_left`/`roll_right` дрейф Hips > eps (root motion ещё в glb).

- [ ] **Step 3: Добавить заморозку горизонтали Hips в merge-скрипт**

В `tools/merge_mixamo.py` после строки `anim_files[os.path.splitext(fname)[0].lower()] = fname` (конец блока сбора файлов, перед `if not anim_files:`) добавить множество и хелпер:

```python
# Клипы, приехавшие с root motion → морозим горизонтальную трансляцию корневой кости
# (делаем in-place). Для уже-in-place клипов это no-op. standing_up НЕ трогаем.
IN_PLACE_CLIPS = {"tackle", "roll_left", "roll_right"}

def freeze_root_horizontal(imp_arm, act):
    # Корневая кость Mixamo (без родителя), обычно "mixamorig:Hips".
    root_bone = None
    for b in imp_arm.data.bones:
        if b.parent is None:
            root_bone = b.name
            break
    if root_bone is None:
        print("IN_PLACE: не найдена корневая кость, пропуск")
        return
    path = 'pose.bones["%s"].location' % root_bone
    for fc in act.fcurves:
        # array_index: 0=X, 1=Y, 2=Z — морозим X и Z, вертикаль (Y) оставляем.
        if fc.data_path == path and fc.array_index in (0, 2):
            if not fc.keyframe_points:
                continue
            first = fc.keyframe_points[0].co[1]
            for kp in fc.keyframe_points:
                kp.co[1] = first
                kp.handle_left[1] = first
                kp.handle_right[1] = first
            fc.update()
    print("IN_PLACE: заморожена горизонталь Hips для action %s" % act.name)
```

Затем внутри цикла `for anim_name, fname in anim_files.items():`, сразу после `act.name = anim_name` (перед вычислением `start`), добавить:

```python
    if anim_name in IN_PLACE_CLIPS:
        freeze_root_horizontal(imp_arm, act)
```

- [ ] **Step 4: Пересобрать glb и переимпортировать**

Run (Blender rebuild):
`& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python tools/merge_mixamo.py -- "C:/Users/User/Desktop/projects/OpenFootball/assets/models/mixamo_src" "C:/Users/User/Desktop/projects/OpenFootball/assets/models/footballer.glb"`
Expected: в выводе `IN_PLACE: ...` для трёх клипов и `MERGE_OK`.

Затем импорт в Godot:
`& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import`
Expected: без ошибок импорта.

- [ ] **Step 5: Запустить тест in-place — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_tackle_in_place.gd"`
Expected: `CHECK PASS`, exit 0.

- [ ] **Step 6: Дополнить `check_footballer_glb.gd` проверкой roll-клипов**

Прочитать `tests/check_footballer_glb.gd`. Он проверяет наличие набора клипов. Добавить `"roll_left"` и `"roll_right"` в список ожидаемых клипов (найти массив/набор ожидаемых имён и дописать эти два). Запустить:
`& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_footballer_glb.gd"`
Expected: `CHECK PASS`.

- [ ] **Step 7: Коммит**

```bash
git add tools/merge_mixamo.py tests/check_tackle_in_place.gd tests/check_footballer_glb.gd assets/models/footballer.glb assets/models/footballer.glb.import
git commit -m "feat(ragdoll): in-place tackle/roll clips + rebuild glb"
```

---

## Task 2: Пол-коллайдер, гравитация в `PlayerMotor`, новые константы

**Files:**
- Modify: `scripts/data/football_constants.gd`
- Modify: `scripts/player/player_motor.gd`
- Modify: `tests/check_player_motor_math.gd`
- Modify: `scripts/match/match_manager.gd` (добавить `_setup_floor`)

**Interfaces:**
- Consumes: ничего нового.
- Produces:
  - Константы `FootballConstants.GRAVITY`, `RAGDOLL_COLLISION_LAYER`, `RAGDOLL_TACKLE_IMPULSE`, `RAGDOLL_UP_IMPULSE`, `RAGDOLL_SETTLE_SPEED`, `RAGDOLL_MIN_DOWN_TIME`, `RAGDOLL_MAX_DOWN_TIME`, `PRONE_BLEND_TIME`, `ROLL_DISTANCE`.
  - `PlayerMotor.gravity_step(vy: float, grounded: bool, gravity: float, delta: float) -> float` (static).
  - Статический пол на y=0 в сцене матча.

- [ ] **Step 1: Добавить константы ragdoll/гравитации**

В `scripts/data/football_constants.gd` после строки `const AI_TACKLE_COOLDOWN := 2.0` (конец секции SLIDE TACKLE) добавить:

```gdscript

# ═══════════════════════════════════════════
#  RAGDOLL TACKLE / GRAVITY (тюнинг-старт)
# ═══════════════════════════════════════════

const GRAVITY := 20.0                 # аркадная гравитация, м/с²
const RAGDOLL_COLLISION_LAYER := 8    # bit4: физкости ragdoll, маскируют только пол (слой1)
const RAGDOLL_TACKLE_IMPULSE := 6.0   # сила сбивающего импульса вдоль подката
const RAGDOLL_UP_IMPULSE := 2.0       # вертикальная добавка импульса
const RAGDOLL_SETTLE_SPEED := 0.6     # ниже этой скорости таза (м/с) → ragdoll осел
const RAGDOLL_MIN_DOWN_TIME := 0.4    # минимум фазы физики, с
const RAGDOLL_MAX_DOWN_TIME := 1.5    # хард-кап фазы физики, с
const PRONE_BLEND_TIME := 0.2         # кроссфейд ragdoll→анимация, с
const ROLL_DISTANCE := 1.2            # смещение тела за один перекат, м
```

- [ ] **Step 2: Написать падающий тест `gravity_step`**

В `tests/check_player_motor_math.gd` перед строкой `print("CHECK PASS" if ok else "CHECK FAIL")` вставить:

```gdscript
	# gravity_step: в воздухе копит вниз; на земле обнуляется (не накапливает бесконечно).
	if not is_equal_approx(PlayerMotor.gravity_step(0.0, false, 20.0, 0.1), -2.0):
		print("CHECK FAIL: gravity_step air → ", PlayerMotor.gravity_step(0.0, false, 20.0, 0.1)); ok = false
	if not is_equal_approx(PlayerMotor.gravity_step(-5.0, true, 20.0, 0.1), 0.0):
		print("CHECK FAIL: gravity_step grounded → ", PlayerMotor.gravity_step(-5.0, true, 20.0, 0.1)); ok = false
```

- [ ] **Step 3: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_motor_math.gd"`
Expected: FAIL — метода `gravity_step` ещё нет.

- [ ] **Step 4: Добавить `gravity_step` и перевести `PlayerMotor` на гравитацию+пол**

4a. В `scripts/player/player_motor.gd` после static-функции `smooth_scalar` (перед `var _intent_dir`) добавить:

```gdscript
## Вертикальная скорость: на земле обнуляется (стоим на полу), в воздухе копит g.
static func gravity_step(vy: float, grounded: bool, gravity: float, delta: float) -> float:
	if grounded:
		return 0.0
	return vy - gravity * delta
```

4b. Удалить поле `var _ground_y: float = 0.5` (строка ~33) и строку `_ground_y = _body.global_position.y` в `_ready` (строка ~44).

4c. В `_ready`, сразу после проверки `_body == null` (внутри, где motor остаётся включённым — т.е. после блока раннего return), добавить настройку floor-snap. Заменить существующий блок `_ready`:

```gdscript
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
```

на:

```gdscript
func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_warning("PlayerMotor: родитель не CharacterBody3D — motor выключен")
		set_physics_process(false)
		return
	_body.up_direction = Vector3.UP
	_body.floor_snap_length = 0.3
	for c in _body.get_children():
		if c is PlayerVisual:
			_visual = c
			break
```

4d. Добавить поле вертикальной скорости. После `var _lean_deg: float = 0.0` добавить:

```gdscript
var _vy: float = 0.0
```

4e. В `_physics_process` заменить блок присвоения скорости и пина Y. Найти:

```gdscript
	_body.velocity = new_vel
	_body.move_and_slide()
	if not _body.is_in_group("fallen"):
		_body.global_position.y = _ground_y  # поле плоское — пиннинг высоты (кроме сбитых: не гасить вертикальный отскок такла)
```

заменить на:

```gdscript
	# Вертикаль: гравитация + приземление на пол-коллайдер (вместо ручного пина Y).
	# Пока сбиты (fallen) — телом владеет ragdoll/оркестратор, motor вертикаль не трогает.
	if _body.is_in_group("fallen"):
		_vy = 0.0
		new_vel.y = 0.0
	else:
		_vy = PlayerMotor.gravity_step(_vy, _body.is_on_floor(), FootballConstants.GRAVITY, delta)
		new_vel.y = _vy
	_body.velocity = new_vel
	_body.move_and_slide()
	if _body.is_on_floor():
		_vy = 0.0
```

(Примечание: `integrate_velocity` возвращает вектор с `y=0`; мы досыпаем `new_vel.y` вручную. Горизонтальная часть не меняется.)

- [ ] **Step 5: Запустить тест мат-мотора — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_player_motor_math.gd"`
Expected: `CHECK PASS`, exit 0.

- [ ] **Step 6: Добавить пол-коллайдер в сцену матча**

6a. В `scripts/match/match_manager.gd` добавить функцию (рядом с прочими `_setup_*`, например после `_setup_tackle_area`):

```gdscript
## Статический пол на y=0 (слой 1 = «газон»): опора для локомоции и приземления ragdoll.
func _setup_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()  # бесконечная плоскость, нормаль +Y, y=0
	floor_body.add_child(col)
	add_child(floor_body)
```

6b. В `_ready`, добавить вызов `_setup_floor()` первой строкой после `_setup_inputs()` (пол должен существовать до спавна игроков):

Найти в `_ready`:
```gdscript
	_setup_inputs()
	_setup_grass()
```
Заменить на:
```gdscript
	_setup_inputs()
	_setup_floor()
	_setup_grass()
```

- [ ] **Step 7: Проверить загрузку проекта headless**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без ошибок скриптов.

- [ ] **Step 8: Ручная проверка (человек)**

Запустить игру, из `main_menu` → Start. Проверить: игроки **стоят на поле** (не проваливаются/не висят) на прежней высоте; движение/разгон/торможение/спринт как раньше; подкат (старое капсульное падение пока на месте — сломается в Task 5, это ожидаемо). Если капсула тонет/висит — поправить высоту `CapsuleShape3D` (сейчас `height=1.5, radius=0.3`, центр тела на y=0.5), не пол.

- [ ] **Step 9: Коммит**

```bash
git add scripts/data/football_constants.gd scripts/player/player_motor.gd tests/check_player_motor_math.gd scripts/match/match_manager.gd
git commit -m "feat(ragdoll): floor collider + gravity/floor-snap in PlayerMotor + ragdoll constants"
```

---

## Task 3: `RagdollSkeleton` — строитель физскелета

**Files:**
- Create: `scripts/player/ragdoll_skeleton.gd`
- Create: `tests/check_ragdoll_build.gd`

**Interfaces:**
- Consumes: `FootballConstants.RAGDOLL_COLLISION_LAYER` (Task 2).
- Produces (инстанс-API, зовётся `PlayerVisual` в Task 4):
  - `func build(skeleton: Skeleton3D, layer: int) -> int` — строит дремлющие физкости, возвращает их число.
  - `func start(impulse: Vector3) -> void`
  - `func stop() -> void`
  - `func active() -> bool`
  - `func hip_position() -> Vector3`
  - `const SKIP_SUBSTRINGS` — исключаемые кости.

- [ ] **Step 1: Написать падающий тест структуры**

Создать `tests/check_ragdoll_build.gd`:

```gdscript
extends SceneTree

# Строит физскелет по синтетическому Skeleton3D и проверяет структуру:
# созданы PhysicalBone3D для не-листовых не-пальцевых костей, у каждой capsule-шейп,
# пальцы исключены.
func _initialize() -> void:
	var ok := true
	var RagdollSkeletonScript := load("res://scripts/player/ragdoll_skeleton.gd")

	var skel := Skeleton3D.new()
	# Цепочка: Hips → Spine → (LeftUpLeg → LeftLeg), плюс палец LeftHandIndex (должен быть исключён).
	var hips := skel.add_bone("mixamorig:Hips")
	var spine := skel.add_bone("mixamorig:Spine")
	skel.set_bone_parent(spine, hips)
	var upleg := skel.add_bone("mixamorig:LeftUpLeg")
	skel.set_bone_parent(upleg, hips)
	var leg := skel.add_bone("mixamorig:LeftLeg")
	skel.set_bone_parent(leg, upleg)
	var finger := skel.add_bone("mixamorig:LeftHandIndex1")
	skel.set_bone_parent(finger, spine)
	# рест-смещения (ненулевые, чтобы длины считались)
	skel.set_bone_rest(spine, Transform3D(Basis(), Vector3(0, 0.2, 0)))
	skel.set_bone_rest(upleg, Transform3D(Basis(), Vector3(0.1, -0.1, 0)))
	skel.set_bone_rest(leg, Transform3D(Basis(), Vector3(0, -0.4, 0)))
	skel.set_bone_rest(finger, Transform3D(Basis(), Vector3(0.05, 0, 0)))
	get_root().add_child(skel)

	var rag = RagdollSkeletonScript.new()
	var n: int = rag.build(skel, 8)
	if n <= 0:
		print("CHECK FAIL: не создано ни одной физкости"); ok = false

	# Собрать имена созданных PhysicalBone3D.
	var pb_names := {}
	var has_capsule := true
	for c in skel.get_children():
		if c is PhysicalBone3D:
			pb_names[c.bone_name] = true
			var cap := false
			for cc in c.get_children():
				if cc is CollisionShape3D and cc.shape is CapsuleShape3D:
					cap = true
			if not cap:
				has_capsule = false
	if not has_capsule:
		print("CHECK FAIL: у физкости нет CapsuleShape3D"); ok = false
	# Палец должен быть исключён (нет физкости, названной как палец, и он лист в любом случае).
	for name in pb_names.keys():
		if String(name).to_lower().contains("index") or String(name).to_lower().contains("finger"):
			print("CHECK FAIL: пальцевая кость не исключена: ", name); ok = false
	# Должна быть физкость хотя бы для Hips и LeftUpLeg (не-листовые).
	if not pb_names.has("mixamorig:Hips"):
		print("CHECK FAIL: нет физкости для Hips"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ragdoll_build.gd"`
Expected: FAIL — `ragdoll_skeleton.gd` ещё не существует (parse/load error).

- [ ] **Step 3: Написать `RagdollSkeleton`**

Создать `scripts/player/ragdoll_skeleton.gd`:

```gdscript
class_name RagdollSkeleton
extends RefCounted

## Кости, которые не превращаем в физкости (мелкие → взрыв солвера, невидимы с камеры).
const SKIP_SUBSTRINGS := ["Hand", "Finger", "Toe", "Thumb", "Index", "Middle", "Ring", "Pinky"]

var _skeleton: Skeleton3D
var _bones: Array = []          # созданные PhysicalBone3D
var _hip: PhysicalBone3D
var _active: bool = false

func _skip(bone_name: String) -> bool:
	for s in SKIP_SUBSTRINGS:
		if bone_name.contains(s):
			return true
	return false

## Первый не-исключённый ребёнок кости (для размера капсулы), или -1.
func _first_child(skel: Skeleton3D, bone_id: int) -> int:
	for b in skel.get_bone_count():
		if skel.get_bone_parent(b) == bone_id and not _skip(skel.get_bone_name(b)):
			return b
	return -1

## Построить дремлющий физскелет как детей skeleton. Одна физкость на не-листовую
## не-исключённую кость; капсула тянется к её первому ребёнку. Возвращает число костей.
func build(skeleton: Skeleton3D, layer: int) -> int:
	_skeleton = skeleton
	for bone_id in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone_id)
		if _skip(bone_name):
			continue
		var child := _first_child(skeleton, bone_id)
		if child < 0:
			continue  # лист — накрыт капсулой родителя
		var child_rest := skeleton.get_bone_rest(child)
		var length := maxf(child_rest.origin.length(), 0.05)
		var pb := PhysicalBone3D.new()
		pb.bone_name = bone_name
		pb.collision_layer = layer
		pb.collision_mask = 1                       # только пол (слой1)
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_PIN  # старт: свободные пины (стабильно);
		                                               # cone-лимиты — живой тюнинг
		# Капсула вдоль направления к ребёнку, центр на середине кости.
		var dir := child_rest.origin.normalized()
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.height = length
		cap.radius = clampf(length * 0.18, 0.03, 0.12)
		cs.shape = cap
		cs.transform = Transform3D(_axis_to(dir), dir * length * 0.5)
		pb.add_child(cs)
		skeleton.add_child(pb)
		_bones.append(pb)
		if bone_name.to_lower().contains("hips"):
			_hip = pb
	if _hip == null and not _bones.is_empty():
		_hip = _bones[0]
	return _bones.size()

## Базис, ставящий локальную ось Y капсулы вдоль dir.
func _axis_to(dir: Vector3) -> Basis:
	var y := dir
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func start(impulse: Vector3) -> void:
	if _skeleton == null or _bones.is_empty():
		return
	_skeleton.physical_bones_start_simulation()
	_active = true
	if _hip != null:
		_hip.apply_central_impulse(impulse)

func stop() -> void:
	if _skeleton == null:
		return
	_skeleton.physical_bones_stop_simulation()
	_active = false

func active() -> bool:
	return _active

## Мировая позиция таза (для ведения CharacterBody3D за ragdoll и снапа при вставании).
func hip_position() -> Vector3:
	if _hip != null:
		return _hip.global_position
	if _skeleton != null:
		return _skeleton.global_position
	return Vector3.ZERO
```

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_ragdoll_build.gd"`
Expected: `CHECK PASS`, exit 0.

- [ ] **Step 5: Проверить загрузку проекта headless**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без ошибок скриптов.

- [ ] **Step 6: Коммит**

```bash
git add scripts/player/ragdoll_skeleton.gd tests/check_ragdoll_build.gd
git commit -m "feat(ragdoll): RagdollSkeleton builder (physical bones from Skeleton3D)"
```

---

## Task 4: `PlayerVisual` — API ragdoll/вставания + one-shot стейты

**Files:**
- Modify: `scripts/player/player_visual.gd`

**Interfaces:**
- Consumes: `RagdollSkeleton` (Task 3); `FootballConstants.RAGDOLL_COLLISION_LAYER` (Task 2).
- Produces (зовётся `match_manager` в Task 5):
  - `func start_ragdoll(impulse: Vector3) -> void`
  - `func ragdoll_active() -> bool`
  - `func ragdoll_hip_position() -> Vector3`
  - `func end_ragdoll() -> void` — стоп физики, разлочка выбора стейта локомоции.
  - `func play_oneshot(clip: StringName) -> float` — travel в one-shot стейт, возвращает длину клипа (сек).
  - Регистрация стейтов `tackle`/`roll_left`/`roll_right`/`standing_up`.

- [ ] **Step 1: Зарегистрировать one-shot стейты вставания/подката**

1a. В `scripts/player/player_visual.gd` после строки `const LOOP_CLIPS := [&"idle", &"run", &"sprint", &"fallen_idle"]` добавить:

```gdscript
## Дополнительные one-shot клипы (подкат/перекаты/вставание): travel-only, без авто-возврата —
## цепочку падения ведёт match_manager по длине клипов.
const ONESHOT_CLIPS := [&"tackle", &"roll_left", &"roll_right", &"standing_up"]
```

1b. В `_build_anim_tree`, сразу после цикла `for action in ACTION_CLIPS:` (после строки `_states[clip] = true`, перед комментарием `# Оборачиваем StateMachine...`) добавить регистрацию one-shot стейтов:

```gdscript
	for clip in ONESHOT_CLIPS:
		var cs: String = String(clip)
		if not ap.has_animation(cs) or _states.has(cs):
			continue
		var onode := AnimationNodeAnimation.new()
		onode.animation = clip
		sm.add_node(cs, onode, Vector2(120, y))
		y += 80.0
		sm.add_transition(LOCOMOTION, cs, _make_transition(false))
		sm.add_transition(cs, LOCOMOTION, _make_transition(false))
		_states[cs] = true
```

- [ ] **Step 2: Добавить поля ragdoll и fall-lock**

2a. После `var _action_contact_done: bool = false` добавить:

```gdscript
var _skeleton: Skeleton3D
var _ragdoll: RagdollSkeleton
var _fall_lock: bool = false   # пока true — _process не выбирает стейт локомоции (ведёт fall-цепочка)
```

2b. В `_ready`, после успешного `_build_anim_tree(ap)` (после строки `_last_pos = global_position`) добавить поиск скелета и построение дремлющего ragdoll:

```gdscript
	_skeleton = _find_skeleton(_model)
	if _skeleton != null:
		_ragdoll = RagdollSkeleton.new()
		var n := _ragdoll.build(_skeleton, FootballConstants.RAGDOLL_COLLISION_LAYER)
		if n == 0:
			_ragdoll = null
			push_warning("PlayerVisual: физскелет не построен (0 костей)")
	else:
		push_warning("PlayerVisual: нет Skeleton3D — ragdoll недоступен")
```

- [ ] **Step 3: Добавить хелпер поиска Skeleton3D**

После функции `_find_anim_player` добавить:

```gdscript
func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
```

- [ ] **Step 4: Подавить выбор стейта локомоции во время fall**

В `_process` найти строку:

```gdscript
	if _active_action == "" and _playback != null:
```

заменить на:

```gdscript
	if _active_action == "" and not _fall_lock and _playback != null:
```

- [ ] **Step 5: Добавить публичный API ragdoll/вставания**

После функции `cancel_action` (перед `_set_action_speed`) добавить:

```gdscript
## Запустить физ-ragdoll: физика перехватывает скелет, импульс в таз. Блокирует выбор
## стейта локомоции (его вернёт end_ragdoll).
func start_ragdoll(impulse: Vector3) -> void:
	if _ragdoll == null:
		return
	_fall_lock = true
	_active_action = ""
	_ragdoll.start(impulse)

func ragdoll_active() -> bool:
	return _ragdoll != null and _ragdoll.active()

## Мировая позиция таза (для ведения тела за ragdoll / снапа при вставании).
func ragdoll_hip_position() -> Vector3:
	if _ragdoll != null:
		return _ragdoll.global_transform_hip()
	return global_position

## Остановить физику (анимация снова владеет скелетом). _fall_lock снимет recover().
func stop_ragdoll() -> void:
	if _ragdoll != null:
		_ragdoll.stop()

## Проиграть one-shot клип (подкат/перекат/вставание). Возвращает длину клипа (сек);
## 0.0, если клипа/стейта нет. Цепочку и тайминг ведёт вызывающий (match_manager).
func play_oneshot(clip: StringName) -> float:
	if _playback == null or not _states.has(String(clip)):
		return 0.0
	_fall_lock = true
	_active_action = ""
	_playback.travel(clip)
	if _ap != null and _ap.has_animation(clip):
		return _ap.get_animation(clip).length
	return 0.0

## Завершить падение: вернуть idle и снять fall-lock (возобновить локомоцию).
func recover() -> void:
	_fall_lock = false
	if _playback != null:
		_playback.travel(LOCOMOTION)
```

Примечание: `start_ragdoll` использует `ragdoll_hip_position()` через `RagdollSkeleton`. В `RagdollSkeleton` метод называется `hip_position()`. Поправить вызов: в `ragdoll_hip_position()` заменить `_ragdoll.global_transform_hip()` на `_ragdoll.hip_position()`.

- [ ] **Step 6: Исправить имя вызова hip_position**

В только что добавленном `ragdoll_hip_position()` строку `return _ragdoll.global_transform_hip()` заменить на:

```gdscript
		return _ragdoll.hip_position()
```

- [ ] **Step 7: Проверить загрузку проекта headless**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без ошибок скриптов.

- [ ] **Step 8: Коммит**

```bash
git add scripts/player/player_visual.gd
git commit -m "feat(ragdoll): PlayerVisual ragdoll + one-shot getup/tackle clip API"
```

---

## Task 5: Автомат падения жертвы в `match_manager`

**Files:**
- Modify: `scripts/match/match_manager.gd`

**Interfaces:**
- Consumes: `PlayerVisual.start_ragdoll/ragdoll_active/ragdoll_hip_position/stop_ragdoll/play_oneshot/recover` (Task 4); `PlayerMotor.find_on` + `set_control_locked` (существуют); `FootballConstants.RAGDOLL_*`, `ROLL_DISTANCE`, `PRONE_BLEND_TIME` (Task 2).
- Produces: конечный автомат падения сбитого игрока (замена капсульного наклона).

- [ ] **Step 1: Добавить состояние падения и поля**

1a. В `scripts/match/match_manager.gd` рядом с `enum TackleState { NORMAL, SLIDING, RECOVERING }` (строка ~18) добавить:

```gdscript
enum FallState { NONE, RAGDOLL, PRONE_BLEND, ROLL_1, ROLL_2, GETUP }
```

1b. Рядом с полями `_tackled_*` (строки ~31–33) добавить:

```gdscript
var _fall_state: FallState = FallState.NONE
var _fall_player: CharacterBody3D
var _fall_visual: PlayerVisual
var _fall_timer: float = 0.0
var _fall_away_dir: Vector3 = Vector3.ZERO   # горизонталь: от подкатчика к жертве
var _fall_roll_clip: StringName = &"roll_left"
var _fall_hip_prev: Vector3 = Vector3.ZERO
```

- [ ] **Step 2: Заменить капсульное падение на запуск ragdoll в `_on_tackle_hit_player`**

В `_on_tackle_hit_player` (строка ~893) заменить блок от `# Push tackled player back` до конца функции:

```gdscript
	# Push tackled player back
	body.global_position += normal.normalized() * FootballConstants.SLIDE_TACKLE_FALL_DISTANCE

	# Fall over (if already fallen, extend timer slightly instead of resetting)
	if body.is_in_group("fallen"):
		_tackled_fall_timer = max(_tackled_fall_timer, 0.5)
		return
	_tackled_player = body
	_tackled_orig_rotation = body.rotation
	body.rotation.x = deg_to_rad(90)
	_tackled_fall_timer = FootballConstants.SLIDE_TACKLE_FALL_TIME
	body.add_to_group("fallen")
	_cancel_ball_action(body)
```

на:

```gdscript
	# Уже падает — не перезапускаем цепочку.
	if body.is_in_group("fallen"):
		return
	_begin_fall(body, normal)
```

- [ ] **Step 3: Реализовать `_begin_fall` и `_player_visual` использование**

Добавить функцию (например, сразу после `_on_tackle_hit_player`):

```gdscript
## Запустить физ-ragdoll падение жертвы + завести автомат вставания.
func _begin_fall(body: CharacterBody3D, normal: Vector3) -> void:
	var visual := _player_visual(body)
	if visual == null or not visual.has_method(&"start_ragdoll"):
		# Фолбэк: нет визуала/ragdoll — просто помечаем fallen на короткое время.
		body.add_to_group("fallen")
		_fall_player = body
		_fall_visual = null
		_fall_state = FallState.GETUP
		_fall_timer = 0.8
		return
	body.add_to_group("fallen")
	_cancel_ball_action(body)
	var motor := PlayerMotor.find_on(body)
	if motor != null:
		motor.set_control_locked(true)

	# away-направление (от подкатчика к жертве), горизонталь.
	var away := body.global_position - _tackle_player.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = _tackle_dir
	_fall_away_dir = away.normalized()
	# Сторона переката: знак векторного (fall_away × up) относительно взгляда тела.
	var side := _fall_away_dir.cross(Vector3.UP)
	var facing := -body.global_transform.basis.z
	_fall_roll_clip = &"roll_left" if side.dot(facing) >= 0.0 else &"roll_right"

	# Импульс сбивания: вдоль подката + вверх.
	var impulse := _tackle_dir * FootballConstants.RAGDOLL_TACKLE_IMPULSE \
		+ Vector3.UP * FootballConstants.RAGDOLL_UP_IMPULSE
	_fall_player = body
	_fall_visual = visual
	_fall_hip_prev = visual.ragdoll_hip_position()
	visual.start_ragdoll(impulse)
	_fall_state = FallState.RAGDOLL
	_fall_timer = 0.0
```

- [ ] **Step 4: Заменить старый блок падения в `_physics_process` на автомат**

В `_physics_process` (строки ~514–524) заменить блок `# Handle tackled player fall`:

```gdscript
	# Handle tackled player fall
	if _tackled_player and is_instance_valid(_tackled_player):
		if _tackled_fall_timer > 0:
			_tackled_fall_timer -= delta
		else:
			_tackled_player.rotation.x = move_toward(_tackled_player.rotation.x,
				_tackled_orig_rotation.x, 3.0 * delta)
			if abs(_tackled_player.rotation.x - _tackled_orig_rotation.x) < 0.01:
				_tackled_player.rotation.x = _tackled_orig_rotation.x
				_tackled_player.remove_from_group("fallen")
				_tackled_player = null
```

на:

```gdscript
	# Автомат падения сбитого игрока (ragdoll → на живот → 2 переката → вставание).
	_process_fall(delta)
```

- [ ] **Step 5: Реализовать `_process_fall`**

Добавить функцию (например, после `_begin_fall`):

```gdscript
func _process_fall(delta: float) -> void:
	if _fall_state == FallState.NONE:
		return
	if _fall_player == null or not is_instance_valid(_fall_player):
		_fall_state = FallState.NONE
		return
	_fall_timer += delta

	match _fall_state:
		FallState.RAGDOLL:
			# Тело XZ ведём за тазом ragdoll.
			var hip := _fall_visual.ragdoll_hip_position()
			_fall_player.global_position.x = hip.x
			_fall_player.global_position.z = hip.z
			var hip_speed := (hip - _fall_hip_prev).length() / maxf(delta, 0.0001)
			_fall_hip_prev = hip
			var settled := hip_speed < FootballConstants.RAGDOLL_SETTLE_SPEED \
				and _fall_timer >= FootballConstants.RAGDOLL_MIN_DOWN_TIME
			if settled or _fall_timer >= FootballConstants.RAGDOLL_MAX_DOWN_TIME:
				# Нормализация: снап тела в XZ таза, yaw «лицом вниз по направлению падения»,
				# стоп физики и кроссфейд в первый кадр цепочки.
				_fall_player.global_position.x = hip.x
				_fall_player.global_position.z = hip.z
				_fall_player.rotation.y = atan2(-_fall_away_dir.x, -_fall_away_dir.z)
				_fall_visual.stop_ragdoll()
				_fall_state = FallState.PRONE_BLEND
				_fall_timer = 0.0
		FallState.PRONE_BLEND:
			if _fall_timer >= FootballConstants.PRONE_BLEND_TIME:
				_start_roll(FallState.ROLL_1)
		FallState.ROLL_1:
			_advance_roll(delta, FallState.ROLL_2)
		FallState.ROLL_2:
			_advance_roll(delta, FallState.GETUP, true)
		FallState.GETUP:
			if _fall_visual != null:
				# double-проверка: standing_up доигрался?
				if _fall_timer >= _getup_len:
					_finish_fall()
			else:
				if _fall_timer >= 0.8:  # фолбэк-ветка без визуала
					_finish_fall()
```

- [ ] **Step 6: Реализовать `_start_roll`, `_advance_roll`, `_finish_fall` + поле длины**

6a. Рядом с полями падения (Step 1b) добавить:

```gdscript
var _roll_len: float = 0.5
var _getup_len: float = 1.0
```

6b. Добавить функции:

```gdscript
## Запустить перекат: играем клип, запоминаем длину, обнуляем таймер шага.
func _start_roll(next_state: FallState) -> void:
	_roll_len = _fall_visual.play_oneshot(_fall_roll_clip)
	if _roll_len <= 0.0:
		_roll_len = 0.5
	_fall_timer = 0.0
	_fall_state = next_state if next_state != FallState.ROLL_1 else FallState.ROLL_1
	# Примечание: next_state здесь — состояние, В КОТОРОМ мы проигрываем этот перекат.
	_fall_state = FallState.ROLL_1 if next_state == FallState.ROLL_1 else next_state

## Продвигать активный перекат: смещать тело в сторону away, по концу клипа — следующий шаг.
func _advance_roll(delta: float, next_state: FallState, to_getup: bool = false) -> void:
	# Равномерное боковое смещение за время клипа.
	var move := _fall_away_dir * (FootballConstants.ROLL_DISTANCE / maxf(_roll_len, 0.0001)) * delta
	_fall_player.global_position += move
	if _fall_timer >= _roll_len:
		if to_getup:
			_getup_len = _fall_visual.play_oneshot(&"standing_up")
			if _getup_len <= 0.0:
				_getup_len = 1.0
			_fall_timer = 0.0
			_fall_state = FallState.GETUP
		else:
			# Запустить второй перекат.
			_roll_len = _fall_visual.play_oneshot(_fall_roll_clip)
			if _roll_len <= 0.0:
				_roll_len = 0.5
			_fall_timer = 0.0
			_fall_state = next_state

## Завершить падение: вернуть idle, снять fallen, разлочить motor.
func _finish_fall() -> void:
	if _fall_visual != null:
		_fall_visual.recover()
	if is_instance_valid(_fall_player):
		_fall_player.remove_from_group("fallen")
		var motor := PlayerMotor.find_on(_fall_player)
		if motor != null:
			motor.set_control_locked(false)
	_fall_player = null
	_fall_visual = null
	_fall_state = FallState.NONE
```

Примечание к `_start_roll`: упростить тело функции до однозначного (перезаписи `_fall_state` выше избыточны). Итоговая версия `_start_roll`:

```gdscript
func _start_roll(state_while_rolling: FallState) -> void:
	_roll_len = _fall_visual.play_oneshot(_fall_roll_clip)
	if _roll_len <= 0.0:
		_roll_len = 0.5
	_fall_timer = 0.0
	_fall_state = state_while_rolling
```

И вызвать `_start_roll(FallState.ROLL_1)` из `PRONE_BLEND` (уже так в Step 5).

- [ ] **Step 7: Проверить загрузку проекта headless**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без ошибок скриптов. (Если парсер ругается на `_player_visual` — убедиться, что функция существует; она есть по спеку локомоции. Если нет — использовать `PlayerMotor.find_on`-подобный поиск `PlayerVisual` среди детей body.)

- [ ] **Step 8: Ручная проверка (человек)**

Запустить игру. Подкатить ИИ-соперника (подвести управляемого, Space/тайминг — как обычный подкат под мяч у соперника). Проверить:
- Жертва **физически падает** (ragdoll), а не наклоняется капсулой.
- После оседания — **два переката в сторону ОТ подкатчика**, затем `standing_up` и возврат в `idle`.
- Тело жертвы оказывается там, где легло (камера/индикатор адекватны).
- Мяч выбивается как раньше.

Записать наблюдения по тюнингу: `RAGDOLL_TACKLE_IMPULSE`, `RAGDOLL_MIN/MAX_DOWN_TIME`, `PRONE_BLEND_TIME`, `ROLL_DISTANCE`. Если ragdoll «взрывается» — уменьшить `RAGDOLL_MAX_DOWN_TIME`, при необходимости расширить `SKIP_SUBSTRINGS` или задать cone-лимиты в `RagdollSkeleton`.

- [ ] **Step 9: Коммит**

```bash
git add scripts/match/match_manager.gd
git commit -m "feat(ragdoll): victim fall state machine (ragdoll -> prone -> 2 rolls -> getup)"
```

---

## Task 6: Подкатчик на клип `tackle` + чистка старого кода

**Files:**
- Modify: `scripts/match/match_manager.gd`
- Modify: `scripts/data/football_constants.gd`

**Interfaces:**
- Consumes: `PlayerVisual.play_oneshot/recover` (Task 4).
- Produces: подкатчик проигрывает in-place `tackle`; удалены капсульный наклон подкатчика, мёртвые поля/константы, debug-принты.

- [ ] **Step 1: Подкатчик играет клип `tackle` вместо наклона капсулы**

1a. В `_start_tackle` найти:

```gdscript
	_tackle_player_orig_rotation = player.rotation
	player.rotation.x = deg_to_rad(90)
```

заменить на:

```gdscript
	var tackler_visual := _player_visual(player)
	if tackler_visual != null and tackler_visual.has_method(&"play_oneshot"):
		tackler_visual.play_oneshot(&"tackle")
```

1b. В `_tackle_recover` найти блок лерпа наклона:

```gdscript
	# Lerp capsule rotation back to original
	_tackle_player.rotation.x = lerp_angle(_tackle_player.rotation.x,
		_tackle_player_orig_rotation.x, 5.0 * delta)
```

удалить его.

1c. В `_tackle_recover`, где такл завершается (`if _tackle_recovery_timer <= 0.0:`), найти:

```gdscript
		_tackle_player.rotation = _tackle_player_orig_rotation
```

заменить на возврат визуала в idle:

```gdscript
		var trec_visual := _player_visual(_tackle_player)
		if trec_visual != null and trec_visual.has_method(&"recover"):
			trec_visual.recover()
```

- [ ] **Step 2: Удалить мёртвые поля и константы капсульного падения**

2a. В `scripts/match/match_manager.gd` удалить неиспользуемые после Task 5 поля:

```gdscript
var _tackled_player: CharacterBody3D
var _tackled_fall_timer: float = 0.0
var _tackled_orig_rotation: Vector3 = Vector3.ZERO
```

и `var _tackle_player_orig_rotation: Vector3 = Vector3.ZERO` (наклон подкатчика больше не используется).

2b. В `scripts/data/football_constants.gd` удалить:

```gdscript
const SLIDE_TACKLE_FALL_DISTANCE := 2.0
const SLIDE_TACKLE_FALL_TIME := 1.0
```

Убедиться (grep), что `SLIDE_TACKLE_FALL_DISTANCE`/`SLIDE_TACKLE_FALL_TIME` больше нигде не упоминаются:
Run: `grep -rn "SLIDE_TACKLE_FALL" scripts/`
Expected: пусто.

- [ ] **Step 3: Убрать debug-принты такла**

Удалить все строки `print("[TACKLE_DEBUG] ...")` в `scripts/match/match_manager.gd` (в `_try_tackle`, `_start_tackle`). Проверить:
Run: `grep -rn "TACKLE_DEBUG" scripts/`
Expected: пусто.

- [ ] **Step 4: Проверить загрузку проекта headless**

Run: `& "C:\Users\User\AppData\Local\Godot\Godot_v4.7-stable_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
Expected: без ошибок скриптов.

- [ ] **Step 5: Ручная проверка (человек)**

Запустить игру. Проверить: подкатчик во время слайда проигрывает анимацию `tackle` (не тыкается капсулой на 90°), по окончании `RECOVERING` возвращается в норму; вся цепочка падения жертвы из Task 5 по-прежнему работает.

- [ ] **Step 6: Коммит**

```bash
git add scripts/match/match_manager.gd scripts/data/football_constants.gd
git commit -m "feat(ragdoll): tackler plays tackle clip; remove capsule-fall code, debug prints"
```

---

## Self-Review

**1. Покрытие спека:**
- §1 Пол + отказ от пина Y → Task 2 (floor + gravity_step + PlayerMotor). ✅
- §2 In-place конвертация (`tackle`/`roll_left`/`roll_right`, не `standing_up`) + пересборка + тест → Task 1. ✅
- §3 `RagdollSkeleton` (полный скелет кодом, без пальцев, слой 4, маска = пол) + тест → Task 3. ✅
- §4 Автомат `RAGDOLL → PRONE_BLEND → ROLL_1 → ROLL_2 → GETUP`, роллы от подкатчика, нормализация на живот, ведение тела за тазом → Task 5. ✅
- §4 Подкатчик играет `tackle`, убран `rotation.x=90` → Task 6. ✅
- §5 Константы `GRAVITY`/`RAGDOLL_*`/`ROLL_DISTANCE`/`PRONE_BLEND_TIME` → Task 2; удаление `SLIDE_TACKLE_FALL_*` → Task 6; слои (bit4=8, маска пол) → Task 2/3; тесты headless (in-place, gravity_step, ragdoll build) → Tasks 1/2/3; чистка `[TACKLE_DEBUG]` → Task 6. ✅
- Вне рамок (фолы/судья/карточки, ragdoll подкатчика, стоячий отбор, foot IK) — не включено. ✅

**2. Плейсхолдеры:** код приведён целиком в каждом шаге. `_start_roll` даёт финальную однозначную версию в Step 6 (промежуточные перезаписи `_fall_state` заменены). Порогов «TODO/TBD» нет.

**3. Согласованность типов/имён:**
- `RagdollSkeleton.build(skeleton, layer) -> int`, `start(impulse)`, `stop()`, `active()`, `hip_position()` — совпадают между Task 3 и вызовами в Task 4. ✅ (В Task 4 Step 5 намеренная опечатка `global_transform_hip()` исправляется в Step 6 на `hip_position()`.)
- `PlayerVisual.start_ragdoll/ragdoll_active/ragdoll_hip_position/stop_ragdoll/play_oneshot(clip)->float/recover` — определены в Task 4, зовутся в Task 5/6. ✅
- `PlayerMotor.gravity_step(vy, grounded, gravity, delta)` — Task 2 определяет и тестирует, использует в `_physics_process`. ✅
- `FallState { NONE, RAGDOLL, PRONE_BLEND, ROLL_1, ROLL_2, GETUP }`, поля `_fall_*` — согласованы внутри Task 5. ✅
- Константы `RAGDOLL_TACKLE_IMPULSE`/`RAGDOLL_UP_IMPULSE`/`RAGDOLL_SETTLE_SPEED`/`RAGDOLL_MIN_DOWN_TIME`/`RAGDOLL_MAX_DOWN_TIME`/`PRONE_BLEND_TIME`/`ROLL_DISTANCE`/`RAGDOLL_COLLISION_LAYER`/`GRAVITY` — имена совпадают между Task 2 (объявление) и Tasks 3/5 (использование). ✅

**Заметки-риски (живой тюнинг, не блокеры):**
- **Стык физика→анимация** (PRONE_BLEND): кроссфейд может быть заметен; смягчается ростом `PRONE_BLEND_TIME` (Task 5 Step 8).
- **Стабильность ragdoll**: пин-джойнты стартово; при взрыве — cone-лимиты в `RagdollSkeleton` или расширение `SKIP_SUBSTRINGS` (Task 5 Step 8).
- **`_player_visual`**: план предполагает наличие хелпера (есть по локомоции); Task 5 Step 7 содержит фолбэк-указание, если имя иное.

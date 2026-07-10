# Physical Ragdoll Tackle — Fall, Roll & Get-Up

> Дизайн-спек. Заменяет «капсульное» падение из `2026-07-08-physical-tackle-design.md`
> (там ragdoll был явно вынесен в «Future») настоящим скелетным ragdoll на `PhysicalBone3D`.
> Ветка: `feat/living-locomotion`. Godot 4.7 / GDScript.

## Цель

Подкат сбивает соперника **физичным ragdoll**-падением, после чего проигрывается
авторская цепочка: игрок падает на живот → **два переката в сторону от подкатчика** →
`standing_up` → `idle`. Подкатчик проигрывает in-place клип `tackle` во время слайда.
Мяч выбивается (существующая логика pop-off сохраняется).

Подход — **гибрид**: физика владеет коротким моментом удара/падения, дальше — авторская
анимация (предсказуемое вставание). В ragdoll уходит **только жертва**; подкатчик — нет.

## Ключевые решения (зафиксированы в брейншторме)

1. **Гибрид** физика→анимация, не постоянная физсимуляция.
2. **В ragdoll только сбитый** игрок. Подкатчик — анимация `tackle` + `RECOVERING`.
3. **Полный скелет** `PhysicalBone3D` (без пальцев рук/ног — стабильность).
4. **Переход на пол-коллайдер**: добавляем настоящий статический пол, `PlayerMotor`
   перестаёт вручную пиннить Y. Один общий «газон» для локомоции и для приземления ragdoll.
5. Хореография: удар (физика) → нормализация в позу «лёжа на животе» → `roll`×2 (в сторону
   от подкатчика) → `standing_up` → `idle`.

---

## Разделение ответственности

- **`match_manager.gd`** — оркестратор такла (детект контакта, направление, pop-off мяча,
  группа `fallen`, тайминги, конечный автомат падения жертвы). Меняем ветку физического
  такла и добавляем создание пола.
- **`PlayerVisual` (`player_visual.gd`)** — презентация. Новый публичный API:
  `start_ragdoll(impulse: Vector3)`, `ragdoll_active() -> bool`,
  `ragdoll_hip_position() -> Vector3`, `blend_to_prone(fall_yaw: float)`,
  `play_getup_step(clip: StringName)`, `recover()`. Реализует зарезервированный
  `set_flag("fallen", on)`.
- **`RagdollSkeleton` (`scripts/player/ragdoll_skeleton.gd`, новый, `class_name`)** — чистый
  строитель: по `Skeleton3D` генерирует `PhysicalBone3D` + капсулы + джойнты, умеет
  `start(impulse)` / `stop()` / `hip_position()` / `total_speed()`. Изолирован, чтобы
  `player_visual.gd` не распухал и билд-логику можно было тюнить/тестировать отдельно.

`CharacterBody3D` + коллайдер + AI-скрипт жертвы — не трогаем (кроме control-lock через
существующий `PlayerMotor`).

---

## 1. Пол-коллайдер и отказ от ручного пина Y

**Сейчас:** гравитации нет; `PlayerMotor._physics_process` делает
`global_position.y = _ground_y` каждый кадр (кроме `fallen`). Пола-коллайдера нет.

**Становится:**

- В `match_manager._ready()` создаём `StaticBody3D` с `CollisionShape3D`
  (`WorldBoundaryShape3D`, нормаль +Y, плоскость y=0). Слой коллизий — `1` (это «газон»,
  как и пич/мяч; см. заметку про слои ниже).
- `PlayerMotor`:
  - Убираем поле `_ground_y` и строку `_body.global_position.y = _ground_y`.
  - Добавляем вертикаль: `velocity.y -= GRAVITY * delta` перед `move_and_slide()`;
    `_body.floor_snap_length` задаём небольшим (напр. 0.3), `_body.up_direction = Vector3.UP`.
    Горизонтальная интеграция (`desired_velocity`/`integrate_velocity`/разворот/banking) —
    **без изменений**; velocity.y мы отдельно накапливаем и обнуляем при `is_on_floor()`.
  - Пока тело в группе `fallen`, `PlayerMotor` control-locked — не двигает тело; позицию
    ведёт `match_manager` (см. §4). Спец-случай «пин кроме fallen» исчезает сам.
- **Проверка:** капсула тела встаёт на пол на прежней визуальной высоте (геометрия капсулы
  CollisionShape3D — центр на y≈0.5). Если тонет/висит — правим высоту/offset капсулы, не пол.

Новая константа: `GRAVITY := 20.0` (аркадная, м/с²; тюнинг-старт).

---

## 2. Конвертация анимаций в in-place (пайплайн Blender)

Новые/пересобираемые клипы: `tackle`, `roll_left`, `roll_right` — приехали с root motion
(Hips едет), из-за чего модель уезжает от тела. `standing_up` **уже in-place** — не трогаем.

- В `tools/merge_mixamo.py` добавляем `IN_PLACE_CLIPS = {"tackle", "roll_left", "roll_right"}`.
  Для клипа из набора после импорта **замораживаем горизонтальную трансляцию корневой кости**
  (Hips): на f-curve `location` (индексы X и Z) ставим значение каждого кейфрейма равным
  значению первого кадра. Y (вертикальный боб) сохраняем. Дрейф убирается, стартовая поза цела.
- Роллы держим in-place намеренно: боковое смещение тела при перекате даём **кодом**
  (`ROLL_DISTANCE` в сторону от подкатчика) — так контролируем направление.
- Пересборка: Blender 5.1 merge → `footballer.glb`, затем Godot `--headless --import`.

**Тест:** `tests/check_tackle_in_place.gd` — для `tackle`/`roll_left`/`roll_right` в glb
разброс значений Hips по X и Z вдоль клипа < ε (нет горизонтального дрейфа). Плюс
`check_footballer_glb.gd` дополняем проверкой наличия `roll_left`/`roll_right`.

---

## 3. Строитель физскелета `RagdollSkeleton` (полный скелет, кодом)

Редакторную «Create Physical Skeleton» использовать нельзя (модель инстанцируется в рантайме,
glb переимпортируется). Строим кодом.

- Находим `Skeleton3D` внутри `Model` (рекурсивно, в `PlayerVisual._ready`).
- Для каждой **значимой** кости создаём `PhysicalBone3D` (child of `Skeleton3D`,
  `bone_name` = имя кости):
  - `CollisionShape3D` c `CapsuleShape3D`: длина = расстояние до дочерней кости, радиус —
    доля длины (тюнинг-константа); ориентация капсулы вдоль кости.
  - Трансформы `joint_offset` / `body_offset` считаем из rest-поз костей (повторяем
    математику редакторного генератора: соединение в суставе родитель↔ребёнок).
  - Тип джойнта: `JOINT_TYPE_CONE` для конечностей/шеи (с лимитами), корень (Hips) — свободный.
- **Исключаем** кости, чьё имя содержит `SKIP_BONE_SUBSTRINGS = ["Hand","Finger","Toe","ToeBase"]`
  — мелкие кости дают взрыв солвера и невидимы с трансляционной камеры. Это страховка от
  нестабильности при «полном скелете».
- Коллизии физкостей: слой `RAGDOLL_COLLISION_LAYER` (bit 4), маска = слой пола (`1`), чтобы
  падать на газон; **не** маскируют игроков и мяч (не расталкивают геймплей).
- Строим один раз при `_ready` (дремлющими: `physical_bones_stop_simulation()` не нужен,
  просто не стартуем). `start(impulse)` → `physical_bones_start_simulation()` + импульс в
  Hips/торс. `stop()` → `physical_bones_stop_simulation()`.

**Тест:** `tests/check_ragdoll_build.gd` — на синтетическом `Skeleton3D` строитель создаёт
N>0 `PhysicalBone3D`, у каждой валидный `get_bone_id()` и дочерний `CollisionShape3D` с
`CapsuleShape3D`; кости с `Finger`/`Toe` отсутствуют. (Физику/фил не проверяем — только структуру.)

---

## 4. Конечный автомат падения жертвы (`match_manager`)

Отдельный enum состояния сбитого игрока (в `match_manager`), т.к. это дольше и сложнее
подкатного `RECOVERING`:

```
FallState { NONE, RAGDOLL, PRONE_BLEND, ROLL_1, ROLL_2, GETUP, DONE }
```

Поля: `_fall_state`, `_fall_player: CharacterBody3D`, `_fall_visual: PlayerVisual`,
`_fall_timer`, `_fall_away_dir: Vector3` (горизонтальная away-от-подкатчика),
`_fall_roll_clip: StringName`.

Поток:

1. **Контакт** — `_on_tackle_hit_player(body, normal)`:
   - pop-off мяча (существующая ветка сохраняется).
   - Заменяем `body.rotation.x = deg_to_rad(90)` и `_tackled_*` на запуск падения:
     `_begin_fall(body, normal)`.
   - `_begin_fall`: `body.add_to_group("fallen")`, control-lock motor жертвы,
     `_cancel_ball_action(body)`, вычисляем `_fall_away_dir` = гориз. `(victim - tackler)`,
     выбираем `_fall_roll_clip` = `roll_left`/`roll_right` по знаку
     `cross(_fall_away_dir, UP)` относительно взгляда тела; `_fall_visual.start_ragdoll(impulse)`,
     где `impulse = _tackle_dir*RAGDOLL_TACKLE_IMPULSE + UP*RAGDOLL_UP_IMPULSE`;
     `_fall_state = RAGDOLL`.
2. **RAGDOLL** (в `_physics_process`): тело XZ ведём за `ragdoll_hip_position()`. Условие
   выхода: `total_speed() < RAGDOLL_SETTLE_SPEED` и `_fall_timer ≥ RAGDOLL_MIN_DOWN_TIME`,
   либо `_fall_timer ≥ RAGDOLL_MAX_DOWN_TIME`. → снап тела в финальный XZ таза,
   `_fall_visual.blend_to_prone(fall_yaw)` (стоп-симуляция, yaw тела «лицом вниз по направлению
   падения», кроссфейд ~`PRONE_BLEND_TIME` из позы, где осел ragdoll, в первый кадр цепочки).
   `_fall_state = PRONE_BLEND`.
3. **PRONE_BLEND** — ждём `PRONE_BLEND_TIME`, затем `play_getup_step(_fall_roll_clip)`,
   `_fall_state = ROLL_1`.
4. **ROLL_1 / ROLL_2** — на каждом за длительность клипа смещаем тело на `ROLL_DISTANCE`
   вдоль `_fall_away_dir` (клип in-place). По завершении клипа: ROLL_1 → снова
   `play_getup_step(_fall_roll_clip)` → ROLL_2; ROLL_2 → `play_getup_step(&"standing_up")` →
   `GETUP`.
5. **GETUP** — доигрывается `standing_up`; по завершении `_fall_visual.recover()` (→ `idle`),
   `body.remove_from_group("fallen")`, motor unlock, `_fall_state = DONE/NONE`.

Переходы по завершению клипов ловим через `PlayerVisual.action_finished` (переиспользуем
существующий one-shot тайминг-механизм) либо по таймеру длины клипа.

Старые поля/ветки капсульного падения (`_tackled_player`, `_tackled_fall_timer`,
`_tackled_orig_rotation`, лерп `rotation.x` в `_physics_process`) — удаляем.

### Подкатчик

- В `_start_tackle` убираем `player.rotation.x = deg_to_rad(90)`; вместо этого просим
  `PlayerVisual` подкатчика проиграть in-place клип `tackle` (новый one-shot стейт/`trigger`).
- В `_tackle_recover` убираем лерп `rotation.x` обратно (тело не наклонялось). Логика
  `RECOVERING`-таймера и возврата мяча — без изменений.

---

## 5. Константы, тесты, слои, вне рамок

### Константы (`football_constants.gd`)

Удаляем `SLIDE_TACKLE_FALL_DISTANCE`, `SLIDE_TACKLE_FALL_TIME` (капсульное падение).
Добавляем секцию:

```gdscript
# --- Ragdoll tackle (тюнинг-старт) ---
const GRAVITY := 20.0                 # аркадная гравитация, м/с²
const RAGDOLL_COLLISION_LAYER := 8    # bit4: физкости, маскируют только пол
const RAGDOLL_TACKLE_IMPULSE := 6.0   # сила сбивающего импульса вдоль подката
const RAGDOLL_UP_IMPULSE := 2.0       # вертикальная добавка импульса
const RAGDOLL_SETTLE_SPEED := 0.6     # ниже суммарной скорости костей → осел
const RAGDOLL_MIN_DOWN_TIME := 0.4    # минимум фазы физики, с
const RAGDOLL_MAX_DOWN_TIME := 1.5    # хард-кап фазы физики, с
const PRONE_BLEND_TIME := 0.2         # кроссфейд ragdoll→анимация, с
const ROLL_DISTANCE := 1.2            # смещение тела за один перекат, м
```

### Слои коллизий (важно — легко перепутать, см. CLAUDE.md)

- Layer 1: пич + мяч + **новый пол**.
- Layer 2 (`PLAYER_COLLISION_MASK`): полевые игроки.
- Layer 3 (`BOUNDARY_COLLISION_LAYER`): бортики.
- Layer 4 (`RAGDOLL_COLLISION_LAYER`): физкости ragdoll, маска = только слой 1 (пол).
  Не маскируют игроков/мяч/бортики.
- Фолбэк: если ragdoll задевает мяч на слое 1 некрасиво — вынести пол на отдельный слой и
  маскировать ragdoll только его.

### Тесты (headless — логика/структура, не физика/фил)

- `check_tackle_in_place.gd` — нет дрейфа Hips у `tackle`/`roll_left`/`roll_right`.
- `check_ragdoll_build.gd` — структура физскелета (N>0, валидные кости+капсулы, пальцы исключены).
- `check_footballer_glb.gd` — дополнить проверкой `roll_left`/`roll_right`.
- Фил падения/переката/вставания, стабильность джойнтов, приземление на пол — **только живым
  прогоном**.

### Вне рамок

- Фолы / судья / карточки (остаются закомментированы в `_on_tackle_body_entered`).
- Ragdoll подкатчика, стоячий отбор, foot IK, motion matching.
- Гарантия точной позы «на животе» из чистой физики (её даёт нормализация в PRONE_BLEND, а не
  сам ragdoll).

### Заодно (раз лезем в функцию)

- Чистим `print("[TACKLE_DEBUG] ...")` в tackle-коде `match_manager.gd`.

---

## Риски

1. **Стабильность полного ragdoll на Mixamo-пропорциях** — джойнт-лимиты и радиусы капсул под
   живой тюнинг; страховка — исключение пальцев, при необходимости сузить набор костей или
   уменьшить `RAGDOLL_MAX_DOWN_TIME`.
2. **Стык физика→анимация** (PRONE_BLEND) — если кроссфейд заметен, увеличить `PRONE_BLEND_TIME`
   или снапать скелет в prone-позу жёстче.
3. **Переход локомоции на гравитацию/пол** — риск дрожания/тонущей капсулы; смягчается
   `floor_snap_length` и проверкой геометрии капсулы. Горизонтальный фил не затрагивается.

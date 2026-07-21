# Вбрасывание из аута — дизайн (Фаза A)

**Дата:** 2026-07-22
**Статус:** согласован, готов к плану реализации.

## Что это

Розыгрыш аута: по клавише **T** ближайший к точке аута полевой игрок нашей команды (team_1)
встаёт за боковой линией с мячом в руках, человек камерой/стиком выбирает направление вброса
(сектор ±90° «в поле», назад нельзя), удержанием **A** задаёт силу (= дальность), и мяч летит
баллистической дугой. После выпуска управление переходит к тому, кому летит мяч, и игра
продолжается в обычном режиме.

Это тест-триггерный сет-пис (правил авто-детекта ухода мяча за линию пока нет), в одном ряду с
пенальти/штрафным/угловым/ударом от ворот. Строится по тем же паттернам: контроллер-автомат +
чистая математика + гейтинг в `match_manager`.

## Архитектура

Полный зеркальный аналог удара от ворот (`goal_kick_controller.gd` + `goal_kick_logic.gd`):

- **`scripts/match/throw_in_controller.gd`** (`extends Node`) — автомат `IDLE→SETUP→AIM→STRIKE`,
  читает `Input` напрямую, владеет мячом/камерой/power-bar на время розыгрыша. `setup(manager,
  ball, camera_pivot, power_bar)`-ится в `match_manager._ready`.
- **`scripts/match/throw_in_logic.gd`** (`class_name ThrowInLogic extends Object`) — чистая
  статическая геометрия, **никогда не читает `FootballConstants`** (тюнинг — параметрами), как
  `GoalKickLogic`/`PassSystem`/`KeeperLogic`. Headless-тестируема.
- Переиспользуем как есть: `FreeKickLogic.rotate_heading` (поворот направления с клампом ±arc),
  `FreeKickLogic.push_out_of_radius` (правило 2 м, оно же правило стенки 9.15 м),
  `PassSystem.launch_lob` + `KeeperLogic.drag_horizontal_speed` (дуга с поправкой на драг),
  `match_manager.assign_controlled_player` / `begin_pass_receive` (передача управления
  получателю), `PlayerVisual.get_hold_attachment` + `ball.catch` (мяч в руке).

### Новая способность `PlayerVisual`: `hold_pose(clip)`

Нужна стойка «первого кадра клипа» (замах с мячом за головой), которой сейчас нет (у пенальти
AIM-поза — обычный `idle`). Реализация: мгновенный переход на кадр 0 (`_playback.start(state)`,
без кроссфейда) + заморозка времени (`TimeScale = 0`) + `_fall_lock = true` (чтобы селектор
локомоции не сдёрнул обратно в idle). Снятие — обычный `trigger("throw_in")`, который сбрасывает
`_fall_lock` и восстанавливает скорость проигрывания, и клип идёт вперёд с кадра 0.

## Поток розыгрыша

1. **Триггер (T).** `match_manager._physics_process`: если ни один сет-пис не активен и не идёт
   празднование гола (`not _celebrating`) — `_throw_in.start()`.
2. **SETUP.**
   - Точка аута = проекция мяча на ближайшую боковую линию: `X = ±HALF_FIELD_WIDTH` (знак = знак
     `ball.x`), `Z` = `ball.z`, `Y = BALL_RADIUS`.
   - Вбрасывающий = ближайший к точке аута полевой игрок team_1 (вратарь исключён по группе
     `role_gk`). Ставится за линией снаружи поля (`точка − в_поле·THROW_BEHIND_OFFSET`), лицом в
     поле; мотор залочен.
   - Базовое направление = перпендикуляр к линии, внутрь поля (`-X` для линии `+34`, `+X` для
     `−34`).
   - Мяч в руку вбрасывающего: `ball.catch(thrower, visual.get_hold_attachment())` — пока `CAUGHT`
     мяч сам приклеен к кости кисти каждый кадр (гола забить нельзя — `is_caught()`-гейт створа).
   - Стойка замаха: `visual.hold_pose("throw_in")`.
   - Правило 2 м: каждого соперника вбрасывающего (группа определяется по группе вбрасывающего —
     без хардкода team_1/team_2, как в goal kick) ближе `THROW_ENCROACH_DIST` к точке вброса —
     вытолкнуть `FreeKickLogic.push_out_of_radius` и залочить его мотор.
   - Управление на вбрасывающего: `assign_controlled_player(thrower)`; заморозка полевого AI:
     `set_field_ai_active(false)` (вбрасывающий как `controlled_player` из заморозки исключён).
   - `set_throw_in_active(true)`.
3. **AIM.** Стик крутит **направление + тело + камеру вместе**, кламп ±90°
   (`FreeKickLogic.rotate_heading(heading, base, stick_x, THROW_AIM_SPEED, delta, THROW_AIM_ARC)`,
   `THROW_AIM_ARC = PI/2`); тело доворачивается `motor.set_face_direction(heading)`. Нажатие **A**
   (`pass_short`) = коммит: направление фиксируется, начинается набор силы (power-bar). **Пока
   держишь A — доворота нет.** Отпуск A (или полный заряд) → STRIKE.
4. **STRIKE.** `visual.trigger("throw_in")` (снимает заморозку позы, играет клип). На
   `action_contact` (тайминг `13/33` длины клипа, см. ниже) — выпуск мяча:
   - `land_dist = lerp(THROW_MIN_DIST, THROW_MAX_DIST, ratio)`, `peak = lerp(THROW_PEAK_MIN,
     THROW_PEAK_MAX, ratio)` вдоль зафиксированного направления;
   - дуга: `PassSystem.launch_lob` для `vy`/времени полёта, горизонталь — через
     `KeeperLogic.drag_horizontal_speed` (иначе недолёт под драгом), `ball.launch(vel, false)`;
   - `ball.note_kicker(thrower)` (мяч был `CAUGHT`, помечаем бьющего — анти-самоблок/кулдаун);
   - получатель = ближайший к точке приземления (`spot + heading·land_dist`) полевой team_1 (кроме
     вбрасывающего): `assign_controlled_player(receiver)` + `begin_pass_receive(receiver)` (сам
     выбегает на мяч, как при обычном пасе);
   - `_release()`: размор AI (`set_field_ai_active(true)`, если не идёт празднование), снять лок
     мотора вбрасывающего и `set_face_direction(ZERO)`, `set_throw_in_active(false)`, `IDLE`.

## Гейтинг в `match_manager` (зеркалит goal kick)

- Поля: `_throw_in` (контроллер), `_throw_in_active: bool`, `_throw_in_cam_pose: Transform3D`.
- API: `is_throw_in_active()`, `set_throw_in_active(on)`, `set_throw_in_cam_pose(pose)`.
- `_ready`: preload + `add_child` + `setup(self, ball, camera_pivot, power_bar)`.
- `_setup_inputs`: новый action `throw_in_debug` → `KEY_T`. T уже привязана к `corner_call`, но
  контексты взаимоисключающие (вброс стартует только когда сет-писов нет; `corner_call` читается
  только во время углового) — оба action на KEY_T сосуществуют без реального конфликта.
- `_physics_process`: `if _throw_in_active: _throw_in.update(delta); return`; и триггер
  `if Input.is_action_just_pressed(&"throw_in_debug") and not _celebrating: _throw_in.start();
  return` (среди прочих сет-писов, после их проверок).
- `_process`: ветка парковки камеры `elif _throw_in_active: camera_pivot.global_transform =
  _throw_in_cam_pose`; скрытие cyan-маркера при `_throw_in_active`; исключение из общего
  charge-гейта (`... and not _throw_in_active`).

## Камера

Фикс 3-е лицо за вбрасывающим по направлению (как GK-камера): `eye = spot − heading·THROW_CAM_BACK
+ up·THROW_CAM_HEIGHT`, смотрит `spot + heading·THROW_CAM_AHEAD + up·THROW_CAM_LOOK_Y`; паркуется
через `set_throw_in_cam_pose`. Т.к. `heading` крутится в AIM и замирает на коммите (доворота при
заряде нет), камера едет за прицелом и естественно фиксируется.

## Пайплайн ассета

- `throw_in.fbx` лежит в `assets/models/mixamo_src/` (пользователь добавил). Клип `throw_in` уже
  присутствует в собранном `footballer.glb` (см. список в `check_footballer_glb.gd`), но root-motion
  ещё **не** заморожен.
- Добавить `"throw_in": (0, 2)` в `IN_PLACE_CLIPS` (`tools/merge_mixamo.py`) — заморозить
  горизонталь (игрок стоит на месте, вертикаль оставить живой), с оговоркой из CLAUDE.md про то,
  что выбор осей проверяется эмпирически (если модель «плывёт»/«висит» — перебрать оси).
- Пересобрать glb (Blender 5.1) → `--headless --import`.
- **Калибровка тайминга.** Замерить длину клипа `throw_in`, задать `ACTION_TIMING["throw_in"] =
  {"contact": len·13/33, "lock": len, "speed": 1.0}` в `player_visual.gd`. Пересобрали клип —
  перемерить (как `PEN_ROOT_SCALE`).

## Константы (`football_constants.gd`, секция `THROW-IN`)

`THROW_BEHIND_OFFSET` (0.5 м), `THROW_AIM_SPEED` (2.0 рад/с), `THROW_AIM_ARC` (`PI/2`),
`THROW_CHARGE_MAX_TIME` (0.7 с), `THROW_MIN_DIST`/`MAX_DIST` (6/22 м), `THROW_PEAK_MIN`/`MAX`
(2.0/4.5 м), `THROW_ENCROACH_DIST` (2.0 м), `THROW_CAM_BACK`/`HEIGHT`/`LOOK_Y`/`AHEAD`
(4.5/2.2/1.2/6.0 м). Все — стартовые значения, тюнятся живой приёмкой.

## Тесты

- `tests/check_throw_in_logic.gd` — чистые функции `ThrowInLogic` (точка аута на обеих линиях,
  базовое направление, расстановка за линией) + один кейс `FreeKickLogic.push_out_of_radius` под
  точку вброса.
- `tests/check_player_visual_pose.gd` — `hold_pose("throw_in")` замораживает (`TimeScale=0`) и
  возвращает true; `hold_pose` несуществующего клипа → false; последующий `trigger("throw_in")`
  восстанавливает скорость.
- `tests/check_throw_in_flow.gd` — headless-смоук: `start()` включает режим → `_fire_charge` →
  мяч получил импульс + `_throw_in_active` снят.

Интерактивный фил (доворот тела/камеры, дуга, кламп ±90°, передача управления на бегу) проверяется
только на живом запуске — headless не крутит ввод/рендер.

## Вне рамок (Фаза A)

Авто-детект ухода мяча за линию; правило «команда вбрасывает та, чей соперник последним тронул
мяч» (пока — ближайший team_1); «гол напрямую с вброса не засчитывается»; оффсайд-иммунитет;
умное открывание/движение партнёров во время вброса (пока — заморозка); выбор конкретной руки под
двуручный замах (аппроксимируем правой, как у вратаря).

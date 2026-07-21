# Удар от ворот (Goal Kick) — дизайн (Фаза A)

Дата: 2026-07-21
Ветка: `feat/goal_kick`

## Что это

Стандартное положение «удар от ворот»: мяч ставится в центр линии вратарской площади,
и **вратарь вводит мяч в игру ударом ногой с разбега** (как в штрафном и пенальти).
Игрок выбирает тип ввода — **наземный пас (A)** или **навес (B)** — заряжает силу удержанием
кнопки, задаёт горизонтальное направление до удара и может **доводить/переопределять направление
стиком вплоть до контакта** (камера уже зафиксирована на коммите, но мяч можно «отдать в другую
сторону» — финт). Кручёного и удара-в-створ в этой фиче нет.

После ввода мяча в игру стандартное положение закрывается, и игра продолжается как обычно.

Фаза A: розыгрыш человеком через тестовый триггер (клавиша **G**), от 3-го лица, по образцу
розыгрыша штрафного/углового за полевого игрока. Реальный триггер по правилам (мяч ушёл за
лицевую линию от атакующего) — вне рамок этой фазы.

## Ключевые отличия от других стандартов

- **Бьющий — вратарь**, а не полевой `controlled_player`. Человек на время удара драйвит вратаря
  (контроллер читает сырой `Input`, поэтому неважно, что `controlled_player` остаётся на team_1).
  Вратарский `PlayerVisual` использует тот же `footballer.glb`, поэтому клипы разбега
  `penalty_kick_l/r` + root motion ему доступны.
- **Точка мяча — центр линии вратарской площади** (X=0, Z = `goal_line_z + into * GOAL_AREA_DEPTH`),
  а не позиция бьющего.
- **Нет стенки, нет удара-в-створ, нет кручёного, нет получателя.** Только пас (A) и навес (B).
- **Правило расчистки штрафной — общее и симметричное:** вытесняются соперники **бьющей команды**
  (сторона определяется по группе бьющего вратаря), а не захардкоженный team_1. Свои игроки бьющей
  команды могут стоять в штрафной. Тот же код без изменений заработает, когда полноценный ИИ-соперник
  получит те же функции и будет бить от своих ворот.
- **После удара управление возвращается человеку на его team_1-игроке** — без автоподбора получателя
  и передачи управления (в отличие от штрафного/углового).

## Тестовый сценарий (клавиша G)

Единственный вратарь в проекте — team_2 (зелёный, ворота Home на −Z, которые атакует человек).
Значит тестовый удар от ворот бьёт этот team_2-вратарь; человек драйвит его на время розыгрыша;
соперники бьющей команды = team_1 (игроки человека) вытесняются из штрафной Home. После ввода мяча
управление возвращается на team_1-игрока человека, оба ИИ борются за мяч как обычно.

## Архитектура

Тот же проверенный паттерн, что у FK / пенальти / углового: контроллер-автомат + чистая математика,
gameplay/презентация разделены, вратарь через `_keeper`/`_keeper_brain`, фикс-камера через
`set_*_cam_pose`.

### Новые файлы

**`scripts/match/goal_kick_controller.gd`** (`extends Node`) — автомат `IDLE→SETUP→AIM→STRIKE`.
Бьющий = вратарь. По образцу `corner_controller.gd`, но проще (нет стенки/удара-в-створ/получателя).
`setup(manager, ball, camera_pivot, power_bar, keeper)`, `start(kicker, goal_line_z)`, `is_active()`,
`update(delta)`.

**`scripts/match/goal_kick_logic.gd`** (`class_name GoalKickLogic extends Object`, **никогда не читает
`FootballConstants`** — вся настройка приходит параметрами, headless-тестируемо как `PassSystem`/
`FreeKickLogic`). Уникальная геометрия удара от ворот:
- `spot_position(goal_line_z, into, ga_depth, ball_radius) -> Vector3` — центр линии вратарской.
- `runup_placement(spot, forward, runup_dist, foot_lateral, foot) -> Vector3` — точка постановки
  вратаря за мячом на разбег.
- `push_out_of_penalty_area(pos, goal_line_z, into, pa_depth, pa_half_width, margin) -> Vector3` —
  если `pos` внутри штрафной у `goal_line_z`, вытолкнуть за 16.5-метровую линию (+ запас `margin`),
  иначе вернуть без изменений.

Остальное переиспользуется: `FreeKickLogic.base_heading`/`rotate_heading`, `PassSystem.ground_pass_speed`/
`launch_ground`/`launch_lob`, `KeeperLogic.drag_horizontal_speed`.

### Изменённые файлы

**`scripts/data/football_constants.gd`** — секция `GOAL KICK`:
`GK_RUNUP_DIST`, `GK_DEFAULT_FOOT`, `GK_FOOT_LATERAL`, `GK_AIM_SPEED`, `GK_AIM_ARC`, `GK_REDIRECT_ARC`,
`GK_CHARGE_MAX_TIME`, `GK_GROUND_MIN_DIST`, `GK_GROUND_MAX_DIST`, `GK_LOB_MIN_DIST`, `GK_LOB_MAX_DIST`,
`GK_LOB_PEAK_MIN`, `GK_LOB_PEAK_MAX`, `GK_ENCROACH_MARGIN`, `GK_CAM_BACK`, `GK_CAM_HEIGHT`, `GK_CAM_LOOK_Y`.

**`scripts/match/match_manager.gd`**:
- `_goal_kick` инстанс + `_goal_kick.setup(self, ball, camera_pivot, power_bar, _keeper)` в `_ready`.
- `_goal_kick_active: bool` + `is_goal_kick_active()` / `set_goal_kick_active(on)`.
- `set_goal_kick_cam_pose(t)`.
- Гейтинг в `_physics_process`: `if _goal_kick_active: _goal_kick.update(delta); return`.
- Парковка `CameraPivot` в `_process` при `_goal_kick_active` (как у пенальти/FK).
- Инпут `goal_kick_debug` = `KEY_G` в `_setup_inputs()`.
- Триггер рядом с P/F: `if just_pressed("goal_kick_debug") and _keeper != null and not _celebrating
  and not <любой set-piece active>: _goal_kick.start(_keeper, _keeper_brain.goal_line_z)`.
- `_goal_kick_active` добавляется в общие guard-проверки `not <any set-piece>` там, где они уже есть.

**`scripts/ai/keeper_ai.gd`**:
- `set_goalkick_mode(on)` — пассивный режим бьющего: выйти из любого состояния (`recover`), отпустить
  мяч из рук если пойман, заглушить реактивную логику сейва/распаса (флаг с ранним выходом в
  `_physics_process`/`_position`), при `off` — вернуться в `POSITION`. По образцу `set_penalty_mode`.
- Ранний выход обработчика `action_contact` в goalkick-режиме — иначе на контакте сработают ОБА
  (распас вратаря И запуск контроллера), т.к. у вратаря `connect_action_signals=false` и `keeper_ai`
  сам слушает `action_contact`.

## Фазы и поток

- **SETUP:** `set_goal_kick_active(true)`, `set_field_ai_active(false)`; определить `into` по знаку
  `goal_line_z`, `forward` = вверх поля от линии к центру; мяч на точку (центр линии,
  `release_dribble` + `clear_last_kicker`, обнулить скорости); `keeper_ai.set_goalkick_mode(true)`;
  поставить вратаря за мячом на разбег лицом по `forward`, мотор control-locked, `set_face_direction`;
  вратаря в чистый idle (`cancel_action`/`recover`); расчистка штрафной (см. правило); камера-поза;
  `_heading = base_heading`; → AIM.
- **AIM:** пин мяча на точке; стик-X крутит `_heading` (`FreeKickLogic.rotate_heading` вокруг
  `base_heading`, камера едет); **A** (`pass_short`) → старт заряда `"ground"`, **B** (`pass_lob`) →
  старт заряда `"lob"`; при заряде — PowerBar, при отпускании/макс → в STRIKE.
- **STRIKE:** камера **фиксируется** (перестаёт следовать за `_heading`); играется клип разбега
  `penalty_r/l`, root motion двигает вратаря вдоль `forward` (`consume_root_motion`); **стик продолжает
  крутить `_heading` вплоть до контакта** (доводка/финт, ограничена аркой `GK_REDIRECT_ARC` вокруг
  направления на момент коммита); на `action_contact` — запуск мяча по финальному `_heading`,
  `note_kicker(keeper)`, `struck`, разлочка мотора, `_release()`.
- **`_release()`:** `keeper_ai.set_goalkick_mode(false)`; `set_face_direction(ZERO)`; если гол-
  празднование — сохранить заморозку поля-ИИ (снимет `_celebrate_then_reset`), иначе
  `set_field_ai_active(true)`; `set_goal_kick_active(false)`; → IDLE. `controlled_player` не трогаем —
  управление у человека остаётся на его team_1-игроке.

## Ввод мяча (A / B)

- **A — наземный пас:** `land_dist = lerp(GK_GROUND_MIN_DIST, GK_GROUND_MAX_DIST, ratio)` вдоль
  `_heading`; `speed = PassSystem.ground_pass_speed(land_dist, ratio, PASS_GROUND_MIN/MAX_TRAVEL_TIME,
  PASS_GROUND_MIN/MAX_SPEED)`; `PassSystem.launch_ground(...)` → `ball.launch(vel, flat=true)`.
- **B — навес:** `land_dist = lerp(GK_LOB_MIN_DIST, GK_LOB_MAX_DIST, ratio)`,
  `peak = lerp(GK_LOB_PEAK_MIN, GK_LOB_PEAK_MAX, ratio)`; вертикаль из `PassSystem.launch_lob`,
  горизонталь с поправкой на драг через `KeeperLogic.drag_horizontal_speed` (как в навесе FK/углового,
  иначе недолёт) → `ball.launch(vel, false)`.
- Мяч лежал на точке (`dribbler=null`) → после `launch` явно `note_kicker(keeper)` (анти-самоблок/
  кулдаун, чтобы бьющий не блокировал/перехватывал собственный ввод).

## Правило штрафной (общее)

- Бьющая команда определяется по группе `kicker` (`team_1`/`team_2`); соперники = другая группа.
- Все полевые игроки **соперника** внутри штрафной площади у `goal_line_z`
  (`PENALTY_AREA_DEPTH` × `PENALTY_AREA_WIDTH`) выталкиваются за 16.5-метровую линию через
  `GoalKickLogic.push_out_of_penalty_area(..., GK_ENCROACH_MARGIN)`.
- Свои игроки бьющей команды остаются где стоят.
- Расчистка на старте; поле-ИИ заморожен (`set_field_ai_active(false)`), поэтому все стоят где
  поставили до ввода мяча.

## Камера

Фикс 3-е лицо за вратарём: `eye = spot − heading*GK_CAM_BACK + up*GK_CAM_HEIGHT`,
`look = spot + heading*4 + up*GK_CAM_LOOK_Y`. Парковка `CameraPivot` в `_process` при `_goal_kick_active`
(как у пенальти/FK). До коммита камера следует за прицелом (heading меняется в AIM); на коммите heading
для камеры фиксируется, дальнейшая доводка мяча идёт «вслепую» вбок — это и есть финт.

## Тесты

- **`tests/check_goal_kick_logic.gd`** — чистые функции `GoalKickLogic`: `spot_position` (центр линии,
  правильный Z/into), `runup_placement` (за мячом, латеральный сдвиг под ногу), `push_out_of_penalty_area`
  (внутри штрафной → вытолкнут за линию + запас; снаружи → без изменений).
- **`tests/check_goal_kick_flow.gd`** — headless-smoke: `setup`→`start`→прогон `update` с симуляцией
  заряда/контакта → мяч запущен (скорость > 0) и `_goal_kick_active` снят.
- Интерактивный фил (прицел, камера, разбег, финт-доводка) требует запуска игры человеком — headless
  не драйвит ввод/рендер.

## Вне рамок (будущее)

- Реальный триггер удара от ворот по правилам (мяч за лицевой линией от атакующего).
- ИИ-вратарь, разыгрывающий удар от ворот автономно (логика расчистки/запуска уже общая — добавится
  только выбор цели/силы ИИ).
- Кручёный ввод, выбор точки в пределах вратарской (не только центр), выбор конкретного получателя.

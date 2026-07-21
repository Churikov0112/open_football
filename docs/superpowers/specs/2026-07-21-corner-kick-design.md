# Розыгрыш углового удара — дизайн (Фаза A)

Дата: 2026-07-21. Ветка: `feat/corner`.

## Что это

Розыгрыш углового удара по образцу пенальти и штрафного: отдельный контроллер-автомат,
чистая математика в своём `*Logic`, гейтинг в `match_manager`, активация по клавише. Игрок бьющий
подаёт из угла — навесом верхом (лоб с ручной закруткой и регулируемой высотой траектории) или
разыгрывает коротко через наземный пас подбежавшему партнёру. Вратарь держит створ и ловит то,
что летит рядом. Тестовая активация — клавиша **C**; сторона углового выбирается по тому, к какому
углу был ближе контроллируемый игрок в момент нажатия.

Это Фаза A: один розыгрыш за игрока-человека, затем мяч отдаётся в обычную игру. Полноценный
«выход вратаря на навес», выбор конкретного бьющего и ИИ-розыгрыш углового соперником — вне скоупа.

## Архитектура

Тот же раздел gameplay/pure-math, что у penalty/free-kick:

- **`scripts/match/corner_controller.gd`** (`extends Node`) — автомат `SETUP → AIM → STRIKE`,
  ввод, спавн целей/защитников, камера, конверт тел в ИИ. Создаётся и `setup(...)`-ится в
  `match_manager._ready` рядом с `PenaltyController`/`FreeKickController`.
- **`scripts/match/corner_logic.gd`** (`class_name CornerLogic extends Object`, **никогда не
  читает `FootballConstants`** — тюнинг параметрами) — только угловое-специфичная геометрия;
  headless-тестируется.
- **Переиспользуем готовые чистые функции:** `FreeKickLogic.base_heading` / `rotate_heading` /
  `curl_from_stick` / `scatter_degrees` / `apply_scatter`; `PassSystem.launch_ground` /
  `launch_lob`; `KeeperLogic.drag_horizontal_speed`. Разбег — существующие root-motion клипы
  `penalty_l` / `penalty_r`, масштаб `PEN_ROOT_SCALE`.

Почему отдельный контроллер, а не расширение `FreeKickController`: у FK своя специфика (стенка,
правило 9.15 м, прыжки стенки) и он уже большой. У углового другая геометрия (угол, штрафная, нет
стенки) и другой ввод (стик-Y = высота, кнопки A/B). Отдельный контроллер держит границы чистыми
и тестируемыми — как penalty vs free-kick.

## Автомат состояний

`enum Phase { IDLE, SETUP, AIM, STRIKE }` (фазы `WATCH` с удержанием фикс-вида нет — см. Камера).

- **SETUP** — определить сторону по игроку; поставить мяч в угол; бьющего за мяч лицом в поле
  (root-motion разбег), в чистый idle; вратаря в режим углового; заспавнить наши цели в штрафной +
  защитников; заморозить поле-ИИ (`set_field_ai_active(false)`); включить фикс-камеру. → AIM.
- **AIM** — прицел (стик-X = heading/камера), выбор высоты навеса (стик-Y, до нажатия кнопки),
  выбор ноги (L/R, временно), вызов партнёра (RB), заряд A (наземный пас) или B (навес). → STRIKE.
- **STRIKE** — разбег по root-motion; стик-X копит закрутку; ждём `action_contact`. На контакте
  запускаем мяч, отдаём управление получателю, `_release()` → обычная игра.

## Ввод

Активация: `corner_debug` (**C**), только если есть вратарь и `not _celebrating`.

**В AIM (до нажатия кнопки удара):**
- **Левый стик X** — крутит `_heading` в секторе ±`CORNER_AIM_ARC` вокруг базового (угол→центр
  ворот), камера едет следом. `FreeKickLogic.rotate_heading`. Бьющего не доворачиваем — он смотрит
  по фиксированному `_base_heading` (разбег всегда к мячу).
- **Левый стик Y** — задаёт **тип траектории навеса**, только пока кнопка навеса не нажата:
  вверх → низкая быстрая (на уровень головы), нейтраль → стандарт, вниз → «свеча». Внутри это
  одно число `peak_height` через `CornerLogic.peak_for_stick_y`. Фиксируется в момент нажатия B.
- **L / R** (`foot_left`/`foot_right`) — переключают бьющую ногу `penalty_l` ↔ `penalty_r`:
  меняется клип и латеральный сдвиг под опорную ногу (бьющий переставляется на другую сторону от
  линии разбега). **Временный debug-механизм** — в будущем нога определяется выбранным бьющим
  игроком (левша/правша), а не кнопкой. Тот же блок добавляется в penalty/free-kick.
- **RB** (`corner_call`) — команда ближайшему ИИ-тиммейту подбежать к углу на короткую опцию.
  Кнопок не меняет; просто перемещает цель одного тела на `short_option_pos`.

**Кнопки удара (обе доступны в AIM, тип решает кнопка, не прицел):**
- **A** (`pass_short`) = **наземный короткий пас**. Удержание = заряд силы (`CORNER_CHARGE_MAX_TIME`,
  power-bar виден), lerp `CORNER_PASS_MIN_SPEED..MAX_SPEED`. Без высоты и закрутки.
- **B** (`pass_lob`) = **навес**. Удержание = заряд дальности; стик-Y (зафиксированный) = высота
  дуги; стик-X во время разбега = закрутка (`_curl_accum`, по умолчанию 0 → прямая).

Отпускание кнопки (или максимум заряда) → STRIKE. Во время разбега для навеса стик-X продолжает
копить закрутку до самого контакта (как в штрафном).

## Геометрия (`CornerLogic`)

Поле FIFA: центр `(0,0,0)`, Z длина (±52.5), X ширина (±34). Наша команда атакует −Z; вратарь
защищает атакуемые ворота, `goal_line_z = _keeper_brain.goal_line_z`.

- **Сторона** `side_for_player(player_x) -> float` = `signf(player_x)` (в момент нажатия C).
- **Спот** `corner_spot(side, half_width, goal_line_z, inset, ball_radius) -> Vector3` =
  `(side*(half_width - inset), ball_radius, goal_line_z + into*inset)`, `into = -signf(goal_line_z)`
  (в поле) — чуть внутри от точного угла, чтобы бьющий помещался.
- **Нога** `foot_for_side(side) -> String` — «открытой» ногой в поле: правый угол (`side>0`) →
  `penalty_l`, левый → `penalty_r`. Значение по умолчанию до ручного L/R-переключения.
- **Высота** `peak_for_stick_y(stick_y, peak_head, peak_standard, peak_svecha) -> float` — маппинг
  `stick_y ∈ [-1,1]` (вверх = +1 → `peak_head`, 0 → `peak_standard`, вниз = -1 → `peak_svecha`)
  в высоту дуги. Все три приземляются в одну точку (горизонталь `launch_lob` решается из времени
  полёта), отличается только высота/время.
- **Цели в штрафной** `box_target_positions(goal_line_z, into, ...)` — 2 позиции (ближняя/дальняя
  зона) для наших атакующих = кандидатов-получателей навеса.
- **Короткая опция** `short_option_pos(spot, along_line, dist)` — позиция подбежавшего партнёра
  вдоль линии от угла в поле, на `CORNER_SHORT_DIST`.

Базовый heading: `FreeKickLogic.base_heading(spot, goal_center)`; сектор `rotate_heading` шире
штрафного (`CORNER_AIM_ARC`) — навешивать можно и на дальнюю штангу, и назад под удар.

## Спавн и очистка

Как FK `_spawn_mates`/`_spawn_defense`, все через `PlayerFactory`, группа `corner_spawned`:
- **Наши цели** — 2 атакующих в штрафной (`box_target_positions`), кандидаты-получатели.
- **Короткий партнёр** — ближайший ИИ-тиммейт; до RB стоит обычно, по RB бежит на `short_option_pos`.
- **Защитники** — 1–2 соперника в штрафной (маркируют зоны) + вратарь на линии. Стенки нет.

`_cleanup_spawned` деспавнит тела прошлого углового на старте (кроме бьющего). На `_release`
`_convert_bodies` вливает спавн-тела в обычный ИИ (`simple_ai`/`teammate_ai` как Brain-child,
`add_child`, не `set_script`).

## Разрешение удара (`_on_kicker_contact`)

Получатель — `_select_receiver()` по совпадению с heading (dot от мяча, порог), как в FK.

- **A (наземный пас):** `speed = lerp(CORNER_PASS_MIN_SPEED, CORNER_PASS_MAX_SPEED, ratio)`;
  `vel = PassSystem.launch_ground(from, from + flat, speed)`; `ball.launch(vel, true)` (настильно).
- **B (навес):** точка приземления = позиция получателя (или `heading × дальность_заряда`, если
  получателя нет); `peak` = зафиксированный `peak_for_stick_y`; вертикаль из `PassSystem.launch_lob`,
  **горизонталь с поправкой на драг** `KeeperLogic.drag_horizontal_speed` (иначе недолёт, как лоб в
  FK); закрутка `FreeKickLogic.curl_from_stick(_curl_accum, CORNER_CURL_SCALE, CORNER_CURL_MAX)` →
  если ≠0 `ball.launch_curl(vel, curl, false)`, иначе `ball.launch(vel, false)`.

В обоих случаях: если получатель валиден — `_manager.assign_controlled_player(receiver)` **до**
`_release()`/конверта тел (та же причина, что в FK: конверт читает `controlled_player`), затем
`_release()`, затем `_manager.begin_pass_receive(receiver)` (наведение + принудительный трап).

## Вратарь

Режим углового через существующий `set_freekick_anchor(pos)` — ставим вратаря на позицию у створа
(центр/ближняя штанга), его центральный рефлекс ловли и высокая ловля/дайв уже работают и ловят то,
что летит рядом. `clear_freekick_anchor()` на `_release`. Полноценный «выход на навес» (вратарь
активно идёт на верховой мяч в штрафной) — **вне скоупа Фазы A**, будущее.

## Камера

Фикс 3-е лицо за бьющим (за углом, смотрит в штрафную/ворота), **только до начала движения мяча**.
Новые `match_manager.set_corner_cam_pose(pose)` / `_corner_cam_pose` + гейт в `_process` (пока
`_corner_active`). На контакте мяч запускается и сразу `_release()` — `_corner_active` сбрасывается,
`_process` перестаёт парковать угловую позу, и обычная игровая камера (телевизионная или 3-е лицо,
по переключателю 1/3) возвращается сама. Отдельной фазы удержания вида нет.

## Интеграция в `match_manager`

- Поля/методы: `_corner` (контроллер, `_ready` + `setup`), `_corner_active`,
  `is_corner_active()`, `set_corner_active(on)`, `set_corner_cam_pose(pose)`, `_corner_cam_pose`.
- `_physics_process`: если `_corner_active` — делегируем `_corner.update(delta)` и `return`
  (обычный ввод/ИИ/дриблинг пропускаются), как пенальти.
- `_process`: если `_corner_active` — парковка `camera_pivot` в `_corner_cam_pose`.
- Активация: `Input.is_action_just_pressed(&"corner_debug")` и `_keeper != null` и
  `not _celebrating` → `_corner.start(controlled_player, _keeper_brain.goal_line_z)`.
- Гол с углового: если `is_celebrating()` — поле-ИИ не размораживаем на `_release` (та же защита,
  что в FK/penalty; класс бага покрыт `check_setpiece_goal_freeze`).
- Новые input-действия в `_setup_inputs()`: `corner_debug`(KEY_C), `corner_call`(RB =
  `JOY_BUTTON_RIGHT_SHOULDER`), `foot_left`(KEY_L), `foot_right`(KEY_R). Пас/навес — существующие
  `pass_short`(A)/`pass_lob`(B).

## Правки в penalty/free-kick (переключение ноги)

Сейчас нога — константа (`PEN_DEFAULT_FOOT`/`FK_DEFAULT_FOOT`). Добавляется живое L/R-переключение
в фазе AIM: `foot_left`/`foot_right` меняют `_foot` (`penalty_l`↔`penalty_r`) и **переставляют
бьющего** (пересчёт латерального сдвига под опорную ногу — тот же расчёт, что при `_setup`).
Помечается как временный debug-механизм (в будущем нога — от выбранного бьющего). Единообразный
маленький блок в `penalty_controller.gd`, `free_kick_controller.gd`, `corner_controller.gd`.

## Константы (`football_constants.gd`, секция `CORNER`)

`CORNER_INSET`, `CORNER_AIM_ARC`, `CORNER_AIM_SPEED`, `CORNER_CHARGE_MAX_TIME`,
`CORNER_PASS_MIN_SPEED`/`MAX_SPEED`, `CORNER_LOB_PEAK_HEAD`/`STANDARD`/`SVECHA`,
`CORNER_LOB_MIN_DIST`/`MAX_DIST` (заряд→дальность навеса), `CORNER_CURL_SCALE`/`MAX`,
`CORNER_TARGET_LATERAL`/`DEPTH` (позиции целей), `CORNER_SHORT_DIST`, `CORNER_FOOT_LATERAL`,
`CORNER_RUNUP_DIST`, `CORNER_CAM_BACK`/`HEIGHT`/`LOOK_Y`, `CORNER_DEFAULT_FOOT`. Масштаб root-motion
разбега — переиспользуем `PEN_ROOT_SCALE`.

## Тесты (headless, `tests/`)

- **`check_corner_logic.gd`** — все чистые фн `CornerLogic`: `side_for_player`, `corner_spot`
  (сторона/inset/высота Y мяча), `foot_for_side`, `peak_for_stick_y` (маппинг вверх/центр/вниз),
  `box_target_positions`, `short_option_pos`.
- **`check_corner_flow.gd`** — смоук: `start` → фаза AIM → навес B запускает мяч (`launch_curl`/
  `launch`, скорость > 0) и снимает `_corner_active`; отдельно ветка наземного паса A.
- Раз трогаем L/R в penalty/FK — прогнать существующие `check_penalty_flow.gd` /
  `check_free_kick_flow.gd` на регресс.
- Интерактивный фил (прицел, высота траектории, закрутка, разбег, камера-возврат, дайв вратаря) —
  нужен человек за игрой; headless ловит только логику.

## Явно вне скоупа Фазы A

- ИИ-розыгрыш углового соперником.
- Активный выход вратаря на верховой навес.
- Выбор конкретного бьющего игрока (L/R-переключение ноги — временная заглушка под это).
- Низкий/настильный «прострел» как отдельный тип (только наземный пас A и навес B).

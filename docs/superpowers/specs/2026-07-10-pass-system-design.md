# Система пасов — дизайн

**Дата:** 2026-07-10
**Ветка:** `feat/pass`
**Статус:** дизайн утверждён, готов к плану реализации

## Контекст и цель

Сейчас в игре есть только удар (заряд по `Space`) и примитивный пас (`E`, мгновенный,
фиксированная сила `12.0`) — см. [`match_manager.gd:715`](../../../scripts/match/match_manager.gd).
Этот спек проектирует полноценную **систему пасов** аркадного футбола: пять типов передач с
заряжаемой шкалой силы, авто-наводкой, «нечестной, но не 100%» проходимостью, доводкой
принимающего к мячу (receive-assist) и комбинацией «стенка» (give-and-go). В ту же задачу входит
**добавление поддержки геймпада** и **ремап клавиатуры**.

**Планка — «легко и весело».** Это аркада: пасовать должно быть просто (щедрая помощь наводки и
приёма), но не тривиально (пас — это решение, а не гарантия). Проходимость паса зависит от позиций
игроков в момент передачи.

Прототип сейчас **1 человек + 1 ИИ-партнёр против 1 ИИ-соперника**. Архитектура проектируется с
заделом на 11v11, но реализуется под текущий масштаб (без behaviour tree и прочего оверинжиниринга).

## Референс: OpenSoccer

`C:\Users\User\Desktop\OpenSoccer` (соседний проект того же автора, играется отлично) реализует
почти всё нужное. Ключевые механики, взятые за основу (монолитный ООП, мы переносим алгоритмы в
чистые функции):

- **Выбор цели** — `Team.gd:_findPass(pos, aimDir, id)`: для каждого партнёра
  `score = ((pos + vel*dSmart) - ballpos).normalized().dot(aimDir.normalized())`; берётся максимум
  скалярного произведения (кто лучше по направлению стика), ничья → ближайший. Упреждение по
  скорости встроено.
- **Коридор перехвата** — `Team.gd:_checkPass(pd, len)`: строит `Transform3D` коридора паса
  (`r = pd.cross(UP)`), проецирует соперников в локаль, коридор расширяется
  `lerp(2, 8, smoothstep(0, len, z))`; соперник внутри → пас блокирован. Детерминированно.
- **Receive-assist** — `Player.gd:checkInput()`: `db = (ballpos + ballvel*0.16) - pos`; если
  `db.dot(stick) > acomp` (где `acomp = 1 - moveAssist`) — движение защёлкивается на предсказанную
  точку мяча.
- **Выход на приём** — `AI.gd:_receivePass(ppos, dir, ptype)`: `target = ppos + dir*1.25` (низом) /
  `*2.0` (длинный) — партнёр бежит встречать.
- **Навес** — `Player.gd:chipPass2`: высота `h = 0.1 + smoothstep(0, 100, dist)`, `y += h*34`.

Осознанное расхождение с референсом: у них сила паса берётся из дистанции до цели (`passDir * 1.5`),
у нас — **заряжаемая шкала** (как у удара), заряд поверх базовой баллистики.

## Управление (финал)

Движение уходит на стрелки/стик — буквы WASD освобождаются под действия.

| Действие | Клавиатура | Геймпад (Xbox) |
|---|---|---|
| Движение | Стрелки | Левый стик (аналог, deadzone) |
| Спринт (удерж.) | Left Shift | RT (аналоговый, `get_action_strength`) |
| Удар (удерж., с мячом) / Подкат (без мяча) | D | X |
| Короткий пас низом | X | A |
| Пас на ход низом | W | Y |
| Навес | A | B |
| Модификатор комбо *(атака)* / Смена игрока *(защита)* | Q | LB |
| Пас «в стенку» (give-and-go) | Q + X | LB + A |
| Пас на ход верхом | Q + W | LB + Y |

**Q / LB контекстно-зависимы по владению:** если мяч у нашей команды (атака) — это модификатор
комбо; иначе (защита/ничей мяч) — смена управляемого игрока на ближайшего к мячу. Различается по
`ball.dribbler` (принадлежит ли `team_1`).

**Правила ввода:**
- Весь ввод строится в коде в [`_setup_inputs()`](../../../scripts/match/match_manager.gd) —
  `project.godot` мёртв (см. CLAUDE.md). Буквы `KEY_A/W/S/D` **вырезаются** из `move_*`.
- Джойстик: `InputEventJoypadButton` (кнопки) и `InputEventJoypadMotion` (оси стика ±1 на
  `move_*`, RT-триггер на `sprint`). Направление движения читается через
  `Input.get_vector(...)` с deadzone — даёт аналог от стика и бинарь от стрелок одним вызовом.
- Модификатор комбо — **ручная проверка** `Input.is_action_pressed(&"combo_modifier")` в момент
  `just_pressed` базовой кнопки паса (не отдельные комбо-экшены; Godot их нативно не поддерживает,
  а комбинаторика раздувается). Читается в одном физ-кадре из одного снапшота — гонки нет.
- Спринт аналоговый: `speed_scale = lerp(1.0, LOCO_SPRINT_SPEED/LOCO_TOP_SPEED,
  get_action_strength("sprint"))`. Клавиатурный Shift даёт strength `1.0`.

## Архитектура

Развитие «подхода C»: тяжёлая математика — в чистых статических функциях (тестируется headless, по
образцу [`PlayerMotor`](../../../scripts/player/player_motor.gd) /
[`check_player_motor_math.gd`](../../../tests/check_player_motor_math.gd)); эфемерное состояние — на
узлах; глобальная оркестрация — в менеджере.

### `scripts/match/pass_system.gd` (`class_name PassSystem extends Object`)

Только `static`-функции. **Вход — POD (`PackedVector3Array` позиций/скоростей, скаляры), не узлы;
выход — индексы/векторы/`PassSolution`.** Тюнинг передаётся параметрами, функции **не читают**
`FootballConstants` (иначе тест потянет autoload). Корреляцию индекс→узел держит оркестратор.

Ориентировочные сигнатуры:

```gdscript
static func select_target(passer_pos: Vector3, aim_dir: Vector3,
        mate_positions: PackedVector3Array, mate_velocities: PackedVector3Array,
        lead_gain: float, dot_bias: float, max_range: float) -> int
static func lead_point(target_pos: Vector3, target_vel: Vector3, passer_pos: Vector3,
        ball_speed: float, extra_lead: float) -> Vector3
static func launch_ground(from: Vector3, to: Vector3, power: float) -> Vector3
static func launch_lob(from: Vector3, to: Vector3, peak_height: float, gravity: float) -> Vector3
static func interception_time(pass_from: Vector3, pass_vel: Vector3, ball_speed: float,
        opp_pos: Vector3, opp_speed: float, corridor_half_width: float) -> float   # INF если не достаёт
static func apply_scatter(aim_point: Vector3, spread_base: float, distance: float,
        rng: RandomNumberGenerator) -> Vector3
static func resolve_pass(...) -> PassSolution   # агрегатор всего выше
```

`PassSolution` (`class_name ... extends RefCounted`): `target_index: int`, `aim_point: Vector3`,
`launch_velocity: Vector3`, `intercepted: bool`, `interceptor_index: int`, `intercept_time: float`.
`RefCounted` (не `Resource` — транзиентный, не сериализуется; не `Dictionary` — типобезопасность).

### `scripts/match/pass_types.gd`

```gdscript
enum PassType { SHORT_GROUND, THROUGH_GROUND, LOB, WALL, THROUGH_AIR }
```

`PassParams` (`RefCounted`) с полями `power`, `peak_height` (0 → низом), `extra_lead`, `spread_base`,
`is_air`; фабрика `static func for_type(t: PassType) -> PassParams` через `match` (с фолбэком `_:`),
читающая `FootballConstants.PASS_*`. **Пять типов — это две механики:** «в точку мяча» (в ноги /
точка приземления навеса) и «на ход» (`+dir*lead`). Тип меняет только `lead`/`peak_height`/`is_air`,
не отдельный код-путь.

### `match_manager.gd` (оркестратор)

- **Обобщённый заряд** — `enum ChargeAction { NONE, SHOT, PASS_SHORT, PASS_THROUGH, PASS_LOB,
  PASS_WALL, PASS_THROUGH_AIR }` заменяет булев `_kick_charging`. Поля `_charge_action`,
  `_charge_time`, `_charge_player`. «Заряжаемся» = `_charge_action != NONE`; «только один заряд» —
  бесплатно. Бар заряда и `*_MAX_TIME`/цвет — через `match _charge_action`.
- Собирает состав из групп `team_1`/`team_2` в массивы, зовёт `PassSystem`, применяет
  `launch_velocity` к мячу.
- **Commit-action** — пасы идут через существующий путь `_action_player`/`action_contact`/
  `action_finished` (как удар, **без блокировки мотора** — флаг вместо lock), см.
  [`match_manager.gd:761`](../../../scripts/match/match_manager.gd).
- **Control-handoff** — в момент паса `controlled_player = получатель`, взводится
  `_manual_swap_cooldown` (держит от авто-реверта). Пока мяч летит, `ball.dribbler == null` →
  авто-свитч ни на кого не срабатывает; поймал → авто-свитч на него же = no-op.
- **Детекция коридора** — один раз в момент паса (не каждый кадр).
- **Телеграф-индикатор** — второй маркер над авто-целью во время заряда паса.

### `teammate_ai.gd`

- `enum Role { SUPPORT, RECEIVING, CHASING }` (не полноценная машина — просто явный режим) заменяет
  текущий if/else `_position_for_pass` / `_chase_ball`. Поля `_pass_dir`, `_pass_lead`.
- Менеджер при пасе к партнёру выставляет `Role.RECEIVING` + `_pass_dir`/`_pass_lead`; по приёму/
  таймауту — сброс в `SUPPORT`. ИИ **не угадывает** сам, кому летит мяч.
- **Give-and-go**: группа `giving_run` + `_gng_timer: float`. См. раздел ниже.

### `ball_controller.gd`

- Новый `func launch(velocity: Vector3)` — ставит `_pending_impulse = velocity * mass` напрямую
  (готовая скорость, без хака `dir.y` и без завязки силы на угол). Текущий `kick(dir, power)`
  остаётся для удара.
- `clear_last_kicker()` (уже есть, [`ball_controller.gd:74`](../../../scripts/ball/ball_controller.gd))
  вызывается на возврате give-and-go, чтобы отдавший смог принять мяч (обходит
  `_kick_cooldown_msec`).

## Типы пасов и баллистика

- **Короткий пас низом** (`SHORT_GROUND`): `launch_ground` в ноги цели (точка = позиция цели).
- **Пас на ход низом** (`THROUGH_GROUND`): цель = `lead_point(...) + extra_lead` вперёд по атаке,
  низом.
- **Навес** (`LOB`): `launch_lob` в направлении цели, дуга под **реальную гравитацию мяча**
  (`ProjectSettings physics/3d/default_gravity * ball.gravity_scale`), а **не**
  `FootballConstants.GRAVITY` (та только у `PlayerMotor`).
- **Пас на ход верхом** (`THROUGH_AIR`): `launch_lob` в упреждённую точку `+extra_lead`.
- **«В стенку»** (`WALL`): короткий пас + режим give-and-go у отдавшего (ниже).

Заряд удлиняет/усиливает базовую силу/высоту. Приземление читаемее с лёгким restitution мяча
(`physics_material_override`, ~0.4).

## Авто-наводка

`select_target`: максимум `dot(dir_to_mate, aim_dir)` с упреждением по скорости
(`pos + vel*lead_gain`), ничья (в пределах `tol`) → ближайший, фильтр по конусу/`max_range`.
`aim_dir` — направление стика/движения (а если стоим — по взгляду). Возвращает индекс.
Крайние случаи: нет партнёра по направлению → пас в направлении движения (свободный мяч);
цель = сам отдающий → не включать receive-assist.

## Модель успеха (гибрид)

**Детерминированный перехват** (`interception_time` / коридор): соперник перехватывает, если
проекция его позиции попадает в коридор паса (`0 < along < pass_len`, `|across| <
corridor_half_width(along)`), где полуширина растёт с дистанцией. Плюс **угловой разброс**
(`apply_scatter`, сидируемый `RandomNumberGenerator`), растущий с дистанцией и силой.

**Одна ручка сложности `PASS_ASSIST (0..1)`** (аналог OpenSoccer `moveAssist`) крутит сразу:
разброс (`spread_deg = SPREAD_BASE * (1 - ASSIST) * dist_factor * power_factor`), ширину защёлкивания
receive-assist и (слегка) коридор перехвата. Целевые ощущения: ~80–90% коротких проходит, ~55–70%
длинных. Старт `PASS_ASSIST ≈ 0.75`. **Не 100%** — иначе пас перестаёт быть решением.

## Receive-assist и передача управления

Управление уходит к цели **сразу в момент паса**. В [`_handle_player_input`](../../../scripts/match/match_manager.gd),
после вычисления `stick`-направления и **до** `set_move_intent`, если активна фаза приёма и
`controlled_player == получатель`:

- `db = (ball.global_position + ball.linear_velocity * PREDICT_WINDOW) - player_pos`, `db.y = 0`
  (`PREDICT_WINDOW ≈ 0.12–0.20`).
- `stick.length() < 0.1` (не трогают) → **бежать к мячу сам** (`dir = db.normalized()`, полный
  scale). Стоять — плохо, читается как баг.
- `db.normalized().dot(stick) > DOT_THRESHOLD` (`≈ 0.3–0.5`) → **защёлка на мяч** (`dir =
  db.normalized()`).
- иначе (стик прочь) → **отдать управление игроку** (обычный `dir = stick`) — осознанный dummy-run.

Завершение фазы: пойман (`ball.dribbler == получатель`), перехвачен/сменился `dribbler`, мяч ушёл за
спину и удаляется, или таймаут `RECEIVE_MAX_TIME ≈ 2.0с`. Партнёр-ИИ-получатель выходит на приём
через `Role.RECEIVING` (в ноги — к предсказанной точке мяча; на ход — `+_pass_dir*lead` вперёд;
навес — грубая оценка точки приземления).

## Give-and-go («стенка»)

Человек отдаёт `Q+X` / `LB+A`. Управление штатно уходит к принимающему (свитч на дриблёра). Отдавший
становится ИИ-управляемым, и на него вешается режим:

- Группа `giving_run` (по аналогии с `fallen`) + `_gng_timer = PASS_WALL_WINDOW (3.0)`.
- **Бежит вперёд-в-сторону**, противоположно принимающему (разводят фланги), с уклоном вперёд по
  атаке (`−Z`): `target = giver_pos + attack_dir * 8..12 + lateral * 5..7`.
- **Спринтует** — единственное осознанное исключение из «ИИ не спринтует» (телеграфируемый,
  ограниченный по времени всплеск).
- Выход: получил возврат (`ball.dribbler == self` или менеджер направил пас обратно →
  `Role.RECEIVING`) / таймаут 3с / сбит (`fallen`) — тогда `giving_run` снимается в `_finish_fall`.
- Если принимающий сразу потерял мяч (перехват) — отменить рывок отдавшего.

## Перехват — «честный», не читерский

Геометрия (коридор) решает **«можно ли»**; визуально соперник **добегает** до точки перехвата, а не
телепортирует мяч:

- Если геометрия дала перехват → соперник `Role.CHASING` к `intercept_point`, мяч подбирается
  физикой (`_handle_dribbling`, `dist < 1.0`) когда добежал.
- **Задержка реакции** `AI_INTERCEPT_REACT ≈ 0.2–0.35с` перед реакцией на пас (фора игроку).
- **Шанс «зевка»** `AI_INTERCEPT_CHANCE ≈ 0.7–0.85` — иногда не реагирует, даже если геометрически
  мог (предсказуемо-разнообразный ИИ, не оптимальный).
- Соперник **не** рвётся на перехват, если геометрия коридора не дала (не читерит «вслепую»).

## Телеграф цели

Во время заряда паса — второй индикатор над авто-выбранной целью (переиспользовать cyan-cone
[`_setup_controlled_indicator`](../../../scripts/match/match_manager.gd), другой цвет). Обновляется
каждый кадр по dot-эвристике, пока держишь; водишь стиком — маркер прыгает между партнёрами.
Опционально — пунктир коридора паса (обучает механике перехвата). Убирает угадывание «куда уйдёт
мяч», даёт микро-скилл прицела без наказания.

## Константы

Все в [`football_constants.gd`](../../../scripts/data/football_constants.gd) с префиксом `PASS_*`
(рядом с `LOCO_*`/`SLIDE_TACKLE_*`). Статические функции их **не** читают — читает оркестратор и
передаёт параметрами.

```
PASS_SHORT_POWER, PASS_THROUGH_POWER
PASS_LOB_PEAK_HEIGHT, PASS_THROUGH_AIR_PEAK_HEIGHT
PASS_LEAD_GAIN, PASS_THROUGH_EXTRA_LEAD
PASS_DOT_BIAS, PASS_MAX_RANGE
PASS_CORRIDOR_HALF_WIDTH, PASS_CORRIDOR_SPREAD
PASS_SPREAD_BASE, PASS_ASSIST
PASS_RECEIVE_PREDICT_WINDOW, PASS_RECEIVE_DOT_THRESHOLD, PASS_RECEIVE_MAX_TIME
PASS_WALL_WINDOW = 3.0
AI_INTERCEPT_REACT, AI_INTERCEPT_CHANCE
PASS_CHARGE_MAX_TIME   # если отличается от KICK
```

При случае — консолидировать локальные хардкоды kick-power из `match_manager` сюда же (CLAUDE.md
отмечает это как caveat), чтобы не плодить второй источник истины.

## Тестирование

**Headless** `tests/check_pass_system_math.gd` (`extends SceneTree`, `is_equal_approx`,
`CHECK PASS/FAIL`, `quit(0/1)` — по образцу `check_player_motor_math.gd`):

1. `select_target` — выбор по dot (партнёр по `aim_dir` vs партнёр в стороне); пустые массивы → −1.
2. `lead_point` — упреждение: цель `(10,0,0)`, `vel (0,0,5)`, `ball_speed 15` → смещение +Z на
   `5*(10/15)`; при `vel=0` точка == позиции цели.
3. `launch_lob` — ре-симуляция дуги (`p += v*dt; v.y -= g*dt`) до земли, точка приземления ≈ `to`;
   пик ≈ `peak_height`.
4. `interception_time` — соперник на линии близко → конечное время; вбок дальше
   `corridor_half_width` → `INF`.
5. `apply_scatter` — детерминизм: два вызова с `rng.seed = 42` идентичны; разброс на 30 > на 5.

**Живой прогон** (feel/тайминг/физика, headless не ловит): ширина коридора («честность»), момент
`action_contact` анимации, окно give-and-go, плавность handoff, дедзона/кривая геймпада, не
«пролетает» ли навес из-за `BALL_DRAG`/`air_resistance` (демпфирование, которого нет в чистой
баллистике — калибровать вживую).

## Блокеры в существующем коде (учтено в плане)

- **`swap_player` на `KEY_Q`** конфликтует с модификатором комбо → разрешено контекст-зависимостью
  Q (атака/защита), отдельный ребайнд не нужен.
- **WASD-буквы в `move_*`** ([`_setup_inputs:118`](../../../scripts/match/match_manager.gd)) —
  вырезать.
- **`ball._kick_cooldown_msec = 1500`** ломает возврат give-and-go отдавшему → `clear_last_kicker()`
  на возврате. **`_release_cooldown_msec = 500`** может отбить короткий пас в ноги — проверить на
  минимальной дистанции вживую.
- **`ball.kick`: `power` — импульс (÷mass), `dir` не нормализован** → новый `ball.launch(velocity)`.
- **Гравитация мяча ≠ `FootballConstants.GRAVITY`** → баллистика под реальную гравитацию мяча.
- **`_action_player` — одно поле на матч** ([`match_manager.gd:44`](../../../scripts/match/match_manager.gd)):
  быстрый возврат give-and-go может «проглотиться» `if _action_player != null: return` → отдельный
  путь или раннее снятие; проверить вживую.
- **Баг направления поддержки** — [`teammate_ai.gd:47`](../../../scripts/ai/teammate_ai.gd) ставит
  партнёра на `+Z` (позади носителя; атакуем `−Z`) → починить знак заодно.

## Вне scope (YAGNI)

Behaviour tree / HFSM для партнёра (хватает `enum Role`); хедеры и полноценный приём с воздуха;
итеративный solve точки встречи (хватает first-order); активный «чтец пасов» соперник; пять
отдельных код-путей на пять типов (это две механики). Заложены архитектурные seam'ы под 11v11
(`Role`, централизованный выбор цели в оркестраторе, `PASS_ASSIST`), но не реализуются.

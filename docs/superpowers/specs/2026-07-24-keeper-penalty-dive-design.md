# Прыжок вратаря за пенальти (KeeperIntent) — дизайн

**Дата:** 2026-07-24
**Статус:** согласован, готов к плану реализации.
**Родитель:** роадмап `2026-07-22-match-orchestration-roadmap-design.md`, раздел «Прыжок вратаря за пенальти» (Этап 2, первая фича). Опирается на шов `KickerIntent`/`SetPiecePresentation` из плана B1 (пилот пенальти уже переведён на шов).

## Что это

Дать пенальти второго актёра под управлением — **вратаря**. Сейчас пенальти всегда бьёт человек (клавиша **P**), вратарь ныряет вслепую (`PenaltyLogic.random_dive_zone`). Добавляем зеркальный режим: **ИИ бьёт, человек — вратарь** (новая тест-клавиша **K**), где человек стиком выбирает зону нырка из 5 (лево-верх/низ, право-верх/низ, центр) вплоть до момента удара, а на ударе применяется последняя выбранная зона. Для этого нужен простой ИИ-бьющий (стаб) — иначе некому бить со стороны человека-вратаря.

Все 4 комбинации бьющий×вратарь (кроме Human×Human, отложенной с 2P) работают через один шов: источник намерения вратаря — `KeeperIntent` (Human/AI), бьющего — `KickerIntent` (Human/AI).

## Ключевые решения (из брейнсторма)

- **ИИ-бьющий — простой стаб сейчас**, не полный планировщик `AIIntent` из роадмапа (оценка кандидатов-пасов для пенальти бессмысленна — бьём в пустые ворота, некому пасовать). Стаб: пауза «обдумывания» → фиксированный прицел (случайная точка в створе) → фиксированный заряд → удар.
- **Выбор зоны человеком — стиком/стрелками, как прицел бьющего** (`aim_axis`): квадрант стика → ближайшая угловая зона, нейтраль (в дедзоне) → `CENTER`.
- **Тест-клавиша K** (`keeper_dive_debug`): бьющий = `controlled_player` (то же тело, что бьёт по P), но с `AIKickerIntent`; ввод человека идёт на выбор зоны вратаря.
- **Маркер над вратарём** — cyan, на время K-теста (показать, кем сейчас управляет человек).
- **Физику нырка (`_begin_save`) не трогаем** — она уже развита (пропорциональный импульс, синхрон с клипом, `KEEPER_SAVE_ERROR`). Если ручной фил покажет «нырок не дотягивается» — отдельная follow-up задача, не блокирует эту фичу.

## Архитектура

### `KeeperIntent` (новый шов, per-actor — как `KickerIntent`)

```
class_name KeeperIntent extends RefCounted
func dive_zone() -> int:   # PenaltyLogic.Zone; читается контроллером ОДИН раз в момент удара
	return PenaltyLogic.Zone.CENTER
```

Коммита у вратаря нет — момент нырка принадлежит контроллеру (на `action_contact` бьющего), источник лишь отвечает «какая зона выбрана прямо сейчас». Это даёт «крутить вплоть до удара»: `HumanKeeperIntent.dive_zone()` каждый вызов считает зону из **текущего** стика.

- **`HumanKeeperIntent extends KeeperIntent`** — конфиг-driven (какие оси читать), маппит квадрант стика в зону через чистую функцию `PenaltyLogic.stick_to_zone(stick, deadzone)`; ввод через переопределяемые `_axis(neg,pos)` (как `HumanKickerIntent`, для headless-теста).
- **`AIKeeperIntent extends KeeperIntent`** — оборачивает `PenaltyLogic.random_dive_zone(rng)`: **один** случайный выбор при создании (кэш), `dive_zone()` всегда возвращает его. Ровно текущее поведение P, но через шов.

### `PenaltyLogic.stick_to_zone` (новая чистая функция)

```
static func stick_to_zone(stick: Vector2, deadzone: float) -> int
```
`stick.x` = боковой (лево<0/право>0), `stick.y` = вертикаль (низ<0/верх>0, уже инвертированный `aim_axis`). Длина ниже `deadzone` → `CENTER`. Иначе по знакам: (x<0,y>0)→`HIGH_L`, (x<0,y≤0)→`LOW_L`, (x≥0,y>0)→`HIGH_R`, (x≥0,y≤0)→`LOW_R`. Чистая, headless-тестируется в `check_penalty_logic` или отдельным тестом.

### `AIKickerIntent extends KickerIntent` (стаб-бьющий)

Не «чистая логика» — маленький ИИ-скрипт (как `keeper_ai.gd`), поэтому **читает `FootballConstants` напрямую**. Расширяет базовый `KickerIntent` двумя новыми методами (нужны и базе):

```
# в KickerIntent (база) — дефолты:
func has_fixed_aim() -> bool: return false
func aim_target() -> Vector2: return Vector2.ZERO
```

`AIKickerIntent`:
- В `_init(rng)`: `_start_msec = _now_msec()`; `_aim_target` = случайная точка в створе (`rng`, разброс `AI_PENALTY_AIM_SPREAD`).
- `has_fixed_aim() -> true`, `aim_target() -> _aim_target`.
- `charge_start_variant()`: `-1` пока не прошло `AI_PENALTY_THINK_TIME` с создания; затем **один раз** возвращает `0` и латчит `_charge_start_msec`.
- `charge_committed()`: `true`, когда с `_charge_start_msec` прошло `AI_PENALTY_CHARGE_RATIO * PEN_CHARGE_MAX_TIME`.
- `foot_switch()→0`, `modifier_held()→false`.
- `_now_msec() -> int` — переопределяемый (`Time.get_ticks_msec()`), чтобы тест скриптовал время без `sleep`.

Контроллер потребляет прицел полиморфно, без `is`-проверок: если `_intent.has_fixed_aim()` → `_aim = _intent.aim_target()`, иначе прежняя стик-интеграция.

### `SetPiecePresentation` — ролевой (расширение пилота)

Пилот был бинарным (`is_local_human`). Теперь — по **роли локального человека**, один факт вместо разбросанных флагов:

```
class_name SetPiecePresentation extends RefCounted
enum Role { NONE, KICKER, KEEPER, WALL }   # WALL — задел под штрафной, пока не используется
func _init(local_role: int) -> void: ...
func owns_camera() -> bool:         return _local_role != Role.NONE
func owns_hud() -> bool:            return _local_role == Role.KICKER    # ретикл/power_bar (как в пилоте)
func owns_keeper_marker() -> bool:  return _local_role == Role.KEEPER
```

Вся презентация (камера/HUD/маркер) выводится из роли в одном месте; `KeeperIntent`/`KickerIntent` не содержат presentation-методов. Затрагиваемые вызовы `SetPiecePresentation.new(true)` (в `penalty_controller.setup`) → `SetPiecePresentation.new(Role.KICKER)` — поведение P без изменений.

### `penalty_controller.gd` — интеграция

- Поле `var _keeper_intent: KeeperIntent`.
- `start_single(kicker, goal_line_z, intent=null, presentation=null, keeper_intent=null)` — пятый опциональный параметр; дефолт `AIKeeperIntent.new(_pen_rng)` (текущее поведение P). Дефолт presentation при null остаётся `Role.KICKER` (из setup).
- **Момент среза зоны** переносится из `_fire()` в `_on_kicker_contact()`: было `_struck_zone = PenaltyLogic.random_dive_zone(_pen_rng)` в `_fire`; станет `_struck_zone = _keeper_intent.dive_zone()` в `_on_kicker_contact` (перед `begin_penalty_dive`). Так человек-вратарь крутит до последнего; для ИИ-вратаря результат тот же (зона фиксирована).
- Прицел в `_aim_update`: ветка `has_fixed_aim()`.
- Маркер вратаря: простой cyan-3D-маркер над `_keeper` (паттерн `_build_reticle`/`_update_reticle`), показывается когда `_presentation.owns_keeper_marker()`.

### `match_manager.gd` — тест-триггер K

- Новый action `keeper_dive_debug` = `KEY_K` в `_setup_inputs`.
- В `_physics_process`, по образцу P-блока: при нажатии K (и `_keeper != null and not _celebrating`) — старт пенальти с `AIKickerIntent` (свой seedable rng), `SetPiecePresentation.new(Role.KEEPER)`, `HumanKeeperIntent` (конфиг осей `move_left/right`, `move_forward/back`). Бьющий — `controlled_player` (то же тело, что по P).

### Новые константы (`football_constants.gd`, секция PENALTY)

- `AI_PENALTY_THINK_TIME` (напр. 0.8с) — пауза обдумывания ИИ-бьющего до заряда.
- `AI_PENALTY_CHARGE_RATIO` (напр. 0.7) — доля заряда ИИ-бьющего.
- `AI_PENALTY_AIM_SPREAD` (0..1, напр. 0.7) — разброс прицела ИИ по створу.

## Тестирование

Headless (`tests/check_*.gd`):
- **`check_human_keeper_intent`** — `PenaltyLogic.stick_to_zone` (5 квадрантов + дедзона→CENTER) и `HumanKeeperIntent.dive_zone()` через фейковый сабкласс (скриптованные оси).
- **`check_ai_kicker_intent`** — через переопределённый `_now_msec()`: `charge_start_variant()` даёт -1 до THINK, затем 0 один раз; `charge_committed()` true после CHARGE_RATIO*MAX_TIME; `has_fixed_aim()`/`aim_target()` стабильны.
- **`check_ai_keeper_intent`** — детерминированный единственный выбор по сиду (два вызова `dive_zone()` совпадают).
- **`check_penalty_flow.gd` НЕ трогаем** — зовёт `start_single` с 2 аргументами, дефолты сохраняют прежнее поведение (регрессионная страховка).
- **Валидация сцены** после интеграции: `--quit-after 2 res://scenes/match.tscn`, дифф по baseline-категориям.

Фил (только человек за игрой, headless не драйвит):
- **P** — пенальти как было (регрессия): прицел, чип, заряд, нога, камера.
- **K** — ИИ думает-целится-бьёт; человек стиком крутит 5 зон; вратарь ныряет в выбранную зону; cyan-маркер над вратарём виден; камера — фикс-вид (та же, что у P). Ретикл/power_bar скрыты (бьёт ИИ).

## Границы (вне скоупа)

- **Тюнинг физики нырка** («честный прыжок в угол, дотягивается до мяча») — follow-up, только если фил покажет проблему. `_begin_save` не трогаем.
- **Полный планировщик `AIIntent`** (оценка кандидатов, `SetPiecePlan`) — не нужен для пенальти; появится с ИИ-стандартами, где есть кому пасовать (удар от ворот/аут/угловой/штрафной).
- **Роль WALL** в презентации — только enum-задел, поведение — с ИИ-штрафным (Этап 2).
- **Настоящий keeper-вид камеры/HUD** для человека-вратаря (Фаза B пенальти-спека) — здесь камера остаётся фикс-видом из-за спины бьющего (роадмап: «участвует локальный человек → камера стандарта включена»); специализированный вратарский HUD — позже.
- **Диспетчер судьи** не запускает этот режим — только тест-клавиша K (авто-назначение ролей — Этап 2 полной интеграции).

## Ссылки

- Роадмап: `docs/superpowers/specs/2026-07-22-match-orchestration-roadmap-design.md`.
- Пилот шва: `docs/superpowers/plans/2026-07-23-intent-seam-penalty-pilot.md`.
- Пенальти Фаза A: `docs/superpowers/specs/2026-07-15-penalty-design.md`.

# Стандартные положения и per-actor intent-шов

Шесть контроллеров стандартов ([[пенальти]], [[штрафной]], [[угловой]], [[ввод-от-ворот]],
[[вбрасывание]], [[начальный-удар]]) читают ввод **исключительно через per-actor «intent»-шов**, не
`Input.*` напрямую. Пенальти был пилотом; остальные конвертированы после. Чистый рефактор — поведение
человека бит-в-бит не менялось; цель — дать `AIKickerIntent`/`RemoteKickerIntent` драйвить любой из
шести без правки контроллера или его `*_logic.gd`.

## Общий контур контроллера

Все шесть — `extends Node`, добавлены в `match_manager._ready`, `setup(...)`-ed. Автомат
`SETUP → AIM → STRIKE` (у [[штрафной]] и [[пенальти]] есть ещё `WATCH` — фикс-камера держится после
удара). `match_manager` гейтит каждый: `_*_active` (+ `is_*_active()`); пока true, `_physics_process`
делегирует в `_*.update(delta)` и возвращается (обычный ввод/ИИ/дриблинг пропущены), `_process`
паркует `CameraPivot` в фикс-позу, заряд-бар исключён из общего гейта. **Дебаг-клавиша игнорируется
при `_celebrating`** (ожидающий `_reset_ball` телепортнул бы актёров). Дебаг-клавиши: **P** пенальти,
**Alt+K** пенальти в наши ворота, **F** штрафной, **C** угловой, **G** ввод от ворот, **T** вброс,
**O** кикофф (реальный авто-запуск есть только у кикоффа, диспетч — `match_manager`, не судья; см.
[[начальный-удар]]).

## `KickerIntent`

`scripts/match/kicker_intent.gd` (`class_name KickerIntent extends RefCounted`) — интерфейс роли
бьющего: `aim_axis() -> Vector2`, `foot_switch() -> int`, `charge_start_variant() -> int` (>=0 в кадр
нажатия кнопки заряда, иначе −1; латчит, какая кнопка начала), `charge_committed() -> bool`,
`modifier_held() -> bool` (чип пенальти), `secondary() -> bool` (короткая опция углового),
`has_fixed_aim()`/`aim_target()` (ветка фикс-аима ИИ, база `false`/`ZERO`).

- **`HumanKickerIntent`** (`human_kicker_intent.gd`) — тонкая обёртка `Input.*`, config-driven через
  `cfg: Dictionary` (ключи `aim_lat`/`aim_vert`/`foot`/`charges`/`modifier`/`secondary` называют
  реальные действия), читает через переопределяемые `_pressed`/`_just_pressed`/`_axis` (headless-тест
  сабклассит и скриптует ввод без `Input`). Каждый контроллер строит свой `_default_intent()` с cfg под
  свои прежние прямые чтения.
- **`AIKickerIntent`** (`ai_kicker_intent.gd`) — стаб (think/aim/charge + фикс-аим). `AIKickoffIntent`
  (`ai_kickoff_intent.gd`) — таймированный доворот стика (не фикс-аим).

## `KeeperIntent`

`keeper_intent.gd` — пока только в [[пенальти]] (`dive_zone()`/`step_lateral()`, латчатся на
`action_contact`, не на commit); `Human`/`AIKeeperIntent`. Остальные пять реактивной защиты вратаря не
требуют.

## `SetPiecePresentation`

`set_piece_presentation.gd` (`class_name SetPiecePresentation extends RefCounted`) — профиль владения
презентацией, ключ — `enum Role {NONE, KICKER, KEEPER, WALL}` **локального человека**: `owns_camera()`
(человек — любой актёр), `owns_hud()` (только `KICKER` — реткл/power-bar), `owns_keeper_marker()`
(только `KEEPER`). Все контроллеры по умолчанию `Role.KICKER` (сегодняшний единственный случай), так
что камера/power-bar работают как раньше, но за гейтом `if _presentation.owns_*()`.

## Проводка

`start(...)` получил хвостовые опц. параметры `intent: KickerIntent = null, presentation:
SetPiecePresentation = null`; ничего не передал → прежнее человек-только поведение
(`_intent = intent if intent != null else _default_intent()`). Все дебаг-клавиши и headless
flow-тесты (зовут `_fire_charge`/`_fire_shot` напрямую, минуя шов) работают без изменений.

## Не сделано

Авто-диспетч рестарта (кто получает `Human` vs `AIKickerIntent`) — реальный запуск контроллера есть
**только у кикоффа**, и делает его `match_manager` (`_dispatch_kickoff`), а не `MatchReferee` (сигнал
`restart_awarded` судьи пока ни к чему не подключён; см. [[начальный-удар]]). AI-поведение для четырёх
конвертированных контроллеров не добавлено — рефактор сменил лишь источник ввода. Roadmap: `docs/superpowers/specs/2026-07-22-match-orchestration-
roadmap-design.md`. Шов-тесты (инъектят фейковый `KickerIntent`, гоняют через `update()`):
`check_*_intent.gd`, `check_human_kicker_intent.gd`, `check_ai_kicker_intent.gd`,
`check_setpiece_kicker_no_touch.gd`. См. [[архитектура]] про судью.

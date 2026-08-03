# CLAUDE.md

Guidance for Claude Code (claude.ai/code) in this repository.

## What this is

OpenFootball — аркадный футбол на **Godot 4.7.1 (.NET-редакция) / GDScript + C#**, поле в масштабе
FIFA, **Windows-only**. Идёт порт ядра GameplayFootball на C# (роадмап —
`docs/superpowers/specs/2026-07-29-gameplayfootball-port-roadmap-design.md`).
Пока небольшой прототип (человек + ИИ-тиммейт против двух ИИ-соперников + вратари), не 11-на-11.
Презентация гибридная: поле/разметка/ворота/газон/мяч генерятся кодом, а **игроки — реальные
риггованные Mixamo-модели** в `PlayerVisual`.

**Текущее состояние живёт в вики: `docs/wiki/index.md` — начинать оттуда.** Этот файл несёт только то,
что сломаешь, *не зная, что надо посмотреть*; вики несёт доменную детализацию, а
`docs/wiki/константы.md` — единственный дом каждого настраиваемого числа.

## Валидация (headless)

Тестов/линта/CI нет, кроме двух команд ниже и `tests/check_*.gd`.

- **Меню-загрузка (парсит глобальные `class_name` + autoload):**
  `& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit`
- **Сцена матча (реально гоняет `match_manager`/`*_ai`/`keeper_ai`):**
  `& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 2 res://scenes/match.tscn`
- **Один check-скрипт:** `& "<godot exe>" --path "<repo>" --headless -s "res://tests/<name>.gd"`
- **C#-сборка (ядро порта):** `dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"`
  — гонять после любой правки `.cs`; headless-команды сами C# не пересобирают.

**Нужны ОБЕ headless-команды — ловят разное** (первая не грузит `match.tscn`, значит match-only скрипты
ею не парсятся). У второй есть **известный baseline ошибок** — диффай по **категории/тексту, не по
счётчику**. Подробности, флейки-тесты и baseline — [[архитектура]] и [[конвенции]] в вики.

Чувство игры (accel, поворот, отскок, ловля) headless не ловит — проверяй, реально запустив игру.

## Трип-вайры (детали — в вики по ссылке)

- **Один «мозг» — `scripts/match/match_manager.gd`** (~1000 строк, корень `match.tscn`). Владеет почти
  всем. Узлы прошиваются **кодом** (`_setup_*`, `PlayerFactory.spawn`), не в сцене. Вход —
  `main_menu.tscn`, не `match.tscn`. → [[архитектура]], [[фабрика-игроков]].
- **ИИ — дочерние `Brain`-компоненты**, не `set_script` на теле. Мозг читает тело через `_body`, не
  `self`. Менеджер достаёт ИИ через `_ai_of(body)`. Вратарь особо: тело для идентичности, `k.brain()`
  для API (объявляй `var kb: Node = k.brain()`, `:=` не компилируется). → [[архитектура]], [[вратарь]].
- **Чистая математика — отдельными классами БЕЗ autoload** (`PassSystem`, `NetSim`, `KeeperLogic`,
  `PenaltyLogic`, `FreeKickLogic`/`CornerLogic`/`GoalKickLogic`/`ThrowInLogic`/`KickoffLogic`,
  `RefereeLogic`, `PlayerMotor`-статика) — **никогда не читают `FootballConstants`**, тюнинг параметрами.
- **Gameplay и presentation разделены** — `CharacterBody3D`+мозг+коллизия vs `PlayerVisual`-ребёнок.
  Не запекай анимацию/модель в gameplay-скрипты. → [[презентация-и-ассеты]].
- **Движение — `velocity` + `move_and_slide()` через `PlayerMotor`**, не сдвиг позиции. Исключение —
  слайд подката (`move_and_collide`). → [[локомоция]], [[подкат-и-падение]].
- **Дриблинг — непрерывное lead-follow** (мяч впереди, дистанция растёт со скоростью). `SPRING_*` и
  описание пружины в OPENCODE.md — легаси, игнорируй. → [[мяч-и-дриблинг]].
- **Удар/пас — deferred-impulse (commit-action)** через `ActionExecutor`, ждут `action_contact`
  анимации, не прямой `ball.kick()`. → [[пас]], [[удар]].
- **InputMap строится программно** в `_setup_inputs()` (стирает/пересоздаёт всё в `_ready()`). Биндинги
  в `project.godot` мертвы. **Всегда правь `_setup_inputs()`.** Движение — стрелки/стик; WASD — действия.
  → [[конвенции]].
- **Гол — Law 10 «весь мяч за линией»** (опрос каждый физкадр, отмена при сейве на линии). → [[сетка-ворот]].
- **Правило бэк-паса вратаря** («мяч своих» берётся в ноги, не в руки; пас вратарю не отдаёт управление,
  пока мяч не у ног). → [[вратарь]].
- **`IN_PLACE_CLIPS` в `tools/merge_mixamo.py`** — неверная ось выглядит как «игрок парит», не как
  ось-баг; проверяй эмпирически. → [[подкат-и-падение]].
- **Константы кое-где ВНЕ файла констант:** `KICK_CHARGE_MAX_TIME`/радиус удара инлайн в
  `match_manager.gd`; тайминг ударных клипов в `ACTION_TIMING` (`player_visual.gd`). → [[константы]].

## Документация — вики это живой слой

- `docs/wiki/` — **текущее состояние**, страница на подсистему, перекрёстные `[[ссылки]]`, каталог в
  `docs/wiki/index.md`. Ты её поддерживаешь.
- `docs/wiki/глоссарий.md` — **имена предметной области** и запрещённые синонимы. Термин берётся
  отсюда для заголовков задач, имён тестов и формулировок гипотез; разрешил новый термин —
  допиши сюда. `CONTEXT.md` в корне — только указатель на эту страницу.
- `log.md` (корень) — **append-only хронология** (метод Карпатого): вехи, крупные фичи, отвергнутые
  подходы, решения. Записи `## [YYYY-MM-DD] тип | описание` (парсится: `grep "^## \[" log.md | tail -5`),
  только в конец, старое не редактируется. Завершая сессию, допиши запись `session` и обнови
  `открытые-вопросы.md` — незакрытые хвосты живут там, а не в датированном файле.
- `docs/superpowers/specs/`, `docs/superpowers/plans/` — **датированные первоисточники, не редактировать**.
  Сюда же (`docs/reports/`) кладётся handoff-пакет, когда работа продолжается в свежей сессии: он
  одноразовый и устаревает по природе, поэтому живёт среди снимков, а не в вики.

**Правило: после существенной правки обнови нужную страницу вики — не создавай новый датированный
документ.** Когда закончил задачу:
1. Перепиши устаревшие утверждения на затронутых страницах (не дописывай «UPDATE:»).
2. Менялся порог → `docs/wiki/константы.md` (она заявляет, что сверена с кодом — держи это истинным).
3. Что-то стало (не)подтверждено/сделано → `docs/wiki/открытые-вопросы.md` (закрытое удаляй).
4. Новая страница → строка в `docs/wiki/index.md` + ссылка хотя бы с одной существующей страницы.
5. Веха → строка в `log.md`.
6. Новый скрипт-подсистема → маппинг в `.claude/hooks/wiki-hint.py`.

**Доверяй вики больше датированных спеков и этого файла, но коду — больше всех трёх.** Нашёл расхождение
проза↔код — правь страницу в том же заходе. Периодически или по просьбе «проверь вики»/«wiki lint» —
запускай скилл `wiki-lint` (`.claude/skills/wiki-lint/`).

Три хука (`.claude/hooks/`, на Python — `python3` тут сломанный алиас Microsoft Store, вызывается
`python`; проводка в `.claude/settings.json`) подпирают это механически: session-start оглавление вики,
per-edit подсказка «читай эту страницу первой», stop-check «код менялся — вики нет».

## Workflow

- Where a task matches an installed skill, use that skill — but only when it's genuinely appropriate to the task, not by default. Don't force-fit a skill onto work it wasn't meant for.
- Long-running processes (long builds, model training, long test runs, migrations) must not block the main conversation: launch them via a background agent (Agent tool, `run_in_background: true`) rather than a blocking Bash call, have the agent log progress periodically rather than only at the end, and continue other work or respond to the user while it runs.

Скиллы проекта (`.claude/skills/`):
- `wiki-lint` — когда просят «проверь вики»/«wiki lint»/«проверь константы», а также перед крупной
  задачей, опирающейся на документацию: битые `[[ссылки]]`, сироты, расхождения с
  `football_constants.gd`, противоречия между страницами.
- `handoff` — user-invoked (`disable-model-invocation`), сам не вызывается: когда человек просит
  собрать пакет для продолжения в свежей сессии.

Задачи ведутся цепочкой скиллов: локальный markdown-трекер в `.scratch/`, конфигурация в
`docs/agents/`. Звенья цепочки набирает человек — это user-invoked скиллы, агент их не вызывает.
Задача дозрела до звена — назови команду и дождись её; звено, пройденное по памяти вместо скилла,
даёт похожий на вид документ без правил, ради которых оно существует. Вся цепочка целиком — в
скилле `ask-matt`, читается по месту.

## Agent skills

### Issue tracker

Задачи и спеки — markdown-файлами в `.scratch/<feature>/` внутри репозитория; GitHub Issues не
используются, `gh` CLI не установлен. См. `docs/agents/issue-tracker.md`.

### Triage labels

Пять канонических ролей строками `Status:` в файле тикета, имена совпадают с каноническими
(`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`).
См. `docs/agents/triage-labels.md`.

### Domain docs

Single-context: словарь — `docs/wiki/глоссарий.md` (корневой `CONTEXT.md` — указатель на него),
живое состояние подсистем — `docs/wiki/`, решения — `docs/adr/` по мере появления.
См. `docs/agents/domain.md`.

## 1. Think Before Coding
Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:

State your assumptions explicitly. If uncertain, ask.
If multiple interpretations exist, present them - don't pick silently.
If a simpler approach exists, say so. Push back when warranted.
If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First
Minimum code that solves the problem. Nothing speculative.

No features beyond what was asked.
No abstractions for single-use code.
No "flexibility" or "configurability" that wasn't requested.
No error handling for impossible scenarios.
If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes
Touch only what you must. Clean up only your own mess.

When editing existing code:

Don't "improve" adjacent code, comments, or formatting.
Don't refactor things that aren't broken.
Match existing style, even if you'd do it differently.
If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

Remove imports/variables/functions that YOUR changes made unused.
Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution
Define success criteria. Loop until verified.

Transform tasks into verifiable goals:

"Add validation" → "Write tests for invalid inputs, then make them pass"
"Fix the bug" → "Write a test that reproduces it, then make it pass"
"Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## Выбор модели Claude

Проект использует несколько моделей Claude под разные задачи (решено 2026-07-29, после разбора
[2026-07-29-gameplayfootball-port-roadmap-design.md](docs/superpowers/specs/2026-07-29-gameplayfootball-port-roadmap-design.md)).
Разница не в «умении», а в глубине автономной работы и цене ошибки.

| Задача | Модель | Почему |
|---|---|---|
| Стратегия, гриль, архитектурные решения, спеки, планы фаз | **Fable 5** | Сильнейшая в навигации по неоднозначности и длинных рассуждениях |
| Порт критичной математики порта (варпинг, smuggle, выбор анимаций) | **Fable 5** | Ошибка в порядке применения констант не ловится компилятором; Fable лучшая в first-shot реализации хорошо специфицированных систем и долгих автономных прогонах |
| Порт остального ядра, механический перенос C++→C#, многофайловая агентная работа | **Opus 5** | Рабочая лошадь агентного кодинга, доводит задачи до конца без заглушек, вдвое дешевле Fable |
| Ревью порта против C++ оригинала, охота за расхождениями констант | **Fable 5** или **Opus 5** | Обе сильны в поиске реальных багов и параллельных субагентах |
| Тюнинг ощущений, мелкие правки, быстрые итерации «поправь-запусти-посмотри» | **Sonnet 5** | Почти-Opus в кодинге, быстрее и втрое дешевле — цикл тюнинга это десятки мелких итераций |
| Вики, log.md, коммиты, документация, рутинный chore | **Sonnet 5** | Глубина не нужна, объём большой |

**Правило:** если для текущей задачи по этой таблице рекомендована другая модель, чем активная в
сессии — спроси пользователя явно, хочет ли он продолжить именно на текущей модели, прежде чем
браться за задачу. Не переключай модель молча и не отказывай в работе — только уточняющий вопрос.

## Конвенции

- Отвечать по-русски (предпочтение пользователя); комментарии и доки — на русском.
- Conventional Commits (`feat:`/`fix:`/`refactor:`/`docs:`/`chore:`/`test:`/`perf:`).
- `docs/football_reference.md` — свод правил FIFA + гейм-дизайн; читать перед работой над разметкой,
  воротами, правилами. `AGENTS.md`/`OPENCODE.md` — краткие гайды (указывают сюда и в вику).

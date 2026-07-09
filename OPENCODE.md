# OpenFootball

Футбольный симулятор (клон FIFA) на Godot 4.7.
Аркада с реалистичными правилами, полу-реалистичный стиль (модели Mixamo), physics-based.

---

## Технический стек

- **Godot 4.7** (stable), GDScript
- **Rendering:** mobile + gl_compatibility (нормальный рендеринг, не headless)
- **Windows** only (другие платформы в далёком будущем)

## Поле

- **Реальный размер (FIFA):** 105m (длина, Z) × 68m (ширина, X)
- Центр поля в `(0, 0, 0)`. Поле симметрично:
  - Z: от -52.5 до +52.5 (длина)
  - X: от -34 до +34 (ширина)
- Ось Y = высота
- **Ворота — ТОЛЬКО вдоль оси Z** (никогда по X или Y):
  - Home ворота: `(0, 1.22, -52.5)` — сторона -Z
  - Away ворота: `(0, 1.22, +52.5)` — сторона +Z
  - Ширина ворот: 7.32m, высота: 2.44m
- Полная разметка: штрафные (16.5m), вратарские (5.5m), центр. круг (радиус 9.15m)
- Невидимые стенки по краям поля (4m высотой)

**Игроки атакуют в сторону -Z (Home → Away), AI защищает ворота на -Z и атакует +Z.**

## Игроки

- **Геймплей:** `CharacterBody3D` + `CollisionShape` (капсула 0.3×1.5) + AI/ввод-скрипт
- **Презентация:** дочерний `PlayerVisual` (`scenes/player_visual.tscn`) — риггованная модель Mixamo (`assets/models/footballer.glb`) с `AnimationTree` idle↔run. Геймплей и презентация **разделены**; скорость в визуал передаёт `PlayerMotor` через `set_locomotion(velocity)` каждый физический кадр
- Команда игрока (home + напарник, team_1): **синий** (`Color(0.1, 0.1, 0.9)`)
- Соперник (AI, team_2): **красный** (`Color(0.9, 0.1, 0.1)`)
- Цвет = тинт всего тела через `apply_appearance` (пилот; настоящие киты — в будущем)
- Скорость: константы `LOCO_TOP_SPEED` / `LOCO_SPRINT_SPEED` в `FootballConstants` (применяются через `PlayerMotor`)
- **11v11, составы, вариативность (кожа/волосы/причёски) — в будущем**

## Мяч

- **RigidBody3D**, радиус 0.11m, масса 0.43kg
- Процедурная текстура (белый + чёрные шестиугольники PNG)
- Drag: `0.985` (горизонталь), `0.999` (вертикаль)
- **Дриблинг:** velocity-matching через `_integrate_forces` (НЕ spring-force)
  - Скорость мяча = скорость дриблера + скорректированное смещение (`disp * 30`, кламп 12)
  - `SPRING_*` константы в `football_constants.gd` — legacy, не используются
  - После удара/паса kicker не может подхватить мяч 1.5 секунды

## Локомоция (PlayerMotor)

- **Движение — velocity + inertia + `move_and_slide()`** через компонент `PlayerMotor` (`scripts/player/player_motor.gd`)
- Каждый полевой игрок получает `PlayerMotor` как третьего ребёнка (после `PlayerVisual` и `CollisionShape3D`)
- Код (ввод/AI) вызывает только `motor.set_move_intent(dir: Vector3, speed_scale: float)` раз в кадр — прямые манипуляции `global_position`/`rotation` запрещены
- `PlayerMotor` внутри:
  - Интегрирует velocity к целевой скорости (ускорение `LOCO_ACCEL`, замедление `LOCO_DECEL` — асимметрично, плавный выбег при отпускании)
  - Плавно поворачивает корпус по рысканью (`LOCO_TURN_ROT`, отключено ниже `LOCO_TURN_MIN_SPEED`)
  - Вычисляет сглаженный угол крена/банкинга от бокового ускорения → `PlayerVisual.set_lean()`
  - Вызывает `move_and_slide()`, затем фиксирует `global_position.y` (поле плоское), кроме состояния `fallen`
- **`set_control_locked(true)`** — блокирует управление (для удара/паса/подката); velocity мгновенно в ноль
- **Sprint** (Shift) — человеческий игрок, повышенный `speed_scale`, без выносливости
- **`PlayerMotor.find_on(node)`** (static) — канонический поиск мотор-компонента у игрока
- Константы настройки: `FootballConstants.LOCO_*`

## Управление

| Клавиша | Действие |
|---------|----------|
| W/↑ | Вперёд |
| S/↓ | Назад |
| A/← | Влево |
| D/→ | Вправо |
| Space | Удар: удержание = зарядка (1с до макс), отпускание = выстрел. Анимация `pass` (временно), импульс по `action_contact` |
| E | Пас: мгновенный выстрел по `action_contact` (0.2с), анимация `pass` |
| Q | Смена управляемого игрока |
| Shift (удержание) | Спринт (только человек) |
| Escape | Пауза |

InputMap настраивается **программно** в `_setup_inputs()` — не через `project.godot`.

## Структура проекта

```
OpenFootball/
├── OPENCODE.md            ← этот файл
├── project.godot
├── scenes/
│   ├── main_menu.tscn     — меню, кнопка Start Match
│   ├── match.tscn         — корневая сцена матча
│   ├── ball.tscn          — мяч (RigidBody3D)
│   ├── player.tscn        — игрок (CharacterBody3D)
│   ├── player_visual.tscn — риггованная модель + тинт (ребёнок каждого игрока)
│   └── pitch.tscn         — поле (плоскость + разметка)
├── scripts/
│   ├── data/
│   │   └── football_constants.gd  — автозагрузка, все константы (в т.ч. LOCO_*)
│   ├── ui/
│   │   └── main_menu.gd    — логика меню
│   ├── match/
│   │   └── match_manager.gd  — вся логика матча
│   ├── player/
│   │   ├── player_controller.gd — управление игроком
│   │   ├── player_motor.gd  — PlayerMotor: velocity+inertia locomotion (accel/decel/turn/lean/sprint)
│   │   └── player_visual.gd — PlayerVisual: AnimationTree idle/run/sprint + apply_appearance
│   ├── ai/
│   │   ├── simple_ai.gd    — AI противника (team_2, красный)
│   │   └── teammate_ai.gd  — AI напарника (team_1, синий; также для PlayerHome когда не под управлением человека)
│   ├── ball/
│   │   └── ball_controller.gd  — физика мяча, дриблинг (velocity-matching)
│   └── camera/
│       └── match_camera.gd — FIFA-style камера
├── assets/
│   └── models/
│       ├── footballer.glb  — модель Mixamo + idle/run/sprint (собрано Blender-скриптом)
│       └── mixamo_src/     — сырые FBX (gitignored, не коммитятся)
├── tools/
│   └── merge_mixamo.py     — Blender headless: FBX → glb
├── tests/                  — headless CHECK-скрипты (godot --headless -s)
├── ASSET_CREDITS.md        — источники/лицензии ассетов
└── resources/   — formations, players, teams (пока пусто)
```

## Что уже реализовано (MVP)

- [x] Матч 1v1 (человек + AI)
- [x] Поле с полной разметкой (FIFA-стандарт)
- [x] Ворота с Area3D-детекцией голов
- [x] HUD со счётом
- [x] FIFA-style камера (слежение за мячом сверху-сзади)
- [x] Управление WASD + Space (удар) + E (пас)
- [x] Дриблинг (velocity-matching, мяч «приклеен» к ноге)
- [x] AI: бежит к мячу, дриблит, бьёт по воротам
- [x] Сброс мяча после гола
- [x] Невидимые стенки по краям
- [x] Слайд-подкат (Area3D-детекция, state machine)
- [x] Риггованные модели игроков (Mixamo) + анимации idle/run/sprint через `PlayerVisual`
- [x] `PlayerMotor` — locomotion через velocity + inertia + `move_and_slide()` (accel/decel/turn/lean)
- [x] Sprint (Shift, человек), переключение игрока (Q)
- [x] Цвета команд тинтом (синий/красный)
- [x] Collision layers: 3 отдельных слоя (default / player / boundary) — игроки не маскируют мяч
- [x] **Удар с зарядкой:** Space — удержание для зарядки (1с, сила 12–25), отпускание → анимация `pass` → `action_contact` (t=0.35) → `ball.kick()`. PowerBar с градиентом зелёный→жёлтый→красный, авто-выстрел при макс. заряде
- [x] **Пас:** E — мгновенный, анимация `pass` → `action_contact` (t=0.2) → `ball.kick(dir, 12.0)`
- [x] **Commit-action система:** `_fire_kick()`/`_pass_ball()` выставляют `_action_player`, `_action_dir`, `_action_power`, флаг `_kick_action_active=true`, запускают анимацию. Реальный `ball.kick()` отложен до сигнала `action_contact` от `PlayerVisual`. Флаг `_kick_action_active` позволяет вводу пропустить motor-lock early-return во время удара/паса

## Что НЕ реализовано (ближайшие планы)

- [ ] Таймер матча (90 мин, 2 тайма)
- [ ] 11v11 (расстановки, позиции)
- [ ] Офсайд, ауты, угловые, штрафные
- [ ] Физическая сетка ворот
- [ ] Анимации: подкат, сейв; kick-клип (сейчас `pass` для обоих), вратарские анимации
- [ ] Настоящие киты (шейдер-маска) + вариативность игроков (кожа/волосы/причёски)
- [ ] CC0-реквизит (мяч, ворота, стадион) вместо процедурного
- [ ] Звуки (удар по мячу, гол, свисток, трибуны)
- [ ] Меню выбора команд
- [ ] Карьера тренера (далёкое будущее)
- [ ] LAN мультиплеер (далёкое будущее)

## FIFA/PES Reference

- **Камера:** классическая FIFA — над и позади мяча, смотрит по направлению атаки
- **Физика мяча:** drag с затуханием, отскок от газона (реализовано в `_integrate_forces`), отскок от штанг
- **Дриблинг:** мяч «приклеен» к ноге — не отлетает при беге, следует за поворотом игрока
- **Удар/пас:** направление по движению игрока (не по тому, куда смотрит камера)
- **Приём мяча:** автоматический, в радиусе 1m
- **AI:** прессинг ближайшего к мячу, при дриблинге движется к воротам, бьёт с дистанции

## Архитектурные решения

- `CharacterBody3D` для игроков, `RigidBody3D` для мяча — бесплатная физика
- **Три компонента на игрока:** gameplay (`CharacterBody3D` + AI/input) / motor (`PlayerMotor`, locomotion) / visual (`PlayerVisual`, модель + анимация). Каждый — отдельный дочерний узел; общаются через публичный API (`set_move_intent`, `set_locomotion`, `set_lean`)
- **Локомоция через `PlayerMotor`:** velocity + inertia + `move_and_slide()`. Никаких прямых `global_position`/`rotation`. Вызов `motor.set_move_intent(dir, speed_scale)` — единственный способ движения
- **Collision layers — три отдельных слоя:** default (бит 1: поле + мяч, для Area3D-детекции), player (бит 2: `PLAYER_COLLISION_MASK`), boundary (бит 3: `BOUNDARY_COLLISION_LAYER`). Игроки не маскируют слой мяча — иначе `move_and_slide()` физически цепляет мяч (дёрганый дриблинг)
- Дриблинг через velocity-matching в `_integrate_forces` — мяч копирует скорость дриблера + коррекция позиции (`disp * 30`, кламп 12)
- InputMap настраивается программно в `_setup_inputs()` — `project.godot` не используется
- **Разделение геймплей/презентация:** физика/AI на `CharacterBody3D` не знают про модель; визуал — отдельный `PlayerVisual`, получает скорость от `PlayerMotor.set_locomotion()`
- Модели/анимации игроков — Mixamo, собираются в `.glb` через headless Blender (`tools/merge_mixamo.py`); в репо только `.glb`, сырые FBX gitignored (public/open-source)
- Автозагрузка `FootballConstants` — все числовые константы в одном месте (включая `LOCO_*`)
- **Commit-action с deferred impulse:** удар/пас не применяют `ball.kick()` сразу. Вместо этого `_fire_kick()`/`_pass_ball()` выставляют `_action_player`/`_action_dir`/`_action_power`, включают флаг `_kick_action_active=true`, запускают анимацию через `PlayerVisual.trigger(anim)`. Когда анимация доходит до кадра соприкосновения — `action_contact` сигнал → `_on_action_contact()` → `ball.kick()`. Флаг `kick_action_active` единственный пропускает motor-lock early-return в `_handle_player_input`. Это даёт синхронизацию анимации и физики мяча без motor-lock.
- Анимации (`idle`/`run`/`sprint`/`pass`) в `footballer.glb`, тайминги контакта и конца в `PlayerVisual.ACTION_TIMING`. Pipelines: `tools/merge_mixamo.py` (Blender headless) + Godot `--headless --import`; FBX-исходники в `mixamo_src/` gitignored
- `docs/football_reference.md` — полный референс FIFA-правил и гейм-дизайна (читай перед работой над полем/воротами/механиками)

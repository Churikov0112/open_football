# Порт GameplayFootball, фаза 4: smuggle + физика мяча — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Цель:** мяч живёт по физике оригинала (`Ball::CalculatePrediction`: гравитация, drag, трава, отскок,
трение, штанги, вращение, магнус, предсказание 3000 мс), а игрок «жульнически» подтягивается к нему
всем скелетом (`GetBestCheatableAnimID` + action/movement/rotation-smuggle) и реально касается:
дриблинг, трап, пас, удар. Приёмка по роадмапу: **касания/пасы/удары в лаб-сцене, нога у мяча в кадр
контакта** (глазами).

**Архитектура:** два переплетённых куска. (1) `Gpf.Ball` — дословный порт `ball.cpp` минус сетка
(решение роадмапа: наш `NetSim` лучше) минус звук/сцена/temporal smoothing; кэш предсказаний 300 точек
по 10 мс, первый шаг интеграции = новое состояние. (2) Слой наследника `Humanoid` — porт в
`src/gpf/Humanoid.cs` как **partial той же C#-класса `HumanoidBase`** (файл-граница повторяет границу
база/наследник C++): контур `Process` наследника (ReQueue, touch-исполнение, смагглы), `SelectAnim`
наследника (crude-query + сорт-цепочки + `GetBestCheatableAnimID`), `GetBodyBallDistanceAdvantage`,
`CalculateMovementSmuggle`, touch-векторы (`humanoid_utils.cpp`). Новая лаб-сцена `ball_lab.tscn` —
игрок + мяч, глазная приёмка. `walk_lab` не трогается (эталон фазы 3).

**Tech stack:** Godot 4.7.1 .NET (`net8.0`), C#-ядро + GDScript check-харнесс.

**Первоисточники:** роадмап [2026-07-29-gameplayfootball-port-roadmap-design.md](../specs/2026-07-29-gameplayfootball-port-roadmap-design.md) (п. 4 фазировки),
тех-отчёт [2026-07-29-gameplayfootball-core-report.md](../specs/2026-07-29-gameplayfootball-core-report.md).
C++-оригинал: `C:\Users\User\Desktop\projects\FootballCPP` (read-only; все номера строк — от него).
Ключевые файлы:
- `src/onthepitch/ball.cpp` (:23-29 константы, :91-135 Touch/SetPosition/SetMomentum/SetRotation,
  :137-537 CalculatePrediction, :539-551 GetAveragePosition, :562-585 Process, :602-615 ResetSituation),
  `ball.hpp` (:51-57 Predict).
- `src/onthepitch/player/humanoid/humanoid.cpp` (:40-65 константы, :92-360 Process наследника,
  :360-646 touch-исполнение, :648-781 смагглы+apply, :1143-1157 GetHasteFactor, :1159-1820 SelectAnim,
  :1822-1857 NeedTouch, :1859-1997 GetBodyBallDistanceAdvantage, :1999-2323 GetBestCheatableAnimID,
  :2326-2408 CalculateMovementSmuggle, :2410-…​ GetBestPossibleTouch), `humanoid.hpp` (:45 объявление,
  Anim-структура).
- `src/onthepitch/player/humanoid/humanoid_utils.cpp` (:103-115 GetFrontOfFootOffsetRel,
  :146-206 GetDifficultyFactors, :208-332 GetBallControlVector, :334-352 GetTrapVector,
  :354-520 GetShotVector).
- `src/onthepitch/match.cpp` (:1926-2045 CheckBallCollisions).
- `src/gamedefines.hpp` (:56 ballPredictionSize_ms, :64 defaultTouchOffset_ms, :66 defaultPlayerHeight,
  :271-279 размеры поля/ворот, :175-229 PlayerCommand/TouchInfo).
- `src/base/geometry/line.cpp` (:60-71 GetClosestToPoint), `src/base/math/quaternion.cpp`
  (GetRotationTo/GetRotationAngle/GetRotationMultipliedBy/SetAngles — номера строк найти grep'ом).
- `src/onthepitch/player/playerbase.cpp` / `player.cpp` (GetLastTouchBias, HasPossession — grep).

**ВАЖНО — главный урок фазы 3, здесь острее всего:** `GetBestCheatableAnimID` существует ТОЛЬКО в
наследнике `Humanoid` (`humanoid.hpp:45`), в `HumanoidBase` его нет вообще. В отличие от
`CalculatePhysicsVector` (был и там и там), здесь портировать «по базе» нечего — весь механизм
переносится с наследника. Не искать эквивалент в `humanoidbase.cpp` — там его нет.

## Global Constraints

- **Godot exe:** `C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe` (единственный валидный).
- **Перед любым headless-тестом — `dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"`**: headless-команды C# сами не пересобирают.
- **Порт дословный, bug-for-bug, каждая функция и каждый числовой литерал — с комментарием-ссылкой
  `файл:строки` C++.** Спорные места НЕ чинить молча. Главный риск — не код, а константы и порядок их
  применения: у smuggle ~20 калиброванных чисел (`cheatFactor=0.5` humanoid.cpp:43,
  `cheatDiscardDistance=0.02` :46, `radiusFactor=0.3*(1-awkwardness)` :2172 и его множители по типам
  :2174-2186, эллипс :1935-1945), у мяча — bounce/friction/drag/magnus (:23-29) и порядок их
  применения в одном шаге интеграции (:167-533). Расхождение = «мимо мяча»/дёрганые касания,
  компилятором не ловится.
- **Опорные числа в тестах — только из сырых ключей `.anim`/данных и формул C++, перевычисленных в
  самом тесте** (урок всех трёх фаз: план систематически ошибался — данные нет). Тест не берёт
  эталонное число из этого документа.
- **Сортировки только `AnimSelector.StableSort`** — задача 3 добавляет НОВЫЕ сорт-цепочки
  (priority/idlelevel/foot/bodydir/velocity/baseanim) — все через StableSort, `List.Sort` запрещён.
- **Seeded-RNG (`GpfRng`) внутри ядра** — никакого `Godot.randf`/`GD.Randf`/`System.Random` без сида.
  Все `random(a,b)` оригинала (GetDifficultyFactors, GetShotVector, deflect/interfere/sliding-ветки,
  CheckBallCollisions) идут через один инжектируемый генератор. Последовательность НЕ совпадёт с
  эталон-exe (у них unseeded boost) — допустимое расхождение, фиксируется в вики.
- **Float-парсинг — только `CultureInfo.InvariantCulture`** (`BluntMath.AtoF`/`AtoI`).
- **Namespace `Gpf`**, ядро без `[GlobalClass]`, без чтения `FootballConstants`, без Godot-нод внутри
  логики. Тюнинг — параметрами.
- **Данные `assets/gpf/**` — read-only.**
- **Оси:** ядро — «их» пространство (Z-вверх, вперёд −Y); конверсия — только базис `GpfSpace`.
- **Интероп GDScript↔C#:** `var x := ...` не выводит тип из C#-Variant — тип явно; C#-дефолт-аргументы
  моста не переносятся — звать полным списком; методы с `out`-параметрами через мост не зовутся —
  обёртки-геттеры; статики зовутся прямо на `load("res://src/gpf/X.cs")`.
- **Check-скрипты** — конвенции репо: `extends SceneTree`, `_initialize()`, аккумулятор `ok`,
  `print("CHECK FAIL: ...")` построчно, финал `print("CHECK PASS" if ok else "CHECK FAIL")` +
  `quit(0 if ok else 1)`. Новый `.gd` требует `.uid`: после создания прогнать
  `& "<godot exe>" --path "<repo>" --headless --import` и закоммитить `.uid` вместе со скриптом.
- **Обе стандартные headless-валидации** в финале каждой задачи, затрагивающей `src/` или
  `project.godot`; baseline ошибок матч-сцены диффать по категории/тексту, не по счётчику.
- **Коммиты** — Conventional Commits, описания по-русски.
- **Вики не трогать до задачи 10** (там всё разом).
- **Модель по таблице CLAUDE.md:** задачи 2, 4, 5, 7 — критичная математика порта (**Fable 5**);
  задачи 1, 3, 6, 8 — механический перенос/сцена (**Opus 5**); задачи 9, 10 — chore/доки (**Sonnet 5**,
  задачу 9 можно Opus).
- **Скорости** (`gamedefines.hpp:18-27`): idle 0 / dribble 3.5 / walk 5.0 / sprint 8.0, `AnimSprint`
  7.0; переключатели 1.8 / 4.2 / 6.0. Радиус мяча **0.11** — хардкод оригинала по всему коду (не
  константа!), переносится литералом с комментарием.

## Скоуп фазы 4 — решения, принятые ДО кода

1. **Порядок кусков: мяч раньше smuggle.** `GetBestCheatableAnimID` читает предсказание мяча
   (`GetBallPrediction(animTouchFrame*10)`, :2099) — без `Gpf.Ball` smuggle нечем кормить.
2. **MentalImage НЕ портируется** (слой ИИ, по роадмапу — после фазы 4). Всюду, где оригинал зовёт
   `currentMentalImage->GetBallPrediction(t)`, порт зовёт `_ball.Predict(t)` напрямую — это ровно
   MentalImage с нулевой задержкой восприятия (`mentalimage.cpp:87-105` деградирует к
   `match->GetBall()->Predict` при reactionTime 0). Каждое такое место — комментарий
   `// MentalImage-шов: оригинал humanoid.cpp:NNNN, задержка восприятия придёт с ИИ-фазой`.
3. **ReQueue портируется в этой фазе** (закрывает открытый вопрос фазы 3). BallControl-очередь
   оригинала перевыбирает клип едва ли не каждый тик (маски `% 20/30/40/50/80` мс, :161-184) — без
   ReQueue smuggle не даст оригинальной отзывчивости. Порт: константы :56-63, гейты :140-212,
   отказные фильтры :1192-1234, «не в тот же квадрант» :1727-1742.
4. **`Humanoid`-код — в `src/gpf/Humanoid.cs` как `public partial class HumanoidBase`** (partial той
   же класса). Судьи (голый `HumanoidBase` оригинала) в порт не входят никогда; граница файлов
   повторяет границу классов C++, не ломая 17 существующих тестов и мост. Шапка файла это объясняет.
5. **AI_GetPass/AI_GetShotDirection НЕ портируются** (ИИ-слой). Refine-блок паса (:474-505) и удара
   (:550-566) пропускается: `ballDirection`/`ballPower` берутся из `originatingCommand.TouchInfo`
   напрямую, с комментарием-швом (вернётся с Eliza). Всё остальное в touch-ветках — дословно.
6. **Сетка ворот вырезана** (`netting`, ball.cpp:333-408) — решение роадмапа, наш `NetSim`.
   `ballTouchesNet` не переносится. Штанги/перекладина (:240-328) — переносятся с их константами
   (`goalHalfWidth=3.7` и т.д., gamedefines.hpp:277-279): интеграция с нашим полем — не эта фаза.
7. **Коллизии мяч↔тело — AABB по костям утилитарного скелета** (приближение: оригинал берёт AABB
   Geometry-сегментов, `match.cpp:1991`; у палочника геометрии нет). Сегмент кости = отрезок
   родитель→ребёнок, AABB с паддингом. Расхождение документируется в [[открытые-вопросы]] (родственно
   существующему пункту про `touch_bodypart`).
8. **Одиночная лаба упрощает командный контекст** — в `ball_lab` один игрок: он всегда
   `designatedPossessionPlayer` своей команды и матча, соперников нет
   (`GetClosestOpponentDistance` → большая константа, множитель толкучки :2314 == 1.0), ретейнера нет.
   Все эти значения — **параметры/поля с дефолтами**, не выпиленные ветки: ветки портируются дословно
   и оживут в матче.
9. **`GetTimeNeededToGetToBall_ms` (нужен `CalculateMovementSmuggle`, :2340-2345) — лаб-суррогат**:
   `дистанция_до_мяча / GetMaxVelocity * 1000`, сеттером `SetTimeNeededToGetToBall(uint ms)`; честный
   расчёт — ИИ-фаза. Комментарий-шов обязателен.
10. **Высота игрока — параметр `PlayerHeight`, дефолт 1.92** (`defaultPlayerHeight`,
    gamedefines.hpp:66): масштаб `animBallPos.z` (:2118) при дефолте == 1.0.
11. **Фикс-тик матча 100 Гц — отдельная задача 9** (решение именно этой фазы, откладывать нельзя).
12. **Bump-прерывание (:129-134) в оригинале ЗАКОММЕНТИРОВАНО** — переносится как комментарий (не
    живой код!), сторож «FLYING PLAYERS» (:338-340) — живой код, переносится.

**НЕ портируется в фазе 4** (в [[открытые-вопросы]] задачей 10):
- MentalImage/ElizaController/командные очереди ИИ (`RequestCommand`) — следующая фаза по роадмапу.
- `Header`/`Catch`/`Special`-исполнение касания (вратарь/голова) — ветки select'а фильтруют эти типы,
  но touch-исполнение только для BallControl/Trap/Pass/Shot/Interfere/Deflect/Sliding (все, что есть
  в :390-646). Catch-исполнения в :390-646 нет и у оригинала (вратарские руки — другой контур).
- `SelectRetainAnim` (:1087-1136) и вынос ретейнера из штрафной (:745-760) — вратарский контур.
- Temporal smoothing / Put-буферы / звук — презентация, у нас своя.
- `GetTeamPossessionAmount` в `GetHasteFactor` (:1152-1154) — зовётся с
  `considerOpponentProximity=false` во всех местах фазы 4 (:1683, :1690, :1697, :1711) — ветка
  портируется, но мертва; команда придёт с ИИ-фазой.

## Уроки фаз 1-3, применённые здесь

1. Опорные числа тестов — из сырых `.anim`-ключей и формул C++, перевычисленных в тесте.
2. Bug-for-bug с комментарием-ссылкой; спорное не чинить: `radiusOffset_ret = 1000.0f` с todo «is
   this still in use?» (:2227), `lol varnames` (`powerFac`, ball.cpp:231), `volatile radian factor`
   (:443 — в C# просто `float`, комментарий), мёртвая lenient/strict-диагностика (:1383-1435 —
   не переносится, это закомментированный debug), деприкейтед method 2 дискарда (:2269-2278 — как
   комментарий).
3. Все sort'ы — только `AnimSelector.StableSort`.
4. Путь игроков — наследник `Humanoid`: SelectAnim, Process-контур, смагглы — всё отсюда.
5. Seeded-RNG везде вместо `random()`.
6. Закрываются открытые вопросы фазы 3: ReQueue (решение п.3 выше), movementSmuggle наследника
   (:1785), порядок слагаемых apply-буфера наследника (:769), `anim`/`smooth`/`smoothFactor` в
   apply-буфере (:275-284), сторож z==0, movement-отбор наследника (lenient/strict, bySide —
   задача 3 портирует `Humanoid::SelectAnim` целиком, включая movement-ветку).

---

### Задача 1: фундамент — кватернионы, Line, GpfRng, константы поля (Opus 5)

**Files:**
- Modify: `src/gpf/QuatUtil.cs` (добавить `SetAngles`, `GetRotationTo`, `GetRotationAngle`,
  `GetRotationMultipliedBy`)
- Modify: `src/gpf/BluntMath.cs` (добавить `LineClosestToPoint`)
- Create: `src/gpf/GpfRng.cs`
- Create: `src/gpf/GpfPitch.cs`
- Test: `tests/check_gpf_ball_foundation.gd`

**Interfaces:**
- Consumes: `QuatUtil.GetAngles` (фаза 2), `BluntMath` (фаза 2).
- Produces (для задач 2, 4, 5, 7):
  - `QuatUtil`: `Quaternion SetAngles(float x, float y, float z)` (порт `Quaternion::SetAngles`,
    quaternion.cpp — найти grep'ом, перенести их порядок осей ДОСЛОВНО — он парный к `GetAngles`
    фазы 2: `SetAngles(GetAngles(q)) == q` с точностью до знака);
    `Quaternion GetRotationTo(Quaternion from, Quaternion to)` (их `GetRotationTo`: `to * from^-1`
    или как в источнике — сверить!); `float GetRotationAngle(Quaternion q, Quaternion reference)`
    (угол между, их формула); `Quaternion GetRotationMultipliedBy(Quaternion q, float factor)`
    (масштаб угла вокруг той же оси).
  - `BluntMath.LineClosestToPoint(Vector3 v0, Vector3 v1, Vector3 point) -> float` — порт
    `Line::GetClosestToPoint` (line.cpp:60-71): 2D-проекция (только coords[0]/[1]!), возврат `u`.
  - `Gpf.GpfRng` — детерминированный PRNG: `GpfRng(ulong seed)`, `float Uniform(float min, float max)`,
    `void Reseed(ulong seed)`. Реализация — xorshift64* (или PCG32) с равномерным `[min,max]`;
    формулу зафиксировать в комментарии. Замена `random(a,b)` оригинала (unseeded boost) — сид у нас,
    распределение то же.
  - `Gpf.GpfPitch` — статик-константы оригинала: `PitchHalfW=55f, PitchHalfH=36f, LineHalfW=0.06f`
    (gamedefines.hpp:271-275), `GoalDepth=2.55f, GoalHeight=2.5f, GoalHalfWidth=3.7f` (:277-279),
    `DefaultPlayerHeight=1.92f` (:66), `DefaultTouchOffsetMs=80` (:64), `BallPredictionSizeMs=3000`
    (:56), `BallHistorySizeMs=4000` (:57), `BallDistanceOptimizeThreshold=10f` (:59).

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 4, задача 1: кватернионные примитивы (quaternion.cpp), Line (line.cpp:60-71),
# GpfRng, константы поля (gamedefines.hpp). Ожидания — математические тождества и формулы C++,
# перевычисленные здесь; НЕ литералы из плана.

func feq(a: float, b: float, eps := 1.0e-5) -> bool:
	return absf(a - b) < eps

func _initialize() -> void:
	var ok := true
	var Q = load("res://src/gpf/QuatUtil.cs")
	var BM = load("res://src/gpf/BluntMath.cs")
	var RNG = load("res://src/gpf/GpfRng.cs")
	var P = load("res://src/gpf/GpfPitch.cs")
	if Q == null or BM == null or RNG == null or P == null:
		print("CHECK FAIL: C#-скрипты не найдены — сначала dotnet build")
		quit(1)
		return

	# --- SetAngles/GetAngles — пара (тождество на произвольном кватернионе) ---
	var src: Quaternion = Q.AngleAxis(0.37, Vector3(0.2, -0.5, 0.84).normalized())
	var ang: Vector3 = Q.GetAnglesVec(src)
	var back: Quaternion = Q.SetAngles(ang.x, ang.y, ang.z)
	if not (back.is_equal_approx(src) or back.is_equal_approx(-src)):
		print("CHECK FAIL: SetAngles(GetAngles(q)) != q: ", back, " vs ", src); ok = false

	# --- GetRotationTo: q1.GetRotationTo(q2) * q1 == q2 ---
	var q1: Quaternion = Q.AngleAxis(0.3, Vector3(0, 0, 1))
	var q2: Quaternion = Q.AngleAxis(-0.5, Vector3(0, 1, 0)) * q1
	var rot_to: Quaternion = Q.GetRotationTo(q1, q2)
	var applied: Quaternion = rot_to * q1
	if not (applied.is_equal_approx(q2) or applied.is_equal_approx(-q2)):
		print("CHECK FAIL: GetRotationTo не доводит q1 до q2"); ok = false

	# --- GetRotationAngle: угол против identity == угол конструирования ---
	var q3: Quaternion = Q.AngleAxis(0.42, Vector3(1, 0, 0))
	var got_angle: float = Q.GetRotationAngle(q3, Quaternion.IDENTITY)
	if not feq(absf(got_angle), 0.42, 1.0e-4):
		print("CHECK FAIL: GetRotationAngle = ", got_angle); ok = false

	# --- GetRotationMultipliedBy: удвоенный кватернион == AngleAxis с удвоенным углом ---
	var half: Quaternion = Q.AngleAxis(0.2, Vector3(0, 0, 1))
	var doubled: Quaternion = Q.GetRotationMultipliedBy(half, 2.0)
	var expected_d: Quaternion = Q.AngleAxis(0.4, Vector3(0, 0, 1))
	if not (doubled.is_equal_approx(expected_d) or doubled.is_equal_approx(-expected_d)):
		print("CHECK FAIL: GetRotationMultipliedBy x2"); ok = false

	# --- LineClosestToPoint (line.cpp:60-71): 2D-проекция, u без клампа ---
	# точка над серединой отрезка (0,0)-(2,0) → u = 0.5; за концом → u > 1 (кламп у ВЫЗЫВАЮЩЕГО)
	var u: float = BM.LineClosestToPoint(Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(1, 5, 0))
	if not feq(u, 0.5):
		print("CHECK FAIL: LineClosestToPoint середина: ", u); ok = false
	u = BM.LineClosestToPoint(Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0))
	if not feq(u, 1.5):
		print("CHECK FAIL: LineClosestToPoint за концом (без клампа): ", u); ok = false
	# вырожденный отрезок → 0 (line.cpp:61-63)
	u = BM.LineClosestToPoint(Vector3(1, 1, 0), Vector3(1, 1, 0), Vector3(5, 5, 0))
	if not feq(u, 0.0):
		print("CHECK FAIL: LineClosestToPoint вырожденный: ", u); ok = false

	# --- GpfRng: детерминизм по сиду, диапазон, чувствительность к сиду ---
	var r1 = RNG.new(); r1.Reseed(42)
	var r2 = RNG.new(); r2.Reseed(42)
	var all_in_range := true
	var same := true
	var prev_vals: Array = []
	for i in 100:
		var a: float = r1.Uniform(-1.0, 1.0)
		var b: float = r2.Uniform(-1.0, 1.0)
		if a != b: same = false
		if a < -1.0 or a > 1.0: all_in_range = false
		prev_vals.append(a)
	if not same: print("CHECK FAIL: GpfRng не детерминирован по сиду"); ok = false
	if not all_in_range: print("CHECK FAIL: GpfRng вышел из [min,max]"); ok = false
	var r3 = RNG.new(); r3.Reseed(43)
	var diff_count := 0
	for i in 100:
		if r3.Uniform(-1.0, 1.0) != prev_vals[i]: diff_count += 1
	if diff_count < 90:
		print("CHECK FAIL: GpfRng слабо зависит от сида: ", diff_count); ok = false

	# --- GpfPitch: сверка с gamedefines.hpp (эти числа — данные оригинала, не тюнинг) ---
	if not feq(P.PitchHalfW, 55.0) or not feq(P.PitchHalfH, 36.0) or not feq(P.LineHalfW, 0.06):
		print("CHECK FAIL: размеры поля"); ok = false
	if not feq(P.GoalDepth, 2.55) or not feq(P.GoalHeight, 2.5) or not feq(P.GoalHalfWidth, 3.7):
		print("CHECK FAIL: размеры ворот"); ok = false
	if not feq(P.DefaultPlayerHeight, 1.92) or P.DefaultTouchOffsetMs != 80:
		print("CHECK FAIL: рост/тач-офсет"); ok = false
	if P.BallPredictionSizeMs != 3000 or P.BallHistorySizeMs != 4000:
		print("CHECK FAIL: размеры предсказания/истории"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: прогнать — падает** (нет новых методов/классов). Не забыть `--import` для `.uid`.

```powershell
dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_gpf_ball_foundation.gd"
```

- [ ] **Шаг 3: реализация**

Кватернионные методы: **сначала открыть `src/base/math/quaternion.cpp` оригинала** (grep
`GetRotationTo`, `GetRotationAngle`, `GetRotationMultipliedBy`, `SetAngles`), перенести дословно с
комментарием-ссылкой на найденные строки. НЕ выводить формулы из головы и НЕ брать Godot-аналоги
(`Quaternion.AngleTo` и т.п.) — поведение должно совпадать с оригиналом, включая нормализации и
выбор знака. Ожидаемые сигнатуры в `QuatUtil`:

```csharp
        // quaternion.cpp:NN-NN (проставить реальные строки при переносе)
        public static Quaternion SetAngles(float x, float y, float z) { /* порт */ }
        public static Quaternion GetRotationTo(Quaternion from, Quaternion to) { /* порт */ }
        public static float GetRotationAngle(Quaternion q, Quaternion reference) { /* порт */ }
        public static Quaternion GetRotationMultipliedBy(Quaternion q, float factor) { /* порт */ }
```

`BluntMath.LineClosestToPoint` (line.cpp:60-71 — тут формула короткая, переносится как есть):

```csharp
        // line.cpp:60-71 — u проекции точки на отрезок v0→v1 (2D: только X/Y), БЕЗ клампа.
        public static float LineClosestToPoint(Vector3 v0, Vector3 v1, Vector3 point)
        {
            if (v0 == v1) return 0.0f;
            float lineDistance = (v1 - v0).Length();
            if (lineDistance < 0.000001f) return 0.0f;
            float u = ((point.X - v0.X) * (v1.X - v0.X) +
                       (point.Y - v0.Y) * (v1.Y - v0.Y)) /
                      (lineDistance * lineDistance);
            return u;
        }
```

`src/gpf/GpfRng.cs`:

```csharp
using Godot;

namespace Gpf
{
    // Детерминированный PRNG ядра порта — замена unseeded boost-random() оригинала
    // (мультиплеер-дисциплина №3 роадмапа). Распределение равномерное [min,max],
    // последовательность с эталон-exe НЕ совпадает (у оригинала сид от времени, main.cpp:285-288).
    // xorshift64* (Marsaglia); зафиксировано — менять алгоритм нельзя без пересчёта тестов.
    public partial class GpfRng : RefCounted
    {
        private ulong _state = 0x9E3779B97F4A7C15UL;

        public GpfRng() { }
        public GpfRng(ulong seed) => Reseed(seed);

        public void Reseed(ulong seed) => _state = seed == 0 ? 0x9E3779B97F4A7C15UL : seed;

        private ulong NextRaw()
        {
            _state ^= _state >> 12;
            _state ^= _state << 25;
            _state ^= _state >> 27;
            return _state * 0x2545F4914F6CDD1DUL;
        }

        // random(min, max) оригинала (равномерное включительно-приближённое)
        public float Uniform(float min, float max)
        {
            float t = (NextRaw() >> 11) * (1.0f / 9007199254740992.0f); // 53 бита → [0,1)
            return min + (max - min) * t;
        }
    }
}
```

`src/gpf/GpfPitch.cs`:

```csharp
namespace Gpf
{
    // Константы поля/игры оригинала — данные, не тюнинг (gamedefines.hpp).
    // Интеграция с нашим FIFA-полем — не фаза 4; лаба живёт в их размерах.
    public static class GpfPitch
    {
        public const float PitchHalfW = 55f;            // gamedefines.hpp:271
        public const float PitchHalfH = 36f;            // :272
        public const float LineHalfW = 0.06f;           // :275
        public const float GoalDepth = 2.55f;           // :277
        public const float GoalHeight = 2.5f;           // :278
        public const float GoalHalfWidth = 3.7f;        // :279
        public const int   BallPredictionSizeMs = 3000; // :56
        public const int   BallHistorySizeMs = 4000;    // :57
        public const float BallDistanceOptimizeThreshold = 10f; // :59
        public const int   DefaultTouchOffsetMs = 80;   // :64
        public const float DefaultPlayerHeight = 1.92f; // :66
    }
}
```

- [ ] **Шаг 4: прогнать — PASS**; `dotnet build` чист; все 17 существующих `check_gpf_*` зелёные.

- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/QuatUtil.cs src/gpf/BluntMath.cs src/gpf/GpfRng.cs src/gpf/GpfPitch.cs tests/check_gpf_ball_foundation.gd tests/check_gpf_ball_foundation.gd.uid
git commit -m "feat(gpf): кватернионные примитивы, LineClosestToPoint, GpfRng, GpfPitch (фаза 4, задача 1)"
```

---

### Задача 2: Gpf.Ball — физика мяча целиком (Fable 5, критичная математика)

**Files:**
- Create: `src/gpf/Ball.cs`
- Test: `tests/check_gpf_ball.gd`

**Interfaces:**
- Consumes: `QuatUtil` (`AngleAxis`, `Slerp`, `GetAngles`/`GetAnglesVec`, `SetAngles`,
  `GetRotationTo`, `GetRotationAngle`, `GetRotationMultipliedBy` — задача 1), `BluntMath`
  (`NormalizedClamp`, `GetNormalized`, `Get2D`), `GpfPitch`.
- Produces (для задач 4-8):
  - `public partial class Gpf.Ball : RefCounted`:
    - `Vector3 Predict(int predictTimeMs)` — порт ball.hpp:51-57 (**bug-for-bug**: отрицательный
      аргумент через unsigned-каст оригинала даёт ПОСЛЕДНЮЮ точку, не первую — воспроизвести
      `(uint)`-кастом с комментарием);
    - `Vector3 GetMovement()` (м/с), `Vector3 GetPositionBuffer()`;
    - `void Touch(Vector3 target)` (ball.cpp:91-103 минус мозаика матча/командной статистики —
      комментарий-шов на месте), `void SetPosition(Vector3 target)` (:105-112),
      `void SetMomentum(Vector3 target)` (:114-117),
      `void SetRotation(float x, float y, float z, float bias)` (:119-131),
      `void SetRotationVec(Vector3 rot, float bias)` (:133-135; отдельное имя — GDScript-мост не
      различает перегрузки);
    - `void Process()` (:562-585 минус debug-клавиша и Put-буферы),
      `void ResetSituation(Vector3 focusPos)` (:602-615),
      `Vector3 GetAveragePosition(int durationMs)` (:539-551);
    - `bool WoodworkEnabled` (публичное поле, дефолт `true`) — лаба без ворот может выключить.

**Решения по вырезкам (все — с комментарием на месте):** сетка (:333-408) вырезана целиком
(NetSim-решение роадмапа, `ballTouchesNet` не переносится); звук (:46-68, :325-327, :553-560),
сцена/geometry (:33-44), Put/temporal smoothing (:587-600), debug-клавиша BACKSPACE (:564-569),
`match->UpdateLatestMentalImageBallPredictions()`/командная статистика (:99-102) — вырезаны.
`autoDegrade_timeStep` (:160, :518-522) — мёртвая ветка (`false`), портируется дословно как
`static readonly bool`.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 4, задача 2: Gpf.Ball == Ball::CalculatePrediction (ball.cpp:137-537).
# Ключевой приём: тест сам перевычисляет ОДИН шаг интеграции (10 мс) по формулам C++
# (порядок: гравитация → drag → отскок → трение → [штанги] → вращение → магнус → интеграция)
# и сверяет с Predict(10). Это пиннит порядок применения констант целиком.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

# один шаг интеграции C++ для мяча БЕЗ вращения (rotation identity) вне штанг:
# возвращает [новый momentum, новая позиция]
func step_no_rotation(pos: Vector3, mom: Vector3) -> Array:
	var dt := 0.01
	# гравитация (ball.cpp:175)
	mom.z += -9.81 * dt
	# сопротивление воздуха (:180-183)
	var velo := mom.length()
	var dragged := velo - 0.015 * velo * velo * dt
	if velo > 0.0001:
		mom = mom.normalized() * dragged
	# влияние травы (:186-191)
	var ball_bottom := pos.z - 0.11
	var grass_bias: float = clampf(1.0 - (ball_bottom / 0.025), 0.0, 1.0)
	grass_bias = pow(grass_bias, 0.7)
	# отскок (:197-205)
	var friction_factor := 0.0
	if pos.z < 0.11:
		if mom.z < 0.0:
			friction_factor = clampf((-mom.z - 0.5) / 12.0, 0.0, 1.0)
			mom.z = -mom.z * 0.62
			mom.z = maxf(mom.z - 0.06, 0.0)
		pos.z = 0.11
	# трение газона (:210-227)
	if pos.z < 0.11 + 0.025:
		var adapted_friction := 0.04 * grass_bias
		var xy := Vector3(mom.x, mom.y, 0)
		var v := xy.length()
		var new_velo := v - adapted_friction * v * v * dt
		new_velo = clampf(new_velo - 1.6 * grass_bias * dt, 0.0, 100000.0)
		if v > 0.0001:
			xy = xy.normalized() * new_velo
		mom.x = xy.x
		mom.y = xy.y
	# вращение (:413-481): при identity-вращении ballRotationMomentum = 0,
	# rotBias = 0.01*grass_bias (+0.5*friction_factor), кламп [0,1]
	if pos.z < 0.11 + 0.025:
		var rot_bias: float = 0.01 * grass_bias
		if friction_factor > 0.0:
			rot_bias += 0.5 * friction_factor
		rot_bias = clampf(rot_bias, 0.0, 1.0)
		mom.x = mom.x * (1.0 - rot_bias)
		mom.y = mom.y * (1.0 - rot_bias)
	# магнус при identity-вращении = 0 (:486-501)
	# интеграция (:506)
	pos += mom * dt
	return [mom, pos]

func _initialize() -> void:
	var ok := true
	var B = load("res://src/gpf/Ball.cs")
	if B == null:
		print("CHECK FAIL: Ball.cs не найден — сначала dotnet build")
		quit(1)
		return

	# ---------- 1. ResetSituation: все предсказания в точке покоя ----------
	var ball = B.new()
	ball.ResetSituation(Vector3(0, 0, 0))
	if not vec_eq(ball.Predict(0), Vector3(0, 0, 0.11)):
		print("CHECK FAIL: ResetSituation Predict(0) = ", ball.Predict(0)); ok = false
	if not vec_eq(ball.Predict(2990), Vector3(0, 0, 0.11)):
		print("CHECK FAIL: ResetSituation Predict(2990)"); ok = false

	# ---------- 2. Один шаг качения == перевычисление формул C++ ----------
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(0, 0, 0.11))
	ball.SetMomentum(Vector3(5, 0, 0))
	var expected: Array = step_no_rotation(Vector3(0, 0, 0.11), Vector3(5, 0, 0))
	var exp_pos: Vector3 = expected[1]
	if not vec_eq(ball.Predict(10), exp_pos, 1.0e-3):
		print("CHECK FAIL: качение, шаг 1: ", ball.Predict(10), " != ", exp_pos); ok = false

	# ---------- 3. Свободное падение: время до земли и отскок ----------
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(0, 0, 2.0))
	ball.SetMomentum(Vector3(0, 0, 0))
	# перевычисляем падение по шагам до первого контакта
	var sim_pos := Vector3(0, 0, 2.0)
	var sim_mom := Vector3.ZERO
	var steps := 0
	while sim_pos.z > 0.11 and steps < 300:
		var r: Array = step_no_rotation(sim_pos, sim_mom)
		sim_mom = r[0]
		sim_pos = r[1]
		steps += 1
	var t_ms := steps * 10
	# в кадре контакта предсказание тоже должно быть на земле (±1 кадр на накопление float)
	var land_a: Vector3 = ball.Predict(t_ms - 10)
	var land_b: Vector3 = ball.Predict(t_ms + 10)
	if not (land_a.z <= 0.115 or land_b.z <= 0.115):
		print("CHECK FAIL: падение — контакт не в ", t_ms, " мс: ",
			land_a.z, " / ", land_b.z); ok = false
	# после контакта мяч поднимается (отскок 0.62 жив)
	var bounced := false
	for i in range(t_ms + 10, t_ms + 400, 10):
		if ball.Predict(i).z > 0.2:
			bounced = true
			break
	if not bounced:
		print("CHECK FAIL: отскока нет"); ok = false
	# и затухает: второй пик ниже первого источника
	var peak := 0.0
	for i in range(t_ms, 3000, 10):
		peak = maxf(peak, ball.Predict(i).z)
	if peak > 1.6:
		print("CHECK FAIL: отскок не затух: пик ", peak); ok = false

	# ---------- 4. Первый шаг == новое состояние (:527-531) ----------
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(0, 0, 0.11))
	ball.SetMomentum(Vector3(5, 0, 0))
	var pred10: Vector3 = ball.Predict(10)
	ball.Process()
	if not vec_eq(ball.GetPositionBuffer(), pred10, 1.0e-4):
		print("CHECK FAIL: Process не взял Predict(10): ",
			ball.GetPositionBuffer(), " != ", pred10); ok = false
	var exp_mom: Vector3 = expected[0]
	if not vec_eq(ball.GetMovement(), exp_mom, 1.0e-3):
		print("CHECK FAIL: momentum после Process: ", ball.GetMovement(), " != ", exp_mom); ok = false

	# ---------- 5. Магнус: сильное вращение уводит мяч вбок ----------
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(0, 0, 1.0))
	ball.SetMomentum(Vector3(0, -20, 0))
	var straight: Vector3 = ball.Predict(800)
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(0, 0, 1.0))
	ball.SetRotationVec(Vector3(0, 0, 12.0), 1.0)  # z-спин
	ball.SetMomentum(Vector3(0, -20, 0))
	var curved: Vector3 = ball.Predict(800)
	if absf(curved.x - straight.x) < 0.05:
		print("CHECK FAIL: магнус не увёл мяч: dx = ", absf(curved.x - straight.x)); ok = false

	# ---------- 6. Штанга отражает (:247-292) ----------
	# мяч летит вдоль y на штангу (PitchHalfW, GoalHalfWidth) на малой высоте
	ball = B.new()
	ball.ResetSituation(Vector3.ZERO)
	ball.SetPosition(Vector3(54.0, 3.7, 1.0))
	ball.SetMomentum(Vector3(10, 0, 0))
	var deflected := false
	for i in range(0, 1500, 10):
		var p: Vector3 = ball.Predict(i)
		# оригинал выталкивает мяч из капсулы штанги: внутри радиуса точек быть не должно
		var post_dist: float = (Vector2(p.x, p.y) - Vector2(55.0, 3.7)).length()
		if p.z < 2.5 and post_dist < 0.11 + 0.07 - 0.01:
			print("CHECK FAIL: мяч внутри штанги в ", i, " мс"); ok = false
			break
		if p.x < 53.5 and i > 200:
			deflected = true  # отлетел назад
			break
	if not deflected:
		print("CHECK FAIL: штанга не отразила (мяч не вернулся)"); ok = false

	# ---------- 7. Детерминизм ----------
	var b1 = B.new(); var b2 = B.new()
	for b in [b1, b2]:
		b.ResetSituation(Vector3.ZERO)
		b.SetPosition(Vector3(1, 2, 0.5))
		b.SetRotationVec(Vector3(3, -2, 5), 1.0)
		b.SetMomentum(Vector3(-7, 4, 6))
	for i in range(0, 3000, 10):
		if b1.Predict(i) != b2.Predict(i):
			print("CHECK FAIL: недетерминизм в ", i, " мс"); ok = false
			break

	# ---------- 8. Отрицательный Predict — bug-for-bug последняя точка (ball.hpp:52-55) ----------
	if ball.Predict(-5) != ball.Predict(2990):
		print("CHECK FAIL: Predict(<0) должен дать последнюю точку (unsigned-каст оригинала)"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: прогнать — падает** (нет `Ball.cs`). `--import` для `.uid`.

- [ ] **Шаг 3: реализация — порт ball.cpp целиком**

Скелет класса (интеграционное ядро переносить строго по строкам; ниже — обязательная структура и
самые рискованные места, остальное — дословная транскрипция :137-537):

```csharp
using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // Порт Ball (ball.cpp/ball.hpp) минус: сетка ворот (:333-408, решение роадмапа — наш NetSim),
    // звук, сцена, Put/temporal smoothing, привязки к Match. Радиус мяча 0.11 — хардкод оригинала.
    public partial class Ball : RefCounted
    {
        // ball.cpp:23-29 — калиброванные константы, НЕ менять
        private const float Bounce = 0.62f;
        private const float LinearBounce = 0.06f;
        private const float Drag = 0.015f;       // previously 0.025f (комментарий оригинала)
        private const float Friction = 0.04f;
        private const float LinearFriction = 1.6f;
        private const float Gravity = -9.81f;
        private const float GrassHeight = 0.025f;

        public bool WoodworkEnabled = true; // лаба без ворот может выключить

        private Vector3 _momentum;
        private Quaternion _rotationMs = Quaternion.Identity;
        private readonly Vector3[] _predictions = new Vector3[GpfPitch.BallPredictionSizeMs / 10];
        private Quaternion _orientPrediction = Quaternion.Identity;
        private readonly List<Vector3> _ballPosHistory = new();
        private Vector3 _previousMomentum, _previousPosition;
        private Vector3 _positionBuffer;
        private Quaternion _orientationBuffer = Quaternion.Identity;

        // ball.hpp:51-57. Bug-for-bug: отрицательный predictTimeMs проходит unsigned-каст
        // оригинала и даёт ПОСЛЕДНЮЮ точку кэша, не первую.
        public Vector3 Predict(int predictTimeMs)
        {
            uint index = (uint)predictTimeMs;
            if (index >= GpfPitch.BallPredictionSizeMs) index = GpfPitch.BallPredictionSizeMs - 10;
            index /= 10;
            return _predictions[index];
        }

        public Vector3 GetMovement() => _momentum;             // ball.cpp:86-89
        public Vector3 GetPositionBuffer() => _positionBuffer;

        public void Touch(Vector3 target)                       // ball.cpp:91-103
        {
            if (_positionBuffer.Z < 0.11f) _positionBuffer.Z = 0.11f;
            SetMomentum(target);
            CalculatePrediction();
            // шов: match->UpdateLatestMentalImageBallPredictions()/статистика — слой матча/ИИ
        }
        // SetPosition (:105-112), SetMomentum (:114-117), SetRotation (:119-131),
        // SetRotationVec (:133-135), Process (:562-585 минус debug/Put),
        // ResetSituation (:602-615), GetAveragePosition (:539-551) — дословно.

        // Ядро: CalculatePrediction (:137-537). Возвращаемые newMomentum/newRotation
        // применяются в Process. Порядок секций внутри шага — СВЯЩЕННЫЙ:
        // гравитация (:175) → drag (:180-183) → grassBias (:186-191) → отскок (:197-205)
        // → трение газона (:210-227) → штанги+перекладина (только firstTime, :240-328)
        // → [сетка ВЫРЕЗАНА, :333-408] → вращение от качения + обратное влияние (:413-481)
        // → магнус (:486-501) → интеграция позиции/ориентации (:506-514)
        // → кэш каждые 10 мс (:516-525) → снапшот нового состояния на 10 мс (:527-531).
    }
}
```

Рисковые места (сверять на ревью в первую очередь):
- **:167 — цикл `predictTime_ms` начинается с 10** (`int(timeStep*1000)`), `predictions[0]` заполнен
  ДО цикла (:150). Кэш пишется при `predictTime_ms % 10 == 0` — при шаге 10 это каждый виток (:524).
- **:180-183 — drag применяется к ПОЛНОМУ 3D-вектору** (не только XY): `GetNormalized(0) *
  momentumVeloDragged`. При нулевой скорости `GetNormalized(0)` даёт 0-вектор — наш
  `BluntMath.GetNormalized(v, Vector3.Zero)`.
- **:199 — `frictionFactor` считается ДО перезаписи `momentumPredict.coords[2]`** и только в кадре
  удара о землю (один раз на отскок): `NormalizedClamp(-vz - 0.5, 0, 12)`.
- **:201 — линейный отскок**: `max(vz*0.62 - 0.06, 0)` — вычитание ПОСЛЕ множителя.
- **:210 — порог трения `z < 0.11 + grassHeight`**, а внутри отскока `z < 0.11` — разные пороги.
- **:221 — линейное трение клампится снизу нулём** (`clamp(..., 0, 100000)`) — мяч не едет назад.
- **:236 — `netAbsorbInv = pow(0.95, timeStep*100)` считается, но с вырезанной сеткой не
  используется** — НЕ переносить (мёртвый код вырезанной секции), отметить комментарием.
- **:240 — штанги проверяются ТОЛЬКО на первом шаге** (`firstTime`) — на предсказание дальних
  отскоков от штанги оригинал забил; переносится как есть.
- **:291 — формула отражения от штанги**: `(momentum2D.GetNormalized(normal) + normal*1.1).
  GetNormalized() * |momentum2D| * 0.8 + (0,0,1)*vz` — постабсорб 0.8 (`postAbsorbInv`).
- **:298 — перекладина в плоскости XZ**: `nextPos * Vector3(1,0,1)`, сравнение с
  `(PitchHalfW, 0, GoalHeight)`, юниты Y сохраняются.
- **:434-448 — кап скорости изменения вращения**: `GetRotationTo → GetRotationAngle(identity) *
  1000 → max pi*grassBias (+4pi при ударе) → GetRotationMultipliedBy(factor)`. Всё через QuatUtil.
- **:457-463 — обратное влияние вращения**: `GetAngles(x,y,z); x = -x;` затем
  `ballRotationMomentum = (y, x, 0) * radius * 1000` — оси нарочно перепутаны местами (качение).
- **:466-476 — rotBias = 0.01*grassBias (+0.5*frictionFactor), кламп [0,1]**, микс покомпонентно
  только X/Y.
- **:492-495 — магнус**: `swerveAmount = NormalizedClamp(|v|,0,70)`;
  `pow(sin(swerveAmount*pi*0.94), 2.6)`; `swerve = (normalize(v)*swerveAmount*30) × (-rotVec)`;
  `rotVec = GetAngles(rotationPredict)*10` (:488-489).
- **:508-514 — интеграция ориентации**: `rotationVector = GetAngles(rotation_ms) * (timeStep/0.001)`
  → `SetAngles` → умножение СЛЕВА на `nextOrientation`.
- **Process (:571-576):** `momentum = результат.momentum; rotation_ms = результат.rotation;
  positionBuffer = Predict(10); orientationBuffer = orientPrediction;` история позиций с капом
  `BallHistorySizeMs` записей×10мс (:578-579).

- [ ] **Шаг 4: прогнать — PASS**; `dotnet build` чист; 18 тестов (17 + задача 1) зелёные; обе
  стандартные headless-валидации без новых категорий.

- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/Ball.cs tests/check_gpf_ball.gd tests/check_gpf_ball.gd.uid
git commit -m "feat(gpf): Gpf.Ball — порт физики мяча ball.cpp минус сетка (фаза 4, задача 2)"
```

---

### Задача 3: PlayerCommand + SelectAnim наследника (crude query, сорт-цепочки, NeedTouch) (Opus 5)

**Files:**
- Create: `src/gpf/PlayerCommand.cs`
- Create: `src/gpf/Humanoid.cs` (**`public partial class HumanoidBase`** — файл наследника, см.
  решение п.4 скоупа; шапка файла объясняет партиальность)
- Modify: `src/gpf/AnimSelector.cs` (полные сигнатуры `KeepBest*`, недостающие компараторы)
- Modify: `src/gpf/HumanoidBase.cs` (движение-ветка переезжает на цепочку наследника)
- Test: `tests/check_gpf_touch_select.gd`

**Interfaces:**
- Consumes: `AnimCollection.CrudeSelection`/`CrudeSelectionQuery` (фаза 2), `AnimSelector.StableSort`,
  `Gpf.Ball` (задача 2), `SpatialState` (фаза 3).
- Produces (для задач 4-8):
  - `Gpf.PlayerCommand` (класс) + `Gpf.TouchInfo` — порт gamedefines.hpp:175-229/:145-167, все поля
    и дефолты конструктора дословно (`DesiredFunctionType=Movement`, `DesiredVelocityFloat=0`,
    `StrictMovement=Dynamic`, `TripType=1` и т.д.). `e_StrictMovement` → `int`-константы
    (`StrictFalse=0/StrictTrue=1/StrictDynamic=2`).
  - `AnimSelector`: `_KeepBestDirectionAnims(List<int> dataSet, ..., bool strict, float allowedAngle,
    int allowedVelocitySteps, int forcedQuadrantID)` — расширение до ПОЛНОЙ сигнатуры
    `humanoidbase.cpp:1103-1172` (дефолты `strict=true, allowedAngle=0, allowedVelocitySteps=0,
    forcedQuadrantID=-1`); `_KeepBestBodyDirectionAnims(..., bool strict, float allowedAngle)`
    (`:1174-…`); компараторы `CompareNumericVariable` (priority/idlelevel),
    `CompareBaseanimSimilarity`, `CompareCatchOrDeflect`, `CompareTripDirectionSimilarity` — все из
    humanoidbase.cpp (grep `bool HumanoidBase::Compare`), через `StableSort`.
  - `HumanoidBase` (в файле `Humanoid.cs`):
    - `internal List<int> BuildCrudeDataSet(PlayerCommand command)` — порт головы `Humanoid::SelectAnim`
      :1242-1365: сборка `CrudeSelectionQuery` наследника (включая hax long pass→short pass :1256,
      таблицу линейности/строгости по типам :1263-1304, `bySide` :1306-1311, `byIncomingBallDirection`
      c предсказанием мяча :1318-1323, спец-стейты :1349-1354), вызов `CrudeSelection`, фолбэк
      idle-клипа для movement (:1359-1365);
    - `internal void SortDataSet(List<int> dataSet, PlayerCommand command)` — порт :1369-1637: ветки
      `KeepBest*` по типам (:1441-1551: movement strict-цепочка наследника; ballcontrol
      `allowedBaseAngle=0` strict-если-не-lastditch; trap `0.3π`/2 шага + отказ «too wrong» :1511-1538;
      interfere `0.3π`/1 шаг) + сорт-цепочка :1556-1637 (priority → idlelevel → foot →
      [не-ballcontrol: incomingBodyDirection] → incomingVelocity → [trip: tripDirection] →
      [не-movement: baseanim] → [deflect: catchOrDeflect]);
    - `internal bool NeedTouch(int animId, PlayerCommand command)` — порт :1822-1857 **bug-for-bug**:
      `if (FloatToEnumVelocity(anim->GetOutgoingVelocity() != e_Velocity_Idle))` (:1828) — скобочный
      баг оригинала: сравнение ВНУТРИ вызова; переносится как есть с комментарием;
    - `internal float GetHasteFactor(bool considerOpponentProximity)` — порт :1143-1157
      (`GetTeamPossessionAmount`-ветка мертва — считать команду недоступной, множитель-заглушка с
      комментарием-швом);
    - `public void SetBall(Ball ball)`, `public void SetRng(GpfRng rng)` — инжекция зависимостей;
    - лаб-контекст (см. решения п.8-10 скоупа): `public void SetLabContext(float closestOpponentDistance,
      float playerHeight)` — дефолты 1000f / 1.92f;
    - `desiredIdleLevel` (:1563-1567): `IsInPlay=true`, `IsInSetPiece=false` в лабе → уровень
      определяется только дистанцией мяча (>16 м → 1) — поля-геймстейты как параметры с дефолтами.
- **Движение-ветка `SelectNextMovementAnim` фазы 3 переезжает на цепочку наследника** (:1441-1455):
  `_KeepBestDirectionAnims(dataSet, command, true)` + `_KeepBestBodyDirectionAnims(dataSet, command,
  true)` вместо базовых дефолтов, сорт-цепочка — общая (`SortDataSet`). Это закрывает главный
  открытый вопрос фазы 3 (movement-отбор базы vs наследника). Ожидаемо меняет выбор клипа на части
  переходов — `check_gpf_walker.gd`/`check_gpf_selector.gd` прогнать и, если упали НА ОЖИДАНИЯХ
  ВЫБОРА (не на инвариантах), обновить ожидания с комментарием «фаза 4: отбор наследника».

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 4, задача 3: SelectAnim наследника — crude query + сорт-цепочки (humanoid.cpp:1159-1637)
# + NeedTouch (:1822-1857). Проверки — перевалидация фильтров на живой коллекции (как check_gpf_crude)
# и структурные инварианты сортировки; опорных литералов из плана нет.

func _initialize() -> void:
	var ok := true
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var B = load("res://src/gpf/Ball.cs")
	var V = load("res://src/gpf/Velo.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)
	var sel = load("res://src/gpf/AnimSelector.cs").new()
	sel.Setup(c)

	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -1.0, 0))
	h.SetBall(ball)

	# ---------- 1. BallControl-запрос: отбор непуст и все клипы — ballcontrol ----------
	var ds: Array = h.BuildCrudeDataSetBridge(2)  # 2 == e_FunctionType_BallControl (gamedefines.hpp:93-109)
	if ds.size() == 0:
		print("CHECK FAIL: ballcontrol crude-отбор пуст"); ok = false
	for id in ds:
		if c.GetAnim(id).GetAnimType() != "ballcontrol":
			print("CHECK FAIL: не-ballcontrol в отборе: ", c.GetAnim(id).GetName()); ok = false
			break

	# ---------- 2. Отсортированный отбор: голова стабильна и повторяема ----------
	var s1: Array = h.BuildSortedDataSetBridge(2)
	var s2: Array = h.BuildSortedDataSetBridge(2)
	if s1.size() != s2.size():
		print("CHECK FAIL: недетерминизм размера"); ok = false
	else:
		for i in s1.size():
			if s1[i] != s2[i]:
				print("CHECK FAIL: недетерминизм сортировки, позиция ", i); ok = false
				break

	# ---------- 3. Сорт-инвариант priority (первый ключ цепочки :1556-1561) ----------
	# после всех сортировок расстояние |priority - 0| первого клипа <= последнего
	if s1.size() >= 2:
		var first_prio: int = int(c.GetAnim(s1[0]).GetVariable("priority"))
		var last_prio: int = int(c.GetAnim(s1[s1.size() - 1]).GetVariable("priority"))
		if absi(first_prio) > absi(last_prio):
			print("CHECK FAIL: priority-сортировка нарушена: ", first_prio, " > ", last_prio); ok = false

	# ---------- 4. Pass-запрос (ShortPass): long pass hax и непустой отбор ----------
	var ds_pass: Array = h.BuildCrudeDataSetBridge(4)  # ShortPass
	var ds_long: Array = h.BuildCrudeDataSetBridge(5)  # LongPass — hax :1256 даёт тот же тип
	if ds_pass.size() == 0:
		print("CHECK FAIL: shortpass-отбор пуст"); ok = false
	if ds_long.size() != ds_pass.size():
		print("CHECK FAIL: longpass != shortpass (hax :1256): ",
			ds_long.size(), " vs ", ds_pass.size()); ok = false

	# ---------- 5. NeedTouch: стоячий мяч + idle-желание → false; быстрый мяч → true ----------
	# (:1824-1830: idle-клип, desiredVelocity < 1.8, |ballMovement| <= 2 — не трогаем каждый кадр)
	ball.SetPosition(Vector3(0, -0.5, 0.11))
	var idle_id: int = c.GetIdleMovementAnimID()
	if h.NeedTouchBridge(idle_id, 0.0):
		print("CHECK FAIL: NeedTouch true на стоячем мяче и idle-желании"); ok = false
	ball.SetMomentum(Vector3(0, -8, 0))
	if not h.NeedTouchBridge(idle_id, 0.0):
		print("CHECK FAIL: NeedTouch false на быстром мяче (:1830)"); ok = false

	# ---------- 6. Движение-ветка наследника жива: walker-инварианты не сломаны ----------
	# (подробная проверка — существующие check_gpf_walker/selector; здесь смоук)
	var h2 = HB.new()
	h2.Setup(c, sel)
	h2.ResetSituation(Vector3.ZERO, 0.0)
	h2.SetBall(ball)
	for i in 200:
		h2.Tick(Vector3(0, -1, 0), V.Walk, false)
	if h2.GetSpatialFloatVelocity() < 1.8:
		print("CHECK FAIL: движение сломано отбором наследника: v = ",
			h2.GetSpatialFloatVelocity()); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

Мостовые обёртки (`BuildCrudeDataSetBridge(int functionTypeId)`,
`BuildSortedDataSetBridge(int functionTypeId)`, `NeedTouchBridge(int animId, float desiredVelocity)`)
— публичные методы для тестов, собирают минимальный `PlayerCommand` с дефолтами и зовут internal-путь.
`Tick` может потребовать третий аргумент против фазы 3 — если сигнатура меняется, обновить
существующие вызовы в `WalkLabMain.cs`/тестах в этой же задаче.

- [ ] **Шаг 2: прогнать — падает.** `--import` для `.uid`.

- [ ] **Шаг 3: реализация.** Порядок работ:
  1. `PlayerCommand.cs` — все поля/дефолты gamedefines.hpp:175-229 дословно.
  2. `AnimSelector`: раскрыть полные сигнатуры `_KeepBest*` по humanoidbase.cpp:1103-1231 (найти и
     перенести недостающие ветки `allowedVelocitySteps`/`forcedQuadrantID`/нестрогий режим),
     добавить компараторы (grep `CompareNumericVariable|CompareBaseanimSimilarity|
     CompareCatchOrDeflect|CompareTripDirectionSimilarity` в humanoidbase.cpp). Все сорты —
     `StableSort`.
  3. `Humanoid.cs`: `BuildCrudeDataSet` (:1242-1365) + `SortDataSet` (:1369-1637) + `NeedTouch`
     (:1822-1857, скобочный баг :1828 как есть) + `GetHasteFactor` (:1143-1157). MentalImage-места
     (:1322, :1841) — `_ball.Predict(...)` с комментарием-швом.
  4. Переключить movement-ветку на цепочку наследника; прогнать walker/selector-тесты, поправить
     ожидания выбора при необходимости (только выбора, не инвариантов!).

- [ ] **Шаг 4: прогнать — PASS**; полный набор `check_gpf_*`; обе headless-валидации.

- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/PlayerCommand.cs src/gpf/Humanoid.cs src/gpf/AnimSelector.cs src/gpf/HumanoidBase.cs src/lab/WalkLabMain.cs tests/check_gpf_touch_select.gd tests/check_gpf_touch_select.gd.uid
git commit -m "feat(gpf): PlayerCommand + SelectAnim наследника — crude query и сорт-цепочки (фаза 4, задача 3)"
```

---

### Задача 4: GetBodyBallDistanceAdvantage + GetBestCheatableAnimID (Fable 5, сердце фазы)

**Files:**
- Modify: `src/gpf/Humanoid.cs`
- Test: `tests/check_gpf_cheatable.gd`

**Interfaces:**
- Consumes: задачи 1-3 (`Ball.Predict`, `GpfRng` — здесь НЕ нужен, `LineClosestToPoint`,
  crude/sorted dataSet), `PhysicsVector.Calculate` (фаза 3, internal), `PhysicsVector.
  CalculateMovementAtFrame`, `Animation.GetTouchCount/GetTouchFrame/GetTouchPosition/
  GetInterpolatedRotation/SampleRootPosition/GetVariable`, `AnimCollection.GetPositionCacheInternal`,
  `QuatUtil.GetAngles`, `BluntMath`, `Velo`, `GpfPitch`.
- Produces (для задач 5-8):
  - `internal static Vector3 GetFrontOfFootOffsetRel(float velocity, float bodyAngleRel, float height)`
    — порт humanoid_utils.cpp:103-115;
  - `internal float GetBodyBallDistanceAdvantage(Animation anim, int functionType,
    Vector3 animTouchMovement, Vector3 touchMovement, Vector3 incomingMovement,
    Vector3 outgoingMovement, float outgoingAngle, Vector3 bodyPos, Vector3 ffo,
    Vector3 animBallPos2D, Vector3 actualBallPos2D, Vector3 ballMovement2D, float radiusFactor,
    float radiusCheatDistance, float decayPow, bool debug)` — порт :1859-1997;
  - `internal int GetBestCheatableAnimID(List<int> sortedDataSet, bool useDesiredMovement,
    Vector3 desiredDirection, float desiredVelocityFloat, bool useDesiredBodyDirection,
    Vector3 desiredBodyDirectionRel, List<Vector3> positionsRet, ref int animTouchFrameRet,
    ref float radiusOffsetRet, ref Vector3 touchPosRet, ref Vector3 fullActionSmuggleRet,
    ref Vector3 actionSmuggleRet, ref float rotationSmuggleRet, float hasteFactor,
    int localInterruptAnim, bool preferPassAndShot)` — порт :1999-2323 (`hasteFactor` в теле
    оригинала НЕ используется — параметр переносится и не читается, комментарий);
  - `internal float GetLastTouchBias(int durationMs, long queryTimeMs)` — порт
    `PlayerBase::GetLastTouchBias` (grep в playerbase.cpp, перенести дословно) поверх полей
    `_lastTouchTimeMs` (устанавливается касаниями в задаче 7; до тех пор −бесконечность → биас 0);
  - `public void SetBallRetainerSelf(bool retains)` — лаб-суррогат `match->GetBallRetainer()`
    (в фазе 4 ретейнер либо «этот игрок», либо никто);
  - мост для тестов: `public Godot.Collections.Dictionary CheatableBridge(int functionTypeId,
    Vector3 desiredDirection, float desiredVelocityFloat)` — собирает команду, строит sorted dataSet
    (задача 3), зовёт `GetBestCheatableAnimID`, возвращает `{ "id": int, "touch_frame": int,
    "touch_pos": Vector3, "full_smuggle": Vector3, "action_smuggle": Vector3,
    "rotation_smuggle": float }`.

**Константы наследника (humanoid.cpp:40-65) — завести приватными констами в `Humanoid.cs` с
комментарием на КАЖДОЙ:** `cheatFactor=0.5` (:43), `useContinuousBallCheck=true` (:44),
`enableMovementSmuggle=true` (:45), `cheatDiscardDistance=0.02` (:46), `cheatDistanceBonus=0.02`
(:47), `cheatDiscardDistanceMultiplier=0.4` (:48), `maxSmuggleDiscardDistance=0.2` (:49),
`enableActionSmuggleDiscard=true` (:50), `forceFullActionSmuggleDiscard=false` (:51),
`discardForwardSmuggle=true` (:52), `discardSidewaysSmuggle=false` (:53),
`bodyRotationSmoothingFactor=1.0` (:54), `bodyRotationSmoothingMaxAngle=0.25π` (:55 — при
`animSmoothing=true`), ReQueue-константы :56-63 (задача 6), `allowPreTouchRotationSmuggle=false`
(:64), `enableControlledBallCollisions=true` (:65). Флаги — `static readonly bool` (не `const`,
урок фазы 3: CS0162 на мёртвых ветках).

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 4, задача 4: GetBestCheatableAnimID (humanoid.cpp:1999-2323) +
# GetBodyBallDistanceAdvantage (:1859-1997) + GetFrontOfFootOffsetRel (humanoid_utils.cpp:103-115).
# Ожидания — формулы C++, перевычисленные здесь, и точные тождества выходов.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return (a - b).length() < eps

func _initialize() -> void:
	var ok := true
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var B = load("res://src/gpf/Ball.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)
	var sel = load("res://src/gpf/AnimSelector.cs").new()
	sel.Setup(c)

	# --- GetFrontOfFootOffsetRel: перевычисление humanoid_utils.cpp:103-115 ---
	var velo := 5.0
	var body_angle := 0.2
	var height := 0.11
	var distance: float = 0.34 + velo * 80.0 * 0.001 * 1.0
	var ffo_exp: Vector3 = Vector3(0, -distance * 0.8, 0)
	var angled: Vector3 = Vector3(0, -distance * 0.2, 0).rotated(Vector3(0, 0, 1), body_angle)
	ffo_exp = (ffo_exp + angled) * (1.0 - clampf((height - 0.11) / 4.0, 0.0, 0.5))
	var ffo_got: Vector3 = HB.GetFrontOfFootOffsetRelBridge(velo, body_angle, height)
	if not vec_eq(ffo_got, ffo_exp):
		print("CHECK FAIL: GetFrontOfFootOffsetRel ", ffo_got, " != ", ffo_exp); ok = false
	# ниже idleDribbleSwitch угол тела игнорируется (:111)
	var ffo_idle: Vector3 = HB.GetFrontOfFootOffsetRelBridge(1.0, 0.5, 0.11)
	var d_idle: float = 0.34 + 1.0 * 0.08
	if not vec_eq(ffo_idle, Vector3(0, -d_idle * 0.8, 0) + Vector3(0, -d_idle * 0.2, 0)):
		print("CHECK FAIL: GetFrontOfFootOffsetRel idle-угол не занулён"); ok = false

	# --- сцена: игрок в нуле, мяч чуть впереди на земле ---
	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -0.6, 0))  # «их-вперёд» = -Y
	h.SetBall(ball)

	# ---------- 1. Мяч у ног → ballcontrol находится ----------
	var r: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)  # 2 == BallControl (gamedefines.hpp:96)
	if int(r["id"]) < 0:
		print("CHECK FAIL: мяч у ног, ballcontrol не найден"); ok = false
	else:
		var tf: int = int(r["touch_frame"])
		var anim = c.GetAnim(int(r["id"]))
		if tf < 0 or tf >= anim.GetFrameCount():
			print("CHECK FAIL: touch_frame вне клипа: ", tf); ok = false
		# точное тождество :2238 — touchPos == предсказание мяча на кадр касания
		var expected_tp: Vector3 = ball.Predict(tf * 10)
		if not vec_eq(Vector3(r["touch_pos"]), expected_tp, 1.0e-5):
			print("CHECK FAIL: touch_pos != Predict(tf*10): ",
				r["touch_pos"], " != ", expected_tp); ok = false
		# assert :2317 — у action-смаггла нет Z
		if not feq(Vector3(r["action_smuggle"]).z, 0.0, 1.0e-6):
			print("CHECK FAIL: action_smuggle.z != 0"); ok = false
		if not feq(Vector3(r["full_smuggle"]).z, 0.0, 1.0e-6):
			print("CHECK FAIL: full_smuggle.z != 0"); ok = false

	# ---------- 2. Высокий мяч → ground-ballcontrol отвергнут (гейт 0.22, :2149) ----------
	ball.SetPosition(Vector3(0, -0.6, 1.6))
	ball.SetMomentum(Vector3.ZERO)
	var r_high: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)
	if int(r_high["id"]) >= 0:
		var got = c.GetAnim(int(r_high["id"]))
		# если нашёлся — допустимо только касание на высоте (клип с тачем выше гейта после скалирования)
		var tp: Vector3 = got.GetTouchPosition(int(r_high["touch_frame"]))
		if tp.z < 0.8:
			print("CHECK FAIL: высокий мяч взят низким тачем: клип ", got.GetName(),
				" тач-высота ", tp.z); ok = false

	# ---------- 3. Мяч далеко → radius deny (:1970) ----------
	ball.SetPosition(Vector3(0, -5.0, 0.11))
	ball.SetMomentum(Vector3.ZERO)
	var r_far: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)
	if int(r_far["id"]) >= 0:
		print("CHECK FAIL: мяч в 5 м «дотянут»: ", c.GetAnim(int(r_far["id"])).GetName()); ok = false

	# ---------- 4. Ретейнер-сам: обход advantage (:2217), нулевой смаггл (:2280) ----------
	ball.SetPosition(Vector3(0, -0.6, 0.11))
	ball.SetMomentum(Vector3.ZERO)
	h.SetBallRetainerSelf(true)
	var r_ret: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)
	if int(r_ret["id"]) < 0:
		print("CHECK FAIL: ретейнер не нашёл клип"); ok = false
	elif Vector3(r_ret["action_smuggle"]).length() > 1.0e-6:
		print("CHECK FAIL: ретейнер: action_smuggle != 0"); ok = false
	# порядок тач-перебора (:2065-2073): первым пробуется средний тач первого клипа списка
	if int(r_ret["id"]) >= 0:
		var first_anim = c.GetAnim(int(r_ret["id"]))
		var n_touches: int = first_anim.GetTouchCount()
		var mid_frame: int = first_anim.GetTouchFrame(n_touches / 2)
		if int(r_ret["touch_frame"]) != mid_frame:
			print("CHECK FAIL: ретейнер: не средний тач (", r_ret["touch_frame"],
				" != ", mid_frame, ")"); ok = false
	h.SetBallRetainerSelf(false)

	# ---------- 5. Детерминизм ----------
	var ra: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)
	var rb: Dictionary = h.CheatableBridge(2, Vector3(0, -1, 0), 3.5)
	if int(ra["id"]) != int(rb["id"]) or ra["touch_frame"] != rb["touch_frame"] \
			or Vector3(ra["action_smuggle"]) != Vector3(rb["action_smuggle"]):
		print("CHECK FAIL: недетерминизм"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

`GetFrontOfFootOffsetRelBridge` — статический публичный мост (внутренний метод + обёртка).

- [ ] **Шаг 2: прогнать — падает.** `--import` для `.uid`.

- [ ] **Шаг 3: реализация.** Полный порт; ключевой код (сохранить ВСЕ комментарии-ссылки):

```csharp
        // humanoid_utils.cpp:103-115 — где нога «хочет» видеть мяч (отн. корня, anim space)
        internal static Vector3 GetFrontOfFootOffsetRel(float velocity, float bodyAngleRel, float height)
        {
            float fullDistanceFactor = 1.0f;
            float distance = 0.34f + velocity * GpfPitch.DefaultTouchOffsetMs * 0.001f * fullDistanceFactor;
            Vector3 ffo = new Vector3(0, -distance * 0.8f, 0);
            float bodyAngle = bodyAngleRel;
            if (velocity < Velo.IdleDribbleSwitch) bodyAngle = 0;                    // :111
            Vector3 angled = BluntMath.GetRotated2D(new Vector3(0, -distance * 0.2f, 0), bodyAngle);
            return (ffo + angled) * (1.0f - Mathf.Clamp((height - 0.11f) / 4.0f, 0.0f, 0.5f)); // :114
        }
```

`GetBodyBallDistanceAdvantage` (:1859-1997) — транскрипция один-в-один:

```csharp
        internal float GetBodyBallDistanceAdvantage(Animation anim, int functionType,
            Vector3 animTouchMovement, Vector3 touchMovement, Vector3 incomingMovement,
            Vector3 outgoingMovement, float outgoingAngle, Vector3 bodyPos, Vector3 ffo,
            Vector3 animBallPos2D, Vector3 actualBallPos2D, Vector3 ballMovement2D,
            float radiusFactor, float radiusCheatDistance, float decayPow, bool debug)
        {
            // :1867-1876 — скорости
            float touchVelocity = touchMovement.Length();
            float animTouchVelocity = animTouchMovement.Length();
            float highestTouchVelocity = Mathf.Max(animTouchVelocity, touchVelocity);
            float incomingVelocity = incomingMovement.Length();
            float outgoingVelocity = outgoingMovement.Length();
            float averageInOutVelocity = (incomingMovement + outgoingMovement).Length() * 0.5f;
            float highestInOutVelocity = Mathf.Max(incomingVelocity, outgoingVelocity);
            float highestVelocity = Mathf.Max(highestTouchVelocity, highestInOutVelocity); // не используется дальше — как в оригинале
            float velocityChange = outgoingVelocity - incomingVelocity;                     // :1878
            float velocityChangeMps = velocityChange / (anim.GetFrameCount() * 0.01f);      // :1879

            // :1882-1885 — бонусы близости/скорости
            float bodyAnimBallBonus = 1.0f - BluntMath.Curve(BluntMath.NormalizedClamp(
                ((bodyPos + BluntMath.GetNormalized(ffo, Vector3.Zero) * 0.1f) - animBallPos2D).Length(),
                0.0f, 0.7f), 0.7f);
            float bodyActualBallBonus = 1.0f - BluntMath.Curve(BluntMath.NormalizedClamp(
                ((bodyPos + BluntMath.GetNormalized(ffo, Vector3.Zero) * 0.1f) - actualBallPos2D).Length(),
                0.0f, 0.7f), 0.4f);
            float velocityBonus = 1.0f - BluntMath.NormalizedClamp(averageInOutVelocity, Velo.Idle, Velo.Sprint);
            float velocityChangeBonus = 1.0f - BluntMath.NormalizedClamp(velocityChangeMps / 20.0f, -1.0f, 1.0f);

            // :1888-1894 — радиус
            float radius = radiusFactor;
            radius *= 1.0f + 1.0f * bodyAnimBallBonus + 0.6f * bodyActualBallBonus +
                      0.8f * bodyAnimBallBonus * bodyActualBallBonus +
                      0.0f * velocityChangeBonus + 1.0f * velocityBonus;

            float effectiveRadiusCheatDistance = radiusCheatDistance;                      // :1901

            // :1903-1908 — исходящее направление
            Vector3 outgoingDirection;
            if (Velo.FloatToEnumVelocity(outgoingMovement.Length()) == Velo.IdVelIdle)
                outgoingDirection = BluntMath.GetRotated2D(new Vector3(0, -1, 0), outgoingAngle);
            else
                outgoingDirection = outgoingMovement.Normalized();

            // :1911-1921 — behindVector: зона смещается назад по ходу
            Vector3 behindVectorUnscaled = -(incomingMovement * 0.1f + touchMovement * 0.2f + outgoingMovement * 0.7f);
            Vector3 behindVector = BluntMath.GetNormalized(behindVectorUnscaled, Vector3.Zero) *
                Mathf.Pow(BluntMath.NormalizedClamp(behindVectorUnscaled.Length(), 0, Velo.Sprint), 0.5f);
            float dot = new Vector3(0, -1, 0).Dot(outgoingDirection);                      // :1919
            dot = 0.5f + Mathf.Clamp(dot * 0.5f + 0.5f, 0.0f, 1.0f) * 0.5f;
            behindVector *= dot;

            Vector3 animToActualBall = actualBallPos2D - animBallPos2D;                    // :1923

            bool deformArea = true;                                                        // :1925
            if (deformArea)
            {
                // :1927-1929
                Vector3 straightAngleVectorUnscaled = incomingMovement;
                Vector3 straightAngleVector = BluntMath.GetNormalized(straightAngleVectorUnscaled, outgoingDirection);
                float toStraightAngle = BluntMath.GetAngle2D(new Vector3(0, -1, 0), straightAngleVector);
                animToActualBall = BluntMath.GetRotated2D(animToActualBall, toStraightAngle); // :1932
                // :1935-1945 — эллипс: латеральный чит труднее на скорости
                float lateralRadiusFactor = 0.6f - 0.3f * Mathf.Pow(
                    BluntMath.NormalizedClamp(straightAngleVectorUnscaled.Length(), Velo.Idle, Velo.Sprint), 0.7f);
                animToActualBall.X /= lateralRadiusFactor;   // X — латеральная компонента
                radius *= Mathf.Pow(1.0f / lateralRadiusFactor, 0.5f); // сохранить площадь πr²
                animToActualBall = BluntMath.GetRotated2D(animToActualBall, -toStraightAngle); // :1957
            }

            // :1963-1970 — итоговая проверка
            Vector3 adaptedActualBallPos2D = animBallPos2D + animToActualBall;
            float radiusCheatBehindBias = 0.6f;                                            // :1965
            Vector3 behindCenter = animBallPos2D + behindVector *
                (radius + (effectiveRadiusCheatDistance * radiusCheatBehindBias)) * CheatFactor;
            float result = 1.0f;
            float allowedRadius = (radius + effectiveRadiusCheatDistance) * CheatFactor + CheatDistanceBonus;
            if (adaptedActualBallPos2D.DistanceTo(behindCenter) > allowedRadius) result = 0.0f;
            return result; // debug-пилоны :1972-1992 не переносятся
        }
```

`GetBestCheatableAnimID` (:1999-2323) — транскрипция; каркас с обязательными деталями:

```csharp
        internal int GetBestCheatableAnimID(List<int> sortedDataSet, /* ...сигнатура выше... */)
        {
            // :2002 — чужой ретейнер запрещает тач-клипы; в фазе 4 ретейнер бывает только «сам»
            // (лаб-суррогат SetBallRetainerSelf), ветка «чужой» придёт с матчем — комментарий-шов.

            Vector3 incomingMovement = BluntMath.GetRotated2D(_spatial.Movement, -_spatial.Angle); // :2004
            int bestAnimID = -1;
            Vector3 bestActionSmuggleVec2D = Vector3.Zero;
            // :2016 — functionType от ПЕРВОГО клипа списка (не от команды!) — bug-for-bug
            int functionType = AnimCollection.StringToFunctionType(
                _anims.GetAnim(sortedDataSet[0]).GetAnimType());
            float rotationSmuggleTmp = 0f;
            float predictedAngle = 0f;
            Vector3 adaptedOutgoingMovement = Vector3.Zero;
            bool found = false;
            int iterIdx = 0;
            while (iterIdx < sortedDataSet.Count && !found)                                 // :2025
            {
                Animation anim = _anims.GetAnim(sortedDataSet[iterIdx]);
                bool isBase = anim.GetVariable("baseanim") == "true";                       // :2028
                var origPositionCache = _anims.GetPositionCacheInternal(sortedDataSet[iterIdx]);
                // :2034 — траектория клипа под текущую физику
                _physicsVector.Calculate(anim, origPositionCache, useDesiredMovement,
                    desiredDirection * desiredVelocityFloat, useDesiredBodyDirection,
                    desiredBodyDirectionRel, positionsRet, out rotationSmuggleTmp);
                // :2037-2038
                predictedAngle = anim.GetOutgoingAngle() + rotationSmuggleTmp;
                predictedAngle = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi, predictedAngle);
                Vector3 outgoingMovement = BluntMath.GetRotated2D(
                    CalculateOutgoingMovement(positionsRet), -_spatial.Angle);               // :2050
                adaptedOutgoingMovement = outgoingMovement;
                int frameCount = anim.GetEffectiveFrameCount();                              // :2053
                int totalTouches = anim.GetTouchCount();                                     // :2057
                int defaultTouchFrame = BluntMath.AtoI(anim.GetVariable("touchframe"));      // :2061
                // :2065-2073 — порядок перебора: от среднего вниз до 0, затем средний+1 и вверх
                var touchIDs = new int[totalTouches];
                int count = 0;
                for (int i = totalTouches / 2; i > -1; i--) { touchIDs[count] = i; count++; }
                for (int i = totalTouches / 2 + 1; i < totalTouches; i++) { touchIDs[count] = i; count++; }

                int touchNum = 0;
                while (touchNum < totalTouches && !found)                                    // :2075
                {
                    int animTouchFrame = anim.GetTouchFrame(touchIDs[touchNum]);
                    Vector3 animBallPos = anim.GetTouchPosition(touchIDs[touchNum]);         // :2077
                    // :2083-2090 — мяч за пределами поля в кадр касания → пропустить
                    if (!_ballRetainerSelf)
                    {
                        Vector3 absBallPos = _ball.Predict(animTouchFrame * 10);
                        if (Mathf.Abs(absBallPos.X) > GpfPitch.PitchHalfW + GpfPitch.LineHalfW + 0.11f ||
                            Mathf.Abs(absBallPos.Y) > GpfPitch.PitchHalfH + GpfPitch.LineHalfW + 0.11f)
                        { touchNum++; continue; }
                    }
                    // :2095-2096 — движения в кадр касания (варпнутое и исходное)
                    Vector3 touchMovement = BluntMath.GetRotated2D(
                        PhysicsVector.CalculateMovementAtFrame(positionsRet, animTouchFrame, 1), -_spatial.Angle);
                    Vector3 animTouchMovement =
                        PhysicsVector.CalculateMovementAtFrame(origPositionCache, animTouchFrame, 1);
                    // :2098-2102 — предсказание мяча в anim space (MentalImage-шов: Predict напрямую)
                    Vector3 ballPos = _ball.Predict(animTouchFrame * 10);
                    Vector3 ballMovement = (_ball.Predict(animTouchFrame * 10 + 10) -
                                            _ball.Predict(animTouchFrame * 10)) * 100.0f;
                    ballPos = BluntMath.GetRotated2D(ballPos - _spatial.Position, -_spatial.Angle);
                    ballMovement = BluntMath.GetRotated2D(ballMovement, -_spatial.Angle);
                    // :2104-2110
                    Vector3 bodyPos = BluntMath.GetRotated2D(positionsRet[animTouchFrame], -_spatial.Angle);
                    bodyPos.Z = 0;
                    Quaternion animBodyRot = anim.GetInterpolatedRotation("player", animTouchFrame);
                    Vector3 animBodyPos = anim.SampleRootPosition(animTouchFrame, 0f);
                    QuatUtil.GetAngles(animBodyRot, out float rotX, out float rotY, out float rotZ);
                    // :2112-2118 — позиция мяча клипа → пространство траектории + рост игрока
                    float animBallHeight = animBallPos.Z;
                    if (AllowPreTouchRotationSmuggle)
                        animBallPos = BluntMath.GetRotated2D(animBallPos - animBodyPos,
                                rotationSmuggleTmp * ((float)animTouchFrame / frameCount)) +
                            BluntMath.GetRotated2D(positionsRet[animTouchFrame], -_spatial.Angle);
                    else
                        animBallPos = (animBallPos - animBodyPos) +
                            BluntMath.GetRotated2D(positionsRet[animTouchFrame], -_spatial.Angle);
                    animBallPos.Z = animBallHeight * (_playerHeight / GpfPitch.DefaultPlayerHeight);
                    // :2122-2126 — непрерывная проверка окна −6..+3 мс
                    if (UseContinuousBallCheck)
                    {
                        Vector3 v0 = ballPos - ballMovement * 0.006f;
                        Vector3 v1 = ballPos + ballMovement * 0.003f;
                        float u = Mathf.Clamp(BluntMath.LineClosestToPoint(v0, v1, animBallPos), 0.0f, 1.0f);
                        ballPos = v0 + (v1 - v0) * u;
                    }
                    Vector3 actionSmuggleVec3D = ballPos - animBallPos;                      // :2129
                    Vector3 actionSmuggleVec2D = BluntMath.Get2D(actionSmuggleVec3D);
                    // :2135-2147 — высотный гейт со скидками
                    float ballDistanceZ = Mathf.Abs(actionSmuggleVec3D.Z);
                    ballDistanceZ *= 1.0f - Mathf.Clamp((animBallPos.Z - 0.11f) * 0.3f, 0.0f, 0.2f);
                    ballDistanceZ *= 1.0f - Mathf.Clamp((ballPos.Z - 0.11f) * 0.4f, 0.0f, 0.3f);
                    if (ballPos.Z > 1.8f && ballPos.Z > animBallPos.Z + 0.12f) ballDistanceZ *= 2.0f;
                    if (ballPos.Z > 2.6f && ballPos.Z > animBallPos.Z + 0.08f) ballDistanceZ *= 20.0f;
                    if (functionType == AnimCollection.FtDeflect) ballDistanceZ *= 0.8f;
                    if (_ballRetainerSelf) ballDistanceZ = 0.0f;
                    if (ballPos.Z < 0.5f && isBase) ballDistanceZ = Mathf.Max(ballDistanceZ - 0.15f, 0.0f);

                    if (ballDistanceZ < 0.22f)                                               // :2149
                    {
                        // :2152-2153
                        float touchFrameAwkwardness = BluntMath.NormalizedClamp(
                            Mathf.Abs(defaultTouchFrame - animTouchFrame), 0.0f, 4.0f);
                        touchFrameAwkwardness = Mathf.Pow(touchFrameAwkwardness, 2.0f) * 0.5f;
                        // :2162-2168
                        float touchFrameFactor = animTouchFrame / 24.0f;
                        touchFrameFactor = Mathf.Pow(touchFrameFactor, 0.7f);
                        if (touchFrameFactor > 1.0f) touchFrameFactor = 1.0f + ((touchFrameFactor - 1.0f) * 0.5f);
                        // :2170-2188 — радиус по типу действия
                        float radiusCheatOffset = 0.0f;
                        float radiusFactor = 0.3f * (1.0f - touchFrameAwkwardness);
                        if (functionType == AnimCollection.FtDeflect)   { radiusFactor *= 1.8f; radiusCheatOffset += 0.4f; }
                        if (functionType == AnimCollection.FtSliding)   { radiusFactor *= 0.2f; radiusCheatOffset = 0.0f; }
                        if (functionType == AnimCollection.FtInterfere) { radiusFactor *= 1.4f; radiusCheatOffset += 0.2f; }
                        if (functionType == AnimCollection.FtShortPass) { radiusFactor *= 1.3f; radiusCheatOffset += 0.15f; }
                        if (functionType == AnimCollection.FtLongPass)  { radiusFactor *= 1.3f; radiusCheatOffset += 0.15f; }
                        if (functionType == AnimCollection.FtHighPass)  { radiusFactor *= 1.3f; radiusCheatOffset += 0.15f; }
                        if (functionType == AnimCollection.FtShot)      { radiusFactor *= 1.3f; radiusCheatOffset += 0.15f; }
                        if ((functionType == AnimCollection.FtTrap ||
                             functionType == AnimCollection.FtBallControl) && preferPassAndShot)
                            radiusFactor *= 0.3f;                                            // :2184-2186
                        radiusCheatOffset *= (1.0f - touchFrameAwkwardness);                 // :2188
                        // :2190-2197 — FFO
                        float touchVelo = touchMovement.Length();
                        Vector3 ffo = GetFrontOfFootOffsetRel(touchVelo, rotZ, ballPos.Z);
                        if (Velo.FloatToEnumVelocity(touchVelo) != Velo.IdVelIdle)
                            ffo = BluntMath.GetRotated2D(ffo, BluntMath.FixAngle(BluntMath.GetAngle2D(
                                BluntMath.GetNormalized(touchMovement, new Vector3(0, -1, 0)))));
                        // :2204-2209 — свежее касание жмёт радиус
                        float lastTouchBias = BluntMath.Curve(GetLastTouchBias(600,
                            _actualTimeMs + animTouchFrame * 10), 1.0f);
                        if (lastTouchBias > 0.0f)
                        {
                            float factor = 1.0f - lastTouchBias * 0.97f * (1.0f - _statBallControl * 0.1f);
                            radiusFactor *= factor;
                            radiusCheatOffset *= factor;
                        }
                        // :2214-2217
                        float touchFramedRadiusFactor = radiusFactor * touchFrameFactor;
                        float advantage = GetBodyBallDistanceAdvantage(anim, functionType,
                            animTouchMovement, touchMovement, incomingMovement, adaptedOutgoingMovement,
                            predictedAngle, bodyPos, ffo, BluntMath.Get2D(animBallPos),
                            BluntMath.Get2D(ballPos), BluntMath.Get2D(ballMovement),
                            touchFramedRadiusFactor, radiusCheatOffset, 1.0f, false);
                        if (advantage >= 1.0f || _ballRetainerSelf)                          // :2217
                        {
                            found = true;
                            bestAnimID = sortedDataSet[iterIdx];                             // :2223
                            bestActionSmuggleVec2D = actionSmuggleVec2D;
                            animTouchFrameRet = animTouchFrame;
                            radiusOffsetRet = 1000.0f; // :2227 — todo оригинала «is this still in use?», как есть
                        }
                    }
                    touchNum++;
                }
                iterIdx++;
            }

            if (found)                                                                       // :2236
            {
                touchPosRet = _ball.Predict(animTouchFrameRet * 10);                         // :2238
                fullActionSmuggleRet = BluntMath.GetRotated2D(bestActionSmuggleVec2D, _spatial.Angle);
                actionSmuggleRet = fullActionSmuggleRet;
                if (ForceFullActionSmuggleDiscard) { actionSmuggleRet = Vector3.Zero; }      // :2243
                else if (EnableActionSmuggleDiscard)                                         // :2247
                {
                    // :2250-2256
                    float smuggleDistance = actionSmuggleRet.Length();
                    float adaptedMult = CheatDiscardDistanceMultiplier;
                    if (functionType != AnimCollection.FtBallControl) adaptedMult *= 0.8f;
                    if (touchPosRet.Z > 0.5f) adaptedMult *= 0.7f;
                    if (touchPosRet.Z > 1.0f) adaptedMult *= 0.7f;
                    float cheatDiscardDistanceBonus = 0.0f;
                    if (functionType == AnimCollection.FtInterfere) cheatDiscardDistanceBonus += 0.1f;
                    // :2264-2267 — метод 1; std::min c maxSmuggleDiscardDistance ПОРТИРУЕТСЯ КАК ЕСТЬ:
                    // при |full| < 0.2 даёт отрицательную дистанцию (разворот смаггла) — подозрение на
                    // баг оригинала, НЕ чинить (см. Global Constraints)
                    smuggleDistance = Mathf.Clamp(
                        smuggleDistance - (CheatDiscardDistance + cheatDiscardDistanceBonus), 0.0f, 100.0f);
                    smuggleDistance *= 1.0f - adaptedMult;
                    smuggleDistance = Mathf.Min(smuggleDistance,
                        actionSmuggleRet.Length() - MaxSmuggleDiscardDistance);
                    if (_ballRetainerSelf) smuggleDistance = 0.0f;                           // :2280
                    actionSmuggleRet = BluntMath.GetNormalized(actionSmuggleRet, Vector3.Zero) * smuggleDistance;
                    // :2286-2311 — гашение передней компоненты
                    if (DiscardForwardSmuggle || DiscardSidewaysSmuggle)
                    {
                        float toStraightAngle = _spatial.Angle + predictedAngle;             // :2288
                        actionSmuggleRet = BluntMath.GetRotated2D(actionSmuggleRet, -toStraightAngle);
                        if (DiscardForwardSmuggle)
                        {
                            float shortenForwardDistance = 0.02f;                            // :2293
                            float allowForwardDistance = 0.25f *
                                (1.0f - Mathf.Pow(BluntMath.NormalizedClamp(
                                    adaptedOutgoingMovement.Length(), Velo.Idle, Velo.Sprint - 2.0f), 0.6f)) *
                                (animTouchFrameRet * 0.1f);                                  // :2294-2300
                            if (functionType != AnimCollection.FtBallControl &&
                                functionType != AnimCollection.FtTrap)
                                allowForwardDistance += 0.1f;                                // :2301
                            if (actionSmuggleRet.Y < 0.0f)
                                actionSmuggleRet.Y = Mathf.Clamp(actionSmuggleRet.Y + shortenForwardDistance,
                                    -allowForwardDistance, 0.0f);                            // :2302
                        }
                        if (DiscardSidewaysSmuggle) actionSmuggleRet.X *= 0.7f;              // :2304-2306
                        actionSmuggleRet = BluntMath.GetRotated2D(actionSmuggleRet, toStraightAngle);
                    }
                    // :2314 — демпфирование в толкучке (в лабе соперников нет → множитель 1.0)
                    actionSmuggleRet *= 0.7f + 0.3f * BluntMath.NormalizedClamp(
                        _closestOpponentDistance, 0.6f, 1.2f);
                }
            }
            rotationSmuggleRet = rotationSmuggleTmp;                                         // :2320
            return bestAnimID;
        }
```

Примечания к порту: `AnimCollection.StringToFunctionType`/`Ft*`-константы — если фаза 2 их назвала
иначе, использовать существующие имена (сверить с `CheckFunctionType`); `_physicsVector` — тот же
инстанс, каким `HumanoidBase` фазы 3 варпит movement (не заводить второй — статы/конфиг общие);
`_actualTimeMs` — счётчик тика ×10 мс, инкремент в начале `Tick`.

- [ ] **Шаг 4: прогнать — PASS**; полный набор `check_gpf_*`; обе headless-валидации.

- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/Humanoid.cs tests/check_gpf_cheatable.gd tests/check_gpf_cheatable.gd.uid
git commit -m "feat(gpf): GetBestCheatableAnimID + GetBodyBallDistanceAdvantage (фаза 4, задача 4)"
```

---

### Задача 5: смагглы в тике — накопление, apply-буфер наследника, CalculateMovementSmuggle (Fable 5)

**Files:**
- Modify: `src/gpf/Humanoid.cs` (`CalculateMovementSmuggle`, заполнение Anim при выборе)
- Modify: `src/gpf/HumanoidBase.cs` (Anim-структура: touch/smuggle-поля; тик: накопление смагглов,
  apply-буфер наследника)
- Modify: `src/gpf/AnimationApplier.cs` (ветка smooth/smoothFactor)
- Test: `tests/check_gpf_smuggle_apply.gd`

**Interfaces:**
- Consumes: задачи 2-4 (`Ball`, `GetBestCheatableAnimID` ref-выходы, `GetFrontOfFootOffsetRel`),
  `CalculatePredictedSituation` (появится здесь же — см. ниже), фаза 3 (`Tick`, apply-буфер).
- Produces (для задач 6-8):
  - Anim-структура (`HumanoidBase.Anim`) дополняется по `humanoid.hpp`: `TouchFrame` (уже есть),
    `TouchPos`, `RadiusOffset`, `FullActionSmuggle`, `ActionSmuggle`, `ActionSmuggleOffset` (есть),
    `ActionSmuggleSustain`, `ActionSmuggleSustainOffset` (есть), `MovementSmuggle`,
    `MovementSmuggleOffset` (есть), `PositionOffset`, `OriginatingCommand` (PlayerCommand),
    `OriginatingInterrupt` (int), `FunctionType` (int);
  - apply-буфер дополняется `Anim`/`Smooth`/`SmoothFactor` (закрывает открытый вопрос фазы 3);
    правила `smoothFactor` — humanoid.cpp:277-284: movement→movement на Switch = 0.0, иначе 1.0;
    Shot/ShortPass/HighPass/Deflect/Sliding/BallControl/Trap = 0.8;
  - `internal Vector3 CalculateMovementSmuggle(Vector3 desiredDirection, float desiredVelocityFloat)`
    — порт humanoid.cpp:2326-2408;
  - `internal void CalculatePredictedSituation(out Vector3 predictedPos, out float predictedAngle)`
    — порт humanoidbase.cpp:1603-1615 (нужен и смагглу :2351, и ReQueue задачи 6, и touch-исполнению);
  - геттеры для тестов: `GetActionSmuggle()`, `GetActionSmuggleOffset()`, `GetMovementSmuggle()`,
    `GetMovementSmuggleOffset()`, `GetCurrentTouchFrame()`, `GetSmoothFactor()`.

**Что именно меняется в тике** (это самые тонкие 100 строк фазы — сверять построчно):

1. **Накопление action-смаггла** (humanoid.cpp:668-695): при `touchFrame != -1 && frameNum <=
   touchFrame` — косинусный ease:
   `value = cos((frameNum / (touchFrame + 1) − 0.5) · 2π) + 1` → `value = value·0.1 + 0.9` →
   `actionSmuggleMovement = (actionSmuggle / (touchFrame + 1)) · value · 100` (м/с в
   `spatialState`), `actionSmuggleOffset += actionSmuggleMovement / 100`. Иначе
   `actionSmuggleMovement = 0`.
2. **Накопление movement-смаггла** (:698-719): при `touchFrame == -1 && frameNum <=
   effectiveFrameCount` — та же кос-формула с `effectiveFrameCount + 1` в обоих знаменателях.
3. **Rotation-смаггл** (:722-742): уже портирован в фазе 3 с 16-кадровым капом, НО теперь
   `touchFrame != -1` включает вторую ветку: `beginFrameBias = min(1, (frameNum+1) /
   min(16, touchFrame+1))`, `endFrameBias` = 0 до касания, после — `(frameNum − touchFrame) /
   (effectiveFrameCount − touchFrame)` (`allowPreTouchRotationSmuggle=false`). Убедиться, что
   формула фазы 3 расширена, а не задублирована.
4. **Apply-буфер — порядок наследника** (:765-780, закрывает открытый вопрос):
   `position = startPos + positions[frameNum] + actionSmuggleOffset + actionSmuggleSustainOffset +
   movementSmuggleOffset`, `orientation = startAngle + rotationSmuggleOffset`, `noPos = true`;
   ветка «positions кончились» (:773-777) — `startPos + смагглы`, `noPos = false`. При нулевых
   смагглах порядок численно совпадает с фазой 3 — регрессий walker-теста быть не должно.
5. **`spatialState.positionOffsetMovement = 0`** в начале тика (:121) — уже есть с фазы 3, проверить.
6. **Заполнение Anim при выборе** (humanoid.cpp:1747-1786): при найденном клипе — все поля дословно,
   ВКЛЮЧАЯ порядок: `movementSmuggle = 0` (:1777), затем позиции/команда, затем
   `movementSmuggle = CalculateMovementSmuggle(...)` (:1785) — двойное присваивание оригинала
   переносится как есть (комментарий «needs to be reset here» :1777). `rotationSmuggle.begin`
   (:1769) — формула с `bodyRotationSmoothingMaxAngle · (movement ? 1.0 : 0.5)` — фаза 3 несёт
   только movement-вариант, добавить множитель 0.5 для не-movement.
7. **Сторож «FLYING PLAYERS»** (:338-340): `startPos.Z != 0` → `GD.PushError`, живой код.
   Bump-прерывание (:129-134) — переносится ЗАКОММЕНТИРОВАННЫМ, как в оригинале.

`CalculateMovementSmuggle` (:2326-2408) — порт дословный; лаб-швы: `team->GetDesignatedTeamPossession
Player() == player && match->GetDesignatedPossessionPlayer() == player` → `_designatedPossession`
(поле, дефолт `true` в лабе); `match->IsInPlay()/IsInSetPiece()/GetBallRetainer()` → поля-параметры;
`CastPlayer()->HasPossession()` → `_hasPossession` (поле, лаба обновляет: мяч ближе 1.6 м и ниже
1 м — суррогат с комментарием-швом, настоящий предикат Match::CalculatePossession придёт с матчем);
`GetTimeNeededToGetToBall_ms` → `SetTimeNeededToGetToBall` (решение п.9 скоупа). Формулы (:2381-2399)
— дословно: `maxEffectTimeTreshold_ms = 250 + 80` (idle-выход клипа → 2000), `maxEffectVelocity =
dribbleWalkSwitch`, `maxSmuggleMPS = 1.6`, `NormalizeMax(1.6 · effectiveFrameCount · 0.01)`,
`removeDistance = 0.06`.

`AnimationApplier.Apply` — добавить параметры `smooth`/`smoothFactor`: ветка сглаживания из
`Animation::Apply` (animation.cpp — grep `smooth` в Apply, перенести квата-слерп предыдущей позы
с фактором; наш `Apply` статичен — предыдущие позы читать из скелета до записи). Сигнатура растёт —
обновить все вызовы (лабы, тесты) полным списком аргументов (интероп-гоча).

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 4, задача 5: накопление смагглов (humanoid.cpp:668-742) + apply-буфер наследника (:765-780).
# Ожидания — перевычисление косинусного ease в тесте.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

# сумма кос-ease приращений по формуле :682-691 за кадры 0..n
func cos_ease_sum(total: Vector3, denom: int, frames: int) -> Vector3:
	var acc := Vector3.ZERO
	for f in frames:
		var value: float = cos((float(f) / float(denom) - 0.5) * PI * 2.0) + 1.0
		value = value * 0.1 + 0.9
		acc += (total / float(denom)) * value
	return acc

func _initialize() -> void:
	var ok := true
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var B = load("res://src/gpf/Ball.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)
	var sel = load("res://src/gpf/AnimSelector.cs").new()
	sel.Setup(c)
	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -0.6, 0))
	h.SetBall(ball)

	# ---------- 1. Разбежаться и догнать мяч: тач-клип выбирается, смаггл накапливается ----------
	var got_touch := false
	var touch_frame := -1
	var smuggle_at_selection := Vector3.ZERO
	for i in 600:
		h.Tick(Vector3(0, -1, 0), 3.5, true)  # want_ball = true
		if not got_touch and h.GetCurrentTouchFrame() >= 0:
			got_touch = true
			touch_frame = h.GetCurrentTouchFrame()
			smuggle_at_selection = h.GetActionSmuggle()
		if got_touch:
			break
	if not got_touch:
		print("CHECK FAIL: тач-клип не выбран за 600 тиков"); ok = false
	else:
		# ---------- 2. Накопление == кос-ease формула (:682-691) ----------
		# прогоняем до кадра касания, offset должен сойтись к сумме приращений
		var frames_run := 0
		while h.GetCurrentTouchFrame() >= 0 and h.GetCurrentFrameNum() < touch_frame \
				and frames_run < 100:
			h.Tick(Vector3(0, -1, 0), 3.5, true)
			frames_run += 1
		if h.GetCurrentTouchFrame() == touch_frame:
			var expected: Vector3 = cos_ease_sum(smuggle_at_selection, touch_frame + 1,
				h.GetCurrentFrameNum() + 1)
			var got_off: Vector3 = h.GetActionSmuggleOffset()
			# ease в сумме к touchFrame даёт ~полный смаггл; сверяем длину траектории
			if (got_off - expected).length() > 0.02 + expected.length() * 0.1:
				print("CHECK FAIL: накопление смаггла ", got_off, " != ", expected); ok = false
			# смаггл вошёл в позицию apply-буфера (:769)
			if got_off.length() > 0.005:
				var apply_pos: Vector3 = h.GetApplyPosition()
				var no_smuggle: Vector3 = h.GetApplyPositionNoSmuggle()
				if (apply_pos - no_smuggle).length() < 0.001:
					print("CHECK FAIL: смаггл не в apply-буфере"); ok = false

	# ---------- 3. smoothFactor по типам (:277-284) ----------
	# после выбора тач-клипа (ballcontrol) фактор должен быть 0.8, после movement→movement — 0.0
	if got_touch and not feq(h.GetSmoothFactor(), 0.8):
		print("CHECK FAIL: smoothFactor тач-клипа = ", h.GetSmoothFactor()); ok = false

	# ---------- 4. movement-смаггл без мяча нулевой, с мячом у ног — может быть ненулевым ----------
	var h2 = HB.new()
	h2.Setup(c, sel)
	h2.ResetSituation(Vector3(20, 20, 0), 0.0)  # мяч далеко
	var ball2 = B.new()
	ball2.ResetSituation(Vector3(0, 0, 0))
	h2.SetBall(ball2)
	for i in 50:
		h2.Tick(Vector3(0, -1, 0), 3.5, false)
	if h2.GetMovementSmuggle().length() > 1.0e-6:
		print("CHECK FAIL: movement-смаггл ненулевой при далёком мяче (гейты :2330-2332)"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

`GetApplyPositionNoSmuggle()` — тестовый геттер: `startPos + positions[frameNum]` без смагглов.
`GetCurrentFrameNum()` — геттер кадра. Сигнатура `Tick` получает флаг «хочу мяч» (`wantBall`) —
временный лаб-ввод до настоящей командной очереди (задача 6 заменит на очередь команд, задача 8 —
на клавиши).

- [ ] **Шаг 2: прогнать — падает.** `--import`.
- [ ] **Шаг 3: реализация** по списку «Что именно меняется в тике» выше, построчно с C++.
- [ ] **Шаг 4: прогнать — PASS**; полный набор `check_gpf_*` (walker обязателен: нулевые смагглы
  ничего не меняют в чистом движении); обе headless-валидации.
- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/Humanoid.cs src/gpf/HumanoidBase.cs src/gpf/AnimationApplier.cs src/lab/WalkLabMain.cs tests/check_gpf_smuggle_apply.gd tests/check_gpf_smuggle_apply.gd.uid
git commit -m "feat(gpf): смагглы в тике — накопление, apply наследника, CalculateMovementSmuggle (фаза 4, задача 5)"
```

---

### Задача 6: ReQueue — прерывание клипа и командная очередь (Opus 5)

**Files:**
- Modify: `src/gpf/HumanoidBase.cs` (контур тика: interruptAnim-машинерия, previousAnim)
- Modify: `src/gpf/Humanoid.cs` (гейты ReQueue)
- Test: `tests/check_gpf_requeue.gd`

**Interfaces:**
- Consumes: задачи 3-5 (SelectAnim наследника, Anim-поля, `CalculatePredictedSituation`).
- Produces (для задач 7-8):
  - `Tick` принимает **очередь команд** `List<PlayerCommand>` (внутренний путь) + мост
    `TickBridge(Vector3 desiredDirection, float desiredVelocity, bool wantBall)`, собирающий
    очередь лаб-уровня: `wantBall` → `[BallControl, Movement]`, иначе `[Movement]` (порядок
    «первая применимая» — humanoid.cpp:229-247); задача 8 добавит pass/shot-команды;
  - int-константы `InterruptNone/InterruptSwitch/InterruptReQueue` (порт `e_InterruptAnim`;
    Trip/Bump/LocalInterrupt — только значения, ветки придут со столкновениями);
  - `_previousAnim` (полная копия Anim при смене клипа, :1759);
  - `GetReQueueCount()` — тестовый счётчик перевыборов по ReQueue.

**Порт, построчно:**
1. **Константы** (humanoid.cpp:56-63): `initialReQueueDelayFrames=22`,
   `minRemainingMovementReQueueFrames=6`, `minRemainingTrapReQueueFrames=6`,
   `maxBallControlReQueueFrame=8`, `allowReQueue/Movement/BallControl/Trap = true`.
2. **Гейт тика** (:140-212): `mayReQueue` — сброс при уже висящем interrupt (:145-149); маска
   частоты (:161-184): `designated + actionDistance < 3` → `(время + teamID·10) % 20 == 0`;
   `designated` → `% 30`; `teamDesignated` → `% 40`; `dist < 5` → `% 50`; `dist < 10` → `% 80`
   (лаба: оба designated-флага true — поля из задачи 5; `actionDistance` — :163 дословно);
   правильный ли клип (:189-205): movement без владения при `ballDistance < 16` / movement с
   владением / trap+`TouchPending()` / ballcontrol+`TouchPending()`, без спец-стейтов.
   `TouchPending()` — grep в humanoid/humanoidbase.hpp, портировать (по смыслу
   `touchFrame != -1 && frameNum <= touchFrame` — сверить с фактическим телом!).
3. **Interrupt-детект** (:136-138): граница клипа → `Switch` (уже есть в фазе 3 неявно — теперь
   явным полем `_interruptAnim`); `mayReQueue` → `ReQueue` (:210-212).
4. **Отказные фильтры SelectAnim** (:1192-1234) — дословно (все пороги: `frameNum+6 >
   effectiveFrameCount`, `frameNum > 8` для ballcontrol, similarity-отказы :1205-1231).
5. **«Не в тот же квадрант»** (:1727-1742) — после `GetBestCheatableAnimID`/movement-выбора.
6. **`CalculateFactualSpatialState`-гейт** (:1236): `localInterruptAnim != ReQueue || frameNum > 12`.
7. **Пост-выбор** (:269-326): `startPos/startAngle`, `CalculatePredictedSituation(nextStartPos,
   nextStartAngle)` (поля завести), smoothFactor-правила (задача 5), `reQueueDelayFrames`
   (:317-326): установка при ReQueue same-type, декремент каждый тик.
8. **Разрешение interrupt в конце** (:336): `_interruptAnim = None`.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 4, задача 6: ReQueue (humanoid.cpp:140-212, :1192-1234). Поведенческие инварианты.

func _initialize() -> void:
	var ok := true
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var B = load("res://src/gpf/Ball.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)
	var sel = load("res://src/gpf/AnimSelector.cs").new()
	sel.Setup(c)

	# ---------- 1. Резкая смена команды посреди клипа → перевыбор раньше границы ----------
	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -1.0, 0))  # мяч рядом — маска частоты активна
	h.SetBall(ball)
	# разогнаться прямо
	for i in 100:
		h.TickBridge(Vector3(0, -1, 0), 5.0, false)
	# резко назад: без ReQueue реакция ждёт границы клипа; с ReQueue — быстрее
	var id_before: int = h.GetCurrentAnimId()
	var frames_to_change := -1
	for i in 40:
		h.TickBridge(Vector3(0, 1, 0), 5.0, false)
		if h.GetCurrentAnimId() != id_before:
			frames_to_change = i
			break
	if frames_to_change < 0:
		print("CHECK FAIL: смена команды не перевыбрала клип за 40 тиков"); ok = false
	if h.GetReQueueCount() == 0:
		# допустимо, если смена пришлась ровно на границу — повторить с другим сдвигом
		var requeued := false
		for attempt in 3:
			for i in 7:
				h.TickBridge(Vector3(0, 1, 0), 5.0, false)
			for i in 40:
				h.TickBridge(Vector3(attempt - 1, -1, 0).normalized(), 5.0, false)
				if h.GetReQueueCount() > 0:
					requeued = true
					break
			if requeued: break
		if not requeued:
			print("CHECK FAIL: ReQueue ни разу не сработал"); ok = false

	# ---------- 2. Похожая команда НЕ перевыбирает (:1206-1209) ----------
	var h2 = HB.new()
	h2.Setup(c, sel)
	h2.ResetSituation(Vector3.ZERO, 0.0)
	var ball2 = B.new()
	ball2.ResetSituation(Vector3(0, -30, 0))  # мяч далеко — движение с ballDistance > 16 не requeue-ится
	h2.SetBall(ball2)
	for i in 30:
		h2.TickBridge(Vector3(0, -1, 0), 5.0, false)
	var rq_before: int = h2.GetReQueueCount()
	for i in 100:
		h2.TickBridge(Vector3(0, -1, 0), 5.0, false)  # та же команда
	if h2.GetReQueueCount() != rq_before:
		print("CHECK FAIL: ReQueue на неизменной команде (", h2.GetReQueueCount(), ")"); ok = false

	# ---------- 3. Детерминизм контура с ReQueue ----------
	var run_ids: Array = []
	for run in 2:
		var hh = HB.new()
		hh.Setup(c, sel)
		hh.ResetSituation(Vector3.ZERO, 0.0)
		var bb = B.new()
		bb.ResetSituation(Vector3(0, -1.0, 0))
		hh.SetBall(bb)
		var ids: Array = []
		for i in 150:
			hh.TickBridge(Vector3(0, -1, 0) if i < 75 else Vector3(1, 0, 0), 5.0, false)
			ids.append(hh.GetCurrentAnimId())
		run_ids.append(ids)
	if run_ids[0] != run_ids[1]:
		print("CHECK FAIL: недетерминизм контура с ReQueue"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: прогнать — падает.** `--import`.
- [ ] **Шаг 3: реализация** по списку «Порт, построчно».
- [ ] **Шаг 4: PASS**; полный набор `check_gpf_*`; walker может сменить выборы клипов (ReQueue жив
  и в чистом движении при близком мяче — в walker-тесте мяча нет → `SetBall` не зван → гейты мертвы,
  регрессий быть не должно; если `SetBall` обязателен — мяч в walker ставить далеко). Обе
  headless-валидации.
- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/HumanoidBase.cs src/gpf/Humanoid.cs tests/check_gpf_requeue.gd tests/check_gpf_requeue.gd.uid
git commit -m "feat(gpf): ReQueue — прерывание клипа и командная очередь (фаза 4, задача 6)"
```

---

### Задача 7: исполнение касания — touch-векторы + Touch в тике + коллизии мяч↔тело (Fable 5)

**Files:**
- Create: `src/gpf/TouchVectors.cs` (статики humanoid_utils)
- Modify: `src/gpf/Humanoid.cs` (touch-ветки тика, GetBestPossibleTouch, контролируемая коллизия)
- Modify: `src/gpf/HumanoidBase.cs` (если тик-каркас требует)
- Test: `tests/check_gpf_touch_vectors.gd`

**Interfaces:**
- Consumes: задачи 2-6; `GpfRng` (инжекция `SetRng` — обязательна для всех формул с `random()`).
- Produces (для задачи 8):
  - `Gpf.TouchVectors` (статик-класс, все методы принимают контекст параметрами — без глобалов):
    - `GetDifficultyFactors(Ball ball, Vector3 playerMovement, Vector3 playerPosition,
      Vector3 playerDirectionVec, float positionOffsetLength, float statBallControl,
      float lastOppTouchBias, float statReaction, GpfRng rng, out float distanceFactor,
      out float heightFactor, out float ballMovementFactor)` — порт humanoid_utils.cpp:146-206
      (перехват-штраф :182-195: `lastOppTouchBias` — параметр, в лабе 0; `random(0.5,1)` → rng);
    - `GetBallControlVector(...)` — порт :208-332 (все аргументы оригинала + статы/контекст
      параметрами; `player->GetController()->GetFloatVelocity()` → параметр
      `controllerVelocity` — в лабе желаемая скорость команды; `GetClosestOpponentDistance` →
      параметр; выходные `xRot/yRot` — `out`);
    - `GetTrapVector(...)` — порт :334-352;
    - `GetShotVector(...)` — порт :354-520 (все `random()` → rng; `touchInfo.desiredDirection` —
      из команды);
  - `Humanoid`: `internal Vector3 GetBestPossibleTouch(Vector3 desiredTouch, int functionType)` —
    порт humanoid.cpp:2410-…​ (конец функции — до следующего метода; maxPower-кламп :2429-2437,
    стат-скидки :2444-2448, randomRotation :2456-2467 через rng, `animBallDirection` :2459 с
    `startAngle + rotationSmuggleOffset`);
  - тик: **ветки исполнения касания** (:390-646) при `touchFrame == frameNum`:
    `fullBallDistance`/`touchableDistance=0.4` (:396-398), `bumpyRideBias` (:416-419),
    высотный гейт `|desiredBallHeight − ballZ| < 1` (:422), затем по типам — Trap (:426-443),
    BallControl (:445-461), пасы (:463-546 — без AI_GetPass, решение п.5 скоупа; зато
    `touchVec = ballDirection · 36 · (ballPower + 0.3)` :511, `GetBestPossibleTouch` :516,
    кривизна :518-526, вращение :537-541), Shot (:548-582 — без AI_GetShotDirection), Interfere
    (:584-596), Deflect (:598-630 — retain-гейты; в лабе `canRetain` выключен параметром — вратарский
    контур не эта фаза, ветка портируется), Sliding (:632-…);
    **контролируемая коллизия** (:362-387): триггер `TriggerControlledBallCollision` + условия
    (:342-359, пороги 0.6/0.65/1.6); `match->CheckBallCollisions` (match.cpp:1926-2045) —
    **лаб-оркестратор** (задача 8) зовёт `Gpf.BallBodyCollider.Check(...)`:
    - `Gpf.BallBodyCollider` (новый статик в `TouchVectors.cs` или отдельно): порт CheckBallCollisions
      с AABB по сегментам костей утилитарного скелета (решение п.7 скоупа): AABB сегмента =
      min/max концов кости ± `0.12` паддинг; пороги/формулы :1931-2042 дословно (`150 мс`-кулдаун,
      `boundingBoxSizeOffset` по типам, отражение :2024-2039, `random(-30,30)` → rng);
  - `_lastTouchTimeMs` обновляется каждым касанием (для `GetLastTouchBias` задачи 4).

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 4, задача 7: touch-векторы (humanoid_utils.cpp:146-520) + GetBestPossibleTouch.
# Формулы перевычисляются с фиксированным сидом RNG.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func _initialize() -> void:
	var ok := true
	var TV = load("res://src/gpf/TouchVectors.cs")
	var B = load("res://src/gpf/Ball.cs")
	var RNG = load("res://src/gpf/GpfRng.cs")
	if TV == null:
		print("CHECK FAIL: TouchVectors.cs не найден"); quit(1); return

	# ---------- 1. GetDifficultyFactors: покой у ног → все факторы ~0 ----------
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -0.5, 0))
	var rng = RNG.new(); rng.Reseed(7)
	var f: Dictionary = TV.GetDifficultyFactorsBridge(ball, Vector3.ZERO, Vector3.ZERO,
		Vector3(0, -1, 0), 0.0, 0.6, 0.0, 0.6, rng)
	# позиция+0.2·dir → до мяча ~0.3 м < 0.7 → fartherAwayPenalty = 0; скорости 0 → пенальти 0
	if not feq(float(f["distance"]), 0.0, 1.0e-3) or not feq(float(f["height"]), 0.0, 1.0e-3):
		print("CHECK FAIL: DifficultyFactors в покое: ", f); ok = false

	# ---------- 2. GetDifficultyFactors: перевычисление штрафа расстояния ----------
	# игрок в 1.3 м от мяча: fartherAwayPenalty = pow(NormalizedClamp(1.3-0.2·1... , 0.7, 1.3), 2)·2
	rng.Reseed(7)
	var pos := Vector3(0, 1.0, 0)  # мяч в (0,-0.5) → расстояние от pos+0.2·(0,-1,0) до мяча = 1.3
	var f2: Dictionary = TV.GetDifficultyFactorsBridge(ball, Vector3.ZERO, pos,
		Vector3(0, -1, 0), 0.0, 0.6, 0.0, 0.6, rng)
	var far_pen: float = pow(clampf((1.3 - 0.7) / (1.3 - 0.7), 0.0, 1.0), 2.0) * 2.0
	var dist_exp: float = far_pen * 4.0
	# skillPenaltyMultiplier = (1-0.6·0.5)·random(0.5,1); random — первый вызов rng с сидом 7
	var rng2 = RNG.new(); rng2.Reseed(7)
	var skill_mult: float = (1.0 - 0.6 * 0.5) * rng2.Uniform(0.5, 1.0)
	dist_exp = clampf(dist_exp * skill_mult, 0.0, 1.0)
	if not feq(float(f2["distance"]), dist_exp, 1.0e-3):
		print("CHECK FAIL: distanceFactor ", f2["distance"], " != ", dist_exp); ok = false

	# ---------- 3. Детерминизм GetShotVector по сиду ----------
	var shot_args := {
		"desired_direction": Vector3(0, -1, 0), "desired_power": 0.8,
		"touch_velocity": Vector3(0, -5, 0),
	}
	rng.Reseed(99)
	var s1: Vector3 = TV.GetShotVectorBridge(ball, shot_args, rng)
	rng.Reseed(99)
	var s2: Vector3 = TV.GetShotVectorBridge(ball, shot_args, rng)
	if s1 != s2:
		print("CHECK FAIL: GetShotVector недетерминирован при одном сиде"); ok = false
	if s1.length() < 5.0:
		print("CHECK FAIL: удар слабее разумного: ", s1.length()); ok = false
	# удар прижат к желаемому направлению (y-компонента доминирует и отрицательна)
	if s1.y > -absf(s1.x):
		print("CHECK FAIL: удар не туда: ", s1); ok = false

	# ---------- 4. BallControl толкает мяч вперёд по ходу ----------
	rng.Reseed(3)
	var bc: Vector3 = TV.GetBallControlVectorBridge(ball, Vector3(0, -1, 0), 5.0, rng)
	if bc.y >= 0.0:
		print("CHECK FAIL: ballcontrol не вперёд: ", bc); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

Мостовые обёртки (`*Bridge`) собирают полный контекст с лаб-дефолтами; их сигнатуры фиксирует
реализация — тест подстраивается под мосты, формулы под C++.

- [ ] **Шаг 2: прогнать — падает.** `--import`.
- [ ] **Шаг 3: реализация.** Порядок: `GetDifficultyFactors` → `GetBallControlVector` (внутри —
  `GetFrontOfFootOffsetRel` задачи 4, `StretchSprintTo` фазы 3) → `GetTrapVector` →
  `GetShotVector` → `GetBestPossibleTouch` → тик-ветки :390-646 → `BallBodyCollider`. Все
  `random()` → `_rng.Uniform`. `AI_GetPass`/`AI_GetShotDirection`-блоки — пропуск с комментарием-швом
  (решение п.5 скоупа).
- [ ] **Шаг 4: PASS**; полный набор; обе headless-валидации.
- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/TouchVectors.cs src/gpf/Humanoid.cs src/gpf/HumanoidBase.cs tests/check_gpf_touch_vectors.gd tests/check_gpf_touch_vectors.gd.uid
git commit -m "feat(gpf): touch-векторы и исполнение касания в тике (фаза 4, задача 7)"
```

---

### Задача 8: ball_lab — игрок + мяч, глазная приёмка (Opus 5)

**Files:**
- Create: `src/lab/BallLabMain.cs`
- Create: `scenes/lab/ball_lab.tscn` (один `Node3D` со скриптом — паттерн `walk_lab.tscn`)
- Test: `tests/check_gpf_ball_walker.gd`

**Interfaces:**
- Consumes: всё из задач 1-7; `StickmanRenderer`, `GpfSpace`/`SkeletonBuilder`, `AnimationApplier`
  (фазы 1-3), паттерн `WalkLabMain` (ввод, HUD, фикс-тик).
- Produces: сцена приёмки фазы. `walk_lab` НЕ трогается (эталон фазы 3).

**Сцена:**
- `_Ready`: `Engine.PhysicsTicksPerSecond = 100`; скелет+палочник как в walk_lab; `Gpf.Ball`
  (визуал — `SphereMesh` r=0.11 внутри `GpfSpace`); `Gpf.HumanoidBase` с `SetBall`/`SetRng`
  (сид фиксированный, печатается в HUD); мяч стартует в `(0, -2, 0)`.
- `_PhysicsProcess`: (1) опрос стрелок → направление/скорость команды (паттерн walk_lab);
  (2) сборка очереди команд лаб-уровня: зажат `W` → пас (`ShortPass` c `TouchInfo` по направлению
  команды), `S` → удар (`Shot`), иначе близкий мяч → `[BallControl, Movement]`; (3) `humanoid.Tick`;
  (4) `BallBodyCollider.Check` + `ball.Process()`; (5) применение клипа + позиция мяча в визуал.
- HUD: имя клипа, `touchFrame`/кадр, |actionSmuggle|, |movementSmuggle|, скорость игрока и мяча,
  дистанция нога-мяч в кадр контакта (печать в консоль в кадр касания — для приёмки «нога у мяча»).
- Маркер: маленькая сфера в `touchPos` выбранного тач-клипа (жёлтая), гаснет после касания.

- [ ] **Шаг 1: написать падающий тест** — `tests/check_gpf_ball_walker.gd`, поведенческий
  сквозной (как `check_gpf_walker.gd`, но с мячом; без сцены — прямой прогон ядра):

```gdscript
extends SceneTree
# Фаза 4, задача 8: сквозной прогон — игрок добегает до мяча, касается, ведёт.
# Приёмка «нога у мяча в кадр контакта» в headless-приближении: в кадр касания
# позиция мяча близка к предсказанной touchPos (сам факт Touch меняет траекторию мяча).

func _initialize() -> void:
	var ok := true
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var B = load("res://src/gpf/Ball.cs")
	var RNG = load("res://src/gpf/GpfRng.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)
	var sel = load("res://src/gpf/AnimSelector.cs").new()
	sel.Setup(c)
	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -3.0, 0))
	var rng = RNG.new(); rng.Reseed(1234)
	h.SetBall(ball)
	h.SetRng(rng)

	# ---------- 1. Добежать и коснуться ----------
	var touched := false
	var touch_tick := -1
	var mom_before := Vector3.ZERO
	for i in 1200:
		var had_touch_frame: bool = h.GetCurrentTouchFrame() == h.GetCurrentFrameNum() \
			and h.GetCurrentTouchFrame() >= 0
		if had_touch_frame:
			mom_before = ball.GetMovement()
		h.TickBridge(Vector3(0, -1, 0), 3.5, true)
		ball.Process()
		if had_touch_frame and ball.GetMovement() != mom_before:
			touched = true
			touch_tick = i
			break
	if not touched:
		print("CHECK FAIL: касание не случилось за 1200 тиков"); ok = false

	# ---------- 2. Смаггл жил хотя бы раз (нога дотянулась не магией позиций) ----------
	# после первого касания у клипа был ненулевой full-смаггл ИЛИ нулевой (идеальное попадание);
	# проверяем, что механизм вообще включался: тач-клип был выбран
	if touch_tick < 0:
		print("CHECK FAIL: тач-клип не выбирался"); ok = false

	# ---------- 3. Ведение: серия касаний, мяч остаётся при игроке ----------
	var touches := 0
	for i in 2000:
		var had_touch_frame: bool = h.GetCurrentTouchFrame() == h.GetCurrentFrameNum() \
			and h.GetCurrentTouchFrame() >= 0
		var mb: Vector3 = ball.GetMovement()
		h.TickBridge(Vector3(0, -1, 0), 3.5, true)
		ball.Process()
		if had_touch_frame and ball.GetMovement() != mb:
			touches += 1
	if touches < 3:
		print("CHECK FAIL: ведение не удерживается: касаний ", touches); ok = false
	var dist: float = (ball.Predict(0) - h.GetSpatialPosition()).length()
	if dist > 6.0:
		print("CHECK FAIL: мяч убежал: ", dist, " м"); ok = false

	# ---------- 4. Детерминизм сквозного прогона (фикс-сид) ----------
	var positions: Array = []
	for run in 2:
		var hh = HB.new(); hh.Setup(c, sel); hh.ResetSituation(Vector3.ZERO, 0.0)
		var bb = B.new(); bb.ResetSituation(Vector3(0, -3.0, 0))
		var rr = RNG.new(); rr.Reseed(77)
		hh.SetBall(bb); hh.SetRng(rr)
		for i in 500:
			hh.TickBridge(Vector3(0, -1, 0), 3.5, true)
			bb.Process()
		positions.append([hh.GetSpatialPosition(), bb.Predict(0)])
	if positions[0][0] != positions[1][0] or positions[0][1] != positions[1][1]:
		print("CHECK FAIL: недетерминизм сквозного прогона"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: прогнать — вероятно, частично проходит уже после задачи 7** (ядро готово) — тогда
  тест выполняет роль сквозного замка; если падает — чинить интеграцию, не тест.
- [ ] **Шаг 3: реализовать сцену** `BallLabMain.cs` + `ball_lab.tscn` по структуре выше.
- [ ] **Шаг 4: PASS всех тестов + обе headless-валидации + ручной запуск сцены:**

```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" res://scenes/lab/ball_lab.tscn
```

Глазная приёмка (человеком, вне скоупа субагента — субагент только готовит сцену): дриблинг
непрерывен, нога у мяча в кадр контакта, пас/удар уходят по направлению, мяч скачет/крутится
правдоподобно.

- [ ] **Шаг 5: коммит**

```powershell
git add src/lab/BallLabMain.cs scenes/lab/ball_lab.tscn tests/check_gpf_ball_walker.gd tests/check_gpf_ball_walker.gd.uid
git commit -m "feat(lab): ball_lab — игрок и мяч на ядре порта, сквозной тест (фаза 4, задача 8)"
```

---

### Задача 9: матч на фикс-тик 100 Гц (Opus 5 или Sonnet 5)

**Files:**
- Modify: `project.godot` (`physics/common/physics_ticks_per_second=100`)

Решение именно этой фазы (см. [[открытые-вопросы]]): мультиплеер-дисциплина №1 роадмапа. Ставим
глобально в `project.godot` (лабы, ставящие 100 из кода, не пострадают — значение совпадёт).

- [ ] **Шаг 1: замерить baseline** — обе headless-валидации ДО правки, сохранить вывод второй
  (категории ошибок) в заметку задачи.
- [ ] **Шаг 2: внести правку** в `project.godot`:

```ini
[physics]

common/physics_ticks_per_second=100
```

(секция `[physics]` может уже существовать — тогда только ключ.)

- [ ] **Шаг 3: перепрогон** — обе headless-валидации; сравнить категории ошибок с baseline
  (счётчики могут плавать). Флейки-тесты (`check_keeper_clear.gd`, `check_keeper_no_rush_on_pass.gd`,
  flow/intent-семейство) прогнать 3×: устойчивый регресс = чинить или откатывать, единичный флейк =
  норм. GDScript-геймплей масштабируется `delta` — систематических поломок не ожидается; таймеры
  на кадрах (если найдутся) — чинить по месту с комментарием.
- [ ] **Шаг 4: ручной смоук матча** (запуск `main_menu.tscn`, пара минут игры) — чувство
  движения/паса не развалилось. Это готовит человек-приёмку; субагент фиксирует только headless.
- [ ] **Шаг 5: коммит**

```powershell
git add project.godot
git commit -m "feat(match): фикс-тик 100 Гц — мультиплеер-дисциплина порта (фаза 4, задача 9)"
```

---

### Задача 10: документация (Sonnet 5)

**Files:**
- Modify: `docs/wiki/порт-gameplayfootball.md` (статус фазы 4; секции: Ball, smuggle-контур,
  ReQueue, touch-векторы, ball_lab, новые тесты; «Что НЕ портировано» — переписать: смагглы/ReQueue
  убрать, MentalImage/Eliza/командные очереди/Header-Catch-исполнение/ретейнер-контур — оставить)
- Modify: `docs/wiki/открытые-вопросы.md` (закрыть: ReQueue, movementSmuggle наследника, порядок
  apply-буфера, smoothFactor-поле, сторож z==0, 100 Гц матча, movement-отбор наследника; добавить:
  AABB-коллизии по костям — приближение против Geometry-сегментов, HasPossession/
  TimeNeededToGetToBall — лаб-суррогаты до ИИ-фазы, AI_GetPass/AI_GetShotDirection — швы, GpfRng ≠
  последовательность эталон-exe, min-в-maxSmuggleDiscardDistance — подозрение на баг оригинала,
  влияние 100 Гц на старые GDScript-тайминги — наблюдать)
- Modify: `docs/wiki/index.md` (если появится страница; иначе — обновить описание строки порта)
- Modify: `docs/wiki/конвенции.md` (только если задачи 1-8 поймали новые интероп-грабли)
- Modify: `log.md` (веха фазы 4 — append-only)
- Modify: `.claude/hooks/wiki-hint.py` (маппинги: `Ball.cs`, `Humanoid.cs`, `TouchVectors.cs`,
  `GpfRng.cs`, `GpfPitch.cs`, `PlayerCommand.cs`, `BallLabMain.cs` → `порт-gameplayfootball.md`)

- [ ] **Шаг 1:** переписать устаревшие утверждения на затронутых страницах (не «UPDATE:»-дописки).
- [ ] **Шаг 2:** `docs/wiki/константы.md` — новые настраиваемые числа НЕ появились (всё — данные
  оригинала в коде с комментариями-ссылками) — но проверить это утверждение по факту diff'а задач
  1-8; если что-то стало тюнингом (пороги лаб-суррогатов) — внести.
- [ ] **Шаг 3:** `log.md` — веха `## [2026-07-30] feat | фаза 4 порта GPF: smuggle + физика мяча`.
- [ ] **Шаг 4:** прогнать скилл `wiki-lint` (битые ссылки/сироты/противоречия).
- [ ] **Шаг 5: коммит**

```powershell
git add docs/wiki log.md .claude/hooks/wiki-hint.py
git commit -m "docs(wiki): фаза 4 порта GPF — smuggle, мяч, ReQueue, ball_lab (задача 10)"
```

---

## Порядок и зависимости

```
1 (фундамент) → 2 (Ball) → 3 (SelectAnim) → 4 (Cheatable) → 5 (смагглы) → 6 (ReQueue) → 7 (touch) → 8 (ball_lab)
задача 9 (100 Гц) — независима, можно в любой момент после 1
задача 10 (доки) — строго последней
```

## Самопроверка плана (выполнена при написании)

1. **Покрытие задания фазы:** GetBestCheatableAnimID (задача 4) ✓, GetBodyBallDistanceAdvantage
   (4) ✓, частичный сброс смаггла :2247-2315 (4) ✓, накопление-ease :675-694 (5) ✓,
   movementSmuggle :2326+:699-718 (5) ✓, rotationSmuggle.end реальный (5) ✓, физика мяча целиком
   минус сетка (2) ✓, Touch/SetRotation (2) ✓, touch-векторы (7) ✓, GetDifficultyFactors + seeded
   RNG (7) ✓, CheckBallCollisions (7) ✓, ReQueue (6) ✓, порядок apply наследника (5) ✓,
   smoothFactor-поле (5) ✓, сторож z==0 (5) ✓, 100 Гц (9) ✓, movement-отбор наследника (3) ✓,
   touch_bodypart-пересмотр — НЕ решается, фиксируется в открытых вопросах (10) ✓.
2. **Плейсхолдеров нет**: каждый кодовый шаг несёт код или точную ссылку файл:строки C++ с
   указанием «перенести дословно» — для механики, которую опасно переписывать по памяти плана
   (урок фаз 1-3: код C++ — истина, план — нет).
3. **Согласованность типов**: мостовые сигнатуры `Tick`/`TickBridge`, `CheatableBridge`,
   ref-выходы `GetBestCheatableAnimID` согласованы между задачами 4-8; тестовые мосты объявлены
   в Produces своих задач.

**Правило для исполнителя (повторение урока фаз 1-3):** при любом расхождении между этим планом и
C++-оригиналом — прав оригинал. План даёт структуру и ссылки; числовые литералы и порядок операций
исполнитель сверяет с `FootballCPP` построчно, а ревьюер — повторно.

# Порт GameplayFootball, фаза 3: CalculatePhysicsVector (варпинг траектории) — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Цель:** корневая траектория выбранного клипа пересчитывается под реальную физику, ловкость и статы
игрока (`CalculatePhysicsVector`), палочник в `walk_lab` движется по варпнутым позициям с настоящим
`CalculateSpatialState` вместо lite-интеграции — движение становится узнаваемо «живым» (приёмка:
глазами, сверка с эталонным exe).

**Архитектура:** дословный порт `HumanoidBase::CalculatePhysicsVector` (`humanoidbase.cpp:2014-2544`)
и его хелперов (`humanoid_utils.cpp:68-100,129-144`) в чистый C#-класс `Gpf.PhysicsVector`; порт
контура состояния `HumanoidBase` (порядок `Process` `:585-594` + apply-данные `:684-711`,
`CalculateSpatialState` `:1622-1726`, `CalculateFactualSpatialState` `:1728-1737`, заполнение
`currentAnim` из `SelectAnim` `:1501-1597`) в новый `Gpf.HumanoidBase`. `WalkLabMain` делегирует
состояние `HumanoidBase` и применяет клип с `noPos=true` + варпнутой позицией корня. Кэш позиций
корня per-клип (`match.cpp:86-105`) переезжает в `AnimCollection.Load`.

**Tech stack:** Godot 4.7.1 .NET (`net8.0`), C#-ядро + GDScript check-харнесс.

**Первоисточники:** роадмап [2026-07-29-gameplayfootball-port-roadmap-design.md](../specs/2026-07-29-gameplayfootball-port-roadmap-design.md) (п. 3 фазировки),
тех-отчёт [2026-07-29-gameplayfootball-core-report.md](../specs/2026-07-29-gameplayfootball-core-report.md) §3.1.
C++-оригинал: `C:\Users\User\Desktop\projects\FootballCPP` (read-only; все номера строк — от него).
Ключевые файлы: `src/onthepitch/player/humanoid/humanoidbase.cpp` (`:569-714` Process,
`:1374-1601` SelectAnim, `:1603-1737` состояние, `:2014-2544` варпинг),
`src/onthepitch/player/humanoid/humanoid_utils.cpp` (`:68-100`, `:129-144`),
`src/onthepitch/player/humanoid/humanoid.cpp` (`:40-65` константы, `:1657-1722` места вызова),
`src/onthepitch/player/playerbase.cpp` (`:127-146`), `src/onthepitch/match.cpp` (`:86-105` кэш),
`src/base/math/vector3.cpp` (`:190-228`), `src/gamedefines.hpp` (`:18-44`).

## Global Constraints

- **Godot exe:** `C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe` (единственный валидный).
- **Перед любым headless-тестом — `dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"`**: headless-команды C# сами не пересобирают.
- **Порт дословный, bug-for-bug, каждая функция и каждый числовой литерал — с комментарием-ссылкой
  `файл:строки` C++.** Спорные места оригинала НЕ чинить молча (напр. `todo: shouldn't this be
  agility?` у `technical_ballcontrol` в бонусе угла касания `:2108` — переносится как есть,
  с комментарием). Главный риск фазы — не код, а ~200 взаимно откалиброванных констант и порядок их
  применения; расхождение даёт «плавающих»/«дёргающихся» игроков и компилятором не ловится.
- **Опорные числа в тестах — только из сырых ключей `.anim` и формул C++** (урок фазы 2: план может
  ошибаться, данные — нет). Тест, которому нужно эталонное число, сам парсит сырую строку файла или
  перевычисляет формулу, а не берёт константу из этого документа.
- **Мёртвые ветки оригинала портируются дословно.** Четыре mod-флага выключены в оригинале
  (`mod_CorneringBraking`, `mod_MaximumAccelDecel`, `mod_BrakeOnTouch`, `mod_CheatBodyDirection`,
  `:2138-2146`) — их код переносится целиком под `static readonly bool` (не `const` — иначе
  CS0162 unreachable code на живой сборке).
- **Сортировки только стабильные** (`AnimSelector.StableSort`) — фаза 3 новых сортировок не вводит,
  но при любой правке отбора запрет `List.Sort`/`Array.Sort` действует.
- **Float-парсинг — только `CultureInfo.InvariantCulture`** (`BluntMath.AtoF`/`AtoI`).
- **Namespace `Gpf`**, ядро без `[GlobalClass]` и без чтения `FootballConstants`. Тюнинг — параметрами
  (статы, конфиг-факторы, touch-контекст), никаких глобалов.
- **Данные `assets/gpf/**` — read-only.**
- **Оси:** ядро — «их» пространство (Z-вверх, вперёд −Y); конверсия — только базис `GpfSpace`.
- **Интероп GDScript↔C#:** `var x := ...` не выводит тип из C#-Variant — тип явно; C#-дефолт-аргументы
  моста не переносятся — звать полным списком; enum-ы через мост — `int`-иды; статики зовутся прямо на
  `load("res://src/gpf/X.cs")` (паттерн `check_gpf_bluntmath.gd:12`). Методы с `out`-параметрами через
  мост не зовутся — для тестов нужны обёртки-геттеры.
- **Check-скрипты** — конвенции репо: `extends SceneTree`, `_initialize()`, аккумулятор `ok`,
  `print("CHECK FAIL: ...")` построчно, финал `print("CHECK PASS" if ok else "CHECK FAIL")` +
  `quit(0 if ok else 1)`. Новый `.gd` требует `.uid`: после создания прогнать
  `& "<godot exe>" --path "<repo>" --headless --import` и закоммитить `.uid` вместе со скриптом.
- **Обе стандартные headless-валидации** (меню-загрузка и `match.tscn`) — в финале каждой задачи,
  затрагивающей `src/`; у сцены матча есть известный baseline ошибок — диффать по категории/тексту,
  не по счётчику.
- **Коммиты** — Conventional Commits, описания по-русски.
- **Вики не трогать до задачи 6** (там всё разом).
- **Модель по таблице CLAUDE.md:** задачи 3–4 — критичная математика варпинга (**Fable 5**);
  задачи 1–2 — механический перенос хелперов (**Opus 5**); задача 5 — сцена/механика (**Opus 5**);
  задача 6 — доки (**Sonnet 5**).
- **Скорости** (`gamedefines.hpp:18-27`): idle 0 / dribble 3.5 / walk 5.0 / sprint 8.0 +
  `animSprintVelocity` **7.0** (`:23`); переключатели 1.8 / 4.2 / 6.0. Корзины дескрипторов клипа
  (`Animation.BucketVelocity`): верх **7.0**, не 8.0. Это ДВЕ разные семёрки: `animSprintVelocity` —
  константа исходного пространства спринта для `StretchSprintTo`, литерал 7.0 в `BucketVelocity` —
  квантование дескрипторов; не объединять.

## Скоуп фазы 3

**Портируется:** `CalculatePhysicsVector` целиком (все ветки типов клипов, включая мёртвые при
movement-only использовании — pass/shot/sliding/trip; они понадобятся фазе 4 без переделки);
`CalculateMovementAtFrame`, `StretchSprintTo`, `GetMaxVelocity`; кэш позиций корня; `SpatialState`
полностью; порядок тика `Process` (`:585-594`), apply-данные (`:684-711`), `CalculateSpatialState`,
`CalculateFactualSpatialState`, `CalculateOutgoingMovement`, заполнение `currentAnim` при выборе
(`:1558-1597`, smuggle-поля — нули), `rotationSmuggle.begin/end` (`:1580-1581`) с константами
`bodyRotationSmoothingFactor`/`bodyRotationSmoothingMaxAngle` (`humanoid.cpp:54-55`).

**НЕ портируется в фазе 3** (уходит в [[открытые-вопросы]] задачей 6):
- **ReQueue** (`e_InterruptAnim_ReQueue`, `ShouldReQueue`, `initialReQueueDelayFrames` и весь блок
  `:597-613`, `:1535-1553`) — смена клипа только на границе (`e_InterruptAnim_Switch`, `:592-594`).
  Это следующий шаг «отзывчивости» — оригинал перевыбирает клип ~каждые 240 мс.
- **`previousAnim`** и его бухгалтерия — нужен только requeue/smuggle.
- **`CalculatePredictedSituation`/`nextStartPos`** (`:1603-1615`) — потребитель — ИИ/мяч (фаза 4+).
- **Smuggle-механика** (action/movement/rotation-*смещения* из мяча) — все `*Smuggle*`-поля заводятся
  и участвуют в формулах дословно, но остаются нулями до фазы 4. Исключение — `rotationSmuggle`
  begin/end: это часть варпинга, живёт уже сейчас.
- **`decayingPositionOffset`** как живущее поле (`:574-575`) — толкучка игроков; в лабе некому
  толкаться, в `PhysicsVector` входит параметром `decayingPositionOffsetLength` (лаба передаёт 0).
- **MentalImage, командная очередь `RequestCommand`, Put/буферы/temporal smoothing** — другие слои.

## Уроки фаз 1–2, применённые здесь

1. Опорные числа тестов — из сырых `.anim`-ключей и формул C++ (у `movement/walk/045.anim` **четыре**
   ключа root-трека — тест кэша парсит файл сам).
2. Bug-for-bug с комментарием-ссылкой; сомнительное не чинить (`:2108` ballcontrol-вместо-agility,
   `:2026` предупреждение про `incomingSwitchBias`, безымянный дискард `isBaseAnim` `:2072`).
3. Стабильные сортировки — без изменений (фаза 3 сортировок не добавляет).
4. Lite-интеграция `walk_lab` заменяется настоящей — ровно этой фазой.
5. Верх корзины квантования дескрипторов — 7.0 (уже в `BucketVelocity`); `animSprintVelocity` 7.0 —
   отдельная константа для `StretchSprintTo`.

---

### Задача 1: примитивы Vector3 + кэш позиций корня

**Files:**
- Modify: `src/gpf/BluntMath.cs` (добавить `NormalizeMax`, `GetNormalizedTo`, `GetNormalizedMax`)
- Modify: `src/gpf/Velo.cs` (добавить `AnimSprint`)
- Modify: `src/gpf/Animation.cs` (добавить `GetEffectiveFrameCount`, `GetInterpolatedRotation`)
- Modify: `src/gpf/AnimCollection.cs` (кэш позиций корня в `Load`)
- Test: `tests/check_gpf_physics_foundation.gd`

**Interfaces:**
- Consumes: `Animation.SampleRootPosition(int frame, float timeOffsetMs)` (фаза 2),
  `Animation.GetFrameCount()`, приватный `GetInterpolatedValues` (фаза 2).
- Produces (для задач 2–5):
  - `BluntMath`: `Vector3 NormalizeMax(Vector3 v, float length)` (порт `vector3.cpp:199-204`,
    return-стиль), `Vector3 GetNormalizedTo(Vector3 v, float length)` (`:218-223`; 0-вектор у
    оригинала — warning и NaN от деления на 0 — у нас вернуть `v` как есть с комментарием об
    отклонении), `Vector3 GetNormalizedMax(Vector3 v, float length)` (`:225-228`).
  - `Velo.AnimSprint = 7.0f` (`gamedefines.hpp:23`).
  - `Animation`: `int GetEffectiveFrameCount()` (== `GetFrameCount() - 1`, `animation.hpp:83`),
    `Quaternion GetInterpolatedRotation(string nodeName, int frame)` — публичный порт
    ориентационной половины `Animation::GetKeyFrame` (`animation.hpp:85` →
    `GetInterpolatedValues(track, frame)`); позиционная половина уже есть —
    `SampleRootPosition(frame, 0f)` даёт ровно `GetInterpolatedValues(frame)` (bias 0).
  - `AnimCollection`: приватный `List<List<Vector3>> _positionCaches` (заполняется в конце `Load`
    параллельно `_animations`), `internal List<Vector3> GetPositionCacheInternal(int animIndex)`,
    `public int GetPositionCacheCount()`,
    `public static Godot.Collections.Array BuildPositionCache(Animation anim)` — порт цикла
    `match.cpp:97-102`: для `frame` в `0..GetFrameCount()-1` взять `SampleRootPosition(frame, 0f)`,
    занулить Z, сложить в список. `Load` использует ту же логику (internal-вариант
    `BuildPositionCacheInternal`), чтобы тест и рантайм не разошлись.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 3, задача 1: примитивы Vector3 (vector3.cpp:190-228) + кэш позиций корня (match.cpp:86-105).
# Опорные числа кэша — из СЫРЫХ ключей .anim (урок фазы 2), парсим файл сами.

const ANIM_PATH := "res://assets/gpf/animations/movement/walk/045.anim"

func feq(a: float, b: float, eps := 1.0e-5) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-5) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var BM = load("res://src/gpf/BluntMath.cs")
	var V = load("res://src/gpf/Velo.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var A = load("res://src/gpf/Animation.cs")
	if BM == null or V == null or AC == null or A == null:
		print("CHECK FAIL: C#-скрипты не найдены — сначала dotnet build")
		quit(1)
		return

	# --- NormalizeMax (vector3.cpp:199-204): длиннее лимита → обрезать, короче → не трогать ---
	var v: Vector3 = BM.NormalizeMax(Vector3(3, 4, 0), 2.5)
	if not feq(v.length(), 2.5):
		print("CHECK FAIL: NormalizeMax длина ", v.length()); ok = false
	if not vec_eq(v.normalized(), Vector3(0.6, 0.8, 0)):
		print("CHECK FAIL: NormalizeMax сменил направление ", v); ok = false
	v = BM.NormalizeMax(Vector3(1, 0, 0), 2.5)
	if not vec_eq(v, Vector3(1, 0, 0)):
		print("CHECK FAIL: NormalizeMax тронул короткий ", v); ok = false

	# --- GetNormalizedTo (vector3.cpp:218-223): любую длину → ровно length ---
	v = BM.GetNormalizedTo(Vector3(0, -2, 0), 3.49)
	if not vec_eq(v, Vector3(0, -3.49, 0)):
		print("CHECK FAIL: GetNormalizedTo ", v); ok = false

	# --- GetNormalizedMax (vector3.cpp:225-228) ---
	v = BM.GetNormalizedMax(Vector3(0, -0.5, 0), 1.0)
	if not vec_eq(v, Vector3(0, -0.5, 0)):
		print("CHECK FAIL: GetNormalizedMax короткий ", v); ok = false
	v = BM.GetNormalizedMax(Vector3(0, -4, 0), 1.0)
	if not vec_eq(v, Vector3(0, -1, 0)):
		print("CHECK FAIL: GetNormalizedMax длинный ", v); ok = false

	# --- Velo.AnimSprint (gamedefines.hpp:23) ---
	if not feq(V.AnimSprint, 7.0):
		print("CHECK FAIL: AnimSprint = ", V.AnimSprint); ok = false

	# --- GetEffectiveFrameCount (animation.hpp:83) ---
	var anim = A.new()
	if not anim.LoadFromFile(ANIM_PATH):
		print("CHECK FAIL: не загрузился ", ANIM_PATH); ok = false
	if anim.GetEffectiveFrameCount() != anim.GetFrameCount() - 1:
		print("CHECK FAIL: GetEffectiveFrameCount"); ok = false

	# --- Кэш позиций: сверка с сырыми ключами player-строки файла ---
	# Формат CSV (порт-gameplayfootball.md): строка 0 = "player,frame,x,y,z,frame,x,y,z,...",
	# строка 1 = "body,frame,qx,qy,qz,qw,..."
	var f := FileAccess.open(ANIM_PATH, FileAccess.READ)
	var tokens := f.get_line().split(",")
	var body_tokens := f.get_line().split(",")
	if tokens[0] != "player" or body_tokens[0] != "body":
		print("CHECK FAIL: неожиданный порядок треков в файле"); ok = false
	var raw_keys: Array = []  # [ [frame, Vector3], ... ]
	var k := 1
	while k + 3 < tokens.size():
		raw_keys.append([int(tokens[k]), Vector3(
			float(tokens[k + 1]), float(tokens[k + 2]), float(tokens[k + 3]))])
		k += 4

	# --- GetInterpolatedRotation: на сыром ключе body == сам ключ (урок 1: ожидание из файла) ---
	# ВНИМАНИЕ: LoadFromFile мутирует клип (ConvertToStartFacingForwardIfIdle — только idle-вход;
	# walk/045 не idle, body-ключи не тронуты; Mirror здесь не зовётся).
	var body_f0 := int(body_tokens[1])
	var body_q0 := Quaternion(float(body_tokens[2]), float(body_tokens[3]),
		float(body_tokens[4]), float(body_tokens[5]))
	var q_int: Quaternion = anim.GetInterpolatedRotation("body", body_f0)
	if not (q_int.is_equal_approx(body_q0) or q_int.is_equal_approx(-body_q0)):
		print("CHECK FAIL: GetInterpolatedRotation на ключе ", q_int, " != ", body_q0); ok = false
	if raw_keys.size() != 4:
		print("CHECK FAIL: у walk/045 ожидалось 4 root-ключа, найдено ", raw_keys.size()); ok = false

	var cache: Array = AC.BuildPositionCache(anim)
	if cache.size() != anim.GetFrameCount():
		print("CHECK FAIL: размер кэша ", cache.size(), " != frameCount ", anim.GetFrameCount()); ok = false
	# на каждом сыром ключе кэш равен ключу с занулённым Z (match.cpp:99)
	for rk in raw_keys:
		var frame: int = rk[0]
		var pos: Vector3 = rk[1]
		var cached: Vector3 = cache[frame]
		if not vec_eq(cached, Vector3(pos.x, pos.y, 0.0)):
			print("CHECK FAIL: кэш[", frame, "] = ", cached, " != ", Vector3(pos.x, pos.y, 0)); ok = false
	# между ключами — lerp (animation.cpp:186-232): середина между ключами 1 и 2
	var fa: int = raw_keys[1][0]
	var fb: int = raw_keys[2][0]
	if fb - fa >= 2:
		var mid_frame: int = fa + (fb - fa) / 2
		var bias: float = float(mid_frame - fa) / float(fb - fa)
		var expected: Vector3 = raw_keys[1][1] * (1.0 - bias) + raw_keys[2][1] * bias
		expected.z = 0.0
		var got: Vector3 = cache[mid_frame]
		if not vec_eq(got, expected, 1.0e-4):
			print("CHECK FAIL: кэш между ключами ", got, " != ", expected); ok = false

	# кэш в коллекции: по списку на каждый клип (после Load)
	# (лёгкая проверка без полной загрузки не существует — грузим коллекцию один раз)
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var collection = AC.new()
	collection.Load("res://assets/gpf/animations", skel)
	if collection.GetPositionCacheCount() != collection.GetAnimationCount():
		print("CHECK FAIL: кэшей ", collection.GetPositionCacheCount(),
			" != клипов ", collection.GetAnimationCount()); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: прогнать тест — убедиться, что падает**

```powershell
dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_gpf_physics_foundation.gd"
```

Ожидание: FAIL (нет `NormalizeMax`/`AnimSprint`/`BuildPositionCache` — вероятно, parse error моста —
это и есть «падает»).

- [ ] **Шаг 3: минимальная реализация**

В `BluntMath.cs` (рядом с `GetNormalized`):

```csharp
        // vector3.cpp:199-204 — обрезать длину сверху; направление не трогать
        public static Vector3 NormalizeMax(Vector3 v, float length)
        {
            if (v.Length() > length) return GetNormalized(v, Vector3.Zero) * length;
            return v;
        }

        // vector3.cpp:218-223. Оригинал на 0-векторе пишет warning и делит на 0 (NaN);
        // у нас 0-вектор возвращается как есть — вызывающие места фазы 3 гарантируют не-0.
        public static Vector3 GetNormalizedTo(Vector3 v, float length)
        {
            if (v.Length() < 1e-6f) return v;
            return GetNormalized(v, Vector3.Zero) * length;
        }

        // vector3.cpp:225-228
        public static Vector3 GetNormalizedMax(Vector3 v, float length)
        {
            if (v.Length() > length) return GetNormalized(v, Vector3.Zero) * length;
            return v;
        }
```

В `Velo.cs` после `Sprint`:

```csharp
        public const float AnimSprint = 7.0f;          // gamedefines.hpp:23 (animSprintVelocity)
```

В `Animation.cs` рядом с `GetFrameCount`:

```csharp
        public int GetEffectiveFrameCount() => GetFrameCount() - 1; // animation.hpp:83
```

и рядом с `SampleRotation`:

```csharp
        // Ориентационная половина Animation::GetKeyFrame (animation.hpp:85):
        // интерполированное значение НА кадре, без субкадрового смещения.
        public Quaternion GetInterpolatedRotation(string nodeName, int frame)
        {
            var track = FindTrack(nodeName);
            if (track == null)
            {
                GD.PushError($"Gpf.Animation: нет трека {nodeName}");
                return Quaternion.Identity;
            }
            GetInterpolatedValues(track.Keys, frame, out var q, out _);
            return q;
        }
```

В `AnimCollection.cs` — поле, заполнение в конце `Load` (после того как коллекция окончательно
собрана и `PrepareAnim` отработал по всем клипам), аксессоры:

```csharp
        // Кэш позиций корня per-клип — порт Match::Match (match.cpp:86-105):
        // позиция player-трека на каждом кадре, Z занулён. Оригинал держит его в Match;
        // у нас живёт при коллекции — единственном владельце клипов.
        private readonly List<List<Vector3>> _positionCaches = new();

        internal List<Vector3> GetPositionCacheInternal(int animIndex) => _positionCaches[animIndex];
        public int GetPositionCacheCount() => _positionCaches.Count;

        internal static List<Vector3> BuildPositionCacheInternal(Animation anim)
        {
            var positions = new List<Vector3>();
            for (int frame = 0; frame < anim.GetFrameCount(); frame++) // match.cpp:97
            {
                Vector3 position = anim.SampleRootPosition(frame, 0f);  // == GetKeyFrame position
                position.Z = 0.0f;                                      // match.cpp:99
                positions.Add(position);
            }
            return positions;
        }

        public static Godot.Collections.Array BuildPositionCache(Animation anim)
        {
            var result = new Godot.Collections.Array();
            foreach (Vector3 p in BuildPositionCacheInternal(anim)) result.Add(p);
            return result;
        }
```

В конце `Load` (после заполнения `_animations` и перед `return`/финальным логом):

```csharp
            _positionCaches.Clear();
            foreach (Animation a in _animations) _positionCaches.Add(BuildPositionCacheInternal(a));
```

- [ ] **Шаг 4: прогнать тест — PASS; затем полный набор `check_gpf_*`**

```powershell
dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"
& "<godot exe>" --path "<repo>" --headless -s "res://tests/check_gpf_physics_foundation.gd"
```

Ожидание: PASS. Затем все 13 существующих `check_gpf_*.gd` — без регрессий (загрузка коллекции стала
чуть дольше из-за кэша — это нормально).

- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/BluntMath.cs src/gpf/Velo.cs src/gpf/Animation.cs src/gpf/AnimCollection.cs tests/check_gpf_physics_foundation.gd tests/check_gpf_physics_foundation.gd.uid
git commit -m "feat(gpf): примитивы Vector3, AnimSprint, кэш позиций корня (фаза 3, задача 1)"
```

---

### Задача 2: хелперы физики — CalculateMovementAtFrame, StretchSprintTo, GetMaxVelocity

**Files:**
- Create: `src/gpf/PhysicsVector.cs` (пока только статики)
- Test: `tests/check_gpf_physics_helpers.gd`

**Interfaces:**
- Consumes: `Velo.WalkSprintSwitch`, `BluntMath.Get2D` (фаза 2).
- Produces (для задач 3–4):
  - `internal static Vector3 PhysicsVector.CalculateMovementAtFrame(List<Vector3> positions, int frameNum, int smoothFrames)` — порт `humanoid_utils.cpp:68-100`;
  - `public static Vector3 PhysicsVector.CalculateMovementAtFrameArr(Godot.Collections.Array positions, int frameNum, int smoothFrames)` — мост для тестов;
  - `public static float PhysicsVector.StretchSprintTo(float inputVelocity, float inputSpaceMaxVelocity, float targetMaxVelocity)` — порт `humanoid_utils.cpp:129-144`;
  - `public static float PhysicsVector.GetMaxVelocity(float statVelocity)` — порт
    `playerbase.cpp:131-139`: `Velo.Sprint * (0.9f + statVelocity * 0.1f)`.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 3, задача 2: хелперы физики (humanoid_utils.cpp:68-100,129-144; playerbase.cpp:131-139).
# Все ожидания перевычислены из формул C++ прямо здесь.

func feq(a: float, b: float, eps := 1.0e-5) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-5) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var PV = load("res://src/gpf/PhysicsVector.cs")
	if PV == null:
		print("CHECK FAIL: PhysicsVector.cs не найден — сначала dotnet build")
		quit(1)
		return

	# --- CalculateMovementAtFrame (humanoid_utils.cpp:68-100) ---
	# синтетические позиции: дельты 0.05 / 0.10 / 0.15 м за кадр (×100 → м/с)
	var poss: Array = [Vector3(0, 0, 0), Vector3(0, -0.05, 0), Vector3(0, -0.15, 0), Vector3(0, -0.30, 0)]
	# кадр 0 — спецслучай (:83-85): (p1-p0)*100
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 0, 1), Vector3(0, -5, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame кадр 0"); ok = false
	# последний кадр — спецслучай (:79-81): (p3-p2)*100, БЕЗ сглаживания
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 3, 1), Vector3(0, -15, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame последний кадр"); ok = false
	# кадр 1, smooth=1 (:87-97): среднее дельт кадров 1 и 2 = ((p1-p0)+(p2-p1))/2*100
	# внимание: цикл берёт frame in [frameNum-1 .. frameNum+1] с условием frame > 0,
	# т.е. дельту (p0→p1) НЕ отбрасывает (frame=1 > 0), а frame=0 отбрасывает.
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 1, 1), Vector3(0, -7.5, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame кадр 1 сглаживание → ",
			PV.CalculateMovementAtFrameArr(poss, 1, 1)); ok = false
	# кадр 2, smooth=1: среднее трёх дельт (кадры 1,2,3) = (5+10+15)/3 = 10
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 2, 1), Vector3(0, -10, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame кадр 2"); ok = false
	# smooth=0 на внутреннем кадре: одна дельта (p1→p2)*100
	if not vec_eq(PV.CalculateMovementAtFrameArr(poss, 2, 0), Vector3(0, -10, 0)):
		print("CHECK FAIL: CalculateMovementAtFrame smooth=0"); ok = false

	# --- StretchSprintTo (humanoid_utils.cpp:129-144) ---
	# ниже walkSprintSwitch (6.0) — без изменений
	if not feq(PV.StretchSprintTo(5.0, 7.0, 8.0), 5.0):
		print("CHECK FAIL: StretchSprintTo ниже порога"); ok = false
	# формула: 6 + (v-6) * (target-6)/(inputMax-6);  7.0: 6+1*(2/1)=8.0
	if not feq(PV.StretchSprintTo(7.0, 7.0, 8.0), 8.0):
		print("CHECK FAIL: StretchSprintTo(7,7,8) → ", PV.StretchSprintTo(7.0, 7.0, 8.0)); ok = false
	# 6.5: 6+0.5*2=7.0
	if not feq(PV.StretchSprintTo(6.5, 7.0, 8.0), 7.0):
		print("CHECK FAIL: StretchSprintTo(6.5,7,8)"); ok = false
	# ровно на пороге: 6+0*x=6
	if not feq(PV.StretchSprintTo(6.0, 7.0, 8.0), 6.0):
		print("CHECK FAIL: StretchSprintTo(6,7,8)"); ok = false

	# --- GetMaxVelocity (playerbase.cpp:131-139): sprint * (0.9 + stat*0.1) ---
	if not feq(PV.GetMaxVelocity(1.0), 8.8):
		print("CHECK FAIL: GetMaxVelocity(1)"); ok = false
	if not feq(PV.GetMaxVelocity(0.0), 7.2):
		print("CHECK FAIL: GetMaxVelocity(0)"); ok = false
	if not feq(PV.GetMaxVelocity(0.6), 8.0 * 0.96):
		print("CHECK FAIL: GetMaxVelocity(0.6)"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: прогнать — падает** (нет `PhysicsVector.cs`). Не забыть `--import` для `.uid`.

- [ ] **Шаг 3: реализация**

```csharp
using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // Порт варпинга траектории HumanoidBase::CalculatePhysicsVector (humanoidbase.cpp:2014-2544)
    // и его хелперов (humanoid_utils.cpp:68-100,129-144; playerbase.cpp:131-139).
    // Задача 2 — только статики; ядро Calculate приходит задачей 3.
    public partial class PhysicsVector : RefCounted
    {
        // humanoid_utils.cpp:68-100. Движение (м/с) в кадре frameNum по кэшу позиций корня.
        internal static Vector3 CalculateMovementAtFrame(List<Vector3> positions, int frameNum, int smoothFrames)
        {
            // :79-81 — выходное движение без сглаживания (иначе неверная квантованная скорость)
            if (frameNum >= positions.Count - 1)
                return BluntMath.Get2D(positions[positions.Count - 1] - positions[positions.Count - 2]) * 100.0f;
            // :83-85 — для кадра 0 берём дельту 0→1
            if (frameNum == 0)
                return BluntMath.Get2D(positions[1] - positions[0]) * 100.0f;

            Vector3 totalMovement = Vector3.Zero;                    // :87-97
            int count = 0;
            for (int frame = frameNum - smoothFrames; frame <= frameNum + smoothFrames; frame++)
            {
                if (frame > 0 && frame < positions.Count) // (был баг frame > 1 — уже исправлен автором)
                {
                    totalMovement += BluntMath.Get2D(positions[frame] - positions[frame - 1]) * 100.0f;
                    count++;
                }
            }
            if (count > 0) totalMovement /= count;
            return totalMovement;
        }

        // Мост для тестов
        public static Vector3 CalculateMovementAtFrameArr(Godot.Collections.Array positions, int frameNum, int smoothFrames)
        {
            var list = new List<Vector3>();
            foreach (var p in positions) list.Add((Vector3)p);
            return CalculateMovementAtFrame(list, frameNum, smoothFrames);
        }

        // humanoid_utils.cpp:129-144 — растянуть спринтовую часть скорости под max игрока
        public static float StretchSprintTo(float inputVelocity, float inputSpaceMaxVelocity, float targetMaxVelocity)
        {
            if (inputVelocity < Velo.WalkSprintSwitch) return inputVelocity;
            float howMuchSprintage = inputVelocity - Velo.WalkSprintSwitch;
            float oldLength = inputSpaceMaxVelocity - Velo.WalkSprintSwitch;
            float newLength = targetMaxVelocity - Velo.WalkSprintSwitch;
            float toNewFactor = newLength / oldLength;
            return Velo.WalkSprintSwitch + howMuchSprintage * toNewFactor;
        }

        // playerbase.cpp:131-139: GetMaxVelocity = sprintVelocity * GetVelocityMultiplier
        public static float GetMaxVelocity(float statVelocity)
            => Velo.Sprint * (0.9f + statVelocity * 0.1f);
    }
}
```

Примечание к порту: у оригинала `frameNum >= positions.Count - 1` записан как
`frameNum == positions.size() - 1` под защитой `assert(frameNum < positions.size())` (`:76`) —
у нас `>=` вместо assert, поведение на легальном диапазоне идентично; отклонение задокументировать
комментарием на месте.

- [ ] **Шаг 4: прогнать — PASS**, `dotnet build` чист.

- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/PhysicsVector.cs tests/check_gpf_physics_helpers.gd tests/check_gpf_physics_helpers.gd.uid
git commit -m "feat(gpf): CalculateMovementAtFrame + StretchSprintTo + GetMaxVelocity (фаза 3, задача 2)"
```

---

### Задача 3: SpatialState + порт CalculatePhysicsVector (сердце фазы)

**Files:**
- Create: `src/gpf/SpatialState.cs`
- Modify: `src/gpf/PhysicsVector.cs` (ядро `Calculate` + мост)
- Test: `tests/check_gpf_physics_vector.gd`

**Interfaces:**
- Consumes: задачи 1–2 (`NormalizeMax`/`GetNormalizedTo`/`GetNormalizedMax`, `Velo.AnimSprint`,
  `GetEffectiveFrameCount`, `GetPositionCacheInternal`, `CalculateMovementAtFrame`,
  `StretchSprintTo`, `GetMaxVelocity`), дескрипторы `Animation` фазы 2, `BluntMath`, `Velo`.
- Produces (для задач 4–5):
  - `public class Gpf.SpatialState` — порт `humanoidbase.hpp:172-194` (все поля публичные):
    `Vector3 Position; float Angle; Vector3 DirectionVec; int EnumVelocity; float FloatVelocity;
    Vector3 ActualMovement, PhysicsMovement, AnimMovement, Movement;
    Vector3 ActionSmuggleMovement, MovementSmuggleMovement, PositionOffsetMovement;
    float BodyAngle; Vector3 BodyDirectionVec; float RelBodyAngleNonquantized, RelBodyAngle;
    Vector3 RelBodyDirectionVec, RelBodyDirectionVecNonquantized; int Foot;`
    дефолты конструктора `humanoidbase.hpp:113-126`: `DirectionVec=(0,-1,0)`, `Foot=Animation.FootLeft`,
    остальные нули/idle; направления-«вперёд» — `(0,-1,0)`.
  - `PhysicsVector` (инстанс, мост-дружелюбно):
    - `void SetSpatialState(Vector3 position, float angle, Vector3 directionVec, float floatVelocity, Vector3 movement)`
    - `void SetStats(float agility, float acceleration, float velocity, float dribble, float ballControl, float balance)` — дефолты всех 0.6
    - `void SetConfigFactors(float agilityFactor, float accelerationFactor)` — дефолты 0.5/0.5 (`gamedefines.hpp:43-44`)
    - `void SetTouchContext(float lastTouchBias, float decayingPositionOffsetLength)` — дефолты 0/0 (лаба)
    - `internal Vector3 Calculate(Animation anim, List<Vector3> origPositionCache, bool useDesiredMovement, Vector3 desiredMovement, bool useDesiredBodyDirection, Vector3 desiredBodyDirectionRel, List<Vector3> positionsRet, out float rotationOffsetRet)`
    - мост: `public Vector3 CalculateForAnim(AnimCollection anims, int animIndex, bool useDesiredMovement, Vector3 desiredMovement, bool useDesiredBodyDirection, Vector3 desiredBodyDirectionRel)` (внутри зовёт `Calculate` с кэшем коллекции, складывает выходы),
      `public Godot.Collections.Array GetLastPositions()`, `public float GetLastRotationOffset()`.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 3, задача 3: порт CalculatePhysicsVector (humanoidbase.cpp:2014-2544).
# Ожидания — инварианты, выведенные из формул C++, и перевычисления формул на выходах.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

# первый клип по предикату (детерминированный скан)
func find_anim(c, type: String, in_vel: int, out_vel: int, max_out_angle: float) -> int:
	for i in c.GetAnimationCount():
		var a = c.GetAnim(i)
		if a.GetAnimType() != type: continue
		var V = load("res://src/gpf/Velo.cs")
		if V.FloatToEnumVelocity(a.GetIncomingVelocity()) != in_vel: continue
		if V.FloatToEnumVelocity(a.GetOutgoingVelocity()) != out_vel: continue
		if absf(a.GetOutgoingAngle()) > max_out_angle: continue
		if absf(a.GetIncomingBodyAngle()) > 0.06 * PI: continue
		return i
	return -1

func _initialize() -> void:
	var ok := true
	var V = load("res://src/gpf/Velo.cs")
	var BM = load("res://src/gpf/BluntMath.cs")
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var PV = load("res://src/gpf/PhysicsVector.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)

	var fwd := Vector3(0, -1, 0)

	# ---------- 1. Детерминизм + структура на прямом walk-клипе ----------
	var walk_id: int = find_anim(c, "movement", 2, 2, 0.06 * PI)
	if walk_id < 0:
		print("CHECK FAIL: прямой walk-клип не найден"); ok = false
	var walk_anim = c.GetAnim(walk_id)
	var in_vel: float = V.RangeVelocity(walk_anim.GetIncomingVelocity())

	var pv = PV.new()
	pv.SetStats(0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
	pv.SetConfigFactors(0.5, 0.5)
	pv.SetTouchContext(0.0, 0.0)
	pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, in_vel, fwd * in_vel)
	var res1: Vector3 = pv.CalculateForAnim(c, walk_id, true, fwd * 5.0, true, fwd)
	var poss1: Array = pv.GetLastPositions()
	var rot1: float = pv.GetLastRotationOffset()
	var res2: Vector3 = pv.CalculateForAnim(c, walk_id, true, fwd * 5.0, true, fwd)
	var poss2: Array = pv.GetLastPositions()
	if res1 != res2 or poss1.size() != poss2.size() or rot1 != pv.GetLastRotationOffset():
		print("CHECK FAIL: недетерминизм"); ok = false
	for i in poss1.size():
		if poss1[i] != poss2[i]:
			print("CHECK FAIL: недетерминизм позиций, кадр ", i); ok = false
			break

	# размер: цикл :2206 шагом 10 мс кладёт точку каждый виток → ровно frameCount точек
	if poss1.size() != walk_anim.GetFrameCount():
		print("CHECK FAIL: позиций ", poss1.size(), " != frameCount ", walk_anim.GetFrameCount()); ok = false
	for i in poss1.size():
		var p: Vector3 = poss1[i]
		if p.z != 0.0:
			print("CHECK FAIL: Z != 0 в кадре ", i); ok = false
			break
	# прямой клип и прямое желание → путь уходит в -Y
	var last_p: Vector3 = poss1[poss1.size() - 1]
	if last_p.y >= -0.1:
		print("CHECK FAIL: прямой walk не уехал вперёд: ", last_p); ok = false

	# выходная idle-ность совпадает с клипом (:2459-2473, hard quantize)
	if V.FloatToEnumVelocity(res1.length()) == 0:
		print("CHECK FAIL: walk-клип дал idle-выход"); ok = false

	# rotationOffset (:2499-2503): для не-idle выхода — перевычисляем формулу на выходах
	var expected_rot: float = BM.GetAngle2D(BM.GetRotated2D(res1, -0.0), walk_anim.GetOutgoingMovement())
	if not feq(rot1, expected_rot):
		print("CHECK FAIL: rotationOffset ", rot1, " != формула ", expected_rot); ok = false

	# ---------- 2. Idle-клип: желание «стоять» → idle-выход, rotationOffset по формуле ----------
	var idle_id: int = c.GetIdleMovementAnimID()
	var idle_anim = c.GetAnim(idle_id)
	pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, 0.0, Vector3.ZERO)
	var res_idle: Vector3 = pv.CalculateForAnim(c, idle_id, true, Vector3.ZERO, true, fwd)
	if V.FloatToEnumVelocity(res_idle.length()) != 0:
		print("CHECK FAIL: idle-клип дал не-idle выход: ", res_idle.length()); ok = false
	# idle-выход → rotationOffset = toDesiredAngle_capped * physicsBias (:2502); перевычисляем:
	# desired idle → desiredVector = bodyDirRel (fwd); anim-выход idle → animOutgoingVector =
	# GetOutgoingDirection() (:2156); клип «прямо» (|animChange| <= 0.06π) → straight-кап 0.125π;
	# physicsBias movement = 1.0
	var out_dir: Vector3 = idle_anim.GetOutgoingDirection()
	var to_desired: float = BM.GetAngle2D(fwd, out_dir)
	var expected_idle_rot: float = 0.0
	if absf(to_desired) <= 0.5 * PI:
		var anim_change: float = BM.GetAngle2D(out_dir, fwd)
		if absf(anim_change) > 0.06 * PI:
			# сторона совпала/нет — оба капа тут 0.125π, ветвление не влияет (:2163-2169)
			expected_idle_rot = clampf(to_desired, -0.125 * PI, 0.125 * PI)
		else:
			expected_idle_rot = clampf(to_desired, -0.125 * PI, 0.125 * PI)
	if not feq(pv.GetLastRotationOffset(), expected_idle_rot, 1.0e-4):
		print("CHECK FAIL: rotationOffset idle ", pv.GetLastRotationOffset(),
			" != формула ", expected_idle_rot); ok = false

	# ---------- 3. Поворот: желание -45° тянет выход к желаемому ----------
	var right45: Vector3 = BM.GetRotated2D(fwd, -0.25 * PI)
	pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, in_vel, fwd * in_vel)
	var res_turn: Vector3 = pv.CalculateForAnim(c, walk_id, true, right45 * 5.0, true, right45)
	var angle_before: float = absf(BM.GetAngle2D(
		BM.GetNormalized(walk_anim.GetOutgoingMovement(), fwd), right45))
	var angle_after: float = absf(BM.GetAngle2D(BM.GetNormalized(res_turn, fwd), right45))
	if angle_after >= angle_before - 0.01:
		print("CHECK FAIL: поворот не притянул выход: до ", angle_before, " после ", angle_after); ok = false

	# ---------- 4. Стат velocity растягивает спринт ----------
	var sprint_id: int = find_anim(c, "movement", 3, 3, 0.06 * PI)
	if sprint_id < 0:
		print("CHECK FAIL: прямой sprint-клип не найден"); ok = false
	else:
		var sprint_anim = c.GetAnim(sprint_id)
		var sprint_in: float = V.RangeVelocity(sprint_anim.GetIncomingVelocity())
		pv.SetStats(0.6, 0.6, 1.0, 0.6, 0.6, 0.6)
		pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, sprint_in, fwd * sprint_in)
		var res_fast: Vector3 = pv.CalculateForAnim(c, sprint_id, true, fwd * 8.0, true, fwd)
		pv.SetStats(0.6, 0.6, 0.3, 0.6, 0.6, 0.6)
		pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, sprint_in, fwd * sprint_in)
		var res_slow: Vector3 = pv.CalculateForAnim(c, sprint_id, true, fwd * 8.0, true, fwd)
		if res_fast.length() < res_slow.length() - 1.0e-4:
			print("CHECK FAIL: stat_velocity 1.0 медленнее 0.3: ",
				res_fast.length(), " < ", res_slow.length()); ok = false

	# ---------- 5. Ловкость помогает доворачивать ----------
	var right90: Vector3 = BM.GetRotated2D(fwd, -0.5 * PI)
	pv.SetStats(1.0, 0.6, 0.6, 0.6, 0.6, 0.6)
	pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, in_vel, fwd * in_vel)
	var res_agile: Vector3 = pv.CalculateForAnim(c, walk_id, true, right90 * 5.0, true, right90)
	pv.SetStats(0.0, 0.6, 0.6, 0.6, 0.6, 0.6)
	pv.SetSpatialState(Vector3.ZERO, 0.0, fwd, in_vel, fwd * in_vel)
	var res_stiff: Vector3 = pv.CalculateForAnim(c, walk_id, true, right90 * 5.0, true, right90)
	var d_agile: float = absf(BM.GetAngle2D(BM.GetNormalized(res_agile, fwd), right90))
	var d_stiff: float = absf(BM.GetAngle2D(BM.GetNormalized(res_stiff, fwd), right90))
	if d_agile > d_stiff + 1.0e-4:
		print("CHECK FAIL: agility 1.0 довернула хуже 0.0: ", d_agile, " vs ", d_stiff); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: прогнать — падает** (нет `Calculate`). `--import` для `.uid`.

- [ ] **Шаг 3: реализация — порт :2014-2544 целиком**

`src/gpf/SpatialState.cs`:

```csharp
using Godot;

namespace Gpf
{
    // Порт struct SpatialState (humanoidbase.hpp:172-194) + дефолты ctor (:113-126).
    // Обычный C#-класс: через мост не ходит, наружу его отдаёт HumanoidBase геттерами.
    public class SpatialState
    {
        public Vector3 Position = Vector3.Zero;
        public float Angle = 0f;
        public Vector3 DirectionVec = new Vector3(0, -1, 0); // векторная версия Angle
        public int EnumVelocity = Velo.IdVelIdle;
        public float FloatVelocity = 0f;

        public Vector3 ActualMovement = Vector3.Zero;
        public Vector3 PhysicsMovement = Vector3.Zero;  // игнорирует positionoffset-эффекты
        public Vector3 AnimMovement = Vector3.Zero;
        public Vector3 Movement = Vector3.Zero;          // одно из трёх выше (default)
        public Vector3 ActionSmuggleMovement = Vector3.Zero;    // нули до фазы 4
        public Vector3 MovementSmuggleMovement = Vector3.Zero;  // нули до фазы 4
        public Vector3 PositionOffsetMovement = Vector3.Zero;   // нули до фазы 4

        public float BodyAngle = 0f;
        public Vector3 BodyDirectionVec = new Vector3(0, -1, 0);
        public float RelBodyAngleNonquantized = 0f;
        public float RelBodyAngle = 0f;
        public Vector3 RelBodyDirectionVec = new Vector3(0, -1, 0);
        public Vector3 RelBodyDirectionVecNonquantized = new Vector3(0, -1, 0);
        public int Foot = Animation.FootLeft; // humanoidbase.hpp:117
    }
}
```

В `PhysicsVector.cs` — входное состояние + ядро. Ключевые места, где легко ошибиться (проверять на
ревью в первую очередь):

- **:2065 vs :2424 — две разные max-скорости.** Локальная `maxVelocity` после touch умножается на
  0.92; сопротивление воздуха (`:2424`) берёт СВЕЖИЙ `GetMaxVelocity()` без этого множителя.
- **:2229 — усечение кадра.** `GetEffectiveFrameCount() * adaptedFrameBias` кастуется в
  `unsigned int` → в C# `(int)(...)` (усечение вниз, не округление).
- **:2482 — точка каждый виток** (`time_ms % 10 == 0` при шаге 10 всегда истина).
- **:2459/:2478 — «последние два кадра»**: `time_ms >= (frameCount - 2) * 10`.
- **mod-флаги** — `static readonly bool`, мёртвые ветки портируются.
- **`mode` в MaxCornering (:2357)** — локальная `int mode = 1;` (не const — иначе CS0162).

```csharp
        // ---- входное состояние (сеттеры; дефолты — лаба без мяча и толкучки) ----
        private Vector3 _spatialPosition;
        private float _spatialAngle;
        private Vector3 _spatialDirectionVec = new Vector3(0, -1, 0);
        private float _spatialFloatVelocity;
        private Vector3 _spatialMovement;
        private float _statAgility = 0.6f, _statAcceleration = 0.6f, _statVelocity = 0.6f;
        private float _statDribble = 0.6f, _statBallControl = 0.6f, _statBalance = 0.6f;
        private float _agilityFactor = 0.5f;       // gameplay_agilityfactor (gamedefines.hpp:43)
        private float _accelerationFactor = 0.5f;  // gameplay_accelerationfactor (gamedefines.hpp:44)
        private float _lastTouchBias = 0f;                    // player->GetLastTouchBias(1000)
        private float _decayingPositionOffsetLength = 0f;     // decayingPositionOffset.GetLength()

        private readonly List<Vector3> _lastPositions = new();
        private float _lastRotationOffset;

        public void SetSpatialState(Vector3 position, float angle, Vector3 directionVec,
                                    float floatVelocity, Vector3 movement)
        {
            _spatialPosition = position; _spatialAngle = angle; _spatialDirectionVec = directionVec;
            _spatialFloatVelocity = floatVelocity; _spatialMovement = movement;
        }

        public void SetStats(float agility, float acceleration, float velocity,
                             float dribble, float ballControl, float balance)
        {
            _statAgility = agility; _statAcceleration = acceleration; _statVelocity = velocity;
            _statDribble = dribble; _statBallControl = ballControl; _statBalance = balance;
        }

        public void SetConfigFactors(float agilityFactor, float accelerationFactor)
        { _agilityFactor = agilityFactor; _accelerationFactor = accelerationFactor; }

        public void SetTouchContext(float lastTouchBias, float decayingPositionOffsetLength)
        { _lastTouchBias = lastTouchBias; _decayingPositionOffsetLength = decayingPositionOffsetLength; }

        // мост для тестов
        public Vector3 CalculateForAnim(AnimCollection anims, int animIndex,
            bool useDesiredMovement, Vector3 desiredMovement,
            bool useDesiredBodyDirection, Vector3 desiredBodyDirectionRel)
        {
            var result = Calculate(anims.GetAnim(animIndex), anims.GetPositionCacheInternal(animIndex),
                useDesiredMovement, desiredMovement, useDesiredBodyDirection, desiredBodyDirectionRel,
                _lastPositions, out _lastRotationOffset);
            return result;
        }

        public Godot.Collections.Array GetLastPositions()
        {
            var arr = new Godot.Collections.Array();
            foreach (Vector3 p in _lastPositions) arr.Add(p);
            return arr;
        }

        public float GetLastRotationOffset() => _lastRotationOffset;
```

Ядро (полный порт; в реализации сохранить ВСЕ комментарии-ссылки):

```csharp
        // Порт HumanoidBase::CalculatePhysicsVector (humanoidbase.cpp:2014-2544).
        // positionsRet — варпнутая траектория корня (точка на кадр, относительная от старта клипа);
        // rotationOffsetRet — rotationSmuggle.end; возвращает итоговое движение (м/с).
        internal Vector3 Calculate(Animation anim, List<Vector3> origPositionCache,
            bool useDesiredMovement, Vector3 desiredMovement,
            bool useDesiredBodyDirection, Vector3 desiredBodyDirectionRel,
            List<Vector3> positionsRet, out float rotationOffsetRet)
        {
            positionsRet.Clear();                                          // :2016

            int animTouchFrame = BluntMath.AtoI(anim.GetVariable("touchframe")); // :2018
            bool touch = animTouchFrame > 0;

            float statAgility = _statAgility;                              // :2021-2024
            float statAcceleration = _statAcceleration;
            float statDribble = _statDribble;

            float incomingSwitchBias = 0.0f; // :2026 — не-0 даёт непуристичное поведение (ориг.)
            float outgoingSwitchBias = 0.0f;

            string animType = anim.GetAnimType();                          // :2029

            if (animType == "ballcontrol") outgoingSwitchBias = 0.0f;      // :2031-2047
            else if (animType == "trap") outgoingSwitchBias = 0.0f;
            else if (animType == "interfere") outgoingSwitchBias = 0.0f;
            else if (animType == "deflect") outgoingSwitchBias = 1.0f;
            else if (animType == "sliding") outgoingSwitchBias = 0.0f;
            else if (animType == "special") outgoingSwitchBias = 1.0f;
            else if (animType == "trip") outgoingSwitchBias = 0.5f; // направление отчасти предрешено коллизией
            else if (touch) outgoingSwitchBias = 1.0f;

            if (anim.GetVariable("incoming_special_state") != "" ||
                anim.GetVariable("outgoing_special_state") != "") outgoingSwitchBias = 1.0f; // :2049-2050

            Vector3 animIncomingMovement = BluntMath.GetRotated2D(new Vector3(0, -1, 0), _spatialAngle)
                * Velo.RangeVelocity(anim.GetIncomingVelocity());          // :2052
            Vector3 adaptedCurrentMovement = animIncomingMovement * incomingSwitchBias
                + _spatialMovement * (1.0f - incomingSwitchBias);          // :2053

            Vector3 predictedOutgoingMovement =
                BluntMath.GetRotated2D(anim.GetOutgoingMovement(), _spatialAngle); // :2055
            Vector3 velocifiedDesiredMovement =
                useDesiredMovement ? desiredMovement : predictedOutgoingMovement;  // :2056

            Vector3 adaptedDesiredMovement = predictedOutgoingMovement * outgoingSwitchBias
                + velocifiedDesiredMovement * (1.0f - outgoingSwitchBias); // :2060

            float maxVelocity = GetMaxVelocity(_statVelocity);             // :2065
            if (touch) maxVelocity *= 0.92f;                               // :2066

            const int timeStepMs = 10;                                     // :2070

            bool isBaseAnim = anim.GetVariable("baseanim") == "true";      // :2072 (дальше не используется — как в ориг.)
            _ = isBaseAnim;

            float difficultyFactor = BluntMath.AtoF(anim.GetVariable("animdifficultyfactor")); // :2074
            float difficultyPenaltyFactor = Mathf.Pow(                     // :2075-2080
                Mathf.Clamp((difficultyFactor - 0.0f)
                    * (1.0f - (statAgility * 0.2f + statAcceleration * 0.2f)) * 2.0f, 0.0f, 1.0f),
                0.7f);

            // :2082-2084 (todo ориг.: lasttouchbias в цикл, чтобы менялся во времени)
            float powerFactor = 1.0f - Mathf.Clamp(
                Mathf.Pow(_lastTouchBias, 0.8f) * (0.8f - statDribble * 0.3f), 0.0f, 0.4f);
            powerFactor *= 1.0f - Mathf.Clamp(
                _decayingPositionOffsetLength * (10.0f - _statBalance * 5.0f) - 0.1f, 0.0f, 0.3f);

            Vector3 temporalMovement = adaptedCurrentMovement;             // :2088

            Vector3 currentPosition = Vector3.Zero;                        // :2098

            float physicsBias = 1.0f;                                      // :2101
            float maxAngleModUnderAnimAngle = 0.125f * Mathf.Pi;           // :2103-2105
            float maxAngleModOverAnimAngle = 0.125f * Mathf.Pi;
            float maxAngleModStraightAnimAngle = 0.125f * Mathf.Pi;
            if (touch)                                                     // :2106-2112
            {
                float bonus = 1.0f - Mathf.Pow(BluntMath.NormalizedClamp(
                    (adaptedCurrentMovement + predictedOutgoingMovement).Length() * 0.5f,
                    0, Velo.Sprint), 0.8f) * 0.8f;
                bonus *= 0.6f + 0.4f * _statBallControl; // todo ориг.: «shouldn't this be agility?»
                maxAngleModUnderAnimAngle = 0.2f * Mathf.Pi * bonus;
                maxAngleModOverAnimAngle = 0;
                maxAngleModStraightAnimAngle = 0.1f * Mathf.Pi * bonus;
            }
            if (animType == "sliding")                                     // :2113-2117
            {
                maxAngleModUnderAnimAngle = 0.5f * Mathf.Pi;
                maxAngleModOverAnimAngle = 0.5f * Mathf.Pi;
                maxAngleModStraightAnimAngle = 0.5f * Mathf.Pi;
            }

            if (animType == "movement") physicsBias *= 1.0f;               // :2119-2136
            if (animType == "ballcontrol") physicsBias *= 1.0f;
            if (animType == "trap") physicsBias *= 1.0f;
            if (animType == "shortpass") physicsBias *= 0.0f;
            if (animType == "highpass") physicsBias *= 0.0f;
            if (animType == "shot") physicsBias *= 0.0f;
            if (animType == "interfere") physicsBias *= 0.5f;
            if (animType == "deflect") physicsBias *= 0.0f;
            if (animType == "sliding") physicsBias *= 1.0f;
            if (animType == "trip")
            { if (anim.GetVariable("triptype") == "1") physicsBias *= 0.5f; else physicsBias *= 0.0f; }
            if (animType == "special") physicsBias *= 0.0f;
            if (anim.GetVariable("incoming_special_state") != "") physicsBias *= 0.0f;

            // :2138-2146 — readonly, не const: мёртвые ветки должны компилироваться без CS0162
            // (значения — как в оригинале)
            // объявлены полями класса: ModAllowRotation=true, ModCorneringBraking=false,
            // ModPointinessCurve=true, ModMaximumAccelDecel=false, ModBrakeOnTouch=false,
            // ModMaxCornering=true, ModMaxChange=true, ModAirResistance=true, ModCheatBodyDirection=false

            float accelerationMultiplier = 0.5f + _accelerationFactor;     // :2148

            // --- поворот клипа к желаемому углу (:2151-2176) ---
            float toDesiredAngleCapped = 0;
            if (ModAllowRotation && physicsBias > 0.0f)
            {
                Vector3 animOutgoingVector = BluntMath.GetNormalized(predictedOutgoingMovement, Vector3.Zero);
                if (Velo.FloatToEnumVelocity(predictedOutgoingMovement.Length()) == Velo.IdVelIdle)
                    animOutgoingVector = BluntMath.GetRotated2D(anim.GetOutgoingDirection(), _spatialAngle); // :2156
                Vector3 desiredVector = BluntMath.GetNormalized(adaptedDesiredMovement, Vector3.Zero);
                if (Velo.FloatToEnumVelocity(adaptedDesiredMovement.Length()) == Velo.IdVelIdle)
                    desiredVector = BluntMath.GetRotated2D(desiredBodyDirectionRel, _spatialAngle);          // :2158
                float toDesiredAngle = BluntMath.GetAngle2D(desiredVector, animOutgoingVector);              // :2159
                if (Mathf.Abs(toDesiredAngle) <= 0.5f * Mathf.Pi || animType == "sliding")  // :2160 — хотим больше? пропускаем
                {
                    float animChange = BluntMath.GetAngle2D(animOutgoingVector, _spatialDirectionVec); // :2162
                    if (Mathf.Abs(animChange) > 0.06f * Mathf.Pi)
                    {
                        int sign = BluntMath.SignSide(animChange);
                        if (BluntMath.SignSide(toDesiredAngle) == sign)
                            toDesiredAngleCapped = Mathf.Clamp(toDesiredAngle,
                                -maxAngleModOverAnimAngle, maxAngleModOverAnimAngle);
                        else
                            toDesiredAngleCapped = Mathf.Clamp(toDesiredAngle,
                                -maxAngleModUnderAnimAngle, maxAngleModUnderAnimAngle);
                    }
                    else
                    {
                        // клип «прямо» — у него нет стороны (:2170-2173)
                        toDesiredAngleCapped = Mathf.Clamp(toDesiredAngle,
                            -maxAngleModStraightAnimAngle, maxAngleModStraightAnimAngle);
                    }
                }
            }

            float maximumOutgoingVelocity = Velo.Sprint;                   // :2179
            if (ModCorneringBraking)                                       // :2181-2202 — мёртвая ветка
            {
                float brakeBias = 0.8f;
                brakeBias *= touch ? 1.0f : 0.8f;
                brakeBias *= 1.0f - statAgility * 0.2f;
                Vector3 animOutgoingMovementCb = anim.GetOutgoingMovement();
                animOutgoingMovementCb = BluntMath.GetRotated2D(animOutgoingMovementCb, toDesiredAngleCapped);
                brakeBias *= Mathf.Pow(BluntMath.NormalizedClamp(
                    _spatialFloatVelocity, Velo.Idle, Velo.Sprint - 0.5f), 0.8f);
                float maxVelo = Velo.Sprint * ((1.0f - brakeBias)
                    + (1.0f - Mathf.Pow(Mathf.Abs(BluntMath.GetAngle2D(
                        BluntMath.GetNormalized(animOutgoingMovementCb, Vector3.Zero),
                        new Vector3(0, -1, 0)) / Mathf.Pi), 0.5f)) * brakeBias);
                maximumOutgoingVelocity = maxVelo;
            }

            // --- loop da loop (:2206-2493) ---
            for (int timeMs = 0; timeMs < anim.GetFrameCount() * 10; timeMs += timeStepMs)
            {
                // +1: первый кадр тоже под влиянием; финал с bias 1.0 на предпоследнем кадре (:2208-2211)
                float frameBias = (timeMs + 10) / (float)((anim.GetEffectiveFrameCount() + 1) * 10);

                float lagExp = 1.0f;                                       // :2213-2227
                if (ModPointinessCurve && physicsBias > 0.0f
                    && (animType == "ballcontrol" || animType == "movement"))
                {
                    lagExp = 1.4f - _agilityFactor * 0.8f;
                    lagExp *= 1.2f - statAgility * 0.4f;
                    if (touch) lagExp += -0.1f + Mathf.Clamp(difficultyFactor * 0.4f, 0.0f, 0.5f);
                    else lagExp += -0.2f + Mathf.Clamp(difficultyFactor * 0.2f, 0.0f, 0.2f);
                    lagExp = Mathf.Clamp(lagExp, 0.25f, 4.0f);
                    if (touch && timeMs < animTouchFrame * 10) lagExp = Mathf.Max(lagExp, 0.7f); // не «пропустить» мяч
                    lagExp = lagExp * physicsBias + 1.0f * (1.0f - physicsBias);
                }
                float adaptedFrameBias = Mathf.Pow(frameBias, lagExp);     // :2228
                // (unsigned int)-каст оригинала → усечение вниз (:2229)
                Vector3 animMovement = BluntMath.GetRotated2D(
                    CalculateMovementAtFrame(origPositionCache,
                        (int)(anim.GetEffectiveFrameCount() * adaptedFrameBias), 1),
                    _spatialAngle);

                float animVelo = animMovement.Length();                    // :2231-2233
                Vector3 adaptedAnimMovement = animMovement;
                float adaptedAnimVelo = animVelo;

                // спринт клипа → max скорость игрока (:2238-2245)
                if (animVelo > Velo.WalkSprintSwitch
                    && (animType == "movement" || animType == "ballcontrol" || animType == "trap"))
                {
                    if (maxVelocity > animVelo) // только ускоряем: в клипе бывают быстрые куски
                    {
                        adaptedAnimVelo = StretchSprintTo(animVelo, Velo.AnimSprint, maxVelocity);
                        adaptedAnimMovement = BluntMath.GetNormalized(adaptedAnimMovement, Vector3.Zero) * adaptedAnimVelo;
                    }
                }

                float maxSlower = 1.6f;   // :2248 — не свалиться ниже dribble − idleDribbleSwitch
                if (touch) maxSlower = 1.2f;
                float maxFaster = 0.0f;
                if (touch) maxFaster = 0.0f;
                if (temporalMovement.Length() > adaptedAnimVelo)           // :2252 — уже быстрее, ладно
                    maxFaster = Mathf.Min(0.0f + 1.0f * (1.0f - frameBias),
                        Mathf.Max(maxFaster, temporalMovement.Length() - adaptedAnimVelo));
                if (maxFaster > 0)                                         // :2253 — только в нужную сторону
                    maxFaster *= Mathf.Max(0.0f, BluntMath.GetNormalizedMax(adaptedAnimMovement, 1.0f)
                        .Dot(BluntMath.GetNormalized(adaptedDesiredMovement, Vector3.Zero)));
                if (animType == "sliding") maxFaster = 100;                // :2254
                float desiredVelocity = adaptedDesiredMovement.Length();
                adaptedAnimVelo = Mathf.Clamp(desiredVelocity,
                    adaptedAnimVelo - maxSlower, adaptedAnimVelo + maxFaster); // :2256
                adaptedAnimMovement = BluntMath.GetNormalized(adaptedAnimMovement, Vector3.Zero) * adaptedAnimVelo;

                if (ModCorneringBraking)                                   // :2259-2265 — мёртвая ветка
                {
                    float frameBiasedMaximumOutgoingVelocity =
                        Velo.Sprint * (1.0f - frameBias) + maximumOutgoingVelocity * frameBias;
                    if (adaptedAnimVelo > frameBiasedMaximumOutgoingVelocity)
                    {
                        adaptedAnimVelo = frameBiasedMaximumOutgoingVelocity;
                        adaptedAnimMovement = BluntMath.GetNormalized(adaptedAnimMovement, Vector3.Zero) * adaptedAnimVelo;
                    }
                }

                if (ModMaximumAccelDecel)                                  // :2267-2279 — мёртвая ветка
                {
                    float maxAccelMPS = 20.0f;
                    float maxDecelMPS = 20.0f;
                    float currentVelo = temporalMovement.Length();
                    float veloChangeMPS = (adaptedAnimVelo - currentVelo) / (timeStepMs * 0.001f);
                    if (veloChangeMPS < -maxDecelMPS || veloChangeMPS > maxAccelMPS)
                    {
                        adaptedAnimVelo = currentVelo
                            + Mathf.Clamp(veloChangeMPS, -maxDecelMPS, maxAccelMPS) * (timeStepMs * 0.001f);
                        adaptedAnimMovement = BluntMath.GetNormalized(adaptedAnimMovement, Vector3.Zero) * adaptedAnimVelo;
                    }
                }

                Vector3 resultingPhysicsMovement = adaptedAnimMovement;    // :2281
                // угол (:2284)
                resultingPhysicsMovement = BluntMath.GetRotated2D(
                    resultingPhysicsMovement, toDesiredAngleCapped * frameBias);

                // --- насколько остаёмся верны клипу (:2289) ---
                resultingPhysicsMovement = resultingPhysicsMovement * physicsBias
                    + animMovement * (1.0f - physicsBias);

                Vector3 toDesired = resultingPhysicsMovement - temporalMovement; // :2294

                float penaltyBreakFactor = 0.0f;                           // :2303
                if (ModBrakeOnTouch)                                       // :2304-2326 — мёртвая ветка
                {
                    // precalc на touchframe: temporalMovement изменится из-за этого же эффекта
                    int numBrakeFrames = 15;
                    if (touch && timeMs >= animTouchFrame * 10
                        && timeMs < (animTouchFrame + numBrakeFrames) * 10)
                    {
                        int brakeFramesInto = (timeMs - animTouchFrame * 10) / 10;
                        float brakeFrameFactor = Mathf.Pow(1.0f - brakeFramesInto / (float)numBrakeFrames, 0.5f);
                        float touchBrakeFactor = 0.3f;
                        float touchDifficultyFactor = Mathf.Clamp(
                            (difficultyFactor + 0.7f) * (1.0f - statDribble * 0.4f), 0.0f, 1.0f);
                        touchDifficultyFactor *= 1.0f - Mathf.Pow(
                            Mathf.Abs(anim.GetOutgoingAngle()) / Mathf.Pi, 0.75f); // не помогать тормозить к 180°
                        float veloFactorBt = BluntMath.NormalizedClamp(
                            temporalMovement.Length(), Velo.Walk, Velo.Sprint);
                        penaltyBreakFactor = touchDifficultyFactor * veloFactorBt * brakeFrameFactor * touchBrakeFactor;
                    }
                }

                if (ModMaxCornering)                                       // :2341-2370
                {
                    Vector3 predictedMovement = temporalMovement + toDesired;
                    float startVelo = Velo.IdleDribbleSwitch;
                    if (temporalMovement.Length() > startVelo && predictedMovement.Length() > startVelo)
                    {
                        float angle = BluntMath.GetAngle2D(
                            BluntMath.GetNormalized(predictedMovement, Vector3.Zero),
                            BluntMath.GetNormalized(temporalMovement, Vector3.Zero)); // :2345 (длины > 0 гарантированы)
                        float maxAngleFactor = 1.0f * (timeStepMs / 1000.0f);          // :2346
                        maxAngleFactor *= 0.7f + 0.3f * statAgility;
                        if (!touch) maxAngleFactor *= 1.5f;
                        float maxAngle = maxAngleFactor * Mathf.Pi;
                        float veloFactorMc = Mathf.Pow(BluntMath.NormalizedClamp(
                            temporalMovement.Length(), 0, Velo.Sprint), 1.0f);
                        maxAngle /= veloFactorMc + 0.01f;

                        if (Mathf.Abs(angle) > maxAngle)
                        {
                            int mode = 1; // 0: ограничить угол, 1: ограничить скорость (:2357)
                            if (mode == 0)
                            {
                                Vector3 restrictedPredictedMovement = BluntMath.GetRotated2D(
                                    predictedMovement, (Mathf.Abs(angle) - maxAngle) * -BluntMath.SignSide(angle));
                                toDesired = restrictedPredictedMovement - temporalMovement;
                            }
                            else if (mode == 1)
                            {
                                float overAngle = Mathf.Abs(angle) - maxAngle; // > 0
                                toDesired += -temporalMovement * Mathf.Clamp(overAngle / Mathf.Pi * 3.0f, 0.0f, 1.0f);
                            }
                        }
                    }
                }

                if (ModMaxChange)                                          // :2372-2405
                {
                    float maxChange = 0.03f;
                    if (animType == "trip") maxChange *= 0.7f;
                    if (animType == "sliding") maxChange = 0.1f;
                    float veloFactorM = Mathf.Pow(BluntMath.NormalizedClamp(
                        temporalMovement.Length(), 0, Velo.Sprint), 1.5f);
                    float firstStepFactor = veloFactorM;
                    if (animType == "movement") firstStepFactor *= 0.4f;
                    maxChange *= (1.0f - firstStepFactor)
                        + firstStepFactor * BluntMath.Curve(BluntMath.NormalizedClamp(timeMs, 0.0f, 160.0f), 1.0f);
                    maxChange *= 1.2f - veloFactorM * 0.4f;
                    maxChange *= 0.75f + _agilityFactor * 0.5f;            // :2387
                    maxChange *= powerFactor;                              // :2399

                    float desiredLength = toDesired.Length();              // :2401-2404
                    float maxAddition = maxChange * timeStepMs;
                    toDesired = BluntMath.NormalizeMax(toDesired, Mathf.Min(desiredLength, maxAddition));
                }

                // --- сопротивление воздуха (:2410-2451) ---
                if (ModAirResistance && animType != "sliding" && animType != "deflect")
                {
                    float veloExp = 1.8f;
                    float accelPower = 11.0f * accelerationMultiplier;
                    float falloffStartVelo = Velo.IdleDribbleSwitch;

                    if ((temporalMovement + toDesired).Length() > falloffStartVelo)
                    {
                        accelPower *= 1.0f - difficultyPenaltyFactor * 0.4f; // тяжёлые клипы — слабее

                        // ВНИМАНИЕ: :2424 берёт СВЕЖИЙ GetMaxVelocity() (без touch-множителя 0.92!)
                        float veloAirResistanceFactor = Mathf.Clamp(
                            Mathf.Pow(Mathf.Clamp((temporalMovement.Length() - falloffStartVelo)
                                / (GetMaxVelocity(_statVelocity) - falloffStartVelo), 0.0f, 1.0f),
                                veloExp), 0.0f, 1.0f);

                        // круговая версия (:2432-2439)
                        Vector3 forwardVector = Vector3.Zero;
                        if ((temporalMovement + toDesired).Length() > temporalMovement.Length()) // вне «круга скорости»
                        {
                            Vector3 destination = temporalMovement + toDesired;
                            float velo = temporalMovement.Length();
                            float accel = destination.Length() - velo;
                            forwardVector = BluntMath.GetNormalized(destination, Vector3.Zero) * accel;
                        }

                        float accelerationAddition = forwardVector.Length();
                        float maxAccelerationMPS = accelPower * (1.0f - veloAirResistanceFactor)
                            * (statAcceleration * 0.3f + 0.7f);            // :2442
                        float maxAccelerationAddition = maxAccelerationMPS * (timeStepMs / 1000.0f);
                        if (accelerationAddition > maxAccelerationAddition)
                        {
                            float remainingFactor = maxAccelerationAddition / accelerationAddition;
                            toDesired -= forwardVector * (1.0f - remainingFactor);
                        }
                    }
                }

                // MAKE IT SEW! (:2454)
                Vector3 tmpTemporalMovement = temporalMovement + toDesired;

                // выходная скорость той же idle-ности, что клип (:2459-2473)
                if (timeMs >= (anim.GetFrameCount() - 2) * 10)
                {
                    bool hardQuantize = true;                              // :2461
                    if (!hardQuantize && anim.GetVariable("outgoing_special_state") != "") hardQuantize = true;

                    if (!hardQuantize)
                    {
                        // мягкая версия (:2464-2467) — мёртвая ветка
                        if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) == Velo.IdVelIdle
                            && Velo.FloatToEnumVelocity(tmpTemporalMovement.Length()) != Velo.IdVelIdle)
                            tmpTemporalMovement = BluntMath.GetNormalizedTo(
                                tmpTemporalMovement, Velo.IdleDribbleSwitch - 0.01f);
                        else if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) != Velo.IdVelIdle
                            && Velo.FloatToEnumVelocity(tmpTemporalMovement.Length()) == Velo.IdVelIdle)
                            tmpTemporalMovement = BluntMath.GetNormalizedTo(
                                BluntMath.GetRotated2D(anim.GetOutgoingMovement(), _spatialAngle),
                                Velo.IdleDribbleSwitch + 0.01f);
                    }
                    else
                    {
                        // жёсткая версия (:2469-2471)
                        if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) == Velo.IdVelIdle
                            && Velo.FloatToEnumVelocity(tmpTemporalMovement.Length()) != Velo.IdVelIdle)
                            tmpTemporalMovement = Vector3.Zero;
                        else if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) != Velo.IdVelIdle
                            && Velo.FloatToEnumVelocity(tmpTemporalMovement.Length()) == Velo.IdVelIdle)
                            tmpTemporalMovement = BluntMath.GetNormalizedTo(
                                BluntMath.GetRotated2D(anim.GetOutgoingMovement(), _spatialAngle),
                                Velo.Dribble);
                    }
                }

                temporalMovement = tmpTemporalMovement;                    // :2476

                if (timeMs >= (anim.GetFrameCount() - 2) * 10) penaltyBreakFactor = 0.0f; // :2478
                currentPosition += temporalMovement * (1.0f - penaltyBreakFactor)
                    * (timeStepMs / 1000.0f);                              // :2479

                if (timeMs % 10 == 0) positionsRet.Add(currentPosition);   // :2482-2484 (шаг 10 → каждый виток)
            }

            Vector3 resultingMovement = temporalMovement;                  // :2496

            if (Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) != Velo.IdVelIdle
                && Velo.FloatToEnumVelocity(resultingMovement.Length()) != Velo.IdVelIdle)
                rotationOffsetRet = BluntMath.GetAngle2D(
                    BluntMath.GetRotated2D(resultingMovement, -_spatialAngle),
                    anim.GetOutgoingMovement());                           // :2499-2500
            else
                rotationOffsetRet = toDesiredAngleCapped * physicsBias;    // :2502

            // body direction assist (:2507-2539) — мёртвая ветка (ModCheatBodyDirection=false)
            if (ModCheatBodyDirection && useDesiredBodyDirection && animType == "movement")
            {
                float angleFactor = 0.5f;
                float maxAngleCbd = 0.25f * Mathf.Pi;
                float predictedAngleRel = anim.GetOutgoingAngle() + anim.GetOutgoingBodyAngle() + rotationOffsetRet;
                float desiredRotationOffset = BluntMath.GetAngle2D(
                    BluntMath.GetRotated2D(desiredBodyDirectionRel, -predictedAngleRel),
                    new Vector3(0, -1, 0));
                if (Mathf.Abs(desiredRotationOffset) < 0.5f * Mathf.Pi)    // :2515 — иначе слишком
                {
                    float outgoingVelocityFactorInv = 1.0f - BluntMath.NormalizedClamp(
                        resultingMovement.Length(), Velo.IdleDribbleSwitch, Velo.Sprint - 1.0f) * 1.0f;
                    float animLengthFactor = BluntMath.NormalizedClamp(anim.GetFrameCount(), 0, 25);
                    float maximizedRotationOffset = Mathf.Clamp(desiredRotationOffset,
                        outgoingVelocityFactorInv * animLengthFactor * angleFactor * -maxAngleCbd,
                        outgoingVelocityFactorInv * animLengthFactor * angleFactor * maxAngleCbd);
                    rotationOffsetRet += maximizedRotationOffset;
                }
            }

            return resultingMovement;
        }
```

Плюс поля-флаги (:2138-2146):

```csharp
        // Флаги модов оригинала (humanoidbase.cpp:2138-2146). readonly, не const:
        // мёртвые ветки должны компилироваться (bug-for-bug, включаемо при отладке).
        private static readonly bool ModAllowRotation = true;
        private static readonly bool ModCorneringBraking = false;
        private static readonly bool ModPointinessCurve = true;
        private static readonly bool ModMaximumAccelDecel = false;
        private static readonly bool ModBrakeOnTouch = false; // может быть слишком «остро» у клипов ~90°
        private static readonly bool ModMaxCornering = true;
        private static readonly bool ModMaxChange = true;
        private static readonly bool ModAirResistance = true;
        private static readonly bool ModCheatBodyDirection = false;
```

Ассерты оригинала (`:2058-2063`, `:2090-2091`, `:2300`, `:2475`, `:2480`, `:2495`, `:2541` — все про
Z==0 и размер positions) не переносить в код — зафиксировать одним комментарием у метода; их
семантику проверяет тест (Z==0, размер == frameCount).

- [ ] **Шаг 4: прогнать тест — PASS**; `dotnet build` чист; полный набор `check_gpf_*` без регрессий.

- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/SpatialState.cs src/gpf/PhysicsVector.cs tests/check_gpf_physics_vector.gd tests/check_gpf_physics_vector.gd.uid
git commit -m "feat(gpf): порт CalculatePhysicsVector — варпинг траектории (фаза 3, задача 3)"
```

---

### Задача 4: Gpf.HumanoidBase — контур состояния movement-пути

**Files:**
- Create: `src/gpf/HumanoidBase.cs`
- Test: `tests/check_gpf_humanoid_state.gd`

**Interfaces:**
- Consumes: `AnimSelector.SelectMovementInternal(...)` (internal, фаза 2), `AnimSelector
  .ForceIntoAllowedBodyDirectionVec(Vector3)`, `AnimCollection.GetAnim/GetIdleMovementAnimID/
  GetPositionCacheInternal`, `PhysicsVector` (задачи 2–3), `SpatialState` (задача 3),
  `Animation.GetInterpolatedRotation/SampleRootPosition/GetEffectiveFrameCount/GetOutgoingFootId/
  GetIncomingBodyAngle`, `QuatUtil.GetAngles`, `BluntMath`, `Velo`.
- Produces (для задачи 5):

```csharp
public partial class HumanoidBase : RefCounted
{
    public void Setup(AnimCollection anims, AnimSelector selector);
    public void ResetSituation(Vector3 position, float angle);   // старт: idle-клип из кэша
    public void SetStatsPreset(float preset);                    // все 6 статов = preset (лаба)
    // один тик 10 мс; порядок Process (:585-594): CalculateSpatialState → frameNum++ →
    // (граница: выбор нового клипа) → apply-данные (:684-711). Возвращает true при смене клипа.
    public bool Tick(Vector3 desiredDirectionWorld, float desiredVelocityFloat,
                     bool useDesiredLookAt, Vector3 desiredLookAt);
    // apply-данные текущего тика (animApplyBuffer, :700-711)
    public int GetApplyFrameNum();
    public Vector3 GetApplyPosition();
    public float GetApplyOrientation();
    public bool GetApplyNoPos();
    public int GetCurrentAnimId();
    // spatial-мост (для лабы/тестов)
    public Vector3 GetSpatialPosition();
    public float GetSpatialAngle();
    public int GetSpatialEnumVelocity();
    public float GetSpatialFloatVelocity();
    public Vector3 GetSpatialMovement();
    public Vector3 GetRelBodyDirectionVec();
    public int GetFoot();
}
```

**Структура реализации** (всё — с комментариями-ссылками):

- Константы `humanoid.cpp:42,54-55`:

```csharp
    private const bool AnimSmoothing = true;                       // humanoid.cpp:42
    private const float BodyRotationSmoothingFactor = 1.0f;        // humanoid.cpp:54
    private static readonly float BodyRotationSmoothingMaxAngle =
        AnimSmoothing ? 0.25f * Mathf.Pi : 0.0f;                   // humanoid.cpp:55
```

- Держатель текущего клипа (подмножество `Anim`-структуры `humanoidbase.hpp:85-112`; smuggle-поля —
  нули до фазы 4, но участвуют в формулах дословно):

```csharp
    private class CurrentAnimState
    {
        public int Id = -1;
        public Animation Anim = null!;
        public int FrameNum;
        public List<Vector3> Positions = new();
        public float RotationSmuggleBegin, RotationSmuggleEnd, RotationSmuggleOffset;
        public Vector3 IncomingMovement, OutgoingMovement;
        public Vector3 ActionSmuggleOffset, ActionSmuggleSustainOffset, MovementSmuggleOffset; // нули (фаза 4)
    }
```

- Поля: `_anims`, `_selector`, `readonly PhysicsVector _physics`, `readonly SpatialState _spatial`,
  `_startPos`, `_startAngle`, `_previousPosition2D`, `_current` (CurrentAnimState), apply-буфер
  (`_applyFrameNum/_applyPosition/_applyOrientation/_applyNoPos`), `_statsPreset = 0.6f`.

- `ResetSituation(position, angle)` — аналог инициализации `humanoidbase.cpp:948-957` без
  random-кадра (лаба детерминирована, отклонение задокументировать): `_current.Id =
  idleMovementAnimID`, `Positions = кэш коллекции` (`:953`), `FrameNum = 0`, smuggle-поля 0,
  `_startPos = position`, `_startAngle = angle`, `_previousPosition2D = position`, `_spatial` — свежий
  `SpatialState` с `Position = position`, `Angle = angle`.

- `Tick(...)` — порядок `Process`:

```csharp
    public bool Tick(Vector3 desiredDirectionWorld, float desiredVelocityFloat,
                     bool useDesiredLookAt, Vector3 desiredLookAt)
    {
        CalculateSpatialState();                       // :585
        _spatial.PositionOffsetMovement = Vector3.Zero; // :586
        _current.FrameNum++;                            // :588

        bool switched = false;
        // на границе — выбор следующего клипа (:592-594 → SelectAnim; requeue не портирован)
        if (_current.FrameNum == _current.Anim.GetFrameCount() - 1)
        {
            switched = SelectNextMovementAnim(desiredDirectionWorld, desiredVelocityFloat,
                                              useDesiredLookAt, desiredLookAt);
            if (!switched)
            {
                // «RED ALERT» (:640) в лабе недостижим: SelectMovementInternal сам подставляет
                // idle-фолбэк (:1412-1417). Страховка от вылета на пустой коллекции:
                // перезапустить текущий клип с нуля.
                GD.PushError("Gpf.HumanoidBase: не найден следующий клип — перезапуск текущего");
                _current.FrameNum = 0;
            }
        }

        // movement/rotation smuggle → apply-данные (:684-711)
        float frameBias = (_current.FrameNum + 1)
            / (float)(_current.Anim.GetEffectiveFrameCount() + 1);         // :687
        _current.RotationSmuggleOffset = _current.RotationSmuggleBegin * (1.0f - frameBias)
            + _current.RotationSmuggleEnd * frameBias;                     // :694-695

        _applyFrameNum = _current.FrameNum;                                // :700
        if (_current.Positions.Count > _current.FrameNum)                  // :702-705
        {
            _applyPosition = _startPos + _current.ActionSmuggleOffset
                + _current.ActionSmuggleSustainOffset + _current.MovementSmuggleOffset
                + _current.Positions[_current.FrameNum];
            _applyOrientation = _startAngle + _current.RotationSmuggleOffset;
            _applyNoPos = true;
        }
        else                                                               // :706-711
        {
            _applyPosition = _startPos + _current.ActionSmuggleOffset
                + _current.ActionSmuggleSustainOffset + _current.MovementSmuggleOffset;
            _applyOrientation = _startAngle;
            _applyNoPos = false;
        }
        return switched;
    }
```

- `SelectNextMovementAnim(...)` — порт вызова из `SelectAnim` (`:1374-1601`, movement-ветка):

```csharp
    private bool SelectNextMovementAnim(Vector3 desiredDirectionWorld, float desiredVelocityFloat,
                                        bool useDesiredLookAt, Vector3 desiredLookAt)
    {
        // :1377 — на Switch-прерывании условие «!= ReQueue» всегда истинно
        CalculateFactualSpatialState();

        var dataSet = _selector.SelectMovementInternal(_spatial.Position, _spatial.Angle,
            _spatial.EnumVelocity, _spatial.FloatVelocity, _spatial.RelBodyDirectionVec,
            _spatial.Foot, desiredDirectionWorld, desiredVelocityFloat,
            useDesiredLookAt, desiredLookAt);
        if (dataSet.Count == 0) return false;                              // :1510-1514

        int selectedAnimID = dataSet[0];                                   // :1521
        Animation nextAnim = _anims.GetAnim(selectedAnimID);
        Vector3 desiredMovement = desiredDirectionWorld * desiredVelocityFloat; // :1523
        Vector3 desiredBodyDirectionRel = new Vector3(0, -1, 0);           // :1529
        if (useDesiredLookAt)
            desiredBodyDirectionRel = BluntMath.GetNormalized(
                BluntMath.GetRotated2D(BluntMath.Get2D(desiredLookAt - _spatial.Position), -_spatial.Angle)
                - nextAnim.GetTranslation(), new Vector3(0, -1, 0));       // :1530
        // (в humanoid.cpp:1664-1665 формула другая («hax») — базовый класс считает так; порт по базе)

        _physics.SetSpatialState(_spatial.Position, _spatial.Angle, _spatial.DirectionVec,
            _spatial.FloatVelocity, _spatial.Movement);
        var positionsTmp = new List<Vector3>();
        _physics.Calculate(nextAnim, _anims.GetPositionCacheInternal(selectedAnimID),
            true, desiredMovement, useDesiredLookAt, desiredBodyDirectionRel,
            positionsTmp, out float rotationSmuggleTmp);                   // :1531

        // make it so (:1558-1597; smuggle-поля кроме rotation — нули до фазы 4)
        _current.Id = selectedAnimID;                                      // :1572-1573
        _current.Anim = nextAnim;
        _current.FrameNum = 0;                                             // :1575
        _current.RotationSmuggleBegin = Mathf.Clamp(
            BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi,
                _spatial.RelBodyAngleNonquantized - nextAnim.GetIncomingBodyAngle())
            * BodyRotationSmoothingFactor,
            -BodyRotationSmoothingMaxAngle, BodyRotationSmoothingMaxAngle); // :1580
        _current.RotationSmuggleEnd = rotationSmuggleTmp;                  // :1581
        _current.RotationSmuggleOffset = 0;                                // :1582
        _current.ActionSmuggleOffset = Vector3.Zero;                       // :1585-1589
        _current.ActionSmuggleSustainOffset = Vector3.Zero;
        _current.MovementSmuggleOffset = Vector3.Zero;
        _current.IncomingMovement = _spatial.Movement;                     // :1590
        _current.OutgoingMovement = CalculateOutgoingMovement(positionsTmp); // :1591
        _current.Positions.Clear();                                        // :1592-1593
        _current.Positions.AddRange(positionsTmp);

        _startPos = _spatial.Position;                                     // Process :648-649
        _startAngle = _spatial.Angle;
        return true;
    }
```

- `CalculateOutgoingMovement` (`:1617-1620`):

```csharp
    private static Vector3 CalculateOutgoingMovement(List<Vector3> positions)
    {
        if (positions.Count < 2) return Vector3.Zero;
        return (positions[positions.Count - 1] - positions[positions.Count - 2]) * 100.0f;
    }
```

- `CalculateSpatialState()` — порт `:1622-1726` дословно:

```csharp
    // humanoidbase.cpp:2138-аналог: мёртвая else-ветка портируется под readonly-флагом
    private static readonly bool PreferCorrectVeloOverCorrectAngle = true; // :1691

    private void CalculateSpatialState() // humanoidbase.cpp:1622-1726
    {
        Vector3 position;
        if (_current.Positions.Count > _current.FrameNum)                  // :1624-1625
        {
            position = _startPos + _current.Positions[_current.FrameNum]
                + _current.ActionSmuggleOffset + _current.ActionSmuggleSustainOffset
                + _current.MovementSmuggleOffset;
        }
        else                                                               // :1626-1631
        {
            position = _current.Anim.SampleRootPosition(_current.FrameNum, 0f);
            position.Z = 0.0f;
            position = _startPos + BluntMath.GetRotated2D(position, _startAngle)
                + _current.ActionSmuggleOffset + _current.ActionSmuggleSustainOffset
                + _current.MovementSmuggleOffset;
        }

        if (_current.FrameNum > 12)                                        // :1633-1635
            _spatial.Foot = _current.Anim.GetOutgoingFootId();

        _spatial.ActualMovement = (position - _previousPosition2D) * 100.0f; // :1642
        float positionOffsetMovementIgnoreFactor = 0.5f;                   // :1643
        _spatial.PhysicsMovement = _spatial.ActualMovement
            - _spatial.ActionSmuggleMovement - _spatial.MovementSmuggleMovement
            - _spatial.PositionOffsetMovement * positionOffsetMovementIgnoreFactor; // :1644
        _spatial.AnimMovement = _spatial.PhysicsMovement;                  // :1645
        if (_current.Positions.Count > 0)                                  // :1646-1651
        {
            // экшн-чит исключается из текущего движения — лучшие реквеи (коммент. ориг.)
            var origPositionCache = _anims.GetPositionCacheInternal(_current.Id);
            _spatial.AnimMovement = BluntMath.GetRotated2D(
                PhysicsVector.CalculateMovementAtFrame(origPositionCache, _current.FrameNum, 1),
                _startAngle);
        }
        _spatial.Movement = _spatial.PhysicsMovement;                      // :1655 PICK DEFAULT

        Quaternion bodyOrientation = _current.Anim.GetInterpolatedRotation("body", _current.FrameNum); // :1662
        QuatUtil.GetAngles(bodyOrientation, out _, out _, out float z);    // :1663-1664

        Vector3 bodyDirectionVec = BluntMath.GetRotated2D(new Vector3(0, -1, 0),
            z + _startAngle + _current.RotationSmuggleOffset);             // :1668

        _spatial.FloatVelocity = _spatial.Movement.Length();               // :1670-1671
        _spatial.EnumVelocity = Velo.FloatToEnumVelocity(_spatial.FloatVelocity);

        if (_spatial.EnumVelocity != Velo.IdVelIdle)                       // :1673-1678
            _spatial.DirectionVec = BluntMath.GetNormalized(_spatial.Movement, Vector3.Zero);
        else
            _spatial.DirectionVec = bodyDirectionVec; // слишком медленно — направление тела

        _spatial.Position = position;                                      // :1680
        _spatial.Angle = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi,
            BluntMath.FixAngle(BluntMath.GetAngle2D(_spatial.DirectionVec))); // :1681

        if (_spatial.EnumVelocity != Velo.IdVelIdle)                       // :1683-1715
        {
            Vector3 adaptedBodyDirectionVec = BluntMath.GetRotated2D(bodyDirectionVec, -_spatial.Angle);
            float bodyAngleRel = BluntMath.GetAngle2D(adaptedBodyDirectionVec, new Vector3(0, -1, 0)); // :1692
            if (_spatial.EnumVelocity == Velo.IdVelSprint && Mathf.Abs(bodyAngleRel) >= 0.125f * Mathf.Pi)
            {
                if (PreferCorrectVeloOverCorrectAngle)
                    // невозможная пара скорость×угол → уменьшаем угол (:1696)
                    adaptedBodyDirectionVec = BluntMath.GetRotated2D(new Vector3(0, -1, 0),
                        0.12f * Mathf.Pi * BluntMath.SignSide(bodyAngleRel));
                else
                {
                    // мёртвая ветка (:1698-1700): уменьшаем скорость
                    _spatial.FloatVelocity = Velo.WalkSprintSwitch - 0.1f;
                    _spatial.EnumVelocity = Velo.FloatToEnumVelocity(_spatial.FloatVelocity);
                }
            }
            else if (_spatial.EnumVelocity == Velo.IdVelWalk && Mathf.Abs(bodyAngleRel) >= 0.5f * Mathf.Pi)
            {
                if (PreferCorrectVeloOverCorrectAngle)
                    adaptedBodyDirectionVec = BluntMath.GetRotated2D(new Vector3(0, -1, 0),
                        0.495f * Mathf.Pi * BluntMath.SignSide(bodyAngleRel)); // :1706
                else
                {
                    // мёртвая ветка (:1708-1710)
                    _spatial.FloatVelocity = Velo.DribbleWalkSwitch - 0.1f;
                    _spatial.EnumVelocity = Velo.FloatToEnumVelocity(_spatial.FloatVelocity);
                }
            }
            _spatial.RelBodyDirectionVecNonquantized = adaptedBodyDirectionVec;      // :1714
            _spatial.RelBodyDirectionVec = _selector.ForceIntoAllowedBodyDirectionVec(adaptedBodyDirectionVec); // :1715
        }
        else                                                               // :1716-1719
        {
            _spatial.RelBodyDirectionVecNonquantized = new Vector3(0, -1, 0);
            _spatial.RelBodyDirectionVec = new Vector3(0, -1, 0);
        }
        _spatial.RelBodyAngle = BluntMath.GetAngle2D(_spatial.RelBodyDirectionVec, new Vector3(0, -1, 0)); // :1720
        _spatial.RelBodyAngleNonquantized = BluntMath.GetAngle2D(
            _spatial.RelBodyDirectionVecNonquantized, new Vector3(0, -1, 0));        // :1721
        _spatial.BodyDirectionVec = BluntMath.GetRotated2D(_spatial.RelBodyDirectionVec, _spatial.Angle); // :1722
        _spatial.BodyAngle = BluntMath.GetAngle2D(_spatial.BodyDirectionVec, new Vector3(0, -1, 0));      // :1723

        _previousPosition2D = position;                                    // :1725
    }
```

- `CalculateFactualSpatialState()` — порт `:1728-1737`:

```csharp
    private void CalculateFactualSpatialState()
    {
        _spatial.Foot = _current.Anim.GetOutgoingFootId();                 // :1730
        if (_current.Anim.GetVariable("outgoing_special_state") != "")     // :1732-1736
        {
            _spatial.FloatVelocity = 0;
            _spatial.EnumVelocity = Velo.IdVelIdle;
            _spatial.Movement = Vector3.Zero;
        }
    }
```

- `SetStatsPreset(float p)` → `_physics.SetStats(p, p, p, p, p, p)`.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Фаза 3, задача 4: HumanoidBase — состояние по варпнутым позициям (humanoidbase.cpp:585-711,1622-1737).

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func make_humanoid(c, sel):
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	return h

func _initialize() -> void:
	var ok := true
	var V = load("res://src/gpf/Velo.cs")
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var AS = load("res://src/gpf/AnimSelector.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)
	var sel = AS.new()
	sel.Setup(c)
	var fwd := Vector3(0, -1, 0)

	# --- 1. Стоим по idle-команде: не уезжаем, скорость idle ---
	var h = make_humanoid(c, sel)
	for i in 200:
		h.Tick(fwd, 0.0, true, h.GetSpatialPosition() + fwd * 10.0)
	if h.GetSpatialEnumVelocity() != 0:
		print("CHECK FAIL: idle-команда разогнала до ", h.GetSpatialEnumVelocity()); ok = false
	if h.GetSpatialPosition().length() > 0.5:
		print("CHECK FAIL: idle уехал в ", h.GetSpatialPosition()); ok = false

	# --- 2. Спринт вперёд: инварианты состояния на каждом тике ---
	h = make_humanoid(c, sel)
	# прогрев 2 тика: на самом первом тике previousPosition2D — точка ResetSituation, а позиция —
	# кадр 0 сырого кэша idle-клипа; их дельта не обязана быть нулевой (движение-инвариант
	# осмыслен со второго тика)
	h.Tick(fwd, 8.0, true, h.GetSpatialPosition() + fwd * 10.0)
	h.Tick(fwd, 8.0, true, h.GetSpatialPosition() + fwd * 10.0)
	var allowed := [Vector3(0, -1, 0)]
	for a in [-0.25, 0.25, -0.75, 0.75]:
		allowed.append(Vector3(0, -1, 0).rotated(Vector3(0, 0, 1), a * PI))
	var transitions := 0
	var t := 0
	# 6 клипов: разгон при физике медленнее lite — актуальная скорость может отставать от бакета клипа
	while transitions < 6 and t < 4000:
		var before: Vector3 = h.GetSpatialPosition()
		var switched: bool = h.Tick(fwd, 8.0, true, h.GetSpatialPosition() + fwd * 10.0)
		if switched: transitions += 1
		t += 1
		# движение == дельта позиций ×100 (:1642; smuggle-нули)
		var expected_mv: Vector3 = (h.GetSpatialPosition() - before) * 100.0
		if not vec_eq(h.GetSpatialMovement(), expected_mv, 1.0e-3):
			print("CHECK FAIL: movement != Δpos×100 на тике ", t); ok = false
			break
		# enum == бакет float (CalculateSpatialState :1670-1671)
		if h.GetSpatialEnumVelocity() != V.FloatToEnumVelocity(h.GetSpatialFloatVelocity()):
			print("CHECK FAIL: enum/float разошлись на тике ", t); ok = false
			break
		# RelBodyDirectionVec квантован в одну из 5 разрешённых (:1715)
		var best_dot := -1.0
		for av in allowed:
			var av2: Vector3 = av
			var d: float = av2.dot(h.GetRelBodyDirectionVec())
			if d > best_dot: best_dot = d
		if best_dot < 0.9999:
			print("CHECK FAIL: RelBodyDirectionVec вне решётки: ", h.GetRelBodyDirectionVec()); ok = false
			break
	if t >= 4000:
		print("CHECK FAIL: 6 смен клипа не случились за 4000 тиков"); ok = false
	# после 6 клипов разгона по спринт-команде скорость минимум walk
	if h.GetSpatialEnumVelocity() < 2:
		print("CHECK FAIL: после разгона скорость ", h.GetSpatialEnumVelocity()); ok = false
	if h.GetSpatialPosition().y > -2.0:
		print("CHECK FAIL: не уехал вперёд: ", h.GetSpatialPosition()); ok = false

	# --- 3. Детерминизм: два одинаковых прогона тик-в-тик ---
	var h1 = make_humanoid(c, sel)
	var h2 = make_humanoid(c, sel)
	for i in 500:
		h1.Tick(fwd, 8.0, true, h1.GetSpatialPosition() + fwd * 10.0)
		h2.Tick(fwd, 8.0, true, h2.GetSpatialPosition() + fwd * 10.0)
	if h1.GetSpatialPosition() != h2.GetSpatialPosition() or h1.GetSpatialAngle() != h2.GetSpatialAngle():
		print("CHECK FAIL: недетерминизм прогона"); ok = false

	# --- 4. apply-данные согласованы: noPos и позиция от startPos ---
	if not h.GetApplyNoPos():
		print("CHECK FAIL: apply без noPos при живом кэше positions"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: прогнать — падает** (нет `HumanoidBase.cs`). `--import` для `.uid`.
- [ ] **Шаг 3: реализовать** по структуре выше; `dotnet build` чист.
- [ ] **Шаг 4: прогнать — PASS**; полный `check_gpf_*` без регрессий.
- [ ] **Шаг 5: коммит**

```powershell
git add src/gpf/HumanoidBase.cs tests/check_gpf_humanoid_state.gd tests/check_gpf_humanoid_state.gd.uid
git commit -m "feat(gpf): HumanoidBase — контур состояния movement-пути (фаза 3, задача 4)"
```

---

### Задача 5: walk_lab на настоящей интеграции + walker-тест

**Files:**
- Modify: `src/lab/WalkLabMain.cs`
- Modify: `tests/check_gpf_walker.gd`

**Interfaces:**
- Consumes: `HumanoidBase` (задача 4), `AnimationApplier.Apply(skel, anim, frame, timeOffsetMs,
  noPos, baseRotZ, basePos)` (фаза 2).
- Produces: прежний тестовый API `WalkLabMain` (`SetCommand`, `GetCurrentAnimIndex`,
  `GetTransitionCount`, `GetStateVelocityId`, `GetStateAngle`, `GetStatePosition`, `StepOneFrame`) —
  сигнатуры не меняются, `check_gpf_walker.gd` продолжает их звать; внутри всё делегируется
  `HumanoidBase`.

**Суть правки `WalkLabMain`:**
1. Убрать lite-поля `_position/_angle/_velocityId/_floatVelocity/_relBodyDir/_footId` и весь
   `AdvanceToNextAnim`. Вместо них — `private Gpf.HumanoidBase _humanoid = new();`
   в `_Ready`: `_humanoid.Setup(_collection, _selector); _humanoid.ResetSituation(Vector3.Zero, 0f);`.
2. `StepOneFrame()`:

```csharp
        public void StepOneFrame()
        {
            bool switched = _humanoid.Tick(_desiredDirection,
                Gpf.Velo.EnumToFloatVelocity(_desiredVelocityId),
                true, _humanoid.GetSpatialPosition() + _desiredDirection * 10f); // GetBasicMovementCommand :1771
            if (switched) _transitions++;
            var anim = _collection.GetAnim(_humanoid.GetCurrentAnimId());
            // применение как в animApplyBuffer (:700-711): позиция и доворот идут ЦЕЛИКОМ
            // через basePos/baseRotZ, клипу корень запрещён (noPos)
            _applier.Apply(_skeleton, anim, _humanoid.GetApplyFrameNum(), 0f,
                _humanoid.GetApplyNoPos(), _humanoid.GetApplyOrientation(), _humanoid.GetApplyPosition());
        }
```

   Перед реализацией перечитать `AnimationApplier.cs` и сверить семантику `noPos` с
   `animation.cpp:713-717` (наш `noPos` зануляет X/Y корня клипа, `baseRotZ`/`basePos` применяются
   всегда) — ровно то, что делает `animApplyBuffer.noPos=true` + `position`/`orientation`.
3. Геттеры делегируют: `GetStateVelocityId => _humanoid.GetSpatialEnumVelocity()`,
   `GetStateAngle => _humanoid.GetSpatialAngle()`, `GetStatePosition => _humanoid.GetSpatialPosition()`,
   `GetCurrentAnimIndex => _humanoid.GetCurrentAnimId()`; новый
   `public float GetStateFloatVelocity() => _humanoid.GetSpatialFloatVelocity();` (для HUD и
   walker-теста).
4. HUD: дополнительно печатать `v={floatVelocity:F2} м/с` и текущий пресет статов; клавиша `A`
   циклит пресеты `0.3 → 0.6 → 0.9` (`_humanoid.SetStatsPreset`), подпись в HUD-строке подсказок.
   Камера/стрелка/ввод — без изменений.

**Правка `check_gpf_walker.gd`:** структура та же, три блока (разгон/поворот/стоп), но пороги — под
физику, не под lite-скачки дескрипторов (скорость теперь непрерывна и может требовать больше клипов
на разгон; квантование конца клипа гарантирует только idle-ность, не точный бакет):
- разгон: до **8** смен клипа (было 4), guard 8000; ожидание `GetStateVelocityId() >= 2` и
  `pos.y < -1.0` сохраняются;
- поворот: до **4** смен (было 3), guard 8000, порог `dturn <= -0.15 * PI` сохраняется;
- стоп: до **6** смен (было 5), guard 10000, ожидание `GetStateVelocityId() <= 1` сохраняется.
Если тест проходит с прежними порогами — вернуть прежние (сначала прогнать без ослабления; ослаблять
только по фактическому провалу, с комментарием в тесте «физразгон медленнее lite: N клипов»).

- [ ] **Шаг 1: обновить `check_gpf_walker.gd`** (пороги — как выше, с комментарием при ослаблении).
- [ ] **Шаг 2: прогнать — падает** (лаба ещё lite; ожидаемый провал — отсутствие
  `GetStateFloatVelocity` у lite-лабы; тест обязан использовать этот геттер хотя бы в одной проверке
  непрерывности: в середине разгона `GetStateFloatVelocity()` не равна ни одному из бакетов
  0/3.5/5.0/8.0 точно — lite отдаёт ровно бакеты дескрипторов, физика — промежуточные значения).
- [ ] **Шаг 3: переписать `WalkLabMain`** по схеме выше; `dotnet build`.
- [ ] **Шаг 4: прогнать walker + весь `check_gpf_*` + обе стандартные headless-валидации** — PASS/без
  новых категорий ошибок.
- [ ] **Шаг 5: визуальная приёмка человеком** — запустить

```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" res://scenes/lab/walk_lab.tscn
```

  Чек-лист глаз: разгон плавный (скорость ползёт, не прыгает по бакетам); резкая смена направления
  даёт дугу, а не телепорт-поворот; торможение занимает клип-другой; на пресете статов 0.9 повороты
  заметно резче, чем на 0.3; палочник не «плавает» относительно ног (варп двигает корень синхронно с
  шагами). Сверка бок-о-бок с эталонным exe GameplayFootball (см. роадмап). **Это приёмка фазы —
  без неё задача не закрыта.** Замечания глаз → фикс-итерации в этой же задаче.
- [ ] **Шаг 6: коммит**

```powershell
git add src/lab/WalkLabMain.cs tests/check_gpf_walker.gd
git commit -m "feat(lab): walk_lab на варпнутых траекториях — настоящий CalculateSpatialState (фаза 3, задача 5)"
```

---

### Задача 6: документация и финальная валидация

**Files:**
- Modify: `docs/wiki/порт-gameplayfootball.md`
- Modify: `docs/wiki/открытые-вопросы.md`
- Modify: `log.md` (append-only)
- Modify: `.claude/hooks/wiki-hint.py`

**Interfaces:** consumes — итог задач 1–5; produces — актуальная вики.

- [ ] **Шаг 1: `порт-gameplayfootball.md`** — переписать (не дописывать «UPDATE»):
  - статус: фаза 3 код-complete (+визуальная приёмка — по факту шага 5.5);
  - структура: добавить `PhysicsVector.cs`, `SpatialState.cs`, `HumanoidBase.cs` с одним-двумя
    предложениями на каждый; кэш позиций в `AnimCollection`;
  - инварианты фазы 3 (новая секция): двойной `GetMaxVelocity` (touch-сжатый локальный vs свежий в
    сопротивлении воздуха, `:2065` vs `:2424`); `(int)`-усечение кадра `:2229`; mod-флаги — `static
    readonly`, мёртвые ветки портированы; `animSprintVelocity` 7.0 ≠ литерал 7.0 квантования
    дескрипторов; последние два кадра (`frameCount-2`) — жёсткое квантование idle-ности; порядок тика
    `CalculateSpatialState → frameNum++ → выбор → apply`;
  - секцию «Что НЕ портировано» обновить: lite-интеграция ушла; requeue, `previousAnim`,
    `CalculatePredictedSituation`, smuggle-механика (поля-нули), `decayingPositionOffset` как живущее
    поле — фаза 4;
  - тесты: перечислить 4 новых check-скрипта одной строкой каждый;
  - раздел `walk_lab`: клавиша `A` (пресеты статов), v= в м/с.
- [ ] **Шаг 2: `открытые-вопросы.md`** — удалить пункт про lite-интеграцию `walk_lab`; добавить в
  раздел порта: «ReQueue не портирован — клип живёт до конца, отзывчивость ниже оригинала (~240 мс
  перевыбор); фаза 4»; «smuggle-поля нулевые, формулы уже их учитывают»; «пресеты статов лабы —
  сурроргат настоящих PlayerData из БД оригинала».
- [ ] **Шаг 3: `log.md`** — одна запись `## [2026-07-30] feat | Порт GPF фаза 3: CalculatePhysicsVector`
  (3–5 строк: что, ключевой риск — константы, как проверено).
- [ ] **Шаг 4: `wiki-hint.py`** — добавить маппинги `src/gpf/PhysicsVector.cs`, `src/gpf/SpatialState.cs`,
  `src/gpf/HumanoidBase.cs` → `порт-gameplayfootball`.
- [ ] **Шаг 5: финальная валидация** — `dotnet build`; обе стандартные headless-команды (baseline —
  по категориям); все 17 `check_gpf_*.gd` подряд.
- [ ] **Шаг 6: коммит**

```powershell
git add docs/wiki/порт-gameplayfootball.md docs/wiki/открытые-вопросы.md log.md .claude/hooks/wiki-hint.py
git commit -m "docs(wiki): фаза 3 порта GPF — варпинг CalculatePhysicsVector"
```

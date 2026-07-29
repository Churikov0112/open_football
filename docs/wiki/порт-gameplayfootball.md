# Порт ядра GameplayFootball (C#)

Порт игрового ядра [GameplayFootball](https://github.com/vi3itor/GameplayFootball) (Apache 2.0) —
стратегическое решение от 2026-07-29: вместо дальнейшего тюнинга собственного `PlayerMotor`/lead-follow
переносим проверенное 9/10-ощущение оригинала. Полный контекст решения, отвергнутые альтернативы
(active-ragdoll/Rabona, GDExtension, big-bang перевод на C#) и фазировка — в роадмап-спеке
`docs/superpowers/specs/2026-07-29-gameplayfootball-port-roadmap-design.md`; разбор оригинального кода
по файлам и номерам строк — в приложенном тех-отчёте `docs/superpowers/specs/
2026-07-29-gameplayfootball-core-report.md`. Ядро портируется на **C#** (`.NET`-редакция Godot 4.7.1,
solution `OpenFootball.sln`); существующий GDScript **не** переписывается превентивно — файл переезжает
на C# только когда всё равно перерабатывается под новое ядро.

## Статус: фаза 2 (`AnimCollection`) код-complete, визуальная приёмка впереди

Фаза 1 («лаб-сцена + скелет-палочник») закрыта и принята визуально человеком 2026-07-29. Фаза 2
(`AnimCollection`: загрузка всей библиотеки, автогенерация вариаций, зеркала, грубый отбор + выбор
клипа `AnimSelector`, лаб-сцена `walk_lab` — палочник ходит/бегает по командам) реализована и
код-complete: все 13 headless-тестов `tests/check_gpf_*.gd` зелёные, обе стандартные headless-валидации
без новых категорий ошибок, `dotnet build` чист. **Интерактивная визуальная приёмка человеком** (шаг
плана фазы 2 — палочник в `walk_lab.tscn` реально ускоряется/тормозит/поворачивает по клавишам без
дёрганий) и финальное ревью ветки — ещё не пройдены, идут следом за этой документационной задачей.
Следующая веха после приёмки — фаза 3 (варпинг траектории под физику, `CalculatePhysicsVector`).

## Структура

- `assets/gpf/` — датасет GameplayFootball как есть: 293 файла `.anim` (+3 служебных `.anim.util`) под
  `assets/gpf/animations/**` (293 включают 10 в `templates/`), `LICENSE-GameplayFootball` (Apache 2.0).
  **Read-only данные** — это исходники оригинала, руками не редактируются.
- `src/gpf/` — переиспользуемое C#-ядро порта, без зависимости от лабы или матча:
  - `Animation.cs` (`Gpf.Animation`) — парсер `.anim` + интерполяция кадра (порт `animation.cpp`);
    фаза 2 добавила write-API (`Clone`/`SetKeyFrame`/`Shift`/`SetVariable`/`SetName`/
    `SetCurrentFootId`), `Mirror()`, `ConvertToStartFacingForwardIfIdle()` (вызывается из
    `LoadFromFile`), `NormalizeDirectionTags()` и 12 ленивых дескрипторов клипа (`GetIncoming/
    OutgoingVelocity`, `GetIncoming/OutgoingMovement`, `GetIncoming/OutgoingBodyAngle`,
    `GetIncoming/OutgoingBodyDirection`, `GetOutgoingDirection`, `GetOutgoingAngle`, `GetTranslation`)
    с кэшем `DirtyCache()`.
  - `QuatUtil.cs` (`Gpf.QuatUtil`) — кватернионная математика 1:1 с `quaternion.cpp` (slerp с `bias>1`
    для экстраполяции, `SameNeighborhood`, покомпонентный lerp) — **не** заменять на `Quaternion.Slerp`
    из Godot, поведение должно совпадать с оригиналом побитово; фаза 2 добавила `GetAngles`/
    `GetAnglesVec` (эйлеры) и `AngleAxis`.
  - `SkeletonBuilder.cs` (`Gpf.SkeletonBuilder`) — 14-костный `Skeleton3D` 1:1 `player.object` + базис
    конверсии осей `GpfSpace`.
  - `AnimationApplier.cs` (`Gpf.AnimationApplier`) — применение сэмпла клипа на `Skeleton3D`, порт
    `Animation::Apply`; фаза 2 добавила `baseRotZ`-доворот позиции корня (`position.Rotate2D`) и
    `basePos`-смещение (`animation.cpp:413-415, 715`) — закрывает шов, оставленный в фазе 1.
  - `BluntMath.cs` (`Gpf.BluntMath`) — порт `bluntmath.{hpp,cpp}`/`vector3.hpp`/`utils.cpp`:
    `Curve`/`NormalizedClamp`/`ModulateIntoRange`/`FixAngle`/`AtoF`/`AtoI`/`GetVectorFromString`/
    `GetRotated2D`/`GetAngle2D` (обе перегрузки)/`GetNormalized`/`Get2D`. Общий математический
    фундамент фазы 2, читают все остальные новые файлы.
  - `Velo.cs` (`Gpf.Velo`) — константы скоростей оригинала (`gamedefines.hpp:18-27`: idle 0 / dribble
    3.5 / walk 5.0 / sprint 8.0, переключатели 1.8/4.2/6.0) + конверсии `RangeVelocity`/
    `ClampVelocity`/`FloorVelocity`/`EnumToFloatVelocity`/`FloatToEnumVelocity`/`GetVelocityID`.
  - `AnimCollection.cs` (`Gpf.AnimCollection`) — 34 квадранта (idle + 3 скорости × 11 углов), `Load`
    всей библиотеки (файлы ×2 зеркала + автогены из `templates/`), `GenerateAutoAnims`, `PrepareAnim`
    (дескрипторы + `touch_bodypart` + `quadrant_id`), `CrudeSelection` (грубый булев фильтр,
    ~12 независимых секций).
  - `CrudeSelectionQuery.cs` (`Gpf.CrudeSelectionQuery`) — параметры запроса `CrudeSelection`: тип
    функции, стопа, сторона, вход/выход скорости, подбор мяча, направление тела/мяча, свойства,
    тип спотыкания, форсированная нога.
  - `AnimSelector.cs` (`Gpf.AnimSelector`) — `StableSort` (единственный разрешённый способ сортировки
    отбора), `ForceInto*`-таблицы, предикаты сравнения клипов и movement-путь `SelectAnim`
    (`SelectMovementAnim`/`SelectMovementDataSet`).
- `src/lab/` — сцены-приёмники для глаз, к матчу отношения не имеют:
  - `LabMain.cs` (`Gpf.Lab.LabMain`) — корень `scenes/lab/anim_lab.tscn`: сканирует
    `assets/gpf/animations`, листает клипы, держит фикс-тик 100 Гц.
  - `StickmanRenderer.cs` (`Gpf.Lab.StickmanRenderer`) — линии костей по `GetBoneGlobalPose`; левая
    сторона красная, правая синяя (визуальный контроль зеркала).
  - `WalkLabMain.cs` (`Gpf.Lab.WalkLabMain`) — корень `scenes/lab/walk_lab.tscn`: грузит всю
    `AnimCollection`, палочник шагает/бежит/поворачивает по клавишным командам через
    `AnimSelector.SelectMovementAnim`; интеграция состояния между клипами — намеренное **lite**-
    упрощение фазы 2 (см. «Что НЕ портировано» ниже).
- `scenes/lab/walk_lab.tscn` — минимальная сцена (один `Node3D` со скриптом `WalkLabMain.cs`),
  параллельна `anim_lab.tscn`, друг друга не трогают.

## Формат `.anim` — три части файла

`Animation.LoadFromFile` разбирает файл в три фазы подряд (`LoadData` → `LoadFootballExtension` →
`LoadXmlTail`, порт `Animation::Load`):

1. **CSV-строки** — 14 строк-треков в фиксированном порядке `TrackOrder` (`player`, `body`, `middle`,
   `neck`, оба плеча/локтя, оба бедра/колена/лодыжки). Ключи разрежены: строка `player` несёт только
   позицию корня (`frame,x,y,z`), остальные 13 — только **абсолютную локальную ориентацию** джойнта
   (`frame,qx,qy,qz,qw`, порядок компонент как в `Godot.Quaternion`).
2. **`extension`-строки** (опционально) — `extension,football,frame,x,y,z,frame,x,y,z,...`: кадры
   касания мяча + позиция мяча в пространстве клипа. Оригинал чистит карту касаний на каждый вызов
   `Load`, поэтому при нескольких `extension,football`-строках в одном файле переживает только
   последняя.
3. **XML-хвост** — плоские теги верхнего уровня (`<type>`, `<baseanim>`, `<balldirection>`, ...) →
   словарь тег→сырой текст, читается через `GetVariable(tag)`/`GetAnimType()`.

## Инварианты

- **«Их» пространство остаётся внутри.** Клип и скелет живут в осях оригинала (Z-вверх, «вперёд» = −Y).
  Конверсия в Godot-оси происходит **только** на обёртке `GpfSpace` (`Node3D` с базисом
  `SkeletonBuilder.AxisConversionBasis()` — столбцы `X(−1,0,0) Y(0,0,1) Z(0,1,0)`, `det=+1`). Кости и
  данные клипа сами по себе никогда не переводятся в другие оси.
- **`CultureInfo.InvariantCulture`** на каждом `float`/`int` парсинге (`ParseF`, `int.Parse` в
  `LoadData`/`LoadFootballExtension`) — иначе парсинг ловит региональные настройки Windows (запятая как
  разделитель дробной части вместо точки).
- **Кадр = 10 мс.** `timeOffsetMs` семплит между `frame` и `frame+1` в пределах одного 10-мс кадра
  (`SampleBias`).
- **`frameCount = maxFrame + 1`**, не число ключей. `SetKeyFrame` растит `_frameCount` при каждом кадре
  `>= _frameCount` (порт `animation.cpp:123`) — трек может кончиться раньше `frameCount`, тогда
  интерполяция держит последний ключ до конца клипа (см. `GetInterpolatedValues`).
- **Сентинел `timeOffsetMs < 0` → `bias 0.5`**, не 0. Порт `animation.cpp:391-392`: «смещение неизвестно»
  семантически отличается от «смещение 0 мс» — рендер-путь оригинала (`humanoidbase.cpp:779`) зовёт
  `Apply` именно с этим сентинелом. Проверено тестом `check_gpf_anim_sample.gd` (сентинел −1 даёт то же,
  что offset 5 мс).

## Инварианты фазы 2 (`AnimCollection`/`AnimSelector`)

- **Сортировки только через `AnimSelector.StableSort`.** `List<int>.Sort` в C# **не**гарантированно
  стабилен (в отличие от `std::stable_sort` оригинала) — нестабильная сортировка даёт недетерминированный
  выбор клипа при равных ключах сравнения. `StableSort` реализован через LINQ `OrderBy` (документированно
  стабилен); в порте запрещено звать `List.Sort`/`Array.Sort` на любом `dataSet` отбора клипов.
- **Bug-for-bug `animcollection.cpp:619`.** Оригинал в CULL WRONG ROTATIONAL SIDE складывает
  `int`-сторону (`e_Side`, 0/1) с углом в радианах (`queryIncomingToFenceSide + fenceToOutgoingAngle`) —
  похоже на баг (нужен был угол `queryIncomingToFenceAngle`), но портируется **дословно, без починки**
  (`CrudeSelectionInternal`, секция `BySide`, `src/gpf/AnimCollection.cs`).
- **Кумулятивный lean в `GenerateAutoAnims` — так и задумано.** `movementChangeMps *= ...` (:315) стоит
  ВНУТРИ кадрового цикла тела и накапливается от кадра к кадру — это не забытый reset, а поведение
  оригинала; портировано как есть с комментарием на месте.
- **Порядок зеркал разный для файловых клипов и автогенов.** Файловая ветка `Load` добавляет клип в
  порядке оригинал→зеркало (`mirror` 0 затем 1). Ветка автогенов — наоборот, зеркало→оригинал
  (`animcollection.cpp:408-419`): для каждого сгенерированного клипа сначала `Clone().Mirror()`, потом
  сам оригинал.
- **`ConvertToStartFacingForwardIfIdle` работает внутри `LoadFromFile`.** Клипы с idle-входом
  (`GetIncomingVelocity() < 1.8`) разворачиваются лицом вперёд ещё на загрузке — до попадания в
  коллекцию; позиции root, ориентации body, касания и direction-теги вращаются синхронно.
- **Квантование скорости в дескрипторах клипа — верхняя корзина 7.0, не `Velo.Sprint` (8.0).**
  `Animation.BucketVelocity` (`animation.cpp:825-828`/`:902-905`, используется в
  `GetIncoming/OutgoingVelocity`): `<1.8→0`, `[1.8,4.2)→3.5`, `[4.2,6.0)→5.0`, `≥6.0→7.0`. Это отдельная
  функция от `Velo.RangeVelocity`, у которой верхняя корзина честные 8.0 (`Sprint`) — она используется
  для позиций квадрантов `AnimCollection`. Литерал `7.0` — так в оригинале, не опечатка порта.
- **Направление-теги существуют в ДВУХ форматах — bug-for-bug.** После `NormalizeDirectionTags()` (в
  `LoadFromFile`) значение сериализуется БЕЗ пробелов после запятых (`"0.000000,1.000000,0.000000"` —
  инлайн-формат `real_to_str` оригинала, `animation.cpp:1162/1170/1178`). После `Mirror()`/
  `ConvertToStartFacingForwardIfIdle()` то же значение переписывается через `BluntMath
  .GetStringFromVector` — С пробелами (`"0.000000, 1.000000, 0.000000"`, `utils.cpp:213-219`,
  `animation.cpp:337-339,1308-1310`). `BluntMath.GetVectorFromString` парсит оба формата (`Split(',')` +
  `Trim()` на каждом токене) — читатель не должен полагаться на конкретный формат строки.
- **`AnimationApplier.Apply` теперь доворачивает и позицию корня.** Шов, оставленный в фазе 1
  (`position.Rotate2D(baseRot)` не был подключён), закрыт: `!noPos` доворачивает `pos` на `baseRotZ` и
  прибавляет `basePos` (`animation.cpp:413-415,715`). Прежний открытый вопрос закрыт и удалён из
  [[открытые-вопросы]].

## Интероп-гочи GDScript ↔ C#

Мост `load("res://src/gpf/....cs").new()` из GDScript-тестов поймал несколько граблей за задачи 3–6
(общий список интеропа проекта — [[конвенции]], здесь только специфичное для порта):

- **`var x := ...` не выводит тип** из `Variant`-результата C#-метода — парсинг падает. Объявляй тип
  явно (`var mid: Quaternion = anim.SampleRotation(...)`).
- **Мост не переносит C#-дефолт-аргументы** (`default_args` на GDScript-стороне пуст) — `AnimationApplier
  .Apply(skel, anim, frame, offset, noPos: bool = false, baseRotZ: float = 0f, basePos: Vector3 =
  default)` из GDScript зовётся только полным списком из 7 аргументов, иначе parse error (фаза 2
  добавила 7-й параметр `basePos`).
- **`Gpf.Animation` может быть затенено `Godot.Animation`** при `using Godot;` — но только в
  C#-файлах ВНЕ `namespace Gpf` и его вложенных подпространств. Поиск типа в C# сначала обходит
  объемлющие неймспейсы изнутри наружу и лишь потом — using-директивы, поэтому внутри `Gpf`/`Gpf.Lab`
  (как `src/lab/LabMain.cs`) голое `Animation` и так резолвится в `Gpf.Animation` — риска нет
  (проверено минимальной репродукцией). Риск реален для будущего C#-кода в других слоях (например,
  gameplay) с `using Godot;` без `using Gpf;` — там пиши полное `Gpf.Animation`.

## `AnimCollection` и выбор клипа

Фаза 2 добавляет слой над сырыми клипами: загрузку **всей** библиотеки, автогенерацию промежуточных
вариаций и грубый+точный отбор клипа под текущее состояние тела и желаемую команду движения.

**Квадранты.** `AnimCollection` строит 34 квадранта на старте (не из файлов): 1 idle + 3 скорости
(dribble/walk/sprint) × 11 углов (`0°, ±20°, ±45°, ±90°, ±135°, ±179°`). Каждому загруженному клипу
`PrepareAnim` присваивает `quadrant_id` — ближайший квадрант по `outgoing movement` (`GetQuadrantID`,
`animcollection.cpp:865-880`).

**`Load` (`animcollection.cpp:354-487`).** Два независимых источника клипов, оба идут в одну плоскую
`List<Animation>`:
1. Все `.anim` вне `templates/`/`luxury` — по 2 раза (оригинал + `Mirror()`), файлы отсортированы
   `Ordinal` для детерминизма (в C++ порядок диктовала ФС).
2. 10 шаблонов из `templates/` → `GenerateAutoAnims` (`animcollection.cpp:162-352`) перебирает все пары
   шаблонов × 9 направлений (`10×10×9 = 900` кандидатов), режет нелегальные комбинации (макс.
   ускорение/торможение, угол поворота, суммарный разворот тела и т. д.) и bias-интерполирует
   оставшиеся в клип на 25 кадров. Каждый легальный автоген кладётся в коллекцию дважды: зеркало, затем
   оригинал.

После `Load` ищется первый клип `type=="movement"` с `incoming`/`outgoing` velocity `< 1.8` — это
`idleMovementAnimId`, фолбэк-стенд-клип (`humanoidbase.cpp:1416`), возвращается им же `SelectMovementAnim`
при пустом отборе.

**`CrudeSelection` (`animcollection.cpp:494-863`)** — один линейный проход по коллекции, ~12 независимых
секций-фильтров (`CrudeSelectionQuery`): тип функции, вход/выход скорости (строго или с матрицей
нестрогих запретов + линейность), сторона поворота (bug-for-bug `:619`, см. инварианты выше), подбор
мяча, last-ditch, направление тела на входе, направление мяча вход/выход, произвольные строковые
свойства, тип спотыкания, форсированная нога. Каждая секция может только выключить `selectAnim`, не
включить обратно — семантика чистого AND-фильтра оригинала.

**`AnimSelector` — movement-путь (`humanoidbase.cpp:1374-1496`).** `SelectMovementAnim` собирает
`CrudeSelectionQuery` по текущему состоянию (входящая скорость/направление тела, строго), затем цепочкой
`StableSort`/`Keep*` сужает список до одного клипа: `KeepBestDirectionAnims` (ближайший квадрант по
`GetMovementSimilarity`) → опционально `KeepBestBodyDirectionAnims` (если задан `desiredLookAt`) →
`StableSort` по близости `idlelevel` → по совпадению желаемой ноги → по близости входящего направления
тела → по близости входящей скорости. Итоговый `dataSet[0]` — выбранный клип; `SelectMovementDataSet`
отдаёт весь отсортированный список (для тестов/отладки).

Не-movement пути `SelectAnim` (ballcontrol/trap/pass/shot/catch/...) в оригинале — отдельные функции с
собственными `_KeepBest*`-цепочками поверх того же `CrudeSelection`; в порт они **не входят** — см.
ниже.

## Что НЕ портировано (после фазы 2)

- **`Slowdown`/`SmoothPositions`** — мертвы в самом оригинале: `_PrepareAnim` считает
  `expectedFrameCount` (`CalculateAnimDifficulty`), но вызов, который использовал бы его для растяжки
  клипа, закомментирован в C++ (`animcollection.cpp:1186`). Порт честно повторяет это — считает и
  выбрасывает результат (`_ = expectedFrameCount;` в `PrepareAnim`), функцию растяжки не пишет.
  Не «недоделка порта» — оригинал сам этого не делает.
- **Реальный `CalculateFactualSpatialState`** (`humanoidbase.cpp:1650-1720`) — варпинг траектории клипа
  под физически пройденный путь. `walk_lab` вместо него использует **lite**-интеграцию состояния
  (`WalkLabMain.AdvanceToNextAnim`: позиция/угол/скорость/foot/body-direction берутся напрямую из
  дескрипторов завершившегося клипа, без варпинга и без учёта столкновений/физики) — сознательное
  упрощение для приёмки «клипы выбираются осмысленно», не финальная механика. Настоящий варпинг —
  фаза 3. См. [[открытые-вопросы]].
- **Не-movement пути `SelectAnim`** (ballcontrol/trap/pass/shot/header/catch/interfere/trip/sliding/
  special) — только `CrudeSelection` умеет фильтровать по этим `FunctionType`
  (`AnimCollection.CheckFunctionType` знает все 14 типов), но собственных `_KeepBest*`-цепочек и
  публичных `SelectXxxAnim`-обёрток для них нет. Придут вместе со smuggle/физикой мяча (фаза 4+), когда
  появится сам контекст «есть мяч у ног/летит пас/бьём».

## Лаб-сцены: запуск и управление

### `anim_lab` — листалка клипов (фаза 1)

```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" `
  --path "C:\Users\User\Desktop\projects\OpenFootball" res://scenes/lab/anim_lab.tscn
```

`LabMain._Ready` сканирует `res://assets/gpf/animations` рекурсивно, собирает все `.anim` (293 клипа) и
сразу включает первый по алфавиту. Управление:

| Клавиша | Действие |
|---|---|
| `→` / `←` | следующий / предыдущий клип |
| `Space` | пауза |
| `R` | сначала |

HUD (`CanvasLayer`) печатает имя клипа, `type`, `frameCount`, текущий кадр и кадры касаний мяча.
Оранжевые полупрозрачные сферы — маркеры позиций касаний из `extension,football` в пространстве клипа.
Палочник: левая сторона красная, правая синяя (`StickmanRenderer.BoneColor`) — быстрый визуальный тест
на зеркало осей при ревью.

Дисциплина мультиплеера с первого дня порта: `LabMain._Ready` ставит `Engine.PhysicsTicksPerSecond = 100`
— **только в лабе**; матч по-прежнему живёт на дефолтных 60 Гц, перевод матча на 100 Гц — решение
фазы 4 (когда портируется физика мяча). См. [[открытые-вопросы]].

### `walk_lab` — палочник бегает по командам (фаза 2)

```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" `
  --path "C:\Users\User\Desktop\projects\OpenFootball" res://scenes/lab/walk_lab.tscn
```

`WalkLabMain._Ready` грузит всю `AnimCollection` (1452 клипа, ~0.8 с) и стартует с
`idleMovementAnimId`. Клавиши задают **команду** (направление + желаемая скорость), а не прямое
управление — палочник сам подбирает следующий клип через `AnimSelector.SelectMovementAnim` на каждой
границе клипа и доезжает до команды за несколько смен клипа (idle→dribble→walk→sprint максимум по
+1 уровню скорости за клип, как в оригинале):

| Клавиша | Действие |
|---|---|
| `↑` / `↓` / `←` / `→` | направление команды (их оси: вперёд = −Y) |
| `0` / `1` / `2` / `3` | желаемая скорость: idle / dribble / walk / sprint |

HUD печатает имя текущего клипа, `quadrant_id`, номер кадра, состояние (скорость/угол) и саму команду.
Жёлтая стрелка над палочником — визуализация команды. Ввод — сырой `_UnhandledKeyInput`, не
`InputMap`: сцена не участвует в `_setup_inputs()` матча, конфликтов с игровыми биндингами нет.
Интеграция состояния между клипами — **lite**, не настоящий `CalculateFactualSpatialState` (см. «Что НЕ
портировано» выше).

## Тесты

Тринадцать headless-скриптов `tests/check_gpf_*.gd` (запуск поштучно — см. CLAUDE.md, «Один
check-скрипт»). Первые пять — фундамент фазы 1 (парсинг/сэмплирование/метаданные/скелет/применение),
следующие восемь — фаза 2:

- `check_gpf_anim_parse.gd` — CSV-парсинг: порядок треков, разрежённые ключи, `frameCount`, сброс
  состояния при повторном `LoadFromFile` на одном экземпляре, смоук по всему корпусу (293 файла — везде
  ровно 14 треков), негативы (несуществующий путь, битый файл).
- `check_gpf_anim_sample.gd` — интерполяция: точный ключ, lerp позиции корня, slerp между ключами,
  субкадровый lerp+normalize, сентинел `timeOffset=-1`, края (`frame<=0`, экстраполяция за концом клипа,
  трек, кончившийся раньше `frameCount`).
- `check_gpf_anim_meta.gd` — метаданные: касания (кадр+позиция, сортировка по кадру внутри одной
  extension-строки с несколькими касаниями в обратном файловом порядке — сценарий нескольких
  отдельных extension-строк в одном файле тестом не покрыт, по коду там last-wins, см. «Формат
  `.anim`» выше), сброс касаний при повторной загрузке (пиннится тестом), обновление
  `GetAnimType()`/`GetVariable()` при повторной загрузке (пиннится только перезапись `type`; сброс
  протухшего тега вроде `baseanim` не проверен), выход за границы (`GetTouchFrame`/`GetTouchPosition`
  вне диапазона), битый XML-хвост → `false`.
- `check_gpf_skeleton.gd` — 14 костей, иерархия родителей, рест-позы 1:1 `player.object`, базис
  `GpfSpace` (det=+1, «их-вперёд»/«их-верх» → ожидаемые Godot-оси).
- `check_gpf_apply.gd` — `Apply()`: ротация джойнта == ключ клипа, позиция корня, глобальная поза
  (рест-смещение не искажено), `noPos` зануляет X/Y корня, `baseRotZ` доворачивает `body` и (фаза 2)
  доворачивает позицию корня через `Rotate2D`, `basePos` смещает корень аддитивно.
- `check_gpf_bluntmath.gd` — `BluntMath`/`Velo`/эйлеры `QuatUtil`: `Curve`/`ModulateIntoRange`/
  `FixAngle`/`GetAngle2D` (обе перегрузки, включая знак)/`GetNormalized` (по-осевой эпсилон, не по
  длине)/скоростные конверсии/`GetAngles`/`AngleAxis`-круговая проверка.
- `check_gpf_anim_write.gd` — write-API: `Clone` (глубина — мутация клона не трогает оригинал), `SetKeyFrame`
  (рост `frameCount`), `Shift` (±1, drop-правило на границе, синхронный сдвиг касаний), `SetVariable`/
  `SetName`, `SetCurrentFootId`.
- `check_gpf_anim_descriptors.gd` — 12 ленивых дескрипторов на эталонном `movement/walk/045.anim`:
  опорные числа выведены из сырых ключей файла по формулам `animation.cpp:789-1052` (квантование
  скорости, углы, направления тела/движения, нога).
- `check_gpf_anim_mirror.gd` — `Mirror` как инволюция (двойное зеркало == оригинал), смена ноги,
  зеркало касаний, `ConvertToStartFacingForwardIfIdle`, нормализация direction-тегов при загрузке (оба
  формата строки).
- `check_gpf_collection.gd` — каркас `AnimCollection`: 34 квадранта, файловая загрузка ×2 (`566 =
  283×2`), автогены (размер `>566`, чётность `(total-566)`, `priority=1`/`type=="movement"`/25 кадров,
  `autogen_count == total-566`, `GetAutoAnimVelocityMismatchCount()==0`) — на живой библиотеке
  фактический размер коллекции **1452** (566 файловых + 2×443 легальных автогена).
- `check_gpf_crude.gd` — `CrudeSelection`: свойства-фильтры перепроверяются на живой коллекции
  повторной валидацией каждого результата (тип, скорости, сторона, свойства, forced foot и т. д.).
- `check_gpf_selector.gd` — `AnimSelector`: детерминизм `StableSort`, `ForceInto*`-таблицы,
  `CalculateBiasForFastCornering`, осмысленность выбранных клипов (idle→walk, смена направления).
- `check_gpf_walker.gd` — поведенческий тест `walk_lab` целиком: разгон idle→dribble→walk→sprint строго
  по +1 скорости за клип, поворот вправо по команде, торможение по стоп-команде — на реальной
  `AnimCollection`/`AnimSelector`, не моках.

Чистая математика порта (`BluntMath`, `Velo`, `QuatUtil`, дескрипторы `Animation`) намеренно **не
читает `FootballConstants`** — тот же инвариант, что у `PassSystem`/`KeeperLogic` и остального проекта.
См. [[архитектура]].

## Ссылки

[[архитектура]], [[конвенции]], [[открытые-вопросы]]

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

## Статус: фаза 3 (`CalculatePhysicsVector`) завершена и принята

Фазы 1–3 закрыты и приняты визуально человеком. Фаза 3 (варпинг траектории под физику: `SpatialState`,
`PhysicsVector.Calculate` == `CalculatePhysicsVector`, контур состояния `HumanoidBase` — тик, выбор
следующего движения-клипа, apply-буфер; `walk_lab` переведён с lite-дескрипторов фазы 2 на настоящую
интеграцию) код-complete: все 17 headless-тестов `tests/check_gpf_*.gd` зелёные, обе стандартные
headless-валидации без новых категорий ошибок, `dotnet build` чист. **Визуальная приёмка человеком
пройдена 2026-07-30**: разгон/торможение/повороты в `walk_lab.tscn` непрерывны (без квантованных
скачков по бакетам скорости), выпрямление корпуса при возврате в спринт после резкого поворота
опознано как поведение оригинала (см. кламп угла тела в «Инварианты фазы 3»), разница пресетов статов
клавиши `A` заметна на разгоне со стойки (в потолке скорости и радиусе поворота — почти нет, статы
дают там небольшой эффект, см. ниже). Финальное ревью ветки — пройдено (см. `log.md`). Следующая
веха — фаза 4 (smuggle + физика мяча).

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
    ~12 независимых секций); фаза 3 добавила кэш позиций корня per-клип (`_positionCaches`, порт
    `Match::Match`, `match.cpp:86-105`) — параллельный `_animations` список, читают `PhysicsVector` и
    `HumanoidBase`.
  - `CrudeSelectionQuery.cs` (`Gpf.CrudeSelectionQuery`) — параметры запроса `CrudeSelection`: тип
    функции, стопа, сторона, вход/выход скорости, подбор мяча, направление тела/мяча, свойства,
    тип спотыкания, форсированная нога.
  - `AnimSelector.cs` (`Gpf.AnimSelector`) — `StableSort` (единственный разрешённый способ сортировки
    отбора), `ForceInto*`-таблицы, предикаты сравнения клипов и movement-путь `SelectAnim`
    (`SelectMovementAnim`/`SelectMovementDataSet`).
  - `SpatialState.cs` (`Gpf.SpatialState`) — обычный C#-класс (не `RefCounted`, через мост не ходит),
    порт `struct SpatialState` (`humanoidbase.hpp:172-194`): 19 полей физического+анимационного
    состояния тела (позиция/угол/скорость, три варианта движения, relative-body-direction, нога);
    дефолты повторяют `HumanoidBase::ResetPosition` (`humanoidbase.cpp:937-947`, `foot=Right`).
  - `PhysicsVector.cs` (`Gpf.PhysicsVector`) — порт `HumanoidBase::CalculatePhysicsVector`
    (`humanoidbase.cpp:2014-2544`, варпинг траектории клипа под физику игрока: статы, разгон/
    торможение, сопротивление воздуха, макс. скорость, ограничение угла поворота за кадр) + статики
    `CalculateMovementAtFrame`/`StretchSprintTo`/`GetMaxVelocity` (`humanoid_utils.cpp:68-100,129-144`,
    `playerbase.cpp:131-139`). `RefCounted` с сеттерами состояния/статов/конфига и мостом
    `CalculateForAnim`/`GetLastPositions`/`GetLastRotationOffset` для тестов.
  - `HumanoidBase.cs` (`Gpf.HumanoidBase`) — контур состояния movement-пути: порядок тика `Tick`
    (`CalculateSpatialState` → `frameNum++` → выбор следующего клипа на границе → apply-буфер,
    `humanoidbase.cpp:585-711`), `CalculateSpatialState`/`CalculateFactualSpatialState` (`:1622-1737`),
    выбор следующего движения-клипа (`SelectNextMovementAnim`, движение-ветка `SelectAnim`,
    `:1374-1601`). Два места портированы по НАСЛЕДНИКУ `Humanoid` (путь игроков, не базовый
    `HumanoidBase` — судьи): лерп `rotationSmuggleOffset` с 16-кадровым капом (`humanoid.cpp:722-742`)
    и «hax»-формула `desiredBodyDirectionRel` (`humanoid.cpp:1664-1665`) — см. «Инварианты фазы 3».
- `src/lab/` — сцены-приёмники для глаз, к матчу отношения не имеют:
  - `LabMain.cs` (`Gpf.Lab.LabMain`) — корень `scenes/lab/anim_lab.tscn`: сканирует
    `assets/gpf/animations`, листает клипы, держит фикс-тик 100 Гц.
  - `StickmanRenderer.cs` (`Gpf.Lab.StickmanRenderer`) — линии костей по `GetBoneGlobalPose`; левая
    сторона красная, правая синяя (визуальный контроль зеркала).
  - `WalkLabMain.cs` (`Gpf.Lab.WalkLabMain`) — корень `scenes/lab/walk_lab.tscn`: грузит всю
    `AnimCollection`, палочник шагает/бежит/поворачивает по клавишным командам; фаза 3 убрала
    lite-интеграцию фазы 2 — состояние, выбор клипа и apply-буфер целиком за `Gpf.HumanoidBase`, лаба
    только вводит команду, отрисовывает и печатает HUD. Клавиша `A` циклит пресеты статов
    (0.3/0.6/0.9, дефолт 0.6); HUD `v=` печатает непрерывную скорость в м/с (не бакет).
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

## Инварианты фазы 3 (`PhysicsVector`/`HumanoidBase`)

- **Два разных `GetMaxVelocity` в одном `Calculate`.** В начале функции (`:2065`) скорость считается
  один раз и touch-жмётся `*0.92` (`:2066`) — этим локальным значением масштабируется спринтовая часть
  клипа (`StretchSprintTo`, `:2241`). В блоке сопротивления воздуха (`:2422-2427`) оригинал зовёт
  `GetMaxVelocity()` ЗАНОВО, БЕЗ touch-множителя — не переиспользует локальную переменную `:2065`. Порт
  бьёт оба места отдельными вызовами `GetMaxVelocity(_statVelocity)`, не кэширует значение `:2065` для
  `:2422` — bug-for-bug, не оптимизация.
- **`(int)`-усечение кадра (`:2229`).** `CalculateMovementAtFrame` зовётся с
  `(int)(anim.GetEffectiveFrameCount() * adaptedFrameBias)` — оригинальный `(unsigned int)`-каст того
  же выражения (`humanoid_utils.hpp:25`) усекает вниз; C#-`(int)` на неотрицательном float делает то же
  самое. Кастовать именно на границе вызова, не раньше (промежуточный `float` теряет точность иначе).
- **Mod-флаги — `static readonly`, не `const`.** Четыре выключенных мода оригинала
  (`ModCorneringBraking`/`ModMaximumAccelDecel`/`ModBrakeOnTouch`/`ModCheatBodyDirection`, `:2138-2146`)
  и их мёртвые ветки портированы дословно и продолжают компилироваться (`static readonly bool`, не
  `const` — иначе C# ловит недостижимый код как `CS0162`). Не удалять эти ветки при рефакторинге — это
  дословный порт выключенного функционала оригинала, не мусор.
- **`Velo.AnimSprint` (7.0) ≠ литерал 7.0 квантования дескрипторов.** `AnimSprint` — `gamedefines.hpp:23`,
  исходное пространство спринта для `StretchSprintTo` (`:2241`, растяжка клипа под `GetMaxVelocity`);
  литерал `7.0` в `Animation.BucketVelocity` (фаза 2, инварианты выше) — верхняя корзина квантования
  `incoming`/`outgoingVelocity` дескрипторов клипа. Числовое совпадение случайно, роли разные — не
  объединять при рефакторинге.
- **Последние два кадра клипа (`frameCount-2`) — жёсткое квантование idle-ности.** С `timeMs >=
  (frameCount-2)*10` (`:2459`) итоговая скорость кадра принудительно приводится к той же idle/не-idle
  категории, что заявляет `outgoingVelocity` клипа (`:2468-2471`): если клип «должен» кончиться в idle,
  а физика ещё разогнана — обнуляем; если клип не-idle, а физика ещё не разогналась — подтягиваем к
  `Velo.Dribble`. Мягкая недо-версия (`:2464-2467`) — мёртвая ветка (`hardQuantize` всегда `true`,
  `:2461-2462`), портирована, но недостижима.
- **Порядок тика `HumanoidBase.Tick`: `CalculateSpatialState → frameNum++ → выбор клипа → apply`.**
  Именно в этом порядке (`humanoidbase.cpp:585-594` → `:615-637` → `:700-711`): состояние читается ДО
  инкремента кадра (то есть для ещё не показанного кадра предыдущего клипа), кадр инкрементируется, и
  только потом на границе клипа (`frameNum == frameCount-1`) идёт выбор следующего движения; apply-буфер
  собирается в конце тика из уже (возможно) обновлённого `_current`. Перестановка любого шага ломает
  синхронизацию между `positions[frameNum]` и заявленным `frameNum`.
- **`rotationSmuggleOffset` и `desiredBodyDirectionRel` портированы по НАСЛЕДНИКУ `Humanoid`, не по базе
  `HumanoidBase`.** Игроки инстанцируются как `Humanoid` (`player.cpp:88`); голый `HumanoidBase` в
  оригинале — только судьи. Поэтому:
  - лерп `rotationSmuggleOffset` — версия наследника с 16-кадровым ease-in капом
    (`humanoid.cpp:722-742`), НЕ незакапленный лерп базы (`humanoidbase.cpp:687-695`);
  - `desiredBodyDirectionRel` — «hax»-формула наследника (`humanoid.cpp:1664-1665`: упреждение
    `_spatial.Movement * 0.1f`, нормализация ДО `GetRotated2D`, БЕЗ вычета `nextAnim.GetTranslation()`),
    НЕ формула базы (`humanoidbase.cpp:1529-1530`). Перенесено bug-for-bug, включая todo-«hax» оригинала
    — не чинить.
- **`GetMaxVelocity = Sprint * (0.9 + statVelocity * 0.1)`, диапазон `[7.2, 8.0]` ПРИ статах `[0,1]`.**
  Оговорка обязательна: `GetStat` оригинала не клампит статы к `[0,1]` — при статах вне этого диапазона
  (модифицированные/баговые данные) диапазон max-скорости может выйти за `[7.2, 8.0]`. Порт статы тоже
  не клампит (bug-for-bug); диапазон в комментарии — для типичного случая статов `[0,1]`.

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

**Портированный movement-путь — по базовому `HumanoidBase::SelectAnim`, реальные игроки бегут по
переопределению наследника `Humanoid::SelectAnim`** (другие `ForceLinearity`-флаги, другая цепочка
`bySide`/lenient-strict). Выбранный клип поэтому может отличаться от эталон-exe на некоторых
переходах — главный открытый вопрос фазы 3, см. [[открытые-вопросы]].

## Что НЕ портировано (после фазы 3)

- **`Slowdown`/`SmoothPositions`** — мертвы в самом оригинале: `_PrepareAnim` считает
  `expectedFrameCount` (`CalculateAnimDifficulty`), но вызов, который использовал бы его для растяжки
  клипа, закомментирован в C++ (`animcollection.cpp:1186`). Порт честно повторяет это — считает и
  выбрасывает результат (`_ = expectedFrameCount;` в `PrepareAnim`), функцию растяжки не пишет.
  Не «недоделка порта» — оригинал сам этого не делает.
- **Не-movement пути `SelectAnim`** (ballcontrol/trap/pass/shot/header/catch/interfere/trip/sliding/
  special) — только `CrudeSelection` умеет фильтровать по этим `FunctionType`
  (`AnimCollection.CheckFunctionType` знает все 14 типов), но собственных `_KeepBest*`-цепочек и
  публичных `SelectXxxAnim`-обёрток для них нет. Придут вместе со smuggle/физикой мяча (фаза 4+), когда
  появится сам контекст «есть мяч у ног/летит пас/бьём».
- **`ReQueue` не портирован.** `HumanoidBase.Tick` всегда идёт по ветке `Switch` (граница клипа → выбор
  следующего); ветки `ReQueue`/`Trip`/`LocalInterrupt` контура `Process` (`humanoidbase.cpp:592-614`,
  `:646-682`) не тронуты — клип всегда доигрывает до конца, отзывчивость на смену команды ниже
  оригинала (перевыбор реагирует не мгновенно, а раз в клип, ~100–240 мс). Фаза 4.
- **`previousAnim`/`CalculatePredictedSituation`** не портированы — используются только `ReQueue`-путём
  и предсказанием ситуации на будущий клип, которых пока нет в порте. Фаза 4.
- **Smuggle-механика (`Action*`/`Movement*Smuggle`, `PositionOffsetMovement`) — поля есть, формулы их
  учитывают, но они нули.** `SpatialState`/внутреннее состояние `HumanoidBase` несут все смаггл-поля, и
  формулы `PhysicsVector.Calculate`/`CalculateSpatialState` читают их bug-for-bug, но код, который их
  УСТАНАВЛИВАЕТ (реакция на столкновения/удержание мяча/касание), не портирован — поэтому сейчас они
  тождественно 0 и физику варпинга не меняют. Исключение — `rotationSmuggleOffset`: тот считается по-
  настоящему (лерп begin/end наследника, см. «Инварианты фазы 3» выше). Смаггл — фаза 4.
- **`decayingPositionOffset` как живущее поле.** `PhysicsVector.SetTouchContext` уже принимает
  `decayingPositionOffsetLength` и формула `powerFactor` (`:2084`) его честно использует, но ни один
  вызывающий код порта не обновляет это значение от реальных столкновений — лаба всегда передаёт 0.
  Станет живым, когда появятся толкучка/удержание мяча (фаза 4).

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

Дисциплина мультиплеера с первого дня порта — фикс-тик **100 Гц**. Лабы ставят его из кода
(`LabMain._Ready`/`WalkLabMain._Ready`: `Engine.PhysicsTicksPerSecond = 100`), а с фазы 4 (задача 9)
он стоит **глобально** в `project.godot` — значит и матч. Наследие GDScript-геймплея, затюненного при
60 Гц, приведено к тику через `TickScale` (драг мяча, `MAGNUS_DECAY`, `DRIBBLE_ROLL_DRAG`,
`DRIBBLE_CONTROL_LERP`, `KEEPER_DIVE_DECAY`; предохранитель подтверждения гола переведён в секунды) —
см. [[константы]]. Приёмка ощущения после перевода — за человеком, [[открытые-вопросы]].

### `walk_lab` — палочник бегает по командам (варпнутые траектории, фаза 3)

```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" `
  --path "C:\Users\User\Desktop\projects\OpenFootball" res://scenes/lab/walk_lab.tscn
```

`WalkLabMain._Ready` грузит всю `AnimCollection` (1452 клипа, ~0.8 с) и заводит `Gpf.HumanoidBase`
(`ResetSituation` — старт на `idleMovementAnimId`, кадр 0). Клавиши задают **команду** (направление +
желаемая скорость), а не прямое управление — на каждой границе клипа `HumanoidBase.Tick` сам подбирает
следующий клип (`SelectNextMovementAnim` → `AnimSelector`) и варпит его траекторию под текущую физику
(`PhysicsVector.Calculate`); скорость доезжает до команды непрерывно, не бакетами (idle→dribble→walk→
sprint по-прежнему максимум +1 уровень скорости клипа за смену, как в оригинале):

| Клавиша | Действие |
|---|---|
| `↑` / `↓` / `←` / `→` | направление команды; **две стрелки сразу — диагональ** (45° / 135°) |
| `0` / `1` / `2` / `3` | желаемая скорость: idle / dribble / walk / sprint |
| `A` | циклит пресет статов (все шесть статов разом): 0.3 → 0.6 → 0.9 → 0.3…, дефолт 0.6 |

**Медленной ходьбы в датасете нет** — три движущиеся походки GameplayFootball это трусца/бег/спринт
(`dribble` 3.5, `walk` 5.0, `sprint` 8.0 м/с; даже самая медленная — бег с мячом ~12,6 км/ч), поэтому
`1/2/3` дают бег с тремя скоростями, а не «шаг → бег». HUD печатает непрерывную скорость `v=` в м/с (не
бакет — физика варпинга даёт промежуточные значения между дескрипторами клипов, в отличие от lite-версии
фазы 2).

Направление читается **опросом зажатых стрелок** каждый физкадр (`PollDirectionInput`), а не дискретным
событием — так набираются диагонали, и `←`/`→` соответствуют экрану (клавиша `←` = «их-влево» `(1,0,0)`,
которое базис `GpfSpace` зеркалит в экранный «влево»; прямое присваивание `Left→(-1,0,0)` уводило бы
персонажа вправо). Скорость и пресет статов — дискретно в `_UnhandledKeyInput`. HUD печатает имя
текущего клипа, `quadrant_id`, номер кадра, состояние (скорость в м/с, угол), саму команду и активный
пресет статов. Жёлтая стрелка над палочником — визуализация команды. Ввод — не `InputMap`: сцена не
участвует в `_setup_inputs()` матча, конфликтов с игровыми биндингами нет.

Интеграция состояния между клипами — **настоящая**: `WalkLabMain` не хранит и не вычисляет позицию/
угол/скорость сама, всё отдаёт `Gpf.HumanoidBase` через apply-буфер тика (`humanoidbase.cpp:700-711`);
lite-дескрипторное приближение фазы 2 удалено. См. «Инварианты фазы 3» выше.

## Тесты

Семнадцать headless-скриптов `tests/check_gpf_*.gd` (запуск поштучно — см. CLAUDE.md, «Один
check-скрипт»). Первые пять — фундамент фазы 1 (парсинг/сэмплирование/метаданные/скелет/применение),
следующие восемь — фаза 2, последние четыре — фаза 3 (варпинг траектории):

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
- `check_gpf_walker.gd` — поведенческий тест `walk_lab` целиком на настоящей интеграции
  `Gpf.HumanoidBase`/`AnimCollection`/`AnimSelector` (не моках): разгон idle→dribble→walk→sprint,
  непрерывность float-скорости (физика варпинга даёт промежуточные значения между бакетами — было
  наоборот у lite-версии фазы 2), поворот вправо по команде, торможение по стоп-команде.
- `check_gpf_physics_foundation.gd` — примитивы `Vector3` (`NormalizeMax`/`GetNormalizedTo`/
  `GetNormalizedMax`, `vector3.cpp:190-228`) и кэш позиций корня `AnimCollection` (`match.cpp:86-105`)
  на эталонном `movement/walk/045.anim` — опорные числа из сырых ключей файла.
- `check_gpf_physics_helpers.gd` — хелперы `CalculateMovementAtFrame`/`StretchSprintTo`/`GetMaxVelocity`
  (`humanoid_utils.cpp:68-100,129-144`, `playerbase.cpp:131-139`) на синтетических позициях, все
  ожидания перевычислены по формулам C++ прямо в тесте.
- `check_gpf_physics_vector.gd` — `PhysicsVector.Calculate` == `CalculatePhysicsVector`
  (`humanoidbase.cpp:2014-2544`) на живой `AnimCollection`: инварианты и перевычисления формул на
  выходах (растяжка спринта, поворот к желаемому углу, сопротивление воздуха, квантование последних
  кадров).
- `check_gpf_humanoid_state.gd` — `HumanoidBase.Tick`/`CalculateSpatialState`/
  `CalculateFactualSpatialState` (`humanoidbase.cpp:585-711,1622-1737`): жёсткие ассерты первого тика из
  сырого кэша idle-клипа, порядок apply-буфера, смена клипа на границе.

Чистая математика порта (`BluntMath`, `Velo`, `QuatUtil`, дескрипторы `Animation`, `PhysicsVector`)
намеренно **не читает `FootballConstants`** — тот же инвариант, что у `PassSystem`/`KeeperLogic` и
остального проекта. См. [[архитектура]].

## Ссылки

[[архитектура]], [[конвенции]], [[открытые-вопросы]]

# Технический разбор ядра GameplayFootball (по коду) — приложение к порт-роадмапу

**Дата:** 2026-07-29
**Тип:** тех-справка (первоисточник фактуры; не редактировать).
**К спеку:** [2026-07-29-gameplayfootball-port-roadmap-design.md](./2026-07-29-gameplayfootball-port-roadmap-design.md)
**Источник:** автоматический разбор кодовой базы `C:\Users\User\Desktop\projects\FootballCPP` (актуальный
форк) со сверкой по `GameplayFootball` и `football` (Google Research Football). Пути даны от корня FootballCPP.

> Примечание: номера строк — на момент разбора 2026-07-29 (форки на своих HEAD). При работе сверяться с
> фактическим кодом — файлы могут разъехаться. Это карта, а не контракт.

---

## 1. Формат `.anim` файлов

**Расположение:** `data/media/animations/` — 17 категорий, 293 файла. Распределение: `movement` 43,
`ballcontrol` 45, `trap` 40, `pass` 36, `deflect` 28, `shot` 17, `highpass` 15, `movement_special` 16,
`trip` 19, `interfere` 7, `sliding` 6, `celebration` 3, `special` 1, `templates` 10.

**Структура (текстовый CSV + XML-хвост).** Пример `data/media/animations/movement/walk/045.anim`:
строка `player` (root, только позиция: `player,frame,x,y,z,...`), строки джойнтов (только ориентация,
кватернион `name,frame,qx,qy,qz,qw,...`), `extension,football,frame,x,y,z...` (позиция мяча в кадрах
касания), затем XML-теги `<balldirection>`, `<incomingballdirection>`, `<steps>`, `<type>` и др.

**Парсинг:** `src/utils/animation.cpp:1109` (`Animation::Load`) → `:1076` (`LoadData`). Строка 0 всегда
`player` (`:1096-1102`), строки 1..13 — джойнты-кватернионы (`:1085-1092`). Кадры **разрежены** (0,6,12,
19,24), между ними slerp/lerp (`GetInterpolatedValues`, `:179`). **1 кадр = 10 мс** (движок 100 Гц).
Типичная длина 24–26 кадров (~один шаг); максимум — `trap/walk/highballs/D135_chest_jump_decel.anim`
(111 кадров).

**14 треков, порядок фиксирован:** `player`(root,поз) → `body` → `middle` → {`neck`,
`left_shoulder`→`left_elbow`, `right_shoulder`→`right_elbow`}; `body` → {`left_thigh`→`left_knee`→
`left_ankle`, `right_thigh`→`right_knee`→`right_ankle`}. Код рассчитывает на этот порядок
(`animation.cpp:789-1029`).

**Extension football:** `src/utils/animationextensions/footballanimationextension.cpp:109` (`Load`),
чтение `GetFirstTouch`/`GetTouch`/`GetTouchPos` (`:147-186`).

**XML-метаданные (частота по библиотеке):** `<type>` 296, `<steps>` 107, `<baseanim>` 77,
`<incomingballdirection>` 75, `<balldirection>` 75, `<touch_maxpowerfactor>` 48,
`<incomingballdirection_maxdeviation>` 41, `<touch_difficultyfactor>` 37,
`<outgoing_special_state>`/`<incoming_special_state>` 32/4, `<outgoing_retain_state>`/
`<incoming_retain_state>` 29/20, `<outgoingballdirection_maxdeviation>` 20, `<triptype>` 19,
`<bumpdirection>` 19, `<lastditch>` 14, `<idlelevel>` 2, `<touchfoot>`/`<forcedfoot>` 1/1.

**Важно: скорости и углы в файле НЕ хранятся** — вычисляются из root-трека при загрузке и кэшируются:
`GetIncomingVelocity`/`GetOutgoingVelocity` (`animation.cpp:816`/`:893`, дельта первых/последних ключей
×100, квантование в 4 корзины: `<1.8→0`, `[1.8,4.2)→3.5`, `[4.2,6.0)→5.0`, `≥6.0→7.0`),
`GetOutgoingAngle` (`:914`), `GetIncomingBodyAngle`/`GetOutgoingBodyAngle` (`:964`/`:993`).
Обогащение в `AnimCollection::_PrepareAnim` (`animcollection.cpp:1171`): `animdifficultyfactor`
(`CalculateAnimDifficulty`, `:977`), `touchframe` + `touch_bodypart` (`AddExtraTouches`, `:883`),
`quadrant_id` (`GetQuadrantID`, `:865`). **Зеркалирование:** каждый клип ×2 (`Mirror()`,
`animation.cpp:1246`; вызов `animcollection.cpp:444-449`).

---

## 2. AnimCollection / выбор анимации

**Файлы:** `src/onthepitch/player/humanoid/animcollection.{hpp,cpp}` (217 + 1275 строк).

**Загрузка** (`AnimCollection::Load`, `:354`): утилитарный скелет `media/objects/players/player.object`
(`:361-371`); из `templates/` (10) генерируются movement-анимации `GenerateAutoAnims` (`:162`,
комбинаторика t1×t2×9 направлений с правилами легальности `:188-222`); остальные 283 грузятся ×2 (файлы
«luxury» пропускаются `:437`). Итог — `std::vector<Animation*>` порядка 1000–2000 записей.

**Квадранты** (`:61-106`): 1 idle + 3 скорости × 11 углов = 34. Скорости `dribble 3.5/walk 5.0/sprint
8.0` (`src/gamedefines.hpp:18-21`), углы 0,±20,±45,±90,±135,±179°.

**Это НЕ motion matching.** Двухфазный отбор: жёсткая булева фильтрация + лексикографическая сортировка
по цепочке предикатов. Взвешенная функция по позам (`GetRatedDataSet`, `humanoidbase.cpp:1232-1371`)
**закомментирована**. Сравнение по семантическим дескрипторам, не по позам скелета.

**Фаза 1 — `CrudeSelection`** (`animcollection.cpp:494`): линейный проход, булев фильтр по
`CrudeSelectionQuery` (`animcollection.hpp:106-164`). Критерии (строки в animcollection.cpp): тип функции
510-514, входная скорость 529-575, выходная 585-589, сторона поворота 594-623, retain-state 640-647,
last-ditch 652-658, входной корпус 663-752, направление прилёта мяча 757-786 (Z-компонента ×0.4 перед
сравнением, `:766-770`), направление вылета 791-807, special/retain/vars 812-819, trip 824-828, forced
foot 834-857. Запрос строит `Humanoid::SelectAnim` (`humanoid.cpp:1244-1357`) / упрощённо
`HumanoidBase::SelectAnim` (`humanoidbase.cpp:1383-1411`).

**Фаза 2 — сортировки** (`humanoid.cpp:1558-1636` / `humanoidbase.cpp:1425-1496`): серия `stable_sort` в
обратном порядке важности. Предикаты (humanoidbase.cpp): `CompareMovementSimilarity` (:1871, ядро
`GetMovementSimilarity` :1826), `CompareBodyDirectionSimilarity` (:1906),
`CompareIncomingVelocitySimilarity` (:1793), `CompareIncomingBodyDirectionSimilarity` (:1893),
`CompareFootSimilarity` (:1779), `CompareTripDirectionSimilarity` (:1972), `CompareBallDirectionSimilarity`
(:1982), `CompareBaseanimSimilarity` (:1988), `CompareNumericVariable` (:2009). Прунинг:
`_KeepBestDirectionAnims` (:1103), `_KeepBestBodyDirectionAnims` (:1174). Квантование углов
`ForceIntoAllowed*`/`ForceIntoPreferred*` (:2547-2606, таблицы :63-97).

**Фаза 3 — физпроверка достижимости для действий с мячом:** `GetBestCheatableAnimID` (см. §3).

**Частота:** `SelectAnim` при `interruptAnim != None` — на последнем кадре (`humanoidbase.cpp:592`) либо
re-queue, т.е. ~каждые 24 кадра (240 мс) на игрока. Линейный скан ~1500 клипов × 22 игрока — главная
статья расхода при порте.

---

## 3. Humanoid: варпинг, smuggle, слои

**Файлы:** `humanoid.cpp` (2486), `humanoidbase.cpp` (2606), `humanoid_utils.cpp` (520),
`humanoidbase.hpp` (395).

**Идея:** анимация НЕ проигрывается как есть. При выборе вычисляется новая траектория корня
(`Anim::positions`, `humanoidbase.hpp:112`) — точка на кадр, учитывает физику/статы/желание. Оригинал
позиций в `Match::animPositionCache` (`match.cpp:85-105`). Анимация применяется с `noPos=true`
(`humanoid.cpp:768-772`, `humanoidbase.cpp:702-711`).

**3.1 Варпинг — `CalculatePhysicsVector`** (`humanoidbase.cpp:2014-2544`). Симуляция по 10 мс на кадр
(`:2206`). Механизмы (строки): `physicsBias` 2119-2136 (movement/ballcontrol/trap/sliding=1.0,
interfere=0.5, **pass/highpass/shot/deflect/special=0.0**, trip=0.5/0.0), `outgoingSwitchBias` 2031-2050,
поворот к желаемому углу 2151-2176 (лимиты `maxAngleMod_*`=0.125π обычно, 0.2π·bonus при касании, 0.5π
подкат), «pointiness/лаг» 2213-2228 (`lagExp` из `physical_agility`), растяжение спринта 2238-2245
(`StretchSprintTo`, `humanoid_utils.cpp:129`), лимиты замедл/ускор 2248-2257 (`maxSlower`=1.6/1.2),
cornering 2341-2370, `maxChange` 2372-2405 (0.03 м/с за мс базово), сопротивление воздуха игрока
2410-2451 (`accelPower`=11.0·mult), квантование выходной скорости 2459-2473, `rotationOffset_ret`
2499-2503. Штрафы: `difficultyPenaltyFactor` (:2074-2080), `powerFactor` (:2082-2084).

**3.2 Smuggle («IK»)** — `GetBestCheatableAnimID` (`humanoid.cpp:1999-2323`): для каждого клипа считать
траекторию (`:2034`); перебор тач-фреймов от среднего (`:2065-2073`); предсказанная позиция мяча
`currentMentalImage->GetBallPrediction(animTouchFrame*10)` (`:2099`); позиция мяча из клипа,
масштаб по росту `animBallPos.z = animBallHeight*(playerHeight/1.92)` (`:2112-2118`); непрерывная проверка
±(−6..+3 мс) (`:2122-2126`); `actionSmuggleVec3D = ballPos − animBallPos` (`:2129`); проверка высоты
`ballDistanceZ<0.22` (`:2149`); 2D-радиус `GetBodyBallDistanceAdvantage` (`:1859-1997`, база
`radiusFactor=0.3·(1−awkwardness)`, ×1.8 deflect/×1.4 interfere/×1.3 pass-shot/×0.2 sliding; зона
смещается назад по `behindVector` :1911-1921; эллипс `lateralRadiusFactor=0.6−0.3·(v/vmax)^0.7`
:1935-1945; глобальный `cheatFactor=0.5` :43); частичный сброс smuggle (`:2247-2315`,
`cheatDiscardDistance=0.02`, гасит переднюю компоненту `:2291-2303`, демпфирование в толкучке `:2314`);
накопление — косинусный ease (`humanoid.cpp:675-694`). Плюс `movementSmuggle` (`:2326`, применение
`:699-718`) и `rotationSmuggle` (`:723-742`). **Это НЕ IK-решатель — корневой варп всего скелета.**

**3.3 Процедурные оффсеты костей (слои)** — `CalculateGeomOffsets` (`humanoid.cpp:783-1086`), механизм
`BiasedOffset` (`animation.hpp:46-54`), применение `Animation::Apply` (`:425-433`). Флаги `:798-805`:
`adaptLegsToTrueVelocity` (0.7, :814-849, компенсация фут-слайдинга), `adaptBodyToBallPosition` (0.5,
:854-893), `adaptArmsToOpp` (0.9, :898-1000+, руки-щит), `adaptLegToTouchPos` — **выключен** (:802,
был бы настоящий IK ноги). Формальных слоёв верх/низ нет, только per-bone bias.

**3.4 Сглаживание переходов** — `Animation::Apply` (`:370-722`): интерполяция кадров (`:389-405`),
`MovementHistory` (`:442-458`), слерп к анимации `beginBias` (`:460`, сильное сглаживание первые 8
кадров), лимит `maxDiff_per_ms=5π·0.001` (`:496`), `smoothFactor` 0.6/1.0 (`humanoidbase.cpp:655`),
temporal smoother нод (`:785-796`). Начальный доворот корпуса `rotationSmuggle.begin`
(`humanoidbase.cpp:1580`, константы `humanoid.cpp:54-55`).

---

## 4. Физика мяча

**Файл:** `src/onthepitch/ball.cpp` (615) / `ball.hpp` (121). Ядро `CalculatePrediction()`
(`:137-537`): симуляция 3000 мс вперёд (`ballPredictionSize_ms`, `gamedefines.hpp:56`), шаг 0.01 с,
кэш каждые 10 мс (`:524`). Первый шаг = новое состояние (`:527-531`) — ИИ бесплатно получает точный
прогноз.

**Константы** (`ball.cpp:23-29`): `bounce=0.62`, `linearBounce=0.06`, `drag=0.015`, `friction=0.04`,
`linearFriction=1.6`, `gravity=−9.81`, `grassHeight=0.025`. Радиус мяча `0.11` (хардкод).

**Формулы** (строки): гравитация 175, сопротивление воздуха 180-183 (`|v|'=|v|−drag·|v|²·dt`), влияние
травы 186-191 (`grassBias=clamp(1−(z−0.11)/grassHeight,0,1)^0.7`), отскок 197-205
(`vz'=max(−vz·0.62−0.06,0)`, `frictionFactor` усиливает трение при ударе о землю), трение газона 210-227,
штанги 240-328 (`postRadius=0.07`, `postAbsorbInv=0.8`), сетка 333-410 (**вырезаем — используем наш
NetSim**), вращение от качения 421-451 (`ωx=vy/r`), обратное влияние вращения 454-480 (подкрученный мяч
уезжает вбок при касании газона), **магнус** 486-501 (`swerveAmount=sin(clamp(|v|,0,70)·π·0.94)^2.6`,
`swerve=(normalize(v)·swerveAmount·30)×(−rotVec)`).

Касание: `Ball::Touch` (`:91`), `SetRotation` (`:119`). Векторы удара — `humanoid_utils.cpp`:
`GetBallControlVector` (:208), `GetTrapVector` (:334), `GetShotVector` (:354). Модель ошибки касания
`GetDifficultyFactors` (:146, штрафы за сбитость/разницу скоростей/удалённость/перехват; ×(1−
technical_ballcontrol·0.5)·**random(0.5,1.0)** ← seeded-RNG при порте). Коллизии мяч↔тело — не ODE, а
AABB по геометриям тела `Match::CheckBallCollisions` (`match.cpp:1926-2045`). ODE в геймплее НЕ
используется.

---

## 5. Матч-флоу и ИИ

**Матч** (`match.cpp` 2232 / `match.hpp` 378): `Process()` (`:851`), тик 10 мс (`:962`). Порядок:
`CheckBallCollisions` (:1926) → `referee->Process()` (`referee.cpp`, 446 строк) → `ball->Process()` →
создание `MentalImage` (`AIsupport/mentalimage.cpp`, 106; история 30 снимков; ИИ видит мир с задержкой
`GetMentalImage(GetReactionTime_ms())`, `humanoid.cpp:117`) → `teams[i]->Process()` → `Player::Process` →
`Humanoid::Process` → `CalculateBestPossessionTeamID` → `CheckHumanoidCollisions` (:1484,:1550) → голы/
время/замены/реплей. Фазы `Process/PreparePutBuffers/FetchPutBuffers/Put` — двухпоточная симуляция/
отрисовка.

**ИИ трёхуровневый.** (1) **`TeamAIController`** (`teamAIcontroller.cpp` 1042) — командный:
`GetAdaptedFormationPosition` (:293), `CalculateDynamicRoles` (:430, венгерский алгоритм `hungarian_init`
:486), `CalculateManMarking` (:587), `ApplyOffsideTrap` (:642), `PrepareSetPiece` (:670). **НЕ портируем
сейчас — заглушка под 2×2.** (2) **`ElizaController`** (`elizacontroller.cpp` 1147, наследник
`PlayerController` 634) — индивидуальный: `RequestCommand` (:51, приоритетная if/else-цепочка),
утилитарный пас-скоринг `_GetPassingOdds` (:1025,:1037), `GetSupportPosition_ForceField` (:610),
`GetOnTheBallCommands` (:809, очередь `PlayerCommand`). (3) **Стратегии вне мяча**
`controller/strategies/offtheball/{default_def,default_mid,default_off,goalie_default}.cpp`.

**Интерфейс AI→анимация:** `struct PlayerCommand` (`gamedefines.hpp:175-231`) — `desiredFunctionType`,
`desiredDirection`, `desiredVelocityFloat`, `desiredLookAt`, `touchInfo`, `tripType`. Чистый шов, при
порте сохраняется. Утилиты `AIsupport/AIfunctions.cpp` (1299).

---

## 6. Скелет и модели

**Скелет** `data/media/objects/players/player.object` (XML). Иерархия и локальные позиции (метры):
`player`(root) → `body`(0,0,**0.96**) → `middle`(0,0,0.15) → `neck`(0,−0.03,0.5); `middle` →
`left_shoulder`(0.16,−0.01,0.48)→`left_elbow`(−0.01,0,−0.33), симметрично right; `body` →
`left_thigh`(**0.087**,0,−0.01)→`left_knee`(0,0,**−0.42**)→`left_ankle`(0,−0.04,**−0.44**), симметрично
right. **13 костей + root.** Нет многосегментного позвоночника, ключиц, кистей/пальцев, носков; одна
`neck` несёт голову. Базовая поза — `data/media/animations/base.anim.util` (все клипы применяются
поверх; `HumanoidBase::PrepareFullbodyModel`, `humanoidbase.cpp:209-219`; есть `base.inverse.anim.util`,
`straight.anim.util`). Рост — `zMultiplier=playerHeight/1.92` (`humanoidbase.cpp:102`).

**⚠️ Для фазы 1 палочник строить ровно по этим пропорциям** — тогда позиции касания мяча из метаданных
совпадут со стопами и «нога у мяча» проверяема сразу.

**Модели:** формат **`.ase`** (3ds Max ASCII, загрузчик `src/loaders/aseloader.cpp`). Сегментные куски
`models/{pelvis,trunk,head,upperarm,lowerarm,upperleg,lowerleg,foot}.ase` (утилитарный скелет для расчёта
позиций тела при анализе касания). Реальная скинированная — `fullbody.ase` (377 КБ) + `fullbody.object`,
8 материалов, низкополи. **Веса скиннинга в vertex colors** (`jointID=floor(color·0.1)`, max 3 кости,
`humanoidbase.cpp:316-330`). Скиннинг на **CPU** каждый кадр (`UpdateFullbodyModel`, `:437-561`).
**Их меши не берём.**

**Совместимость с Mixamo** (концептуальная, не 1:1): `body`→Hips, `middle`→Spine/1/2 (свернуть 3→1),
`neck`→Neck+Head (свернуть), `left_shoulder`→**LeftArm** (не LeftShoulder!), `left_elbow`→LeftForeArm,
`left_thigh`→LeftUpLeg, `left_knee`→LeftLeg, `left_ankle`→LeftFoot; кисти/пальцы/носки отбросить.
**Три ловушки ретаргета:** (1) оси — у движка Z-вверх, «вперёд»=`(0,−1,0)`, `FixAngle()` (+π/2,
`animcollection.hpp:50`); (2) базовая поза — ротации относительно `base.anim.util`, не рест-позы меша
(нужна компенсация дельты по кости); (3) один `middle` против трёх Spine (распределить вращение).
Ретаргет через Godot `BoneMap`+`SkeletonProfileHumanoid` реален; конвертер `.anim`→`.tres` ~200-400
строк. **Smuggle работает на уровне корня — точность касаний переживает кривой ретаргет автоматически.**

---

## 7. Масштаб и отделимость

**Объём** (строк): `src/onthepitch` **20 121** (ядро геймплея), `src/systems` 9 729 (GL/OpenAL/ODE —
НЕ нужно), `src/menu` 8 507 (НЕ нужно), `src/utils` 8 019 (в т.ч. `animation.cpp` 1712), `src/base`
4 235 (математика), `src/scene` 3 586, прочее ~5 400. Всего 69 761.

Анимационная подсистема в узком смысле ~**9 753** строк (`animation.cpp` 1712 + extensions 275 +
`animcollection` 1492 + `humanoidbase` 3001 + `humanoid` 2542 + `humanoid_utils` 554 + `animation.hpp`
177). Плюс мяч 736, матч 2610, ИИ ~4 400.

**Зависимости от Blunted2 — тонкие, заменяемые:** `Vector3`/`Quaternion`/утилиты (`src/base/math/*`,
самодостаточно → Godot + ~100 строк, **другая ось «вверх» и знак углов**); `Node` граф сцены → `Skeleton3D`
+ `Node3D`; `XMLTree` → парсер ~50 строк; `Properties` → `Dictionary`; `.ase`/`ObjectLoader` нужен только
на старте для `touch_bodypart` → офлайн-препроцессинг; boost → std/Ref; `TemporalSmoother` не нужен;
Log/Config тривиально. **НЕ нужно:** `src/systems`, `src/menu`, `src/framework`, `src/league`, `src/data`.

**Отделимость высокая.** Единственная точка сцепления `Animation` с движком — `Animation::Apply()`
(`animation.cpp:370`, пишет в `map<string,intrusive_ptr<Node>>`) → в Godot `Skeleton3D::
set_bone_pose_rotation`. **Три реальные сложности:** (1) система координат Z-up пронизывает весь код —
хранить внутреннее «анимационное» пространство как есть, конвертировать на границе с Godot; (2) фикс-тик
100 Гц — все константы привязаны (`maxChange=0.03/мс`, кадр=10 мс) → `physics_ticks_per_second=100`;
(3) boost → std/Godot.

**Оценка порта** (анимации+мяч+humanoid, без AI и матч-флоу): ~10 000 строк C++ с механической
конвертацией математики + переписыванием `Animation::Apply` под `Skeleton3D`. **Главный риск — не код, а
тюнинг ~200 взаимно откалиброванных констант** (`cheatFactor 0.5`, `maxChange 0.03`, `physicsBias` по
типам, `lagExp`, `maxAngleMod_*`); расхождение в порядке применения → «плавающие»/«дёргающиеся» игроки.

**Рекомендуемый порядок порта:** `Animation` (формат+интерполяция) → `AnimCollection` (загрузка +
CrudeSelection) → `CalculatePhysicsVector` → `GetBestCheatableAnimID`/smuggle → `CalculateGeomOffsets`.
Первые два дают проверяемый результат («игрок проигрывает выбранный клип»), третий — узнаваемое движение.

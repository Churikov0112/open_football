class_name TickScale
extends RefCounted

## Приведение множителей-«за физкадр» к текущему фикс-тику.
##
## Матч живёт на фикс-тике 100 Гц (`physics/common/physics_ticks_per_second`) — мультиплеер-дисциплина
## порта GameplayFootball. Но затухания (драг мяча, `MAGNUS_DECAY`, `DRIBBLE_ROLL_DRAG`,
## `KEEPER_DIVE_DECAY`, сглаживание удержания мяча) применяются РАЗ ЗА ФИЗКАДР и затюнены ощущением
## при 60 Гц: `0.985^60` за секунду против `0.985^100` — вдвое больший драг. Числа поэтому хранятся в
## 60-герцевом виде (тюнинг-смысл сохраняется), а к реальному шагу приводятся здесь: потеря за
## СЕКУНДУ остаётся той, на какой всё настраивалось.
##
## Чистая математика без autoload: `FootballConstants` не читается, число приходит параметром.
## (Звать `FootballConstants.per_tick` было нельзя — static-функция через имя autoload не
## компилируется, в отличие от констант.)

const TUNED_TICKS := 60.0   # частота, на которой затюнены все множители-за-физкадр


## Множитель-за-физкадр (0..1), затюненный при 60 Гц → множитель под текущий фикс-тик.
static func factor(at_60hz: float) -> float:
	return pow(at_60hz, TUNED_TICKS / float(Engine.physics_ticks_per_second))


## То же для веса lerp-сглаживания: инвариант — доля, «доезжаемая» за секунду, а не за кадр.
static func lerp_weight(at_60hz: float) -> float:
	return 1.0 - factor(1.0 - at_60hz)


## Окно/дедлайн, отмеренное в кадрах при 60 Гц → кадров при текущем тике (окно в СЕКУНДАХ то же).
## Нужно check-тестам: они считают физкадры вручную, и на 100 Гц их бюджеты сжимались бы в 0.6×.
static func frames(at_60hz: int) -> int:
	return int(round(float(at_60hz) * float(Engine.physics_ticks_per_second) / TUNED_TICKS))

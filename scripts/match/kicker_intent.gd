class_name KickerIntent
extends RefCounted
## Источник намерения бьющего в стандарте (per-actor шов). Контроллер потребляет ЭТО вместо
## прямых Input.*. Варианты (charge_start_variant) — enum самого контроллера, поэтому ИИ-реализация
## позже отдаёт id варианта, не зная имён кнопок. База — no-op дефолты.

## Прицел: x = боковой (move_left/right), y = вертикаль/глубина (move_forward/back, инвертирован).
func aim_axis() -> Vector2:
	return Vector2.ZERO

## Смена ноги в этом кадре: -1 левая, +1 правая, 0 нет.
func foot_switch() -> int:
	return 0

## В этом кадре стартовал заряд с выбранным вариантом → id варианта (>=0), иначе -1.
## Реализация латчит стартовую кнопку для последующего коммита.
func charge_start_variant() -> int:
	return -1

## Латченный заряд должен выстрелить в этом кадре (стартовая кнопка отпущена).
func charge_committed() -> bool:
	return false

## Модификатор зажат (чип у пенальти; резерв под wall/air-варианты).
func modifier_held() -> bool:
	return false

## Вторичное действие в этом кадре (corner_call). По умолчанию нет.
func secondary() -> bool:
	return false

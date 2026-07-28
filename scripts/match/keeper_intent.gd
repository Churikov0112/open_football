class_name KeeperIntent
extends RefCounted
## Источник намерения вратаря в стандарте (per-actor шов, симметричен KickerIntent). Контроллер
## читает dive_zone() ОДИН раз в момент удара (action_contact бьющего) — коммита у вратаря нет,
## момент нырка принадлежит контроллеру. База — no-op (центр).

## Выбранная зона нырка (PenaltyLogic.Zone).
func dive_zone() -> int:
	return PenaltyLogic.Zone.CENTER

## Желаемое боковое смещение вратаря по линии в фазе прицеливания (AIM), [-1..1]; 0 = стоять.
## Отдельно от dive_zone: позиционирование телом, а не выбор зоны прыжка.
func step_lateral() -> float:
	return 0.0

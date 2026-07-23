class_name KeeperIntent
extends RefCounted
## Источник намерения вратаря в стандарте (per-actor шов, симметричен KickerIntent). Контроллер
## читает dive_zone() ОДИН раз в момент удара (action_contact бьющего) — коммита у вратаря нет,
## момент нырка принадлежит контроллеру. База — no-op (центр).

## Выбранная зона нырка (PenaltyLogic.Zone).
func dive_zone() -> int:
	return PenaltyLogic.Zone.CENTER

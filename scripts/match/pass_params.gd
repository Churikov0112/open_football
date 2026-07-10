class_name PassParams
extends RefCounted

## Тип паса. Пять значений, но по механике всего два семейства: «в точку мяча»
## (SHORT_GROUND/LOB) и «на ход» (THROUGH_GROUND/THROUGH_AIR). WALL — короткий пас + режим
## give-and-go у отдавшего. Тип задаёт только параметры ниже, не отдельный код-путь.
enum PassType { SHORT_GROUND, THROUGH_GROUND, LOB, WALL, THROUGH_AIR }

var power: float = 0.0          # базовая скорость мяча, м/с (для низовых)
var peak_height: float = 0.0    # высота дуги, м (0 → низом)
var extra_lead: float = 0.0     # доп. вынос точки «на ход», м
var is_air: bool = false        # верхом (баллистика) vs низом
var is_wall: bool = false       # запускать give-and-go у отдавшего

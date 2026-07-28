class_name BoundaryLogic
extends Object
## Чистая геометрия границ поля. НИКОГДА не читает FootballConstants — тюнинг параметрами.
## Классифицирует выход мяча за линии и даёт точки рестарта.

enum Exit { NONE = 0, TOUCHLINE = 1, GOAL_LINE_NEG = 2, GOAL_LINE_POS = 3 }

## Мяч ПОЛНОСТЬЮ пересёк линию (центр дальше линии на радиус). Аут (боковая) проверяется
## первым; за лицевой засчитывается ТОЛЬКО мимо створа (|x| > goal_half_width) — иначе это
## взятие ворот, не аут. Угловой корнер (за обе линии) отдаём боковой (детерминированно).
static func classify(ball_pos: Vector3, half_len: float, half_width: float, goal_half_width: float, ball_radius: float) -> int:
	if absf(ball_pos.x) > half_width + ball_radius:
		return Exit.TOUCHLINE
	if ball_pos.z < -(half_len + ball_radius) and absf(ball_pos.x) > goal_half_width:
		return Exit.GOAL_LINE_NEG
	if ball_pos.z > half_len + ball_radius and absf(ball_pos.x) > goal_half_width:
		return Exit.GOAL_LINE_POS
	return Exit.NONE

## Точка вброса: проекция на ближайшую боковую линию (x = ±half_width), z сохраняется.
static func throw_in_spot(ball_pos: Vector3, half_width: float, ball_radius: float) -> Vector3:
	var sx := 1.0 if ball_pos.x >= 0.0 else -1.0
	return Vector3(sx * half_width, ball_radius, ball_pos.z)

## Точка углового: ближний угловой флаг на пересечённой лицевой, сдвинут inset внутрь поля.
static func corner_spot(ball_pos: Vector3, half_len: float, half_width: float, exit: int, inset: float, ball_radius: float) -> Vector3:
	var gz := -half_len if exit == Exit.GOAL_LINE_NEG else half_len
	var sx := 1.0 if ball_pos.x >= 0.0 else -1.0
	var sz := 1.0 if gz < 0.0 else -1.0   # inset внутрь поля от лицевой
	return Vector3(sx * (half_width - inset), ball_radius, gz + sz * inset)

## Точка удара от ворот: центр линии вратарской площади на пересечённой лицевой.
static func goal_kick_spot(exit: int, half_len: float, ga_depth: float, ball_radius: float) -> Vector3:
	var gz := -half_len if exit == Exit.GOAL_LINE_NEG else half_len
	var into := 1.0 if gz < 0.0 else -1.0
	return Vector3(0.0, ball_radius, gz + into * ga_depth)

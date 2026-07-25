class_name KickoffLogic
extends Object
## Кикофф — чистая статическая геометрия. НИКОГДА не читает FootballConstants (тюнинг —
## параметрами вызывающего), как FreeKickLogic/PassSystem/GoalKickLogic. Headless-тестируема.

## Прижимает pos к своей половине (own_sign = -attack_z_sign), если pos оказался на чужой.
## margin — минимальный отступ от центральной линии на своей стороне после прижатия.
## На самой линии (z=0) или уже на своей половине — pos не меняется.
static func clamp_to_own_half(pos: Vector3, attack_z_sign: float, margin: float) -> Vector3:
	var own_sign := -attack_z_sign
	if pos.z * own_sign >= 0.0:
		return pos
	return Vector3(pos.x, pos.y, margin * own_sign)


## Знаковый угол (рад, вокруг вертикали) от from_dir к to_dir — на сколько и в какую сторону
## повернуть from_dir, чтобы совпасть с to_dir. Знак совместим с FreeKickLogic.rotate_heading:
## при stick_x = -signf(результат) один шаг rotate_heading сдвигает heading В СТОРОНУ to_dir
## (см. AIKickoffIntent, где это используется для расчёта длительности доворота стиком).
static func signed_angle_xz(from_dir: Vector3, to_dir: Vector3) -> float:
	return from_dir.signed_angle_to(to_dir, Vector3.UP)


## Жеребьёвка старта матча: кто разводит первым, 1 или 2. Чистая функция (не читает
## FootballConstants) специально ради тестируемости при фиксированном seed — вызывающий сам
## решает, сидировать rng или randomize()-ить.
static func coin_flip(rng: RandomNumberGenerator) -> int:
	return 1 if rng.randf() < 0.5 else 2


## Позиция и heading кикера кикоффа: вплотную к мячу (центр поля), смещён на ЧУЖУЮ половину
## (attack_z_sign-направление) на offset, лицом на свою половину (-attack_z_sign). ЕДИНАЯ формула —
## используется и контроллером при расстановке, и диспетчером при построении геометрии для
## AIKickoffIntent (тому нужна финальная позиция кикера ДО того, как контроллер её выставит —
## intent передаётся в start() раньше, чем _setup() успевает что-либо разместить). Вынос в общую
## чистую функцию убирает дублирование формулы между двумя местами.
static func kicker_placement(attack_z_sign: float, offset: float, body_y: float) -> Dictionary:
	return {
		"pos": Vector3(0.0, body_y, attack_z_sign * offset),
		"base_heading": Vector3(0.0, 0.0, -attack_z_sign),
	}

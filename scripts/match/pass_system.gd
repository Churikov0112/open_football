class_name PassSystem
extends Object

## Выбор цели паса: партнёр, лучше всего совпадающий с направлением прицела (стика), с
## упреждением по скорости и штрафом за дистанцию. Возвращает индекс в mate_* или -1.
## Все данные — POD; узлы держит вызывающий (индекс → узел).
static func select_target(passer_pos: Vector3, aim_dir: Vector3,
		mate_positions: PackedVector3Array, mate_velocities: PackedVector3Array,
		lead_gain: float, dot_bias: float, max_range: float) -> int:
	var aim := aim_dir
	aim.y = 0.0
	if aim.length() < 0.001:
		return -1
	aim = aim.normalized()
	var best_idx := -1
	var best_score := -1000.0
	for i in range(mate_positions.size()):
		var predicted: Vector3 = mate_positions[i] + mate_velocities[i] * lead_gain
		var diff := predicted - passer_pos
		diff.y = 0.0
		var dist := diff.length()
		if dist > max_range or dist < 0.001:
			continue
		var score := diff.normalized().dot(aim) - dot_bias * (dist / max_range)
		if score > best_score:
			best_score = score
			best_idx = i
	return best_idx

## Точка упреждения: куда бить, чтобы прийти к движущейся цели. Время полёта = дистанция /
## скорость мяча; плюс доп. вынос вперёд по скорости цели (для паса «на ход»). Стоящая цель
## (vel≈0) → точка == позиции цели (extra_lead игнорируется, некуда вести).
static func lead_point(target_pos: Vector3, target_vel: Vector3, passer_pos: Vector3,
		ball_speed: float, extra_lead: float) -> Vector3:
	var flat_to := target_pos - passer_pos
	flat_to.y = 0.0
	var travel := flat_to.length() / maxf(ball_speed, 0.001)
	var point := target_pos + target_vel * travel
	var vflat := target_vel
	vflat.y = 0.0
	if vflat.length() > 0.001:
		point += vflat.normalized() * extra_lead
	point.y = target_pos.y
	return point

## Низовой пас: плоская скорость к цели, величиной power (м/с).
static func launch_ground(from: Vector3, to: Vector3, power: float) -> Vector3:
	var dir := to - from
	dir.y = 0.0
	if dir.length() < 0.001:
		return Vector3.ZERO
	return dir.normalized() * power

## Навес/верховой пас: баллистическая стартовая скорость, приземляющая мяч в to с пиком
## peak_height, под гравитацию gravity. Старт и приземление на одной высоте (плоское поле):
## v_y = sqrt(2*g*h); полное время полёта T = 2*v_y/g; горизонталь = flat/T.
static func launch_lob(from: Vector3, to: Vector3, peak_height: float, gravity: float) -> Vector3:
	var vy := sqrt(2.0 * gravity * maxf(peak_height, 0.001))
	var flight := 2.0 * vy / gravity
	var flat := to - from
	flat.y = 0.0
	var horizontal := flat / maxf(flight, 0.001)
	return Vector3(horizontal.x, vy, horizontal.z)

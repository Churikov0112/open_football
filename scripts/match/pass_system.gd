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

## Куда бежать принимающему: точка перехвата ПО ХОДУ мяча (ball_pos + ball_vel*lead_time), а НЕ
## текущая позиция мяча — иначе на медленном мяче принимающий бежит назад к отдавшему («из ноги в
## ногу»). Спецкейс: если мяч летит почти прямо В или ОТ принимающего (|dot| > on_line_dot),
## упреждать вбок незачем — встречаем на линии (возвращаем ball_pos). Пустая скорость → ball_pos.
static func receive_point(receiver_pos: Vector3, ball_pos: Vector3, ball_vel: Vector3,
		lead_time: float, on_line_dot: float) -> Vector3:
	var bv := Vector3(ball_vel.x, 0.0, ball_vel.z)
	if bv.length() < 0.001:
		return ball_pos
	var to_ball := Vector3(ball_pos.x - receiver_pos.x, 0.0, ball_pos.z - receiver_pos.z)
	if to_ball.length() > 0.001 and absf(to_ball.normalized().dot(bv.normalized())) > on_line_dot:
		return ball_pos
	return ball_pos + bv * lead_time

## Низовой пас: плоская скорость к цели, величиной power (м/с).
static func launch_ground(from: Vector3, to: Vector3, power: float, up: float = 0.0) -> Vector3:
	var dir := to - from
	dir.y = 0.0
	if dir.length() < 0.001:
		return Vector3.ZERO
	return dir.normalized() * power + Vector3.UP * up

## Скорость низового паса: чтобы мяч ВСЕГДА проходил distance м, скорость выводится из
## дистанции и времени полёта (не задаётся абсолютно). Заряд лерпит время полёта между
## max_time (слабый заряд, медленный/мягкий пас) и min_time (полный заряд, быстрый/жёсткий
## пас) — так пас одинаково доходит и на 5м, и на 40м, отличается лишь скорость подачи.
static func ground_pass_speed(distance: float, charge_ratio: float,
		min_time: float, max_time: float, min_speed: float, max_speed: float) -> float:
	var travel_time := lerpf(max_time, min_time, clampf(charge_ratio, 0.0, 1.0))
	var speed := distance / maxf(travel_time, 0.001)
	return clampf(speed, min_speed, max_speed)

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

## Успеет ли соперник перехватить пас в коридоре. Проецируем соперника на луч паса:
## along — вдоль (0..длина), across — поперёк. Коридор расширяется с дистанцией
## (half + along*spread). Соперник перехватывает, если внутри коридора И добегает до линии
## не позже мяча. Возврат — время перехвата (сек) или INF.
static func interception_time(pass_from: Vector3, pass_to: Vector3, ball_speed: float,
		opp_pos: Vector3, opp_speed: float, corridor_half_width: float, corridor_spread: float) -> float:
	var line := pass_to - pass_from
	line.y = 0.0
	var length := line.length()
	if length < 0.001:
		return INF
	var dir := line / length
	var rel := opp_pos - pass_from
	rel.y = 0.0
	var along := rel.dot(dir)
	if along < 0.0 or along > length:
		return INF
	var closest := pass_from + dir * along
	var across := (opp_pos - closest)
	across.y = 0.0
	var across_dist := across.length()
	var half := corridor_half_width + along * corridor_spread
	if across_dist > half:
		return INF
	var ball_time := along / maxf(ball_speed, 0.001)
	var opp_time := across_dist / maxf(opp_speed, 0.001)
	if opp_time <= ball_time:
		return ball_time
	return INF

## Максимальный угол разброса (градусы): растёт с дистанцией, гасится «лёгкостью» assist.
static func scatter_degrees(spread_base: float, assist: float, distance: float, distance_ref: float) -> float:
	var dist_factor := clampf(distance / maxf(distance_ref, 0.001), 0.2, 1.5)
	return spread_base * (1.0 - clampf(assist, 0.0, 1.0)) * dist_factor

## Повернуть плоское направление вокруг оси Y на случайный угол в пределах ±spread_deg.
## RNG передаётся снаружи → детерминизм в тестах (seed).
static func apply_scatter(flat_dir: Vector3, spread_deg: float, rng: RandomNumberGenerator) -> Vector3:
	if spread_deg <= 0.0:
		return flat_dir
	var angle := deg_to_rad(rng.randf_range(-spread_deg, spread_deg))
	return flat_dir.rotated(Vector3.UP, angle)

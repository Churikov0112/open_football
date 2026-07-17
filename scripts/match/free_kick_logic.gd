class_name FreeKickLogic
extends Object
## Чистая математика штрафного. НИКОГДА не читает FootballConstants — тюнинг параметрами.

## Горизонтальное направление от точки удара к центру ворот (нормализованное).
static func base_heading(from: Vector3, goal_center: Vector3) -> Vector3:
	var d := Vector3(goal_center.x - from.x, 0.0, goal_center.z - from.z)
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD

## Повернуть heading вокруг вертикали на stick_x*speed*dt, кламп к сектору ±arc от base.
## stick_x > 0 (вправо) → поворот вправо (по часовой вокруг UP).
static func rotate_heading(cur: Vector3, base: Vector3, stick_x: float, speed: float, dt: float, arc: float) -> Vector3:
	var next := cur.rotated(Vector3.UP, -stick_x * speed * dt)
	var ang := base.signed_angle_to(next, Vector3.UP)
	ang = clampf(ang, -arc, arc)
	return base.rotated(Vector3.UP, ang).normalized()

## Вектор запуска прямого удара: горизонталь по heading, угол вылета и скорость растут с зарядом.
static func launch_velocity(heading: Vector3, charge: float, min_speed: float, max_speed: float, min_elev_deg: float, max_elev_deg: float) -> Vector3:
	var c := clampf(charge, 0.0, 1.0)
	var speed := lerpf(min_speed, max_speed, c)
	var elev := deg_to_rad(lerpf(min_elev_deg, max_elev_deg, c))
	var flat := Vector3(heading.x, 0.0, heading.z).normalized()
	var dir := flat * cos(elev) + Vector3.UP * sin(elev)
	return dir * speed

## Угловой разброс (град) растёт с зарядом.
static func scatter_degrees(charge: float, min_deg: float, max_deg: float) -> float:
	return lerpf(min_deg, max_deg, clampf(charge, 0.0, 1.0))

## Случайное угловое отклонение вектора запуска (yaw+pitch) в пределах ±spread_deg.
static func apply_scatter(vel: Vector3, spread_deg: float, rng: RandomNumberGenerator) -> Vector3:
	if spread_deg <= 0.0:
		return vel
	var yaw := deg_to_rad(rng.randf_range(-spread_deg, spread_deg))
	var v := vel.rotated(Vector3.UP, yaw)
	var right := Vector3(v.z, 0.0, -v.x)
	if right.length() > 0.001:
		var pitch := deg_to_rad(rng.randf_range(-spread_deg, spread_deg))
		v = v.rotated(right.normalized(), pitch)
	return v

## Curl-вектор из накопленного бокового ввода стика (интеграл stick_x*dt за окно нажатие→контакт).
## Возвращает Vector3(0,0,mag) — mag в конвенции ball._curl.z (боковая, Magnus вдоль left=horiz×UP).
static func curl_from_stick(accum: float, scale: float, max_curl: float) -> Vector3:
	var mag := clampf(accum * scale, -max_curl, max_curl)
	return Vector3(0.0, 0.0, mag)

## Ближняя/дальняя штанги относительно точки удара (side-aware по горизонтали).
static func near_far_posts(from: Vector3, goal_center_x: float, half_width: float, goal_line_z: float) -> Array:
	var left_post := Vector3(goal_center_x - half_width, 0.0, goal_line_z)
	var right_post := Vector3(goal_center_x + half_width, 0.0, goal_line_z)
	if from.distance_to(left_post) <= from.distance_to(right_post):
		return [left_post, right_post]
	return [right_post, left_post]

## Число игроков в стенке: 0 дальше far_dist, max_n у near_dist и ближе, линейно между.
static func wall_count(dist_to_goal: float, far_dist: float, near_dist: float, min_n: int, max_n: int) -> int:
	if dist_to_goal > far_dist:
		return 0
	if dist_to_goal <= near_dist:
		return max_n
	var t := (dist_to_goal - near_dist) / (far_dist - near_dist)   # 0 у near → 1 у far
	return int(round(lerpf(float(max_n), float(min_n), t)))

## Центр ряда стенки и единичный right-вектор вдоль ряда. Стенка на линии мяч→ближняя штанга,
## в wall_dist от мяча; если ворота ближе wall_dist — на линию ворот (центр створа), on_line=true.
static func wall_line(from: Vector3, near_post: Vector3, goal_line_z: float, wall_dist: float, y: float) -> Dictionary:
	var to_near := Vector3(near_post.x - from.x, 0.0, near_post.z - from.z)
	if to_near.length() <= wall_dist:
		return {"center": Vector3(0.0, y, goal_line_z), "right": Vector3.RIGHT, "on_line": true}
	var dir := to_near.normalized()
	var center := from + dir * wall_dist
	center.y = y
	var right := dir.cross(Vector3.UP).normalized()
	return {"center": center, "right": right, "on_line": false}

## Позиции тел стенки в ряд, центрированы относительно center вдоль right с интервалом spacing.
static func wall_body_positions(center: Vector3, right: Vector3, count: int, spacing: float) -> Array:
	var out := []
	for i in range(count):
		var offset := (float(i) - float(count - 1) * 0.5) * spacing
		out.append(center + right * offset)
	return out

## Прыгать ли стенке: как только мяч ЛЕТИТ на стенку и близок по времени (t <= jump_rise_time) —
## прыгаем, НЕЗАВИСИМО от высоты (пик прыжка ≈ приход мяча). Тогда низкий удар проходит ПОД
## прыгнувшей стенкой (гол!), средний перекрывается поднятыми телами, высокий перелетает. Мяч,
## летящий ОТ стенки, игнорируем.
static func wall_should_jump(ball_pos: Vector3, ball_vel: Vector3, wall_center: Vector3, jump_rise_time: float) -> bool:
	var horiz := Vector3(ball_vel.x, 0.0, ball_vel.z)
	if horiz.length() < 0.5:
		return false
	var to_wall := Vector3(wall_center.x - ball_pos.x, 0.0, wall_center.z - ball_pos.z)
	var along := to_wall.dot(horiz.normalized())
	if along <= 0.0:
		return false
	var t := along / horiz.length()
	return t > 0.0 and t <= jump_rise_time

## Если pos ближе min_dist к center (по горизонтали) — выталкивает наружу вдоль (pos-center)
## до ровно min_dist (y не трогает). Иначе возвращает pos без изменений. Правило 9.15 м:
## соперники не должны стоять ближе к мячу вообще, по любому направлению (не только в
## коридоре удара) — в отличие от push_out_of_corridor, это радиус, а не полоса.
static func push_out_of_radius(pos: Vector3, center: Vector3, min_dist: float) -> Vector3:
	var d := Vector3(pos.x - center.x, 0.0, pos.z - center.z)
	var len := d.length()
	if len >= min_dist:
		return pos
	var dir := d / len if len > 0.01 else Vector3.RIGHT
	var out := center + dir * min_dist
	out.y = pos.y
	return out

## Если pos лежит внутри коридора (от from до to, полу-ширина half_width) — выталкивает его
## перпендикулярно наружу коридора (сохраняя продвижение вдоль линии, y не трогает). Иначе
## возвращает pos без изменений. Используется, чтобы никто не стоял между бьющим и стенкой.
static func push_out_of_corridor(pos: Vector3, from: Vector3, to: Vector3, half_width: float) -> Vector3:
	var seg := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var seg_len := seg.length()
	if seg_len < 0.01:
		return pos
	var dir := seg / seg_len
	var rel := Vector3(pos.x - from.x, 0.0, pos.z - from.z)
	var t := clampf(rel.dot(dir), 0.0, seg_len)
	var closest := from + dir * t
	var perp := Vector3(pos.x - closest.x, 0.0, pos.z - closest.z)
	var d := perp.length()
	if d >= half_width:
		return pos
	var side := perp / d if d > 0.01 else dir.cross(Vector3.UP).normalized()
	var out := closest + side * half_width
	out.y = pos.y
	return out

## Оптимальная позиция вратаря: по биссектрисе угла обстрела (между штангами), выход step_out
## от линии в поле. Возвращает мировую точку на высоте ground_y.
static func keeper_position(from: Vector3, near_post: Vector3, far_post: Vector3, half_width: float, step_out: float, goal_line_z: float, ground_y: float) -> Vector3:
	var dir_near := (near_post - from).normalized()
	var dir_far := (far_post - from).normalized()
	var bis := (dir_near + dir_far).normalized()
	var pos := from
	if absf(bis.z) > 0.001:
		var t := (goal_line_z - from.z) / bis.z
		pos = from + bis * t
	var into := signf(from.z - goal_line_z)
	pos.z += into * step_out
	pos.x = clampf(pos.x, -half_width, half_width)
	pos.y = ground_y
	return pos

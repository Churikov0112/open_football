class_name KeeperPlayLogic
extends Object
## Чистая математика раздачи/позиции вратаря. НИКОГДА не читает FootballConstants — тюнинг параметрами.

## Кламп позиции в штрафную площадь. into = знак в поле от линии ворот (+1 если ворота на -Z).
## X ограничивается ±pa_half_width; глубина (rel от линии) — [0, pa_depth].
static func clamp_to_penalty_area(pos: Vector3, goal_line_z: float, into: float, pa_depth: float, pa_half_width: float) -> Vector3:
	var out := pos
	out.x = clampf(pos.x, -pa_half_width, pa_half_width)
	var rel := (pos.z - goal_line_z) * into
	rel = clampf(rel, 0.0, pa_depth)
	out.z = goal_line_z + into * rel
	return out

## Автонаведение руки: индекс своего для раската/броска. Целевой банд дистанции = lerp(near,far,charge);
## скор = совпадение направления с прицелом − близость к банду. -1 если кандидатов нет.
static func select_hand_target(keeper_pos: Vector3, aim_dir: Vector3, mate_positions: Array, charge: float, near_dist: float, far_dist: float) -> int:
	var want := lerpf(near_dist, far_dist, clampf(charge, 0.0, 1.0))
	var best := -1
	var best_score := -INF
	for i in mate_positions.size():
		var to: Vector3 = mate_positions[i] - keeper_pos
		to.y = 0.0
		var d := to.length()
		if d < 0.01:
			continue
		var dir := to / d
		var dot := dir.dot(aim_dir)
		var dist_pen := absf(d - want) / maxf(far_dist, 0.01)
		var score := dot - dist_pen
		if score > best_score:
			best_score = score
			best = i
	return best

## Вынос к центру поля: горизонталь вдоль into (к средней линии), фикс скорость + лифт.
static func clear_center_vector(into: float, speed: float, lift: float) -> Vector3:
	return Vector3(0.0, 0.0, into) * speed + Vector3.UP * lift

## Направленный вынос: горизонталь по aim_flat, скорость по заряду, + лифт. Пустой aim → вперёд (+Z).
static func directed_clear_vector(aim_flat: Vector3, charge: float, min_speed: float, max_speed: float, lift: float) -> Vector3:
	var dir := Vector3(aim_flat.x, 0.0, aim_flat.z)
	if dir.length() < 0.01:
		dir = Vector3(0.0, 0.0, 1.0)
	dir = dir.normalized()
	var speed := lerpf(min_speed, max_speed, clampf(charge, 0.0, 1.0))
	return dir * speed + Vector3.UP * lift

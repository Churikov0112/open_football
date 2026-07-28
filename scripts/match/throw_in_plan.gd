class_name ThrowInPlan
extends Object
## Чистый скорер вброса из аута. НИКОГДА не читает FootballConstants — всё тюнингом-параметрами.
## Навес всегда (руками), без вариантов ground/lob. Отделён от проигрывания (AIThrowInIntent).

## Возврат: { "index": int, "power_ratio": float, "aim_dir": Vector3 }.
## При index == -1 выход самодостаточен: aim_dir = flat(into) (прямо в поле), power_ratio = 0.5.
static func choose(spot: Vector3, into: Vector3, attack_dir: Vector3, aim_arc: float,
		candidates: Array, opponents: Array,
		min_dist: float, max_dist: float,
		ball_speed: float, opp_speed: float, corridor_hw: float, corridor_spread: float,
		upfield_weight: float) -> Dictionary:
	var flat_into := Vector3(into.x, 0.0, into.z).normalized()
	var flat_attack := Vector3(attack_dir.x, 0.0, attack_dir.z).normalized()
	var best_index := -1
	var best_score := -INF
	var best_ratio := 0.5
	var best_dir := flat_into
	for i in candidates.size():
		var cand: Vector3 = candidates[i]
		var vec := Vector3(cand.x - spot.x, 0.0, cand.z - spot.z)
		var dist := vec.length()
		if dist < 0.001:
			continue
		var dir := vec / dist
		# Гейт сектора: цель вне ±aim_arc от перпендикуляра в поле — недостижима прицелом.
		if absf(KickoffLogic.signed_angle_xz(flat_into, dir)) > aim_arc:
			continue
		# Гейт дальности.
		if dist < min_dist or dist > max_dist:
			continue
		# Гейт коридора: перехваченный соперником — исключается (навес v1 коридор как наземный).
		var blocked := false
		for opp in opponents:
			if PassSystem.interception_time(spot, cand, ball_speed, opp, opp_speed, corridor_hw, corridor_spread) != INF:
				blocked = true
				break
		if blocked:
			continue
		var score := upfield_weight * dir.dot(flat_attack)
		if score > best_score:
			best_score = score
			best_index = i
			best_ratio = clampf(inverse_lerp(min_dist, max_dist, dist), 0.0, 1.0)
			best_dir = dir
	return { "index": best_index, "power_ratio": best_ratio, "aim_dir": best_dir }

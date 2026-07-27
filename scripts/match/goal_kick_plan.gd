class_name GoalKickPlan
extends Object
## Чистый скорер удара от ворот. НИКОГДА не читает FootballConstants — всё тюнингом-параметрами.
## Выбирает получателя среди своих + вариант (0=ground/1=lob) + силу (power_ratio) + направление
## доворота (aim_dir). Отделён от проигрывания (AIGoalKickIntent) — тестируется без симуляции.

## Возврат: { "index": int, "variant": int, "power_ratio": float, "aim_dir": Vector3 }.
## index = лучший кандидат или -1. При -1 выход ВСЁ РАВНО валиден: aim_dir = attack_dir,
## variant = 1 (lob), power_ratio = 1.0 (дальний вынос вперёд — удар от ворот всегда состоится).
static func choose(spot: Vector3, attack_dir: Vector3, aim_arc: float,
		candidates: Array, opponents: Array,
		ground_min: float, ground_max: float, lob_min: float, lob_max: float,
		pass_min_time: float, pass_max_time: float, pass_min_speed: float, pass_max_speed: float,
		opp_speed: float, corridor_hw: float, corridor_spread: float,
		upfield_weight: float) -> Dictionary:
	var flat_attack := Vector3(attack_dir.x, 0.0, attack_dir.z).normalized()
	var best_index := -1
	var best_score := -INF
	var best_variant := 1
	var best_ratio := 1.0
	var best_dir := flat_attack
	for i in candidates.size():
		var cand: Vector3 = candidates[i]
		var vec := Vector3(cand.x - spot.x, 0.0, cand.z - spot.z)
		var dist := vec.length()
		if dist < 0.001:
			continue
		var dir := vec / dist
		# Гейт дуги: цель за клампом прицела контроллера (±aim_arc) недостижима — иначе ИИ навёлся
		# бы в край сектора, а не на цель.
		if absf(KickoffLogic.signed_angle_xz(flat_attack, dir)) > aim_arc:
			continue
		var upfield := dir.dot(flat_attack)
		var variant := -1
		var ratio := 0.0
		# Ground, если в диапазоне И коридор чист низом.
		if dist >= ground_min and dist <= ground_max:
			ratio = clampf(inverse_lerp(ground_min, ground_max, dist), 0.0, 1.0)
			var ball_speed := PassSystem.ground_pass_speed(dist, ratio,
				pass_min_time, pass_max_time, pass_min_speed, pass_max_speed)
			if _lane_clear(spot, cand, ball_speed, opponents, opp_speed, corridor_hw, corridor_spread):
				variant = 0
		# Иначе lob, если в диапазоне навеса (навес летит над защитой — коридор не считаем).
		if variant == -1 and dist >= lob_min and dist <= lob_max:
			ratio = clampf(inverse_lerp(lob_min, lob_max, dist), 0.0, 1.0)
			variant = 1
		if variant == -1:
			continue   # недостижим ни одним вариантом по дальности
		var score := upfield_weight * upfield
		if score > best_score:
			best_score = score
			best_index = i
			best_variant = variant
			best_ratio = ratio
			best_dir = dir
	return {
		"index": best_index,
		"variant": best_variant,
		"power_ratio": best_ratio,
		"aim_dir": best_dir,
	}

static func _lane_clear(from: Vector3, to: Vector3, ball_speed: float, opponents: Array,
		opp_speed: float, corridor_hw: float, corridor_spread: float) -> bool:
	for opp in opponents:
		if PassSystem.interception_time(from, to, ball_speed, opp, opp_speed, corridor_hw, corridor_spread) != INF:
			return false
	return true

class_name CornerPlan
extends Object
## Чистый скорер углового. НИКОГДА не читает FootballConstants — всё тюнингом-параметрами.
## Lob-first: навес в штрафную на реального тиммейта предпочитается; наземный короткий пас — только
## когда цель слишком близка для навеса (вне нижней кромки lob-диапазона + запас) или навес недостижим.
## Выбирает получателя среди кандидатов + вариант (0=ground/1=lob) + силу (power_ratio) + направление
## доворота (aim_dir). Отделён от проигрывания (AICornerIntent) — тестируется без симуляции.

## Возврат: { "index": int, "variant": int, "power_ratio": float, "aim_dir": Vector3 }.
## index = лучший кандидат или -1. При -1 выход ВСЁ РАВНО валиден: aim_dir = base_heading (в створ),
## variant = 1 (lob), power_ratio = 0.5 (навес в центр штрафной — угловой всегда состоится).
static func choose(spot: Vector3, base_heading: Vector3, attack_dir: Vector3, aim_arc: float,
		candidates: Array, opponents: Array,
		ground_min: float, ground_max: float, lob_min: float, lob_max: float, lob_bias: float,
		pass_min_time: float, pass_max_time: float, pass_min_speed: float, pass_max_speed: float,
		opp_speed: float, corridor_hw: float, corridor_spread: float,
		upfield_weight: float) -> Dictionary:
	var flat_base := Vector3(base_heading.x, 0.0, base_heading.z).normalized()
	var flat_attack := Vector3(attack_dir.x, 0.0, attack_dir.z).normalized()
	var best_index := -1
	var best_score := -INF
	var best_variant := 1
	var best_ratio := 0.5
	var best_dir := flat_base
	for i in candidates.size():
		var cand: Vector3 = candidates[i]
		var vec := Vector3(cand.x - spot.x, 0.0, cand.z - spot.z)
		var dist := vec.length()
		if dist < 0.001:
			continue
		var dir := vec / dist
		# Гейт дуги: цель за клампом поворота heading контроллера (±aim_arc от базового) недостижима.
		if absf(KickoffLogic.signed_angle_xz(flat_base, dir)) > aim_arc:
			continue
		var upfield := dir.dot(flat_attack)
		var variant := -1
		var ratio := 0.5
		# Lob-first: навес, если цель в пределах lob-диапазона (нижняя кромка расширена запасом bias —
		# цель чуть ближе lob_min всё равно навешивается на мин. заряде). Навес летит над защитой —
		# коридор не считаем.
		if dist <= lob_max and dist >= lob_min - lob_bias:
			ratio = clampf(inverse_lerp(lob_min, lob_max, dist), 0.0, 1.0)
			variant = 1
		# Иначе наземный короткий пас, если в диапазоне И коридор чист низом.
		elif dist >= ground_min and dist <= ground_max:
			var g_ratio := clampf(inverse_lerp(ground_min, ground_max, dist), 0.0, 1.0)
			var ball_speed := PassSystem.ground_pass_speed(dist, g_ratio,
				pass_min_time, pass_max_time, pass_min_speed, pass_max_speed)
			if _lane_clear(spot, cand, ball_speed, opponents, opp_speed, corridor_hw, corridor_spread):
				variant = 0
				ratio = g_ratio
		if variant == -1:
			continue   # недостижим ни одним вариантом
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

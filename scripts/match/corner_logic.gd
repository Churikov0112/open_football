class_name CornerLogic
extends Object
## Чистая математика углового. НИКОГДА не читает FootballConstants — тюнинг параметрами.

## Сторона углового по X игрока в момент активации: +1 (правый угол) / -1 (левый).
static func side_for_player(player_x: float) -> float:
	return -1.0 if player_x < 0.0 else 1.0

## Точка мяча в углу: чуть внутрь поля от точного угла (на inset по обеим осям), y на радиусе мяча.
## into = в поле от лицевой линии (-signf(goal_line_z)); goal_line_z<0 → into=+1.
static func corner_spot(side: float, half_width: float, goal_line_z: float, inset: float, ball_radius: float) -> Vector3:
	var into := -signf(goal_line_z)
	return Vector3(side * (half_width - inset), ball_radius, goal_line_z + into * inset)

## «Открытой» ногой в поле: правый угол → левая нога, левый угол → правая. Ключ ACTION_CLIPS.
static func foot_for_side(side: float) -> String:
	return "penalty_l" if side > 0.0 else "penalty_r"

## Высота дуги навеса по стику Y ∈ [-1,1]: вверх(+1)=head (низкая/быстрая), 0=standard, вниз(-1)=svecha (высокая/долгая).
static func peak_for_stick_y(stick_y: float, peak_head: float, peak_standard: float, peak_svecha: float) -> float:
	var y := clampf(stick_y, -1.0, 1.0)
	if y >= 0.0:
		return lerpf(peak_standard, peak_head, y)
	return lerpf(peak_standard, peak_svecha, -y)

## 2 позиции целей в штрафной (ближняя/дальняя зона по X), на глубине depth в поле от линии.
static func box_target_positions(goal_line_z: float, into: float, lateral: float, depth: float, y: float) -> Array:
	var z := goal_line_z + into * depth
	return [Vector3(-lateral, y, z), Vector3(lateral, y, z)]

## Позиция короткой опции: вглубь поля вдоль линии (на dist по Z в поле), ближе к центру по X.
## Точка, КУДА бежит партнёр из штрафной по вызову (RB) — рядом с бьющим, для короткого паса.
static func short_option_pos(spot: Vector3, side: float, into: float, dist: float, y: float) -> Vector3:
	return Vector3(spot.x - side * 2.0, y, spot.z + into * dist)

## Стартовая позиция партнёра под короткий розыгрыш: В ШТРАФНОЙ (у ближней штанги, на стороне
## угла), пока не позвали RB — оттуда он выбегает к short_option_pos.
static func short_mate_start_pos(side: float, goal_line_z: float, into: float, lateral: float, depth: float, y: float) -> Vector3:
	return Vector3(side * lateral, y, goal_line_z + into * depth)

## Горизонтальное направление разбега бьющего к мячу (куда он БЕЖИТ и лицом). База — из поля
## наружу к углу (side по X к боковой линии, -into по Z к лицевой), затем поворот на ±angle_deg
## вокруг вертикали по ноге: правая и левая заходят к мячу с РАЗНЫХ сторон угла. Разбег всегда
## стартует внутри поля (бьющий стоит на runup_dir*dist позади мяча), а не за флажком.
static func runup_dir(side: float, into: float, foot: String, angle_deg: float) -> Vector3:
	var base := Vector3(side, 0.0, -into).normalized()
	var sign := 1.0 if foot == "penalty_r" else -1.0
	return base.rotated(Vector3.UP, deg_to_rad(sign * angle_deg)).normalized()

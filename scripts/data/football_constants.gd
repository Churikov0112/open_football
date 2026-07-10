extends Node


# ═══════════════════════════════════════════
#  FIELD — реальные размеры FIFA
# ═══════════════════════════════════════════

const FIELD_LENGTH := 105.0        # полная длина поля (Z)
const FIELD_WIDTH := 68.0          # полная ширина поля (X)
const HALF_FIELD_LENGTH := FIELD_LENGTH / 2.0    # 52.5
const HALF_FIELD_WIDTH := FIELD_WIDTH / 2.0      # 34.0

const GOAL_WIDTH := 7.32           # между стойками
const GOAL_HEIGHT := 2.44          # от газона до перекладины
const GOAL_DEPTH := 2.0           # глубина сетки (визуальная)
const GOAL_POST_RADIUS := 0.08    # толщина штанги

const PENALTY_AREA_DEPTH := 16.5  # от лицевой линии
const PENALTY_AREA_WIDTH := 40.32 # полная ширина

const GOAL_AREA_DEPTH := 5.5
const GOAL_AREA_WIDTH := 18.32

const CENTER_CIRCLE_RADIUS := 9.15
const CENTER_SPOT_RADIUS := 0.15
const PENALTY_SPOT_DIST := 11.0   # от лицевой линии
const PENALTY_ARC_RADIUS := 9.15  # радиус дуги штрафной (от точки пенальти)
const CORNER_ARC_RADIUS := 1.0

const LINE_THICKNESS := 0.12       # ширина линий разметки


# ═══════════════════════════════════════════
#  BALL
# ═══════════════════════════════════════════

const BALL_RADIUS := 0.11
const BALL_MASS := 0.43
const BALL_DRAG := 0.985
const BALL_AIR_RESISTANCE := 0.999
const SHOT_POWER := 18.0
const PASS_POWER := 12.0
const SHOT_Y_UP := 0.3           # подъём мяча при ударе
const PASS_Y_UP := 0.1           # подъём мяча при пасе


# ═══════════════════════════════════════════
#  PLAYER
# ═══════════════════════════════════════════

const PLAYER_SPEED := 8.0
const PLAYER_HEIGHT := 1.8
const PLAYER_RADIUS := 0.3
const PLAYER_CAPSULE_HEIGHT := 1.5
const PLAYER_ROTATION_SPEED := 10.0
const PLAYER_START_Z := 0.0         # стартовая позиция Z

# --- Living locomotion (velocity+inertia, рецепт OpenSoccer; тюнинг-старт) ---
const LOCO_TOP_SPEED := 8.0          # обычная максимальная скорость, м/с
const LOCO_SPRINT_SPEED := 12.0      # максимальная при спринте (≈1.5×)
const LOCO_ACCEL := 25.0             # разгон, м/с² (≈0.32 с до полной)
const LOCO_DECEL := 20.0             # торможение, м/с² (мягче разгона → глайд)
const LOCO_TURN_ROT := 18.0          # темп доворота тела, 1/с
const LOCO_TURN_MIN_SPEED := 1.0     # ниже этой скорости не доворачиваемся
const LOCO_MAX_BANK_DEG := 20.0      # макс. крен корпуса в повороте, градусы
const LOCO_BANK_SMOOTH := 8.0        # сглаживание крена, 1/сек (гасит рывки от дискретного WASD-ввода)
const LOCO_RUN_SCALE_FUDGE := 1.33   # анти-слайд: scale = (speed/top)*fudge
const LOCO_RUN_ANIM_SPEED := 1.5     # порог входа в стейт run, м/с
const LOCO_SPRINT_ANIM_SPEED := 9.0  # порог входа в стейт sprint, м/с
const PLAYER_COLLISION_MASK := 2     # слой полевых игроков (bit2): бьются только друг о друга
const BOUNDARY_COLLISION_LAYER := 4  # слой границ поля (bit3): отдельно от мяча/питча (слой1),
                                     # чтобы игрок упирался в стены, но НЕ толкал мяч физически


# ═══════════════════════════════════════════
#  DRIBBLING
# ═══════════════════════════════════════════

const DRIBBLE_FORWARD_DIST := 0.5
const DRIBBLE_HEIGHT := 0.08
const SPRING_STIFFNESS := 300.0
const SPRING_DAMPING := 15.0
const SPRING_MAX_FORCE := 50.0
const DRIBBLE_DRAG := 0.995
const DRIBBLE_ACQUIRE_DIST := 1.0
const DRIBBLE_LOSE_DIST := 3.0
const DRIBBLE_RELEASE_COOLDOWN_MSEC := 500
const KICKER_REACQUIRE_COOLDOWN_MSEC := 1500


# ═══════════════════════════════════════════
#  MATCH
# ═══════════════════════════════════════════

const MATCH_DURATION_MIN := 90
const HALF_DURATION_MIN := 45
const HALFTIME_DURATION_MIN := 15
const RESET_BALL_Y := 0.5


# ═══════════════════════════════════════════
#  AI
# ═══════════════════════════════════════════

const AI_SPEED := 5.0
const AI_SHOOT_RANGE := 25.0
const AI_DRIBBLE_SPEED_FACTOR := 0.8
const AI_KICK_COOLDOWN := 0.8
const AI_KICK_POWER := 10.0
const AI_ACQUIRE_RANGE := 1.8


# ═══════════════════════════════════════════
#  SLIDE TACKLE
# ═══════════════════════════════════════════

const SLIDE_TACKLE_SPEED := 18.0
const SLIDE_TACKLE_RANGE := 4.0
# Временный диагностический флаг: подкат на месте (без move_and_collide), чтобы отделить
# анимацию tackle от вопроса "не баг ли в самом скольжении". Пока true, физического
# столкновения с игроком-жертвой не будет (collision из move_and_collide всегда null при
# нулевом motion) — окно такла живёт только по таймеру (тот же SLIDE_TACKLE_SPEED*delta,
# просто не двигает тело), мяч по-прежнему выбивается через Area3D. Вернуть false, когда
# разберёмся с анимацией.
const SLIDE_TACKLE_INPLACE := true
const SLIDE_TACKLE_RECOVERY_TIME := 1.5
const SLIDE_TACKLE_AREA_RADIUS := 1.5
const SLIDE_TACKLE_BALL_DIR_Y := 0.15
const SLIDE_TACKLE_BALL_POWER := 7.0
const AI_TACKLE_RANGE := 2.5
const AI_TACKLE_COOLDOWN := 2.0


# ═══════════════════════════════════════════
#  TACKLE FALL / GRAVITY (тюнинг-старт)
# ═══════════════════════════════════════════

const GRAVITY := 20.0                 # аркадная гравитация, м/с²
# Анимационное падение жертвы подката (Path B: физ-ragdoll несовместим с масштабированным
# Mixamo-скелетом в Godot). Фаза knockdown держит позу «лежит» (fallen_idle) и отбрасывает
# тело кодом, затем 2 переката и вставание.
const KNOCKDOWN_TIME := 0.5           # длительность фазы «сбит/лежит» до первого переката, с
const KNOCKBACK_DISTANCE := 1.0       # отброс тела в сторону от подкатчика за knockdown, м
const ROLL_DISTANCE := 1.2            # смещение тела за один перекат, м
# Слой физкостей для дремлющей библиотеки RagdollSkeleton (сейчас в рантайме не строится —
# оставлено на случай, если ограничение Godot с масштабом скелета будет обойдено).
const RAGDOLL_COLLISION_LAYER := 8    # bit4: маскирует слой пола (BOUNDARY_COLLISION_LAYER=4)


# ═══════════════════════════════════════════
#  CAMERA
# ═══════════════════════════════════════════

const CAMERA_FOLLOW_SPEED := 3.0
const CAMERA_HEIGHT := 25.0
const CAMERA_Z_OFFSET := 3.0
const CAMERA_TILT := -55.0         # градусов

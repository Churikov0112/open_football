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

# Скорость/дистанция скольжения подобраны так, чтобы физический слайд (move_and_collide)
# занимал заметную часть длины клипа tackle (~1.8с), а не долетал до конца дистанции за
# долю секунды, пока клип ещё продолжает играть — раньше (SPEED=18.0) слайд укладывался
# в ~0.22с, и игрок визуально телепортировался в точку, а затем ещё ~1.6с доигрывал
# подкат стоя на месте. Первая попытка (SPEED=5.0) была МЕДЛЕННЕЕ реальной скорости бега
# соперника (simple_ai.gd @export var speed = 6.5 — константа AI_SPEED=5.0 выше по файлу
# им не используется, легаси) — подкат сзади (сближение вдогонку) физически никогда не
# догонял цель, хотя сбоку (сближение поперёк) работал. SPEED поднят с запасом выше 6.5,
# чтобы вдогонку соперника хватало. RECOVERY_TIME подобран так, чтобы суммарный commit
# (слайд + recovery) остался близко к длине клипа, как было тюнено раньше (~1.7-1.8с).
const SLIDE_TACKLE_SPEED := 9.0
const SLIDE_TACKLE_RANGE := 4.0
# Диагностический флаг (подкат на месте, без move_and_collide) для изоляции анимации
# tackle от скольжения — см. tools/merge_mixamo.py IN_PLACE_CLIPS. Причина зависания
# найдена и исправлена там (заморозка вертикали Hips для tackle убрана), возвращаем
# обычное поведение со скольжением.
const SLIDE_TACKLE_INPLACE := false
const SLIDE_TACKLE_RECOVERY_TIME := 1.3
const SLIDE_TACKLE_AREA_RADIUS := 1.5
# Порог сбивания игрока-соперника с ног (match_manager._check_tackle_player_hit) —
# НАМНОГО теснее SLIDE_TACKLE_AREA_RADIUS выше. Тот радиус щедрый специально (дотянуться
# до мяча), но раньше от него же ронялся и игрок — с разницей центров тел до ~1.5м, когда
# капсулы (radius=0.3 у каждой, см. _setup_away_player/_setup_teammate) визуально даже не
# соприкасались.
# 0.9 ≈ сумма радиусов капсул (0.6) + небольшой запас, чтобы не мазать по кадру.
const SLIDE_TACKLE_HIT_RADIUS := 0.9
const SLIDE_TACKLE_BALL_DIR_Y := 0.15
const SLIDE_TACKLE_BALL_POWER := 7.0
# Было 2.5 — решение "подкатывать" принималось иногда слишком издалека, и с добавленным
# упреждением цели (_start_tackle) чем дальше цель в момент решения, тем грубее оценка
# lead_time (нет итерации схождения). Урезано, чтобы ИИ решался ближе — упреждение точнее.
const AI_TACKLE_RANGE := 2.0
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
#  PASSING (тюнинг-старт)
# ═══════════════════════════════════════════

# Базовая скорость мяча (м/с) по типам паса. launch_ground/launch_lob получают её параметром.
const PASS_LOB_PEAK_HEIGHT := 3.0     # высота дуги навеса, м
const PASS_THROUGH_AIR_PEAK_HEIGHT := 2.5  # высота дуги верхового паса на ход

# Низовой пас теперь ВСЕГДА долетает на заданную дистанцию — скорость выводится из
# дистанции и времени полёта (не из фиксированной силы), заряд лишь меняет время полёта
# (мягче/жёстче), а не «долетит/не долетит». См. PassSystem.ground_pass_speed.
const PASS_GROUND_MIN_TRAVEL_TIME := 0.5   # время полёта при полном заряде (жёсткий, быстрый пас), с
const PASS_GROUND_MAX_TRAVEL_TIME := 1.4   # время полёта при минимальном заряде (мягкий, медленный пас), с
const PASS_GROUND_MIN_SPEED := 4.0         # нижний предел скорости мяча низом, м/с
const PASS_GROUND_MAX_SPEED := 28.0        # верхний предел скорости мяча низом, м/с
const PASS_LEAD_SPEED_ESTIMATE := 12.0     # типичная скорость мяча для оценки времени упреждения (lead_point) — НЕ финальная скорость запуска

# Заряд множит базовую силу/высоту в диапазоне [MIN..MAX] по доле заряда.
const PASS_CHARGE_MAX_TIME := 0.6
const PASS_POWER_CHARGE_MIN := 0.7    # доля силы при мгновенном отпускании
const PASS_POWER_CHARGE_MAX := 1.6    # доля силы при полном заряде

# Авто-наводка.
const PASS_LEAD_GAIN := 0.25          # упреждение цели по её скорости (сек)
const PASS_THROUGH_EXTRA_LEAD := 2.0  # доп. вынос точки «на ход» вперёд по скорости цели, м
const PASS_DOT_BIAS := 0.15           # штраф за дистанцию в score выбора цели (0 → чистый dot)
const PASS_MAX_RANGE := 45.0          # дальше цель не рассматривается, м

# Коридор перехвата.
const PASS_CORRIDOR_HALF_WIDTH := 1.2 # полуширина коридора у точки паса, м
const PASS_CORRIDOR_SPREAD := 0.06    # прирост полуширины на метр вдоль паса

# Разброс точности.
const PASS_SPREAD_BASE := 12.0        # макс. разброс угла, градусы (при assist=0, дальней дистанции)
const PASS_SPREAD_DIST_REF := 25.0    # дистанция, на которой разброс достигает базового
const PASS_ASSIST := 0.75             # 0..1 «лёгкость»: 1 → почти без разброса

# Receive-assist (доводка принимающего к мячу).
const PASS_RECEIVE_PREDICT_WINDOW := 0.16  # на сколько сек вперёд предсказываем позицию мяча
const PASS_RECEIVE_MAX_TIME := 2.0         # страховочный таймаут фазы приёма, сек

# Give-and-go («стенка»).
const PASS_WALL_WINDOW := 3.0         # окно возврата, сек
const PASS_WALL_RUN_FORWARD := 10.0   # вынос рывка отдавшего вперёд по атаке, м
const PASS_WALL_RUN_LATERAL := 6.0    # вынос рывка в сторону, м

# Активный перехват ИИ-соперника (честный, не читерский).
const AI_INTERCEPT_REACT := 0.3       # задержка реакции соперника на пас, сек
const AI_INTERCEPT_CHANCE := 0.8      # шанс среагировать (иначе «зевает»)


# ═══════════════════════════════════════════
#  CAMERA
# ═══════════════════════════════════════════

const CAMERA_FOLLOW_SPEED := 3.0
const CAMERA_HEIGHT := 25.0
const CAMERA_Z_OFFSET := 3.0
const CAMERA_TILT := -55.0         # градусов

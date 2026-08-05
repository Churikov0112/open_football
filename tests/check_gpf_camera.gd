extends SceneTree
# Тикет 07 фазы 7: камера матча — Match::UpdateIngameCamera (match.cpp:723-843),
# Get/SetCameraParams (:709-721), наезд первых двух секунд (:1051-1075) и заливка в узлы
# сцены (:1221-1240).
#
# Тест перевычисляет формулы по C++ (включая очередь позиций со взвешенным средним и её
# кап на 150) и сверяет с узлами после Apply. Дрожание детерминировано: камера кормится
# `GpfRng` с известным сидом, тест держит второй экземпляр с тем же сидом и берёт числа в
# том же порядке — по два броска на тик.
#
# Ядро порта тут не тикает (камера считается от подставленных чисел), маршалинг Gpf.* не
# задействован.

const SEED := 20260807
const CAM_POS_SIZE := 150  # match.cpp:30

# gamedefines.hpp:33-36 — дефолты пользовательских параметров
const USER_ZOOM := 0.5
const USER_HEIGHT := 0.3
const USER_FOV := 0.4
const USER_ANGLE := 0.0

# [zoom, height, fov, angleFactor] — как их читает UpdateIngameCamera
const DEFAULTS := [USER_ZOOM, USER_HEIGHT, USER_FOV, USER_ANGLE]

var _fails := 0
var _cam_pos: Array[Vector3] = []  # зеркало очереди camPos внутри теста


func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("  FAIL: ", msg)


func feq(a: float, b: float, eps := 1.0e-3) -> bool:
	return absf(a - b) < eps


func veq(a: Vector3, b: Vector3, eps := 1.0e-3) -> bool:
	return a.distance_to(b) < eps


func qeq(a: Quaternion, b: Quaternion, eps := 1.0e-4) -> bool:
	var d1 := absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) + absf(a.w - b.w)
	var d2 := absf(a.x + b.x) + absf(a.y + b.y) + absf(a.z + b.z) + absf(a.w + b.w)
	return minf(d1, d2) < eps


# quaternion.cpp:284-296 SetAngleAxis
func angle_axis(angle: float, axis: Vector3) -> Quaternion:
	var half := 0.5 * angle
	var s := sin(half)
	return Quaternion(s * axis.x, s * axis.y, s * axis.z, cos(half))


# vector3.hpp:261-268 GetLength — квирк: длина < 1e-6 обнуляется
func vlen(v: Vector3) -> float:
	var l := sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	return 0.0 if l < 0.000001 else l


# bluntmath.cpp:61-63
func sign_side(n: float) -> float:
	return 1.0 if n >= 0.0 else -1.0


# vector3.hpp:325-333 GetRotated2D
func rotated_2d(v: Vector3, angle: float) -> Vector3:
	return Vector3(v.x * cos(angle) - v.y * sin(angle), v.y * cos(angle) + v.x * sin(angle), v.z)


# Один тик очереди позиций (:734-767) — возвращает взвешенное среднее.
# `rng` — экземпляр GpfRng теста, идущий в ногу с камерой (два броска на тик, :748).
func push_and_average(ball_predict0: Vector3, ball_movement: Vector3,
		player_pos: Vector3, player_dir: Vector3, rng, p := DEFAULTS) -> Vector3:
	var zoom: float = p[0]                # :731
	var height: float = p[1] * 1.5        # :732

	var player_bias := 0.6                                                     # :734
	var ball_pos: Vector3 = ball_predict0 * (1.0 - player_bias) + player_pos * player_bias  # :735
	ball_pos += player_dir * 1.0                                               # :737
	# :739 — суррогат лабы: FadingTeamPossessionAmount = 1.0 у обеих команд, слагаемое = 0
	ball_pos.z *= 0.1                                                          # :741

	var max_w: float = 55.0 * 0.84 * (1.0 / (zoom + 0.01))                     # :743
	var max_h: float = 36.0 * 0.60 * (1.0 / (zoom + 0.01)) * (height * 0.75 + 0.25)  # :744
	# слагаемое атаки (:739) и смесь мяч/игрок посчитаны выше — параметры на них не влияют
	if absf(ball_pos.x) > max_w:
		ball_pos.x = max_w * sign_side(ball_pos.x)                             # :745
	if absf(ball_pos.y) > max_h:
		ball_pos.y = max_h * sign_side(ball_pos.y)                             # :746

	var shudder := Vector3(rng.Uniform(-0.1, 0.1), rng.Uniform(-0.1, 0.1), 0.0) \
			* (vlen(ball_movement) * 0.8 + 6.0)                                # :748
	shudder *= 0.2                                                             # :749

	_cam_pos.append(ball_pos + shudder * (float(_cam_pos.size()) / float(CAM_POS_SIZE)))  # :750
	if _cam_pos.size() > CAM_POS_SIZE:
		_cam_pos.remove_at(0)                                                  # :751

	var average := Vector3.ZERO
	var count := 0.0
	var index_size := float(_cam_pos.size())
	for index in _cam_pos.size():
		var weight: float = sin((index / index_size - 0.3) * 1.4 * PI) * 0.5 + 0.5  # :759
		weight *= pow(1.0 - index / index_size, 0.3)                                # :760
		average += _cam_pos[index] * weight                                         # :761
		count += weight                                                             # :762
	return average / count                                                          # :767


# Ожидаемое состояние wide-камеры (:781-791) от среднего очереди.
# [позиция узла, поворот узла, поворот камеры, fov, near, far]
func wide_expected(average: Vector3, p := DEFAULTS) -> Array:
	var fov: float = 0.5 + p[2] * 0.5     # :730
	var zoom: float = p[0]                # :731
	var height: float = p[1] * 1.5        # :732
	var angle_fac: float = 1.0 - p[3] * 0.4  # :769

	zoom = (0.6 + zoom * 1.0) * (1.0 / fov)  # :781
	height = 4.0 + height * 10               # :782

	var dist_rot := average.y / 800.0        # :784
	var cam_orient := angle_axis(dist_rot + (0.42 - height * 0.01) * PI, Vector3(1, 0, 0))  # :786
	var node_orient := angle_axis(
			(-average.x / 55.0) * (1.0 - angle_fac) * 0.25 * PI * 1.24, Vector3(0, 0, 1))   # :787
	var node_pos: Vector3 = average * Vector3(
			1.0 * (1.0 - p[3] * 0.2) * (1.0 - p[0] * 0.3),
			0.9 - p[0] * 0.3,
			0.2) \
		+ Vector3(0, -41.4 - (p[2] * 3.7) + pow(height, 1.2) * 0.46, 10.0 + height) * zoom  # :788
	var cam_fov := (fov * 28.0) - (node_pos.y / 30.0)  # :789
	return [node_pos, node_orient, cam_orient, cam_fov, node_pos.z, 200.0]  # :790-791


func _check_state(node: Node3D, cam: Camera3D, want: Array, what: String) -> void:
	# :1221 — камера-ребёнок всегда в нуле, позицию несёт родитель
	if not veq(cam.position, Vector3.ZERO):
		_fail("%s: позиция камеры-ребёнка %s, ожидался ноль" % [what, cam.position])
	if not veq(node.position, want[0]):
		_fail("%s: позиция узла %s, ожидалось %s" % [what, node.position, want[0]])
	if not qeq(node.quaternion, want[1]):
		_fail("%s: поворот узла %s, ожидалось %s" % [what, node.quaternion, want[1]])
	if not qeq(cam.quaternion, want[2]):
		_fail("%s: поворот камеры %s, ожидалось %s" % [what, cam.quaternion, want[2]])
	if not feq(cam.fov, want[3]):
		_fail("%s: fov %.4f, ожидалось %.4f" % [what, cam.fov, want[3]])
	if not feq(cam.near, want[4]):
		_fail("%s: near %.4f, ожидалось %.4f" % [what, cam.near, want[4]])
	if not feq(cam.far, want[5]):
		_fail("%s: far %.4f, ожидалось %.4f" % [what, cam.far, want[5]])


func _initialize() -> void:
	print("== check_gpf_camera ==")

	var C = load("res://src/lab/IngameCamera.cs")
	var R = load("res://src/gpf/GpfRng.cs")
	if C == null or R == null:
		_fail("нет IngameCamera.cs/GpfRng.cs — сначала dotnet build")
		_done()
		return

	var camera = C.new()
	var cam_rng = R.new()
	cam_rng.Reseed(SEED)
	var my_rng = R.new()
	my_rng.Reseed(SEED)

	var node := Node3D.new()
	var cam := Camera3D.new()
	node.add_child(cam)

	# ---------- 1. Дефолты параметров (gamedefines.hpp:33-36) ----------
	var params: Array = camera.GetCameraParams()
	if not (feq(params[0], USER_ZOOM) and feq(params[1], USER_HEIGHT)
			and feq(params[2], USER_FOV) and feq(params[3], USER_ANGLE)):
		_fail("дефолты параметров: %s, ожидалось [0.5, 0.3, 0.4, 0.0]" % [params])

	camera.SetCameraParams(0.7, 0.2, 0.9, 0.5)  # :716-721
	params = camera.GetCameraParams()
	if not (feq(params[0], 0.7) and feq(params[1], 0.2)
			and feq(params[2], 0.9) and feq(params[3], 0.5)):
		_fail("SetCameraParams не сохранил значения: %s" % [params])
	camera.SetCameraParams(USER_ZOOM, USER_HEIGHT, USER_FOV, USER_ANGLE)  # обратно к дефолтам

	# ---------- 2. Первый тик wide: полное перевычисление ----------
	var ball := Vector3(3.0, -4.0, 0.3)
	var ball_move := Vector3(6.0, 1.0, 0.0)
	var player := Vector3(2.0, -3.0, 0.0)
	var player_dir := Vector3(0, -1, 0)

	var average := push_and_average(ball, ball_move, player, player_dir, my_rng)
	camera.Update(ball, ball_move, player, player_dir, false, 0, player, cam_rng)
	camera.Apply(node, cam)
	_check_state(node, cam, wide_expected(average), "первый тик wide")

	# ---------- 2b. Не-дефолтные параметры: множители угла оживают ----------
	# При angleFactor = 0 множитель (1 - angleFac) в :787 равен нулю и поворот узла всегда
	# единичный — на дефолтах формула вырождена и ошибка в ней незаметна. Гоняем тик с
	# «пользовательскими» значениями: живыми становятся :787 целиком и множители в :788.
	var custom := [0.7, 0.2, 0.9, 0.5]
	camera.SetCameraParams(custom[0], custom[1], custom[2], custom[3])
	var ball_c := Vector3(-18.0, 7.0, 0.5)
	var move_c := Vector3(4.0, -2.0, 0.0)
	var player_c := Vector3(-17.0, 6.0, 0.0)
	var dir_c := Vector3(1, 0, 0)
	var avg_c := push_and_average(ball_c, move_c, player_c, dir_c, my_rng, custom)
	camera.Update(ball_c, move_c, player_c, dir_c, false, 0, player_c, cam_rng)
	camera.Apply(node, cam)
	var want_c: Array = wide_expected(avg_c, custom)
	_check_state(node, cam, want_c, "не-дефолтные параметры")
	if qeq(want_c[1], Quaternion.IDENTITY):
		_fail("кейс не-дефолтных параметров вырожден: поворот узла всё равно единичный")
	camera.SetCameraParams(USER_ZOOM, USER_HEIGHT, USER_FOV, USER_ANGLE)
	camera.ResetPositions()
	_cam_pos.clear()

	# ---------- 3. 200 тиков: очередь капается 150-ю, среднее совпадает ----------
	for i in range(200):
		var t := float(i)
		ball = Vector3(sin(t * 0.05) * 20.0, cos(t * 0.03) * 12.0, 0.4)
		ball_move = Vector3(cos(t * 0.05) * 8.0, -sin(t * 0.03) * 4.0, 0.0)
		player = ball + Vector3(-1.0, 0.5, 0.0)
		player_dir = Vector3(sin(t * 0.02), -cos(t * 0.02), 0.0).normalized()
		average = push_and_average(ball, ball_move, player, player_dir, my_rng)
		camera.Update(ball, ball_move, player, player_dir, false, 0, player, cam_rng)
	camera.Apply(node, cam)
	if _cam_pos.size() != CAM_POS_SIZE:
		_fail("очередь позиций: %d, ожидалось %d" % [_cam_pos.size(), CAM_POS_SIZE])
	_check_state(node, cam, wide_expected(average), "после 200 тиков")

	# ---------- 4. Клампы по полю: мяч далеко за кромкой ----------
	var far_ball := Vector3(300.0, 200.0, 0.0)
	for i in range(300):  # очередь заполняется загнанными в кламп позициями
		average = push_and_average(far_ball, Vector3.ZERO, far_ball, Vector3(0, -1, 0), my_rng)
		camera.Update(far_ball, Vector3.ZERO, far_ball, Vector3(0, -1, 0), false, 0, far_ball, cam_rng)
	camera.Apply(node, cam)
	var max_w: float = 55.0 * 0.84 * (1.0 / (USER_ZOOM + 0.01))
	var max_h: float = 36.0 * 0.60 * (1.0 / (USER_ZOOM + 0.01)) * (USER_HEIGHT * 1.5 * 0.75 + 0.25)
	if absf(average.x) > max_w + 0.5 or absf(average.y) > max_h + 0.5:
		_fail("клампы не держат: среднее %s при maxW %.2f maxH %.2f" % [average, max_w, max_h])
	_check_state(node, cam, wide_expected(average), "клампы по полю")

	# ---------- 5. Гол: первую секунду wide, дальше scorer-cam (:775) ----------
	var scorer := Vector3(50.0, 2.0, 0.0)
	average = push_and_average(ball, ball_move, player, player_dir, my_rng)
	camera.Update(ball, ball_move, player, player_dir, true, 990, scorer, cam_rng)
	camera.Apply(node, cam)
	_check_state(node, cam, wide_expected(average), "гол, таймер < 1000 — ещё wide")

	# бросок дрожания делается ДО ветки, поэтому очередь теста идёт в ногу и тут
	average = push_and_average(ball, ball_move, player, player_dir, my_rng)
	camera.Update(ball, ball_move, player, player_dir, true, 1000, scorer, cam_rng)
	camera.Apply(node, cam)

	var rot := 1000.0 * 0.0005                                                     # :829
	var want_scorer := [
		scorer + rotated_2d(Vector3(0, -1, 0), rot) * 15.0 + Vector3(0, 0, 3),     # :832
		angle_axis(rot, Vector3(0, 0, 1)),                                         # :831
		angle_axis(0.45 * PI, Vector3(1, 0, 0)),                                   # :830
		35.0, 1.0, 220.0,                                                          # :833-836
	]
	_check_state(node, cam, want_scorer, "scorer-cam")

	# облёт нарастает: через секунду поворот больше
	average = push_and_average(ball, ball_move, player, player_dir, my_rng)
	camera.Update(ball, ball_move, player, player_dir, true, 2000, scorer, cam_rng)
	camera.Apply(node, cam)
	var rot2 := 2000.0 * 0.0005
	if not veq(node.position,
			scorer + rotated_2d(Vector3(0, -1, 0), rot2) * 15.0 + Vector3(0, 0, 3)):
		_fail("scorer-cam: облёт не нарастает, позиция %s" % node.position)

	# ---------- 6. Наезд первых двух секунд (:1051-1075) ----------
	# t = 0: bias = 1 — камера ровно в стартовой точке вида сверху
	average = push_and_average(ball, ball_move, player, player_dir, my_rng)
	camera.Update(ball, ball_move, player, player_dir, false, 0, player, cam_rng)
	camera.ApplyIntroZoom(0)
	camera.Apply(node, cam)
	if not veq(node.position, Vector3(0, 0, 60)):
		_fail("наезд t=0: позиция %s, ожидалось (0, 0, 60)" % node.position)
	if not feq(cam.fov, 40.0) or not feq(cam.near, 2.0):
		_fail("наезд t=0: fov %.3f near %.3f, ожидалось 40 и 2" % [cam.fov, cam.near])
	if not qeq(cam.quaternion, Quaternion.IDENTITY):
		_fail("наезд t=0: поворот камеры %s, ожидался единичный" % cam.quaternion)

	# t = 600: середина наезда, работают все четыре смешивания (:1068-1072). Точка взята
	# НЕ на bias = 0.5: там для поворота вокруг одной оси покомпонентный lerp совпадает со
	# slerp, и подмена одного другим прошла бы незамеченной.
	average = push_and_average(ball, ball_move, player, player_dir, my_rng)
	camera.Update(ball, ball_move, player, player_dir, false, 0, player, cam_rng)
	var wide_mid: Array = wide_expected(average)
	camera.ApplyIntroZoom(600)
	camera.Apply(node, cam)

	var bias: float = sin((600.0 / 2000.0) * PI - 0.5 * PI) * -0.5 + 0.5  # :1064-1066
	var initial_pos := Vector3(0, 0, 60)
	if not veq(node.position, wide_mid[0] * (1.0 - bias) + initial_pos * bias):  # :1070
		_fail("наезд t=600: позиция %s, ожидалось %s"
				% [node.position, wide_mid[0] * (1.0 - bias) + initial_pos * bias])
	if not feq(cam.fov, wide_mid[3] * (1.0 - bias) + 40.0 * bias):  # :1071
		_fail("наезд t=600: fov %.4f, ожидалось %.4f"
				% [cam.fov, wide_mid[3] * (1.0 - bias) + 40.0 * bias])
	if not feq(cam.near, wide_mid[4] * (1.0 - bias) + 2.0 * bias):  # :1072
		_fail("наезд t=600: near %.4f, ожидалось %.4f"
				% [cam.near, wide_mid[4] * (1.0 - bias) + 2.0 * bias])
	# повороты — slerp к единичным (:1068-1069): на середине это НЕ покомпонентный lerp
	if not qeq(cam.quaternion, (wide_mid[2] as Quaternion).slerp(Quaternion.IDENTITY, bias)):
		_fail("наезд t=600: поворот камеры %s, ожидался slerp" % cam.quaternion)

	# t >= 2000: наезд кончился, состояние wide не трогается
	average = push_and_average(ball, ball_move, player, player_dir, my_rng)
	camera.Update(ball, ball_move, player, player_dir, false, 0, player, cam_rng)
	camera.ApplyIntroZoom(2000)
	camera.Apply(node, cam)
	_check_state(node, cam, wide_expected(average), "наезд кончился (t = 2000)")

	# ---------- 7. ResetPositions чистит очередь (match.cpp:652) ----------
	camera.ResetPositions()
	_cam_pos.clear()
	average = push_and_average(ball, ball_move, player, player_dir, my_rng)
	camera.Update(ball, ball_move, player, player_dir, false, 0, player, cam_rng)
	camera.Apply(node, cam)
	_check_state(node, cam, wide_expected(average), "после ResetPositions")

	node.queue_free()
	_done()


func _done() -> void:
	print("CHECK PASS" if _fails == 0 else "CHECK FAIL: %d расхождений" % _fails)
	quit(1 if _fails > 0 else 0)

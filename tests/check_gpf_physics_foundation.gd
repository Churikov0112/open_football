extends SceneTree
# Фаза 3, задача 1: примитивы Vector3 (vector3.cpp:190-228) + кэш позиций корня (match.cpp:86-105).
# Опорные числа кэша — из СЫРЫХ ключей .anim (урок фазы 2), парсим файл сами.

const ANIM_PATH := "res://assets/gpf/animations/movement/walk/045.anim"

func feq(a: float, b: float, eps := 1.0e-5) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-5) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var BM = load("res://src/gpf/BluntMath.cs")
	var V = load("res://src/gpf/Velo.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var A = load("res://src/gpf/Animation.cs")
	if BM == null or V == null or AC == null or A == null:
		print("CHECK FAIL: C#-скрипты не найдены — сначала dotnet build")
		quit(1)
		return

	# --- NormalizeMax (vector3.cpp:199-204): длиннее лимита → обрезать, короче → не трогать ---
	var v: Vector3 = BM.NormalizeMax(Vector3(3, 4, 0), 2.5)
	if not feq(v.length(), 2.5):
		print("CHECK FAIL: NormalizeMax длина ", v.length()); ok = false
	if not vec_eq(v.normalized(), Vector3(0.6, 0.8, 0)):
		print("CHECK FAIL: NormalizeMax сменил направление ", v); ok = false
	v = BM.NormalizeMax(Vector3(1, 0, 0), 2.5)
	if not vec_eq(v, Vector3(1, 0, 0)):
		print("CHECK FAIL: NormalizeMax тронул короткий ", v); ok = false

	# --- GetNormalizedTo (vector3.cpp:218-223): любую длину → ровно length ---
	v = BM.GetNormalizedTo(Vector3(0, -2, 0), 3.49)
	if not vec_eq(v, Vector3(0, -3.49, 0)):
		print("CHECK FAIL: GetNormalizedTo ", v); ok = false

	# --- GetNormalizedMax (vector3.cpp:225-228) ---
	v = BM.GetNormalizedMax(Vector3(0, -0.5, 0), 1.0)
	if not vec_eq(v, Vector3(0, -0.5, 0)):
		print("CHECK FAIL: GetNormalizedMax короткий ", v); ok = false
	v = BM.GetNormalizedMax(Vector3(0, -4, 0), 1.0)
	if not vec_eq(v, Vector3(0, -1, 0)):
		print("CHECK FAIL: GetNormalizedMax длинный ", v); ok = false

	# --- Velo.AnimSprint (gamedefines.hpp:23) ---
	# ПОПРАВКА к брифу: бриф читал `V.AnimSprint` напрямую, но мост отдаёт только статические
	# МЕТОДЫ — const-поле CSharpScript недоступно ("Invalid access to property or key
	# 'AnimSprint'"). Читаем через мост-обёртку Velo.GetAnimSprint() (паттерн QuatUtil.GetAnglesVec).
	if not feq(V.GetAnimSprint(), 7.0):
		print("CHECK FAIL: AnimSprint = ", V.GetAnimSprint()); ok = false

	# --- GetEffectiveFrameCount (animation.hpp:83) ---
	var anim = A.new()
	if not anim.LoadFromFile(ANIM_PATH):
		print("CHECK FAIL: не загрузился ", ANIM_PATH); ok = false
	if anim.GetEffectiveFrameCount() != anim.GetFrameCount() - 1:
		print("CHECK FAIL: GetEffectiveFrameCount"); ok = false

	# --- Кэш позиций: сверка с сырыми ключами player-строки файла ---
	# Формат CSV (порт-gameplayfootball.md): строка 0 = "player,frame,x,y,z,frame,x,y,z,...",
	# строка 1 = "body,frame,qx,qy,qz,qw,..."
	var f := FileAccess.open(ANIM_PATH, FileAccess.READ)
	var tokens := f.get_line().split(",")
	var body_tokens := f.get_line().split(",")
	if tokens[0] != "player" or body_tokens[0] != "body":
		print("CHECK FAIL: неожиданный порядок треков в файле"); ok = false
	var raw_keys: Array = []  # [ [frame, Vector3], ... ]
	var k := 1
	while k + 3 < tokens.size():
		raw_keys.append([int(tokens[k]), Vector3(
			float(tokens[k + 1]), float(tokens[k + 2]), float(tokens[k + 3]))])
		k += 4

	# --- GetInterpolatedRotation: на сыром ключе body == сам ключ (урок 1: ожидание из файла) ---
	# ВНИМАНИЕ: LoadFromFile мутирует клип (ConvertToStartFacingForwardIfIdle — только idle-вход;
	# walk/045 не idle, body-ключи не тронуты; Mirror здесь не зовётся).
	var body_f0 := int(body_tokens[1])
	var body_q0 := Quaternion(float(body_tokens[2]), float(body_tokens[3]),
		float(body_tokens[4]), float(body_tokens[5]))
	var q_int: Quaternion = anim.GetInterpolatedRotation("body", body_f0)
	if not (q_int.is_equal_approx(body_q0) or q_int.is_equal_approx(-body_q0)):
		print("CHECK FAIL: GetInterpolatedRotation на ключе ", q_int, " != ", body_q0); ok = false
	if raw_keys.size() != 4:
		print("CHECK FAIL: у walk/045 ожидалось 4 root-ключа, найдено ", raw_keys.size()); ok = false

	var cache: Array = AC.BuildPositionCache(anim)
	if cache.size() != anim.GetFrameCount():
		print("CHECK FAIL: размер кэша ", cache.size(), " != frameCount ", anim.GetFrameCount()); ok = false
	# на каждом сыром ключе кэш равен ключу с занулённым Z (match.cpp:99)
	for rk in raw_keys:
		var frame: int = rk[0]
		var pos: Vector3 = rk[1]
		var cached: Vector3 = cache[frame]
		if not vec_eq(cached, Vector3(pos.x, pos.y, 0.0)):
			print("CHECK FAIL: кэш[", frame, "] = ", cached, " != ", Vector3(pos.x, pos.y, 0)); ok = false
	# между ключами — lerp (animation.cpp:186-232): середина между ключами 1 и 2
	var fa: int = raw_keys[1][0]
	var fb: int = raw_keys[2][0]
	if fb - fa >= 2:
		var mid_frame: int = fa + (fb - fa) / 2
		var bias: float = float(mid_frame - fa) / float(fb - fa)
		var expected: Vector3 = raw_keys[1][1] * (1.0 - bias) + raw_keys[2][1] * bias
		expected.z = 0.0
		var got: Vector3 = cache[mid_frame]
		if not vec_eq(got, expected, 1.0e-4):
			print("CHECK FAIL: кэш между ключами ", got, " != ", expected); ok = false

	# кэш в коллекции: по списку на каждый клип (после Load)
	# (лёгкая проверка без полной загрузки не существует — грузим коллекцию один раз)
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var collection = AC.new()
	collection.Load("res://assets/gpf/animations", skel)
	if collection.GetPositionCacheCount() != collection.GetAnimationCount():
		print("CHECK FAIL: кэшей ", collection.GetPositionCacheCount(),
			" != клипов ", collection.GetAnimationCount()); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

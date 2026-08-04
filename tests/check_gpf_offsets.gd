extends SceneTree
# Фаза 6, «труба» офсетов: ветка offset в Animation::Apply (animation.cpp:424-433).
#
# В живой игре карта офсетов ВСЕГДА пуста: Humanoid::CalculateGeomOffsets не вызывается
# никогда, а базовая версия закомментирована (разбор — .scratch/oracle/issues/14). Поэтому
# карта здесь наполняется тестом напрямую: проверяется математика, которой воспользуется
# фаза 9, когда тело функции будет перенесено.

func quat_close(a: Quaternion, b: Quaternion, eps := 1.0e-4) -> bool:
	var d1 := absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) + absf(a.w - b.w)
	var d2 := absf(a.x + b.x) + absf(a.y + b.y) + absf(a.z + b.z) + absf(a.w + b.w)
	return minf(d1, d2) < eps

# Покомпонентный lerp — как QuatUtil.Lerp (quaternion.cpp:348-350).
func lerp_cw(a: Quaternion, bias: float, b: Quaternion) -> Quaternion:
	return Quaternion(a.x + (b.x - a.x) * bias, a.y + (b.y - a.y) * bias,
		a.z + (b.z - a.z) * bias, a.w + (b.w - a.w) * bias)

# MakeSameNeighborhood (quaternion.cpp:426) — вернуть q в полусферу reference.
func same_hemi(q: Quaternion, reference: Quaternion) -> Quaternion:
	return q if q.dot(reference) >= 0.0 else Quaternion(-q.x, -q.y, -q.z, -q.w)

func _initialize() -> void:
	var ok := true
	var skel: Skeleton3D = load("res://src/gpf/SkeletonBuilder.cs").new().BuildUtilitySkeleton()
	get_root().add_child(skel)  # глобальные позы требуют дерева
	var anim = load("res://src/gpf/Animation.cs").new()
	anim.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	var applier = load("res://src/gpf/AnimationApplier.cs").new()

	var neck := skel.find_bone("neck")
	var body := skel.find_bone("body")

	# Базовая поза без единого офсета — она же регрессия: пустая карта не должна ничего менять.
	applier.Apply(skel, anim, 12, 0.0, false, 0.0, Vector3.ZERO, false, 1.0, 10)
	var base_neck: Quaternion = skel.get_bone_pose_rotation(neck)
	var base_body: Quaternion = skel.get_bone_pose_rotation(body)

	var target := Quaternion(Vector3(1, 0, 0), 0.4)
	var target_n := same_hemi(target, base_neck)

	# 1. Абсолютный офсет с bias = 1: поза кости становится ориентацией офсета (:431).
	applier.SetOffset("neck", 1.0, target, false)
	applier.Apply(skel, anim, 12, 0.0, false, 0.0, Vector3.ZERO, false, 1.0, 10)
	if not quat_close(skel.get_bone_pose_rotation(neck), target_n.normalized()):
		print("CHECK FAIL: абсолютный офсет bias=1 → ", skel.get_bone_pose_rotation(neck)); ok = false

	# 1b. Офсет одной кости не трогает соседнюю: ключ карты — имя узла.
	if not quat_close(skel.get_bone_pose_rotation(body), base_body):
		print("CHECK FAIL: офсет neck сдвинул body → ", skel.get_bone_pose_rotation(body)); ok = false

	# 2. Частичный bias — покомпонентный lerp к ориентации офсета, затем нормализация (:431).
	applier.SetOffset("neck", 0.5, target, false)
	applier.Apply(skel, anim, 12, 0.0, false, 0.0, Vector3.ZERO, false, 1.0, 10)
	if not quat_close(skel.get_bone_pose_rotation(neck),
			lerp_cw(base_neck, 0.5, target_n).normalized()):
		print("CHECK FAIL: абсолютный офсет bias=0.5 → ", skel.get_bone_pose_rotation(neck)); ok = false

	# 3. Относительный офсет: цель — офсет, ДОМНОЖЕННЫЙ на позу кадра (:429).
	applier.SetOffset("neck", 1.0, target, true)
	applier.Apply(skel, anim, 12, 0.0, false, 0.0, Vector3.ZERO, false, 1.0, 10)
	if not quat_close(skel.get_bone_pose_rotation(neck), (target_n * base_neck).normalized()):
		print("CHECK FAIL: относительный офсет → ", skel.get_bone_pose_rotation(neck)); ok = false

	# 4. Нулевой bias УДАЛЯЕТ запись (humanoidbase.cpp:869-870), а не пишет нулевое влияние.
	applier.SetOffset("neck", 0.0, target, false)
	applier.Apply(skel, anim, 12, 0.0, false, 0.0, Vector3.ZERO, false, 1.0, 10)
	if not quat_close(skel.get_bone_pose_rotation(neck), base_neck):
		print("CHECK FAIL: bias=0 не удалил офсет → ", skel.get_bone_pose_rotation(neck)); ok = false

	# 5. Офсет на кости, которой нет в клипе, ничего не ломает: поиск идёт по узлам клипа.
	applier.SetOffset("нет_такой_кости", 1.0, target, false)
	applier.Apply(skel, anim, 12, 0.0, false, 0.0, Vector3.ZERO, false, 1.0, 10)
	if not quat_close(skel.get_bone_pose_rotation(neck), base_neck):
		print("CHECK FAIL: посторонний офсет задел neck → ", skel.get_bone_pose_rotation(neck)); ok = false

	skel.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

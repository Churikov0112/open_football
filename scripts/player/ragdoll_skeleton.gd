class_name RagdollSkeleton
extends RefCounted

## Кости, которые не превращаем в физкости (мелкие → взрыв солвера, невидимы с камеры).
const SKIP_SUBSTRINGS := ["Hand", "Finger", "Toe", "Thumb", "Index", "Middle", "Ring", "Pinky"]

## Угловые лимиты cone-джойнта (градусы; тюнинг-старт). PIN-джойнты (было изначально)
## не ограничивают вращение вообще — цепочка из 18 капсул с нулевым сопротивлением
## вращению от одного импульса схлопывается в спутанную массу ("гигантский блин" из
## живого прогона). swing — раскрыв конуса относительно направления кости; twist —
## вращение вокруг собственной оси (Godot-дефолт 180° — фактически свободное).
const JOINT_SWING_SPAN_DEG := 45.0
const JOINT_TWIST_SPAN_DEG := 30.0

var _skeleton: Skeleton3D
var _bones: Array = []          # созданные PhysicalBone3D
var _hip: PhysicalBone3D
var _active: bool = false

func _skip(bone_name: String) -> bool:
	for s in SKIP_SUBSTRINGS:
		if bone_name.contains(s):
			return true
	return false

## Первый ребёнок любого рода (для теста «лист» и фолбэка размера капсулы), или -1.
func _first_child(skel: Skeleton3D, bone_id: int) -> int:
	for b in skel.get_bone_count():
		if skel.get_bone_parent(b) == bone_id:
			return b
	return -1

## Первый НЕ-исключённый ребёнок (предпочтительно им меряем капсулу), или -1.
func _first_unskipped_child(skel: Skeleton3D, bone_id: int) -> int:
	for b in skel.get_bone_count():
		if skel.get_bone_parent(b) == bone_id and not _skip(skel.get_bone_name(b)):
			return b
	return -1

## Построить дремлющий физскелет как детей skeleton. Одна физкость на не-листовую
## не-исключённую кость; капсула тянется к её первому ребёнку. Возвращает число костей.
func build(skeleton: Skeleton3D, layer: int) -> int:
	_skeleton = skeleton
	# Skeleton3D часто сидит под масштабированным предком (Mixamo-риги: 0.01, cm→m без
	# запекания при экспорте). PhysicalBone3D всегда работает в НАСТОЯЩИХ мировых
	# единицах (Godot сам компенсирует масштаб предка в собственном transform физкости —
	# её глобальный scale всегда 1.0), а get_bone_rest() отдаёт длины в "сырых" локальных
	# единицах скелета (сотни вместо метров при scale=0.01). Без этой поправки капсулы
	# получаются в 1/scale раз больше нужного — отсюда гигантский, разлетающийся при
	# столкновениях ragdoll.
	var world_scale := skeleton.global_transform.basis.get_scale().x
	if world_scale <= 0.0:
		world_scale = 1.0
	for bone_id in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone_id)
		if _skip(bone_name):
			continue
		var any_child := _first_child(skeleton, bone_id)
		if any_child < 0:
			continue  # истинный лист — физкость не строим
		var sizing_child := _first_unskipped_child(skeleton, bone_id)
		if sizing_child < 0:
			sizing_child = any_child  # единственный ребёнок исключён (напр. кисть) — мерим по нему
		var child_rest := skeleton.get_bone_rest(sizing_child)
		var length := maxf(child_rest.origin.length() * world_scale, 0.05)
		var pb := PhysicalBone3D.new()
		pb.bone_name = bone_name
		pb.collision_layer = layer
		pb.collision_mask = FootballConstants.BOUNDARY_COLLISION_LAYER   # слой пола — приземляемся на пол, не трогая мяч(слой1)/игроков(слой2)
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		# joint_constraints/*_span у PhysicalBone3D — в градусах (дефолт движка сам это
		# подтверждает: swing_span=45.0, twist_span=180.0 — разумные "45°"/"180°", а не
		# абсурдные тысячи градусов, какими были бы 45/180 радиан).
		pb.set("joint_constraints/swing_span", JOINT_SWING_SPAN_DEG)
		pb.set("joint_constraints/twist_span", JOINT_TWIST_SPAN_DEG)
		# Капсула вдоль направления к ребёнку, центр на середине кости.
		var dir := child_rest.origin.normalized()
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.height = length
		cap.radius = clampf(length * 0.18, 0.03, 0.12)
		cs.shape = cap
		cs.transform = Transform3D(_axis_to(dir), dir * length * 0.5)
		pb.add_child(cs)
		skeleton.add_child(pb)
		_bones.append(pb)
		if bone_name.to_lower().contains("hips"):
			_hip = pb
	if _hip == null and not _bones.is_empty():
		_hip = _bones[0]
	return _bones.size()

## Базис, ставящий локальную ось Y капсулы вдоль dir.
func _axis_to(dir: Vector3) -> Basis:
	var y := dir
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func start(impulse: Vector3) -> void:
	if _skeleton == null or _bones.is_empty():
		return
	_skeleton.physical_bones_start_simulation()
	_active = true
	if _hip != null:
		_hip.apply_central_impulse(impulse)

func stop() -> void:
	if _skeleton == null:
		return
	_skeleton.physical_bones_stop_simulation()
	_active = false

func active() -> bool:
	return _active

## Мировая позиция таза (для ведения CharacterBody3D за ragdoll и снапа при вставании).
func hip_position() -> Vector3:
	if _hip != null:
		return _hip.global_position
	if _skeleton != null:
		return _skeleton.global_position
	return Vector3.ZERO

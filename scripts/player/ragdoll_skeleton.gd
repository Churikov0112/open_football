class_name RagdollSkeleton
extends RefCounted

## Кости, которые не превращаем в физкости (мелкие → взрыв солвера, невидимы с камеры).
const SKIP_SUBSTRINGS := ["Hand", "Finger", "Toe", "Thumb", "Index", "Middle", "Ring", "Pinky"]

var _skeleton: Skeleton3D
var _bones: Array = []          # созданные PhysicalBone3D
var _hip: PhysicalBone3D
var _active: bool = false

func _skip(bone_name: String) -> bool:
	for s in SKIP_SUBSTRINGS:
		if bone_name.contains(s):
			return true
	return false

## Первый не-исключённый ребёнок кости (для размера капсулы), или -1.
func _first_child(skel: Skeleton3D, bone_id: int) -> int:
	for b in skel.get_bone_count():
		if skel.get_bone_parent(b) == bone_id and not _skip(skel.get_bone_name(b)):
			return b
	return -1

## Построить дремлющий физскелет как детей skeleton. Одна физкость на не-листовую
## не-исключённую кость; капсула тянется к её первому ребёнку. Возвращает число костей.
func build(skeleton: Skeleton3D, layer: int) -> int:
	_skeleton = skeleton
	for bone_id in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone_id)
		if _skip(bone_name):
			continue
		var child := _first_child(skeleton, bone_id)
		if child < 0:
			continue  # лист — накрыт капсулой родителя
		var child_rest := skeleton.get_bone_rest(child)
		var length := maxf(child_rest.origin.length(), 0.05)
		var pb := PhysicalBone3D.new()
		pb.bone_name = bone_name
		pb.collision_layer = layer
		pb.collision_mask = FootballConstants.BOUNDARY_COLLISION_LAYER   # слой пола — приземляемся на пол, не трогая мяч(слой1)/игроков(слой2)
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_PIN  # старт: свободные пины (стабильно);
		                                               # cone-лимиты — живой тюнинг
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

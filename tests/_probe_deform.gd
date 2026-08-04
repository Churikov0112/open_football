extends SceneTree

# Зонд: где 14-костный скелет ломает силуэт болванки.
#
# Рендер не нужен — скиннинг считается на CPU по тем же данным, что ушли бы на
# GPU: v' = Σ wᵢ · (globalᵢ · global_restᵢ⁻¹) · v. Мерим, как меняются длины
# рёбер меша против рест-позы: сильно сжатое ребро — схлопнувшийся сустав,
# сильно растянутое — разъехавшаяся оболочка. Зона ребра = кость с наибольшим
# суммарным весом на его концах.
#
# Глобальные трансформы считаются ЗДЕСЬ, обходом иерархии, а не через
# Skeleton3D.get_bone_global_pose(): в headless Godot пересчитывает позы
# отложенно, и без обработки кадра геттер отдаёт рест — поза «не меняется».
# Поза ставится из клипа напрямую (SampleRotation), минуя AnimationApplier.Apply:
# через мост GDScript→C# тот молча ничего не делает. Для метрики этого хватает —
# доворот корня, сглаживание и ограничитель угловой скорости на длины рёбер
# не влияют.
#
# Запуск (headless):
#   & "<godot>" --path "<repo>" --headless -s "res://tests/_probe_deform.gd"

# Переопределяется переменной окружения GPF_MODEL (пусто → болванка) —
# тот же зонд гоняется и по MakeHuman-телу.
var MODEL: String = OS.get_environment("GPF_MODEL") if OS.get_environment("GPF_MODEL") != "" \
		else "res://assets/models/gpf_blockout.glb"

# Клипы подобраны под подозреваемые зоны: руки над головой, глубокий наклон,
# полный шаг, подкат, перекат через спину.
const CLIPS := [
	["keeper_high_deflect", "res://assets/gpf/animations/deflect/idle/000_high_deflect_close.anim"],
	["keeper_ground_hold", "res://assets/gpf/animations/deflect/idle/000_ground_holdball.anim"],
	["sprint", "res://assets/gpf/animations/movement/sprint/000_idlelevel1.anim"],
	["shot", "res://assets/gpf/animations/shot/idle/020.anim"],
	["sliding", "res://assets/gpf/animations/sliding/idle/000.anim"],
	["stand_up", "res://assets/gpf/animations/movement_special/idle/special/000_stand_up_from_back.anim"],
]

const SQUEEZE := 0.55   # ниже — схлопывание
const STRETCH := 1.60   # выше — разрыв оболочки
const FRAMES_PER_CLIP := 10


func _find_all(node: Node, type_name: String) -> Array:
	var out: Array = []
	if node.is_class(type_name):
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_all(child, type_name))
	return out


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _find(child, type_name)
		if found != null:
			return found
	return null


func _initialize() -> void:
	print("== _probe_deform ==")

	var inst: Node3D = load(MODEL).instantiate()
	root.add_child(inst)
	var skel: Skeleton3D = _find(inst, "Skeleton3D")
	var count: int = skel.get_bone_count()

	for i in count:
		if skel.get_bone_parent(i) >= i:
			print("!! кость %d идёт раньше родителя — обход иерархии неверен" % i)
			quit(1)
			return

	# Модель бывает из НЕСКОЛЬКИХ мешей: у оригинальной fullbody их 12, и веса
	# там живут внутри части. Взять первый MeshInstance3D — значит померить одну
	# двенадцатую и получить ложно-зелёный результат.
	var parts: Array = []
	for mi in _find_all(skel, "MeshInstance3D"):
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]

		# ARRAY_BONES индексирует СКИН, а не скелет: у glTF свой порядок joints.
		# Рест-самопроверка перестановку не ловит (в ресте все матрицы единичны),
		# поэтому маппинг обязателен — иначе вершины тянут чужие кости.
		var skin: Skin = mi.skin
		var skin_to_bone: PackedInt32Array = PackedInt32Array()
		var bind_inv: Array[Transform3D] = []
		for i in skin.get_bind_count():
			var b: int = skin.get_bind_bone(i)
			if b < 0:
				b = skel.find_bone(skin.get_bind_name(i))
			skin_to_bone.append(b)
			bind_inv.append(skin.get_bind_pose(i))

		var edges: Array = _collect_edges(arrays[Mesh.ARRAY_INDEX])
		var per_vertex: int = bones.size() / verts.size()
		var rest_len: PackedFloat32Array = PackedFloat32Array()
		var edge_zone: PackedInt32Array = PackedInt32Array()
		for e in edges:
			rest_len.append((verts[e[0]] - verts[e[1]]).length())
			edge_zone.append(skin_to_bone[_dominant_bone(e[0], e[1], bones,
					arrays[Mesh.ARRAY_WEIGHTS], per_vertex, skin.get_bind_count())])

		parts.append({
			"name": mi.name, "verts": verts, "bones": bones,
			"weights": arrays[Mesh.ARRAY_WEIGHTS], "per_vertex": per_vertex,
			"binds": skin.get_bind_count(), "skin_to_bone": skin_to_bone,
			"bind_inv": bind_inv, "edges": edges, "rest_len": rest_len,
			"edge_zone": edge_zone,
		})

	var total_verts: int = 0
	var total_edges: int = 0
	for p in parts:
		total_verts += p["verts"].size()
		total_edges += p["edges"].size()
	print("частей меша: %d, вершин: %d, костей: %d" % [parts.size(), total_verts, count])

	var rest: Array[Transform3D] = _globals(skel, null, 0)

	# Рёбра-стыки — те, чьи концы тянут разные кости. Только они и могут
	# показать схлопывание; если их нет, оболочка не сшита и метрика вырождена.
	var seam: int = 0
	for p in parts:
		for e in p["edges"]:
			if _dominant_bone(e[0], e[0], p["bones"], p["weights"], p["per_vertex"], p["binds"]) \
					!= _dominant_bone(e[1], e[1], p["bones"], p["weights"], p["per_vertex"], p["binds"]):
				seam += 1
	print("рёбер всего %d, из них через стык костей: %d" % [total_edges, seam])

	# Самопроверка: с рест-глобалами skin-матрица единична, деформации быть не должно.
	var dev: float = 0.0
	for p in parts:
		var at_rest: PackedVector3Array = _skin(p["verts"], p["bones"], p["weights"],
				p["per_vertex"], rest, p["bind_inv"], p["skin_to_bone"])
		for i in p["verts"].size():
			dev = max(dev, (at_rest[i] - p["verts"][i]).length())
	print("рест: max отклонение %.6f м (должно быть ~0)" % dev)

	# Рука и нога — несмежные цепочки. Вершина, которую тянут обе, означает, что
	# автоскиннинг склеил их: в рест-позе (руки вниз) кисть сидит вплотную к бедру.
	var bled: int = 0
	for p in parts:
		var arm := {}
		var leg := {}
		for i in p["binds"]:
			var n: String = skel.get_bone_name(p["skin_to_bone"][i])
			if n.ends_with("shoulder") or n.ends_with("elbow"):
				arm[i] = true
			elif n.ends_with("thigh") or n.ends_with("knee") or n.ends_with("ankle"):
				leg[i] = true

		for v in p["verts"].size():
			var has_arm := false
			var has_leg := false
			for k in p["per_vertex"]:
				if p["weights"][v * p["per_vertex"] + k] <= 0.01:
					continue
				var b: int = p["bones"][v * p["per_vertex"] + k]
				if arm.has(b):
					has_arm = true
				elif leg.has(b):
					has_leg = true
			if has_arm and has_leg:
				bled += 1
	print("вершин, которые тянут и рука, и нога: %d из %d" % [bled, total_verts])

	var probe = load("res://src/gpf/Animation.cs").new()
	probe.LoadFromFile(CLIPS[0][1])
	var bad := ""
	for i in count:
		var q: Quaternion = probe.SampleRotation(skel.get_bone_name(i), 12, 0.0)
		if abs(q.length() - 1.0) > 0.01:
			bad += " %s(|q|=%.3f)" % [skel.get_bone_name(i), q.length()]
	print("вырожденных кватернионов:%s\n" % (bad if bad != "" else " нет"))

	var worst: Dictionary = {}   # bone -> [min, max, clip_min, frame_min, clip_max, frame_max]

	for entry in CLIPS:
		var label: String = entry[0]
		var path: String = entry[1]
		if not FileAccess.file_exists(path):
			print("нет клипа: ", path)
			continue

		var anim = load("res://src/gpf/Animation.cs").new()
		anim.LoadFromFile(path)
		var frames: int = anim.GetFrameCount()
		var step: int = max(1, frames / FRAMES_PER_CLIP)
		var moved: float = 0.0

		for frame in range(0, frames, step):
			var globals: Array[Transform3D] = _globals(skel, anim, frame)
			moved = max(moved, (globals[skel.find_bone("left_elbow")].origin
					- rest[skel.find_bone("left_elbow")].origin).length())

			for p in parts:
				var posed: PackedVector3Array = _skin(p["verts"], p["bones"], p["weights"],
						p["per_vertex"], globals, p["bind_inv"], p["skin_to_bone"])
				var edges: Array = p["edges"]
				for ei in edges.size():
					if p["rest_len"][ei] < 0.0005:
						continue
					var ratio: float = (posed[edges[ei][0]] - posed[edges[ei][1]]).length() \
							/ p["rest_len"][ei]
					var zone: int = p["edge_zone"][ei]
					if not worst.has(zone):
						worst[zone] = [ratio, ratio, label, frame, label, frame]
					var w: Array = worst[zone]
					if ratio < w[0]:
						w[0] = ratio
						w[2] = label
						w[3] = frame
					if ratio > w[1]:
						w[1] = ratio
						w[4] = label
						w[5] = frame

		print("  %-20s кадров %3d, локоть уходит от рест-позы до %.2f м" % [label, frames, moved])

	print("\nсжатие/растяжение рёбер по зонам (1.00 = без деформации):")
	print("%-16s %6s %-24s %6s %-24s" % ["зона", "min", "где", "max", "где"])
	for i in count:
		if not worst.has(i):
			continue
		var w: Array = worst[i]
		var flag := ""
		if w[0] < SQUEEZE:
			flag = "  <-- схлопывание"
		elif w[1] > STRETCH:
			flag = "  <-- растяжение"
		print("%-16s %6.2f %-24s %6.2f %-24s%s" % [
			skel.get_bone_name(i), w[0], "%s@%d" % [w[2], w[3]],
			w[1], "%s@%d" % [w[4], w[5]], flag])

	inst.queue_free()
	quit()


# anim == null → рест-глобалы. Иерархия обходится по возрастанию индекса:
# родитель гарантированно раньше ребёнка (проверено выше).
func _globals(skel: Skeleton3D, anim, frame: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in skel.get_bone_count():
		var name: String = skel.get_bone_name(i)
		var basis := Basis.IDENTITY
		if anim != null and name != "player":
			basis = Basis(anim.SampleRotation(name, frame, 0.0))
		var local := Transform3D(basis, skel.get_bone_rest(i).origin)
		var p: int = skel.get_bone_parent(i)
		out.append(local if p < 0 else out[p] * local)
	return out


func _collect_edges(indices: PackedInt32Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for t in range(0, indices.size(), 3):
		for k in 3:
			var a: int = indices[t + k]
			var b: int = indices[t + (k + 1) % 3]
			var key: int = (min(a, b) << 20) | max(a, b)
			if seen.has(key):
				continue
			seen[key] = true
			out.append([a, b])
	return out


func _dominant_bone(v0: int, v1: int, bones: PackedInt32Array,
		weights: PackedFloat32Array, per_vertex: int, bone_count: int) -> int:
	var acc: PackedFloat32Array = PackedFloat32Array()
	acc.resize(bone_count)
	for v in [v0, v1]:
		for k in per_vertex:
			var b: int = bones[v * per_vertex + k]
			if b >= 0 and b < bone_count:
				acc[b] += weights[v * per_vertex + k]
	var best: int = 0
	for i in bone_count:
		if acc[i] > acc[best]:
			best = i
	return best


func _skin(verts: PackedVector3Array, bones: PackedInt32Array,
		weights: PackedFloat32Array, per_vertex: int, globals: Array[Transform3D],
		bind_inv: Array[Transform3D], skin_to_bone: PackedInt32Array) -> PackedVector3Array:
	var mats: Array[Transform3D] = []
	for i in bind_inv.size():
		mats.append(globals[skin_to_bone[i]] * bind_inv[i])

	var out: PackedVector3Array = PackedVector3Array()
	out.resize(verts.size())
	for v in verts.size():
		var acc := Vector3.ZERO
		var total: float = 0.0
		for k in per_vertex:
			var w: float = weights[v * per_vertex + k]
			if w <= 0.0:
				continue
			acc += (mats[bones[v * per_vertex + k]] * verts[v]) * w
			total += w
		out[v] = acc / total if total > 0.0 else verts[v]
	return out

extends SceneTree
# Тикет 06 фазы 7: визуальная деформация сетки — Match::UpdateGoalNetting (match.cpp:2159-2209).
# Тест перевычисляет формулу подтягивания вершин по C++ и сверяет с вершинами меша после
# Update + Upload. Пара к check_gpf_netting.gd: там ФИЗИКА сетки (ball.cpp:331-408), тут
# ПРЕЗЕНТАЦИЯ, и вход у неё один — флаг касания из физики, своей коллизии нет.
#
# Ядро порта тут не тикает (только математика меша) — маршалинг Gpf.* не задействован.
#
# Два квирка оригинала, которые тест пинит НАРОЧНО:
#  1. Вершина смешивается ВСЕГДА от исходной (nettingMeshesSrc, :2178), а не от текущей —
#     деформация не накапливается от кадра к кадру.
#  2. При нулевом influenceBias запись не делается вовсе (:2187) — мяч, вышедший за плоскость
#     штанг, оставляет сетку деформированной до ветки сброса, а не расправляет её.

const THRESHOLD := 55.06  # pitchHalfW + 0.06 (:2148-2149)
const GOALS_GLB := "res://assets/models/gpf_goals.glb"

var _fails := 0


func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("  FAIL: ", msg)


# vector3.cpp:230-244 GetDistance — ранний выход на нулевой разнице, обнуление длины < 1e-6.
func dist(a: Vector3, b: Vector3) -> float:
	var d := a - b
	if d.x == 0.0 and d.y == 0.0 and d.z == 0.0:
		return 0.0
	var l := sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
	return 0.0 if l < 0.000001 else l


# Ожидаемая позиция ОДНОЙ вершины сетки (:2178-2191). `prev` — что лежит в вершине сейчас:
# при нулевом bias оригинал не пишет ничего, и остаётся именно prev.
func expected(vertex: Vector3, prev: Vector3, ball: Vector3, shortest: float) -> Vector3:
	var bias: float = pow(clampf((shortest + 0.0001) / (dist(vertex, ball) + 0.0001), 0.0, 1.0), 1.5)
	# сетка прибита к штангам — ослабление возле них (:2183)
	var woodwork_inv: float = clampf((absf(ball.x) - 55.0) * 2.0, 0.0, 1.0)
	bias *= woodwork_inv
	bias = sin(bias * PI - 0.5 * PI) * 0.5 + 0.5  # :2186
	if bias > 0.0:  # :2187
		return vertex * (1.0 - bias) + ball * bias
	return prev


# Сторона мяча (:2162) и её фильтр: 0 — левые ворота, 1 — правые.
func on_ball_side(v: Vector3, ball: Vector3) -> bool:
	return v.x < -THRESHOLD if ball.x < 0.0 else v.x > THRESHOLD


# [[MeshInstance3D, surface, PackedVector3Array], ...] — ВСЕ поверхности всех мешей ворот
# (GoalNetting обрабатывает их все, тест обязан смотреть туда же).
func _verts(root: Node) -> Array:
	var out := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			out.append([mi, s, mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]])
	return out


# Плоский снимок вершин: ключ — «id узла#поверхность» (узлы вне дерева, get_path() там
# недоступен), значение — массив вершин.
func _snapshot(root: Node) -> Dictionary:
	var snap := {}
	for entry in _verts(root):
		snap["%d#%d" % [entry[0].get_instance_id(), entry[1]]] = entry[2].duplicate()
	return snap


# Сверяет текущую геометрию с ожидаемой (снимок такой же формы).
func _expect(root: Node, want: Dictionary, what: String) -> void:
	var reported := 0
	for entry in _verts(root):
		var key := "%d#%d" % [entry[0].get_instance_id(), entry[1]]
		if not want.has(key):
			_fail("%s: поверхность %s пропала" % [what, key])
			continue
		var now: PackedVector3Array = entry[2]
		var exp_verts: PackedVector3Array = want[key]
		if now.size() != exp_verts.size():
			_fail("%s: %s — вершин %d, ожидалось %d" % [what, key, now.size(), exp_verts.size()])
			continue
		for i in now.size():
			if now[i].distance_to(exp_verts[i]) > 1e-4:
				_fail("%s: вершина %d у %s = %s, ожидалось %s"
						% [what, i, key, now[i], exp_verts[i]])
				reported += 1
				if reported >= 3:
					return
				break


# Ожидаемый снимок после Update(true, ball) поверх состояния `prev`.
func _deform(src: Dictionary, prev: Dictionary, ball: Vector3) -> Dictionary:
	var shortest := 100000.0  # :2165-2174 — минимум по вершинам стороны мяча, от ИСХОДНЫХ
	for key in src:
		for v in src[key]:
			if on_ball_side(v, ball):
				shortest = minf(shortest, dist(v, ball))

	var want := {}
	for key in src:
		var verts: PackedVector3Array = src[key].duplicate()
		for i in verts.size():
			verts[i] = (expected(src[key][i], prev[key][i], ball, shortest)
					if on_ball_side(src[key][i], ball) else prev[key][i])
		want[key] = verts
	return want


func _spread(a: Dictionary, b: Dictionary) -> Array:
	var moved := 0
	var max_shift := 0.0
	for key in a:
		for i in a[key].size():
			var shift: float = a[key][i].distance_to(b[key][i])
			if shift > 1e-5:
				moved += 1
			max_shift = maxf(max_shift, shift)
	return [moved, max_shift]


func _initialize() -> void:
	print("== check_gpf_netting_deform ==")

	var G = load("res://src/lab/GoalNetting.cs")
	if G == null:
		_fail("нет GoalNetting.cs — сначала dotnet build")
		_done()
		return
	if not ResourceLoader.exists(GOALS_GLB):
		_fail("нет %s — собери tools/build_gpf_stadium.py" % GOALS_GLB)
		_done()
		return

	var root: Node = (load(GOALS_GLB) as PackedScene).instantiate()
	var src := _snapshot(root)  # исходная геометрия, ДО Prepare

	var netting = G.new()
	netting.Prepare(root)

	# ---------- 1. Prepare отдаёт собственную копию меша, не трогая геометрию ----------
	_expect(root, src, "Prepare")

	# Материалы обязаны пережить подмену меша: слот `mat<NN>` в самом меше и перекрытие на
	# узле (его ставит AseMaterials). Потеря слота рисует сетку сплошным полотном —
	# вершинами такое не ловится.
	for entry in _verts(root):
		if entry[0].mesh.surface_get_material(entry[1]) == null:
			_fail("после Prepare у %s#%d пропал слот материала" % [entry[0].name, entry[1]])

	# ---------- 2. Деформация справа совпадает с перевычислением формул C++ ----------
	var ball_a := Vector3(56.5, 0.5, 1.2)  # мяч в ПРАВЫХ воротах (sideID = 1)
	var want_a := _deform(src, src, ball_a)
	netting.Update(true, ball_a)
	netting.Upload()
	_expect(root, want_a, "деформация справа")

	var spread: Array = _spread(want_a, src)
	if spread[0] < 100 or spread[1] < 0.1:
		_fail("деформация не видна глазами: сдвинуто %d вершин, максимум %.4f м" % spread)
	else:
		print("деформировано %d вершин, макс сдвиг %.3f м" % spread)

	# ---------- 3. Второй кадр подряд считается ОТ ИСХОДНЫХ вершин (:2178) ----------
	# Ловит накопление деформации: реализация, читающая текущую вершину вместо источника,
	# на этом шаге разойдётся.
	var ball_b := Vector3(56.9, -1.4, 1.9)
	var want_b := _deform(src, want_a, ball_b)
	netting.Update(true, ball_b)
	netting.Upload()
	_expect(root, want_b, "второй кадр деформации")

	# ---------- 4. КВИРК: мяч на линии ворот — записи нет, деформация ЗАЛИПАЕТ ----------
	# woodworkTensionBiasInv = 0 → influenceBias = 0 → ветка :2187 не пишет ничего, и в
	# вершинах остаётся кадр из шага 3 (расправляет сетку только ветка сброса).
	netting.Update(true, Vector3(55.0, 0.5, 1.2))
	netting.Upload()
	_expect(root, want_b, "мяч на линии ворот (деформация обязана залипнуть)")

	# ---------- 5. Возврат формы, когда касания больше нет (:2197-2207) ----------
	netting.Update(false, ball_b)
	netting.Upload()
	_expect(root, src, "возврат формы")

	# ---------- 6. Левые ворота: sideID = 0, правая сторона не трогается ----------
	var ball_l := Vector3(-56.5, 0.5, 1.2)
	var want_l := _deform(src, src, ball_l)
	netting.Update(true, ball_l)
	netting.Upload()
	_expect(root, want_l, "деформация слева")

	netting.Update(false, ball_l)
	netting.Upload()
	_expect(root, src, "возврат формы слева")

	# ---------- 7. Мяч снаружи: физика флага не даёт — сетка не шевелится ----------
	# (внешние ветки касания в ball.cpp:369-373, :388-392 закомментированы в оригинале)
	netting.Update(false, Vector3(58.5, 0.0, 1.0))
	netting.Upload()
	_expect(root, src, "мяч снаружи")

	root.free()
	_done()


func _done() -> void:
	print("CHECK PASS" if _fails == 0 else "CHECK FAIL: %d расхождений" % _fails)
	quit(1 if _fails > 0 else 0)

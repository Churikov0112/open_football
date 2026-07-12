class_name NetSim
extends Object

# Строит объёмную сетку ворот из 4 независимых панелей (задняя, верх, левая,
# правая; низ открыт). Каждая панель — прямоугольная решётка; её внешнее кольцо
# узлов закреплено (лежит на пруте каркаса), интерьер свободен и колышется.
# Чистая функция: НЕ читает FootballConstants.
static func build_box_net(width: float, height: float, depth: float,
		w_div: int, h_div: int, d_div: int) -> Dictionary:
	var net := {
		"pos": PackedVector3Array(),
		"rest": PackedVector3Array(),
		"prev": PackedVector3Array(),
		"normal": PackedVector3Array(),
		"pinned": PackedByteArray(),
		"edges": PackedInt32Array(),
		"rest_len": PackedFloat32Array(),
	}
	var hw := width * 0.5
	# Задняя панель: плоскость z=depth, u=x по ширине, v=y по высоте, нормаль +z.
	_add_panel(net, w_div, h_div, Vector3(0, 0, 1),
		func(su: float, sv: float) -> Vector3:
			return Vector3(lerpf(-hw, hw, su), lerpf(0.0, height, sv), depth))
	# Верхняя панель: плоскость y=height, u=x по ширине, v=z по глубине, нормаль +y.
	_add_panel(net, w_div, d_div, Vector3(0, 1, 0),
		func(su: float, sv: float) -> Vector3:
			return Vector3(lerpf(-hw, hw, su), height, lerpf(0.0, depth, sv)))
	# Левая панель: плоскость x=-hw, u=z по глубине, v=y по высоте, нормаль -x.
	_add_panel(net, d_div, h_div, Vector3(-1, 0, 0),
		func(su: float, sv: float) -> Vector3:
			return Vector3(-hw, lerpf(0.0, height, sv), lerpf(0.0, depth, su)))
	# Правая панель: плоскость x=hw, u=z по глубине, v=y по высоте, нормаль +x.
	_add_panel(net, d_div, h_div, Vector3(1, 0, 0),
		func(su: float, sv: float) -> Vector3:
			return Vector3(hw, lerpf(0.0, height, sv), lerpf(0.0, depth, su)))
	return net

# Добавляет одну панель-решётку (u_div×v_div ячеек) в net. point(su,sv) даёт
# позицию узла по нормализованным координатам su,sv ∈ [0,1]. Узлы на границе
# решётки закрепляются (pinned=1).
static func _add_panel(net: Dictionary, u_div: int, v_div: int, normal: Vector3,
		point: Callable) -> void:
	var base: int = net["pos"].size()
	var cols := u_div + 1
	var rows := v_div + 1
	for j in range(rows):
		for i in range(cols):
			var p: Vector3 = point.call(float(i) / float(u_div), float(j) / float(v_div))
			net["pos"].append(p)
			net["rest"].append(p)
			net["prev"].append(p)
			net["normal"].append(normal)
			var on_edge := (i == 0 or i == u_div or j == 0 or j == v_div)
			net["pinned"].append(1 if on_edge else 0)
	# Структурные пружины: к правому и верхнему соседу.
	for j in range(rows):
		for i in range(cols):
			var idx := base + j * cols + i
			if i < cols - 1:
				_add_edge(net, idx, idx + 1)
			if j < rows - 1:
				_add_edge(net, idx, idx + cols)

static func _add_edge(net: Dictionary, a: int, b: int) -> void:
	net["edges"].append(a)
	net["edges"].append(b)
	net["rest_len"].append(net["pos"][a].distance_to(net["pos"][b]))

# Один шаг полу-неявного Verlet. Мутирует net["pos"]/net["prev"]. Силы —
# ускорения; интегрируется как pos += (pos-prev)*damping + force*dt*dt.
static func integrate(net: Dictionary, ball_pos: Vector3, ball_speed: float,
		p: Dictionary, dt: float) -> void:
	var pos: PackedVector3Array = net["pos"]
	var prev: PackedVector3Array = net["prev"]
	var rest: PackedVector3Array = net["rest"]
	var pinned: PackedByteArray = net["pinned"]
	var normal: PackedVector3Array = net["normal"]
	var edges: PackedInt32Array = net["edges"]
	var rest_len: PackedFloat32Array = net["rest_len"]
	var n := pos.size()

	var gravity: float = p["gravity"]
	var damping: float = p["damping"]
	var stiffness: float = p["stiffness"]
	var shape_return: float = p["shape_return"]
	var radius: float = p["ball_radius"]
	var vel_scale: float = p["ball_vel_scale"]
	var ball_force: float = p["ball_force"]

	var force := PackedVector3Array()
	force.resize(n)
	# Узловые силы: гравитация, возврат к форме, толчок мяча.
	for i in range(n):
		if pinned[i] == 1:
			continue
		var f := Vector3(0.0, -gravity, 0.0)
		f += (rest[i] - pos[i]) * shape_return
		var d := pos[i] - ball_pos
		var prox := 1.0 - smoothstep(radius, radius * 1.15, d.length())
		if prox > 0.0:
			f += normal[i] * prox * (1.0 + ball_speed * vel_scale) * ball_force
		force[i] = f
	# Пружины по рёбрам (симметрично на оба конца).
	var e := edges.size() / 2
	for k in range(e):
		var a: int = edges[k * 2]
		var b: int = edges[k * 2 + 1]
		var sv := pos[a] - pos[b]
		var length := sv.length()
		if length > 0.00001:
			var sf := -sv * (stiffness * (1.0 - rest_len[k] / length))
			if pinned[a] == 0:
				force[a] = force[a] + sf
			if pinned[b] == 0:
				force[b] = force[b] - sf
	# Verlet-шаг.
	var dt2 := dt * dt
	for i in range(n):
		if pinned[i] == 1:
			prev[i] = pos[i]
			continue
		var temp := pos[i]
		pos[i] = pos[i] + (pos[i] - prev[i]) * damping + force[i] * dt2
		prev[i] = temp
	net["pos"] = pos
	net["prev"] = prev

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

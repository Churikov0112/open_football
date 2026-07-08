extends SceneTree

func _initialize() -> void:
	var ok := true
	# синтетическое дерево: Node3D → MeshInstance3D(x2, вложенные)
	var root := Node3D.new()
	var m1 := MeshInstance3D.new()
	m1.mesh = BoxMesh.new()
	var m2 := MeshInstance3D.new()
	m2.mesh = BoxMesh.new()
	root.add_child(m1)
	m1.add_child(m2)
	var col := Color(0.9, 0.1, 0.1)
	var n := PlayerVisual.tint_tree(root, col)
	if n != 2:
		print("CHECK FAIL: ожидали 2 меша, получили ", n)
		ok = false
	var mat := m1.material_override as StandardMaterial3D
	if mat == null or not mat.albedo_color.is_equal_approx(col):
		print("CHECK FAIL: albedo m1 = ", mat.albedo_color if mat else "нет материала")
		ok = false
	var mat2 := m2.material_override as StandardMaterial3D
	if mat2 == null or not mat2.albedo_color.is_equal_approx(col):
		print("CHECK FAIL: albedo m2 не выставлен")
		ok = false
	root.free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

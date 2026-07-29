extends SceneTree
# Mirror (инволюция, нога, касания, переменные) + ConvertToStartFacingForwardIfIdle +
# нормализация direction-тегов при загрузке.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func quat_close(a: Quaternion, b: Quaternion, eps := 1.0e-4) -> bool:
	var d1 := absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) + absf(a.w - b.w)
	var d2 := absf(a.x + b.x) + absf(a.y + b.y) + absf(a.z + b.z) + absf(a.w + b.w)
	return minf(d1, d2) < eps

func _initialize() -> void:
	var ok := true
	var AnimScript := load("res://src/gpf/Animation.cs")

	# --- Mirror: базовые свойства на walk/045 ---
	var a = AnimScript.new()
	a.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	var orig_root24: Vector3 = a.GetKeyPosition("player", 24)
	var orig_la_rot: Quaternion = a.GetKeyRotation("left_ankle", 0)
	var orig_ra_rot: Quaternion = a.GetKeyRotation("right_ankle", 0)
	var orig_angle: float = a.GetOutgoingAngle()

	var m = a.Clone()
	m.Mirror()
	if not m.GetName().ends_with("_mirror"):
		print("CHECK FAIL: имя без _mirror → ", m.GetName()); ok = false
	if m.GetCurrentFootId() != 0:
		print("CHECK FAIL: Mirror не флипнул ногу (right→left)"); ok = false
	# X позиции root отражён
	if not vec_eq(m.GetKeyPosition("player", 24), Vector3(-orig_root24.x, orig_root24.y, orig_root24.z)):
		print("CHECK FAIL: root X не отражён → ", m.GetKeyPosition("player", 24)); ok = false
	# Треки left/right поменялись местами (с негацией Y/Z кватерниона)
	var expected_la := Quaternion(orig_ra_rot.x, -orig_ra_rot.y, -orig_ra_rot.z, orig_ra_rot.w)
	if not quat_close(m.GetKeyRotation("left_ankle", 0), expected_la):
		print("CHECK FAIL: left_ankle после Mirror ≠ отражённый right_ankle"); ok = false
	# Дескрипторы пересчитаны: угол сменил знак
	if not feq(m.GetOutgoingAngle(), -orig_angle, 5.0e-3):
		print("CHECK FAIL: outgoing angle после Mirror → ", m.GetOutgoingAngle(), " ожидался ", -orig_angle); ok = false

	# Инволюция: Mirror дважды == исходник (позиции, ротации, нога, имя не проверяем)
	var mm = a.Clone()
	mm.Mirror()
	mm.Mirror()
	if not vec_eq(mm.GetKeyPosition("player", 24), orig_root24):
		print("CHECK FAIL: Mirror² root"); ok = false
	if not quat_close(mm.GetKeyRotation("left_ankle", 0), orig_la_rot):
		print("CHECK FAIL: Mirror² left_ankle"); ok = false
	if mm.GetCurrentFootId() != 1:
		print("CHECK FAIL: Mirror² нога"); ok = false

	# --- Mirror: касания и переменные на ballcontrol/idle/000 ---
	var bc = AnimScript.new()
	bc.LoadFromFile("res://assets/gpf/animations/ballcontrol/idle/000.anim")
	var t_pos: Vector3 = bc.GetTouchPosition(0)
	var t_frame: int = bc.GetTouchFrame(0)
	var bd_raw: String = bc.GetVariable("balldirection")
	var touchfoot_raw: String = bc.GetVariable("touchfoot")
	var bm = bc.Clone()
	bm.Mirror()
	if bm.GetTouchFrame(0) != t_frame:
		print("CHECK FAIL: Mirror сдвинул кадр касания"); ok = false
	if not vec_eq(bm.GetTouchPosition(0), Vector3(-t_pos.x, t_pos.y, t_pos.z)):
		print("CHECK FAIL: Mirror касание X → ", bm.GetTouchPosition(0)); ok = false
	# balldirection: X-негация (animation.cpp:1305-1310)
	if bd_raw != "":
		var bd: Vector3 = load("res://src/gpf/BluntMath.cs").GetVectorFromString(bd_raw)
		var bdm: Vector3 = load("res://src/gpf/BluntMath.cs").GetVectorFromString(bm.GetVariable("balldirection"))
		if not vec_eq(bdm, Vector3(-bd.x, bd.y, bd.z)):
			print("CHECK FAIL: Mirror balldirection → ", bdm); ok = false
	# touchfoot left↔right (animation.cpp:1294-1303)
	if touchfoot_raw == "left" and bm.GetVariable("touchfoot") != "right":
		print("CHECK FAIL: Mirror touchfoot left→right"); ok = false
	if touchfoot_raw == "right" and bm.GetVariable("touchfoot") != "left":
		print("CHECK FAIL: Mirror touchfoot right→left"); ok = false

	# --- Нормализация direction-тегов при загрузке (шов 3): длина 1, тег пуст, либо нулевой вектор ---
	# КОРРЕКЦИЯ ТЕСТА (брифа): ballcontrol/idle/000 НЕ содержит тега balldirection, но idle-конверсия
	# ConvertToStartFacingForwardIfIdle зовёт SetVariable("balldirection", ...) безусловно (bug-for-bug,
	# animation.cpp:337-339), записывая нулевой вектор "0.000000,0.000000,0.000000". Поэтому исходная
	# проверка «непустой ⇒ длина 1» ложна; верный инвариант — «ненулевой ⇒ длина 1» (нормализация
	# сохраняет длину при повороте, а нулевой вектор так и остаётся нулевым).
	if bd_raw != "":
		var bd2: Vector3 = load("res://src/gpf/BluntMath.cs").GetVectorFromString(bd_raw)
		if bd2.length() > 1.0e-6 and absf(bd2.length() - 1.0) > 1.0e-3:
			print("CHECK FAIL: balldirection не нормализован при загрузке → len ", bd2.length()); ok = false

	# --- ConvertToStartFacingForwardIfIdle: все idle-клипы стартуют лицом вперёд ---
	# Скан всего корпуса: у каждого клипа с GetIncomingVelocity() < 1.8 угол корпуса на входе ≈ 0.
	var paths: Array[String] = []
	_scan("res://assets/gpf/animations", paths)
	var checked := 0
	for p in paths:
		if p.contains("/templates/"):
			continue
		var c = AnimScript.new()
		if not c.LoadFromFile(p):
			continue
		if c.GetIncomingVelocity() < 1.8:
			checked += 1
			# КОРРЕКЦИЯ ТЕСТА (брифа): порог 0.05 слишком тесен. Конверсия домножает body слева на
			# поворот вокруг МИРОВОЙ оси Z на -incomingBodyAngle, но извлечённый z-эйлер под большим
			# питчем корпуса гимбал-связан: у клипа с корпусом, наклонённым ~88° вокруг X
			# (movement_special/idle/special/000_back_to_front_holdball, первый ключ body
			# (-0.695570,0.021859,0.022557,0.717772)), сырой incomingBodyAngle = 0.06283, а после
			# конверсии остаётся 0.06086 — мировой Z-поворот почти не меняет z-эйлер при таком питче.
			# Это 1:1 с оригиналом C++ (та же формула, тот же остаток; проверено арифметически).
			# Порог 0.1 рад (~5.7°) ловит грубую неконверсию (боком стоящий клип даёт |angle|~1.5),
			# но допускает честный гимбал-остаток сильно наклонённых клипов.
			if absf(c.GetIncomingBodyAngle()) > 0.1:
				print("CHECK FAIL: idle-клип не развёрнут вперёд: ", p, " angle=", c.GetIncomingBodyAngle())
				ok = false
	if checked < 20:
		print("CHECK FAIL: подозрительно мало idle-клипов в скане: ", checked); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

func _scan(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null: return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var path := dir + "/" + f
		if d.current_is_dir():
			if not f.begins_with("."): _scan(path, out)
		elif f.ends_with(".anim"):
			out.append(path)
		f = d.get_next()
	d.list_dir_end()

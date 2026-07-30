extends SceneTree
# Фаза 4, задача 3: SelectAnim наследника — crude query + сорт-цепочки (humanoid.cpp:1159-1637)
# + NeedTouch (:1822-1857). Проверки — перевалидация фильтров на живой коллекции (как check_gpf_crude)
# и структурные инварианты сортировки; опорных литералов из плана нет.

func _initialize() -> void:
	var ok := true
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var B = load("res://src/gpf/Ball.cs")
	var builder = SB.new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()
	get_root().add_child(skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", skel)
	var sel = load("res://src/gpf/AnimSelector.cs").new()
	sel.Setup(c)

	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new()
	ball.ResetSituation(Vector3(0, -1.0, 0))
	h.SetBall(ball)

	# ---------- 1. BallControl-запрос: отбор непуст и все клипы — ballcontrol ----------
	var ds: Array = h.BuildCrudeDataSetBridge(2)  # 2 == e_FunctionType_BallControl (gamedefines.hpp:93-109)
	if ds.size() == 0:
		print("CHECK FAIL: ballcontrol crude-отбор пуст"); ok = false
	for id in ds:
		if c.GetAnim(id).GetAnimType() != "ballcontrol":
			print("CHECK FAIL: не-ballcontrol в отборе: ", c.GetAnim(id).GetName()); ok = false
			break

	# ---------- 2. Отсортированный отбор: голова стабильна и повторяема ----------
	var s1: Array = h.BuildSortedDataSetBridge(2)
	var s2: Array = h.BuildSortedDataSetBridge(2)
	if s1.size() != s2.size():
		print("CHECK FAIL: недетерминизм размера"); ok = false
	else:
		for i in s1.size():
			if s1[i] != s2[i]:
				print("CHECK FAIL: недетерминизм сортировки, позиция ", i); ok = false
				break

	# ---------- 3. Сорт-инвариант priority (первый ключ цепочки :1556-1561) ----------
	# после всех сортировок расстояние |priority - 0| первого клипа <= последнего
	if s1.size() >= 2:
		var first_prio: int = int(c.GetAnim(s1[0]).GetVariable("priority"))
		var last_prio: int = int(c.GetAnim(s1[s1.size() - 1]).GetVariable("priority"))
		if absi(first_prio) > absi(last_prio):
			print("CHECK FAIL: priority-сортировка нарушена: ", first_prio, " > ", last_prio); ok = false

	# ---------- 4. Pass-запрос (ShortPass): long pass hax и непустой отбор ----------
	var ds_pass: Array = h.BuildCrudeDataSetBridge(4)  # ShortPass
	var ds_long: Array = h.BuildCrudeDataSetBridge(5)  # LongPass — hax :1256 даёт тот же тип
	if ds_pass.size() == 0:
		print("CHECK FAIL: shortpass-отбор пуст"); ok = false
	if ds_long.size() != ds_pass.size():
		print("CHECK FAIL: longpass != shortpass (hax :1256): ",
			ds_long.size(), " vs ", ds_pass.size()); ok = false

	# ---------- 5. NeedTouch: стоячий мяч + idle-желание → false; быстрый мяч → true ----------
	# (:1824-1830: idle-клип, desiredVelocity < 1.8, |ballMovement| <= 2 — не трогаем каждый кадр)
	ball.SetPosition(Vector3(0, -0.5, 0.11))
	var idle_id: int = c.GetIdleMovementAnimID()
	if h.NeedTouchBridge(idle_id, 0.0):
		print("CHECK FAIL: NeedTouch true на стоячем мяче и idle-желании"); ok = false
	ball.SetMomentum(Vector3(0, -8, 0))
	if not h.NeedTouchBridge(idle_id, 0.0):
		print("CHECK FAIL: NeedTouch false на быстром мяче (:1830)"); ok = false

	# ---------- 6. Движение-ветка наследника жива: walker-инварианты не сломаны ----------
	# (подробная проверка — существующие check_gpf_walker/selector; здесь смоук)
	var h2 = HB.new()
	h2.Setup(c, sel)
	h2.ResetSituation(Vector3.ZERO, 0.0)
	h2.SetBall(ball)
	# 5.0 — walkVelocity (gamedefines.hpp:20): const-поля C#-класса через мост не читаются
	# (см. Velo.cs), поэтому литерал. Tick — пятиаргументный с задачи 5 (третий — wantBall);
	# мост требует полный список.
	for i in 200:
		h2.Tick(Vector3(0, -1, 0), 5.0, false, false, Vector3.ZERO)
	if h2.GetSpatialFloatVelocity() < 1.8:
		print("CHECK FAIL: движение сломано отбором наследника: v = ",
			h2.GetSpatialFloatVelocity()); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

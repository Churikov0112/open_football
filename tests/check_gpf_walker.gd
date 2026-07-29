extends SceneTree
# Walker: разгон из idle до спринта по команде «вперёд», поворот по команде «вправо».
# Детерминизм: сцена шагается вручную StepOneFrame, физ-тики не нужны.

func _initialize() -> void:
	var ok := true
	var packed: PackedScene = load("res://scenes/lab/walk_lab.tscn")
	if packed == null:
		print("CHECK FAIL: walk_lab.tscn не найден")
		quit(1)
		return
	var lab = packed.instantiate()
	get_root().add_child(lab)
	# В режиме SceneTree-скрипта (`-s`) _Ready C#-ноды не вызывается синхронно на add_child, а
	# откладывается до первого кадра главного цикла. Пропускаем кадры, пока _Ready не построит
	# коллекцию и не выставит стартовый клип (_currentAnim >= 0) — иначе StepOneFrame рано выходит.
	# Это правка тест-харнеса под жизненный цикл движка, не подгонка поведения палочника.
	var ready_guard := 0
	while lab.GetCurrentAnimIndex() < 0 and ready_guard < 60:
		await process_frame
		ready_guard += 1
	if lab.GetCurrentAnimIndex() < 0:
		print("CHECK FAIL: _Ready сцены не отработал за 60 кадров"); ok = false

	# Команда: вперёд, спринт. Идём до 4 смен клипа (idle→dribble→walk→sprint максимум по +1 за клип).
	lab.SetCommand(Vector3(0, -1, 0), 3)
	var guard := 0
	while lab.GetTransitionCount() < 4 and guard < 5000:
		lab.StepOneFrame()
		guard += 1
	if guard >= 5000:
		print("CHECK FAIL: 4 смены клипа не случились за 5000 кадров"); ok = false
	if lab.GetStateVelocityId() < 2:
		print("CHECK FAIL: после 4 клипов скорость всё ещё ", lab.GetStateVelocityId()); ok = false
	# Двигаемся вперёд: |угол| мал, позиция ушла в -Y
	if absf(lab.GetStateAngle()) > 0.15 * PI:
		print("CHECK FAIL: угол после разгона → ", lab.GetStateAngle()); ok = false
	var pos: Vector3 = lab.GetStatePosition()
	if pos.y > -1.0:
		print("CHECK FAIL: позиция не ушла вперёд → ", pos); ok = false

	# Поворот направо (в «их» осях право = Rotate2D(вперёд, -pi/2))
	var angle_before: float = lab.GetStateAngle()
	var right := Vector3(0, -1, 0).rotated(Vector3(0, 0, 1), -0.5 * PI)
	lab.SetCommand(right, 2)
	var transitions_before: int = lab.GetTransitionCount()
	guard = 0
	while lab.GetTransitionCount() < transitions_before + 3 and guard < 5000:
		lab.StepOneFrame()
		guard += 1
	var dturn: float = lab.GetStateAngle() - angle_before
	# ModulateIntoRange вручную, углы могли перескочить через -pi
	while dturn > PI: dturn -= TAU
	while dturn < -PI: dturn += TAU
	if dturn > -0.15 * PI:
		print("CHECK FAIL: за 3 клипа не повернул направо: Δ", dturn); ok = false

	# Стоп-команда: скорость спадает
	lab.SetCommand(Vector3(0, -1, 0), 0)
	transitions_before = lab.GetTransitionCount()
	guard = 0
	while lab.GetTransitionCount() < transitions_before + 5 and guard < 8000:
		lab.StepOneFrame()
		guard += 1
	if lab.GetStateVelocityId() > 1:
		print("CHECK FAIL: после стоп-команды скорость → ", lab.GetStateVelocityId()); ok = false

	lab.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

extends SceneTree

# Регресс-тест: пока PlayerMotor заблокирован (set_control_locked(true), как во время
# слайд-такла подкатчика), гравитация НЕ должна копиться и move_and_slide() не должен
# двигать тело по вертикали — иначе motor спорит за Y с внешней системой (ручной
# move_and_collide() в _tackle_slide()), что даёт "телепорт/зависание в воздухе/отброс"
# при подкате. Тело без пола под ногами — если бы гравитация применялась, тело падало бы.

var _body: CharacterBody3D
var _motor: PlayerMotor
var _frame := 0
var _start_y := 5.0

func _initialize() -> void:
	_body = CharacterBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.5
	shape.radius = 0.3
	col.shape = shape
	_body.add_child(col)
	root.add_child(_body)
	_motor = PlayerMotor.new()
	_body.add_child(_motor)
	_motor.set_control_locked(true)

func _process(_delta: float) -> bool:
	# add_child в _initialize не входит в дерево синхронно (см. check_player_visual_actions.gd) —
	# ставим позицию и ждём on первом кадре, когда is_inside_tree() уже true.
	if _frame == 0 and not _body.is_inside_tree():
		return false
	if _frame == 0:
		_body.global_position = Vector3(0, _start_y, 0)
	_frame += 1
	if _frame < 11:
		return false
	var ok := true
	if not is_equal_approx(_body.global_position.y, _start_y):
		print("CHECK FAIL: залоченное тело сдвинулось по Y под гравитацией → ", _body.global_position.y, " (было ", _start_y, ")")
		ok = false
	if not is_zero_approx(_body.velocity.y):
		print("CHECK FAIL: залоченное тело накопило вертикальную скорость → ", _body.velocity.y)
		ok = false
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
	return true

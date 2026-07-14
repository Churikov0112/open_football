extends CharacterBody3D
## AI-вратарь: позиционирование на линии + сейв. Движение — через PlayerMotor; нырок (Task 11) —
## свой move_and_collide при заблокированном моторе (как подкат). Математика — в KeeperLogic.

@export var ball: RigidBody3D
var goal_line_z: float = 0.0
var save_area: Area3D

enum State { POSITION, DIVE, RECOVER, HOLD, DISTRIBUTE }
var _state: int = State.POSITION
var _wired: bool = false

func _motor() -> PlayerMotor:
	return PlayerMotor.find_on(self)

func _visual() -> PlayerVisual:
	for c in get_children():
		if c is PlayerVisual:
			return c
	return null

## Скорость перемещения по линии относительно общей максимальной.
func _base_scale() -> float:
	return 1.0

func _to_position() -> void:
	_state = State.POSITION

## Одноразовая проводка: стиль локомоции вратаря (на случай, если спавнер не выставил).
func _ensure_wired() -> void:
	if _wired:
		return
	_wired = true
	var v := _visual()
	if v != null:
		v.set_locomotion_style(PlayerVisual.LOCO_STYLE_KEEPER)

func _physics_process(delta: float) -> void:
	if not ball or not is_instance_valid(ball):
		return
	_ensure_wired()
	match _state:
		State.POSITION:
			_position(delta)

## Держим линию: X за мячом, лицом к мячу, лёгкий выход под угол.
func _position(_delta: float) -> void:
	var m := _motor()
	if m == null:
		return
	m.set_face_direction(ball.global_position - global_position)
	var target := KeeperLogic.line_position(
		ball.global_position, goal_line_z, FootballConstants.GOAL_WIDTH * 0.5,
		FootballConstants.KEEPER_LINE_NARROW_GAIN, FootballConstants.KEEPER_MAX_OFF_LINE)
	var to := target - global_position
	to.y = 0.0
	if to.length() > 0.15:
		m.set_move_intent(to.normalized(), _base_scale())
	else:
		m.set_move_intent(Vector3.ZERO)

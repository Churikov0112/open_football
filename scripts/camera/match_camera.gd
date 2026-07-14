extends Camera3D
## Пассивная камера: позицию и ориентацию задаёт CameraPivot — match_manager ведёт вид от
## 3-го лица за управляемым игроком. Камера сидит статичным «глазом» в начале пивота, чтобы
## camera_pivot.global_transform.basis совпадал с направлением взгляда (камера-относительный ввод).

func _ready() -> void:
	current = true
	transform = Transform3D.IDENTITY

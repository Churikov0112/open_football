extends Camera3D

@export var target: Node3D
@export var follow_speed: float = 4.0
@export var offset := Vector3(-40, 15, 12)
@export var angle := Vector2(-0.6, 0.0)


func _ready() -> void:
	current = true
	rotation.x = angle.x
	rotation.y = angle.y


func _physics_process(delta: float) -> void:
	if not target:
		return
	# Follow the ball in Z only; keep X at 0 (side-view camera).
	var target_pos := Vector3(0, target.global_position.y, target.global_position.z) + offset
	global_position = global_position.lerp(target_pos, follow_speed * delta)
	look_at(Vector3(0, target.global_position.y, target.global_position.z), Vector3.UP)

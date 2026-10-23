extends Node3D

@export var Sensitivity = 0.2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		get_parent().rotate_y(deg_to_rad(-event.relative.x * Sensitivity))
		rotate_x(deg_to_rad(-event.relative.y * Sensitivity))
		rotation.x = clampf(rotation.x,deg_to_rad(-90),deg_to_rad(90))
	

extends CharacterBody3D

enum PlayerState { WALK, SPRINT, CROUCH, JUMP, FALL }

@export_category("Speeds")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.5

@export_category("Acceleration Rates")
@export var walk_accel: float = 12.0
@export var sprint_accel: float = 8.0
@export var crouch_accel: float = 15.0
@export var fall_accel: float = 1.0 

@export_category("Jumping")
@export var jump_velocity: float = 4.5
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.5 # 0.5 = cuts vertical speed by half on release

var current_state: PlayerState = PlayerState.WALK
var current_speed: float = 0.0

func _physics_process(_delta: float) -> void:
	var dt := get_physics_process_delta_time()
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var Grounded := is_on_floor()
	var is_moving_forward := input_dir.y < -0.1
	
	# 1. Determine State
	if Grounded:
		if Input.is_action_pressed("StanceDown"):
			current_state = PlayerState.CROUCH
		elif Input.is_action_pressed("PaceUp") and is_moving_forward:
			current_state = PlayerState.SPRINT
		else:
			current_state = PlayerState.WALK
	else:
		current_state = PlayerState.JUMP if velocity.y > 0.1 else PlayerState.FALL

	# 2. Match System: Define Parameters
	var Speed: float
	var Acceleration: float

	match current_state:
		PlayerState.SPRINT:
			Speed = sprint_speed; Acceleration = sprint_accel
		PlayerState.CROUCH:
			Speed = crouch_speed; Acceleration = crouch_accel
		PlayerState.JUMP, PlayerState.FALL:
			Speed = 0.0; Acceleration = fall_accel
		_:
			Speed = walk_speed; Acceleration = walk_accel

	# 3. Movement Execution
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var target_vel := direction * Speed
	
	velocity.x = lerp(velocity.x, target_vel.x, Acceleration * dt)
	velocity.z = lerp(velocity.z, target_vel.z, Acceleration * dt)
	
	# Jump Execution
	if Input.is_action_just_pressed("Jump") and Grounded:
		velocity.y = jump_velocity + (Speed * 0.5)
	# Variable Height: Cut vertical momentum if button released early while ascending
	elif Input.is_action_just_released("Jump") and velocity.y > 0.0:
		velocity.y *= jump_cut_multiplier
		
	# Physics Forces
	if not Grounded:
		velocity += get_gravity() * dt
		velocity.y = clamp(velocity.y, -50.0, 100.0)
	elif velocity.y < 0:
		velocity.y = -2.0 
		
	current_speed = Vector2(velocity.x, velocity.z).length()
	move_and_slide()

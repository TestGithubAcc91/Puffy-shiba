# VineComponent.gd - Version with improved input blocking system
extends Node

@export var swing_speed: float = 400.0
@export var release_boost: float = 1.5
@export var max_swing_velocity: float = 600.0
@export var gravity_multiplier_while_swinging: float = 0.3
@export var max_swing_angle_degrees: float = 70.0
@export var slowdown_start_angle_degrees: float = 50.0
@export var input_unlock_angle_degrees: float = 20.0  # Angle on opposite side where inputs become available again
@export var return_force_strength: float = 200.0
@export var return_force_buildup_rate: float = 1.5
@export var pendulum_restore_force: float = 150.0
@export var swing_damping: float = 0.98
@export var slowdown_curve_exponent: float = 2.0
@export var max_slowdown_factor: float = 0.7

var current_vine: Vine = null
var is_swinging: bool = false
var player: CharacterBody2D
var swing_angle: float = 0.0
var swing_angular_velocity: float = 0.0
var nearby_vine: Vine = null
var current_grab_distance: float = 0.0
var max_swing_angle_radians: float
var slowdown_start_angle_radians: float
var input_unlock_angle_radians: float
var time_at_limit: float = 0.0
var recently_released_vine: Vine = null
var is_grounded: bool = false

# New variables for input blocking system
var inputs_blocked: bool = false
var blocked_direction: int = 0  # -1 for left, 1 for right, 0 for none
var last_swing_direction: int = 0  # Track which direction we were swinging when blocked

func _ready():
	player = get_parent() as CharacterBody2D
	max_swing_angle_radians = deg_to_rad(max_swing_angle_degrees)
	slowdown_start_angle_radians = deg_to_rad(slowdown_start_angle_degrees)
	input_unlock_angle_radians = deg_to_rad(input_unlock_angle_degrees)

func _physics_process(delta):
	# Check if player is grounded
	if player and player.is_on_floor():
		if not is_grounded:
			is_grounded = true
			if recently_released_vine:
				recently_released_vine = null
	else:
		is_grounded = false
	
	# Check for vine release input (Jump button)
	if Input.is_action_just_pressed("ui_accept") and is_swinging:
		release_vine()
	
	# Auto-grab vine immediately when in detection area (no jump needed)
	if nearby_vine and not is_swinging:
		var distance_to_vine_bottom = player.global_position.distance_to(
			nearby_vine.global_position + Vector2(0, nearby_vine.vine_length)
		)
		
		if distance_to_vine_bottom <= nearby_vine.grab_range:
			if recently_released_vine == null or nearby_vine != recently_released_vine:
				grab_vine(nearby_vine)
	
	if is_swinging and current_vine:
		handle_vine_swinging(delta)

func player_in_vine_detection_area() -> bool:
	if not nearby_vine:
		return false
	
	var player_pos = player.global_position
	var vine_bottom = nearby_vine.global_position + Vector2(0, nearby_vine.vine_length)
	var distance = player_pos.distance_to(vine_bottom)
	
	return distance <= nearby_vine.grab_range

func set_nearby_vine(vine: Vine):
	nearby_vine = vine

func clear_nearby_vine(vine: Vine):
	if nearby_vine == vine:
		nearby_vine = null

func grab_vine(vine: Vine):
	current_vine = vine
	is_swinging = true
	vine.attach_player(player)
	
	# Reset input blocking when grabbing a new vine
	inputs_blocked = false
	blocked_direction = 0
	last_swing_direction = 0
	
	current_grab_distance = vine.vine_length + 5.0
	
	var to_player = player.global_position - vine.vine_anchor
	var direction = to_player.normalized()
	
	player.global_position = vine.vine_anchor + direction * current_grab_distance
	
	to_player = player.global_position - vine.vine_anchor
	swing_angle = atan2(to_player.x, to_player.y)
	
	if swing_angle > max_swing_angle_radians:
		swing_angle = max_swing_angle_radians
	elif swing_angle < -max_swing_angle_radians:
		swing_angle = -max_swing_angle_radians
	
	swing_angular_velocity = 0.0
	time_at_limit = 0.0
	
func release_vine():
	if current_vine:
		recently_released_vine = current_vine
		current_vine.release_player()
		current_vine = null
		is_swinging = false
		swing_angle = 0.0
		swing_angular_velocity = 0.0
		current_grab_distance = 0.0
		time_at_limit = 0.0
		
		# Reset input blocking when releasing vine
		inputs_blocked = false
		blocked_direction = 0
		last_swing_direction = 0
		
		player.velocity = Vector2.ZERO

func handle_vine_swinging(delta):
	if not current_vine:
		return
	
	var vine_anchor = current_vine.vine_anchor
	var effective_vine_length = current_grab_distance
	
	var gravity_magnitude = player.get_gravity().y
	var pendulum_acceleration = -(gravity_magnitude * gravity_multiplier_while_swinging / effective_vine_length) * sin(swing_angle)
	var additional_restoration = -(pendulum_restore_force / effective_vine_length) * sin(swing_angle)
	
	swing_angular_velocity += (pendulum_acceleration + additional_restoration) * delta
	
	var abs_angle = abs(swing_angle)
	var at_limit = abs_angle >= (max_swing_angle_radians * 0.95)
	
	if at_limit:
		time_at_limit += delta
		var return_force_multiplier = time_at_limit * return_force_buildup_rate
		var return_force = -sign(swing_angle) * return_force_strength * return_force_multiplier / effective_vine_length
		swing_angular_velocity += return_force * delta
	else:
		time_at_limit = 0.0
	
	# NEW: Check if we should block inputs based on swing angle
	check_input_blocking()
	
	# Get player input, but respect blocking
	var raw_input = Input.get_axis("Move_Left", "Move_Right")
	var horizontal_input = 0.0
	
	if not inputs_blocked:
		horizontal_input = raw_input
		# Track the last swing direction for blocking logic
		if horizontal_input != 0:
			last_swing_direction = sign(horizontal_input)
	else:
		# If inputs are blocked, only allow input in the opposite direction of the block
		if (blocked_direction == 1 and raw_input < 0) or (blocked_direction == -1 and raw_input > 0):
			horizontal_input = raw_input
	
	# Add player input to swing
	if horizontal_input != 0:
		var input_force = horizontal_input * swing_speed / effective_vine_length
		var moving_against_swing = (horizontal_input * swing_angular_velocity) < 0
		
		if moving_against_swing:
			input_force *= 2.0
		
		swing_angular_velocity += input_force * delta
	else:
		swing_angular_velocity *= swing_damping
	
	# Apply progressive slowdown as we approach the limits
	if abs_angle > slowdown_start_angle_radians:
		var moving_towards_limit = (swing_angle * swing_angular_velocity) > 0
		
		if moving_towards_limit:
			var slowdown_range = max_swing_angle_radians - slowdown_start_angle_radians
			var progress_in_slowdown = (abs_angle - slowdown_start_angle_radians) / slowdown_range
			progress_in_slowdown = clamp(progress_in_slowdown, 0.0, 1.0)
			
			var curve_progress = pow(progress_in_slowdown, slowdown_curve_exponent)
			var slowdown_factor = 1.0 - (curve_progress * max_slowdown_factor)
			slowdown_factor = max(slowdown_factor, 1.0 - max_slowdown_factor)
			
			swing_angular_velocity *= slowdown_factor
	
	# Clamp angular velocity
	var max_angular_velocity = max_swing_velocity / effective_vine_length
	swing_angular_velocity = clamp(swing_angular_velocity, -max_angular_velocity, max_angular_velocity)
	
	# Update angle
	var new_angle = swing_angle + swing_angular_velocity * delta
	
	# Constrain the angle to ±70 degrees
	if new_angle > max_swing_angle_radians:
		new_angle = max_swing_angle_radians
		swing_angular_velocity = -swing_angular_velocity * 0.3
	elif new_angle < -max_swing_angle_radians:
		new_angle = -max_swing_angle_radians
		swing_angular_velocity = -swing_angular_velocity * 0.3
	
	swing_angle = new_angle
	
	# Calculate new position
	var new_position = vine_anchor + Vector2(sin(swing_angle), cos(swing_angle)) * effective_vine_length
	player.global_position = new_position
	
	# Set velocity for proper collision detection
	var tangent_direction = Vector2(-cos(swing_angle), sin(swing_angle))
	player.velocity = tangent_direction * swing_angular_velocity * effective_vine_length
	
	# Check for release input (Jump button)
	if Input.is_action_just_pressed("Jump"):
		release_vine()

# NEW FUNCTION: Check if inputs should be blocked or unblocked
func check_input_blocking():
	var abs_angle = abs(swing_angle)
	
	# Check if we should block inputs (reached slowdown angle)
	if abs_angle >= slowdown_start_angle_radians and not inputs_blocked:
		inputs_blocked = true
		# Determine which direction is blocked based on swing angle
		blocked_direction = sign(swing_angle)
		print("Inputs blocked for direction: ", blocked_direction)
	
	# Check if we should unblock inputs (reached unlock angle on opposite side)
	if inputs_blocked:
		if blocked_direction == 1:  # Right was blocked
			# Unblock if we've swung to the left unlock angle
			if swing_angle <= -input_unlock_angle_radians:
				inputs_blocked = false
				blocked_direction = 0
				print("Inputs unblocked - reached left unlock angle")
		elif blocked_direction == -1:  # Left was blocked
			# Unblock if we've swung to the right unlock angle
			if swing_angle >= input_unlock_angle_radians:
				inputs_blocked = false
				blocked_direction = 0
				print("Inputs unblocked - reached right unlock angle")

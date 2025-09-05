# VineComponent.gd - Fixed version that doesn't teleport player
extends Node

@export var swing_speed: float = 400.0
@export var release_boost: float = 1.5
@export var max_swing_velocity: float = 600.0
@export var gravity_multiplier_while_swinging: float = 0.3
@export var max_swing_angle_degrees: float = 70.0
@export var slowdown_start_angle_degrees: float = 50.0
@export var return_force_strength: float = 200.0  # Base strength of the return force
@export var return_force_buildup_rate: float = 1.5  # How quickly the return force increases
@export var pendulum_restore_force: float = 150.0  # Natural pendulum restoration force
@export var swing_damping: float = 0.98  # Damping factor to gradually reduce swing (0.98 = 2% reduction per frame)

var current_vine: Vine = null
var is_swinging: bool = false
var player: CharacterBody2D
var swing_angle: float = 0.0
var swing_angular_velocity: float = 0.0
var nearby_vine: Vine = null  # Track nearby vine for input checking
var current_grab_distance: float = 0.0
var max_swing_angle_radians: float
var slowdown_start_angle_radians: float
var time_at_limit: float = 0.0  # Track how long player has been at the swing limit
var recently_released_vine: Vine = null  # Track vine that was just released
var is_grounded: bool = false  # Track if player is on ground

func _ready():
	player = get_parent() as CharacterBody2D
	max_swing_angle_radians = deg_to_rad(max_swing_angle_degrees)
	slowdown_start_angle_radians = deg_to_rad(slowdown_start_angle_degrees)

func _physics_process(delta):
	# Check if player is grounded
	if player and player.is_on_floor():
		if not is_grounded:
			is_grounded = true
			# Clear recently released vine when touching ground
			if recently_released_vine:
				print("Player touched ground - can reattach to vine")
				recently_released_vine = null
	else:
		is_grounded = false
	
	# Check for vine release input (Jump button)
	if Input.is_action_just_pressed("ui_accept") and is_swinging:
		release_vine()
	
	# Auto-grab vine when nearby (no input needed)
	# But prevent reattaching to recently released vine until grounded
	if nearby_vine and not is_swinging:
		if recently_released_vine == null or nearby_vine != recently_released_vine:
			grab_vine(nearby_vine)
		else:
			print("Cannot reattach to recently released vine until touching ground")
	
	if is_swinging and current_vine:
		handle_vine_swinging(delta)

func set_nearby_vine(vine: Vine):
	nearby_vine = vine
	print("Nearby vine set: ", vine)

func clear_nearby_vine(vine: Vine):
	if nearby_vine == vine:
		nearby_vine = null
		print("Nearby vine cleared")

func grab_vine(vine: Vine):
	print("VineComponent: Auto-grabbing vine")
	current_vine = vine
	is_swinging = true
	vine.attach_player(player)
	
	# FIXED: Use the player's CURRENT distance from vine anchor, don't teleport!
	var to_player = player.global_position - vine.vine_anchor
	current_grab_distance = to_player.length()
	
	# Calculate the current swing angle based on player's actual position
	swing_angle = atan2(to_player.x, to_player.y)  # Angle from vertical down
	
	# Constrain initial angle if it's outside the allowed range
	if swing_angle > max_swing_angle_radians:
		swing_angle = max_swing_angle_radians
	elif swing_angle < -max_swing_angle_radians:
		swing_angle = -max_swing_angle_radians
	
	# DON'T teleport the player - let them stay where they are!
	# The swing will work from their current position
	
	swing_angular_velocity = 0.0
	time_at_limit = 0.0  # Reset timer when grabbing vine
	
	print("Player grabs vine at current position. Distance from anchor: ", current_grab_distance, ", angle: ", rad_to_deg(swing_angle))
	
func release_vine():
	if current_vine:
		print("Player released vine with Jump button")
		
		# Store the vine that was just released
		recently_released_vine = current_vine
		
		# Simply drop the player without applying any release velocity
		current_vine.release_player()
		current_vine = null
		is_swinging = false
		swing_angle = 0.0
		swing_angular_velocity = 0.0
		current_grab_distance = 0.0
		time_at_limit = 0.0  # Reset the timer when releasing
		
		# Reset player velocity to zero for a clean drop
		player.velocity = Vector2.ZERO

func handle_vine_swinging(delta):
	if not current_vine:
		return
	
	var vine_anchor = current_vine.vine_anchor
	var effective_vine_length = current_grab_distance
	
	# Physics-based pendulum motion
	# For a pendulum, the restoring force is always toward center (angle = 0)
	# The force should be: F = -mg*sin(angle) / length
	# Since we want the vine to return to center, we need the force to oppose the angle
	
	var gravity_magnitude = player.get_gravity().y
	
	# Standard pendulum physics: acceleration = -(g/L) * sin(angle)
	# This naturally creates the restoring force toward vertical
	var pendulum_acceleration = -(gravity_magnitude * gravity_multiplier_while_swinging / effective_vine_length) * sin(swing_angle)
	
	# Add additional restoration force for faster return to center
	var additional_restoration = -(pendulum_restore_force / effective_vine_length) * sin(swing_angle)
	
	# Apply both forces
	swing_angular_velocity += (pendulum_acceleration + additional_restoration) * delta
	
	# Check if player is at or near the swing limits
	var abs_angle = abs(swing_angle)
	var at_limit = abs_angle >= (max_swing_angle_radians * 0.95)  # Consider 95% of max as "at limit"
	
	if at_limit:
		# Increase time at limit
		time_at_limit += delta
		
		# Apply additional return force that gets stronger over time
		var return_force_multiplier = time_at_limit * return_force_buildup_rate
		var return_force = -sign(swing_angle) * return_force_strength * return_force_multiplier / effective_vine_length
		swing_angular_velocity += return_force * delta
	else:
		# Reset timer when not at limit
		time_at_limit = 0.0
	
	# Get player input
	var horizontal_input = Input.get_axis("Move_Left", "Move_Right")
	
	# Add player input to swing
	if horizontal_input != 0:
		var input_force = horizontal_input * swing_speed / effective_vine_length
		
		# Check if player is trying to move against the current swing direction
		var moving_against_swing = (horizontal_input * swing_angular_velocity) < 0
		
		if moving_against_swing:
			# Make it easier to change direction by boosting the input force
			input_force *= 2.0  # Double the force when moving against swing direction
		
		swing_angular_velocity += input_force * delta
	else:
		# When no input is applied, add damping to gradually slow the swing
		# This prevents infinite swinging and helps the vine settle at center
		swing_angular_velocity *= swing_damping
	
	# Apply progressive slowdown as we approach the limits (only when moving towards the limit)
	if abs_angle > slowdown_start_angle_radians:
		# Check if we're moving towards the limit (same sign means moving towards limit)
		var moving_towards_limit = (swing_angle * swing_angular_velocity) > 0
		
		if moving_towards_limit:
			# Calculate how close we are to the max (0.0 = at slowdown start, 1.0 = at max)
			var slowdown_range = max_swing_angle_radians - slowdown_start_angle_radians
			var progress_in_slowdown = (abs_angle - slowdown_start_angle_radians) / slowdown_range
			progress_in_slowdown = clamp(progress_in_slowdown, 0.0, 1.0)
			
			# Much gentler slowdown curve (reduced from progress^2 to progress^0.5)
			var slowdown_factor = 1.0 - (sqrt(progress_in_slowdown) * 0.3)  # Max 30% reduction instead of 60%
			swing_angular_velocity *= slowdown_factor
	
	# Clamp angular velocity
	var max_angular_velocity = max_swing_velocity / effective_vine_length
	swing_angular_velocity = clamp(swing_angular_velocity, -max_angular_velocity, max_angular_velocity)
	
	# Update angle
	var new_angle = swing_angle + swing_angular_velocity * delta
	
	# Constrain the angle to ±70 degrees and handle collision/bounce
	if new_angle > max_swing_angle_radians:
		new_angle = max_swing_angle_radians
		# Much gentler bounce since we've already been slowing down
		swing_angular_velocity = -swing_angular_velocity * 0.3  # Reduced from 0.7 to 0.3
	elif new_angle < -max_swing_angle_radians:
		new_angle = -max_swing_angle_radians
		# Much gentler bounce since we've already been slowing down
		swing_angular_velocity = -swing_angular_velocity * 0.3
	
	swing_angle = new_angle
	
	# Calculate new position using the current grab distance (not vine_length!)
	var new_position = vine_anchor + Vector2(sin(swing_angle), cos(swing_angle)) * effective_vine_length
	player.global_position = new_position
	
	# Set velocity for proper collision detection
	var tangent_direction = Vector2(-cos(swing_angle), sin(swing_angle))
	player.velocity = tangent_direction * swing_angular_velocity * effective_vine_length
	
	# Check for release input (Jump button)
	if Input.is_action_just_pressed("ui_accept"):
		release_vine()

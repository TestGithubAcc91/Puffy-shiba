# VineComponent.gd - Add this as a child node to your player
extends Node

@export var swing_speed: float = 400.0
@export var release_boost: float = 1.5
@export var max_swing_velocity: float = 600.0
@export var gravity_multiplier_while_swinging: float = 0.3
@export var max_swing_angle_degrees: float = 70.0
@export var slowdown_start_angle_degrees: float = 50.0

var current_vine: Vine = null
var is_swinging: bool = false
var player: CharacterBody2D
var swing_angle: float = 0.0
var swing_angular_velocity: float = 0.0
var nearby_vine: Vine = null  # Track nearby vine for input checking
var current_grab_distance: float = 0.0
var max_swing_angle_radians: float
var slowdown_start_angle_radians: float  # Added this missing variable

func _ready():
	player = get_parent() as CharacterBody2D
	max_swing_angle_radians = deg_to_rad(max_swing_angle_degrees)
	slowdown_start_angle_radians = deg_to_rad(slowdown_start_angle_degrees)  # Added this conversion

func _physics_process(delta):
	# Check for vine grab input
	if Input.is_action_just_pressed("Interact") and nearby_vine and not is_swinging:
		grab_vine(nearby_vine)
	
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
	print("VineComponent: Attempting to grab vine")
	current_vine = vine
	is_swinging = true
	vine.attach_player(player)
	
	# Calculate initial swing angle and distance based on current player position
	var to_player = player.global_position - vine.vine_anchor
	swing_angle = atan2(to_player.x, to_player.y)  # Angle from vertical
	
	# Store the actual distance where the player grabbed the vine
	current_grab_distance = to_player.length()
	
	# Constrain initial angle if it's outside the allowed range
	if swing_angle > max_swing_angle_radians:
		swing_angle = max_swing_angle_radians
		# Reposition player to the constraint boundary
		var new_position = vine.vine_anchor + Vector2(sin(swing_angle), cos(swing_angle)) * current_grab_distance
		player.global_position = new_position
	elif swing_angle < -max_swing_angle_radians:
		swing_angle = -max_swing_angle_radians
		# Reposition player to the constraint boundary
		var new_position = vine.vine_anchor + Vector2(sin(swing_angle), cos(swing_angle)) * current_grab_distance
		player.global_position = new_position
	
	swing_angular_velocity = 0.0
	
	print("Player grabbed vine at angle: ", rad_to_deg(swing_angle), " at distance: ", current_grab_distance)

func release_vine():
	if current_vine:
		print("Player released vine with velocity: ", player.velocity)
		
		# Apply release velocity boost based on swing direction
		var tangent_direction = Vector2(-cos(swing_angle), sin(swing_angle))
		var release_velocity = tangent_direction * swing_angular_velocity * current_grab_distance
		player.velocity += release_velocity * release_boost
		
		current_vine.release_player()
		current_vine = null
		is_swinging = false
		swing_angle = 0.0
		swing_angular_velocity = 0.0
		current_grab_distance = 0.0

func handle_vine_swinging(delta):
	if not current_vine:
		return
	
	var vine_anchor = current_vine.vine_anchor
	var effective_vine_length = current_grab_distance
	
	# Physics-based pendulum motion
	var gravity_component = sin(swing_angle) * player.get_gravity().y * gravity_multiplier_while_swinging / effective_vine_length
	swing_angular_velocity += gravity_component * delta
	
	# Add player input to swing
	var horizontal_input = Input.get_axis("Move_Left", "Move_Right")
	if horizontal_input != 0:
		var input_force = horizontal_input * swing_speed / effective_vine_length
		swing_angular_velocity += input_force * delta
	
	# Apply progressive slowdown as we approach the limits (only when moving towards the limit)
	var abs_angle = abs(swing_angle)
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
	
	# Calculate new position using the constrained angle
	var new_position = vine_anchor + Vector2(sin(swing_angle), cos(swing_angle)) * effective_vine_length
	player.global_position = new_position
	
	# Set velocity for proper collision detection
	var tangent_direction = Vector2(-cos(swing_angle), sin(swing_angle))
	player.velocity = tangent_direction * swing_angular_velocity * effective_vine_length
	
	# Check for release input
	if Input.is_action_just_released("Interact"):
		release_vine()

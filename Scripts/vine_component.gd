extends Node
class_name VineComponent

@export var swing_speed: float = 400.0
@export var release_boost: float = 1.5
@export var max_swing_velocity: float = 600.0
@export var gravity_multiplier_while_swinging: float = 0.3
@export var max_swing_angle_degrees: float = 70.0
@export var slowdown_start_angle_degrees: float = 50.0
@export var input_unlock_angle_degrees: float = 20.0
@export var return_force_strength: float = 200.0
@export var return_force_buildup_rate: float = 1.5
@export var pendulum_restore_force: float = 150.0
@export var swing_damping: float = 0.98
@export var slowdown_curve_exponent: float = 2.0
@export var max_slowdown_factor: float = 0.7

@export_group("Approach Speed Boost")
@export var min_approach_time_for_boost: float = 0.5
@export var base_initial_boost: float = 100.0
@export var max_approach_boost: float = 300.0
@export var approach_time_for_max_boost: float = 2.0
@export var approach_boost_curve: float = 1.5
@export var player_velocity_boost_multiplier: float = 0.8
@export var approach_direction_boost_multiplier: float = 1.2

# NEW: Minimum velocity threshold to allow swinging when directly under vine
@export var min_velocity_for_under_vine_swing: float = 50.0

@export_group("Vine Return Animation")
@export var vine_return_damping: float = 0.95
@export var vine_return_gravity_multiplier: float = 0.8
@export var vine_return_stop_threshold: float = 0.05  # Stop animating when angle is very small


@export_group("Momentum System")
@export var momentum_force_multiplier: float = 2.0  # How strong the initial momentum force is
@export var momentum_decay_rate: float = 3.0  # How quickly momentum decays (higher = faster decay)
@export var min_momentum_threshold: float = 10.0  # Minimum force before momentum stops applying

var momentum_force: Vector2 = Vector2.ZERO
var is_applying_momentum: bool = false


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
var inputs_blocked: bool = false
var blocked_direction: int = 0
var last_swing_direction: int = 0

# NEW: Variables for vine return animation
var vine_returning_to_rest: bool = false
var return_vine: Vine = null

func _ready():
	player = get_parent() as CharacterBody2D
	max_swing_angle_radians = deg_to_rad(max_swing_angle_degrees)
	slowdown_start_angle_radians = deg_to_rad(slowdown_start_angle_degrees)
	input_unlock_angle_radians = deg_to_rad(input_unlock_angle_degrees)

func _physics_process(delta):
	if player and player.is_on_floor():
		if not is_grounded:
			is_grounded = true
			if recently_released_vine:
				recently_released_vine = null
		# Stop momentum when player lands
		if is_applying_momentum:
			is_applying_momentum = false
			momentum_force = Vector2.ZERO
	else:
		is_grounded = false
	
	# NEW: Apply momentum force gradually
	if is_applying_momentum and player:
		apply_momentum_force(delta)
	
	if Input.is_action_just_pressed("Jump") and is_swinging:
		release_vine()
	
	if nearby_vine and not is_swinging:
		var distance_to_vine_bottom = player.global_position.distance_to(
			nearby_vine.global_position + Vector2(0, nearby_vine.vine_length)
		)
		
		if distance_to_vine_bottom <= nearby_vine.grab_range:
			if recently_released_vine == null or nearby_vine != recently_released_vine:
				grab_vine(nearby_vine)
	
	if is_swinging and current_vine:
		handle_vine_swinging(delta)
	
	# Handle vine return animation
	if vine_returning_to_rest and return_vine:
		handle_vine_return_animation(delta)

func set_nearby_vine(vine: Vine):
	nearby_vine = vine


# NEW: Apply momentum force function
func apply_momentum_force(delta: float):
	if not player or not is_applying_momentum:
		return
	
	# Apply current momentum force to player
	var force_to_apply = momentum_force * delta
	player.velocity.x += force_to_apply.x
	
	# Decay the momentum force over time
	momentum_force = momentum_force.move_toward(Vector2.ZERO, momentum_force.length() * momentum_decay_rate * delta)
	
	# Stop applying momentum when force becomes too small
	if momentum_force.length() < min_momentum_threshold:
		is_applying_momentum = false
		momentum_force = Vector2.ZERO
		print("Momentum force ended")


func clear_nearby_vine(vine: Vine):
	if nearby_vine == vine:
		nearby_vine = null

func calculate_initial_speed_boost(vine: Vine, approach_time: float) -> float:
	var total_boost = base_initial_boost
	var horizontal_distance_to_vine = abs(player.global_position.x - vine.vine_anchor.x)
	var is_directly_under_vine = horizontal_distance_to_vine <= vine.grab_range
	
	# MODIFIED: Check if player has sufficient velocity when directly under vine
	if is_directly_under_vine:
		var player_speed = player.velocity.length()
		# If player is moving fast enough, allow some boost; otherwise return 0
		if player_speed >= min_velocity_for_under_vine_swing:
			# Scale the boost based on player velocity, but keep it lower than side approaches
			var velocity_factor = clamp(player_speed / 200.0, 0.2, 0.6)
			total_boost *= velocity_factor
		else:
			return 0.0
	
	if approach_time > 0.0 and not is_directly_under_vine:
		if approach_time < min_approach_time_for_boost:
			var minimal_boost = max_approach_boost * 0.1
			total_boost += minimal_boost
		else:
			var time_progress = clamp((approach_time - min_approach_time_for_boost) / 
				(approach_time_for_max_boost - min_approach_time_for_boost), 0.0, 1.0)
			var curved_progress = pow(time_progress, approach_boost_curve)
			var approach_boost = curved_progress * max_approach_boost
			total_boost += approach_boost
	
	if player:
		var velocity_magnitude = player.velocity.length()
		var velocity_boost = velocity_magnitude * player_velocity_boost_multiplier
		var to_vine = (vine.vine_anchor - player.global_position).normalized()
		var velocity_direction = player.velocity.normalized()
		var dot_product = velocity_direction.dot(to_vine)
		
		if dot_product > 0.0 and not is_directly_under_vine:
			velocity_boost *= approach_direction_boost_multiplier * dot_product
		elif is_directly_under_vine:
			# MODIFIED: For under vine, use horizontal velocity component
			var horizontal_velocity = Vector2(player.velocity.x, 0.0).length()
			velocity_boost = horizontal_velocity * player_velocity_boost_multiplier * 0.5
		
		total_boost += velocity_boost
	
	return total_boost

func determine_initial_swing_direction(vine: Vine) -> float:
	if not player:
		return 1.0
	
	# Check if player is directly under the vine
	var horizontal_distance_to_vine = abs(player.global_position.x - vine.vine_anchor.x)
	var is_directly_under_vine = horizontal_distance_to_vine <= vine.grab_range
	
	# MODIFIED: If directly under vine, use player's horizontal velocity to determine direction
	if is_directly_under_vine:
		var player_speed = player.velocity.length()
		# Only apply direction if player is moving fast enough
		if player_speed >= min_velocity_for_under_vine_swing:
			var horizontal_velocity = player.velocity.x
			# Use horizontal velocity direction, but make it less aggressive
			if abs(horizontal_velocity) > 10.0:  # Minimum horizontal movement threshold
				return sign(horizontal_velocity) * 0.7  # Reduced multiplier for under-vine swings
		return 0.0
	
	var velocity_direction = player.velocity.normalized()
	var horizontal_component = velocity_direction.x
	
	if abs(horizontal_component) > 0.3:
		return sign(horizontal_component)
	
	var player_relative_x = player.global_position.x - vine.vine_anchor.x
	return sign(player_relative_x) if abs(player_relative_x) > 5.0 else 1.0

func grab_vine(vine: Vine):
	# Stop any momentum when grabbing a new vine
	is_applying_momentum = false
	momentum_force = Vector2.ZERO
	

	# Stop any ongoing vine return animation if we're grabbing the same vine
	if vine_returning_to_rest and return_vine == vine:
		vine_returning_to_rest = false
		return_vine = null
	
	current_vine = vine
	is_swinging = true
	var approach_time = vine.get_approach_time()
	vine.attach_player(player)
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
	
	# MODIFIED: Use approach timer to determine swing behavior
	var player_speed = player.velocity.length()
	var horizontal_distance_to_vine = abs(player.global_position.x - vine.vine_anchor.x)
	var is_directly_under_vine = horizontal_distance_to_vine <= vine.grab_range
	
	# Check if this is a short approach (accidental contact) or intentional swinging
	var is_short_approach = approach_time < min_approach_time_for_boost
	
	if is_directly_under_vine and player_speed < min_velocity_for_under_vine_swing:
		# Player is directly under vine and moving slowly - no initial swing
		swing_angular_velocity = 0.0
		swing_angle = 0.0  # Force straight down position
		player.global_position = vine.vine_anchor + Vector2(0, current_grab_distance)  # Position directly below
	elif is_short_approach and not is_directly_under_vine:
		# Player approached from side but didn't build up enough approach time - minimal swing
		swing_angular_velocity = 0.0
		swing_angle = 0.0  # Force straight down position  
		player.global_position = vine.vine_anchor + Vector2(0, current_grab_distance)  # Position directly below
	else:
		# Player has sufficient approach time or velocity - normal grab behavior
		var initial_boost = calculate_initial_speed_boost(vine, approach_time)
		var swing_direction = determine_initial_swing_direction(vine)
		swing_angular_velocity = (initial_boost / current_grab_distance) * swing_direction
		
		var max_initial_angular_velocity = (max_swing_velocity * 1.2) / current_grab_distance
		swing_angular_velocity = clamp(swing_angular_velocity, -max_initial_angular_velocity, max_initial_angular_velocity)
	
	time_at_limit = 0.0
	vine.reset_approach_timer()

func release_vine():
	if current_vine:
		recently_released_vine = current_vine
		
		# Calculate momentum
		var vine_anchor = current_vine.vine_anchor
		var effective_vine_length = current_grab_distance
		
		var tangent_direction = Vector2(-cos(swing_angle), sin(swing_angle))
		var swing_velocity = tangent_direction * swing_angular_velocity * effective_vine_length
		
		var base_horizontal_momentum = swing_velocity.x * release_boost
		
		var min_momentum = 100.0
		if abs(base_horizontal_momentum) < min_momentum and abs(swing_angular_velocity) > 0.1:
			base_horizontal_momentum = sign(swing_angular_velocity) * min_momentum * release_boost
		
		base_horizontal_momentum *= 2.0
		
		# Apply momentum to player instead of handling it in VineComponent
		if player and player.has_method("apply_external_momentum"):
			player.apply_external_momentum(Vector2(base_horizontal_momentum, 0.0))
		
		# Give small immediate velocity
		player.velocity.x += base_horizontal_momentum * 0.1  # Just 10% immediate
		if player.velocity.y > -50.0:
			player.velocity.y = -50.0
		
		print("Releasing vine - Applied momentum: ", base_horizontal_momentum)
		
		# Clean up vine stuff
		vine_returning_to_rest = true
		return_vine = current_vine
		
		current_vine.release_player()
		current_vine = null
		is_swinging = false
		current_grab_distance = 0.0
		time_at_limit = 0.0
		inputs_blocked = false
		blocked_direction = 0
		last_swing_direction = 0

# NEW: Handle vine return to rest animation
func handle_vine_return_animation(delta):
	if not return_vine:
		vine_returning_to_rest = false
		return
	
	var effective_vine_length = return_vine.vine_length
	var gravity_magnitude = player.get_gravity().y if player else 980.0
	var pendulum_acceleration = -(gravity_magnitude * vine_return_gravity_multiplier / effective_vine_length) * sin(swing_angle)
	
	swing_angular_velocity += pendulum_acceleration * delta
	swing_angular_velocity *= vine_return_damping
	
	swing_angle += swing_angular_velocity * delta
	
	# Stop the animation when the vine is close to rest position and moving slowly
	if abs(swing_angle) < vine_return_stop_threshold and abs(swing_angular_velocity) < 0.1:
		swing_angle = 0.0
		swing_angular_velocity = 0.0
		vine_returning_to_rest = false
		# NEW: Clear the vine component reference from the vine
		if return_vine:
			return_vine.clear_vine_component_ref()
		return_vine = null

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
	
	check_input_blocking()
	
	var raw_input = Input.get_axis("Move_Left", "Move_Right")
	var horizontal_input = 0.0
	
	if not inputs_blocked:
		horizontal_input = raw_input
		if horizontal_input != 0:
			last_swing_direction = sign(horizontal_input)
	else:
		if (blocked_direction == 1 and raw_input < 0) or (blocked_direction == -1 and raw_input > 0):
			horizontal_input = raw_input
	
	if horizontal_input != 0:
		var input_force = horizontal_input * swing_speed / effective_vine_length
		var moving_against_swing = (horizontal_input * swing_angular_velocity) < 0
		
		if moving_against_swing:
			input_force *= 2.0
		
		swing_angular_velocity += input_force * delta
	else:
		swing_angular_velocity *= swing_damping
	
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
	
	var max_angular_velocity = max_swing_velocity / effective_vine_length
	swing_angular_velocity = clamp(swing_angular_velocity, -max_angular_velocity, max_angular_velocity)
	
	var new_angle = swing_angle + swing_angular_velocity * delta
	
	if new_angle > max_swing_angle_radians:
		new_angle = max_swing_angle_radians
		swing_angular_velocity = -swing_angular_velocity * 0.3
	elif new_angle < -max_swing_angle_radians:
		new_angle = -max_swing_angle_radians
		swing_angular_velocity = -swing_angular_velocity * 0.3
	
	swing_angle = new_angle
	
	var new_position = vine_anchor + Vector2(sin(swing_angle), cos(swing_angle)) * effective_vine_length
	player.global_position = new_position
	
	var tangent_direction = Vector2(-cos(swing_angle), sin(swing_angle))
	player.velocity = tangent_direction * swing_angular_velocity * effective_vine_length
	
	if Input.is_action_just_pressed("Jump"):
		release_vine()

func check_input_blocking():
	var abs_angle = abs(swing_angle)
	
	if abs_angle >= slowdown_start_angle_radians and not inputs_blocked:
		inputs_blocked = true
		blocked_direction = sign(swing_angle)
	
	if inputs_blocked:
		if blocked_direction == 1:
			if swing_angle <= -input_unlock_angle_radians:
				inputs_blocked = false
				blocked_direction = 0
		elif blocked_direction == -1:
			if swing_angle >= input_unlock_angle_radians:
				inputs_blocked = false
				blocked_direction = 0

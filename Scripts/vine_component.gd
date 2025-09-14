extends Node
class_name VineComponent

@export var swing_speed: float = 400.0
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

@export_group("Vine Visual Adjustment")
@export var vine_bend_compensation: float = 0.92
@export var player_position_smoothing: float = 0.1

@export_group("Vine Return Animation")
@export var vine_return_damping: float = 0.95
@export var vine_return_gravity_multiplier: float = 0.8
@export var vine_return_stop_threshold: float = 0.05

@export_group("Vine Release Dash")
@export var vine_release_dash_enabled: bool = true
@export var vine_release_dash_force_multiplier: float = 1.0

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

# Variables for vine return animation
var vine_returning_to_rest: bool = false
var return_vine: Vine = null

# NEW: Adjusted swing radius for visual consistency
var visual_swing_radius: float = 0.0

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
	else:
		is_grounded = false
	
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

func clear_nearby_vine(vine: Vine):
	if nearby_vine == vine:
		nearby_vine = null

func calculate_initial_speed_boost(vine: Vine, approach_time: float) -> float:
	var total_boost = base_initial_boost
	
	if approach_time > 0.0:
		if approach_time < min_approach_time_for_boost:
			var minimal_boost = max_approach_boost * 0.3
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
		
		if dot_product > 0.0:
			velocity_boost *= approach_direction_boost_multiplier * dot_product
		else:
			var horizontal_velocity = Vector2(player.velocity.x, 0.0).length()
			velocity_boost = horizontal_velocity * player_velocity_boost_multiplier * 0.5
		
		total_boost += velocity_boost
	
	return total_boost

func determine_initial_swing_direction(vine: Vine) -> float:
	if not player:
		return 1.0
	
	var horizontal_velocity = player.velocity.x
	if abs(horizontal_velocity) > 10.0:
		return sign(horizontal_velocity)
	
	var player_relative_x = player.global_position.x - vine.vine_anchor.x
	return sign(player_relative_x) if abs(player_relative_x) > 5.0 else 1.0

func grab_vine(vine: Vine):
	# FIXED: Properly clean up previous vine before grabbing new one
	if is_swinging and current_vine and current_vine != vine:
		# Clean up previous vine completely
		cleanup_current_vine()
	
	# FIXED: Stop any ongoing return animation for the new vine
	if vine_returning_to_rest and return_vine == vine:
		vine_returning_to_rest = false
		return_vine.clear_vine_component_ref()
		return_vine = null
	
	current_vine = vine
	is_swinging = true
	var approach_time = vine.get_approach_time()
	vine.attach_player(player)
	inputs_blocked = false
	blocked_direction = 0
	last_swing_direction = 0
	current_grab_distance = vine.vine_length + 5.0
	
	visual_swing_radius = current_grab_distance * vine_bend_compensation
	
	var to_player = player.global_position - vine.vine_anchor
	var direction = to_player.normalized()
	player.global_position = vine.vine_anchor + direction * visual_swing_radius
	
	to_player = player.global_position - vine.vine_anchor
	swing_angle = atan2(to_player.x, to_player.y)
	
	if swing_angle > max_swing_angle_radians:
		swing_angle = max_swing_angle_radians
	elif swing_angle < -max_swing_angle_radians:
		swing_angle = -max_swing_angle_radians
	
	var initial_boost = calculate_initial_speed_boost(vine, approach_time)
	var swing_direction = determine_initial_swing_direction(vine)
	swing_angular_velocity = (initial_boost / visual_swing_radius) * swing_direction
	
	var max_initial_angular_velocity = (max_swing_velocity * 1.2) / visual_swing_radius
	swing_angular_velocity = clamp(swing_angular_velocity, -max_initial_angular_velocity, max_initial_angular_velocity)
	
	time_at_limit = 0.0
	vine.reset_approach_timer()

# FIXED: New function to properly clean up current vine
func cleanup_current_vine():
	if current_vine:
		# Force release the player from the old vine
		current_vine.force_release_player()
		# Clear the vine component reference from the old vine
		current_vine.clear_vine_component_ref()
		current_vine = null
	
	# Reset all swing state
	is_swinging = false
	current_grab_distance = 0.0
	visual_swing_radius = 0.0
	time_at_limit = 0.0
	inputs_blocked = false
	blocked_direction = 0
	last_swing_direction = 0
	swing_angle = 0.0
	swing_angular_velocity = 0.0

func release_vine():
	if current_vine:
		recently_released_vine = current_vine
		
		# Apply jump velocity
		player.velocity.y = player.JUMP_VELOCITY
		
		# Check if vine release dash is enabled and player is actively inputting direction
		if vine_release_dash_enabled:
			var input_direction = Input.get_axis("Move_Left", "Move_Right")
			
			if abs(input_direction) > 0.1:
				var dash_direction = Vector2.LEFT if input_direction < 0 else Vector2.RIGHT
				trigger_vine_release_dash(dash_direction)
		
		# FIXED: Store vine reference for return animation before cleanup
		var vine_to_animate = current_vine
		
		# Clean up vine connection
		cleanup_current_vine()
		
		# Set up return animation AFTER cleanup
		vine_returning_to_rest = true
		return_vine = vine_to_animate

func trigger_vine_release_dash(direction: Vector2):
	if player.is_dashing:
		return
	
	var original_can_dash = player.can_dash
	
	player.dash_started_on_ground = false
	player.was_on_ground_before_dash = false
	player.dash_start_time = Time.get_ticks_msec() / 1000.0
	player.dash_direction = direction * vine_release_dash_force_multiplier
	player.is_dashing = true
	player.can_dash = false
	
	player.is_vine_release_dash = true
	
	player.spawn_air_puff()
	player.animated_sprite.play("Dash")
	
	player.dash_timer.start()
	if original_can_dash:
		player.can_dash = true
	else:
		player.dash_cooldown_timer.start()
	
	if direction.x < 0:
		player.animated_sprite.flip_h = true
		if player.glint_sprite:
			player.glint_sprite.position.x = abs(player.glint_sprite.position.x)
	else:
		player.animated_sprite.flip_h = false
		if player.glint_sprite:
			player.glint_sprite.position.x = abs(player.glint_sprite.position.x) * -1

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
	
	if abs(swing_angle) < vine_return_stop_threshold and abs(swing_angular_velocity) < 0.1:
		swing_angle = 0.0
		swing_angular_velocity = 0.0
		vine_returning_to_rest = false
		if return_vine:
			return_vine.clear_vine_component_ref()
		return_vine = null

func handle_vine_swinging(delta):
	if not current_vine:
		return
	
	var vine_anchor = current_vine.vine_anchor
	var effective_vine_length = visual_swing_radius
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
	
	var target_position = vine_anchor + Vector2(sin(swing_angle), cos(swing_angle)) * effective_vine_length
	
	if player_position_smoothing > 0.0:
		player.global_position = player.global_position.lerp(target_position, 1.0 - player_position_smoothing)
	else:
		player.global_position = target_position
	
	var tangent_direction = Vector2(-cos(swing_angle), sin(swing_angle))
	player.velocity = tangent_direction * swing_angular_velocity * effective_vine_length

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

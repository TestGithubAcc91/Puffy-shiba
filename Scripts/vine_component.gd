# VineComponent.gd - Add this as a child node to your player
extends Node

@export var swing_speed: float = 400.0
@export var release_boost: float = 1.5
@export var max_swing_velocity: float = 600.0
@export var gravity_multiplier_while_swinging: float = 0.3

var current_vine: Vine = null
var is_swinging: bool = false
var player: CharacterBody2D
var swing_angle: float = 0.0
var swing_angular_velocity: float = 0.0
var nearby_vine: Vine = null  # Track nearby vine for input checking

func _ready():
	player = get_parent() as CharacterBody2D

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
	
	# Calculate initial swing angle based on player position relative to vine anchor
	var to_player = player.global_position - vine.vine_anchor
	swing_angle = atan2(to_player.x, to_player.y)  # Angle from vertical
	swing_angular_velocity = 0.0
	
	print("Player grabbed vine at angle: ", rad_to_deg(swing_angle))

func release_vine():
	if current_vine:
		print("Player released vine with velocity: ", player.velocity)
		
		# Apply release velocity boost based on swing direction
		var tangent_direction = Vector2(-cos(swing_angle), sin(swing_angle))
		var release_velocity = tangent_direction * swing_angular_velocity * current_vine.vine_length
		player.velocity += release_velocity * release_boost
		
		current_vine.release_player()
		current_vine = null
		is_swinging = false
		swing_angle = 0.0
		swing_angular_velocity = 0.0

func handle_vine_swinging(delta):
	if not current_vine:
		return
	
	var vine_anchor = current_vine.vine_anchor
	var vine_length = current_vine.vine_length
	
	# Physics-based pendulum motion
	var gravity_component = sin(swing_angle) * player.get_gravity().y * gravity_multiplier_while_swinging / vine_length
	swing_angular_velocity += gravity_component * delta
	
	# Add player input to swing
	var horizontal_input = Input.get_axis("Move_Left", "Move_Right")
	if horizontal_input != 0:
		var input_force = horizontal_input * swing_speed / vine_length
		swing_angular_velocity += input_force * delta
	
	# Clamp angular velocity
	var max_angular_velocity = max_swing_velocity / vine_length
	swing_angular_velocity = clamp(swing_angular_velocity, -max_angular_velocity, max_angular_velocity)
	
	# Update angle
	swing_angle += swing_angular_velocity * delta
	
	# Calculate new position
	var new_position = vine_anchor + Vector2(sin(swing_angle), cos(swing_angle)) * vine_length
	player.global_position = new_position
	
	# Set velocity for proper collision detection
	var tangent_direction = Vector2(-cos(swing_angle), sin(swing_angle))
	player.velocity = tangent_direction * swing_angular_velocity * vine_length
	
	# Check for release input
	if Input.is_action_just_released("Interact"):
		release_vine()

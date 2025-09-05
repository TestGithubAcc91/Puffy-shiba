extends Node2D

const SPEED = 60

# Movement properties
@export var vertical_movement_enabled: bool = true  # Toggle vertical movement on/off
@export var vertical_distance: float = 50.0  # Distance to move up and down
@export var vertical_speed: float = 30.0  # Speed of vertical movement

@export var horizontal_movement_enabled: bool = false  # Toggle horizontal movement on/off
@export var horizontal_distance: float = 100.0  # Distance to move left and right
@export var horizontal_speed: float = 60.0  # Speed of horizontal movement

@export var circular_movement_enabled: bool = false  # Toggle circular movement on/off
@export var circular_radius: float = 75.0  # Radius of the circular path
@export var circular_speed: float = 2.0  # Speed of circular movement (radians per second)

# Detection and state variables
var player_detected = false
var detection_timer = 0.0
var is_spiked = false  # Flag to track spiked state

# Movement variables
var initial_position: Vector2
var moving_up: bool = true
var moving_right: bool = true
var circular_angle: float = 0.0  # Current angle for circular movement

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $KillzoneScript_Area
@onready var unparryable_warning: Label = $UnparryableWarning

func _ready():
	# Store the initial position for vertical movement reference
	initial_position = position
	
	# Connect the detection area signals
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	
	# Hide the warning label initially
	if unparryable_warning:
		unparryable_warning.visible = false

func _process(delta: float):
	# Handle player detection timer
	if player_detected:
		detection_timer -= delta
		if detection_timer <= 0:
			player_detected = false
			is_spiked = false  # Reset spiked flag
			animated_sprite.play("Idle")  # Return to default animation
			
			# Hide the unparryable warning
			if unparryable_warning:
				unparryable_warning.visible = false
			
			# Make the damage area parryable again
			var damage_area = $KillzoneScript_Area  # Adjust path as needed
			if damage_area:
				damage_area.unparryable = false
			

	
	# Handle movement if enabled
	if circular_movement_enabled:
		handle_circular_movement(delta)
	
	# Handle linear movements (can combine with circular if desired)
	if vertical_movement_enabled and not circular_movement_enabled:
		handle_vertical_movement(delta)
	if horizontal_movement_enabled and not circular_movement_enabled:
		handle_horizontal_movement(delta)

func handle_vertical_movement(delta):
	var movement = vertical_speed * delta
	
	if moving_up:
		position.y -= movement
		# Check if we've reached the upper limit
		if position.y <= initial_position.y - vertical_distance:
			position.y = initial_position.y - vertical_distance
			moving_up = false
	else:
		position.y += movement
		# Check if we've reached the lower limit
		if position.y >= initial_position.y + vertical_distance:
			position.y = initial_position.y + vertical_distance
			moving_up = true

func handle_horizontal_movement(delta):
	var movement = horizontal_speed * delta
	
	if moving_right:
		position.x += movement
		animated_sprite.flip_h = false
		# Check if we've reached the right limit
		if position.x >= initial_position.x + horizontal_distance:
			position.x = initial_position.x + horizontal_distance
			moving_right = false
	else:
		position.x -= movement
		animated_sprite.flip_h = true
		# Check if we've reached the left limit
		if position.x <= initial_position.x - horizontal_distance:
			position.x = initial_position.x - horizontal_distance
			moving_right = true

func toggle_vertical_movement():
	vertical_movement_enabled = !vertical_movement_enabled
	# Reset to initial position when disabling movement
	if not vertical_movement_enabled:
		position.y = initial_position.y
		moving_up = true  # Reset movement direction

func handle_circular_movement(delta):
	# Update the angle based on speed
	circular_angle += circular_speed * delta
	
	# Calculate position on the circle
	var x_offset = cos(circular_angle) * circular_radius
	var y_offset = sin(circular_angle) * circular_radius
	
	# Set position relative to initial position (center of circle)
	position = initial_position + Vector2(x_offset, y_offset)
	
	# Optional: Face the direction of movement
	# Calculate movement direction for sprite flipping
	var prev_angle = circular_angle - circular_speed * delta
	var prev_x = cos(prev_angle) * circular_radius
	var current_x = cos(circular_angle) * circular_radius
	
	if current_x > prev_x:  # Moving right
		animated_sprite.flip_h = false
	elif current_x < prev_x:  # Moving left
		animated_sprite.flip_h = true

func toggle_horizontal_movement():
	horizontal_movement_enabled = !horizontal_movement_enabled
	# Reset to initial position when disabling movement
	if not horizontal_movement_enabled:
		position.x = initial_position.x
		moving_right = true  # Reset movement direction
		animated_sprite.flip_h = false  # Reset sprite orientation

func toggle_circular_movement():
	circular_movement_enabled = !circular_movement_enabled
	# Reset to initial position when disabling movement
	if not circular_movement_enabled:
		position = initial_position
		circular_angle = 0.0
		animated_sprite.flip_h = false  # Reset sprite orientation

func _on_detection_area_body_entered(body: Node2D):
	var health_component = body.get_node("HealthScript") if body.has_node("HealthScript") else null
	if health_component:  # Only trigger if it's actually the player
		player_detected = true
		is_spiked = true  # Set spiked flag
		detection_timer = 2.0  # 2 seconds
		animated_sprite.play("Spiked")
		
		# Show the unparryable warning
		if unparryable_warning:
			unparryable_warning.visible = true
		
		# Make the damage area unparryable when spiked
		var damage_area = $KillzoneScript_Area  # Adjust path as needed
		if damage_area:
			damage_area.unparryable = true
		


func _on_detection_area_body_exited(body: Node2D):
	# Optional: Handle when player leaves detection area
	if body.is_in_group("Player"):
		print("Player left detection area")

# Add a method to check if enemy is in spiked form
func is_in_spiked_form() -> bool:
	return is_spiked

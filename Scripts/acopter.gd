extends Node2D
@export var acorn_scene: PackedScene
@export var fire_rate: float = 2.0  # Time between shots in seconds
@export var spawn_offset: Vector2 = Vector2(0, 4)  # Offset from helicopter center to spawn acorns
@export var facing_left: bool = false  # Toggle for direction

# Vertical movement properties
@export var vertical_movement_enabled: bool = true  # Toggle vertical movement on/off
@export var vertical_distance: float = 50.0  # Distance to move up and down
@export var vertical_speed: float = 30.0  # Speed of vertical movement

var fire_timer: Timer
var animated_sprite: AnimatedSprite2D
var initial_position: Vector2
var moving_up: bool = true

func _ready():
	# Store the initial position for vertical movement reference
	initial_position = position
	
	# Get the AnimatedSprite2D node (assumes it's a child of this node)
	animated_sprite = get_node("AnimatedSprite2D")
	
	# Set initial facing direction
	update_facing_direction()
	
	# Create and configure the firing timer
	fire_timer = Timer.new()
	fire_timer.wait_time = fire_rate
	fire_timer.autostart = true
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	add_child(fire_timer)

func _process(delta):
	# Handle vertical movement if enabled
	if vertical_movement_enabled:
		handle_vertical_movement(delta)

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

func toggle_direction():
	facing_left = !facing_left
	update_facing_direction()

func update_facing_direction():
	if animated_sprite:
		animated_sprite.flip_h = facing_left

func toggle_vertical_movement():
	vertical_movement_enabled = !vertical_movement_enabled
	# Reset to initial position when disabling movement
	if not vertical_movement_enabled:
		position.y = initial_position.y

func _on_fire_timer_timeout():
	# Start the shooting sequence if the scene is assigned
	if acorn_scene and animated_sprite:
		start_shooting_sequence()

func start_shooting_sequence():
	# Play the "Shoot" animation
	animated_sprite.play("Shoot")
	
	# Wait 0.2 seconds before spawning the acorn
	await get_tree().create_timer(0.2).timeout
	spawn_acorn()
	
	# Wait another 0.2 seconds after spawning
	await get_tree().create_timer(0.2).timeout
	
	# Return to idle animation
	animated_sprite.play("Idle")

func spawn_acorn():
	# Instance the acorn scene
	var acorn = acorn_scene.instantiate()
	
	# Get the parent scene (usually the main scene or level)
	var parent = get_parent()
	if parent:
		# Add the acorn to the scene
		parent.add_child(acorn)
		
		# Calculate spawn position based on facing direction
		var adjusted_spawn_offset = spawn_offset
		if facing_left:
			adjusted_spawn_offset.x = -spawn_offset.x  # Flip the x offset when facing left
		
		# Set the acorn's position relative to the helicopter
		acorn.global_position = global_position + adjusted_spawn_offset
		
		# Set the acorn's direction
		if acorn.has_method("set_direction"):
			acorn.set_direction(facing_left)

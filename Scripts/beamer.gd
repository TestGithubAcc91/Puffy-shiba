extends Node2D
@export var animation_duration: float = 3.0
@export var speedup_duration: float = 2.0
@export var cooldown_duration: float = 2.0
@export var beam_scene: PackedScene  # Scene containing a single beam square
@export var beam_count: int = 5  # Number of beam squares to create
@export var beam_start_offset: float = -5  # Distance from shooter to start beam
@export var direction: Direction = Direction.UP  # Beam direction
@onready var animated_sprite = $AnimatedSprite2D

enum Direction {
	UP,
	DOWN,
	LEFT,
	RIGHT
}

var animation_timer = 0.0
var is_shooting = false
var is_speeding_up = false
var is_on_cooldown = false
var beam_instances = []
var warning_beam_instances = []
var warning_beam_tweens = []  # Store tween references

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animated_sprite.play("default")
	set_rotation_for_direction()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	animation_timer += delta
	
	# Check if we should start speeding up (2 seconds before shoot) - only if not on cooldown
	if not is_shooting and not is_speeding_up and not is_on_cooldown and animation_timer >= (animation_duration - speedup_duration):
		animated_sprite.speed_scale = 5
		is_speeding_up = true
		create_warning_beam()
	
	if animation_timer >= animation_duration:
		if is_shooting:
			# Finished shooting, start cooldown
			animated_sprite.play("default")
			animated_sprite.speed_scale = 1.0
			is_shooting = false
			is_speeding_up = false
			is_on_cooldown = true
			destroy_beam()
		elif is_on_cooldown:
			# Cooldown finished, can start next cycle
			is_on_cooldown = false
		else:
			# Start shooting
			animated_sprite.play("Shoot")
			animated_sprite.speed_scale = 1.0
			is_shooting = true
			is_speeding_up = false
			destroy_warning_beam()  # Remove warning beam before creating real beam
			create_beam()
		
		animation_timer = 0.0

func set_rotation_for_direction():
	match direction:
		Direction.UP:
			rotation_degrees = 0
		Direction.DOWN:
			rotation_degrees = 180
		Direction.LEFT:
			rotation_degrees = -90  # Changed from 90 to -90
		Direction.RIGHT:
			rotation_degrees = 90   # Changed from -90 to 90

func get_beam_direction_vector() -> Vector2:
	match direction:
		Direction.UP:
			return Vector2.DOWN  # Changed from UP
		Direction.DOWN:
			return Vector2.UP    # Changed from DOWN
		Direction.LEFT:
			return Vector2.RIGHT # Changed from LEFT
		Direction.RIGHT:
			return Vector2.LEFT  # Changed from RIGHT
		_:
			return Vector2.DOWN  # Changed default from UP

func create_warning_beam():
	if not beam_scene:
		print("No beam scene assigned!")
		return
	
	# Clear any existing warning beam instances
	destroy_warning_beam()
	
	var beam_size = 16  # Adjust this to match your beam square size
	
	# Create warning beam squares
	for i in range(beam_count):
		var beam_instance = beam_scene.instantiate()
		get_parent().add_child(beam_instance)
		
		# Calculate world position
		var distance_from_origin = beam_start_offset - (i * beam_size)
		var direction_vector = get_beam_direction_vector()
		beam_instance.global_position = global_position + (direction_vector * distance_from_origin)
		
		# Rotate beam sprites for horizontal directions
		if direction == Direction.LEFT or direction == Direction.RIGHT:
			beam_instance.rotation_degrees = 90
		
		# Make the warning beam transparent and disable non-visual components
		setup_warning_beam_appearance(beam_instance)
		
		warning_beam_instances.append(beam_instance)

func setup_warning_beam_appearance(beam_instance):
	# Find and modify only the AnimatedSprite2D node to make it transparent/flashing
	var animated_sprite_node = find_animated_sprite_in_beam(beam_instance)
	if animated_sprite_node:
		# Make it semi-transparent
		animated_sprite_node.modulate.a = 0.5
		
		# Create a flashing effect using a Tween
		var tween = create_tween()
		tween.set_loops()  # Make it loop indefinitely
		tween.tween_property(animated_sprite_node, "modulate:a", 0.1, 0.3)
		tween.tween_property(animated_sprite_node, "modulate:a", 0.5, 0.3)
		
		# Store the tween reference so we can kill it later
		warning_beam_tweens.append(tween)
	
	# Disable collision and damage components (keep only visual)
	disable_non_visual_components(beam_instance)

func find_animated_sprite_in_beam(beam_instance) -> AnimatedSprite2D:
	# Search for AnimatedSprite2D node in the beam instance
	for child in beam_instance.get_children():
		if child is AnimatedSprite2D:
			return child
	
	# If not found in direct children, search recursively
	return find_animated_sprite_recursive(beam_instance)

func find_animated_sprite_recursive(node) -> AnimatedSprite2D:
	if node is AnimatedSprite2D:
		return node
	
	for child in node.get_children():
		var result = find_animated_sprite_recursive(child)
		if result:
			return result
	
	return null

func disable_non_visual_components(beam_instance):
	# Recursively disable collision bodies, areas, and other non-visual components
	disable_components_recursive(beam_instance)

func disable_components_recursive(node):
	# Disable collision and damage components but keep visual ones
	if node is CollisionShape2D or node is CollisionPolygon2D:
		node.disabled = true
	elif node is Area2D or node is RigidBody2D or node is CharacterBody2D:
		# Disable the collision layer/mask to prevent interactions
		if node.has_method("set_collision_layer"):
			node.set_collision_layer(0)
		if node.has_method("set_collision_mask"):
			node.set_collision_mask(0)
	
	# Continue recursively for all children
	for child in node.get_children():
		disable_components_recursive(child)

func create_beam():
	if not beam_scene:
		print("No beam scene assigned!")
		return
	
	# Clear any existing beam instances
	destroy_beam()
	
	var beam_size = 16  # Adjust this to match your beam square size
	
	# Create beam squares
	for i in range(beam_count):
		var beam_instance = beam_scene.instantiate()
		get_parent().add_child(beam_instance)  # Add to parent instead of self
		
		# Calculate world position
		var distance_from_origin = beam_start_offset - (i * beam_size)
		var direction_vector = get_beam_direction_vector()
		beam_instance.global_position = global_position + (direction_vector * distance_from_origin)
		
		# Rotate beam sprites for horizontal directions
		if direction == Direction.LEFT or direction == Direction.RIGHT:
			beam_instance.rotation_degrees = 90
		
		beam_instances.append(beam_instance)

func destroy_beam():
	for beam in beam_instances:
		if is_instance_valid(beam):
			beam.queue_free()
	beam_instances.clear()

func destroy_warning_beam():
	# Kill all warning beam tweens first
	for tween in warning_beam_tweens:
		if is_instance_valid(tween):
			tween.kill()
	warning_beam_tweens.clear()
	
	# Then destroy the beam instances
	for beam in warning_beam_instances:
		if is_instance_valid(beam):
			beam.queue_free()
	warning_beam_instances.clear()

# Helper function to change direction at runtime
func set_direction(new_direction: Direction):
	direction = new_direction
	set_rotation_for_direction()

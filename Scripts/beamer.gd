extends Node2D

@export var animation_duration: float = 3.0
@export var speedup_duration: float = 2.0
@export var cooldown_duration: float = 2.0
@export var beam_scene: PackedScene  # Scene containing a single beam square
@export var beam_count: int = 5  # Number of beam squares to create
@export var beam_start_offset: float = -5  # Distance below shooter to start beam
@onready var animated_sprite = $AnimatedSprite2D

var animation_timer = 0.0
var is_shooting = false
var is_speeding_up = false
var is_on_cooldown = false
var beam_instances = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animated_sprite.play("default")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	animation_timer += delta
	
	# Check if we should start speeding up (2 seconds before shoot) - only if not on cooldown
	if not is_shooting and not is_speeding_up and not is_on_cooldown and animation_timer >= (animation_duration - speedup_duration):
		animated_sprite.speed_scale = 5
		is_speeding_up = true
	
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
			create_beam()
		
		animation_timer = 0.0

func create_beam():
	if not beam_scene:
		print("No beam scene assigned!")
		return
	
	# Clear any existing beam instances
	destroy_beam()
	
	# Create beam squares
	for i in range(beam_count):
		var beam_instance = beam_scene.instantiate()
		add_child(beam_instance)
		
		# Position each beam square vertically with start offset
		# You may need to adjust this based on your beam square size
		var beam_size = 16  # Adjust this to match your beam square size
		beam_instance.position.y = beam_start_offset + -(i * beam_size)
		
		beam_instances.append(beam_instance)

func destroy_beam():
	for beam in beam_instances:
		if is_instance_valid(beam):
			beam.queue_free()
	beam_instances.clear()

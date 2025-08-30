extends CharacterBody2D

const SPEED = 150.0
const JUMP_VELOCITY = -200.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_script = $HealthScript

var flicker_timer: Timer
var is_flickering: bool = false
@export var flicker_interval: float = 0.1  # How fast the flicker effect is

# Parry system variables
var parry_timer: Timer
var is_parrying: bool = false
@export var parry_duration: float = 0.4  # Duration of parry i-frames
@export var parry_cooldown: float = 1.0  # Cooldown between parries
var parry_cooldown_timer: Timer
var can_parry: bool = true

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# Handle jump.
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# Handle parry input
	if Input.is_action_just_pressed("Parry") and can_parry:
		activate_parry()
	
	# Get the input direction and handle the movement/deceleration.
	var direction := Input.get_axis("Move_Left", "Move_Right")
	
	if direction > 0:
		animated_sprite.flip_h = false
	elif direction < 0:
		animated_sprite.flip_h = true
		
	if is_on_floor():
		if direction == 0:
			animated_sprite.play("Idle")
		else:
			animated_sprite.play("Run")
	else: 
		animated_sprite.play("Jump")
	
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
	
	move_and_slide()

func _ready():
	# Connect to the health component's signals
	health_script.died.connect(_on_player_died)
	health_script.iframe_started.connect(_on_iframe_started)
	health_script.iframe_ended.connect(_on_iframe_ended)
	
	# Create flicker timer
	flicker_timer = Timer.new()
	flicker_timer.wait_time = flicker_interval
	flicker_timer.timeout.connect(_on_flicker_timeout)
	add_child(flicker_timer)
	
	# Create parry timer
	parry_timer = Timer.new()
	parry_timer.wait_time = parry_duration
	parry_timer.one_shot = true
	parry_timer.timeout.connect(_on_parry_timeout)
	add_child(parry_timer)
	
	# Create parry cooldown timer
	parry_cooldown_timer = Timer.new()
	parry_cooldown_timer.wait_time = parry_cooldown
	parry_cooldown_timer.one_shot = true
	parry_cooldown_timer.timeout.connect(_on_parry_cooldown_timeout)
	add_child(parry_cooldown_timer)

func activate_parry():
	if not can_parry:
		return
	
	print("Parry activated! Player is invulnerable for ", parry_duration, " seconds")
	
	# Set parry state
	is_parrying = true
	can_parry = false
	
	# Grant invulnerability through health script
	health_script.is_invulnerable = true
	
	# Start parry timer
	parry_timer.start()
	
	# Start cooldown timer
	parry_cooldown_timer.start()
	
	# Start visual feedback (flicker effect)
	is_flickering = true
	flicker_timer.start()
	
	# Emit iframe signals for consistency with damage-based i-frames
	health_script.iframe_started.emit()

func _on_parry_timeout():
	print("Parry ended")
	is_parrying = false
	
	# Remove invulnerability
	health_script.is_invulnerable = false
	
	# Stop flicker effect
	is_flickering = false
	flicker_timer.stop()
	animated_sprite.modulate.a = 1.0
	
	# Emit iframe ended signal
	health_script.iframe_ended.emit()

func _on_parry_cooldown_timeout():
	can_parry = true
	print("Parry is ready to use again")

func _on_iframe_started():
	# Only start flickering if we're not already parrying (to avoid conflicts)
	if not is_parrying:
		is_flickering = true
		flicker_timer.start()
		print("Flicker effect started")

func _on_iframe_ended():
	# Only stop flickering if we're not parrying (parry has its own flicker control)
	if not is_parrying:
		is_flickering = false
		flicker_timer.stop()
		# Make sure sprite is visible when iframes end
		animated_sprite.modulate.a = 1.0
		print("Flicker effect ended")

func _on_flicker_timeout():
	if is_flickering:
		# Toggle visibility by changing alpha
		if animated_sprite.modulate.a > 0.5:
			animated_sprite.modulate.a = 0.3  # Semi-transparent
		else:
			animated_sprite.modulate.a = 1.0  # Fully visible
		
		flicker_timer.start()  # Restart timer for continuous flicker

func _on_player_died():
	print("Player died! Reloading scene...")
	# Stop all effects when player dies
	is_flickering = false
	is_parrying = false
	flicker_timer.stop()
	parry_timer.stop()
	parry_cooldown_timer.stop()
	animated_sprite.modulate.a = 1.0
	
	# Add the same time scale effect as the original script
	Engine.time_scale = 0.2
	
	# Optional: disable player collision to prevent further interactions
	$CollisionShape2D.set_deferred("disabled", true)
	
	# Wait a moment before reloading (like the original timer)
	await get_tree().create_timer(1.0).timeout
	
	# Reset time scale and reload scene
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func get_is_parrying() -> bool:
	return is_parrying

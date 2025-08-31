extends CharacterBody2D

const SPEED = 150.0
const JUMP_VELOCITY = -200.0
const HIGH_JUMP_VELOCITY = -350.0

@onready var animated_sprite: AnimatedSprite2D = $MainSprite
@onready var glint_sprite: AnimatedSprite2D = $GlintSprite
@onready var health_script = $HealthScript

var flicker_timer: Timer
var is_flickering: bool = false
@export var flicker_interval: float = 0.1  # How fast the flicker effect is

# Parry system variables
var parry_timer: Timer
var is_parrying: bool = false
@export var parry_duration: float = 0.4  # Duration of parry i-frames
@export var parry_success_cooldown: float = 0.0  # No cooldown after successful parry
@export var parry_fail_cooldown: float = 1.0  # Cooldown after failed parry
var parry_cooldown_timer: Timer
var can_parry: bool = true
var parry_was_successful: bool = false  # Track if the current parry was successful

# Parry stack system variables
@export var max_parry_stacks: int = 3  # Maximum number of parry stacks
var current_parry_stacks: int = 0  # Current number of parry stacks
signal parry_stacks_changed(new_stacks: int)  # Signal for UI updates

# Charge sprite textures (4 random options)
@export var charge_texture_1: Texture2D
@export var charge_texture_2: Texture2D
@export var charge_texture_3: Texture2D
@export var charge_texture_4: Texture2D
@export var empty_charge_texture: Texture2D  # Texture for empty state

# References to the 3 empty charge sprites - Drag from scene tree
@export var empty_charge_sprite_1: Sprite2D
@export var empty_charge_sprite_2: Sprite2D
@export var empty_charge_sprite_3: Sprite2D

var empty_charge_sprites: Array[Sprite2D] = []
var charge_textures: Array[Texture2D] = []
var assigned_textures: Array[Texture2D] = []  # Remember assigned textures for each sprite

# Dash system variables
@export var dash_distance: float = 200.0  # How far the dash goes
@export var dash_speed: float = 800.0  # How fast the dash moves (pixels per second)
@export var dash_cooldown: float = 1.0  # Cooldown between dashes
@export var wall_bounce_force: Vector2 = Vector2(300.0, -150.0)  # Horizontal and vertical bounce force
@export var bounce_delay: float = 0.2  # Delay before horizontal bounce kicks in
@export var bounce_distance: float = 150.0  # How far the bounce back goes
@export var bounce_speed: float = 600.0  # How fast the bounce moves (pixels per second)

# High jump system variables
@export var high_jump_cooldown: float = 2.0  # Cooldown between high jumps
var high_jump_cooldown_timer: Timer
var can_high_jump: bool = true
var dash_timer: Timer
var dash_cooldown_timer: Timer
var bounce_timer: Timer
var is_dashing: bool = false
var can_dash: bool = true
var dash_direction: Vector2 = Vector2.ZERO
var dash_started_on_ground: bool = false  # Track if dash started while grounded
var was_on_ground_before_dash: bool = false  # Track previous ground state
var dash_start_time: float = 0.0  # Track when dash started
var dash_duration: float = 0.0  # Calculated based on distance and speed
var pending_bounce_direction: float = 0.0  # Store bounce direction for delayed application
var is_bouncing: bool = false  # Track if we're in bounce state
var bounce_start_time: float = 0.0  # Track when bounce started
var bounce_duration: float = 0.0  # Calculated based on bounce distance and speed
var bounce_direction_vector: Vector2 = Vector2.ZERO  # Store bounce direction as vector

func _physics_process(delta: float) -> void:
	# Handle dash input
	if Input.is_action_just_pressed("Dash") and can_dash and current_parry_stacks >= 2:
		activate_dash()
	
	# If dashing, override normal movement
	if is_dashing:
		velocity.x = dash_direction.x * (dash_distance / dash_duration)
		
		# Calculate elapsed dash time
		var current_time = Time.get_ticks_msec() / 1000.0
		var dash_elapsed = current_time - dash_start_time
		var dash_progress = dash_elapsed / dash_duration
		
		# For the first half of dash, maintain horizontal movement only (no gravity)
		if dash_progress < 0.5:
			# Lock vertical velocity to prevent falling/rising
			velocity.y = 0.0
		else:
			# Second half: apply gravity normally
			if not is_on_floor():
				velocity += get_gravity() * delta
		
		move_and_slide()
		
		# Check for wall collision during dash
		if is_on_wall_only():
			handle_wall_bounce()
			return
		
		# Check for ground landing to end dash prematurely
		check_dash_ground_landing()
		return
	
	# If bouncing, handle bounce movement
	if is_bouncing:
		var current_time = Time.get_ticks_msec() / 1000.0
		var bounce_elapsed = current_time - bounce_start_time
		
		# Check if bounce duration is complete
		if bounce_elapsed >= bounce_duration:
			end_bounce()
		else:
			# Apply bounce movement with distance/speed calculation
			velocity.x = bounce_direction_vector.x * (bounce_distance / bounce_duration)
		
		# Still apply gravity during bounce
		if not is_on_floor():
			velocity += get_gravity() * delta
		
		move_and_slide()
		return
	
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# Handle jump.
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# Handle high jump (Q key)
	if Input.is_action_just_pressed("HighJump") and is_on_floor() and can_high_jump and current_parry_stacks >= 2:
		activate_high_jump()
	
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
	
	# Setup charge sprites and textures
	setup_charge_system()
	
	# Initialize glint sprite as inactive
	if glint_sprite:
		glint_sprite.visible = false
		print("Glint sprite initialized as inactive")
	else:
		print("Warning: GlintSprite not found!")
	
	# Calculate dash duration based on distance and speed
	dash_duration = dash_distance / dash_speed
	
	# Calculate bounce duration based on distance and speed
	bounce_duration = bounce_distance / bounce_speed
	
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
	parry_cooldown_timer.one_shot = true
	parry_cooldown_timer.timeout.connect(_on_parry_cooldown_timeout)
	add_child(parry_cooldown_timer)
	
	# Create dash timer
	dash_timer = Timer.new()
	dash_timer.wait_time = dash_duration
	dash_timer.one_shot = true
	dash_timer.timeout.connect(_on_dash_timeout)
	add_child(dash_timer)
	
	# Create dash cooldown timer
	dash_cooldown_timer = Timer.new()
	dash_cooldown_timer.wait_time = dash_cooldown
	dash_cooldown_timer.one_shot = true
	dash_cooldown_timer.timeout.connect(_on_dash_cooldown_timeout)
	add_child(dash_cooldown_timer)
	
	# Create bounce timer for delayed horizontal bounce
	bounce_timer = Timer.new()
	bounce_timer.wait_time = bounce_delay
	bounce_timer.one_shot = true
	bounce_timer.timeout.connect(_on_bounce_timeout)
	add_child(bounce_timer)
	
	# Create high jump cooldown timer
	high_jump_cooldown_timer = Timer.new()
	high_jump_cooldown_timer.wait_time = high_jump_cooldown
	high_jump_cooldown_timer.one_shot = true
	high_jump_cooldown_timer.timeout.connect(_on_high_jump_cooldown_timeout)
	add_child(high_jump_cooldown_timer)

func activate_parry():
	if not can_parry:
		return
	
	print("Parry activated! Player is invulnerable for ", parry_duration, " seconds")
	
	# Set parry state
	is_parrying = true
	can_parry = false
	parry_was_successful = false  # Reset success flag
	
	# Grant invulnerability through health script
	health_script.is_invulnerable = true
	
	# Activate glint sprite
	if glint_sprite:
		glint_sprite.visible = true
		glint_sprite.play("default")  # Play the glint animation (adjust animation name as needed)
		print("Glint sprite activated")
	
	# Start parry timer
	parry_timer.start()
	
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
	
	# Deactivate glint sprite
	if glint_sprite:
		glint_sprite.visible = false
		glint_sprite.stop()  # Stop the animation
		print("Glint sprite deactivated")
	
	# Stop flicker effect
	is_flickering = false
	flicker_timer.stop()
	animated_sprite.modulate.a = 1.0
	
	# Emit iframe ended signal
	health_script.iframe_ended.emit()
	
	# Determine cooldown based on whether parry was successful
	if parry_was_successful:
		print("Successful parry! No cooldown applied")
		can_parry = true  # Can parry immediately again
	else:
		print("Failed parry! Applying ", parry_fail_cooldown, " second cooldown")
		parry_cooldown_timer.wait_time = parry_fail_cooldown
		parry_cooldown_timer.start()

func _on_parry_cooldown_timeout():
	can_parry = true
	print("Parry is ready to use again")

# Called by damage sources when a parry is successful
func on_parry_success():
	print("Parry success registered!")
	parry_was_successful = true
	
	# Add a parry stack
	add_parry_stack()

# Parry stack management functions
func add_parry_stack():
	if current_parry_stacks < max_parry_stacks:
		current_parry_stacks += 1
		print("Parry stack gained! Current stacks: ", current_parry_stacks, "/", max_parry_stacks)
		parry_stacks_changed.emit(current_parry_stacks)
		update_charge_sprites()
	else:
		print("Max parry stacks reached (", max_parry_stacks, ")")

func consume_parry_stack():
	if current_parry_stacks > 0:
		current_parry_stacks -= 1
		print("Parry stack consumed! Remaining stacks: ", current_parry_stacks, "/", max_parry_stacks)
		parry_stacks_changed.emit(current_parry_stacks)
		update_charge_sprites()
		return true
	return false

func reset_parry_stacks():
	current_parry_stacks = 0
	print("Parry stacks reset!")
	parry_stacks_changed.emit(current_parry_stacks)
	update_charge_sprites()

func get_parry_stacks() -> int:
	return current_parry_stacks

# Charge sprite system functions
func setup_charge_system():
	# Store references to empty charge sprites only
	empty_charge_sprites = [empty_charge_sprite_1, empty_charge_sprite_2, empty_charge_sprite_3]
	
	# Store texture references in array
	charge_textures = [charge_texture_1, charge_texture_2, charge_texture_3, charge_texture_4]
	
	# Initialize assigned textures array (null means no texture assigned yet)
	assigned_textures = [null, null, null]
	
	# Initially all sprites should show as empty
	update_charge_sprites()

func update_charge_sprites():
	# Update empty charge sprites based on current stack count
	# Fill from left to right (1, 2, 3), empty from right to left (3, 2, 1)
	for i in range(empty_charge_sprites.size()):
		if empty_charge_sprites[i]:
			if i < current_parry_stacks:
				# This slot should be filled
				if assigned_textures[i] == null:
					# No texture assigned yet - assign a new random one
					assign_new_random_texture_to_sprite(i)
				else:
					# Texture already assigned - use the remembered one
					empty_charge_sprites[i].texture = assigned_textures[i]
					empty_charge_sprites[i].modulate.a = 1.0  # Make sure it's fully visible
					print("Empty charge sprite ", i + 1, " using remembered texture")
			else:
				# This slot should be empty - clear assigned texture and show empty
				assigned_textures[i] = null  # Clear the remembered texture
				assign_empty_texture_to_sprite(i)
			
			# Always keep sprites visible
			empty_charge_sprites[i].visible = true
		
		print("Charge slot ", i + 1, " - State: ", ("FILLED" if i < current_parry_stacks else "EMPTY"))

func get_currently_used_textures() -> Array[Texture2D]:
	# Get all textures currently assigned to filled sprites
	var used_textures: Array[Texture2D] = []
	for i in range(current_parry_stacks):
		if assigned_textures[i] != null:
			used_textures.append(assigned_textures[i])
	return used_textures

func assign_new_random_texture_to_sprite(index: int):
	# Assign a random texture from the 4 options and remember it, ensuring no repeats
	if index < empty_charge_sprites.size() and empty_charge_sprites[index]:
		var valid_textures = charge_textures.filter(func(texture): return texture != null)
		if valid_textures.size() > 0:
			# Get currently used textures to avoid repeats
			var used_textures = get_currently_used_textures()
			
			# Filter out textures that are already in use
			var available_textures = valid_textures.filter(func(texture): return not texture in used_textures)
			
			# If all textures are used but we have more slots than textures, allow repeats
			if available_textures.size() == 0:
				available_textures = valid_textures
				print("Warning: All textures in use, allowing repeats for sprite ", index + 1)
			
			# Pick a random texture from available ones
			var random_texture = available_textures[randi() % available_textures.size()]
			assigned_textures[index] = random_texture  # Remember this texture
			empty_charge_sprites[index].texture = random_texture
			empty_charge_sprites[index].modulate.a = 1.0  # Make sure it's fully visible
			print("Empty charge sprite ", index + 1, " assigned NEW unique random texture and remembered it")

func assign_empty_texture_to_sprite(index: int):
	# Assign the empty texture to show the sprite as empty
	if index < empty_charge_sprites.size() and empty_charge_sprites[index]:
		if empty_charge_texture:
			empty_charge_sprites[index].texture = empty_charge_texture
			empty_charge_sprites[index].modulate.a = 1.0  # Reset alpha
			print("Empty charge sprite ", index + 1, " assigned empty texture")
		else:
			# If no empty texture is set, make sprite semi-transparent
			empty_charge_sprites[index].modulate.a = 0.3
			print("Empty charge sprite ", index + 1, " made semi-transparent (no empty texture)")

func activate_dash():
	if not can_dash or is_dashing:
		return
	
	# Check if we have enough stacks to use dash
	if current_parry_stacks < 2:
		print("Not enough parry stacks for dash! Need 2 stacks, have ", current_parry_stacks)
		return
	
	print("Dash activated! Consuming 2 parry stacks. Current: ", current_parry_stacks, "/", max_parry_stacks)
	
	# Consume 2 stacks for dash
	current_parry_stacks -= 2
	print("Dash consumed 2 stacks. Remaining: ", current_parry_stacks, "/", max_parry_stacks)
	parry_stacks_changed.emit(current_parry_stacks)
	update_charge_sprites()
	
	# Store ground state when dash starts
	dash_started_on_ground = is_on_floor()
	was_on_ground_before_dash = dash_started_on_ground
	
	# Record dash start time for horizontal-only calculation
	dash_start_time = Time.get_ticks_msec() / 1000.0
	
	# Determine dash direction based on sprite facing
	if animated_sprite.flip_h:
		dash_direction = Vector2.LEFT
	else:
		dash_direction = Vector2.RIGHT
	
	# Set dash state
	is_dashing = true
	can_dash = false
	
	# Start dash timer
	dash_timer.start()
	
	# Start cooldown timer
	dash_cooldown_timer.start()

func activate_high_jump():
	if not can_high_jump:
		return
	
	# Check if we have enough stacks to use high jump
	if current_parry_stacks < 2:
		print("Not enough parry stacks for high jump! Need 2 stacks, have ", current_parry_stacks)
		return
	
	print("High jump activated! Consuming 2 parry stacks. Current: ", current_parry_stacks, "/", max_parry_stacks)
	
	# Consume 2 stacks for high jump
	current_parry_stacks -= 2
	print("High jump consumed 2 stacks. Remaining: ", current_parry_stacks, "/", max_parry_stacks)
	parry_stacks_changed.emit(current_parry_stacks)
	update_charge_sprites()
	
	# Apply high jump velocity
	velocity.y = HIGH_JUMP_VELOCITY
	
	# Set cooldown
	can_high_jump = false
	high_jump_cooldown_timer.start()

func _on_high_jump_cooldown_timeout():
	can_high_jump = true
	print("High jump is ready to use again")

func handle_wall_bounce():
	print("Wall hit during dash! Bouncing back")
	
	# Store dash direction before ending dash (since end_dash resets it)
	var original_dash_direction = dash_direction
	
	# End the dash
	end_dash()
	
	# Apply upward bounce immediately
	velocity.y = wall_bounce_force.y
	# Zero out horizontal movement for now
	velocity.x = 0.0
	
	# Determine bounce direction (opposite of dash direction)
	if original_dash_direction.x > 0:  # Was dashing right
		bounce_direction_vector = Vector2.LEFT
	else:  # Was dashing left
		bounce_direction_vector = Vector2.RIGHT
	
	# Start timer for delayed horizontal bounce
	bounce_timer.start()

func _on_bounce_timeout():
	# Start the horizontal bounce movement
	is_bouncing = true
	bounce_start_time = Time.get_ticks_msec() / 1000.0
	print("Horizontal distance-based bounce started")

func end_bounce():
	is_bouncing = false
	bounce_direction_vector = Vector2.ZERO
	bounce_start_time = 0.0
	print("Bounce movement ended")

func check_dash_ground_landing():
	# Only end dash early if we land on ground AND we didn't start on ground
	if is_on_floor() and not dash_started_on_ground:
		print("Dash ended early due to ground landing")
		end_dash()
	# If we started on ground, wait for the next ground contact after being airborne
	elif dash_started_on_ground and not was_on_ground_before_dash and is_on_floor():
		print("Dash ended early due to returning to ground after being airborne")
		end_dash()
	
	# Update previous ground state for next frame comparison
	was_on_ground_before_dash = is_on_floor()

func end_dash():
	if not is_dashing:
		return
		
	is_dashing = false
	dash_direction = Vector2.ZERO
	dash_start_time = 0.0  # Reset start time
	dash_timer.stop()  # Stop the timer since we're ending early

func _on_dash_timeout():
	print("Dash ended (timer)")
	end_dash()

func _on_dash_cooldown_timeout():
	can_dash = true
	print("Dash is ready to use again")

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
	is_dashing = false
	is_bouncing = false
	flicker_timer.stop()
	parry_timer.stop()
	parry_cooldown_timer.stop()
	dash_timer.stop()
	dash_cooldown_timer.stop()
	bounce_timer.stop()
	animated_sprite.modulate.a = 1.0
	pending_bounce_direction = 0.0
	bounce_direction_vector = Vector2.ZERO
	
	# Deactivate glint sprite on death
	if glint_sprite:
		glint_sprite.visible = false
		glint_sprite.stop()
	
	# Reset parry stacks on death
	reset_parry_stacks()
	
	# Add the same time scale effect as the original script
	Engine.time_scale = 0.2
	
	# Optional: disable player collision to prevent further interactions
	$CollisionShape2D.set_deferred("disabled", true)
	
	# Wait a moment before reloading (like the original timer)
	await get_tree().create_timer(1.0).timeout
	
	# Reset time scale and reload scene
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

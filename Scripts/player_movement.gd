extends CharacterBody2D

const SPEED = 150.0
const JUMP_VELOCITY = -200.0
const HIGH_JUMP_VELOCITY = -350.0

@onready var animated_sprite: AnimatedSprite2D = $MainSprite
@onready var glint_sprite: AnimatedSprite2D = $GlintSprite
@onready var zipline_friction: AnimatedSprite2D = $ZiplineFriction
@onready var parry_spark: Sprite2D = $ParrySpark
@onready var health_script = $HealthScript
@onready var vine_component = $VineComponent

@export var air_puff_scene: PackedScene
@export var air_puffV_scene: PackedScene

var last_attack_was_unparryable: bool = false

# Parry variables
var parry_timer: Timer
var is_parrying: bool = false
@export var parry_duration: float = 0.4
@export var parry_success_cooldown: float = 0.0
@export var parry_fail_cooldown: float = 1.0
var parry_cooldown_timer: Timer
var can_parry: bool = true
var parry_was_successful: bool = false
# NEW: Track if player was already invulnerable before parry
var was_invulnerable_before_parry: bool = false

# Parry freeze variables
var parry_freeze_timer: Timer
var is_in_parry_freeze: bool = false
var parry_pre_freeze_timer: Timer
var is_in_pre_freeze_parry: bool = false
@export var parry_freeze_duration: float = 0.3
@export var parry_pre_freeze_duration: float = 0.1

# Charge system variables
@export var max_parry_stacks: int = 3
var current_parry_stacks: int = 0
signal parry_stacks_changed(new_stacks: int)

@export var charge_texture_1: Texture2D
@export var charge_texture_2: Texture2D
@export var charge_texture_3: Texture2D
@export var charge_texture_4: Texture2D
@export var empty_charge_texture: Texture2D
@export var empty_charge_sprite_1: Sprite2D
@export var empty_charge_sprite_2: Sprite2D
@export var empty_charge_sprite_3: Sprite2D

var empty_charge_sprites: Array[Sprite2D] = []
var charge_textures: Array[Texture2D] = []
var assigned_textures: Array[Texture2D] = []

# Movement variables
@export var dash_distance: float = 200.0
@export var dash_speed: float = 800.0
@export var dash_cooldown: float = 0.5
@export var wall_bounce_force: Vector2 = Vector2(300.0, -150.0)
@export var bounce_delay: float = 0.2
@export var bounce_distance: float = 150.0
@export var bounce_speed: float = 600.0
@export var high_jump_cooldown: float = 2.0

var high_jump_cooldown_timer: Timer
var can_high_jump: bool = true
var dash_timer: Timer
var dash_cooldown_timer: Timer
var bounce_timer: Timer
var is_dashing: bool = false
var can_dash: bool = true
var dash_direction: Vector2 = Vector2.ZERO
var dash_started_on_ground: bool = false
var was_on_ground_before_dash: bool = false
var dash_start_time: float = 0.0
var dash_duration: float = 0.0
var is_bouncing: bool = false
var bounce_start_time: float = 0.0
var bounce_duration: float = 0.0
var bounce_direction_vector: Vector2 = Vector2.ZERO

# NEW: Variable to track if this is a vine release dash
var is_vine_release_dash: bool = false

var zipline_in_range: Zipline = null
var is_on_zipline: bool = false
var current_zipline: Zipline = null
var zipline_grab_position: float = 0.0


func _ready():
	health_script.died.connect(_on_player_died)
	
	setup_charge_system()
	setup_ui()
	setup_durations()
	setup_timers()

func setup_ui():
	if glint_sprite:
		glint_sprite.visible = false
	if zipline_friction:
		zipline_friction.visible = false
	if parry_spark:
		parry_spark.visible = false

func setup_durations():
	dash_duration = dash_distance / dash_speed
	bounce_duration = bounce_distance / bounce_speed

func setup_timers():
	var timer_configs = [
		{timer = "parry_timer", wait_time = parry_duration, callback = "_on_parry_timeout"},
		{timer = "parry_cooldown_timer", callback = "_on_parry_cooldown_timeout"},
		{timer = "parry_pre_freeze_timer", wait_time = parry_pre_freeze_duration, callback = "_on_parry_pre_freeze_timeout"},
		{timer = "parry_freeze_timer", wait_time = parry_freeze_duration, callback = "_on_parry_freeze_timeout"},
		{timer = "dash_timer", wait_time = dash_duration, callback = "_on_dash_timeout"},
		{timer = "dash_cooldown_timer", wait_time = dash_cooldown, callback = "_on_dash_cooldown_timeout"},
		{timer = "bounce_timer", wait_time = bounce_delay, callback = "_on_bounce_timeout"},
		{timer = "high_jump_cooldown_timer", wait_time = high_jump_cooldown, callback = "_on_high_jump_cooldown_timeout"}
	]
	
	for config in timer_configs:
		var timer = Timer.new()
		if "wait_time" in config:
			timer.wait_time = config.wait_time
		timer.one_shot = true
		timer.timeout.connect(Callable(self, config.callback))
		add_child(timer)
		set(config.timer, timer)

func _physics_process(delta: float) -> void:
	handle_input()
	handle_movement(delta)
	# Update zipline friction VFX every frame to ensure proper state
	update_zipline_friction_vfx()

func handle_input():
	# Check if player is swinging on a vine OR on a zipline
	var is_on_vine = vine_component && vine_component.is_swinging
	var is_on_zipline_check = is_on_zipline
	
	# Zipline grab/release
	if Input.is_action_just_pressed("Jump") and zipline_in_range and not is_on_vine and not is_on_zipline_check:
		grab_zipline()
	elif Input.is_action_just_pressed("Jump") and is_on_zipline_check:
		release_zipline()
	
	# Dash - cannot be used while on vine OR zipline
	if Input.is_action_just_pressed("Dash") and can_dash and current_parry_stacks >= 1 and not is_on_vine and not is_on_zipline_check:
		activate_dash()
	
	# Regular jump - works normally when not on zipline
	if Input.is_action_just_pressed("Jump") and is_on_floor() and not is_on_zipline_check:
		velocity.y = JUMP_VELOCITY
	
	# High jump - cannot be used while on vine OR zipline
	if Input.is_action_just_pressed("HighJump") and is_on_floor() and can_high_jump and current_parry_stacks >= 2 and not is_on_vine and not is_on_zipline_check:
		activate_high_jump()
	
	# Parry - NOW WORKS ON ZIPLINE! Only blocked by vine swinging
	if Input.is_action_just_pressed("Parry") and can_parry and not is_on_vine:
		activate_parry()

# Add this to your handle_movement() function
func handle_movement(delta: float):
	if is_on_zipline:
		handle_zipline_movement(delta)
	elif is_dashing:
		handle_dash_movement(delta)
	elif is_bouncing:
		handle_bounce_movement(delta)
	else:
		handle_normal_movement(delta)

func handle_dash_movement(delta: float):
	# Set horizontal velocity for both regular and vine release dashes
	velocity.x = dash_direction.x * (dash_distance / dash_duration)
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var dash_elapsed = current_time - dash_start_time
	var dash_progress = dash_elapsed / dash_duration
	
	# Different vertical movement handling for vine release vs regular dash
	if is_vine_release_dash:
		# Vine release dash: Allow natural gravity throughout the dash
		if not is_on_floor():
			velocity += get_gravity() * delta
	else:
		# Regular dash: Lock Y velocity for first half, then allow gravity
		if dash_progress < 0.5:
			velocity.y = 0.0
		else:
			if not is_on_floor():
				velocity += get_gravity() * delta
	
	move_and_slide()
	
	if is_on_wall_only():
		handle_wall_bounce()
		return
	
	check_dash_ground_landing()

func handle_bounce_movement(delta: float):
	var current_time = Time.get_ticks_msec() / 1000.0
	var bounce_elapsed = current_time - bounce_start_time
	
	if bounce_elapsed >= bounce_duration:
		end_bounce()
	else:
		velocity.x = bounce_direction_vector.x * (bounce_distance / bounce_duration)
	
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	move_and_slide()

func handle_normal_movement(delta: float):
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	var direction := get_effective_horizontal_input()
	update_sprite_direction(direction)
	update_animations(direction)
	
	# Simple movement - no momentum system
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * 0.3)
	
	move_and_slide()

func get_effective_horizontal_input() -> float:
	if (vine_component and vine_component.is_swinging and vine_component.inputs_blocked) or is_on_zipline:
		return 0.0
	return Input.get_axis("Move_Left", "Move_Right")

func update_sprite_direction(direction: float):
	if direction > 0:
		animated_sprite.flip_h = false
		if glint_sprite:
			glint_sprite.position.x = abs(glint_sprite.position.x) * -1
		if zipline_friction:
			zipline_friction.flip_h = false
	elif direction < 0:
		animated_sprite.flip_h = true
		if glint_sprite:
			glint_sprite.position.x = abs(glint_sprite.position.x)
		if zipline_friction:
			zipline_friction.flip_h = true

func update_animations(direction: float):
	if not is_in_pre_freeze_parry and not is_dashing:
		if is_on_zipline:
			# Special handling for zipline animations
			if is_parrying or is_in_parry_freeze:
				animated_sprite.play("Parry")
			else:
				animated_sprite.play("Jump")  # Or create a specific zipline animation
		elif is_on_floor():
			animated_sprite.play("Idle" if direction == 0 else "Run")
		else:
			animated_sprite.play("Jump")

func update_zipline_friction_vfx():
	if not zipline_friction:
		return
		
	if is_on_zipline and current_zipline:
		# Show friction effect when on zipline
		zipline_friction.visible = true
		if not zipline_friction.is_playing():
			zipline_friction.play("default")
		
		# Update position based on player facing direction (like glint_sprite)
		if animated_sprite.flip_h:
			zipline_friction.position.x = abs(zipline_friction.position.x)
		else:
			zipline_friction.position.x = abs(zipline_friction.position.x) * -1
	else:
		# Hide friction effect when not on zipline
		if zipline_friction.visible:
			zipline_friction.visible = false
			zipline_friction.stop()

func spawn_air_puff():
	spawn_air_effect(air_puff_scene, Vector2(0, -6), false)

func spawn_air_puffV():
	spawn_air_effect(air_puffV_scene, Vector2(0, -6), true)

func spawn_air_effect(scene: PackedScene, offset: Vector2, is_vertical: bool):
	if not scene:
		return
		
	var air_puff = scene.instantiate()
	get_parent().add_child(air_puff)
	air_puff.global_position = global_position + offset
	
	if is_vertical:
		air_puff.rotation_degrees = -90
	elif air_puff.has_method("set_direction"):
		air_puff.set_direction(dash_direction)
	elif air_puff is AnimatedSprite2D:
		air_puff.flip_h = (dash_direction.x < 0)
	
	setup_air_puff_cleanup(air_puff)

func setup_air_puff_cleanup(air_puff):
	if air_puff is AnimatedSprite2D:
		air_puff.animation_finished.connect(func(): air_puff.queue_free())
		var cleanup_timer = Timer.new()
		cleanup_timer.wait_time = 2.0
		cleanup_timer.one_shot = true
		cleanup_timer.timeout.connect(func(): 
			if is_instance_valid(air_puff):
				air_puff.queue_free()
			cleanup_timer.queue_free()
		)
		air_puff.add_child(cleanup_timer)
		cleanup_timer.start()

# Parry system
func activate_parry():
	if not can_parry:
		return
	
	# Store the invulnerability state before parry
	was_invulnerable_before_parry = health_script.is_invulnerable
	
	is_parrying = true
	can_parry = false
	parry_was_successful = false
	health_script.is_invulnerable = true
	
	if glint_sprite:
		glint_sprite.visible = true
		glint_sprite.play("default")
	
	parry_timer.start()
	
	# Update animation if on zipline
	if is_on_zipline:
		animated_sprite.play("Parry")

func on_parry_success():
	parry_was_successful = true
	add_parry_stack()
	last_attack_was_unparryable = false
	is_parrying = false
	can_parry = true
	is_in_pre_freeze_parry = true
	parry_pre_freeze_timer.start()
	call_deferred("_play_parry_animation")

func _play_parry_animation():
	if is_in_pre_freeze_parry:
		animated_sprite.play("Parry")
		# Activate ParrySpark sprite when playing Parry animation
		if parry_spark:
			parry_spark.visible = true

# Movement abilities
func activate_dash():
	if not can_dash or is_dashing or current_parry_stacks < 1:
		return
	
	consume_parry_stack()
	dash_started_on_ground = is_on_floor()
	was_on_ground_before_dash = dash_started_on_ground
	dash_start_time = Time.get_ticks_msec() / 1000.0
	dash_direction = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
	is_dashing = true
	can_dash = false
	is_vine_release_dash = false  # Regular dashes are NOT vine release dashes
	
	spawn_air_puff()
	animated_sprite.play("Dash")
	dash_timer.start()
	dash_cooldown_timer.start()

func activate_high_jump():
	if not can_high_jump or current_parry_stacks < 2:
		return
	
	current_parry_stacks -= 2
	parry_stacks_changed.emit(current_parry_stacks)
	update_charge_sprites()
	velocity.y = HIGH_JUMP_VELOCITY
	can_high_jump = false
	high_jump_cooldown_timer.start()
	spawn_air_puffV()

func handle_wall_bounce():
	var original_dash_direction = dash_direction
	end_dash()
	velocity.y = wall_bounce_force.y
	velocity.x = 0.0
	bounce_direction_vector = Vector2.LEFT if original_dash_direction.x > 0 else Vector2.RIGHT
	bounce_timer.start()

func check_dash_ground_landing():
	if is_on_floor() and not dash_started_on_ground:
		end_dash()
	elif dash_started_on_ground and not was_on_ground_before_dash and is_on_floor():
		end_dash()
	was_on_ground_before_dash = is_on_floor()

func end_dash():
	if not is_dashing:
		return
	is_dashing = false
	dash_direction = Vector2.ZERO
	dash_start_time = 0.0
	is_vine_release_dash = false  # Reset vine release dash flag
	dash_timer.stop()

func end_bounce():
	is_bouncing = false
	bounce_direction_vector = Vector2.ZERO
	bounce_start_time = 0.0

# Charge system
func add_parry_stack():
	if current_parry_stacks < max_parry_stacks:
		current_parry_stacks += 1
		parry_stacks_changed.emit(current_parry_stacks)
		update_charge_sprites()

func consume_parry_stack():
	if current_parry_stacks > 0:
		current_parry_stacks -= 1
		parry_stacks_changed.emit(current_parry_stacks)
		update_charge_sprites()
		return true
	return false

func reset_parry_stacks():
	current_parry_stacks = 0
	parry_stacks_changed.emit(current_parry_stacks)
	update_charge_sprites()

func get_parry_stacks() -> int:
	return current_parry_stacks

func setup_charge_system():
	empty_charge_sprites = [empty_charge_sprite_1, empty_charge_sprite_2, empty_charge_sprite_3]
	charge_textures = [charge_texture_1, charge_texture_2, charge_texture_3, charge_texture_4]
	assigned_textures = [null, null, null]
	update_charge_sprites()

func update_charge_sprites():
	for i in range(empty_charge_sprites.size()):
		if empty_charge_sprites[i]:
			if i < current_parry_stacks:
				if assigned_textures[i] == null:
					assign_new_random_texture_to_sprite(i)
				else:
					empty_charge_sprites[i].texture = assigned_textures[i]
					empty_charge_sprites[i].modulate.a = 1.0
			else:
				assigned_textures[i] = null
				assign_empty_texture_to_sprite(i)
			empty_charge_sprites[i].visible = true

func get_currently_used_textures() -> Array[Texture2D]:
	var used_textures: Array[Texture2D] = []
	for i in range(current_parry_stacks):
		if assigned_textures[i] != null:
			used_textures.append(assigned_textures[i])
	return used_textures

func assign_new_random_texture_to_sprite(index: int):
	if index < empty_charge_sprites.size() and empty_charge_sprites[index]:
		var valid_textures = charge_textures.filter(func(texture): return texture != null)
		if valid_textures.size() > 0:
			var used_textures = get_currently_used_textures()
			var available_textures = valid_textures.filter(func(texture): return not texture in used_textures)
			
			if available_textures.size() == 0:
				available_textures = valid_textures
			
			var random_texture = available_textures[randi() % available_textures.size()]
			assigned_textures[index] = random_texture
			empty_charge_sprites[index].texture = random_texture
			empty_charge_sprites[index].modulate.a = 1.0

func assign_empty_texture_to_sprite(index: int):
	if index < empty_charge_sprites.size() and empty_charge_sprites[index]:
		if empty_charge_texture:
			empty_charge_sprites[index].texture = empty_charge_texture
			empty_charge_sprites[index].modulate.a = 1.0
		else:
			empty_charge_sprites[index].modulate.a = 0.3

# Timer callbacks
func _on_parry_timeout():
	# Hide parry visual effects
	if glint_sprite:
		glint_sprite.visible = false
		glint_sprite.stop()
	
	# Handle parry failure (including unparryables)
	if not parry_was_successful:
		is_parrying = false
		parry_cooldown_timer.wait_time = parry_fail_cooldown
		parry_cooldown_timer.start()
		
		# CRITICAL FIX: Only disable invulnerability if:
		# 1. Player wasn't already invulnerable before the parry AND
		# 2. This wasn't an unparryable attack (which should maintain iframes from damage)
		if not was_invulnerable_before_parry and not last_attack_was_unparryable:
			health_script.is_invulnerable = false
		# If it was unparryable, the damage system has already handled iframes appropriately
		# If player was already invulnerable, maintain that state
	else:
		# Successful parry - only disable invulnerability if player wasn't already invulnerable
		if not was_invulnerable_before_parry:
			health_script.is_invulnerable = false
		can_parry = true
	
	# Reset flags for next parry
	last_attack_was_unparryable = false
	was_invulnerable_before_parry = false

func _on_parry_cooldown_timeout():
	can_parry = true

func _on_parry_pre_freeze_timeout():
	is_in_pre_freeze_parry = false
	is_in_parry_freeze = true
	Engine.time_scale = 1
	# Hide ParrySpark sprite immediately when freeze begins
	if parry_spark:
		parry_spark.visible = false
	parry_freeze_timer.start()

func _on_parry_freeze_timeout():
	is_in_parry_freeze = false
	Engine.time_scale = 1.0
	# ParrySpark is already hidden from _on_parry_pre_freeze_timeout()

func _on_dash_timeout():
	end_dash()

func _on_dash_cooldown_timeout():
	can_dash = true

func _on_bounce_timeout():
	is_bouncing = true
	bounce_start_time = Time.get_ticks_msec() / 1000.0

func _on_high_jump_cooldown_timeout():
	can_high_jump = true

func set_last_attack_unparryable(unparryable: bool):
	last_attack_was_unparryable = unparryable
	
	# ADDITIONAL PROTECTION: If setting an attack as unparryable and player is currently parrying
	# while already being invulnerable, ensure they stay invulnerable
	if unparryable and is_parrying and was_invulnerable_before_parry:
		health_script.is_invulnerable = true

func _on_player_died():
	is_parrying = false
	is_dashing = false
	is_bouncing = false
	is_in_parry_freeze = false
	is_in_pre_freeze_parry = false
	is_vine_release_dash = false
	
	
	if is_on_zipline and current_zipline:
		current_zipline.release_player()
		is_on_zipline = false
		current_zipline = null
		zipline_in_range = null
	
	for timer in [parry_timer, parry_cooldown_timer, parry_freeze_timer, parry_pre_freeze_timer, dash_timer, dash_cooldown_timer, bounce_timer]:
		timer.stop()
	
	animated_sprite.modulate.a = 1.0
	bounce_direction_vector = Vector2.ZERO
	
	if glint_sprite:
		glint_sprite.visible = false
		glint_sprite.stop()
	
	if zipline_friction:
		zipline_friction.visible = false
		zipline_friction.stop()
	
	if parry_spark:
		parry_spark.visible = false
	
	reset_parry_stacks()
	Engine.time_scale = 0.2
	$CollisionShape2D.set_deferred("disabled", true)
	
	await get_tree().create_timer(1.0).timeout
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func grab_vine(vine: Vine):
	print("Player grab_vine method called")
	if vine.player_in_grab_area and has_node("VineComponent"):
		print("Player attempting to grab vine through VineComponent")
		$VineComponent.grab_vine(vine)

func handle_zipline_movement(delta: float):
	# Movement is handled by the zipline itself
	# Just update animations and VFX
	if current_zipline:
		var zipline_dir = current_zipline.get_zipline_direction_vector()
		update_sprite_direction(zipline_dir.x)
		# Animation is now handled in update_animations() function
		update_animations(0.0)  # Pass 0 since horizontal input is blocked on zipline
	move_and_slide()

func grab_zipline():
	if not zipline_in_range:
		return false
	
	if zipline_in_range.grab_player(self, zipline_grab_position):
		is_on_zipline = true
		current_zipline = zipline_in_range
		# Stop any current movement
		if is_dashing:
			end_dash()
		return true
	return false

func release_zipline():
	if not is_on_zipline or not current_zipline:
		return
	
	# Perform a dash-like release if player has charges
	if current_parry_stacks >= 1:
		# Get zipline direction and use it for a release dash
		var zipline_dir = current_zipline.get_zipline_direction_vector()
		
		# Release from zipline first
		current_zipline.release_player()
		is_on_zipline = false
		current_zipline = null
		# VFX will be updated in _physics_process via update_zipline_friction_vfx()
	else:
		# Simple release without dash
		current_zipline.release_player()
		is_on_zipline = false
		current_zipline = null
		# VFX will be updated in _physics_process via update_zipline_friction_vfx()

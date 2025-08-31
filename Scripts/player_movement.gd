extends CharacterBody2D

const SPEED = 150.0
const JUMP_VELOCITY = -200.0
const HIGH_JUMP_VELOCITY = -350.0

@onready var animated_sprite: AnimatedSprite2D = $MainSprite
@onready var glint_sprite: AnimatedSprite2D = $GlintSprite
@onready var health_script = $HealthScript
@onready var parry_label: Label = $Late_EarlyLabel

var flicker_timer: Timer
var is_flickering: bool = false
@export var flicker_interval: float = 0.1

var parry_timer: Timer
var parry_early_timer: Timer
var is_parrying: bool = false
@export var parry_duration: float = 0.4
@export var parry_success_cooldown: float = 0.0
@export var parry_fail_cooldown: float = 1.0
@export var parry_early_delay: float = 0.15
var parry_cooldown_timer: Timer
var can_parry: bool = true
var parry_was_successful: bool = false
var damage_timer: Timer
var recently_took_damage: bool = false
var parry_end_timer: Timer
var recently_parry_ended: bool = false
var early_text_timer: Timer
var showing_early_text: bool = false
var early_fade_timer: Timer
var is_fading_early_text: bool = false
@export var early_fade_duration: float = 0.5
var late_text_timer: Timer
var late_fade_timer: Timer
var is_fading_late_text: bool = false
var showing_late_text: bool = false
@export var late_fade_duration: float = 0.5

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

@export var dash_distance: float = 200.0
@export var dash_speed: float = 800.0
@export var dash_cooldown: float = 1.0
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
var pending_bounce_direction: float = 0.0
var is_bouncing: bool = false
var bounce_start_time: float = 0.0
var bounce_duration: float = 0.0
var bounce_direction_vector: Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("Dash") and can_dash and current_parry_stacks >= 2:
		activate_dash()
	
	if is_dashing:
		velocity.x = dash_direction.x * (dash_distance / dash_duration)
		
		var current_time = Time.get_ticks_msec() / 1000.0
		var dash_elapsed = current_time - dash_start_time
		var dash_progress = dash_elapsed / dash_duration
		
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
		return
	
	if is_bouncing:
		var current_time = Time.get_ticks_msec() / 1000.0
		var bounce_elapsed = current_time - bounce_start_time
		
		if bounce_elapsed >= bounce_duration:
			end_bounce()
		else:
			velocity.x = bounce_direction_vector.x * (bounce_distance / bounce_duration)
		
		if not is_on_floor():
			velocity += get_gravity() * delta
		
		move_and_slide()
		return
	
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	if Input.is_action_just_pressed("HighJump") and is_on_floor() and can_high_jump and current_parry_stacks >= 2:
		activate_high_jump()
	
	if Input.is_action_just_pressed("Parry") and can_parry:
		activate_parry()
	
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
	health_script.died.connect(_on_player_died)
	health_script.iframe_started.connect(_on_iframe_started)
	health_script.iframe_ended.connect(_on_iframe_ended)
	
	setup_charge_system()
	
	if glint_sprite:
		glint_sprite.visible = false
	
	if parry_label:
		if not showing_early_text and not showing_late_text:
			parry_label.visible = false
			parry_label.text = ""
	
	dash_duration = dash_distance / dash_speed
	bounce_duration = bounce_distance / bounce_speed
	
	flicker_timer = Timer.new()
	flicker_timer.wait_time = flicker_interval
	flicker_timer.timeout.connect(_on_flicker_timeout)
	add_child(flicker_timer)
	
	parry_timer = Timer.new()
	parry_timer.wait_time = parry_duration
	parry_timer.one_shot = true
	parry_timer.timeout.connect(_on_parry_timeout)
	add_child(parry_timer)
	
	parry_early_timer = Timer.new()
	parry_early_timer.wait_time = parry_early_delay
	parry_early_timer.one_shot = true
	parry_early_timer.timeout.connect(_on_parry_early_timeout)
	add_child(parry_early_timer)
	
	parry_cooldown_timer = Timer.new()
	parry_cooldown_timer.one_shot = true
	parry_cooldown_timer.timeout.connect(_on_parry_cooldown_timeout)
	add_child(parry_cooldown_timer)
	
	dash_timer = Timer.new()
	dash_timer.wait_time = dash_duration
	dash_timer.one_shot = true
	dash_timer.timeout.connect(_on_dash_timeout)
	add_child(dash_timer)
	
	dash_cooldown_timer = Timer.new()
	dash_cooldown_timer.wait_time = dash_cooldown
	dash_cooldown_timer.one_shot = true
	dash_cooldown_timer.timeout.connect(_on_dash_cooldown_timeout)
	add_child(dash_cooldown_timer)
	
	bounce_timer = Timer.new()
	bounce_timer.wait_time = bounce_delay
	bounce_timer.one_shot = true
	bounce_timer.timeout.connect(_on_bounce_timeout)
	add_child(bounce_timer)
	
	high_jump_cooldown_timer = Timer.new()
	high_jump_cooldown_timer.wait_time = high_jump_cooldown
	high_jump_cooldown_timer.one_shot = true
	high_jump_cooldown_timer.timeout.connect(_on_high_jump_cooldown_timeout)
	add_child(high_jump_cooldown_timer)
	
	damage_timer = Timer.new()
	damage_timer.wait_time = parry_early_delay
	damage_timer.one_shot = true
	damage_timer.timeout.connect(_on_damage_timer_timeout)
	add_child(damage_timer)
	
	parry_end_timer = Timer.new()
	parry_end_timer.wait_time = parry_early_delay
	parry_end_timer.one_shot = true
	parry_end_timer.timeout.connect(_on_parry_end_timer_timeout)
	add_child(parry_end_timer)
	
	early_text_timer = Timer.new()
	early_text_timer.wait_time = 1.0
	early_text_timer.one_shot = true
	early_text_timer.timeout.connect(_on_early_text_timeout)
	add_child(early_text_timer)
	
	early_fade_timer = Timer.new()
	early_fade_timer.wait_time = 0.02
	early_fade_timer.timeout.connect(_on_early_fade_tick)
	add_child(early_fade_timer)
	
	late_text_timer = Timer.new()
	late_text_timer.wait_time = 1.0
	late_text_timer.one_shot = true
	late_text_timer.timeout.connect(_on_late_text_timeout)
	add_child(late_text_timer)
	
	late_fade_timer = Timer.new()
	late_fade_timer.wait_time = 0.02
	late_fade_timer.timeout.connect(_on_late_fade_tick)
	add_child(late_fade_timer)

func activate_parry():
	if not can_parry:
		return
	
	is_parrying = true
	can_parry = false
	parry_was_successful = false
	
	health_script.is_invulnerable = true
	
	if glint_sprite:
		glint_sprite.visible = true
		glint_sprite.play("default")
	
	parry_timer.start()
	if recently_took_damage:
		parry_early_timer.start()
	health_script.iframe_started.emit()

func _on_parry_timeout():
	is_parrying = false
	health_script.is_invulnerable = false
	
	if glint_sprite:
		glint_sprite.visible = false
		glint_sprite.stop()
	

	
	if parry_early_timer.time_left > 0:
		parry_early_timer.stop()
	
	health_script.iframe_ended.emit()
	
	recently_parry_ended = true
	parry_end_timer.start()
	
	if parry_was_successful:
		can_parry = true
	else:
		parry_cooldown_timer.wait_time = parry_fail_cooldown
		parry_cooldown_timer.start()

func _on_parry_early_timeout():
	if is_parrying and not parry_was_successful and parry_label:
		parry_label.text = "Late!"
		parry_label.visible = true
		parry_label.modulate.a = 1.0
		showing_late_text = true
		is_fading_late_text = false
		late_text_timer.start()

func _on_parry_cooldown_timeout():
	can_parry = true

func _on_damage_timer_timeout():
	recently_took_damage = false

func _on_parry_end_timer_timeout():
	recently_parry_ended = false

func _on_early_text_timeout():
	if parry_label:
		is_fading_early_text = true
		early_fade_timer.start()

func _on_early_fade_tick():
	if parry_label and is_fading_early_text:
		parry_label.modulate.a -= (1.0 / early_fade_duration) * early_fade_timer.wait_time
		
		if parry_label.modulate.a <= 0.0:
			parry_label.visible = false
			parry_label.text = ""
			parry_label.modulate.a = 1.0
			showing_early_text = false
			is_fading_early_text = false
			early_fade_timer.stop()

func _on_late_text_timeout():
	if parry_label:
		is_fading_late_text = true
		late_fade_timer.start()

func _on_late_fade_tick():
	if parry_label and is_fading_late_text:
		parry_label.modulate.a -= (1.0 / late_fade_duration) * late_fade_timer.wait_time
		
		if parry_label.modulate.a <= 0.0:
			parry_label.visible = false
			parry_label.text = ""
			parry_label.modulate.a = 1.0
			is_fading_late_text = false
			showing_late_text = false
			late_fade_timer.stop()

func on_parry_success():
	parry_was_successful = true
	add_parry_stack()

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

func activate_dash():
	if not can_dash or is_dashing:
		return
	
	if current_parry_stacks < 2:
		return
	
	current_parry_stacks -= 2
	parry_stacks_changed.emit(current_parry_stacks)
	update_charge_sprites()
	
	dash_started_on_ground = is_on_floor()
	was_on_ground_before_dash = dash_started_on_ground
	dash_start_time = Time.get_ticks_msec() / 1000.0
	
	if animated_sprite.flip_h:
		dash_direction = Vector2.LEFT
	else:
		dash_direction = Vector2.RIGHT
	
	is_dashing = true
	can_dash = false
	
	dash_timer.start()
	dash_cooldown_timer.start()

func activate_high_jump():
	if not can_high_jump:
		return
	
	if current_parry_stacks < 2:
		return
	
	current_parry_stacks -= 2
	parry_stacks_changed.emit(current_parry_stacks)
	update_charge_sprites()
	
	velocity.y = HIGH_JUMP_VELOCITY
	
	can_high_jump = false
	high_jump_cooldown_timer.start()

func _on_high_jump_cooldown_timeout():
	can_high_jump = true

func handle_wall_bounce():
	var original_dash_direction = dash_direction
	end_dash()
	
	velocity.y = wall_bounce_force.y
	velocity.x = 0.0
	
	if original_dash_direction.x > 0:
		bounce_direction_vector = Vector2.LEFT
	else:
		bounce_direction_vector = Vector2.RIGHT
	
	bounce_timer.start()

func _on_bounce_timeout():
	is_bouncing = true
	bounce_start_time = Time.get_ticks_msec() / 1000.0

func end_bounce():
	is_bouncing = false
	bounce_direction_vector = Vector2.ZERO
	bounce_start_time = 0.0

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
	dash_timer.stop()

func _on_dash_timeout():
	end_dash()

func _on_dash_cooldown_timeout():
	can_dash = true

func _on_iframe_started():
	if recently_parry_ended and parry_label:
		parry_label.text = "Early!"
		parry_label.visible = true
		parry_label.modulate.a = 1.0
		showing_early_text = true
		is_fading_early_text = false
		early_text_timer.start()
		recently_parry_ended = false
		return
	
	if not is_parrying:
		recently_took_damage = true
		damage_timer.start()
		is_flickering = true
		flicker_timer.start()
	else:
		recently_took_damage = true
		damage_timer.start()

func _on_iframe_ended():
	if not is_parrying:
		is_flickering = false
		flicker_timer.stop()
		animated_sprite.modulate.a = 1.0

func _on_flicker_timeout():
	if is_flickering:
		if animated_sprite.modulate.a > 0.5:
			animated_sprite.modulate.a = 0.3
		else:
			animated_sprite.modulate.a = 1.0
		
		flicker_timer.start()

func _on_player_died():
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
	
	if glint_sprite:
		glint_sprite.visible = false
		glint_sprite.stop()
	
	reset_parry_stacks()
	
	Engine.time_scale = 0.2
	$CollisionShape2D.set_deferred("disabled", true)
	
	await get_tree().create_timer(1.0).timeout
	
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

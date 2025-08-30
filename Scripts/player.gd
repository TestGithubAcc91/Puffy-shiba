extends CharacterBody2D


const SPEED = 150.0
const JUMP_VELOCITY = -200.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
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
	# Connect to the health component's died signal
	$HealthScript.died.connect(_on_player_died)

func _on_player_died():
	print("Player died! Reloading scene...")
	# Add the same time scale effect as the original script
	Engine.time_scale = 0.2
	
	# Optional: disable player collision to prevent further interactions
	$CollisionShape2D.set_deferred("disabled", true)
	
	# Wait a moment before reloading (like the original timer)
	await get_tree().create_timer(1.0).timeout
	
	# Reset time scale and reload scene
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

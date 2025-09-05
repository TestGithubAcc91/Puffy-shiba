extends Node2D
@export var speed: float = 100.0
var moving_left: bool = false
var cleanup_timer: Timer
var is_disappearing: bool = false
var ray_cast_left: RayCast2D
var ray_cast_right: RayCast2D

func _ready():
	# Set up cleanup timer to prevent memory buildup
	cleanup_timer = Timer.new()
	cleanup_timer.wait_time = 5.0
	cleanup_timer.one_shot = true
	cleanup_timer.timeout.connect(_on_timeout)
	add_child(cleanup_timer)
	cleanup_timer.start()
	
	# Create raycasts for wall detection
	ray_cast_left = RayCast2D.new()
	ray_cast_left.target_position = Vector2(-2, 0)  # Cast 20 pixels to the left
	ray_cast_left.enabled = true
	add_child(ray_cast_left)
	
	ray_cast_right = RayCast2D.new()
	ray_cast_right.target_position = Vector2(2, 0)  # Cast 20 pixels to the right
	ray_cast_right.enabled = true
	add_child(ray_cast_right)
	
	# Connect collision detection for hitting players
	var area2d = get_area2d_node()
	if area2d:
		area2d.body_entered.connect(_on_body_entered)
		area2d.area_entered.connect(_on_area_entered)

func _process(delta):
	# Only move if not disappearing
	if not is_disappearing:
		# Wall collision detection (like your enemy script)
		if ray_cast_right.is_colliding() and not moving_left:

			start_disappear_sequence()
			return
		if ray_cast_left.is_colliding() and moving_left:

			start_disappear_sequence()
			return
		
		# Move the acorn based on direction
		if moving_left:
			position.x -= speed * delta
		else:
			position.x += speed * delta

func set_direction(facing_left: bool):
	moving_left = facing_left
	
	# Try to find and flip the sprite node
	var sprite = null
	
	# Check for common sprite node types
	if has_node("Sprite2D"):
		sprite = get_node("Sprite2D")
	elif has_node("AnimatedSprite2D"):
		sprite = get_node("AnimatedSprite2D")
	else:
		# Try to find any sprite child node
		for child in get_children():
			if child is Sprite2D or child is AnimatedSprite2D:
				sprite = child
				break
	
	# Flip the sprite if found
	if sprite:
		if sprite is Sprite2D or sprite is AnimatedSprite2D:
			sprite.flip_h = facing_left

func get_area2d_node() -> Area2D:
	# Find the Area2D node
	if has_node("Area2D"):
		return get_node("Area2D")
	else:
		for child in get_children():
			if child is Area2D:
				return child
	return null

func _on_body_entered(body: Node2D):
	# Check if it hit a player (has HealthScript component)
	var health_component = body.get_node("HealthScript") if body.has_node("HealthScript") else null
	if health_component and health_component is Health:

		start_disappear_sequence()
		return

func _on_area_entered(area: Area2D):
	# Additional collision detection for other Area2D nodes if needed
	print("Acorn hit area: ", area.name)

func start_disappear_sequence():
	# Prevent multiple calls
	if is_disappearing:
		return
	
	# Stop movement
	is_disappearing = true
	
	# Stop the cleanup timer since we're disappearing now
	if cleanup_timer and is_instance_valid(cleanup_timer):
		cleanup_timer.stop()
	
	# Deactivate Area2D to prevent damage during disappear animation
	var area2d = get_area2d_node()
	if area2d:
		area2d.set_deferred("monitoring", false)
		area2d.set_deferred("monitorable", false)
	
	# Find the animated sprite
	var animated_sprite = null
	
	if has_node("AnimatedSprite2D"):
		animated_sprite = get_node("AnimatedSprite2D")
	else:
		for child in get_children():
			if child is AnimatedSprite2D:
				animated_sprite = child
				break
	
	# Play disappear animation and delete after it finishes
	if animated_sprite:
		animated_sprite.play("Disappear")
		# Wait for the animation duration (5 frames at 9 fps = ~0.56 seconds)
		await get_tree().create_timer(5.0 / 9.0).timeout
		queue_free()
	else:
		queue_free()

func _on_timeout():
	start_disappear_sequence()

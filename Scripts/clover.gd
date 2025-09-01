extends Node2D

const SPEED = 60
var direction = 1
var player_detected = false
var detection_timer = 0.0
var is_spiked = false  # Add this flag to track spiked state

@onready var ray_cast_left: RayCast2D = $RayCastLeft
@onready var ray_cast_right: RayCast2D = $RayCastRight
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $KillzoneScript_Area

func _ready():
	# Connect the detection area signals
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)

func _process(delta: float):
	# Handle player detection timer
	if player_detected:
		detection_timer -= delta
		if detection_timer <= 0:
			player_detected = false
			is_spiked = false  # Reset spiked flag
			animated_sprite.play("Idle")  # Return to default animation
			
			# Make the damage area parryable again
			var damage_area = $KillzoneScript_Area  # Adjust path as needed
			if damage_area:
				damage_area.unparryable = false
			
			print("Returning to idle - attacks now parryable again")
	
	# Movement and collision detection
	if ray_cast_right.is_colliding():
		direction = -1
		animated_sprite.flip_h = true
	if ray_cast_left.is_colliding():
		direction = 1
		animated_sprite.flip_h = false
	
	position.x += SPEED * delta * direction

func _on_detection_area_body_entered(body: Node2D):
	var health_component = body.get_node("HealthScript") if body.has_node("HealthScript") else null
	if health_component:  # Only trigger if it's actually the player
		player_detected = true
		is_spiked = true  # Set spiked flag
		detection_timer = 2.0  # 2 seconds
		animated_sprite.play("Spiked")
		
		# Make the damage area unparryable when spiked
		var damage_area = $KillzoneScript_Area  # Adjust path as needed
		if damage_area:
			damage_area.unparryable = true
		
		print("Player detected! Playing Spiked animation - attacks now unparryable")

func _on_detection_area_body_exited(body: Node2D):
	# Optional: Handle when player leaves detection area
	if body.is_in_group("Player"):
		print("Player left detection area")

# Add a method to check if enemy is in spiked form
func is_in_spiked_form() -> bool:
	return is_spiked

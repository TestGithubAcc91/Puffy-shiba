extends Area2D

@export var damage_amount: int = 25
@export var ignore_iframes: bool = false  # Toggle this to bypass player i-frames

func _on_body_entered(body: Node2D):
	print("Body entered damage zone: ", body.name)
	
	# Check if the body has a health component
	var health_component = body.get_node("HealthScript") if body.has_node("HealthScript") else null
	
	if health_component and health_component is Health:
		print("Player with health component entered damage zone")
		# Deal damage once when entering
		deal_damage_to_player(body)
	else:
		print("Body has no HealthScript component or HealthScript component not found")

func deal_damage_to_player(player: Node2D):
	print("Attempting to deal damage to: ", player.name)
	var health_component = player.get_node("HealthScript") if player.has_node("HealthScript") else null
	if health_component and health_component is Health:
		print("Dealing ", damage_amount, " damage to player (ignore i-frames: ", ignore_iframes, ")")
		health_component.take_damage(damage_amount, ignore_iframes)
		
		# Optional: Add screen shake or hit effect
		Engine.time_scale = 0.8
		await get_tree().create_timer(0.1).timeout
		Engine.time_scale = 1.0
	else:
		print("Could not find valid HealthScript component on player")
		print("Available child nodes:")
		for child in player.get_children():
			print("  - ", child.name, " (", child.get_script(), ")")

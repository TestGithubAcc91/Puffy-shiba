extends Area2D
@export var damage_amount: int = 25
@export var ignore_iframes: bool = false  # Toggle this to bypass player i-frames

# Parry freeze effect settings
@export var parry_freeze_duration: float = 0.2  # How long to freeze on successful parry
@export var parry_freeze_time_scale: float = 0.0  # How slow time becomes (0.0 = complete freeze)

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
		# Check if player is currently parrying
		var is_player_parrying = false
		if "is_parrying" in player:
			is_player_parrying = player.is_parrying
		
		print("Dealing ", damage_amount, " damage to player (ignore i-frames: ", ignore_iframes, ", player parrying: ", is_player_parrying, ")")
		
		# Store the player's health before damage attempt
		var health_before = health_component.current_health
		
		# Attempt to deal damage
		health_component.take_damage(damage_amount, ignore_iframes)
		
		# Check if damage was actually dealt (health changed)
		var health_after = health_component.current_health
		var damage_was_dealt = health_before != health_after
		
		# If player was parrying and no damage was dealt, trigger freeze effect
		if is_player_parrying and not damage_was_dealt:
			print("Successful parry! Triggering freeze effect")
			# Notify the player that the parry was successful
			if player.has_method("on_parry_success"):
				player.on_parry_success()
			trigger_parry_freeze()
		elif damage_was_dealt:
			# Normal hit effect (your existing effect)
			Engine.time_scale = 0.8
			await get_tree().create_timer(0.1).timeout
			Engine.time_scale = 1.0
	else:
		print("Could not find valid HealthScript component on player")
		print("Available child nodes:")
		for child in player.get_children():
			print("  - ", child.name, " (", child.get_script(), ")")

func trigger_parry_freeze():
	print("Parry freeze activated!")
	
	# Completely freeze time
	Engine.time_scale = parry_freeze_time_scale
	
	# Use get_tree().create_timer() with process_always = true to work with time_scale = 0
	var freeze_timer = get_tree().create_timer(parry_freeze_duration, true, false, true)
	await freeze_timer.timeout
	
	# Restore normal time scale
	Engine.time_scale = 1.0
	print("Parry freeze ended")

extends Area2D
@export var damage_amount: int = 25
@export var ignore_iframes: bool = false  # Toggle this to bypass player i-frames
@export var unparryable: bool = false     # NEW: Toggle this to make attacks unparryable
# Parry freeze effect settings
@export var parry_freeze_duration: float = 0.2  # How long to freeze on successful parry
@export var parry_freeze_time_scale: float = 0.0  # How slow time becomes (0.0 = complete freeze)

# NEW: Global damage tracking system (shared across all killzones)
# Using a static variable so all instances share the same damage tracking
static var global_recently_damaged_players: Dictionary = {}
static var damage_cooldown_duration: float = 0.1  # Prevent multiple hits within 0.1 seconds

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
	
	# NEW: Check if this player was recently damaged (using global tracking)
	var current_time = Time.get_ticks_msec() / 1000.0
	var player_id = player.get_instance_id()
	
	if global_recently_damaged_players.has(player_id):
		var last_damage_time = global_recently_damaged_players[player_id]
		if current_time - last_damage_time < damage_cooldown_duration:
			print("Player recently damaged, skipping damage to prevent double hit")
			return
	
	var health_component = player.get_node("HealthScript") if player.has_node("HealthScript") else null
	
	if health_component and health_component is Health:
		# Check if player is currently parrying
		var is_player_parrying = false
		if "is_parrying" in player:
			is_player_parrying = player.is_parrying
		
		print("Dealing ", damage_amount, " damage to player (ignore i-frames: ", ignore_iframes, ", player parrying: ", is_player_parrying, ", unparryable: ", unparryable, ")")
		
		# CRITICAL FIX: Set the unparryable flag BEFORE any damage processing
		if player.has_method("set_last_attack_unparryable"):
			player.set_last_attack_unparryable(unparryable)
			print("Set unparryable flag to: ", unparryable)
		
		# Store the player's health before damage attempt
		var health_before = health_component.current_health
		
		# FIXED LOGIC: Only ignore iframes in specific circumstances
		var force_ignore_iframes = ignore_iframes
		# Only force through iframes if this is specifically an unparryable attack 
		# being parried (not just any unparryable attack)
		if unparryable and is_player_parrying:
			# Check if player was already invulnerable before parrying
			var was_invulnerable_before_parry = false
			if "was_invulnerable_before_parry" in player:
				was_invulnerable_before_parry = player.was_invulnerable_before_parry
			
			# Only ignore iframes if player wasn't already invulnerable
			if not was_invulnerable_before_parry:
				force_ignore_iframes = true
			# If player was already invulnerable, respect those iframes
		
		# Attempt to deal damage
		health_component.take_damage(damage_amount, force_ignore_iframes)
		
		# Check if damage was actually dealt (health changed)
		var health_after = health_component.current_health
		var damage_was_dealt = health_before != health_after
		
		# NEW: If damage was dealt, mark this player as recently damaged (using global tracking)
		if damage_was_dealt:
			global_recently_damaged_players[player_id] = current_time
			# Clean up old entries to prevent memory bloat
			cleanup_old_damage_entries(current_time)
			print("Damage dealt! Player marked as recently damaged at time: ", current_time)
		else:
			print("No damage dealt (player was invulnerable or parried successfully)")
		
		# Only trigger parry effects if the attack is parryable
		if is_player_parrying and not damage_was_dealt and not unparryable:
			print("Successful parry! Triggering freeze effect")
			# Notify the player that the parry was successful
			if player.has_method("on_parry_success"):
				player.on_parry_success()
			trigger_parry_freeze()
		elif damage_was_dealt:
			# Normal hit effect
			Engine.time_scale = 0.8
			await get_tree().create_timer(0.1).timeout
			Engine.time_scale = 1.0
	else:
		print("Could not find valid HealthScript component on player")

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

# NEW: Clean up old damage entries to prevent memory bloat (using global tracking)
func cleanup_old_damage_entries(current_time: float):
	var keys_to_remove = []
	for player_id in global_recently_damaged_players:
		var damage_time = global_recently_damaged_players[player_id]
		if current_time - damage_time > damage_cooldown_duration * 2:  # Keep for twice the cooldown duration
			keys_to_remove.append(player_id)
	
	for key in keys_to_remove:
		global_recently_damaged_players.erase(key)
	
	if keys_to_remove.size() > 0:
		print("Cleaned up ", keys_to_remove.size(), " old damage entries")

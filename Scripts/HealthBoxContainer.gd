extends HBoxContainer
class_name HealthBoxContainer

@export var hp_nodes: Array[TextureRect] = []  # Drag your HP1, HP2, HP3, HP4 nodes here
@export var health_per_segment: int = 25
@export var three_hearts_texture: Texture2D  # Texture to use when 3 hearts remain
@export var two_hearts_texture: Texture2D   # Texture to use when 2 hearts remain
@export var one_heart_texture: Texture2D    # Texture to use when 1 heart remains
@export var fading_heart_texture: Texture2D # Texture to use when a heart is fading out

var current_active_segments: int = 4
var original_textures: Array[Texture2D] = []  # Store original textures

func _ready():
	setup_health_segments()
	connect_to_health_system()

func setup_health_segments():
	if hp_nodes.is_empty():
		print("Warning: No HP nodes assigned in inspector!")
		return
	
	# Store original textures
	original_textures.clear()
	for hp_node in hp_nodes:
		if hp_node:
			original_textures.append(hp_node.texture)
		else:
			original_textures.append(null)
	
	# Ensure all HP nodes are children of this container
	for i in range(hp_nodes.size()):
		var hp_node = hp_nodes[i]
		if hp_node and hp_node.get_parent() != self:
			# If the node isn't already a child, reparent it
			if hp_node.get_parent():
				hp_node.get_parent().remove_child(hp_node)
			add_child(hp_node)
		
		# Configure TextureRect to prevent squishing (optional)
		if hp_node:
			hp_node.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			hp_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			hp_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hp_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	


func connect_to_health_system():

	
	# Try multiple methods to find the player
	var player = null
	
	# Method 1: Try finding by group
	player = get_tree().get_first_node_in_group("player")

	
	# Method 2: Try finding by name
	if not player:
		player = get_tree().get_first_node_in_group("Player")  # Try with capital P

	
	# Method 3: Try finding by node name "Player" anywhere in the scene tree
	if not player:
		player = get_tree().current_scene.find_child("Player", true, false)

	
	# Method 4: Try relative path to Game, then find Player child
	if not player:
		var game_node = get_node("../../")  # This should be your Game node

		if game_node and game_node.has_node("Player"):
			player = game_node.get_node("Player")

	
	# Method 5: Search through all nodes for one with HealthScript
	if not player:

		var all_nodes = get_tree().current_scene.find_children("*", "", true, false)
		for node in all_nodes:

			if node.has_node("HealthScript"):
				player = node

				break
	

	
	if player:

		for child in player.get_children():
			print("  - ", child.name, " (", child.get_script(), ")")
		
		if player.has_node("HealthScript"):
			var health_script = player.get_node("HealthScript")

			
			if health_script.has_signal("health_changed"):
				# Check if already connected
				if not health_script.health_changed.is_connected(_on_health_changed):
					health_script.health_changed.connect(_on_health_changed)

					
					# Initialize display with current health
					if health_script.has_method("get") or "current_health" in health_script:
						var current_hp = health_script.current_health

						update_health_display(current_hp)
				else:
					print("✓ Already connected to health_changed signal")
			else:
				print("✗ HealthScript doesn't have health_changed signal")
		else:
			print("✗ Player doesn't have HealthScript node")
	else:
		print("✗ Could not find player node")
	


func _on_health_changed(new_health: int):

	update_health_display(new_health)


func update_health_display(current_health: int):

	
	if hp_nodes.is_empty():
		print("✗ No HP nodes assigned!")
		return
	
	# Calculate how many segments should be active
	var segments_needed = ceili(float(current_health) / float(health_per_segment))
	segments_needed = max(0, min(segments_needed, hp_nodes.size()))
	

	
	# Determine which texture to use based on segments remaining
	var texture_to_use = get_texture_for_segments(segments_needed)

	
	# Update segment visibility and textures
	for i in range(hp_nodes.size()):
		var segment = hp_nodes[i]
		if not segment:

			continue
			
		var should_be_active = i < segments_needed
		
		
		# Update texture for ALL segments, not just active ones
		# This ensures invisible hearts also get the right texture for when they become visible again
		update_segment_texture(segment, i, texture_to_use)
		
		# Instead of changing visibility, change modulate (transparency)
		var should_be_visible = should_be_active
		var is_currently_visible = segment.modulate.a > 0.5  # Consider visible if alpha > 0.5
		
		if should_be_visible != is_currently_visible:

			
			if should_be_visible:
				# Show the heart
				animate_segment_gain(segment, i)
			else:
				# Hide the heart (this will use the fading texture)
				animate_segment_loss(segment, i)
		else:
			print("No change needed for segment ", i)
	
	current_active_segments = segments_needed


var last_special_texture: Texture2D = null  # Track the last special texture used

func get_texture_for_segments(segments: int) -> Texture2D:
	"""Determine which texture to use based on remaining segments"""
	var texture_to_use: Texture2D = null
	
	match segments:
		0:
			# When no hearts remain, keep the last special texture used
			return last_special_texture
		1:
			texture_to_use = one_heart_texture if one_heart_texture else null
		2:
			texture_to_use = two_hearts_texture if two_hearts_texture else null
		3:
			texture_to_use = three_hearts_texture if three_hearts_texture else null
		_:
			# 4+ hearts - use original texture and clear last special texture
			last_special_texture = null
			return null
	
	# Store the special texture we're using (for 1-3 hearts)
	if texture_to_use:
		last_special_texture = texture_to_use
	
	return texture_to_use

func update_segment_texture(segment: TextureRect, index: int, special_texture: Texture2D):
	"""Update the texture of a segment based on health state"""
	if not segment:
		return
		
	if special_texture:
		# Switch to special health texture
		if segment.texture != special_texture:
			segment.texture = special_texture
			print("Switched segment ", index, " to special texture")
	else:
		# Use original texture
		if index < original_textures.size() and original_textures[index]:
			if segment.texture != original_textures[index]:
				segment.texture = original_textures[index]
				print("Switched segment ", index, " to original texture")

func animate_segment_loss(segment: TextureRect, segment_index: int):
	# FIXED: Use fading heart texture during the fade animation
	if fading_heart_texture:
		segment.texture = fading_heart_texture
		print("Applied fading texture to segment ", segment_index)
	
	# Make the heart transparent
	var tween = create_tween()
	tween.tween_property(segment, "modulate:a", 0.0, 0.3)
	
	# Optional: Restore original texture after fade completes (if you want)
	# tween.tween_callback(func(): restore_original_texture(segment, segment_index))

func animate_segment_gain(segment: TextureRect, segment_index: int):
	# Make the heart fully opaque
	var tween = create_tween()
	tween.tween_property(segment, "modulate:a", 1.0, 0.3)

func restore_original_texture(segment: TextureRect, segment_index: int):
	"""Restore the original texture after fade animation (optional)"""
	if segment_index < original_textures.size() and original_textures[segment_index]:
		segment.texture = original_textures[segment_index]
		print("Restored original texture to segment ", segment_index)

# Public function to manually set health (useful for testing)
func set_health_display(health: int):
	update_health_display(health)

# Public function to get current active segments
func get_active_segments() -> int:
	return current_active_segments

# Public function to get max segments based on assigned nodes
func get_max_segments() -> int:
	return hp_nodes.size()

# Public function to manually set textures for different heart states
func set_three_hearts_texture(texture: Texture2D):
	three_hearts_texture = texture
	refresh_display()

func set_two_hearts_texture(texture: Texture2D):
	two_hearts_texture = texture
	refresh_display()

func set_one_heart_texture(texture: Texture2D):
	one_heart_texture = texture
	refresh_display()

func set_fading_heart_texture(texture: Texture2D):
	fading_heart_texture = texture

func refresh_display():
	"""Refresh display with current health if available"""
	if current_active_segments > 0:
		update_health_display(current_active_segments * health_per_segment)

# Alternative: Direct connection method - call this from your game setup
func connect_to_player_directly(player_node: Node2D):
	print("=== Direct connection attempt ===")
	print("Player node: ", player_node)
	
	if player_node and player_node.has_node("HealthScript"):
		var health_script = player_node.get_node("HealthScript")
		print("HealthScript found: ", health_script)
		
		if health_script.has_signal("health_changed"):
			if not health_script.health_changed.is_connected(_on_health_changed):
				health_script.health_changed.connect(_on_health_changed)
				print("✓ Successfully connected directly")
				
				# Initialize with current health
				var current_hp = health_script.current_health
				print("Initial health: ", current_hp)
				update_health_display(current_hp)
			else:
				print("✓ Already connected")
		else:
			print("✗ No health_changed signal")
	else:
		print("✗ No HealthScript found")

# Utility function to validate HP nodes in editor
func _validate_hp_nodes() -> bool:
	for i in range(hp_nodes.size()):
		if not hp_nodes[i]:
			print("HP node at index ", i, " is null!")
			return false
		if not hp_nodes[i] is TextureRect:
			print("HP node at index ", i, " is not a TextureRect!")
			return false
	return true

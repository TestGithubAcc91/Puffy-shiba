extends HBoxContainer
class_name HealthBoxContainer

@export var hp_nodes: Array[TextureRect] = []  # Drag your HP1, HP2, HP3, HP4 nodes here
@export var health_per_segment: int = 25

var current_active_segments: int = 4

func _ready():
	setup_health_segments()
	connect_to_health_system()

func setup_health_segments():
	if hp_nodes.is_empty():
		print("Warning: No HP nodes assigned in inspector!")
		return
	
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
	
	print("Setup ", hp_nodes.size(), " HP segments")

func connect_to_health_system():
	print("=== Attempting to connect to health system ===")
	
	# Try multiple methods to find the player
	var player = null
	
	# Method 1: Try finding by group
	player = get_tree().get_first_node_in_group("player")
	print("Method 1 - Player by group: ", player)
	
	# Method 2: Try finding by name
	if not player:
		player = get_tree().get_first_node_in_group("Player")  # Try with capital P
		print("Method 2 - Player by group (capital): ", player)
	
	# Method 3: Try finding by node name "Player" anywhere in the scene tree
	if not player:
		player = get_tree().current_scene.find_child("Player", true, false)
		print("Method 3 - Player by name search: ", player)
	
	# Method 4: Try relative path to Game, then find Player child
	if not player:
		var game_node = get_node("../../")  # This should be your Game node
		print("Method 4 - Game node: ", game_node)
		if game_node and game_node.has_node("Player"):
			player = game_node.get_node("Player")
			print("Method 4 - Player from Game: ", player)
	
	# Method 5: Search through all nodes for one with HealthScript
	if not player:
		print("Method 5 - Searching all nodes for HealthScript:")
		var all_nodes = get_tree().current_scene.find_children("*", "", true, false)
		for node in all_nodes:
			print("  Checking: ", node.name, " (", node.get_script(), ")")
			if node.has_node("HealthScript"):
				player = node
				print("    ^ Found player with HealthScript: ", player)
				break
	
	print("Final player found: ", player)
	
	if player:
		print("Player children:")
		for child in player.get_children():
			print("  - ", child.name, " (", child.get_script(), ")")
		
		if player.has_node("HealthScript"):
			var health_script = player.get_node("HealthScript")
			print("HealthScript found: ", health_script)
			print("HealthScript class: ", health_script.get_script())
			print("Available signals: ", health_script.get_signal_list())
			
			if health_script.has_signal("health_changed"):
				# Check if already connected
				if not health_script.health_changed.is_connected(_on_health_changed):
					health_script.health_changed.connect(_on_health_changed)
					print("✓ Successfully connected to health_changed signal")
					
					# Initialize display with current health
					if health_script.has_method("get") or "current_health" in health_script:
						var current_hp = health_script.current_health
						print("Initial health: ", current_hp)
						update_health_display(current_hp)
				else:
					print("✓ Already connected to health_changed signal")
			else:
				print("✗ HealthScript doesn't have health_changed signal")
		else:
			print("✗ Player doesn't have HealthScript node")
	else:
		print("✗ Could not find player node")
	
	print("=== Connection attempt complete ===")

func _on_health_changed(new_health: int):
	print("=== Health changed signal received ===")
	print("New health: ", new_health)
	print("Health per segment: ", health_per_segment)
	update_health_display(new_health)
	print("=== Health display updated ===")

func update_health_display(current_health: int):
	print("=== Updating health display ===")
	print("Current health: ", current_health)
	print("HP nodes count: ", hp_nodes.size())
	
	if hp_nodes.is_empty():
		print("✗ No HP nodes assigned!")
		return
	
	# Calculate how many segments should be active
	var segments_needed = ceili(float(current_health) / float(health_per_segment))
	segments_needed = max(0, min(segments_needed, hp_nodes.size()))
	
	print("Segments needed: ", segments_needed, " | Current active: ", current_active_segments)
	
	# Update segment visibility
	for i in range(hp_nodes.size()):
		var segment = hp_nodes[i]
		if not segment:
			print("✗ HP node at index ", i, " is null!")
			continue
			
		var should_be_active = i < segments_needed
		print("Segment ", i, " should be active: ", should_be_active, " | current alpha: ", segment.modulate.a)
		
		# Instead of changing visibility, change modulate (transparency)
		var should_be_visible = should_be_active
		var is_currently_visible = segment.modulate.a > 0.5  # Consider visible if alpha > 0.5
		
		if should_be_visible != is_currently_visible:
			print("Changing segment ", i, " visibility to: ", should_be_visible)
			
			if should_be_visible:
				# Show the heart
				animate_segment_gain(segment)
			else:
				# Hide the heart
				animate_segment_loss(segment)
		else:
			print("No change needed for segment ", i)
	
	current_active_segments = segments_needed
	print("=== Health display update complete ===")

func animate_segment_loss(segment: TextureRect):
	# Make the heart transparent instead of invisible
	var tween = create_tween()
	tween.tween_property(segment, "modulate:a", 0.0, 0.3)

func animate_segment_gain(segment: TextureRect):
	# Make the heart fully opaque
	var tween = create_tween()
	tween.tween_property(segment, "modulate:a", 1.0, 0.3)

# Public function to manually set health (useful for testing)
func set_health_display(health: int):
	update_health_display(health)

# Public function to get current active segments
func get_active_segments() -> int:
	return current_active_segments

# Public function to get max segments based on assigned nodes
func get_max_segments() -> int:
	return hp_nodes.size()

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

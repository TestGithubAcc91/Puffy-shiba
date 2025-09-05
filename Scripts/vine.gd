# Vine.gd - Version with sprite-based vine visuals
extends Sprite2D
class_name Vine

@export var vine_length: float = 200.0: set = set_vine_length
@export var swing_force: float = 500.0
@export var grab_range: float = 15.0  # This is the radius of the blue circle (grab area)
@export var debug_enabled: bool = true

# Vine visual properties
@export_group("Vine Visuals")
@export var vine_segment_texture: Texture2D  # 16x16 texture for vine segments
@export var vine_segments_per_16_pixels: int = 1  # How many segments per 16 pixels of length
@export var vine_segment_spacing: float = 16.0  # Distance between segment centers

# Detection area that moves with the vine bottom
var detection_area: Area2D
var grab_indicator: Sprite2D
var debug_label: Label
var player: CharacterBody2D = null
var is_player_grabbing: bool = false
var vine_anchor: Vector2
var current_vine_bottom: Vector2  # Current position of the vine bottom (blue circle)
var player_in_grab_area: bool = false

# Vine segment sprites
var vine_segment_sprites: Array[Sprite2D] = []

func _ready():
	vine_anchor = global_position
	# Initially, vine hangs straight down
	current_vine_bottom = vine_anchor + Vector2(0, vine_length)
	
	create_detection_area()
	create_grab_indicator()
	if debug_enabled:
		create_debug_label()
	
	# Create vine segment sprites
	create_vine_segments()

func set_vine_length(new_length: float):
	vine_length = new_length
	
	# Update current vine bottom position
	if not is_player_grabbing:
		current_vine_bottom = vine_anchor + Vector2(0, vine_length)
	
	# Update detection area position if it exists
	if detection_area and not is_player_grabbing:
		detection_area.position = Vector2(0, vine_length)
	
	# Update grab indicator position if it exists
	if grab_indicator and not is_player_grabbing:
		grab_indicator.position = Vector2(0, vine_length)
	
	# Update debug label position if it exists
	if debug_label:
		debug_label.position = Vector2(-50, vine_length + 40)
	
	# Recreate vine segments with new length
	create_vine_segments()
	
	# Force a redraw to update the green circle
	queue_redraw()
	
	print("Vine length changed to: ", vine_length)

func create_vine_segments():
	# Clear existing segments
	for segment in vine_segment_sprites:
		segment.queue_free()
	vine_segment_sprites.clear()
	
	if not vine_segment_texture:
		print("No vine segment texture assigned - creating default")
		# Create a default 16x16 vine segment texture if none is provided
		vine_segment_texture = create_default_vine_texture()
	
	# Calculate how many segments we need
	var num_segments = max(1, int(vine_length / vine_segment_spacing))
	
	print("Creating ", num_segments, " vine segments for length ", vine_length)
	
	# Create segment sprites
	for i in range(num_segments):
		var segment = Sprite2D.new()
		segment.texture = vine_segment_texture
		
		# Position segment along the vine path
		var segment_progress = float(i) / float(num_segments - 1) if num_segments > 1 else 0.0
		var segment_y = segment_progress * vine_length
		segment.position = Vector2(0, segment_y)
		
		# Add some variety to segments (optional)
		if i % 3 == 1:
			segment.modulate = Color(0.9, 0.8, 0.6)  # Slightly different color
		elif i % 3 == 2:
			segment.rotation = deg_to_rad(5)  # Slight rotation
		
		add_child(segment)
		vine_segment_sprites.append(segment)

func create_default_vine_texture() -> Texture2D:
	# Create a 16x16 default vine segment texture
	var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	
	# Fill with transparent background
	image.fill(Color.TRANSPARENT)
	
	# Draw a simple vine pattern
	# Central stem (4 pixels wide as requested)
	for y in range(16):
		for x in range(6, 10):  # 4 pixels wide, centered
			var color = Color(0.4, 0.2, 0.1)  # Brown color
			# Add some texture variation
			if x == 6 or x == 9:
				color = color.darkened(0.2)  # Darker edges
			if y % 4 == 0:
				color = color.lightened(0.1)  # Lighter rings
			image.set_pixel(x, y, color)
	
	# Add small leaves/texture details
	# Left leaf
	if randf() > 0.7:  # 30% chance for variety
		image.set_pixel(4, 4, Color(0.2, 0.6, 0.1))
		image.set_pixel(5, 5, Color(0.2, 0.6, 0.1))
	
	# Right leaf
	if randf() > 0.7:  # 30% chance for variety
		image.set_pixel(11, 8, Color(0.2, 0.6, 0.1))
		image.set_pixel(10, 9, Color(0.2, 0.6, 0.1))
	
	return ImageTexture.create_from_image(image)

func update_vine_segments_for_swinging():
	if not is_player_grabbing or not player:
		# Vine hangs straight down
		for i in range(vine_segment_sprites.size()):
			var segment = vine_segment_sprites[i]
			var segment_progress = float(i) / float(vine_segment_sprites.size() - 1) if vine_segment_sprites.size() > 1 else 0.0
			var segment_y = segment_progress * vine_length
			segment.position = Vector2(0, segment_y)
			segment.rotation = 0  # No rotation when hanging straight
		return
	
	# When swinging, curve the vine segments toward the player
	var to_player = player.global_position - vine_anchor
	var vine_direction = to_player.normalized()
	var actual_distance = to_player.length()
	
	for i in range(vine_segment_sprites.size()):
		var segment = vine_segment_sprites[i]
		var segment_progress = float(i) / float(vine_segment_sprites.size() - 1) if vine_segment_sprites.size() > 1 else 0.0
		
		# Create a curved vine by interpolating between hanging down and pointing toward player
		var straight_pos = Vector2(0, segment_progress * vine_length)
		var curved_pos = vine_direction * (segment_progress * actual_distance)
		
		# Blend between straight and curved based on how far we are along the vine
		var curve_strength = segment_progress * 0.8  # Stronger curve toward the end
		segment.position = straight_pos.lerp(curved_pos, curve_strength)
		
		# Rotate segments to follow the vine direction
		if i < vine_segment_sprites.size() - 1:
			var next_progress = float(i + 1) / float(vine_segment_sprites.size() - 1)
			var next_straight_pos = Vector2(0, next_progress * vine_length)
			var next_curved_pos = vine_direction * (next_progress * actual_distance)
			var next_pos = next_straight_pos.lerp(next_curved_pos, next_progress * 0.8)
			
			var segment_direction = (next_pos - segment.position).normalized()
			segment.rotation = atan2(segment_direction.x, -segment_direction.y)

func create_detection_area():
	# Create detection area as a circle that will move with the vine bottom
	detection_area = Area2D.new()
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = grab_range
	collision_shape.shape = shape
	
	# Position at the current vine bottom
	detection_area.position = Vector2(0, vine_length)
	
	# Set up Area2D properties
	detection_area.monitoring = true
	detection_area.monitorable = false
	
	# Set collision mask to layer 2 (where the player is)
	detection_area.collision_mask = 2
	detection_area.collision_layer = 0
	
	detection_area.add_child(collision_shape)
	add_child(detection_area)
	
	# Connect signals
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	
	print("Detection area created with radius: ", grab_range)

func create_grab_indicator():
	grab_indicator = Sprite2D.new()
	add_child(grab_indicator)
	
	# Create a circular indicator texture
	var image = Image.create(int(grab_range * 2), int(grab_range * 2), false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 1.0, 0.0, 0.5))  # Semi-transparent green circle
	grab_indicator.texture = ImageTexture.create_from_image(image)
	
	# Position at the vine bottom
	grab_indicator.position = Vector2(0, vine_length)
	grab_indicator.modulate = Color(1.0, 1.0, 1.0, 0.5)
	grab_indicator.visible = false

func create_debug_label():
	debug_label = Label.new()
	add_child(debug_label)
	debug_label.position = Vector2(-50, vine_length + 40)
	debug_label.size = Vector2(100, 60)
	debug_label.text = "Debug Info"
	debug_label.add_theme_color_override("font_color", Color.WHITE)
	debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	debug_label.add_theme_constant_override("shadow_offset_x", 1)
	debug_label.add_theme_constant_override("shadow_offset_y", 1)

func _process(delta):
	# Update vine bottom position based on player position when swinging
	if is_player_grabbing and player:
		current_vine_bottom = player.global_position
		# Move detection area to follow the player (the current vine bottom)
		detection_area.position = player.global_position - global_position
		grab_indicator.position = player.global_position - global_position
	else:
		# When not swinging, vine hangs straight down
		current_vine_bottom = vine_anchor + Vector2(0, vine_length)
		detection_area.position = Vector2(0, vine_length)
		grab_indicator.position = Vector2(0, vine_length)
	
	# Update vine segment positions for swinging animation
	update_vine_segments_for_swinging()
	
	if debug_enabled and debug_label:
		update_debug_info()
	queue_redraw()

func update_debug_info():
	if not debug_label:
		return
	
	var debug_text = ""
	debug_text += "GREEN ORBIT: " + str(int(vine_length)) + "px\n"
	debug_text += "BLUE HITBOX: " + str(int(grab_range)) + "px\n"
	debug_text += "SEGMENTS: " + str(vine_segment_sprites.size()) + "\n"
	debug_text += "In Grab Area: " + str(player_in_grab_area) + "\n"
	debug_text += "Is Grabbing: " + str(is_player_grabbing) + "\n"
	
	if player:
		var distance_from_anchor = vine_anchor.distance_to(player.global_position)
		var distance_from_blue_circle = current_vine_bottom.distance_to(player.global_position)
		debug_text += "Player->Anchor: " + str(int(distance_from_anchor)) + "px\n"
		debug_text += "Player->BlueCircle: " + str(int(distance_from_blue_circle)) + "px\n"
		debug_text += "Player Pos: " + str(Vector2i(player.global_position))
	else:
		debug_text += "No Player\n"
	
	debug_label.text = debug_text

func _draw():
	# Draw debug information (the sprites handle the visual vine now)
	if debug_enabled:
		# Draw vine anchor point (red circle)
		draw_circle(Vector2.ZERO, 8, Color.RED)
		
		# Draw the GREEN PATH GIZMO - the full swing arc that represents where player swings
		var arc_color = Color.GREEN
		arc_color.a = 0.4
		draw_arc(Vector2.ZERO, vine_length, 0, TAU, 64, arc_color, 3.0)
		
		# Draw the BLUE CIRCLE GIZMO - current position of the grab area (detection area)
		var blue_circle_position = detection_area.position
		draw_circle(blue_circle_position, grab_range, Color.BLUE)
		
		# Highlight when player is in grab area
		if player_in_grab_area:
			draw_circle(blue_circle_position, grab_range + 3, Color.CYAN)
		
		# Draw a small dot at the exact center of the blue circle for precision
		draw_circle(blue_circle_position, 2, Color.WHITE)

func _on_body_entered(body):
	print("Body entered vine grab area: ", body.name)
	
	if body.has_method("grab_vine"):
		player = body
		player_in_grab_area = true
		
		# Notify the player's VineComponent about nearby vine
		if body.has_node("VineComponent"):
			body.get_node("VineComponent").set_nearby_vine(self)
		
		# Show grab indicator when player is in range
		if grab_indicator:
			grab_indicator.visible = true
		
		print("Player is now in grab area (blue circle)")

func _on_body_exited(body):
	print("Body exited vine grab area: ", body.name)
	
	if body.has_method("grab_vine"):
		if player == body:
			# Notify the player's VineComponent that vine is no longer nearby
			if body.has_node("VineComponent"):
				body.get_node("VineComponent").clear_nearby_vine(self)
			player = null
		player_in_grab_area = false
		
		# Hide grab indicator when player leaves range
		if grab_indicator:
			grab_indicator.visible = false
		
		print("Player left grab area")

func attach_player(p: CharacterBody2D):
	player = p
	is_player_grabbing = true
	print("Player attached to vine. Will swing on green path at distance: ", vine_length)
	queue_redraw()

func release_player():
	print("Player released from vine")
	player = null
	is_player_grabbing = false
	queue_redraw()

func get_swing_direction_to_player() -> Vector2:
	if not player:
		return Vector2.ZERO
	
	var direction = player.global_position - vine_anchor
	return direction.normalized()

func get_distance_to_player() -> float:
	if not player:
		return 0.0
	
	return vine_anchor.distance_to(player.global_position)

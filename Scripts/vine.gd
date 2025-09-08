# Vine.gd - Version with horizontal approach tracking only
extends AnimatedSprite2D
class_name Vine

@export var vine_length: float = 200.0: set = set_vine_length
@export var swing_force: float = 500.0
@export var grab_range: float = 15.0  # This is the radius of the blue circle (grab area)
@export var debug_enabled: bool = true

# Vine visual properties
@export_group("Vine Visuals")
@export var vine_segment_animation: String = "default"  # Animation name for vine segments
@export var vine_segments_per_16_pixels: int = 1  # How many segments per 16 pixels of length
@export var vine_segment_spacing: float = 16.0  # Distance between segment centers
@export var vine_holder_animation: String = "default"  # Animation for the vine holder (this node)
@export var segment_animation_speed: float = 1.0  # Speed multiplier for segment animations
@export var randomize_segment_frame_offset: bool = true  # Randomize starting frame for variety
@export var remove_end_segments: int = 0: set = set_remove_end_segments  # Number of segments to remove from the end

# End sprite properties
@export_group("End Sprite")
@export var end_sprite_texture: Texture2D  # Texture for the sprite at the end of the vine
@export var end_sprite_scale: Vector2 = Vector2(1.0, 1.0)  # Scale of the end sprite
@export var end_sprite_offset: Vector2 = Vector2.ZERO  # Offset from the vine end position
@export var end_sprite_modulate: Color = Color.WHITE  # Color tint for the end sprite
@export var end_sprite_rotation_degrees: float = 0.0  # Rotation of the end sprite in degrees

# MODIFIED: Horizontal approach tracking properties
@export_group("Horizontal Approach Tracking")
@export var approach_detection_radius: float = 100.0  # Radius of the approach detection area around vine origin
@export var approach_speed_threshold: float = 20.0  # Minimum horizontal speed towards vine to count as "approaching"
@export var approach_angle_tolerance_degrees: float = 60.0  # INCREASED: More forgiving angle for horizontal approach (±60° from direct horizontal line to vine)

# Detection area that moves with the vine bottom
var detection_area: Area2D
var approach_detection_area: Area2D  # Area2D for tracking approach to vine origin
var grab_indicator: Sprite2D
var approach_indicator: Sprite2D  # Visual indicator for approach area
var debug_label: Label
var player: CharacterBody2D = null
var is_player_grabbing: bool = false
var vine_anchor: Vector2
var current_vine_bottom: Vector2  # Current position of the vine bottom (blue circle)
var player_in_grab_area: bool = false

# MODIFIED: Horizontal approach tracking variables
var player_in_approach_area: bool = false
var time_moving_horizontally_towards_vine: float = 0.0  # RENAMED: Now specifically tracks horizontal movement
var last_player_position: Vector2 = Vector2.ZERO
var approach_angle_tolerance_radians: float

# Vine segment animated sprites
var vine_segment_sprites: Array[AnimatedSprite2D] = []
var end_sprite: Sprite2D  # The sprite at the end of the vine

func _ready():
	vine_anchor = global_position
	# Initially, vine hangs straight down
	current_vine_bottom = vine_anchor + Vector2(0, vine_length)
	approach_angle_tolerance_radians = deg_to_rad(approach_angle_tolerance_degrees)
	
	# Set up the vine holder animation (this node)
	setup_vine_holder_animation()
	
	create_detection_area()
	create_approach_detection_area()
	create_grab_indicator()
	create_approach_indicator()
	if debug_enabled:
		create_debug_label()
	
	# Create vine segment sprites
	create_vine_segments()
	
	# Create end sprite
	create_end_sprite()

func setup_vine_holder_animation():
	# If no sprite_frames is assigned to the vine holder, create a default one
	if not sprite_frames:
		print("No SpriteFrames assigned to vine holder - creating default")
		sprite_frames = create_default_vine_holder_sprite_frames()
	
	# Start the animation
	if sprite_frames.has_animation(vine_holder_animation):
		play(vine_holder_animation)
	else:
		print("Animation '", vine_holder_animation, "' not found in vine holder SpriteFrames")

func create_default_vine_holder_sprite_frames() -> SpriteFrames:
	# Create a default SpriteFrames resource for the vine holder (anchor point)
	var frames = SpriteFrames.new()
	frames.add_animation("default")
	
	# Create a few frames for the vine anchor/holder animation
	for i in range(3):
		var image = Image.create(24, 24, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		
		# Draw a tree branch or vine anchor
		var branch_color = Color(0.4, 0.2, 0.1)  # Brown
		var leaf_color = Color(0.2, 0.6, 0.1)   # Green
		
		# Draw branch
		for y in range(10, 14):
			for x in range(8, 16):
				image.set_pixel(x, y, branch_color)
		
		# Add leaves that change per frame for animation
		var leaf_offset = i * 2
		image.set_pixel(6 + leaf_offset, 8, leaf_color)
		image.set_pixel(7 + leaf_offset, 9, leaf_color)
		image.set_pixel(18 - leaf_offset, 8, leaf_color)
		image.set_pixel(17 - leaf_offset, 9, leaf_color)
		
		var texture = ImageTexture.create_from_image(image)
		frames.add_frame("default", texture)
	
	frames.set_animation_speed("default", 2.0)  # 2 FPS for gentle swaying
	frames.set_animation_loop("default", true)
	
	return frames

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
	
	# Update end sprite position
	update_end_sprite_position()
	
	# Force a redraw to update the green circle
	queue_redraw()
	
	print("Vine length changed to: ", vine_length)

func set_remove_end_segments(new_count: int):
	remove_end_segments = max(0, new_count)  # Ensure it's not negative
	# Recreate vine segments to apply the change
	if vine_segment_sprites.size() > 0:
		create_vine_segments()
	print("Remove end segments set to: ", remove_end_segments)

func create_approach_detection_area():
	approach_detection_area = Area2D.new()
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = approach_detection_radius
	collision_shape.shape = shape
	
	# Position at the vine origin (anchor point)
	approach_detection_area.position = Vector2.ZERO
	
	# Set up Area2D properties
	approach_detection_area.monitoring = true
	approach_detection_area.monitorable = false
	
	# Set collision mask to layer 2 (where the player is)
	approach_detection_area.collision_mask = 2
	approach_detection_area.collision_layer = 0
	
	approach_detection_area.add_child(collision_shape)
	add_child(approach_detection_area)
	
	# Connect signals
	approach_detection_area.body_entered.connect(_on_approach_area_entered)
	approach_detection_area.body_exited.connect(_on_approach_area_exited)
	
	print("Approach detection area created with radius: ", approach_detection_radius)

func create_approach_indicator():
	approach_indicator = Sprite2D.new()
	add_child(approach_indicator)
	
	# Create a circular indicator texture (larger, more transparent)
	var size = int(approach_detection_radius * 2)
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	# Draw a circle outline
	var center = Vector2(size / 2, size / 2)
	var color = Color(1.0, 1.0, 0.0, 0.3)  # Semi-transparent yellow
	
	# Draw circle outline (simple method - not perfect but functional)
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x, y).distance_to(center)
			if abs(dist - approach_detection_radius) < 2.0:  # 2-pixel thick outline
				image.set_pixel(x, y, color)
	
	approach_indicator.texture = ImageTexture.create_from_image(image)
	approach_indicator.position = Vector2.ZERO  # Centered on vine origin
	approach_indicator.modulate = Color(1.0, 1.0, 1.0, 0.5)
	approach_indicator.visible = debug_enabled  # Only show when debug is enabled

func _on_approach_area_entered(body):
	print("Body entered approach area: ", body.name)
	if body.has_method("grab_vine"):
		player_in_approach_area = true
		last_player_position = body.global_position
		print("Player entered approach detection area")

func _on_approach_area_exited(body):
	print("Body exited approach area: ", body.name)
	if body.has_method("grab_vine"):
		player_in_approach_area = false
		time_moving_horizontally_towards_vine = 0.0  # Reset timer when leaving area
		print("Player exited approach detection area - horizontal approach timer reset")

# MODIFIED: Check if player is moving horizontally towards the vine origin
func is_player_moving_horizontally_towards_vine() -> bool:
	if not player or not player_in_approach_area:
		return false
	
	var current_position = player.global_position
	var movement_vector = current_position - last_player_position
	
	# MODIFIED: Only consider horizontal movement
	var horizontal_movement = Vector2(movement_vector.x, 0.0)
	
	# Check if player is moving horizontally fast enough
	var horizontal_movement_speed = horizontal_movement.length() / get_process_delta_time()
	if horizontal_movement_speed < approach_speed_threshold:
		return false
	
	# MODIFIED: Check if player is moving horizontally towards the vine
	var to_vine_horizontal = Vector2(vine_anchor.x - current_position.x, 0.0).normalized()
	var horizontal_movement_direction = horizontal_movement.normalized()
	
	# Calculate angle between horizontal movement direction and horizontal direction to vine
	var angle_to_vine = horizontal_movement_direction.angle_to(to_vine_horizontal)
	
	return abs(angle_to_vine) <= approach_angle_tolerance_radians

func create_end_sprite():
	if end_sprite:
		end_sprite.queue_free()
	
	end_sprite = Sprite2D.new()
	add_child(end_sprite)
	
	# Set up the end sprite
	if end_sprite_texture:
		end_sprite.texture = end_sprite_texture
	else:
		# Create a default 16x16 texture if none is provided
		end_sprite.texture = create_default_end_sprite_texture()
	
	# Apply inspector properties
	end_sprite.scale = end_sprite_scale
	end_sprite.modulate = end_sprite_modulate
	end_sprite.rotation = deg_to_rad(end_sprite_rotation_degrees)
	
	# Position at the end of the vine
	update_end_sprite_position()

func create_default_end_sprite_texture() -> ImageTexture:
	# Create a default 16x16 end sprite (like a small fruit or leaf)
	var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	# Draw a small berry or fruit
	var fruit_color = Color(0.8, 0.2, 0.2)  # Red
	var highlight_color = Color(1.0, 0.4, 0.4)  # Light red
	var stem_color = Color(0.4, 0.2, 0.1)  # Brown
	
	# Draw the fruit (circular)
	for y in range(4, 12):
		for x in range(4, 12):
			var distance_from_center = Vector2(x - 8, y - 8).length()
			if distance_from_center <= 3.5:
				var color = fruit_color
				# Add highlight
				if x < 8 and y < 8:
					color = fruit_color.lerp(highlight_color, 0.5)
				image.set_pixel(x, y, color)
	
	# Draw small stem at top
	image.set_pixel(8, 2, stem_color)
	image.set_pixel(8, 3, stem_color)
	
	# Add small leaf
	image.set_pixel(7, 3, Color(0.2, 0.6, 0.1))
	image.set_pixel(6, 4, Color(0.2, 0.6, 0.1))
	
	return ImageTexture.create_from_image(image)

func update_end_sprite_position():
	if not end_sprite:
		return
	
	if not is_player_grabbing:
		# When hanging straight, position at the end of the vine
		end_sprite.position = Vector2(0, vine_length) + end_sprite_offset
	# When swinging, the position will be updated in update_vine_segments_for_swinging()

func create_vine_segments():
	# Clear existing segments
	for segment in vine_segment_sprites:
		segment.queue_free()
	vine_segment_sprites.clear()
	
	# Use this node's SpriteFrames for the segments
	var segment_frames = sprite_frames
	if not segment_frames:
		print("No vine segment SpriteFrames assigned - creating default")
		segment_frames = create_default_vine_segment_sprite_frames()
	
	# Calculate how many segments we need
	var total_segments = max(1, int(vine_length / vine_segment_spacing))
	
	# Calculate how many segments to actually create (subtract removed segments)
	var visible_segments = max(0, total_segments - remove_end_segments)
	
	print("Creating ", visible_segments, " animated vine segments (", remove_end_segments, " removed from end) for length ", vine_length)
	
	# Create animated segment sprites (only the visible ones)
	for i in range(visible_segments):
		var segment = AnimatedSprite2D.new()
		segment.sprite_frames = segment_frames
		
		# Position segment along the vine path (using original total segment count for spacing)
		var segment_progress = float(i) / float(total_segments - 1) if total_segments > 1 else 0.0
		var segment_y = segment_progress * vine_length
		segment.position = Vector2(0, segment_y)
		
		# Start animation
		if segment_frames.has_animation(vine_segment_animation):
			segment.play(vine_segment_animation)
			segment.speed_scale = segment_animation_speed
			
			# Randomize starting frame for visual variety
			if randomize_segment_frame_offset:
				segment.frame = randi() % segment_frames.get_frame_count(vine_segment_animation)
		else:
			print("Animation '", vine_segment_animation, "' not found in segment SpriteFrames")
		
		# Add some variety to segments (but NO FLIPPING)
		if i % 4 == 1:
			segment.modulate = Color(0.95, 0.9, 0.8)  # Slightly different tint
		elif i % 4 == 2:
			segment.modulate = Color(0.9, 1.0, 0.9)  # Slight green tint instead
		elif i % 4 == 3:
			segment.speed_scale = segment_animation_speed * 0.8  # Slightly slower animation
		
		add_child(segment)
		vine_segment_sprites.append(segment)

func create_default_vine_segment_sprite_frames() -> SpriteFrames:
	# Create a default SpriteFrames resource for vine segments
	var frames = SpriteFrames.new()
	frames.add_animation("default")
	
	# Create multiple frames for vine segment animation (swaying, growing, etc.)
	for frame_idx in range(4):
		var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		
		# Draw vine segment with slight variations per frame
		var vine_color = Color(0.4, 0.2, 0.1)  # Brown
		var leaf_color = Color(0.2, 0.6, 0.1)  # Green
		
		# Central stem (4 pixels wide as requested)
		var stem_offset = sin(frame_idx * 0.5) * 0.5  # Slight sway animation
		for y in range(16):
			for x in range(6, 10):  # 4 pixels wide, centered
				var actual_x = x + int(stem_offset)
				if actual_x >= 0 and actual_x < 16:
					var color = vine_color
					# Add some texture variation
					if x == 6 or x == 9:
						color = color.darkened(0.2)  # Darker edges
					if (y + frame_idx) % 6 == 0:
						color = color.lightened(0.1)  # Moving texture rings
					image.set_pixel(actual_x, y, color)
		
		# Add animated leaves/details
		var leaf_frame_offset = frame_idx
		
		# Left leaf (animated)
		if frame_idx % 2 == 0:
			image.set_pixel(4, 4 + leaf_frame_offset, leaf_color)
			image.set_pixel(5, 5 + leaf_frame_offset, leaf_color)
		
		# Right leaf (animated)
		if (frame_idx + 1) % 3 == 0:
			image.set_pixel(11, 8 + (leaf_frame_offset % 2), leaf_color)
			image.set_pixel(10, 9 + (leaf_frame_offset % 2), leaf_color)
		
		# Add small animated details
		if frame_idx == 2:
			# Small berries or buds
			image.set_pixel(3, 12, Color(0.8, 0.2, 0.2))  # Red berry
			image.set_pixel(12, 6, Color(0.8, 0.2, 0.2))  # Red berry
		
		var texture = ImageTexture.create_from_image(image)
		frames.add_frame("default", texture)
	
	frames.set_animation_speed("default", 3.0)  # 3 FPS for gentle animation
	frames.set_animation_loop("default", true)
	
	return frames

func update_vine_segments_for_swinging():
	if not is_player_grabbing or not player:
		# Vine hangs straight down
		for i in range(vine_segment_sprites.size()):
			var segment = vine_segment_sprites[i]
			# Calculate segment progress based on total segments (including removed ones)
			var total_segments = max(1, int(vine_length / vine_segment_spacing))
			var segment_progress = float(i) / float(total_segments - 1) if total_segments > 1 else 0.0
			var segment_y = segment_progress * vine_length
			segment.position = Vector2(0, segment_y)
			segment.rotation = 0  # No rotation when hanging straight
			
			# Normal animation speed when not swinging
			segment.speed_scale = segment_animation_speed
		
		# Position end sprite at the vine end when hanging straight
		if end_sprite:
			end_sprite.position = Vector2(0, vine_length) + end_sprite_offset
			end_sprite.rotation = deg_to_rad(end_sprite_rotation_degrees)  # Reset to inspector rotation
		return
	
	# When swinging, curve the vine segments toward the vine's visual bottom (not player position)
	var to_vine_bottom = current_vine_bottom - vine_anchor
	var vine_direction = to_vine_bottom.normalized()
	var vine_visual_distance = vine_length  # Use the vine's visual length, not distance to player
	
	# Calculate swing intensity for animation effects
	var swing_speed = player.velocity.length()
	var swing_intensity = clamp(swing_speed / 300.0, 0.0, 2.0)  # 0-2x multiplier based on swing speed
	
	var last_segment_position = Vector2.ZERO
	var last_segment_rotation = 0.0
	var total_segments = max(1, int(vine_length / vine_segment_spacing))
	
	for i in range(vine_segment_sprites.size()):
		var segment = vine_segment_sprites[i]
		# Calculate segment progress based on total segments (including removed ones)
		var segment_progress = float(i) / float(total_segments - 1) if total_segments > 1 else 0.0
		
		# Create a curved vine by interpolating between hanging down and pointing toward vine bottom
		var straight_pos = Vector2(0, segment_progress * vine_length)
		var curved_pos = vine_direction * (segment_progress * vine_visual_distance)
		
		# Blend between straight and curved based on how far we are along the vine
		var curve_strength = segment_progress * 0.8  # Stronger curve toward the end
		segment.position = straight_pos.lerp(curved_pos, curve_strength)
		
		# Remember the last segment's position for the end sprite
		if i == vine_segment_sprites.size() - 1:
			last_segment_position = segment.position
		
		# Rotate segments to follow the vine direction (NO ROTATION LIMITS)
		if i < vine_segment_sprites.size() - 1:
			var next_progress = float(i + 1) / float(total_segments - 1)
			var next_straight_pos = Vector2(0, next_progress * vine_length)
			var next_curved_pos = vine_direction * (next_progress * vine_visual_distance)
			var next_pos = next_straight_pos.lerp(next_curved_pos, next_progress * 0.8)
			
			var segment_direction = (next_pos - segment.position).normalized()
			
			# Calculate rotation angle - NO CLAMPING OR LIMITS
			var angle = atan2(-segment_direction.x, segment_direction.y)
			segment.rotation = angle
			
			# Remember the last segment's rotation for the end sprite
			if i == vine_segment_sprites.size() - 1:
				last_segment_rotation = angle
		else:
			# Last segment uses the same angle as the previous segment
			if i > 0:
				segment.rotation = vine_segment_sprites[i-1].rotation
				last_segment_rotation = segment.rotation
		
		# Speed up animation based on swing intensity
		segment.speed_scale = segment_animation_speed * (1.0 + swing_intensity)
	
	# Position and rotate the end sprite to follow the last segment
	if end_sprite:
		# Position at the end of the curved vine path (always at vine_length, not affected by removed segments)
		var end_direction = vine_direction
		var end_position = end_direction * vine_visual_distance + end_sprite_offset
		end_sprite.position = end_position
		
		# Rotate the end sprite to match the vine direction + inspector rotation
		var vine_rotation = atan2(vine_direction.x, -vine_direction.y)
		end_sprite.rotation = vine_rotation + deg_to_rad(end_sprite_rotation_degrees)

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
	# MODIFIED: Update horizontal approach tracking with stop detection
	if player_in_approach_area and player:
		if is_player_moving_horizontally_towards_vine():
			time_moving_horizontally_towards_vine += delta
			print("Horizontal approach time: ", time_moving_horizontally_towards_vine)
		else:
			# NEW: Reset timer immediately if player stops or changes direction
			if time_moving_horizontally_towards_vine > 0.0:
				print("Player stopped or changed direction - resetting horizontal approach timer")
			time_moving_horizontally_towards_vine = 0.0
		
		# Update last position for next frame's calculation
		last_player_position = player.global_position
	
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
	
	# Update end sprite properties from inspector (in case they changed)
	if end_sprite:
		if end_sprite_texture and end_sprite.texture != end_sprite_texture:
			end_sprite.texture = end_sprite_texture
		elif not end_sprite_texture and not end_sprite.texture:
			end_sprite.texture = create_default_end_sprite_texture()
		
		end_sprite.scale = end_sprite_scale
		end_sprite.modulate = end_sprite_modulate
	
	# Update approach indicator visibility based on debug setting
	if approach_indicator:
		approach_indicator.visible = debug_enabled
	
	if debug_enabled and debug_label:
		update_debug_info()
	queue_redraw()

func update_debug_info():
	if not debug_label:
		return
	
	var debug_text = ""
	debug_text += "GREEN ORBIT: " + str(int(vine_length)) + "px\n"
	debug_text += "BLUE HITBOX: " + str(int(grab_range)) + "px\n"
	debug_text += "APPROACH AREA: " + str(int(approach_detection_radius)) + "px\n"
	debug_text += "SEGMENTS: " + str(vine_segment_sprites.size()) + "\n"
	debug_text += "REMOVED: " + str(remove_end_segments) + "\n"
	debug_text += "END SPRITE: " + ("Yes" if end_sprite else "No") + "\n"
	debug_text += "In Grab Area: " + str(player_in_grab_area) + "\n"
	debug_text += "In Approach Area: " + str(player_in_approach_area) + "\n"
	debug_text += "Is Grabbing: " + str(is_player_grabbing) + "\n"
	debug_text += "H-Approach Time: " + str(time_moving_horizontally_towards_vine) + "s\n"  # MODIFIED
	debug_text += "H-Moving to Vine: " + str(is_player_moving_horizontally_towards_vine()) + "\n"  # MODIFIED
	
	if player:
		var distance_from_anchor = vine_anchor.distance_to(player.global_position)
		var distance_from_blue_circle = current_vine_bottom.distance_to(player.global_position)
		debug_text += "Player->Anchor: " + str(int(distance_from_anchor)) + "px\n"
		debug_text += "Player->BlueCircle: " + str(int(distance_from_blue_circle)) + "px\n"
		debug_text += "Player Pos: " + str(Vector2i(player.global_position)) + "\n"
		debug_text += "H-Speed: " + str(int(Vector2(player.velocity.x, 0.0).length())) + "px/s\n"  # MODIFIED: Show horizontal speed only
	else:
		debug_text += "No Player\n"
	
	debug_label.text = debug_text

func _draw():
	# Draw debug information (the animated sprites handle the visual vine now)
	if debug_enabled:
		# Draw vine anchor point (red circle)
		draw_circle(Vector2.ZERO, 8, Color.RED)
		
		# Draw the GREEN PATH GIZMO - the full swing arc that represents where player swings
		var arc_color = Color.GREEN
		arc_color.a = 0.4
		draw_arc(Vector2.ZERO, vine_length, 0, TAU, 64, arc_color, 3.0)
		
		# Draw the YELLOW APPROACH AREA - circular area around vine origin
		var approach_color = Color.YELLOW
		approach_color.a = 0.2
		draw_arc(Vector2.ZERO, approach_detection_radius, 0, TAU, 64, approach_color, 2.0)
		
		# MODIFIED: Highlight approach area when player is moving horizontally towards vine
		if player_in_approach_area and is_player_moving_horizontally_towards_vine():
			var highlight_color = Color.ORANGE
			highlight_color.a = 0.4
			draw_arc(Vector2.ZERO, approach_detection_radius, 0, TAU, 64, highlight_color, 3.0)
		
		# Draw the BLUE CIRCLE GIZMO - current position of the grab area (detection area)
		var blue_circle_position = detection_area.position
		draw_circle(blue_circle_position, grab_range, Color.BLUE)
		
		# Highlight when player is in grab area
		if player_in_grab_area:
			draw_circle(blue_circle_position, grab_range + 3, Color.CYAN)
		
		# Draw a small dot at the exact center of the blue circle for precision
		draw_circle(blue_circle_position, 2, Color.WHITE)
		
		# MODIFIED: Draw horizontal approach timer visualization (progress bar near vine origin)
		if time_moving_horizontally_towards_vine > 0.0:
			var bar_width = 40.0
			var bar_height = 6.0
			var bar_position = Vector2(-bar_width / 2, -30)  # Above the vine anchor
			
			# Background bar
			draw_rect(Rect2(bar_position, Vector2(bar_width, bar_height)), Color.BLACK)
			
			# Progress bar (clamped to a reasonable max time for visualization)
			var max_time_for_display = 3.0  # 3 seconds max for full bar
			var progress = clamp(time_moving_horizontally_towards_vine / max_time_for_display, 0.0, 1.0)
			var progress_width = bar_width * progress
			var progress_color = Color.YELLOW.lerp(Color.ORANGE, progress)
			draw_rect(Rect2(bar_position, Vector2(progress_width, bar_height)), progress_color)

func _on_body_entered(body):
	print("Body entered vine grab area: ", body.name)
	
	if body.has_method("grab_vine"):
		player = body
		player_in_grab_area = true
		
		# Notify the player's VineComponent about nearby vine
		if body.has_node("VineComponent"):
			var vine_component = body.get_node("VineComponent")
			vine_component.nearby_vine = self
		
		# Show grab indicator when player is in range
		if grab_indicator:
			grab_indicator.visible = true
		
		print("Player is now in grab area (blue circle)")
		
		# Immediately try to grab the vine if not already swinging
		if body.has_node("VineComponent"):
			var vine_component = body.get_node("VineComponent")
			if not vine_component.is_swinging:
				vine_component.grab_vine(self)

func _on_body_exited(body):
	print("Body exited vine grab area: ", body.name)
	
	if body.has_method("grab_vine"):
		if player == body:
			# Notify the player's VineComponent that vine is no longer nearby
			if body.has_node("VineComponent"):
				body.get_node("VineComponent").nearby_vine = null
			player = null
		player_in_grab_area = false
		
		# Hide grab indicator when player leaves range
		if grab_indicator:
			grab_indicator.visible = false
		
		print("Player left grab area")

func attach_player(p: CharacterBody2D):
	player = p
	is_player_grabbing = true

func release_player():
	player = null
	is_player_grabbing = false

func get_swing_direction_to_player() -> Vector2:
	if not player:
		return Vector2.ZERO
	
	var direction = player.global_position - vine_anchor
	return direction.normalized()

func get_distance_to_player() -> float:
	if not player:
		return 0.0
	
	return vine_anchor.distance_to(player.global_position)

# MODIFIED: Get the current horizontal approach time
func get_approach_time() -> float:
	return time_moving_horizontally_towards_vine

# Check if player is currently in the approach area
func is_player_in_approach_area() -> bool:
	return player_in_approach_area

# MODIFIED: Reset the horizontal approach timer
func reset_approach_timer():
	time_moving_horizontally_towards_vine = 0.0

# MODIFIED: Get horizontal approach progress as a normalized value (0.0 to 1.0)
func get_approach_progress(max_time: float = 3.0) -> float:
	return clamp(time_moving_horizontally_towards_vine / max_time, 0.0, 1.0)

extends AnimatedSprite2D
class_name Vine

@export var vine_length: float = 200.0: set = set_vine_length
@export var swing_force: float = 500.0
@export var grab_range: float = 15.0
@export var debug_enabled: bool = true

@export_group("Vine Visuals")
@export var vine_segment_animation: String = "default"
@export var vine_segments_per_16_pixels: int = 1
@export var vine_segment_spacing: float = 16.0
@export var vine_holder_animation: String = "default"
@export var segment_animation_speed: float = 1.0
@export var randomize_segment_frame_offset: bool = true
@export var remove_end_segments: int = 0: set = set_remove_end_segments

@export_group("End Sprite")
@export var end_sprite_texture: Texture2D
@export var end_sprite_scale: Vector2 = Vector2(1.0, 1.0)
@export var end_sprite_offset: Vector2 = Vector2.ZERO
@export var end_sprite_modulate: Color = Color.WHITE
@export var end_sprite_rotation_degrees: float = 0.0
@export var end_sprite_locks_rotation: bool = true

@export_group("Horizontal Approach Tracking")
@export var approach_detection_radius: float = 100.0
@export var approach_speed_threshold: float = 20.0
@export var approach_angle_tolerance_degrees: float = 60.0

@export_group("Approach Speed Boost")
@export var min_approach_time_for_boost: float = 0.5
@export var base_initial_boost: float = 100.0
@export var max_approach_boost: float = 300.0
@export var approach_time_for_max_boost: float = 2.0
@export var approach_boost_curve: float = 1.5
@export var player_velocity_boost_multiplier: float = 0.8
@export var approach_direction_boost_multiplier: float = 1.2

@export_group("Vine Bend Compensation")
# NEW: Settings to adjust for vine bending
@export var vine_bend_compensation: float = 0.92  # How much to reduce apparent length
@export var segment_curve_intensity: float = 0.75  # How much each segment curves
@export var progressive_curve_reduction: float = 0.95  # Reduces curve towards the end

var detection_area: Area2D
var approach_detection_area: Area2D
var grab_indicator: Sprite2D
var debug_label: Label
var player: CharacterBody2D = null
var is_player_grabbing: bool = false
var vine_anchor: Vector2
var current_vine_bottom: Vector2
var player_in_grab_area: bool = false
var player_in_approach_area: bool = false
var time_moving_horizontally_towards_vine: float = 0.0
var last_player_position: Vector2 = Vector2.ZERO
var approach_angle_tolerance_radians: float
var vine_segment_sprites: Array[AnimatedSprite2D] = []
var end_sprite: Sprite2D

# NEW: Variables for vine return animation and bend compensation
var vine_component_ref: VineComponent = null
var end_sprite_base_rotation: float = 0.0
var visual_vine_length: float = 0.0  # Adjusted length for visual consistency

func _ready():
	vine_anchor = global_position
	visual_vine_length = vine_length * vine_bend_compensation  # NEW: Calculate visual length
	current_vine_bottom = vine_anchor + Vector2(0, vine_length)
	approach_angle_tolerance_radians = deg_to_rad(approach_angle_tolerance_degrees)
	end_sprite_base_rotation = deg_to_rad(end_sprite_rotation_degrees)
	
	setup_vine_holder_animation()
	create_detection_area()
	create_approach_detection_area()
	create_grab_indicator()
	if debug_enabled: create_debug_label()
	create_vine_segments()
	create_end_sprite()

func setup_vine_holder_animation():
	if not sprite_frames:
		sprite_frames = create_default_vine_holder_sprite_frames()
	if sprite_frames.has_animation(vine_holder_animation):
		play(vine_holder_animation)

func create_default_vine_holder_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("default")
	for i in range(3):
		var image = Image.create(24, 24, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		var branch_color = Color(0.4, 0.2, 0.1)
		var leaf_color = Color(0.2, 0.6, 0.1)
		for y in range(10, 14):
			for x in range(8, 16):
				image.set_pixel(x, y, branch_color)
		var leaf_offset = i * 2
		image.set_pixel(6 + leaf_offset, 8, leaf_color)
		image.set_pixel(7 + leaf_offset, 9, leaf_color)
		image.set_pixel(18 - leaf_offset, 8, leaf_color)
		image.set_pixel(17 - leaf_offset, 9, leaf_color)
		frames.add_frame("default", ImageTexture.create_from_image(image))
	frames.set_animation_speed("default", 2.0)
	frames.set_animation_loop("default", true)
	return frames

func set_vine_length(new_length: float):
	vine_length = new_length
	visual_vine_length = vine_length * vine_bend_compensation  # NEW: Update visual length
	if not is_player_grabbing:
		current_vine_bottom = vine_anchor + Vector2(0, vine_length)
	if detection_area and not is_player_grabbing:
		detection_area.position = Vector2(0, vine_length)
	if grab_indicator and not is_player_grabbing:
		grab_indicator.position = Vector2(0, vine_length)
	if debug_label:
		debug_label.position = Vector2(-50, vine_length + 40)
	create_vine_segments()
	update_end_sprite_position()
	queue_redraw()

func set_remove_end_segments(new_count: int):
	remove_end_segments = max(0, new_count)
	if vine_segment_sprites.size() > 0:
		create_vine_segments()

func create_approach_detection_area():
	approach_detection_area = Area2D.new()
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = approach_detection_radius
	collision_shape.shape = shape
	approach_detection_area.position = Vector2.ZERO
	approach_detection_area.monitoring = true
	approach_detection_area.monitorable = false
	approach_detection_area.collision_mask = 2
	approach_detection_area.collision_layer = 0
	approach_detection_area.add_child(collision_shape)
	add_child(approach_detection_area)
	approach_detection_area.body_entered.connect(_on_approach_area_entered)
	approach_detection_area.body_exited.connect(_on_approach_area_exited)

func _on_approach_area_entered(body):
	if body.has_method("grab_vine"):
		player_in_approach_area = true
		last_player_position = body.global_position

func _on_approach_area_exited(body):
	if body.has_method("grab_vine"):
		player_in_approach_area = false
		time_moving_horizontally_towards_vine = 0.0

func is_player_moving_horizontally_towards_vine() -> bool:
	if not player or not player_in_approach_area:
		return false
	var current_position = player.global_position
	var movement_vector = current_position - last_player_position
	var horizontal_movement = Vector2(movement_vector.x, 0.0)
	var horizontal_movement_speed = horizontal_movement.length() / get_process_delta_time()
	if horizontal_movement_speed < approach_speed_threshold:
		return false
	var horizontal_distance_to_vine = abs(current_position.x - vine_anchor.x)
	if horizontal_distance_to_vine <= grab_range:
		return false
	var to_vine_horizontal = Vector2(vine_anchor.x - current_position.x, 0.0).normalized()
	var horizontal_movement_direction = horizontal_movement.normalized()
	var angle_to_vine = horizontal_movement_direction.angle_to(to_vine_horizontal)
	return abs(angle_to_vine) <= approach_angle_tolerance_radians

func create_end_sprite():
	if end_sprite:
		end_sprite.queue_free()
	end_sprite = Sprite2D.new()
	add_child(end_sprite)
	if end_sprite_texture:
		end_sprite.texture = end_sprite_texture
	else:
		end_sprite.texture = create_default_end_sprite_texture()
	end_sprite.scale = end_sprite_scale
	end_sprite.modulate = end_sprite_modulate
	end_sprite.rotation = end_sprite_base_rotation
	update_end_sprite_position()

func create_default_end_sprite_texture() -> ImageTexture:
	var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var fruit_color = Color(0.8, 0.2, 0.2)
	var highlight_color = Color(1.0, 0.4, 0.4)
	var stem_color = Color(0.4, 0.2, 0.1)
	for y in range(4, 12):
		for x in range(4, 12):
			var distance_from_center = Vector2(x - 8, y - 8).length()
			if distance_from_center <= 3.5:
				var color = fruit_color
				if x < 8 and y < 8:
					color = fruit_color.lerp(highlight_color, 0.5)
				image.set_pixel(x, y, color)
	image.set_pixel(8, 2, stem_color)
	image.set_pixel(8, 3, stem_color)
	image.set_pixel(7, 3, Color(0.2, 0.6, 0.1))
	image.set_pixel(6, 4, Color(0.2, 0.6, 0.1))
	return ImageTexture.create_from_image(image)

func update_end_sprite_position():
	if not end_sprite:
		return
	if not is_player_grabbing:
		end_sprite.position = Vector2(0, vine_length) + end_sprite_offset

# NEW: Calculate the actual distance a vine segment chain would reach
func calculate_segment_chain_length(segments: int, segment_spacing: float, curve_factor: float = 0.8) -> float:
	if segments <= 1:
		return segment_spacing
	
	var total_length = 0.0
	var current_curve = curve_factor
	
	for i in range(segments):
		var segment_length = segment_spacing * current_curve
		total_length += segment_length
		current_curve *= progressive_curve_reduction  # Each segment curves slightly less
	
	return total_length

func create_vine_segments():
	for segment in vine_segment_sprites:
		segment.queue_free()
	vine_segment_sprites.clear()
	
	var segment_frames = sprite_frames
	if not segment_frames:
		segment_frames = create_default_vine_segment_sprite_frames()
	
	var total_segments = max(1, int(vine_length / vine_segment_spacing))
	var visible_segments = max(0, total_segments - remove_end_segments)
	
	# NEW: Calculate cumulative position considering bend
	var cumulative_distance = 0.0
	
	for i in range(visible_segments):
		var segment = AnimatedSprite2D.new()
		segment.sprite_frames = segment_frames
		
		# NEW: Progressive curve calculation
		var segment_progress = float(i) / float(total_segments - 1) if total_segments > 1 else 0.0
		var curve_intensity = segment_curve_intensity * (1.0 - segment_progress * 0.3)  # Reduce curve towards end
		
		# Calculate this segment's contribution to the chain
		var segment_length = vine_segment_spacing * curve_intensity
		cumulative_distance += segment_length
		
		# Position segment based on cumulative curved distance, but map to straight vine length
		var straight_position_ratio = cumulative_distance / visual_vine_length
		straight_position_ratio = clamp(straight_position_ratio, 0.0, 1.0)
		var segment_y = straight_position_ratio * vine_length
		
		segment.position = Vector2(0, segment_y)
		
		if segment_frames.has_animation(vine_segment_animation):
			segment.play(vine_segment_animation)
			segment.speed_scale = segment_animation_speed
			if randomize_segment_frame_offset:
				segment.frame = randi() % segment_frames.get_frame_count(vine_segment_animation)
		
		if i % 4 == 1:
			segment.modulate = Color(0.95, 0.9, 0.8)
		elif i % 4 == 2:
			segment.modulate = Color(0.9, 1.0, 0.9)
		elif i % 4 == 3:
			segment.speed_scale = segment_animation_speed * 0.8
		
		add_child(segment)
		vine_segment_sprites.append(segment)

func create_default_vine_segment_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("default")
	for frame_idx in range(4):
		var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		var vine_color = Color(0.4, 0.2, 0.1)
		var leaf_color = Color(0.2, 0.6, 0.1)
		var stem_offset = sin(frame_idx * 0.5) * 0.5
		for y in range(16):
			for x in range(6, 10):
				var actual_x = x + int(stem_offset)
				if actual_x >= 0 and actual_x < 16:
					var color = vine_color
					if x == 6 or x == 9:
						color = color.darkened(0.2)
					if (y + frame_idx) % 6 == 0:
						color = color.lightened(0.1)
					image.set_pixel(actual_x, y, color)
		var leaf_frame_offset = frame_idx
		if frame_idx % 2 == 0:
			image.set_pixel(4, 4 + leaf_frame_offset, leaf_color)
			image.set_pixel(5, 5 + leaf_frame_offset, leaf_color)
		if (frame_idx + 1) % 3 == 0:
			image.set_pixel(11, 8 + (leaf_frame_offset % 2), leaf_color)
			image.set_pixel(10, 9 + (leaf_frame_offset % 2), leaf_color)
		if frame_idx == 2:
			image.set_pixel(3, 12, Color(0.8, 0.2, 0.2))
			image.set_pixel(12, 6, Color(0.8, 0.2, 0.2))
		frames.add_frame("default", ImageTexture.create_from_image(image))
	frames.set_animation_speed("default", 3.0)
	frames.set_animation_loop("default", true)
	return frames

func update_vine_segments_for_swinging():
	# NEW: Get swing data from vine component if available
	var swing_angle = 0.0
	var swing_angular_velocity = 0.0
	var vine_returning = false
	
	if vine_component_ref:
		swing_angle = vine_component_ref.swing_angle
		swing_angular_velocity = vine_component_ref.swing_angular_velocity
		vine_returning = vine_component_ref.vine_returning_to_rest
	
	# Handle return animation case
	if vine_returning:
		var vine_direction = Vector2(sin(swing_angle), cos(swing_angle))
		# NEW: Use visual vine length for return animation
		var vine_visual_distance = visual_vine_length
		var total_segments = max(1, int(vine_length / vine_segment_spacing))
		
		for i in range(vine_segment_sprites.size()):
			var segment = vine_segment_sprites[i]
			var segment_progress = float(i) / float(total_segments - 1) if total_segments > 1 else 0.0
			var straight_pos = Vector2(0, segment_progress * vine_length)
			var curved_pos = vine_direction * (segment_progress * vine_visual_distance)
			var curve_strength = segment_progress * 0.6  # Reduced curve for return animation
			segment.position = straight_pos.lerp(curved_pos, curve_strength)
			
			if i < vine_segment_sprites.size() - 1:
				var next_progress = float(i + 1) / float(total_segments - 1)
				var next_straight_pos = Vector2(0, next_progress * vine_length)
				var next_curved_pos = vine_direction * (next_progress * vine_visual_distance)
				var next_pos = next_straight_pos.lerp(next_curved_pos, next_progress * 0.6)
				var segment_direction = (next_pos - segment.position).normalized()
				var angle = atan2(-segment_direction.x, segment_direction.y)
				segment.rotation = angle
			else:
				if i > 0:
					segment.rotation = vine_segment_sprites[i-1].rotation
			segment.speed_scale = segment_animation_speed
		
		if end_sprite:
			var end_direction = vine_direction
			var end_position = end_direction * vine_visual_distance + end_sprite_offset
			end_sprite.position = end_position
			# NEW: Keep end sprite rotation locked if enabled
			if end_sprite_locks_rotation:
				end_sprite.rotation = end_sprite_base_rotation
			else:
				var vine_rotation = atan2(vine_direction.x, -vine_direction.y)
				end_sprite.rotation = vine_rotation + end_sprite_base_rotation
		return
	
	if not is_player_grabbing or not player:
		for i in range(vine_segment_sprites.size()):
			var segment = vine_segment_sprites[i]
			var total_segments = max(1, int(vine_length / vine_segment_spacing))
			var segment_progress = float(i) / float(total_segments - 1) if total_segments > 1 else 0.0
			var segment_y = segment_progress * vine_length
			segment.position = Vector2(0, segment_y)
			segment.rotation = 0
			segment.speed_scale = segment_animation_speed
		if end_sprite:
			end_sprite.position = Vector2(0, vine_length) + end_sprite_offset
			end_sprite.rotation = end_sprite_base_rotation
		return
	
	var to_vine_bottom = current_vine_bottom - vine_anchor
	var vine_direction = to_vine_bottom.normalized()
	# NEW: Use visual vine length for consistency with player position
	var vine_visual_distance = visual_vine_length
	var swing_speed = player.velocity.length()
	var swing_intensity = clamp(swing_speed / 300.0, 0.0, 2.0)
	var total_segments = max(1, int(vine_length / vine_segment_spacing))
	
	for i in range(vine_segment_sprites.size()):
		var segment = vine_segment_sprites[i]
		var segment_progress = float(i) / float(total_segments - 1) if total_segments > 1 else 0.0
		var straight_pos = Vector2(0, segment_progress * vine_length)
		var curved_pos = vine_direction * (segment_progress * vine_visual_distance)
		# NEW: Adjusted curve strength to better match player position
		var curve_strength = segment_progress * segment_curve_intensity
		segment.position = straight_pos.lerp(curved_pos, curve_strength)
		
		if i < vine_segment_sprites.size() - 1:
			var next_progress = float(i + 1) / float(total_segments - 1)
			var next_straight_pos = Vector2(0, next_progress * vine_length)
			var next_curved_pos = vine_direction * (next_progress * vine_visual_distance)
			var next_pos = next_straight_pos.lerp(next_curved_pos, next_progress * segment_curve_intensity)
			var segment_direction = (next_pos - segment.position).normalized()
			var angle = atan2(-segment_direction.x, segment_direction.y)
			segment.rotation = angle
		else:
			if i > 0:
				segment.rotation = vine_segment_sprites[i-1].rotation
		segment.speed_scale = segment_animation_speed * (1.0 + swing_intensity)
	
	if end_sprite:
		var end_direction = vine_direction
		var end_position = end_direction * vine_visual_distance + end_sprite_offset
		end_sprite.position = end_position
		# NEW: Keep end sprite rotation locked if enabled
		if end_sprite_locks_rotation:
			end_sprite.rotation = end_sprite_base_rotation
		else:
			var vine_rotation = atan2(vine_direction.x, -vine_direction.y)
			end_sprite.rotation = vine_rotation + end_sprite_base_rotation

func create_detection_area():
	detection_area = Area2D.new()
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = grab_range
	collision_shape.shape = shape
	detection_area.position = Vector2(0, vine_length)
	detection_area.monitoring = true
	detection_area.monitorable = false
	detection_area.collision_mask = 2
	detection_area.collision_layer = 0
	detection_area.add_child(collision_shape)
	add_child(detection_area)
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

func create_grab_indicator():
	grab_indicator = Sprite2D.new()
	add_child(grab_indicator)
	var image = Image.create(int(grab_range * 2), int(grab_range * 2), false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 1.0, 0.5))
	grab_indicator.texture = ImageTexture.create_from_image(image)
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
	if player_in_approach_area and player and not is_player_grabbing:
		if is_player_moving_horizontally_towards_vine():
			time_moving_horizontally_towards_vine += delta
		else:
			time_moving_horizontally_towards_vine = 0.0
		last_player_position = player.global_position
	else:
		if is_player_grabbing and time_moving_horizontally_towards_vine > 0:
			time_moving_horizontally_towards_vine = 0.0
		if player:
			last_player_position = player.global_position
	
	if is_player_grabbing and player:
		current_vine_bottom = player.global_position
		detection_area.position = player.global_position - global_position
		grab_indicator.position = player.global_position - global_position
	else:
		current_vine_bottom = vine_anchor + Vector2(0, vine_length)
		detection_area.position = Vector2(0, vine_length)
		grab_indicator.position = Vector2(0, vine_length)
	
	update_vine_segments_for_swinging()
	
	if end_sprite:
		if end_sprite_texture and end_sprite.texture != end_sprite_texture:
			end_sprite.texture = end_sprite_texture
		elif not end_sprite_texture and not end_sprite.texture:
			end_sprite.texture = create_default_end_sprite_texture()
		end_sprite.scale = end_sprite_scale
		end_sprite.modulate = end_sprite_modulate
	
	if debug_enabled and debug_label:
		update_debug_info()

func update_debug_info():
	if not debug_label:
		return
	var debug_text = ""
	debug_text += "Vine Length: " + str(int(vine_length)) + "px\n"
	debug_text += "Visual Length: " + str(int(visual_vine_length)) + "px\n"  # NEW: Show visual length
	debug_text += "Grab Range: " + str(int(grab_range)) + "px\n"
	debug_text += "Approach Area: " + str(int(approach_detection_radius)) + "px\n"
	debug_text += "Segments: " + str(vine_segment_sprites.size()) + "\n"
	debug_text += "In Grab Area: " + str(player_in_grab_area) + "\n"
	debug_text += "In Approach Area: " + str(player_in_approach_area) + "\n"
	debug_text += "Is Grabbing: " + str(is_player_grabbing) + "\n"
	
	if not is_player_grabbing:
		debug_text += "Approach Time: " + str("%.2f" % time_moving_horizontally_towards_vine) + "s\n"
		debug_text += "H-Moving to Vine: " + str(is_player_moving_horizontally_towards_vine()) + "\n"
	
	if player:
		debug_text += "Player Pos: " + str(Vector2i(player.global_position)) + "\n"
	debug_label.text = debug_text

func _on_body_entered(body):
	if body.has_method("grab_vine"):
		player = body
		player_in_grab_area = true
		if body.has_node("VineComponent"):
			var vine_component = body.get_node("VineComponent")
			vine_component.nearby_vine = self
		if grab_indicator:
			grab_indicator.visible = true
		if body.has_node("VineComponent"):
			var vine_component = body.get_node("VineComponent")
			if not vine_component.is_swinging:
				vine_component.grab_vine(self)

func _on_body_exited(body):
	if body.has_method("grab_vine"):
		if player == body:
			if body.has_node("VineComponent"):
				body.get_node("VineComponent").nearby_vine = null
			player = null
		player_in_grab_area = false
		if grab_indicator:
			grab_indicator.visible = false

func attach_player(p: CharacterBody2D):
	player = p
	is_player_grabbing = true
	time_moving_horizontally_towards_vine = 0.0
	
	# NEW: Store reference to vine component for animation access
	if player and player.has_node("VineComponent"):
		vine_component_ref = player.get_node("VineComponent")

func release_player():
	player = null
	is_player_grabbing = false
	
	# Keep the vine component reference for the return animation
	# Don't clear it here - let the VineComponent handle its lifecycle

func get_swing_direction_to_player() -> Vector2:
	if not player:
		return Vector2.ZERO
	var direction = player.global_position - vine_anchor
	return direction.normalized()

func get_distance_to_player() -> float:
	if not player:
		return 0.0
	return vine_anchor.distance_to(player.global_position)

func get_approach_time() -> float:
	return time_moving_horizontally_towards_vine

func is_player_in_approach_area() -> bool:
	return player_in_approach_area

func reset_approach_timer():
	time_moving_horizontally_towards_vine = 0.0

func get_approach_progress(max_time: float = 3.0) -> float:
	return clamp(time_moving_horizontally_towards_vine / max_time, 0.0, 1.0)

# NEW: Clear vine component reference when it's no longer needed
func clear_vine_component_ref():
	vine_component_ref = null

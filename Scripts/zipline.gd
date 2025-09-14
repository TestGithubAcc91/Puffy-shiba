@tool
extends Node2D
class_name Zipline

@export var zipline_speed: float = 400.0
@export var can_reverse: bool = true
@export var auto_release_at_end: bool = true
@export var auto_grab: bool = true

# Vine sprite properties
@export var vine_texture: Texture2D : set = _set_vine_texture
@export var vine_segment_size: Vector2 = Vector2(21, 7) # 3x7 sprite size (assuming each cell is 7x7)
@export var vine_segments_per_unit: float = 0.1 # How many segments per pixel of zipline

# These will be automatically updated when you move the marker nodes
@export var start_point: Vector2 : set = _set_start_point
@export var end_point: Vector2 : set = _set_end_point

@onready var line: Line2D = $Line2D
@onready var vine_container: Node2D = $VineContainer
@onready var start_area: Area2D = $StartMarker/GrabArea
@onready var end_area: Area2D = $EndMarker/GrabArea
@onready var start_collision: CollisionShape2D = $StartMarker/GrabArea/CollisionShape2D
@onready var end_collision: CollisionShape2D = $EndMarker/GrabArea/CollisionShape2D
@onready var start_marker: Node2D = $StartMarker
@onready var end_marker: Node2D = $EndMarker

var player: CharacterBody2D = null
var is_player_on_zipline: bool = false
var current_position_on_line: float = 0.0 # 0.0 = start, 1.0 = end
var zipline_direction: int = 1 # 1 = start to end, -1 = end to start
var zipline_length: float = 0.0
var zipline_angle: float = 0.0
var vine_sprites: Array[Sprite2D] = []

signal player_grabbed_zipline(player: CharacterBody2D)
signal player_released_zipline(player: CharacterBody2D)

func _ready():
	# Create vine container if it doesn't exist
	if not has_node("VineContainer"):
		vine_container = Node2D.new()
		vine_container.name = "VineContainer"
		add_child(vine_container)
		# Move vine container behind markers by adjusting z_index
		vine_container.z_index = -1
	else:
		vine_container = $VineContainer
		vine_container.z_index = -1
	
	setup_zipline()
	setup_areas()
	
	# Connect marker position changes if in editor
	if Engine.is_editor_hint():
		setup_editor_connections()

func _set_vine_texture(value: Texture2D):
	vine_texture = value
	update_vine_sprites()

func _set_start_point(value: Vector2):
	start_point = value
	if has_node("StartMarker"):
		$StartMarker.position = start_point
	update_zipline_visual()

func _set_end_point(value: Vector2):
	end_point = value
	if has_node("EndMarker"):
		$EndMarker.position = end_point
	update_zipline_visual()

func setup_editor_connections():
	# Update points when markers are moved in editor
	if start_marker:
		# Connect to the marker's position change
		start_marker.position_changed = _on_start_marker_moved
	if end_marker:
		end_marker.position_changed = _on_end_marker_moved

func _on_start_marker_moved():
	start_point = start_marker.position
	update_zipline_visual()

func _on_end_marker_moved():
	end_point = end_marker.position
	update_zipline_visual()

func setup_zipline():
	# Set initial marker positions
	if start_marker:
		start_marker.position = start_point
	if end_marker:
		end_marker.position = end_point
	
	update_zipline_visual()

func update_zipline_visual():
	# Calculate zipline properties
	zipline_length = start_point.distance_to(end_point)
	if zipline_length > 0:
		zipline_angle = start_point.angle_to_point(end_point)
	
	# Set up the visual line (keep as backup/debug)
	if line:
		line.clear_points()
		line.add_point(start_point)
		line.add_point(end_point)
		line.width = 3.0
		line.default_color = Color.SADDLE_BROWN
		line.visible = false # Hide the line since we're using vine sprites
	
	# Update vine sprites
	update_vine_sprites()

func update_vine_sprites():
	if not vine_container:
		return
	
	# Clear existing vine sprites
	for sprite in vine_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	vine_sprites.clear()
	
	# If no texture or invalid zipline, return
	if not vine_texture or zipline_length <= 0:
		return
	
	# Calculate how many vine segments we need
	var segments_needed = max(1, int(zipline_length * vine_segments_per_unit))
	
	# Create vine sprites along the zipline
	for i in range(segments_needed):
		var sprite = Sprite2D.new()
		sprite.texture = vine_texture
		
		# Set up the sprite region for 3x7 sprite (assuming it's part of a larger texture)
		# You may need to adjust these values based on your actual texture layout
		if vine_texture.get_width() >= vine_segment_size.x and vine_texture.get_height() >= vine_segment_size.y:
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0, 0, vine_segment_size.x, vine_segment_size.y)
		
		# Position the sprite along the zipline
		var t = float(i) / float(segments_needed - 1) if segments_needed > 1 else 0.0
		sprite.position = start_point.lerp(end_point, t)
		
		# Rotate sprite to match zipline angle
		sprite.rotation = zipline_angle
		
		# Keep sprites perfectly aligned (no random variation for straight line)
		
		vine_container.add_child(sprite)
		vine_sprites.append(sprite)
		
		# Set owner for editor
		if Engine.is_editor_hint():
			sprite.owner = get_tree().edited_scene_root

func setup_areas():
	# The areas are now children of the marker nodes, so they move automatically
	if start_area and start_collision:
		var shape = CircleShape2D.new()
		shape.radius = 30.0
		start_collision.shape = shape
		start_area.body_entered.connect(_on_start_area_entered)
		start_area.body_exited.connect(_on_start_area_exited)
	
	if end_area and end_collision:
		var shape = CircleShape2D.new()
		shape.radius = 30.0
		end_collision.shape = shape
		end_area.body_entered.connect(_on_end_area_entered)
		end_area.body_exited.connect(_on_end_area_exited)

# Override _draw for editor visualization
func _draw():
	if Engine.is_editor_hint():
		# Draw the zipline as a guide line
		draw_line(start_point, end_point, Color.SADDLE_BROWN * Color(1, 1, 1, 0.3), 1.0)
		
		# Draw start point
		draw_circle(start_point, 8, Color.GREEN)
		
		# Draw end point  
		draw_circle(end_point, 8, Color.RED)
		
		# Draw grab areas
		draw_arc(start_point, 30, 0, TAU, 32, Color.GREEN * Color(1, 1, 1, 0.3), 2.0)
		draw_arc(end_point, 30, 0, TAU, 32, Color.RED * Color(1, 1, 1, 0.3), 2.0)

func _on_start_area_entered(body):
	if body.has_method("grab_zipline") and not is_player_on_zipline:
		player = body
		body.zipline_in_range = self
		body.zipline_grab_position = 0.0
		
		# Auto-grab if enabled and player isn't on a vine
		if auto_grab and not body.is_on_zipline:
			var is_on_vine = body.vine_component && body.vine_component.is_swinging
			if not is_on_vine:
				body.grab_zipline()

func _on_start_area_exited(body):
	if body == player and not is_player_on_zipline:
		body.zipline_in_range = null
		player = null

func _on_end_area_entered(body):
	if body.has_method("grab_zipline") and not is_player_on_zipline and can_reverse:
		player = body
		body.zipline_in_range = self
		body.zipline_grab_position = 1.0
		
		# Auto-grab if enabled and player isn't on a vine
		if auto_grab and not body.is_on_zipline:
			var is_on_vine = body.vine_component && body.vine_component.is_swinging
			if not is_on_vine:
				body.grab_zipline()

func _on_end_area_exited(body):
	if body == player and not is_player_on_zipline:
		body.zipline_in_range = null
		player = null

func grab_player(player_body: CharacterBody2D, grab_position: float):
	if is_player_on_zipline:
		return false
	
	player = player_body
	is_player_on_zipline = true
	current_position_on_line = grab_position
	
	# Determine direction based on grab position
	zipline_direction = 1 if grab_position < 0.5 else -1
	
	print("Player grabbed zipline at position: ", grab_position, " moving direction: ", zipline_direction)
	player_grabbed_zipline.emit(player)
	return true

func release_player():
	if not is_player_on_zipline or not player:
		return
	
	print("Releasing player from zipline")
	is_player_on_zipline = false
	var released_player = player
	player_released_zipline.emit(player)
	player.zipline_in_range = null
	player = null
	
	# Clear the player's zipline state
	if released_player:
		released_player.is_on_zipline = false
		released_player.current_zipline = null

func update_player_position(delta: float):
	if not is_player_on_zipline or not player:
		return
	
	# Ensure zipline length is valid
	if zipline_length <= 0:
		update_zipline_visual()
		if zipline_length <= 0:
			return
	
	# Move along the zipline
	var speed_normalized = zipline_speed / zipline_length
	var movement_amount = zipline_direction * speed_normalized * delta
	current_position_on_line += movement_amount
	
	# Check for end conditions and clamp position
	var reached_end = false
	if zipline_direction == 1 and current_position_on_line >= 1.0:
		current_position_on_line = 1.0
		reached_end = true
		print("Reached end of zipline (moving toward end_point)")
	elif zipline_direction == -1 and current_position_on_line <= 0.0:
		current_position_on_line = 0.0
		reached_end = true
		print("Reached start of zipline (moving toward start_point)")
	
	# Calculate and set player position
	var target_position = global_position + start_point.lerp(end_point, current_position_on_line)
	player.global_position = target_position
	
	# Set player velocity for physics
	var movement_vector = Vector2.ZERO
	if not reached_end:
		movement_vector = (end_point - start_point).normalized() * zipline_direction * zipline_speed
	player.velocity = movement_vector
	
	# Release player if they reached the end
	if reached_end and auto_release_at_end:
		# Use call_deferred to avoid issues with physics processing
		call_deferred("release_player")

func get_zipline_progress() -> float:
	return current_position_on_line

func get_zipline_direction_vector() -> Vector2:
	if zipline_length <= 0:
		return Vector2.ZERO
	return (end_point - start_point).normalized() * zipline_direction

func _process(delta):
	if is_player_on_zipline:
		update_player_position(delta)
	
	# Update visual in editor when points change
	if Engine.is_editor_hint():
		if start_marker and start_marker.position != start_point:
			start_point = start_marker.position
			update_zipline_visual()
			queue_redraw()
		if end_marker and end_marker.position != end_point:
			end_point = end_marker.position
			update_zipline_visual()
			queue_redraw()

# Vine.gd - Attach this to a Sprite2D node
extends Sprite2D
class_name Vine

@export var vine_length: float = 200.0
@export var swing_force: float = 500.0
@export var grab_range: float = 30.0
@export var debug_enabled: bool = true

# Detection area at the bottom of the vine
var detection_area: Area2D
var grab_indicator: Sprite2D
var debug_label: Label
var player: CharacterBody2D = null
var is_player_grabbing: bool = false
var vine_anchor: Vector2
var vine_bottom_position: Vector2
var player_in_grab_area: bool = false

func _ready():
	vine_anchor = global_position
	vine_bottom_position = vine_anchor + Vector2(0, vine_length)
	
	create_detection_area()
	create_grab_indicator()
	if debug_enabled:
		create_debug_label()
	
	# Set a default texture if none is assigned
	if not texture:
		var image = Image.create(32, int(vine_length), false, Image.FORMAT_RGBA8)
		image.fill(Color.BROWN)
		texture = ImageTexture.create_from_image(image)

func create_detection_area():
	# Create detection area at the bottom of the vine
	detection_area = Area2D.new()
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = grab_range
	collision_shape.shape = shape
	
	# Position the detection area at the bottom of the vine
	detection_area.position = Vector2(0, vine_length)
	
	# Set up Area2D properties
	detection_area.monitoring = true
	detection_area.monitorable = false
	
	# Set collision mask to layer 2 (where the player is)
	detection_area.collision_mask = 2  # This is layer 2 (binary: 10)
	detection_area.collision_layer = 0  # Don't put the vine on any collision layer
	
	detection_area.add_child(collision_shape)
	add_child(detection_area)
	
	# Connect signals
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

func create_grab_indicator():
	grab_indicator = Sprite2D.new()
	add_child(grab_indicator)
	
	# Create a circular indicator texture
	var image = Image.create(int(grab_range * 2), int(grab_range * 2), false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 1.0, 0.0, 0.5))  # Semi-transparent green circle
	grab_indicator.texture = ImageTexture.create_from_image(image)
	
	# Position at the bottom of the vine
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
	if debug_enabled and debug_label:
		update_debug_info()
	queue_redraw()  # For drawing the vine rope

func update_debug_info():
	if not debug_label:
		return
	
	var debug_text = ""
	debug_text += "In Grab Area: " + str(player_in_grab_area) + "\n"
	debug_text += "Is Grabbing: " + str(is_player_grabbing) + "\n"
	
	if player:
		var distance = vine_anchor.distance_to(player.global_position)
		debug_text += "Distance: " + str(int(distance)) + "\n"
		debug_text += "Player Pos: " + str(Vector2i(player.global_position))
	else:
		debug_text += "No Player\n"
	
	debug_text += "Vine Bottom: " + str(Vector2i(vine_bottom_position))
	
	debug_label.text = debug_text

func _draw():
	# Draw the vine rope
	if is_player_grabbing and player:
		var rope_end = player.global_position - global_position
		draw_line(Vector2.ZERO, rope_end, Color.BROWN, 4.0)
	else:
		# Draw vine as a hanging rope when not grabbed
		draw_line(Vector2.ZERO, Vector2(0, vine_length), Color.BROWN, 4.0)
	
	# Draw debug information
	if debug_enabled:
		# Draw vine anchor point
		draw_circle(Vector2.ZERO, 8, Color.RED)
		
		# Draw vine bottom point
		draw_circle(Vector2(0, vine_length), 6, Color.BLUE)
		
		# Draw grab range circle
		var grab_color = Color.GREEN
		grab_color.a = 0.3
		draw_circle(Vector2(0, vine_length), grab_range, grab_color)
		
		# Draw swing arc
		var arc_color = Color.YELLOW
		arc_color.a = 0.2
		draw_arc(Vector2.ZERO, vine_length, 0, TAU, 64, arc_color, 2.0)
		
		# Highlight when player is in grab area
		if player_in_grab_area:
			draw_circle(Vector2(0, vine_length), grab_range + 5, Color.CYAN)

func _on_body_entered(body):
	print("Body entered vine grab area: ", body.name)
	
	if body.has_method("grab_vine"):
		player = body  # Store reference to the player
		player_in_grab_area = true
		
		# Notify the player's VineComponent about nearby vine
		if body.has_node("VineComponent"):
			body.get_node("VineComponent").set_nearby_vine(self)
		
		# Show grab indicator when player is in range
		if grab_indicator:
			grab_indicator.visible = true
		
		print("Player is now in grab area of vine")

func _on_body_exited(body):
	print("Body exited vine grab area: ", body.name)
	
	if body.has_method("grab_vine"):
		if player == body:
			# Notify the player's VineComponent that vine is no longer nearby
			if body.has_node("VineComponent"):
				body.get_node("VineComponent").clear_nearby_vine(self)
			player = null  # Clear player reference when they leave
		player_in_grab_area = false
		
		# Hide grab indicator when player leaves range
		if grab_indicator:
			grab_indicator.visible = false
		
		print("Player left grab area of vine")

func attach_player(p: CharacterBody2D):
	player = p
	is_player_grabbing = true
	print("Player attached to vine. Vine anchor: ", vine_anchor, " Player pos: ", player.global_position)
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

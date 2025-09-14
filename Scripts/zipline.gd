extends Node2D
class_name Zipline

@export var start_point: Vector2
@export var end_point: Vector2
@export var zipline_speed: float = 400.0
@export var can_reverse: bool = true
@export var auto_release_at_end: bool = true

@onready var line: Line2D = $Line2D
@onready var start_area: Area2D = $StartArea
@onready var end_area: Area2D = $EndArea
@onready var start_collision: CollisionShape2D = $StartArea/CollisionShape2D
@onready var end_collision: CollisionShape2D = $EndArea/CollisionShape2D

var player: CharacterBody2D = null
var is_player_on_zipline: bool = false
var current_position_on_line: float = 0.0 # 0.0 = start, 1.0 = end
var zipline_direction: int = 1 # 1 = start to end, -1 = end to start
var zipline_length: float = 0.0
var zipline_angle: float = 0.0

signal player_grabbed_zipline(player: CharacterBody2D)
signal player_released_zipline(player: CharacterBody2D)

func _ready():
	setup_zipline()
	setup_areas()

func setup_zipline():
	# Calculate zipline properties
	zipline_length = start_point.distance_to(end_point)
	zipline_angle = start_point.angle_to_point(end_point)
	
	# Set up the visual line
	if line:
		line.clear_points()
		line.add_point(start_point)
		line.add_point(end_point)
		line.width = 3.0
		line.default_color = Color.SADDLE_BROWN

func setup_areas():
	# Position grab areas at start and end points
	if start_area and start_collision:
		start_area.global_position = global_position + start_point
		var shape = CircleShape2D.new()
		shape.radius = 30.0
		start_collision.shape = shape
		start_area.body_entered.connect(_on_start_area_entered)
		start_area.body_exited.connect(_on_start_area_exited)
	
	if end_area and end_collision:
		end_area.global_position = global_position + end_point
		var shape = CircleShape2D.new()
		shape.radius = 30.0
		end_collision.shape = shape
		end_area.body_entered.connect(_on_end_area_entered)
		end_area.body_exited.connect(_on_end_area_exited)

func _on_start_area_entered(body):
	if body.has_method("grab_zipline") and not is_player_on_zipline:
		player = body
		body.zipline_in_range = self
		body.zipline_grab_position = 0.0

func _on_start_area_exited(body):
	if body == player and not is_player_on_zipline:
		body.zipline_in_range = null
		player = null

func _on_end_area_entered(body):
	if body.has_method("grab_zipline") and not is_player_on_zipline and can_reverse:
		player = body
		body.zipline_in_range = self
		body.zipline_grab_position = 1.0

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
	
	player_grabbed_zipline.emit(player)
	return true

func release_player():
	if not is_player_on_zipline or not player:
		return
	
	is_player_on_zipline = false
	player_released_zipline.emit(player)
	player.zipline_in_range = null
	player = null

func update_player_position(delta: float):
	if not is_player_on_zipline or not player:
		return
	
	# Move along the zipline
	var speed_normalized = zipline_speed / zipline_length
	current_position_on_line += zipline_direction * speed_normalized * delta
	
	# Check for end of zipline
	if zipline_direction == 1 and current_position_on_line >= 1.0:
		current_position_on_line = 1.0
		if auto_release_at_end:
			release_player()
			return
	elif zipline_direction == -1 and current_position_on_line <= 0.0:
		current_position_on_line = 0.0
		if auto_release_at_end:
			release_player()
			return
	
	# Calculate player position
	var target_position = global_position + start_point.lerp(end_point, current_position_on_line)
	player.global_position = target_position
	
	# Set player velocity for smooth movement
	var movement_vector = (end_point - start_point).normalized() * zipline_direction * zipline_speed
	player.velocity = movement_vector

func get_zipline_progress() -> float:
	return current_position_on_line

func get_zipline_direction_vector() -> Vector2:
	return (end_point - start_point).normalized() * zipline_direction

func _process(delta):
	if is_player_on_zipline:
		update_player_position(delta)

# Game.gd
extends Node

@onready var level_select_menu = $LevelSelectMenu
var current_level_scene = null

func _ready():
	level_select_menu.level_selected.connect(_on_level_selected)

func _on_level_selected(level_number):
	# Remove current level if exists
	if current_level_scene:
		current_level_scene.queue_free()
	
	# Disable the level select menu's camera
	if level_select_menu.has_node("Camera2D"):
		level_select_menu.get_node("Camera2D").enabled = false
	
	# Hide menu
	level_select_menu.visible = false
	
	# Load the selected level
	match level_number:
		1:
			current_level_scene = preload("res://Scenes/level_1_holder.tscn").instantiate()
			add_child(current_level_scene)
		
		# Add more levels as needed

func return_to_menu():
	if current_level_scene:
		current_level_scene.queue_free()
		current_level_scene = null
	
	# Re-enable the level select menu's camera
	if level_select_menu.has_node("Camera2D"):
		level_select_menu.get_node("Camera2D").enabled = true
	
	level_select_menu.visible = true

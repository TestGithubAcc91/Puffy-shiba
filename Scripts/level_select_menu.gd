# LevelSelectMenu.gd (attach this to your LevelSelectMenu node)
extends Node2D  # or whatever your LevelSelectMenu actually is

signal level_selected(level_number)

func _ready():
	# Connect your button's pressed signal to a function
	# Replace "Level1Button" with your actual button's name
	$Level1Button.pressed.connect(_on_level_1_button_pressed)

func _on_level_1_button_pressed():
	level_selected.emit(1)

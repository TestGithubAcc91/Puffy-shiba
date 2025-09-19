
# LevelSelectMenu.gd (attach this to your LevelSelectMenu node)
extends Node2D  # or whatever your LevelSelectMenu actually is

signal level_selected(level_number)

func _ready():
	# Connect your TextureButton's pressed signal to a function
	# Replace "Level1Button" with your actual TextureButton's name
	$Level1Button.pressed.connect(_on_level_1_button_pressed)
	
	# You can also connect multiple level buttons here:
	# $Level2Button.pressed.connect(_on_level_2_button_pressed)
	# $Level3Button.pressed.connect(_on_level_3_button_pressed)

func _on_level_1_button_pressed():
	level_selected.emit(1)

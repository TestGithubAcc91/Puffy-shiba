# LevelSelectMenu.gd (attach this to your LevelSelectMenu node)
extends Node2D  # or whatever your LevelSelectMenu actually is

signal level_selected(level_number)

@onready var forest_background = $ForestBackground
var tween: Tween

func _ready():
	# Make sure ForestBackground starts invisible
	forest_background.modulate.a = 0.0
	forest_background.visible = true  # Make it visible but transparent
	
	# Connect your TextureButton's pressed signal to a function
	# Replace "Level1Button" with your actual TextureButton's name
	$Level1Button.pressed.connect(_on_level_1_button_pressed)
	
	# Connect hover signals
	$Level1Button.mouse_entered.connect(_on_level_1_button_hover_start)
	$Level1Button.mouse_exited.connect(_on_level_1_button_hover_end)
	
	# You can also connect multiple level buttons here:
	# $Level2Button.pressed.connect(_on_level_2_button_pressed)
	# $Level3Button.pressed.connect(_on_level_3_button_pressed)

func _on_level_1_button_pressed():
	level_selected.emit(1)

func _on_level_1_button_hover_start():
	# Kill any existing tween
	if tween:
		tween.kill()
	
	# Create new tween to fade in
	tween = create_tween()
	tween.tween_property(forest_background, "modulate:a", 1.0, 0.3)

func _on_level_1_button_hover_end():
	# Kill any existing tween
	if tween:
		tween.kill()
	
	# Create new tween to fade out
	tween = create_tween()
	tween.tween_property(forest_background, "modulate:a", 0.0, 0.3)

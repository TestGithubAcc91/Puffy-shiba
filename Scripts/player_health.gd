extends Node
class_name Health

signal health_changed(new_health: int)
signal died
signal iframe_started
signal iframe_ended

@export var max_health: int = 100
@export var current_health: int = 100
@export var iframe_duration: float = 1.0
@export var flicker_interval: float = 0.1

var is_invulnerable: bool = false
var iframe_timer: Timer
var flicker_timer: Timer
var is_flickering: bool = false

# Reference to the animated sprite for flickering
var animated_sprite: AnimatedSprite2D

func _ready():
	current_health = max_health
	
	# Get reference to the animated sprite from parent
	var parent = get_parent()
	if parent.has_node("MainSprite"):
		animated_sprite = parent.get_node("MainSprite")
	
	# Create iframe timer
	iframe_timer = Timer.new()
	iframe_timer.wait_time = iframe_duration
	iframe_timer.one_shot = true
	iframe_timer.timeout.connect(_on_iframe_timeout)
	add_child(iframe_timer)
	
	# Create flicker timer
	flicker_timer = Timer.new()
	flicker_timer.wait_time = flicker_interval
	flicker_timer.timeout.connect(_on_flicker_timeout)
	add_child(flicker_timer)

func take_damage(amount: int, ignore_iframes: bool = false):
	# Check if damage should be blocked by existing iframes (only when not ignoring them)
	if is_invulnerable and not ignore_iframes:
		print("Player is invulnerable, damage blocked!")
		return
	
	if ignore_iframes and is_invulnerable:
		print("Damage ignoring i-frames!")
	
	print("Taking damage: ", amount, " | Health before: ", current_health)
	current_health = max(0, current_health - amount)
	print("Health after damage: ", current_health)
	health_changed.emit(current_health)
	
	# ALWAYS grant invulnerability and start visual iframes after taking damage
	# This ensures the player gets iframes even when parrying unparryable attacks
	is_invulnerable = true
	iframe_timer.start()
	
	# Start flickering effect
	is_flickering = true
	flicker_timer.start()
	
	iframe_started.emit()
	print("I-frames activated for ", iframe_duration, " seconds")
	
	if current_health <= 0:
		print("Player died!")
		died.emit()

func _on_iframe_timeout():
	is_invulnerable = false
	is_flickering = false
	flicker_timer.stop()
	
	# Reset sprite transparency
	if animated_sprite:
		animated_sprite.modulate.a = 1.0
	
	iframe_ended.emit()  # Signal that iframes have ended
	print("I-frames ended, player can take damage again")

func _on_flicker_timeout():
	if is_flickering and animated_sprite:
		if animated_sprite.modulate.a > 0.5:
			animated_sprite.modulate.a = 0.3
		else:
			animated_sprite.modulate.a = 1.0
		
		flicker_timer.start()

func heal(amount: int):
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health)

func get_health_percentage() -> float:
	return float(current_health) / float(max_health)

func is_alive() -> bool:
	return current_health > 0

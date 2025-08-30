extends Node
class_name Health

signal health_changed(new_health: int)
signal died
signal iframe_started
signal iframe_ended

@export var max_health: int = 100
@export var current_health: int = 100
@export var iframe_duration: float = 1.0

var is_invulnerable: bool = false
var iframe_timer: Timer

func _ready():
	current_health = max_health
	
	# Create iframe timer
	iframe_timer = Timer.new()
	iframe_timer.wait_time = iframe_duration
	iframe_timer.one_shot = true
	iframe_timer.timeout.connect(_on_iframe_timeout)
	add_child(iframe_timer)

func take_damage(amount: int, ignore_iframes: bool = false):
	if is_invulnerable and not ignore_iframes:
		print("Player is invulnerable, damage blocked!")
		return
	
	if ignore_iframes and is_invulnerable:
		print("Damage ignoring i-frames!")
	
	print("Taking damage: ", amount, " | Health before: ", current_health)
	current_health = max(0, current_health - amount)
	print("Health after damage: ", current_health)
	health_changed.emit(current_health)
	
	# Start invulnerability frames (unless this damage source prevents i-frames)
	if not ignore_iframes:
		is_invulnerable = true
		iframe_timer.start()
		iframe_started.emit()  # Signal that iframes have started
		print("I-frames activated for ", iframe_duration, " seconds")
	else:
		print("No i-frames granted (ignored by damage source)")
	
	if current_health <= 0:
		print("Player died!")
		died.emit()

func _on_iframe_timeout():
	is_invulnerable = false
	iframe_ended.emit()  # Signal that iframes have ended
	print("I-frames ended, player can take damage again")

func heal(amount: int):
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health)

func get_health_percentage() -> float:
	return float(current_health) / float(max_health)

func is_alive() -> bool:
	return current_health > 0

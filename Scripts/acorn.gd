extends Node2D

@export var speed: float = 300.0

	
func _process(delta):
	# Move the acorn horizontally
	position.x += speed * delta

	# Optional: Remove the acorn after a certain time to prevent memory buildup
	# You can adjust this time based on your level size
	var timer = Timer.new()
	timer.wait_time = 5.0
	timer.one_shot = true
	timer.timeout.connect(_on_timeout)
	add_child(timer)
	timer.start()

func _on_timeout():
	queue_free()

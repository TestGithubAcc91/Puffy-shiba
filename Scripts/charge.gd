extends Area2D

@export var vfx_scene: PackedScene  # Add this line to create an inspector field for VFX scene
@onready var game_manager: Node = %GameManager
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _on_body_entered(body: Node2D):
	game_manager.add_point()
	animation_player.play("pickup")
	if body.has_method("add_parry_stack"):
		body.add_parry_stack()
	
	# Spawn VFX if a scene is assigned
	if vfx_scene:
		var vfx_instance = vfx_scene.instantiate()
		get_parent().add_child(vfx_instance)
		vfx_instance.global_position = global_position
		
		# Try to find an AnimationPlayer first
		var vfx_animation_player = vfx_instance.get_node_or_null("AnimationPlayer")
		if vfx_animation_player:
			await vfx_animation_player.animation_finished
			vfx_instance.queue_free()
		else:
			# If no AnimationPlayer, try AnimatedSprite2D
			var vfx_animated_sprite = vfx_instance.get_node_or_null("AnimatedSprite2D")
			if vfx_animated_sprite:
				await vfx_animated_sprite.animation_finished
				vfx_instance.queue_free()
			else:
				# Fallback: free after 1 second
				await get_tree().create_timer(1.0).timeout
				vfx_instance.queue_free()

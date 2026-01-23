extends Node
## Auto-cleanup script for one-shot particle effects.
##
## Automatically frees the particle effect node after its lifetime expires.
## Attach this script to any one-shot Particles2D node.

## Extra time after lifetime before cleanup (allows particles to fade).
@export var cleanup_delay: float = 0.5


func _ready() -> void:
	# Wait for particles to finish and then cleanup
	var particles := self as Particles2D
	if particles == null:
		push_error("This script must be attached to a Particles2D node")
		return

	var total_wait := particles.lifetime + cleanup_delay
	await get_tree().create_timer(total_wait).timeout
	particles.queue_free()

extends GPUParticles2D
## Auto-cleanup script for one-shot particle effects.
##
## Automatically frees the particle effect node after its lifetime expires.
## Attach this script to any one-shot GPUParticles2D node.

## Extra time after lifetime before cleanup (allows particles to fade).
@export var cleanup_delay: float = 0.5


func _ready() -> void:
	# Wait for particles to finish and then cleanup
	var total_wait := lifetime + cleanup_delay
	# Check if we're still valid (scene might change during wait)
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(total_wait).timeout
	# Check if node is still valid after await (scene might have changed)
	if is_instance_valid(self) and is_inside_tree():
		queue_free()

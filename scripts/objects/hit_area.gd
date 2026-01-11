extends Area2D
## Hit detection area that forwards on_hit calls to its parent.
##
## This is used as a child of CharacterBody2D-based enemies to allow
## Area2D-based projectiles (bullets) to detect hits on the enemy.


## Called when hit by a projectile.
## Forwards the call to the parent if it has an on_hit method.
func on_hit() -> void:
	var parent := get_parent()
	if parent and parent.has_method("on_hit"):
		parent.on_hit()

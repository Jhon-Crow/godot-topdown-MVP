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


## Called when hit by a projectile with extended hit information.
## Forwards the call to the parent with hit direction and caliber data.
## @param hit_direction: Direction the bullet was traveling.
## @param caliber_data: Caliber resource for effect scaling.
func on_hit_with_info(hit_direction: Vector2, caliber_data: Resource) -> void:
	var parent := get_parent()
	if parent and parent.has_method("on_hit_with_info"):
		parent.on_hit_with_info(hit_direction, caliber_data)
	elif parent and parent.has_method("on_hit"):
		# Fallback to basic on_hit if extended method not available
		parent.on_hit()
